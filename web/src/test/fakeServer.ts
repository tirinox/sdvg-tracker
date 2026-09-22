// In-memory implementation of the /api/sync protocol (shared/README.md), used as `fetch`.
import { mergeFields } from '../core/merge'
import type { Change } from '../core/types'

interface StoredRow extends Change {
  seq: number
}

export class FakeServer {
  readonly serverId = crypto.randomUUID()
  token = 'test-token'
  down = false
  requests = 0
  /** Changes for which this returns true are rejected with 422. */
  reject: (change: Change) => boolean = () => false
  /** Runs after the request is parsed, before it is applied (to interleave local writes). */
  beforeApply: () => Promise<void> = async () => {}
  private records = new Map<string, StoredRow>()
  private seq = 0

  fetch: typeof fetch = async (_url, init) => {
    this.requests += 1
    if (this.down) throw new TypeError('Failed to fetch')
    if (init?.headers && (init.headers as Record<string, string>).Authorization !== `Bearer ${this.token}`) {
      return json(401, { detail: 'Invalid or missing token' })
    }
    const req = JSON.parse(String(init?.body)) as { cursor: number; changes: Change[]; limit: number }
    const bad = req.changes.findIndex((c) => this.reject(c))
    if (bad >= 0) return json(422, { detail: { message: `changes[${bad}]: rejected`, change_index: bad } })
    await this.beforeApply()

    for (const c of req.changes) {
      const key = `${c.entity}|${c.id}`
      const row = this.records.get(key) ?? { entity: c.entity, id: c.id, fields: {}, clocks: {}, seq: 0 }
      if (mergeFields(row.fields, row.clocks, c.fields, c.clocks)) {
        row.seq = ++this.seq
        this.records.set(key, row)
      }
    }
    const rows = [...this.records.values()]
      .filter((r) => r.seq > req.cursor)
      .sort((a, b) => a.seq - b.seq)
    const page = rows.slice(0, req.limit)
    return json(200, {
      server_id: this.serverId,
      cursor: page.at(-1)?.seq ?? req.cursor,
      changes: page.map(({ seq: _seq, ...r }) => structuredClone(r)),
      has_more: rows.length > req.limit,
    })
  }

  row(entity: string, id: string): { fields: Record<string, unknown> } | undefined {
    return this.records.get(`${entity}|${id}`)
  }

  get size(): number {
    return this.records.size
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
