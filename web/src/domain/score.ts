import type { LocalDateTime, PartOfDay, Settings, Timing } from '../core/types'
import { addDays, logicalDay, minutesBetween, partOfDay } from './dates'
import type { DeadlineStatus } from './tasks'

export interface ScoreItem extends Timing {
  deadline_status: DeadlineStatus
  moves: number
}

export type ScoreReason = 'now' | 'deadline' | 'postponed'

const DEADLINE_SCORE: Partial<Record<DeadlineStatus, number>> = { overdue: 90, today: 80, soon: 60 }

/** Minutes from an exact start to now; the start lies on the logical day, so times before day_start_hour are after midnight. */
function minutesSinceStart(now: LocalDateTime, s: Settings, time: string): number {
  let day = logicalDay(now, s.day_start_hour)
  if (Number(time.slice(0, 2)) < s.day_start_hour) day = addDays(day, 1)
  return minutesBetween(`${day}T${time}`, now)
}

const PARTS: PartOfDay[] = ['morning', 'day', 'evening']

/**
 * Whether an item's time has come today: without a time always; a part of the day from its start;
 * an exact time from 30 minutes before it (shared/domain-fixtures/time_started.json).
 */
export function hasStarted(now: LocalDateTime, s: Settings, item: Timing): boolean {
  if (item.time_kind === 'exact' && item.time) return minutesSinceStart(now, s, item.time) >= -30
  if (item.time_kind === 'part' && item.part_of_day) {
    return PARTS.indexOf(partOfDay(now, s)) >= PARTS.indexOf(item.part_of_day)
  }
  return true
}

/** Ranking for the "Now" screen: now + deadline + postpone components. */
export function nowScore(
  now: LocalDateTime,
  s: Settings,
  item: ScoreItem,
): { score: number; reasons: ScoreReason[] } {
  const reasons: ScoreReason[] = []
  let nowPart = 0
  if (item.time_kind === 'exact' && item.time) {
    const mins = minutesSinceStart(now, s, item.time)
    if (mins >= -30 && mins <= 60) nowPart = 100
  } else if (item.time_kind === 'part' && item.part_of_day === partOfDay(now, s)) {
    nowPart = 50
  }
  if (nowPart) reasons.push('now')
  const deadline = DEADLINE_SCORE[item.deadline_status] ?? 0
  if (deadline) reasons.push('deadline')
  const postponed = Math.min(item.moves * 8, 70)
  if (postponed) reasons.push('postponed')
  return { score: nowPart + deadline + postponed, reasons }
}
