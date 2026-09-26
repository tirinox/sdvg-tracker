import type { Change } from '../core/types'
import type { OutboxEntry } from '../db/database'
import type { Store } from '../db/store'

export interface SyncConfig {
  /** '' = same origin (the web app is served next to /api). */
  baseUrl: string
  token: string
}

export type SyncState =
  | 'idle'
  | 'syncing'
  | 'offline'
  | 'unauthorized'
  | 'unconfigured'
  | 'server_changed'
  | 'error'

export interface Counts {
  task: number
  routine: number
}

/** The server holds data this device has not synced with; sync waits for the user's choice. */
export interface ServerChange {
  /** 'changed': the server's data set was replaced; 'first': first connection, both sides have data. */
  kind: 'changed' | 'first'
  serverId: string
  server: Counts
  local: Counts
}

export interface SyncStatus {
  state: SyncState
  lastSyncAt: string | null
  error: string | null
  /** Set while state is 'server_changed'. */
  serverChange: ServerChange | null
}

interface SyncResponse {
  server_id: string
  epoch: string
  cursor: number
  changes: Change[]
  has_more: boolean
  rewind: boolean
}

/** GET /api/sync/info, and the detail of a 409 server_changed. */
interface ServerInfo {
  server_id: string
  epoch: string
  counts: Partial<Record<string, number>>
}

export interface SyncClientOptions {
  fetchFn?: typeof fetch
  batchSize?: number
  timeoutMs?: number
}

const META_CURSOR = 'sync_cursor'
const META_SERVER_ID = 'sync_server_id'
const META_EPOCH = 'sync_epoch'
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
  status: SyncStatus = { state: 'idle', lastSyncAt: null, error: null, serverChange: null }
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

  private setStatus(state: SyncState, error: string | null = null, serverChange: ServerChange | null = null): void {
    const lastSyncAt = state === 'idle' ? new Date().toISOString() : this.status.lastSyncAt
    // A pending question stays up while the next sync checks again, so it does not flicker.
    if (state === 'syncing') serverChange = this.status.serverChange
    this.status = { state, lastSyncAt, error, serverChange }
    for (const listener of this.listeners) listener(this.status)
  }

  private async pause(kind: ServerChange['kind'], info: ServerInfo): Promise<void> {
    const server = { task: info.counts.task ?? 0, routine: info.counts.routine ?? 0 }
    const serverChange = { kind, serverId: info.server_id, server, local: await this.localCounts() }
    this.setStatus('server_changed', null, serverChange)
  }

  private async localCounts(): Promise<Counts> {
    return { task: await this.store.db.task.count(), routine: await this.store.db.routine.count() }
  }

  /** Answer to 'server_changed': drop this device's data and download the server's. */
  async takeServerData(): Promise<void> {
    const { db } = this.store
    await db.transaction('rw', this.store.syncTables(), async () => {
      for (const table of this.store.entityTables()) await table.clear()
      await db.outbox.clear()
      await db.rejected.clear()
      await db.meta.bulkDelete([META_CURSOR, META_SERVER_ID, META_EPOCH])
    })
    await this.sync()
  }

  /** Answer to 'server_changed': send every row of this device into the server's data set. */
  async mergeWithServer(): Promise<void> {
    const change = this.status.serverChange
    if (!change) return
    const { db } = this.store
    await db.transaction('rw', this.store.syncTables(), async () => {
      await this.enqueueAll()
      await this.store.setMeta(META_CURSOR, 0)
      await this.store.setMeta(META_SERVER_ID, change.serverId)
      await db.meta.delete(META_EPOCH)
    })
    await this.sync()
  }

  private request(config: SyncConfig, path: string, init: RequestInit = {}): Promise<Response> {
    return this.fetchFn(`${config.baseUrl}${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${config.token}` },
      signal: AbortSignal.timeout(this.timeoutMs),
    })
  }

  /**
   * Before the first sync, a device that already has tasks or routines looks at the server:
   * if that has data too, merging is the user's call. False = stop (status is set).
   */
  private async firstContact(config: SyncConfig): Promise<boolean> {
    const local = await this.localCounts()
    if (local.task + local.routine === 0) return true
    let resp: Response
    try {
      resp = await this.request(config, '/api/sync/info')
    } catch {
      this.setStatus('offline')
      return false
    }
    if (!resp.ok) {
      this.setStatus(resp.status === 401 ? 'unauthorized' : resp.status >= 500 ? 'offline' : 'error', `HTTP ${resp.status}`)
      return false
    }
    const info = (await resp.json()) as ServerInfo
    if ((info.counts.task ?? 0) + (info.counts.routine ?? 0) === 0) return true
    await this.pause('first', info)
    return false
  }

  private async run(): Promise<void> {
    const config = await loadSyncConfig(this.store)
    if (!config?.token) {
      this.setStatus('unconfigured')
      return
    }
    this.setStatus('syncing')
    const { db } = this.store
    if ((await this.store.getMeta(META_SERVER_ID)) === undefined && !(await this.firstContact(config))) return

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const batch = await db.outbox.orderBy('seq').limit(this.batchSize).toArray()
      const cursor = (await this.store.getMeta<number>(META_CURSOR)) ?? 0
      const serverId = await this.store.getMeta<string>(META_SERVER_ID)
      const epoch = await this.store.getMeta<string>(META_EPOCH)

      let resp: Response
      try {
        resp = await this.request(config, '/api/sync', {
          method: 'POST',
          body: JSON.stringify({
            cursor,
            changes: batch.map(toWire),
            limit: this.batchSize,
            ...(serverId && { server_id: serverId }),
            ...(epoch && { epoch }),
          }),
        })
      } catch {
        this.setStatus('offline')
        return
      }

      if (resp.status === 401) {
        this.setStatus('unauthorized')
        return
      }
      if (resp.status === 409) {
        // Another data set: nothing was applied, and nothing is sent until the user decides.
        await this.pause('changed', (await resp.json()).detail as ServerInfo)
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

      await db.transaction('rw', this.store.syncTables(), async () => {
        await db.outbox.bulkDelete(pushed)
        await this.store.applyRemote(body.changes)
        // Restored from a backup: it lacks whatever changed after the backup, so send it all.
        if (body.rewind) await this.enqueueAll()
        await this.store.setMeta(META_CURSOR, body.cursor)
        await this.store.setMeta(META_SERVER_ID, body.server_id)
        await this.store.setMeta(META_EPOCH, body.epoch)
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

  /** Replaces the outbox with every row we have, whole: they already hold every local change. */
  private async enqueueAll(): Promise<void> {
    const { db } = this.store
    await db.outbox.clear()
    for (const table of this.store.entityTables()) {
      const rows = await table.toArray()
      await db.outbox.bulkAdd(rows.map((r) => ({ entity: table.name, ...r })))
    }
  }
}

function toWire({ entity, id, fields, clocks }: OutboxEntry): Change {
  return { entity, id, fields, clocks }
}
