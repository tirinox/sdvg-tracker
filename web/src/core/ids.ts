import { v5 as uuidv5, v7 as uuidv7 } from 'uuid'
import type { LocalDate } from './types'

/** uuidv5(NAMESPACE_URL, 'urn:sdvg-tracker:ids'), see shared/vectors/ids.json. */
export const IDS_NAMESPACE = uuidv5('urn:sdvg-tracker:ids', uuidv5.URL)

export function newId(): string {
  return uuidv7()
}

export function routineCheckId(routineId: string, date: LocalDate): string {
  return uuidv5(`routine_check:${routineId}:${date}`, IDS_NAMESPACE)
}

export function taskMoveId(taskId: string, fromDate: LocalDate): string {
  return uuidv5(`task_move:${taskId}:${fromDate}`, IDS_NAMESPACE)
}
