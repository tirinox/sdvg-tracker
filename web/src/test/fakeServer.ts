// In-memory implementation of the /api/sync protocol (shared/README.md), used as `fetch`.
import { mergeFields } from '../core/merge'
import type { Change } from '../core/types'

interface StoredRow extends Change {
  seq: number
}

export class FakeServer {
  serverId = crypto.randomUUID()
  epoch = crypto.randomUUID()
  token = 'test-token'
  down = false
  /** Sync requests (info probes are not counted). */
  requests = 0
  /** Changes for which this returns true are rejected with 422. */
  reject: (change: Change) => boolean = () => false
  /** Runs after the request is parsed, before it is applied (to interleave local writes). */
  beforeApply: () => Promise<void> = async () => {}
  private records = new Map<string, StoredRow>()
  private seq = 0

  fetch: typeof fetch = async (url, init) => {
    const probe = String(url).endsWith('/api/sync/info')
    if (!probe) this.requests += 1
    if (this.down) throw new TypeError('Failed to fetch')
    if (init?.headers && (init.headers as Record<string, string>).Authorization !== `Bearer ${this.token}`) {
      return json(401, { detail: 'Invalid or missing token' })
    }
    if (probe) return json(200, this.info())

    const req = JSON.parse(String(init?.body)) as {
      cursor: number
      changes: Change[]
      limit: number
      server_id?: string
      epoch?: string
    }
    if (req.server_id !== undefined && req.server_id !== this.serverId) {
      return json(409, { detail: { error: 'server_changed', ...this.info() } })
    }
    const bad = req.changes.findIndex((c) => this.reject(c))
    if (bad >= 0) return json(422, { detail: { message: `changes[${bad}]: rejected`, change_index: bad } })
    await this.beforeApply()

    const rewind = (req.epoch !== undefined && req.epoch !== this.epoch) || req.cursor > this.seq
    const cursor = rewind ? 0 : req.cursor
    for (const c of req.changes) {
      const key = `${c.entity}|${c.id}`
      const row = this.records.get(key) ?? { entity: c.entity, id: c.id, fields: {}, clocks: {}, seq: 0 }
      if (mergeFields(row.fields, row.clocks, c.fields, c.clocks)) {
        row.seq = ++this.seq
        this.records.set(key, row)
      }
    }
    const rows = [...this.records.values()].filter((r) => r.seq > cursor).sort((a, b) => a.seq - b.seq)
    const page = rows.slice(0, req.limit)
    return json(200, {
      server_id: this.serverId,
      epoch: this.epoch,
      cursor: page.at(-1)?.seq ?? cursor,
      changes: page.map(({ seq: _seq, ...r }) => structuredClone(r)),
      has_more: rows.length > req.limit,
      rewind,
    })
  }

  /** make reset-db: empty, under a new server_id. */
  reset(): void {
    this.records.clear()
    this.seq = 0
    this.serverId = crypto.randomUUID()
    this.epoch = crypto.randomUUID()
  }

  /** make backup */
  backup(): { records: Map<string, StoredRow>; seq: number } {
    return structuredClone({ records: this.records, seq: this.seq })
  }

  /** make restore: the backup's rows and server_id, under a new epoch. */
  restore(backup: { records: Map<string, StoredRow>; seq: number }): void {
    this.records = structuredClone(backup.records)
    this.seq = backup.seq
    this.epoch = crypto.randomUUID()
  }

  row(entity: string, id: string): { fields: Record<string, unknown> } | undefined {
    return this.records.get(`${entity}|${id}`)
  }

  get size(): number {
    return this.records.size
  }

  private info() {
    const counts: Record<string, number> = {}
    for (const r of this.records.values()) counts[r.entity] = (counts[r.entity] ?? 0) + 1
    return { server_id: this.serverId, epoch: this.epoch, counts }
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
