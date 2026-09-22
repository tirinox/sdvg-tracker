// Demo data: ~24 routines, ~40 open tasks and ~4 months of history. Every id is derived from a
// fixed key, so seeding twice (or on two devices) merges into the same rows, and clearDemo can
// find everything again on any client.
import { v5 as uuidv5 } from 'uuid'
import { routineCheckId, taskMoveId } from '../core/ids'
import type {
  LocalDate,
  LocalDateTime,
  PartOfDay,
  RoutineSnapshot,
  RoutineVersion,
  Task,
  TimeKind,
} from '../core/types'
import { addDays } from '../domain/dates'
import { routinesForDay } from '../domain/routines'
import type { LocalChange, Store } from '../db/store'

export const DEMO_NAMESPACE = uuidv5('urn:sdvg-tracker:demo', uuidv5.URL)
const demoId = (key: string) => uuidv5(key, DEMO_NAMESPACE)

const HISTORY_DAYS = 120
const MAX_PAST_TASKS = 1000

// Weekday masks, bit 0 = Monday.
const DAILY = 127
const MON_WED_FRI = 0b0010101
const WORKDAYS = 0b0011111
const TUE_FRI = 0b0010010
const MON_THU = 0b0001001

interface RoutineSpec {
  key: string
  title: string
  emoji: string
  color: number
  kind: TimeKind
  part?: PartOfDay
  time?: string
  duration?: number
  weekdays?: number
  /** Title before a mid-history edit, to demonstrate versions. */
  oldTitle?: string
}

const ROUTINES: RoutineSpec[] = [
  { key: 'water', title: 'Стакан воды после пробуждения', emoji: '💧', color: 6, kind: 'exact', time: '07:00', duration: 5 },
  { key: 'pills', title: 'Принять таблетки', emoji: '💊', color: 0, kind: 'exact', time: '07:30', duration: 5 },
  { key: 'teeth-am', title: 'Почистить зубы', emoji: '🪥', color: 7, kind: 'part', part: 'morning' },
  { key: 'shower', title: 'Принять душ', emoji: '🚿', color: 6, kind: 'part', part: 'morning', duration: 15 },
  { key: 'bed', title: 'Застелить кровать', emoji: '🛏️', color: 9, kind: 'part', part: 'morning' },
  { key: 'breakfast', title: 'Позавтракать', emoji: '🥣', color: 2, kind: 'exact', time: '08:30', duration: 20 },
  { key: 'vitamins', title: 'Витамины', emoji: '🍊', color: 1, kind: 'part', part: 'morning' },
  { key: 'stretch', title: 'Растяжка 10 минут', emoji: '🧘', color: 4, kind: 'part', part: 'morning', duration: 10 },
  { key: 'plan', title: 'Посмотреть план на день', emoji: '🗓️', color: 8, kind: 'exact', time: '09:00', duration: 10 },
  { key: 'walk', title: 'Прогулка с коляской', emoji: '🚼', color: 4, kind: 'part', part: 'day', duration: 60, oldTitle: 'Прогулка' },
  { key: 'lunch', title: 'Пообедать', emoji: '🍲', color: 2, kind: 'exact', time: '13:00', duration: 30 },
  { key: 'water-day', title: 'Выпить воды', emoji: '🥤', color: 6, kind: 'part', part: 'day' },
  { key: 'mail', title: 'Разобрать почту и сообщения', emoji: '📬', color: 8, kind: 'part', part: 'day', duration: 15, weekdays: WORKDAYS },
  { key: 'english', title: 'Английский 15 минут', emoji: '🇬🇧', color: 7, kind: 'part', part: 'day', duration: 15, weekdays: WORKDAYS },
  { key: 'gym', title: 'Спортзал', emoji: '🏋️', color: 0, kind: 'exact', time: '18:30', duration: 60, weekdays: MON_WED_FRI },
  { key: 'flowers', title: 'Полить цветы', emoji: '🪴', color: 4, kind: 'part', part: 'day', weekdays: MON_THU },
  { key: 'trash', title: 'Вынести мусор', emoji: '🗑️', color: 11, kind: 'part', part: 'evening', weekdays: TUE_FRI },
  { key: 'dinner', title: 'Поужинать', emoji: '🍝', color: 1, kind: 'exact', time: '19:30', duration: 30 },
  { key: 'dishes', title: 'Помыть посуду', emoji: '🧽', color: 5, kind: 'part', part: 'evening', duration: 15 },
  { key: 'tidy', title: '15 минут уборки', emoji: '🧹', color: 3, kind: 'part', part: 'evening', duration: 15 },
  { key: 'clothes', title: 'Приготовить одежду на завтра', emoji: '👕', color: 9, kind: 'part', part: 'evening' },
  { key: 'tomorrow', title: 'Проверить календарь на завтра', emoji: '📅', color: 8, kind: 'part', part: 'evening', duration: 5 },
  { key: 'read', title: 'Чтение 20 минут', emoji: '📖', color: 10, kind: 'part', part: 'evening', duration: 20 },
  { key: 'teeth-pm', title: 'Почистить зубы перед сном', emoji: '🪥', color: 7, kind: 'exact', time: '23:00', duration: 5 },
]

