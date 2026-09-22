import { taskMoveId } from '../core/ids'
import type { LocalDate, LocalDateTime, LocalTime, TaskMove } from '../core/types'
import { addDays, daysBetween, logicalDay } from './dates'

export interface RolloverTask {
  id: string
  date: LocalDate | null
  done_on: LocalDate | null
  deleted: boolean
}

export interface PlannedMove extends TaskMove {
  id: string
}

/**
 * Auto rollover: every open task planned before today gets one move per missed day and is
 * re-planned for today. Move ids are deterministic, so two devices produce identical rows.
 */
export function planRollover(
  today: LocalDate,
  tasks: RolloverTask[],
): { moves: PlannedMove[]; dates: Record<string, LocalDate> } {
  const moves: PlannedMove[] = []
  const dates: Record<string, LocalDate> = {}
  for (const t of tasks) {
    if (t.done_on || t.deleted || t.date === null || t.date >= today) continue
    for (let d = t.date; d < today; d = addDays(d, 1)) {
      moves.push({
        id: taskMoveId(t.id, d),
        task_id: t.id,
        from_date: d,
        to_date: addDays(d, 1),
        kind: 'auto',
      })
    }
    dates[t.id] = today
  }
  return { moves, dates }
}

/** 0..4: how many thresholds the move count has reached. */
export function attentionLevel(moves: number, thresholds: readonly number[]): number {
  return thresholds.filter((t) => moves >= t).length
}

export type DeadlineStatus = 'none' | 'ok' | 'soon' | 'today' | 'overdue'

export interface DeadlineInput {
  now: LocalDateTime
  dayStartHour: number
  /** Local date the task was created. */
  createdOn: LocalDate
  deadlineDate: LocalDate | null
  deadlineTime: LocalTime | null
  done: boolean
}

export function deadlineStatus(i: DeadlineInput): DeadlineStatus {
  if (i.done || i.deadlineDate === null) return 'none'
  const today = logicalDay(i.now, i.dayStartHour)
  if (i.deadlineTime !== null && i.now >= `${i.deadlineDate}T${i.deadlineTime}`) return 'overdue'
  if (today > i.deadlineDate) return 'overdue'
  if (today === i.deadlineDate) return 'today'
  const daysLeft = daysBetween(today, i.deadlineDate)
  const total = daysBetween(i.createdOn, i.deadlineDate)
  const elapsed = daysBetween(i.createdOn, today)
  if (daysLeft <= 2 || (total > 0 && elapsed / total > 0.8)) return 'soon'
  return 'ok'
}
