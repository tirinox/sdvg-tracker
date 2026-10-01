// Demo data: ~24 routines, ~40 open tasks and ~4 months of history. Every id is derived from a
// fixed key, so seeding twice (or on two devices) merges into the same rows, and clearDemo can
// find everything again on any client.
import { v5 as uuidv5 } from 'uuid'
import { tr } from '../app/i18n'
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

// The specs are built on each call, so titles come out in the interface language of that moment;
// nothing matches on them (ids come from keys and positions).
const routineSpecs = (): RoutineSpec[] => [
  { key: 'water', title: tr('Стакан воды после пробуждения', 'Glass of water after waking up'), emoji: '💧', color: 6, kind: 'exact', time: '07:00', duration: 5 },
  { key: 'pills', title: tr('Принять таблетки', 'Take meds'), emoji: '💊', color: 0, kind: 'exact', time: '07:30', duration: 5 },
  { key: 'teeth-am', title: tr('Почистить зубы', 'Brush teeth'), emoji: '🪥', color: 7, kind: 'part', part: 'morning' },
  { key: 'shower', title: tr('Принять душ', 'Shower'), emoji: '🚿', color: 6, kind: 'part', part: 'morning', duration: 15 },
  { key: 'bed', title: tr('Застелить кровать', 'Make the bed'), emoji: '🛏️', color: 9, kind: 'part', part: 'morning' },
  { key: 'breakfast', title: tr('Позавтракать', 'Have breakfast'), emoji: '🥣', color: 2, kind: 'exact', time: '08:30', duration: 20 },
  { key: 'vitamins', title: tr('Витамины', 'Vitamins'), emoji: '🍊', color: 1, kind: 'part', part: 'morning' },
  { key: 'stretch', title: tr('Растяжка 10 минут', 'Stretch for 10 minutes'), emoji: '🧘', color: 4, kind: 'part', part: 'morning', duration: 10 },
  { key: 'plan', title: tr('Посмотреть план на день', 'Look over the plan for the day'), emoji: '🗓️', color: 8, kind: 'exact', time: '09:00', duration: 10 },
  { key: 'walk', title: tr('Прогулка с коляской', 'Stroller walk'), emoji: '🚼', color: 4, kind: 'part', part: 'day', duration: 60, oldTitle: tr('Прогулка', 'Walk') },
  { key: 'lunch', title: tr('Пообедать', 'Have lunch'), emoji: '🍲', color: 2, kind: 'exact', time: '13:00', duration: 30 },
  { key: 'water-day', title: tr('Выпить воды', 'Drink some water'), emoji: '🥤', color: 6, kind: 'part', part: 'day' },
  { key: 'mail', title: tr('Разобрать почту и сообщения', 'Go through email and messages'), emoji: '📬', color: 8, kind: 'part', part: 'day', duration: 15, weekdays: WORKDAYS },
  { key: 'english', title: tr('Английский 15 минут', 'French for 15 minutes'), emoji: tr('🇬🇧', '🇫🇷'), color: 7, kind: 'part', part: 'day', duration: 15, weekdays: WORKDAYS },
  { key: 'gym', title: tr('Спортзал', 'Gym'), emoji: '🏋️', color: 0, kind: 'exact', time: '18:30', duration: 60, weekdays: MON_WED_FRI },
  { key: 'flowers', title: tr('Полить цветы', 'Water the plants'), emoji: '🪴', color: 4, kind: 'part', part: 'day', weekdays: MON_THU },
  { key: 'trash', title: tr('Вынести мусор', 'Take out the trash'), emoji: '🗑️', color: 11, kind: 'part', part: 'evening', weekdays: TUE_FRI },
  { key: 'dinner', title: tr('Поужинать', 'Have dinner'), emoji: '🍝', color: 1, kind: 'exact', time: '19:30', duration: 30 },
  { key: 'dishes', title: tr('Помыть посуду', 'Do the dishes'), emoji: '🧽', color: 5, kind: 'part', part: 'evening', duration: 15 },
  { key: 'tidy', title: tr('15 минут уборки', '15 minutes of tidying'), emoji: '🧹', color: 3, kind: 'part', part: 'evening', duration: 15 },
  { key: 'clothes', title: tr('Приготовить одежду на завтра', 'Lay out clothes for tomorrow'), emoji: '👕', color: 9, kind: 'part', part: 'evening' },
  { key: 'tomorrow', title: tr('Проверить календарь на завтра', 'Check tomorrow’s calendar'), emoji: '📅', color: 8, kind: 'part', part: 'evening', duration: 5 },
  { key: 'read', title: tr('Чтение 20 минут', 'Read for 20 minutes'), emoji: '📖', color: 10, kind: 'part', part: 'evening', duration: 20 },
  { key: 'teeth-pm', title: tr('Почистить зубы перед сном', 'Brush teeth before bed'), emoji: '🪥', color: 7, kind: 'exact', time: '23:00', duration: 5 },
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

const openTaskSpecs = (): TaskSpec[] => [
  { title: tr('Починить колесо коляски', 'Fix the stroller wheel'), emoji: '🛠️', color: 1, moves: 12, notes: tr('Нужен шестигранник на 5', 'Need a 5 mm hex key') },
  { title: tr('Записаться к стоматологу', 'Book a dentist appointment'), emoji: '🦷', color: 7, moves: 9, deadline: 3 },
  { title: tr('Заполнить налоговый вычет', 'File the tax return'), emoji: '🧾', color: 11, moves: 7, deadline: -1 },
  { title: tr('Позвонить в поликлинику', 'Call the clinic'), emoji: '📞', color: 0, kind: 'exact', time: '10:30', duration: 15, moves: 2 },
  { title: tr('Оплатить интернет', 'Pay the internet bill'), emoji: '💳', color: 8, deadline: 0, moves: 1 },
  { title: tr('Ответить Лене про выходные', 'Reply to Emma about the weekend'), emoji: '💬', color: 10, kind: 'part', part: 'day', moves: 3 },
  { title: tr('Купить подгузники', 'Buy diapers'), emoji: '🛒', color: 4, kind: 'part', part: 'day' },
  { title: tr('Отнести куртку в химчистку', 'Take the jacket to the dry cleaner'), emoji: '🧥', color: 9, moves: 5 },
  { title: tr('Разобрать фото с телефона', 'Sort the photos on my phone'), emoji: '📸', color: 10, moves: 14 },
  { title: tr('Продлить страховку машины', 'Renew the car insurance'), emoji: '🚗', color: 7, deadline: 2, moves: 4 },
  { title: tr('Подготовить отчёт для работы', 'Prepare the work report'), emoji: '📊', color: 8, kind: 'exact', time: '11:00', duration: 90, deadline: 1, deadlineTime: '18:00' },
  { title: tr('Созвон с командой', 'Team call'), emoji: '👥', color: 7, kind: 'exact', time: '15:00', duration: 30 },
  { title: tr('Поменять лампочку в коридоре', 'Change the hallway light bulb'), emoji: '💡', color: 2, moves: 6 },
  { title: tr('Вернуть книгу в библиотеку', 'Return the library book'), emoji: '📚', color: 3, deadline: -2, moves: 8 },
  { title: tr('Заказать витамины', 'Order vitamins'), emoji: '📦', color: 1, kind: 'part', part: 'evening' },
  { title: tr('Написать маме', 'Text Mom'), emoji: '❤️', color: 0, kind: 'part', part: 'evening', moves: 1 },
  { title: tr('Разморозить морозилку', 'Defrost the freezer'), emoji: '🧊', color: 6, moves: 10 },
  { title: tr('Проверить показания счётчиков', 'Check the meter readings'), emoji: '🔢', color: 11, deadline: 4 },
  { title: tr('Передать показания воды', 'Submit the water meter reading'), emoji: '🚰', color: 6, deadline: 5, moves: 2 },
  { title: tr('Сдать анализы', 'Get blood work done'), emoji: '🧪', color: 0, kind: 'part', part: 'morning', moves: 3, deadline: 6 },
  { title: tr('Постирать шторы', 'Wash the curtains'), emoji: '🪟', color: 5, moves: 4 },
  { title: tr('Настроить резервную копию ноутбука', 'Set up laptop backups'), emoji: '💾', color: 8, moves: 11 },
  { title: tr('Выбросить старые батарейки', 'Recycle the old batteries'), emoji: '🔋', color: 3, moves: 2 },
  { title: tr('Купить подарок на ДР Саше', 'Buy Sam a birthday present'), emoji: '🎁', color: 10, deadline: 9 },
  { title: tr('Забрать посылку', 'Pick up the parcel'), emoji: '📮', color: 1, kind: 'part', part: 'day', deadline: 2 },
  { title: tr('Почистить кофемашину', 'Clean the coffee machine'), emoji: '☕', color: 2, moves: 1 },
  { title: tr('Обновить резюме', 'Update my resume'), emoji: '📝', color: 8, moves: 6 },
  { title: tr('Записать ребёнка к педиатру', 'Book the kid’s pediatrician visit'), emoji: '👶', color: 4, kind: 'part', part: 'morning', deadline: 7 },
  { title: tr('Разобрать шкаф с одеждой', 'Sort out the wardrobe'), emoji: '👚', color: 9, moves: 3 },
  { title: tr('Отменить ненужные подписки', 'Cancel unused subscriptions'), emoji: '✂️', color: 11, moves: 5 },
  { title: tr('Приготовить обед на завтра', 'Make tomorrow’s lunch'), emoji: '🥘', color: 2, kind: 'part', part: 'evening' },
  { title: tr('Сделать дыхательную гимнастику', 'Do breathing exercises'), emoji: '🌬️', color: 5, kind: 'exact', time: '21:00', duration: 10 },
  // Planned ahead
  { title: tr('Встреча с Димой', 'Coffee with Dan'), emoji: '☕', color: 3, day: 1, kind: 'exact', time: '12:00', duration: 60 },
  { title: tr('Поменять резину', 'Swap the tires'), emoji: '🛞', color: 11, day: 3, deadline: 10 },
  { title: tr('Уборка на балконе', 'Clean up the balcony'), emoji: '🧺', color: 4, day: 5 },
  // Inbox
  { title: tr('Придумать, куда поехать летом', 'Decide where to go this summer'), emoji: '🏖️', color: 6, day: null },
  { title: tr('Посмотреть курс по фотографии', 'Look into a photography course'), emoji: '🎓', color: 10, day: null },
  { title: tr('Переклеить обои в детской', 'Redo the wallpaper in the kids’ room'), emoji: '🎨', color: 1, day: null },
  { title: tr('Найти секцию плавания', 'Find swimming lessons'), emoji: '🏊', color: 7, day: null },
  { title: tr('Разобраться с настройками роутера', 'Figure out the router settings'), emoji: '📡', color: 8, day: null },
]

const pastTitles = (): [string, string, number][] => [
  [tr('Купить продукты', 'Buy groceries'), '🛒', 4],
  [tr('Оплатить коммуналку', 'Pay the utility bills'), '💳', 8],
  [tr('Постирать бельё', 'Do the laundry'), '🧺', 5],
  [tr('Забрать посылку', 'Pick up the parcel'), '📮', 1],
  [tr('Позвонить бабушке', 'Call Grandma'), '📞', 0],
  [tr('Сходить в аптеку', 'Go to the pharmacy'), '💊', 0],
  [tr('Заправить машину', 'Fill up the car'), '⛽', 11],
  [tr('Погладить рубашки', 'Iron the shirts'), '👔', 9],
  [tr('Ответить на письма', 'Answer emails'), '📧', 8],
  [tr('Приготовить ужин', 'Cook dinner'), '🍳', 2],
  [tr('Помыть полы', 'Mop the floors'), '🧽', 5],
  [tr('Записаться на стрижку', 'Book a haircut'), '💇', 10],
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
  const routines = routineSpecs()
  const openTasks = openTaskSpecs()
  const past = pastTitles()

  // Routines and their versions.
  const versions: (RoutineVersion & { id: string; hlc: string; spec: RoutineSpec })[] = []
  routines.forEach((spec, i) => {
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
      const [title, emoji, color] = past[Math.floor(rand() * past.length)]!
      const moves = rand() < 0.3 ? 1 + Math.floor(rand() * 3) : 0
      const id = demoId(`past_task:${pastTask}`)
      const first = addDays(d, -moves)
      changes.push({ entity: 'task', id, fields: task({ title, emoji, color }, d, first, d, i) })
      for (let m = 0; m < moves; m++) changes.push(move(id, addDays(first, m), 'auto'))
    }
  }

  // Open tasks for today, ahead and in the inbox.
  openTasks.forEach((spec, i) => {
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
    ...openTaskSpecs().map((_, i) => demoId(`open_task:${i}`)),
    ...Array.from({ length: MAX_PAST_TASKS }, (_, i) => demoId(`past_task:${i}`)),
  ]
  for (const row of await store.db.task.bulkGet(taskIds)) {
    if (row && !row.fields.deleted) {
      changes.push({ entity: 'task', id: row.id, fields: { deleted: true, done_on: null } })
    }
  }
  const routineIds = new Set(routineSpecs().map((r) => routineId(r.key)))
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

export const DEMO_ROUTINE_COUNT = routineSpecs().length
export const DEMO_OPEN_TASK_COUNT = openTaskSpecs().length
