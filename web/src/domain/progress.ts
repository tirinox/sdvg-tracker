import type { CheckStatus, LocalDate } from '../core/types'
import { addDays, weekdayIndex } from './dates'

export interface DayStats {
  done: number
  skipped: number
}

/** Deleted tasks still count: the work was done. Cleared checks count as nothing. */
export function dayStats(
  date: LocalDate,
  tasks: { done_on: LocalDate | null }[],
  checks: { date: LocalDate; status: CheckStatus }[],
): DayStats {
  let done = tasks.filter((t) => t.done_on === date).length
  let skipped = 0
  for (const c of checks) {
    if (c.date !== date) continue
    if (c.status === 'done') done += 1
    else if (c.status === 'skipped') skipped += 1
  }
  return { done, skipped }
}

type DayKind = 'success' | 'neutral' | 'fail'

/**
 * Success days in the unbroken run of success/neutral days ending today. A neutral day
 * (nothing done but a routine consciously skipped) keeps the streak without adding to it.
 * Today is ignored until it is already a success.
 */
export function streak(
  today: LocalDate,
  days: Record<LocalDate, DayStats>,
  minDone: number,
): number {
  const kind = (d: LocalDate): DayKind => {
    const s = days[d] ?? { done: 0, skipped: 0 }
    if (s.done >= minDone) return 'success'
    return s.skipped > 0 ? 'neutral' : 'fail'
  }
  let n = 0
  let d = kind(today) === 'success' ? today : addDays(today, -1)
  for (;;) {
    const k = kind(d)
    if (k === 'fail') return n
    if (k === 'success') n += 1
    d = addDays(d, -1)
  }
}

export interface DayRecord {
  /** Day the previous record was first set; null when nothing was done before today. */
  best_date: LocalDate | null
  best_done: number
  today_done: number
  /** How many more to do today to beat the record. */
  to_beat: number
  broken: boolean
}

/** Most done in a day before today (earliest day on a tie) and how today compares to it. */
export function dayRecord(today: LocalDate, days: Record<LocalDate, DayStats>): DayRecord {
  let best_date: LocalDate | null = null
  let best_done = 0
  for (const [d, s] of Object.entries(days)) {
    if (d >= today || s.done <= 0) continue
    if (s.done > best_done || (s.done === best_done && d < best_date!)) {
      best_date = d
      best_done = s.done
    }
  }
  const today_done = days[today]?.done ?? 0
  return {
    best_date,
    best_done,
    today_done,
    to_beat: Math.max(0, best_done + 1 - today_done),
    broken: best_done > 0 && today_done > best_done,
  }
}

/** Levels 0..4 relative to personal history: quartiles of the non-zero counts. */
export function heatmapLevels(counts: number[]): number[] {
  const v = counts.filter((c) => c > 0).sort((a, b) => a - b)
  const n = v.length
  if (n === 0) return counts.map(() => 0)
  const q = [0.25, 0.5, 0.75].map((p) => v[Math.ceil(p * n) - 1]!)
  return counts.map((c) => (c === 0 ? 0 : 1 + q.filter((t) => c > t).length))
}

export const HEATMAP_WEEKS = 53

/** Monday-first week columns; the last column is the week containing today. */
export function heatmapGrid(today: LocalDate): LocalDate[] {
  const monday = addDays(today, -weekdayIndex(today))
  const first = addDays(monday, -7 * (HEATMAP_WEEKS - 1))
  return Array.from({ length: HEATMAP_WEEKS * 7 }, (_, i) => addDays(first, i))
}
