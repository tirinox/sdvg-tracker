import type { Change } from '../core/types'
import type { OutboxEntry } from '../db/database'
import type { Store } from '../db/store'

export interface SyncConfig {
  /** '' = same origin (the web app is served next to /api). */
  baseUrl: string
  token: string
}

export type SyncState = 'idle' | 'syncing' | 'offline' | 'unauthorized' | 'unconfigured' | 'error'

export interface SyncStatus {
  state: SyncState
  lastSyncAt: string | null
  error: string | null
}

interface SyncResponse {
  server_id: string
  cursor: number
  changes: Change[]
  has_more: boolean
}

export interface SyncClientOptions {
  fetchFn?: typeof fetch
  batchSize?: number
  timeoutMs?: number
}

const META_CURSOR = 'sync_cursor'
const META_SERVER_ID = 'sync_server_id'
const META_CONFIG = 'sync_config'
const MAX_ROUNDS = 1000

export async function loadSyncConfig(store: Store): Promise<SyncConfig | null> {
  return (await store.getMeta<SyncConfig>(META_CONFIG)) ?? null
}

export async function saveSyncConfig(store: Store, config: SyncConfig): Promise<void> {
  await store.setMeta(META_CONFIG, config)
}

/** Implements the /api/sync protocol from shared/README.md over the local Store. */
export class SyncClient {
  status: SyncStatus = { state: 'idle', lastSyncAt: null, error: null }
  private running: Promise<void> | null = null
  private again = false
  private listeners = new Set<(s: SyncStatus) => void>()
  private readonly store: Store
  private readonly fetchFn: typeof fetch
  private readonly batchSize: number
  private readonly timeoutMs: number

  constructor(store: Store, options: SyncClientOptions = {}) {
    this.store = store
    this.fetchFn = options.fetchFn ?? ((...args) => fetch(...args))
    this.batchSize = options.batchSize ?? 500
    this.timeoutMs = options.timeoutMs ?? 15_000
  }

  onStatus(listener: (s: SyncStatus) => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  /** Single-flight: a call during a running sync schedules exactly one more round. */
  sync(): Promise<void> {
    if (this.running) {
      this.again = true
      return this.running
    }
    this.running = (async () => {
      try {
        do {
          this.again = false
          await this.run()
        } while (this.again)
      } finally {
        this.running = null
      }
    })()
    return this.running
  }

  private setStatus(state: SyncState, error: string | null = null): void {
    const lastSyncAt = state === 'idle' ? new Date().toISOString() : this.status.lastSyncAt
    this.status = { state, lastSyncAt, error }
    for (const listener of this.listeners) listener(this.status)
  }

  private async run(): Promise<void> {
    const config = await loadSyncConfig(this.store)
    if (!config?.token) {
      this.setStatus('unconfigured')
      return
    }
    this.setStatus('syncing')
    const { db } = this.store

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const batch = await db.outbox.orderBy('seq').limit(this.batchSize).toArray()
      const cursor = (await this.store.getMeta<number>(META_CURSOR)) ?? 0
      const knownServer = (await this.store.getMeta<string>(META_SERVER_ID)) ?? null

      let resp: Response
      try {
        resp = await this.fetchFn(`${config.baseUrl}/api/sync`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${config.token}` },
          body: JSON.stringify({ cursor, changes: batch.map(toWire), limit: this.batchSize }),
          signal: AbortSignal.timeout(this.timeoutMs),
        })
      } catch {
        this.setStatus('offline')
        return
      }

      if (resp.status === 401) {
        this.setStatus('unauthorized')
        return
      }
      if (resp.status === 422) {
        const detail = (await resp.json().catch(() => null))?.detail
        const index = detail?.change_index
        const bad = typeof index === 'number' ? batch[index] : undefined
        if (!bad) {
          this.setStatus('error', 'Server rejected the request')
          return
        }
        await this.quarantine(bad, String(detail?.message ?? 'HTTP 422'))
        continue
      }
      if (!resp.ok) {
        this.setStatus(resp.status >= 500 ? 'offline' : 'error', `HTTP ${resp.status}`)
        return
      }

      const body = (await resp.json()) as SyncResponse
      const pushed = batch.map((e) => e.seq!)

      if (knownServer !== null && body.server_id !== knownServer) {
        await this.resetForNewServer(body.server_id, pushed)
        continue
      }

      await db.transaction('rw', this.store.syncTables(), async () => {
        await db.outbox.bulkDelete(pushed)
        await this.store.applyRemote(body.changes)
        await this.store.setMeta(META_CURSOR, body.cursor)
        await this.store.setMeta(META_SERVER_ID, body.server_id)
      })

      if (!body.has_more && (await db.outbox.count()) === 0) {
        this.setStatus('idle')
        return
      }
    }
    this.setStatus('error', 'Sync did not settle')
  }

  private async quarantine(entry: OutboxEntry, error: string): Promise<void> {
    const { db } = this.store
    await db.transaction('rw', db.outbox, db.rejected, async () => {
      await db.outbox.delete(entry.seq!)
      const { seq: _seq, ...change } = entry
      await db.rejected.add({ ...change, error, rejected_at: new Date().toISOString() })
    })
  }

  /** The server database was replaced: start over and hand it every row we have. */
  private async resetForNewServer(serverId: string, pushed: number[]): Promise<void> {
    const { db } = this.store
    await db.transaction('rw', this.store.syncTables(), async () => {
      await db.outbox.bulkDelete(pushed)
      for (const table of this.store.entityTables()) {
        const rows = await table.toArray()
        await db.outbox.bulkAdd(rows.map((r) => ({ entity: table.name, ...r })))
      }
      await this.store.setMeta(META_CURSOR, 0)
      await this.store.setMeta(META_SERVER_ID, serverId)
    })
  }
}

function toWire({ entity, id, fields, clocks }: OutboxEntry): Change {
  return { entity, id, fields, clocks }
}
