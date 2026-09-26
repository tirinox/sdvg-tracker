// User intents as local writes. Every function reads what it needs from the Store and writes
// changes through Store.write, so each action is one outbox batch.
import { generateKeyBetween } from 'fractional-indexing'
import { newId, routineCheckId, taskMoveId } from '../core/ids'
import {
  SETTINGS_ID,
  type CheckStatus,
  type LocalDate,
  type Row,
  type RoutineVersion,
  type Settings,
  type Task,
} from '../core/types'
import { addDays } from '../domain/dates'
import { routinesForDay } from '../domain/routines'
import { planRollover } from '../domain/tasks'
import type { LocalChange, Store } from './store'

const utcNow = () => new Date().toISOString()

async function nextSortKey(store: Store, entity: 'task' | 'routine'): Promise<string> {
  const keys = (await store.rows(entity)).map((r) => r.fields.sort_key).filter(Boolean) as string[]
  const last = keys.sort().at(-1) ?? null
  return generateKeyBetween(last, null)
}

// ---------------------------------------------------------------- tasks

export type NewTask = Pick<Task, 'title'> &
  Partial<
    Pick<
      Task,
      | 'notes'
      | 'emoji'
      | 'color'
      | 'date'
      | 'time_kind'
      | 'part_of_day'
      | 'time'
      | 'duration_min'
      | 'deadline_date'
      | 'deadline_time'
    >
  >

export async function createTask(store: Store, input: NewTask): Promise<string> {
  const id = newId()
  const task: Task = {
    notes: '',
    emoji: null,
    color: 0,
    date: null,
    time_kind: 'none',
    part_of_day: null,
    time: null,
    duration_min: null,
    deadline_date: null,
    deadline_time: null,
    ...input,
    first_date: input.date ?? null,
    done_on: null,
    deleted: false,
    sort_key: await nextSortKey(store, 'task'),
    created_at: utcNow(),
  }
  await store.write([{ entity: 'task', id, fields: task }])
  return id
}

export async function updateTask(
  store: Store,
  id: string,
  patch: Partial<Omit<Task, 'first_date' | 'created_at'>>,
): Promise<void> {
  const fields: Partial<Task> = { ...patch }
  const current = await store.get('task', id)
  if (patch.date && !current?.first_date) fields.first_date = patch.date
  await store.write([{ entity: 'task', id, fields }])
}

export async function completeTask(store: Store, id: string, today: LocalDate): Promise<void> {
  await store.write([{ entity: 'task', id, fields: { done_on: today } }])
}

export async function reopenTask(store: Store, id: string): Promise<void> {
  await store.write([{ entity: 'task', id, fields: { done_on: null } }])
}

export async function deleteTask(store: Store, id: string): Promise<void> {
  await store.write([{ entity: 'task', id, fields: { deleted: true } }])
}

/** "Tomorrow": one manual move. An inbox task is just planned for tomorrow, without a move. */
export async function postponeTask(store: Store, id: string, today: LocalDate): Promise<void> {
  const task = await store.get('task', id)
  if (!task) throw new Error(`No task ${id}`)
  const tomorrow = addDays(today, 1)
  if (task.date === null) {
    await updateTask(store, id, { date: tomorrow })
    return
  }
  const from = task.date
  const to = from < today ? tomorrow : addDays(from, 1)
  await store.write([
    {
      entity: 'task_move',
      id: taskMoveId(id, from),
      fields: { task_id: id, from_date: from, to_date: to, kind: 'manual' },
    },
    { entity: 'task', id, fields: { date: to } },
  ])
}

/**
 * Re-plan a task. Pushing a planned task to a later day counts as a postpone (one manual move),
 * so editing the date is not a way around the counter.
 */
export async function rescheduleTask(
  store: Store,
  id: string,
  to: LocalDate | null,
  today: LocalDate,
): Promise<void> {
  const task = await store.get('task', id)
  if (!task) throw new Error(`No task ${id}`)
  const from = task.date
  if (from === null || to === null || to <= from || to <= today || task.done_on) {
    await updateTask(store, id, { date: to })
    return
  }
  await store.write([
    {
      entity: 'task_move',
      id: taskMoveId(id, from),
      fields: { task_id: id, from_date: from, to_date: to, kind: 'manual' },
    },
    { entity: 'task', id, fields: { date: to } },
  ])
}

/**
 * A new task with the same content, planned for `date`: not done and with no moves of its own.
 * A deadline that passes before that day stays behind, or the copy would be born overdue.
 */
export async function copyTask(store: Store, source: NewTask, date: LocalDate): Promise<string> {
  const deadline = source.deadline_date && source.deadline_date >= date ? source.deadline_date : null
  return createTask(store, {
    ...source,
    date,
    deadline_date: deadline,
    deadline_time: deadline ? (source.deadline_time ?? null) : null,
  })
}