interface TaskSpec {
  title: string
  emoji: string
  color: number
  /** Days from today; null = inbox. */
  day?: number | null
  moves?: number
  kind?: TimeKind
  part?: PartOfDay
  time?: string
  duration?: number
  /** Deadline in days from today, optionally with a time. */
  deadline?: number
  deadlineTime?: string
  notes?: string
}

const OPEN_TASKS: TaskSpec[] = [
  { title: 'Починить колесо коляски', emoji: '🛠️', color: 1, moves: 12, notes: 'Нужен шестигранник на 5' },
  { title: 'Записаться к стоматологу', emoji: '🦷', color: 7, moves: 9, deadline: 3 },
  { title: 'Заполнить налоговый вычет', emoji: '🧾', color: 11, moves: 7, deadline: -1 },
  { title: 'Позвонить в поликлинику', emoji: '📞', color: 0, kind: 'exact', time: '10:30', duration: 15, moves: 2 },
  { title: 'Оплатить интернет', emoji: '💳', color: 8, deadline: 0, moves: 1 },
  { title: 'Ответить Лене про выходные', emoji: '💬', color: 10, kind: 'part', part: 'day', moves: 3 },
  { title: 'Купить подгузники', emoji: '🛒', color: 4, kind: 'part', part: 'day' },
  { title: 'Отнести куртку в химчистку', emoji: '🧥', color: 9, moves: 5 },
  { title: 'Разобрать фото с телефона', emoji: '📸', color: 10, moves: 14 },
  { title: 'Продлить страховку машины', emoji: '🚗', color: 7, deadline: 2, moves: 4 },
  { title: 'Подготовить отчёт для работы', emoji: '📊', color: 8, kind: 'exact', time: '11:00', duration: 90, deadline: 1, deadlineTime: '18:00' },
  { title: 'Созвон с командой', emoji: '👥', color: 7, kind: 'exact', time: '15:00', duration: 30 },
  { title: 'Поменять лампочку в коридоре', emoji: '💡', color: 2, moves: 6 },
  { title: 'Вернуть книгу в библиотеку', emoji: '📚', color: 3, deadline: -2, moves: 8 },
  { title: 'Заказать витамины', emoji: '📦', color: 1, kind: 'part', part: 'evening' },
  { title: 'Написать маме', emoji: '❤️', color: 0, kind: 'part', part: 'evening', moves: 1 },
  { title: 'Разморозить морозилку', emoji: '🧊', color: 6, moves: 10 },
  { title: 'Проверить показания счётчиков', emoji: '🔢', color: 11, deadline: 4 },
  { title: 'Передать показания воды', emoji: '🚰', color: 6, deadline: 5, moves: 2 },
  { title: 'Сдать анализы', emoji: '🧪', color: 0, kind: 'part', part: 'morning', moves: 3, deadline: 6 },
  { title: 'Постирать шторы', emoji: '🪟', color: 5, moves: 4 },
  { title: 'Настроить резервную копию ноутбука', emoji: '💾', color: 8, moves: 11 },
  { title: 'Выбросить старые батарейки', emoji: '🔋', color: 3, moves: 2 },
  { title: 'Купить подарок на ДР Саше', emoji: '🎁', color: 10, deadline: 9 },
  { title: 'Забрать посылку', emoji: '📮', color: 1, kind: 'part', part: 'day', deadline: 2 },
  { title: 'Почистить кофемашину', emoji: '☕', color: 2, moves: 1 },
  { title: 'Обновить резюме', emoji: '📝', color: 8, moves: 6 },
  { title: 'Записать ребёнка к педиатру', emoji: '👶', color: 4, kind: 'part', part: 'morning', deadline: 7 },
  { title: 'Разобрать шкаф с одеждой', emoji: '👚', color: 9, moves: 3 },
  { title: 'Отменить ненужные подписки', emoji: '✂️', color: 11, moves: 5 },
  { title: 'Приготовить обед на завтра', emoji: '🥘', color: 2, kind: 'part', part: 'evening' },
  { title: 'Сделать дыхательную гимнастику', emoji: '🌬️', color: 5, kind: 'exact', time: '21:00', duration: 10 },
  // Planned ahead
  { title: 'Встреча с Димой', emoji: '☕', color: 3, day: 1, kind: 'exact', time: '12:00', duration: 60 },
  { title: 'Поменять резину', emoji: '🛞', color: 11, day: 3, deadline: 10 },
  { title: 'Уборка на балконе', emoji: '🧺', color: 4, day: 5 },
  // Inbox
  { title: 'Придумать, куда поехать летом', emoji: '🏖️', color: 6, day: null },
  { title: 'Посмотреть курс по фотографии', emoji: '🎓', color: 10, day: null },
  { title: 'Переклеить обои в детской', emoji: '🎨', color: 1, day: null },
  { title: 'Найти секцию плавания', emoji: '🏊', color: 7, day: null },
  { title: 'Разобраться с настройками роутера', emoji: '📡', color: 8, day: null },
]

