// Mirrors shared/schema/*.schema.json. Dates are local 'YYYY-MM-DD', times local 'HH:MM',
// *_at fields are UTC ISO instants.

export type LocalDate = string
export type LocalTime = string
/** Local wall-clock moment without timezone: 'YYYY-MM-DDTHH:MM'. */
export type LocalDateTime = string
export type Hlc = string

export type TimeKind = 'none' | 'part' | 'exact'
export type PartOfDay = 'morning' | 'day' | 'evening'

export interface Timing {
  time_kind: TimeKind
  part_of_day: PartOfDay | null
  time: LocalTime | null
}

export interface Task extends Timing {
  title: string
  notes: string
  emoji: string | null
  color: number
  date: LocalDate | null
  first_date: LocalDate | null
  duration_min: number | null
  deadline_date: LocalDate | null
  deadline_time: LocalTime | null
  done_on: LocalDate | null
  deleted: boolean
  sort_key: string
  created_at: string
}

export interface TaskMove {
  task_id: string
  from_date: LocalDate
  to_date: LocalDate
  kind: 'auto' | 'manual'
}

export interface Routine {
  sort_key: string
  created_at: string
}

export interface RoutineVersion extends Timing {
  routine_id: string
  effective_from: LocalDate
  title: string
  emoji: string | null
  color: number
  duration_min: number | null
  /** Bit 0 = Monday ... bit 6 = Sunday. */
  weekdays: number
  archived: boolean
  created_at: string
}

export interface RoutineSnapshot extends Timing {
  title: string
  emoji: string | null
  color: number
}

export type CheckStatus = 'done' | 'skipped' | null

export interface RoutineCheck {
  routine_id: string
  date: LocalDate
  status: CheckStatus
  done_at: string | null
  snapshot: RoutineSnapshot | null
}

export interface Settings {
  day_start_hour: number
  part_morning_from: number
  part_day_from: number
  part_evening_from: number
  attention_thresholds: [number, number, number, number]
  streak_min_done: number
}

export const DEFAULT_SETTINGS: Settings = {
  day_start_hour: 4,
  part_morning_from: 6,
  part_day_from: 12,
  part_evening_from: 18,
  attention_thresholds: [1, 3, 6, 10],
  streak_min_done: 1,
}

export interface EntityFields {
  task: Task
  task_move: TaskMove
  routine: Routine
  routine_version: RoutineVersion
  routine_check: RoutineCheck
  settings: Settings
}

export type EntityName = keyof EntityFields

export const ENTITIES: EntityName[] = [
  'task',
  'task_move',
  'routine',
  'routine_version',
  'routine_check',
  'settings',
]

export const SETTINGS_ID = 'settings'

/** A row as stored locally and sent over the wire. Fields may be partial until fully synced. */
export interface Row<E extends EntityName = EntityName> {
  id: string
  fields: Partial<EntityFields[E]>
  /** One HLC per present field. */
  clocks: Record<string, Hlc>
}

export interface Change<E extends EntityName = EntityName> extends Row<E> {
  entity: E
}