/** Moves every open task planned before today to today. Safe to call repeatedly. */
export async function runRollover(store: Store, today: LocalDate): Promise<number> {
  const overdue = await store.db.task.where('fields.date').below(today).toArray()
  const { moves, dates } = planRollover(
    today,
    overdue.map((r) => ({
      id: r.id,
      date: r.fields.date ?? null,
      done_on: r.fields.done_on ?? null,
      deleted: r.fields.deleted ?? false,
    })),
  )
  const existing = new Set(
    (await store.db.task_move.bulkGet(moves.map((m) => m.id))).filter(Boolean).map((r) => r!.id),
  )
  const changes: LocalChange[] = moves
    .filter((m) => !existing.has(m.id))
    .map(({ id, ...fields }) => ({ entity: 'task_move', id, fields }))
  for (const [id, date] of Object.entries(dates)) {
    changes.push({ entity: 'task', id, fields: { date } })
  }
  await store.write(changes)
  return Object.keys(dates).length
}

export async function moveCount(store: Store, taskId: string): Promise<number> {
  return store.db.task_move.where('fields.task_id').equals(taskId).count()
}

// ---------------------------------------------------------------- routines

export type RoutineContent = Pick<RoutineVersion, 'title'> &
  Partial<
    Pick<
      RoutineVersion,
      'emoji' | 'color' | 'time_kind' | 'part_of_day' | 'time' | 'duration_min' | 'weekdays'
    >
  >

export interface VersionWithMeta extends RoutineVersion {
  id: string
  hlc: string
}

function withMeta(row: Row<'routine_version'>): VersionWithMeta {
  return { ...(row.fields as RoutineVersion), id: row.id, hlc: row.clocks.effective_from! }
}

export async function routineVersions(store: Store, routineId?: string): Promise<VersionWithMeta[]> {
  const rows = routineId
    ? await store.db.routine_version.where('fields.routine_id').equals(routineId).toArray()
    : await store.rows('routine_version')
  return rows.map(withMeta)
}

/** Versions of routines scheduled on `date`, keyed by routine id. */
export async function routinesOn(store: Store, date: LocalDate) {
  return routinesForDay(date, await routineVersions(store))
}

export async function createRoutine(
  store: Store,
  input: RoutineContent,
  today: LocalDate,
): Promise<string> {
  const routineId = newId()
  const version: RoutineVersion = {
    emoji: null,
    color: 0,
    time_kind: 'none',
    part_of_day: null,
    time: null,
    duration_min: null,
    weekdays: 127,
    ...input,
    routine_id: routineId,
    effective_from: today,
    archived: false,
    created_at: utcNow(),
  }
  await store.write([
    {
      entity: 'routine',
      id: routineId,
      fields: { sort_key: await nextSortKey(store, 'routine'), created_at: version.created_at },
    },
    { entity: 'routine_version', id: newId(), fields: version },
  ])
  return routineId
}

/**
 * Changes apply from today, or from tomorrow if today's occurrence is already marked:
 * past days (and a marked today) keep the version they were done with.
 */
async function addVersion(
  store: Store,
  routineId: string,
  patch: Partial<RoutineVersion>,
  today: LocalDate,
): Promise<void> {
  const versions = await routineVersions(store, routineId)
  const latest = versions.sort((a, b) =>
    a.effective_from === b.effective_from
      ? a.hlc.localeCompare(b.hlc)
      : a.effective_from.localeCompare(b.effective_from),
  ).at(-1)
  if (!latest) throw new Error(`No routine ${routineId}`)
  const check = await store.get('routine_check', routineCheckId(routineId, today))
  const effectiveFrom = check?.status ? addDays(today, 1) : today
  const { id, hlc, ...base } = latest
  await store.write([
    {
      entity: 'routine_version',
      id: newId(),
      fields: { ...base, ...patch, effective_from: effectiveFrom, created_at: utcNow() },
    },
  ])
}

export async function editRoutine(
  store: Store,
  routineId: string,
  patch: Partial<RoutineContent>,
  today: LocalDate,
): Promise<void> {
  await addVersion(store, routineId, patch, today)
}

export async function archiveRoutine(
  store: Store,
  routineId: string,
  today: LocalDate,
): Promise<void> {
  await addVersion(store, routineId, { archived: true }, today)
}

export async function setRoutineCheck(
  store: Store,
  routineId: string,
  date: LocalDate,
  status: CheckStatus,
): Promise<void> {
  const version = (await routinesOn(store, date)).get(routineId)
  const snapshot = version
    ? {
        title: version.title,
        emoji: version.emoji,
        color: version.color,
        time_kind: version.time_kind,
        part_of_day: version.part_of_day,
        time: version.time,
      }
    : null
  await store.write([
    {
      entity: 'routine_check',
      id: routineCheckId(routineId, date),
      fields: {
        routine_id: routineId,
        date,
        status,
        done_at: status === 'done' ? utcNow() : null,
        snapshot,
      },
    },
  ])
}

// ---------------------------------------------------------------- settings

export async function updateSettings(store: Store, patch: Partial<Settings>): Promise<void> {
  await store.write([{ entity: 'settings', id: SETTINGS_ID, fields: patch }])
}
