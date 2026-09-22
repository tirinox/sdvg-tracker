import type { Hlc, LocalDate } from '../core/types'
import { weekdayIndex } from './dates'

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
