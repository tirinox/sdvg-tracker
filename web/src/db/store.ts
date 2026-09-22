import { Clock, randomNodeId } from '../core/hlc'
import { mergeFields } from '../core/merge'
import {
  DEFAULT_SETTINGS,
  ENTITIES,
  SETTINGS_ID,
  type Change,
  type EntityFields,
  type EntityName,
  type Row,
  type Settings,
} from '../core/types'
import { AppDatabase } from './database'

export interface LocalChange<E extends EntityName = EntityName> {
  entity: E
  id: string
  fields: Partial<EntityFields[E]>
}

type Listener = () => void

/**
 * The local source of truth. Local writes get HLC clocks and go to the outbox in the same
 * transaction; remote changes are merged without touching the outbox.
 */
export class Store {
  readonly db: AppDatabase
  private readonly clock: Clock
  private listeners = new Set<Listener>()

  private constructor(db: AppDatabase, clock: Clock) {
    this.db = db
    this.clock = clock
  }

  static async open(name = 'sdvg-tracker', nowMs: () => number = Date.now): Promise<Store> {
    const db = new AppDatabase(name)
    await db.open()
    let nodeId = (await db.meta.get('node_id'))?.value as string | undefined
    if (!nodeId) {
      nodeId = randomNodeId()
      await db.meta.put({ key: 'node_id', value: nodeId })
    }
    const last = ((await db.meta.get('hlc'))?.value as string | undefined) ?? null
    return new Store(db, Clock.resume(nodeId, last, nowMs))
  }

  get nodeId(): string {
    return this.clock.nodeId
  }

  /** Called after every committed local write (the sync scheduler debounces on this). */
  onLocalWrite(listener: Listener): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  async write(changes: LocalChange[]): Promise<void> {
    if (changes.length === 0) return
    const tables = [...new Set(changes.map((c) => c.entity))].map((e) => this.db.table(e))
    await this.db.transaction('rw', [...tables, this.db.outbox, this.db.meta], async () => {
      let last = ''
      for (const c of changes) {
        last = this.clock.now()
        const clocks = Object.fromEntries(Object.keys(c.fields).map((k) => [k, last]))
        const change = { entity: c.entity, id: c.id, fields: c.fields, clocks } as Change
        await this.mergeRow(change)
        await this.db.outbox.add(structuredClone(change))
      }
      await this.db.meta.put({ key: 'hlc', value: last })
    })
    for (const listener of this.listeners) listener()
  }

  /** Merge changes pulled from the server. Must run inside a transaction covering all tables. */
  async applyRemote(changes: Change[]): Promise<void> {
    let last: string | null = null
    for (const change of changes) {
      const newest = Object.values(change.clocks).sort().at(-1) as string
      last = this.clock.receive(newest)
      await this.mergeRow(change)
    }
    if (last) await this.db.meta.put({ key: 'hlc', value: last })
  }

  async get<E extends EntityName>(entity: E, id: string): Promise<EntityFields[E] | undefined> {
    const row = await this.db.entityTable(entity).get(id)
    return row?.fields as EntityFields[E] | undefined
  }

  async rows<E extends EntityName>(entity: E): Promise<Row<E>[]> {
    return this.db.entityTable(entity).toArray()
  }

  async settings(): Promise<Settings> {
    const stored = await this.get('settings', SETTINGS_ID)
    return { ...DEFAULT_SETTINGS, ...stored }
  }

  async getMeta<T>(key: string): Promise<T | undefined> {
    return (await this.db.meta.get(key))?.value as T | undefined
  }

  async setMeta(key: string, value: unknown): Promise<void> {
    await this.db.meta.put({ key, value })
  }

  entityTables() {
    return ENTITIES.map((e) => this.db.table(e))
  }

  /** Every table a sync transaction touches. */
  syncTables() {
    return [...this.entityTables(), this.db.outbox, this.db.rejected, this.db.meta]
  }

  close(): void {
    this.db.close()
  }

  private async mergeRow(change: Change): Promise<void> {
    const table = this.db.table(change.entity)
    // Copy: Dexie may hand out the same object it caches for live queries, and mutating it in
    // place would make the change invisible to them.
    const stored: Row | undefined = await table.get(change.id)
    const row: Row = stored ? structuredClone(stored) : { id: change.id, fields: {}, clocks: {} }
    if (mergeFields(row.fields, row.clocks, change.fields, change.clocks)) await table.put(row)
  }
}
