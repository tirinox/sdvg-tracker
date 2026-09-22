// Hybrid logical clock, see shared/README.md. Timestamps compare as plain strings.

export const MAX_COUNTER = 9999
const HLC_RE = /^(\d{13})-(\d{4})-([0-9a-f]{16})$/
const NODE_ID_RE = /^[0-9a-f]{16}$/

export interface Timestamp {
  ms: number
  counter: number
  nodeId: string
}

export function parseHlc(value: string): Timestamp {
  const m = HLC_RE.exec(value)
  if (!m) throw new Error(`Invalid HLC timestamp: ${value}`)
  return { ms: Number(m[1]), counter: Number(m[2]), nodeId: m[3]! }
}

export function formatHlc({ ms, counter, nodeId }: Timestamp): string {
  return `${String(ms).padStart(13, '0')}-${String(counter).padStart(4, '0')}-${nodeId}`
}

export function randomNodeId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8))
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

export class Clock {
  readonly nodeId: string
  private readonly nowMs: () => number
  private ms: number
  private counter: number

  constructor(
    nodeId: string,
    nowMs: () => number = Date.now,
    state: { ms: number; counter: number } = { ms: 0, counter: 0 },
  ) {
    if (!NODE_ID_RE.test(nodeId)) throw new Error(`Invalid node id: ${nodeId}`)
    this.nodeId = nodeId
    this.nowMs = nowMs
    this.ms = state.ms
    this.counter = state.counter
  }

  /** Restores a clock that must never go below `last` (e.g. persisted across reloads). */
  static resume(nodeId: string, last: string | null, nowMs: () => number = Date.now): Clock {
    if (!last) return new Clock(nodeId, nowMs)
    const t = parseHlc(last)
    return new Clock(nodeId, nowMs, { ms: t.ms, counter: t.counter })
  }

  /** Timestamp for a local event. */
  now(): string {
    const pt = this.nowMs()
    if (pt > this.ms) {
      this.ms = pt
      this.counter = 0
    } else {
      this.counter += 1
    }
    return this.emit()
  }

  /** Advance past a timestamp received from another node. */
  receive(remote: string): string {
    const r = parseHlc(remote)
    const pt = this.nowMs()
    const ms = Math.max(this.ms, r.ms, pt)
    let counter: number
    if (ms === this.ms && ms === r.ms) counter = Math.max(this.counter, r.counter) + 1
    else if (ms === this.ms) counter = this.counter + 1
    else if (ms === r.ms) counter = r.counter + 1
    else counter = 0
    this.ms = ms
    this.counter = counter
    return this.emit()
  }

  private emit(): string {
    if (this.counter > MAX_COUNTER) {
      this.ms += 1
      this.counter = 0
    }
    return formatHlc({ ms: this.ms, counter: this.counter, nodeId: this.nodeId })
  }
}