const PAST_TITLES: [string, string, number][] = [
  ['Купить продукты', '🛒', 4],
  ['Оплатить коммуналку', '💳', 8],
  ['Постирать бельё', '🧺', 5],
  ['Забрать посылку', '📮', 1],
  ['Позвонить бабушке', '📞', 0],
  ['Сходить в аптеку', '💊', 0],
  ['Заправить машину', '⛽', 11],
  ['Погладить рубашки', '👔', 9],
  ['Ответить на письма', '📧', 8],
  ['Приготовить ужин', '🍳', 2],
  ['Помыть полы', '🧽', 5],
  ['Записаться на стрижку', '💇', 10],
]

/** Deterministic PRNG so the demo looks the same everywhere. */
function mulberry32(seed: number): () => number {
  let a = seed
  return () => {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const iso = (date: LocalDate, time = '09:00') => `${date}T${time}:00Z`
const routineId = (key: string) => demoId(`routine:${key}`)
const versionId = (key: string, v: number) => demoId(`routine_version:${key}:v${v}`)

function version(spec: RoutineSpec, from: LocalDate, title: string): RoutineVersion {
  return {
    routine_id: routineId(spec.key),
    effective_from: from,
    title,
    emoji: spec.emoji,
    color: spec.color,
    time_kind: spec.kind,
    part_of_day: spec.kind === 'part' ? spec.part! : null,
    time: spec.kind === 'exact' ? spec.time! : null,
    duration_min: spec.duration ?? null,
    weekdays: spec.weekdays ?? DAILY,
    archived: false,
    created_at: iso(from, '06:00'),
  }
}

/** Whether a routine would normally be done by `now` on its day. */
function isPast(spec: RoutineSpec, now: LocalDateTime): boolean {
  const hour = Number(now.slice(11, 13))
  if (spec.kind === 'exact') return spec.time! <= now.slice(11, 16)
  if (spec.part === 'morning') return hour >= 12
  if (spec.part === 'day') return hour >= 18
  return false
}

export async function generateDemo(store: Store, today: LocalDate, now: LocalDateTime): Promise<void> {
  const rand = mulberry32(20260922)
  const changes: LocalChange[] = []
  const start = addDays(today, -HISTORY_DAYS)
  const editDay = addDays(today, -30)

  // Routines and their versions.
  const versions: (RoutineVersion & { id: string; hlc: string; spec: RoutineSpec })[] = []
  ROUTINES.forEach((spec, i) => {
    changes.push({
      entity: 'routine',
      id: routineId(spec.key),
      fields: { sort_key: `a${String(i).padStart(3, '0')}`, created_at: iso(start, '06:00') },
    })
    const v1 = version(spec, start, spec.oldTitle ?? spec.title)
    changes.push({ entity: 'routine_version', id: versionId(spec.key, 1), fields: v1 })
    versions.push({ ...v1, id: versionId(spec.key, 1), hlc: '1', spec })
    if (spec.oldTitle) {
      const v2 = version(spec, editDay, spec.title)
      changes.push({ entity: 'routine_version', id: versionId(spec.key, 2), fields: v2 })
      versions.push({ ...v2, id: versionId(spec.key, 2), hlc: '2', spec })
    }
  })

  // History: mostly good days, a few bad ones, one sick day and one empty day.
  const sickDay = addDays(today, -40)
  const emptyDay = addDays(today, -25)
  let pastTask = 0
  for (let d = start; d <= today; d = addDays(d, 1)) {
    const isToday = d === today
    if (d === emptyDay) continue // a real gap: the streak restarts after it
    const quality = rand() < 0.1 ? 0.35 : 0.75 + rand() * 0.22
    for (const v of routinesForDay(d, versions).values()) {
      if (isToday && !isPast(v.spec, now)) continue
      let status: 'done' | 'skipped' | null = null
      if (d === sickDay) status = 'skipped'
      else if (rand() < quality) status = 'done'
      else if (rand() < 0.08) status = 'skipped'
      if (!status) continue
      const snapshot: RoutineSnapshot = {
        title: v.title,
        emoji: v.emoji,
        color: v.color,
        time_kind: v.time_kind,
        part_of_day: v.part_of_day,
        time: v.time,
      }
      changes.push({
        entity: 'routine_check',
        id: routineCheckId(v.routine_id, d),
        fields: {
          routine_id: v.routine_id,
          date: d,
          status,
          done_at: status === 'done' ? iso(d, v.time ?? '12:00') : null,
          snapshot,
        },
      })
    }

    // Completed one-off tasks, some of them after a few postpones.
    if (isToday || d === sickDay) continue
    const count = Math.floor(rand() * 4 * quality) + (quality > 0.5 ? 1 : 0)
    for (let i = 0; i < count && pastTask < MAX_PAST_TASKS; i++, pastTask++) {
      const [title, emoji, color] = PAST_TITLES[Math.floor(rand() * PAST_TITLES.length)]!
      const moves = rand() < 0.3 ? 1 + Math.floor(rand() * 3) : 0
      const id = demoId(`past_task:${pastTask}`)
      const first = addDays(d, -moves)
      changes.push({ entity: 'task', id, fields: task({ title, emoji, color }, d, first, d, i) })
      for (let m = 0; m < moves; m++) changes.push(move(id, addDays(first, m), 'auto'))
    }
  }

  // Open tasks for today, ahead and in the inbox.
  OPEN_TASKS.forEach((spec, i) => {
    const id = demoId(`open_task:${i}`)
    const moves = spec.moves ?? 0
    const date = spec.day === null ? null : addDays(today, spec.day ?? 0)
    const first = date === null ? null : addDays(date, -moves)
    changes.push({ entity: 'task', id, fields: task(spec, date, first, null, i) })
    for (let m = 0; m < moves; m++) {
      changes.push(move(id, addDays(first!, m), m === 0 && moves > 3 ? 'manual' : 'auto'))
    }
  })

  await store.write(changes)
}

function task(
  spec: TaskSpec,
  date: LocalDate | null,
  first: LocalDate | null,
  doneOn: LocalDate | null,
  order: number,
): Task {
  const kind = spec.kind ?? 'none'
  const created = first ?? '2026-01-01'
  return {
    title: spec.title,
    notes: spec.notes ?? '',
    emoji: spec.emoji,
    color: spec.color,
    date,
    first_date: first,
    time_kind: kind,
    part_of_day: kind === 'part' ? spec.part! : null,
    time: kind === 'exact' ? spec.time! : null,
    duration_min: spec.duration ?? null,
    deadline_date: spec.deadline === undefined || !date ? null : addDays(date, spec.deadline),
    deadline_time: spec.deadlineTime ?? null,
    done_on: doneOn,
    deleted: false,
    sort_key: `a${String(order).padStart(4, '0')}`,
    created_at: iso(addDays(created, -3), '08:00'),
  }
}

function move(taskId: string, from: LocalDate, kind: 'auto' | 'manual'): LocalChange<'task_move'> {
  return {
    entity: 'task_move',
    id: taskMoveId(taskId, from),
    fields: { task_id: taskId, from_date: from, to_date: addDays(from, 1), kind },
  }
}

/**
 * Removes the demo through normal synced writes: tasks are deleted (and un-done so they leave
 * the stats), routines get an archived copy of every version (same date, newer clock wins),
 * and routine marks are cleared.
 */
export async function clearDemo(store: Store): Promise<number> {
  const changes: LocalChange[] = []
  const taskIds = [
    ...OPEN_TASKS.map((_, i) => demoId(`open_task:${i}`)),
    ...Array.from({ length: MAX_PAST_TASKS }, (_, i) => demoId(`past_task:${i}`)),
  ]
  for (const row of await store.db.task.bulkGet(taskIds)) {
    if (row && !row.fields.deleted) {
      changes.push({ entity: 'task', id: row.id, fields: { deleted: true, done_on: null } })
    }
  }
  const routineIds = new Set(ROUTINES.map((r) => routineId(r.key)))
  const versions = await store.db.routine_version.where('fields.routine_id').anyOf([...routineIds]).toArray()
  for (const v of versions) {
    if (v.fields.archived) continue
    changes.push({
      entity: 'routine_version',
      id: demoId(`archive:${v.id}`),
      fields: { ...(v.fields as RoutineVersion), archived: true },
    })
  }
  const checks = await store.db.routine_check.where('fields.routine_id').anyOf([...routineIds]).toArray()
  for (const c of checks) {
    if (c.fields.status) changes.push({ entity: 'routine_check', id: c.id, fields: { status: null, done_at: null } })
  }
  await store.write(changes)
  return changes.length
}

export const DEMO_ROUTINE_COUNT = ROUTINES.length
export const DEMO_OPEN_TASK_COUNT = OPEN_TASKS.length
