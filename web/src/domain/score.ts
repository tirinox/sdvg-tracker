import type { LocalDateTime, Settings, Timing } from '../core/types'
import { addDays, logicalDay, minutesBetween, partOfDay } from './dates'
import type { DeadlineStatus } from './tasks'

export interface ScoreItem extends Timing {
  deadline_status: DeadlineStatus
  moves: number
}

export type ScoreReason = 'now' | 'deadline' | 'postponed'

const DEADLINE_SCORE: Partial<Record<DeadlineStatus, number>> = { overdue: 90, today: 80, soon: 60 }

/** Ranking for the "Now" screen: now + deadline + postpone components. */
export function nowScore(
  now: LocalDateTime,
  s: Settings,
  item: ScoreItem,
): { score: number; reasons: ScoreReason[] } {
  const reasons: ScoreReason[] = []
  let nowPart = 0
  if (item.time_kind === 'exact' && item.time) {
    // Start lies on the logical day: times before day_start_hour are after midnight.
    let day = logicalDay(now, s.day_start_hour)
    if (Number(item.time.slice(0, 2)) < s.day_start_hour) day = addDays(day, 1)
    const mins = minutesBetween(`${day}T${item.time}`, now)
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
