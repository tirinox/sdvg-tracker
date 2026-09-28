import type { CheckStatus, Hlc, LocalDate } from '../core/types'
import { addDays, weekdayIndex } from './dates'

export interface VersionRef {
  id: string
  routine_id: string
  effective_from: LocalDate
  weekdays: number
  archived: boolean
  /** The version's clock; breaks ties between versions with the same effective_from. */
  hlc: Hlc
}

/**
 * Routines scheduled on `date`: per routine the version with max (effective_from, hlc) among
 * those with effective_from <= date, kept if not archived and its weekday bit is set.
 */
export function routinesForDay<V extends VersionRef>(date: LocalDate, versions: V[]): Map<string, V> {
  const current = new Map<string, V>()
  for (const v of versions) {
    if (v.effective_from > date) continue
    const cur = current.get(v.routine_id)
    if (
      !cur ||
      v.effective_from > cur.effective_from ||
      (v.effective_from === cur.effective_from && v.hlc > cur.hlc)
    ) {
      current.set(v.routine_id, v)
    }
  }
  const bit = 1 << weekdayIndex(date)
  for (const [rid, v] of current) {
    if (v.archived || !(v.weekdays & bit)) current.delete(rid)
  }
  return current
}

export interface CheckRef {
  routine_id: string
  date: LocalDate
  status: CheckStatus
}

/** Adherence looks back this many days, today included. */
export const ADHERENCE_DAYS = 30

export interface Adherence {
  /** First day counted: the first scheduled day it was done, at most ADHERENCE_DAYS back; null while it never was. */
  from: LocalDate | null
  done: number
  /** Scheduled days since `from`: skipped ones are left out, today counts once it is done. */
  total: number
  /** done / total in whole percent, half up; null while it was never done. */
  percent: number | null
  /** Below the routine_warn_below setting: the routine is being skipped. */
  warning: boolean
}

/**
 * How regularly each routine is done over the last ADHERENCE_DAYS, but not before the first day it
 * was done (shared/domain-fixtures/routine_adherence.json).
 */
export function routineAdherence(
  today: LocalDate,
  versions: VersionRef[],
  checks: CheckRef[],
  warnBelow: number,
): Map<string, Adherence> {
  const own = new Map<string, VersionRef[]>()
  for (const v of versions) own.set(v.routine_id, [...(own.get(v.routine_id) ?? []), v])
  const marks = new Map<string, Map<LocalDate, CheckStatus>>()
  for (const c of checks) {
    if (!marks.has(c.routine_id)) marks.set(c.routine_id, new Map())
    marks.get(c.routine_id)!.set(c.date, c.status)
  }

  const windowStart = addDays(today, 1 - ADHERENCE_DAYS)
  const result = new Map<string, Adherence>()
  for (const [rid, vs] of own) {
    const status = marks.get(rid) ?? new Map<LocalDate, CheckStatus>()
    const scheduled = (d: LocalDate) => routinesForDay(d, vs).has(rid)
    const first = [...status]
      .filter(([d, s]) => s === 'done' && d <= today)
      .map(([d]) => d)
      .sort()
      .find(scheduled)
    const from = first === undefined ? null : first > windowStart ? first : windowStart
    let done = 0
    let total = 0
    for (let d = from; d !== null && d <= today; d = addDays(d, 1)) {
      if (!scheduled(d)) continue
      const s = status.get(d) ?? null
      if (s === 'done') done += 1
      if (s === 'done' || (s === null && d < today)) total += 1
    }
    const percent = total ? Math.floor((200 * done + total) / (2 * total)) : null
    result.set(rid, { from, done, total, percent, warning: percent !== null && percent < warnBelow })
  }
  return result
}
