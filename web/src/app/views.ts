// View models: read the local Store and shape it for screens. Pure reads, safe inside liveQuery.
import type {
  CheckStatus,
  LocalDate,
  LocalDateTime,
  PartOfDay,
  Priority,
  Row,
  RoutineVersion,
  Settings,
  Task,
  TimeKind,
} from '../core/types'
import { routineVersions, type VersionWithMeta } from '../db/actions'
import type { Store } from '../db/store'
import { localNow, logicalDay, partOfDay } from '../domain/dates'
import { compareItems, pickTop, priorityRank } from '../domain/order'
import { dayRecord, heatmapGrid, heatmapLevels, streak, type DayRecord, type DayStats } from '../domain/progress'
import { routineAdherence, routinesForDay, type Adherence } from '../domain/routines'
import { nowScore, type ScoreReason } from '../domain/score'
import { titleHistory, type TitleHistory } from '../domain/suggest'
import { attentionLevel, deadlineStatus, type DeadlineStatus } from '../domain/tasks'

export type Section = 'anytime' | PartOfDay

export const SECTIONS: Section[] = ['anytime', 'morning', 'day', 'evening']

/** A group on the Day screen: open items by part of the day, then everything done or skipped. */
export type DayGroupId = Section | 'done'

export interface DayItem {
  key: string
  kind: 'task' | 'routine'
  id: string
  title: string
  emoji: string | null
  color: number
  time_kind: TimeKind
  part_of_day: PartOfDay | null
  time: string | null
  duration_min: number | null
  priority: Priority
  section: Section
  done: boolean
  skipped: boolean
  moves: number
  attention: number
  deadline: DeadlineStatus
  deadline_date: LocalDate | null
  deadline_time: string | null
  score: number
  reasons: ScoreReason[]
  sort_key: string
  /** Routines only: how regularly it is done as of today. */
  adherence: Adherence | null
}

/** Section a timed item belongs to: exact times fall into the part of day they are in. */
export function sectionOf(
  item: { time_kind: TimeKind; part_of_day: PartOfDay | null; time: string | null },
  s: Settings,
): Section {
  if (item.time_kind === 'part' && item.part_of_day) return item.part_of_day
  if (item.time_kind === 'exact' && item.time) return partOfDay(`2000-01-01T${item.time}`, s)
  return 'anytime'
}

export { compareItems }

const isClosed = (i: DayItem) => i.done || i.skipped

/** created_at is UTC; deadlines are measured in local days. */
function localDateOf(isoUtc: string): LocalDate {
  return localNow(new Date(isoUtc)).slice(0, 10)
}

/** Adherence of every routine as of today; see domain/routines. */
async function adherenceByRoutine(
  store: Store,
  versions: VersionWithMeta[],
  today: LocalDate,
  s: Settings,
): Promise<Map<string, Adherence>> {
  const checks = (await store.rows('routine_check')).map((c) => ({
    routine_id: c.fields.routine_id!,
    date: c.fields.date!,
    status: c.fields.status ?? null,
  }))
  return routineAdherence(today, versions, checks, s.routine_warn_below)
}

async function moveCounts(store: Store): Promise<Map<string, number>> {
  const counts = new Map<string, number>()
  for (const m of await store.rows('task_move')) {
    const id = m.fields.task_id
    if (id) counts.set(id, (counts.get(id) ?? 0) + 1)
  }
  return counts
}

export function taskItem(
  row: Row<'task'>,
  moves: number,
  now: LocalDateTime,
  s: Settings,
  today: LocalDate,
): DayItem {
  const t = row.fields as Task
  const deadline = deadlineStatus({
    now,
    dayStartHour: s.day_start_hour,
    createdOn: t.created_at ? localDateOf(t.created_at) : today,
    deadlineDate: t.deadline_date ?? null,
    deadlineTime: t.deadline_time ?? null,
    done: Boolean(t.done_on),
  })
  const base = {
    key: `task:${row.id}`,
    kind: 'task' as const,
    id: row.id,
    title: t.title ?? '',
    emoji: t.emoji ?? null,
    color: t.color ?? 0,
    time_kind: t.time_kind ?? 'none',
    part_of_day: t.part_of_day ?? null,
    time: t.time_kind === 'exact' ? (t.time ?? null) : null,
    duration_min: t.duration_min ?? null,
    priority: t.priority ?? 'normal',
    done: Boolean(t.done_on),
    skipped: false,
    moves,
    attention: attentionLevel(moves, s.attention_thresholds),
    deadline,
    deadline_date: t.deadline_date ?? null,
    deadline_time: t.deadline_time ?? null,
    sort_key: t.sort_key ?? '',
  }
  const { score, reasons } =
    t.date === today && !base.done
      ? nowScore(now, s, { ...base, deadline_status: deadline })
      : { score: 0, reasons: [] }
  return { ...base, section: sectionOf(base, s), score, reasons, adherence: null }
}

function routineItem(
  v: VersionWithMeta,
  status: CheckStatus,
  sortKey: string,
  now: LocalDateTime,
  s: Settings,
  isToday: boolean,
  adherence: Adherence | null,
): DayItem {
  const base = {
    key: `routine:${v.routine_id}`,
    kind: 'routine' as const,
    id: v.routine_id,
    title: v.title,
    emoji: v.emoji,
    color: v.color,
    time_kind: v.time_kind,
    part_of_day: v.part_of_day,
    time: v.time_kind === 'exact' ? v.time : null,
    duration_min: v.duration_min,
    priority: v.priority ?? 'normal',
    done: status === 'done',
    skipped: status === 'skipped',
    moves: 0,
    attention: 0,
    deadline: 'none' as const,
    deadline_date: null,
    deadline_time: null,
    sort_key: sortKey,
  }
  const { score, reasons } =
    isToday && !status
      ? nowScore(now, s, { ...base, deadline_status: 'none' })
      : { score: 0, reasons: [] }
  return { ...base, section: sectionOf(base, s), score, reasons, adherence }
}

export interface DayView {
  date: LocalDate
  items: DayItem[]
  done: number
  total: number
}

export async function loadDay(store: Store, date: LocalDate, now: LocalDateTime): Promise<DayView> {
  const s = await store.settings()
  const today = logicalDay(now, s.day_start_hour)
  const [versions, checks, routines, planned, doneThatDay, moves] = await Promise.all([
    routineVersions(store),
    store.db.routine_check.where('fields.date').equals(date).toArray(),
    store.rows('routine'),
    store.db.task.where('fields.date').equals(date).toArray(),
    store.db.task.where('fields.done_on').equals(date).toArray(),
    moveCounts(store),
  ])
  const status = new Map(checks.map((c) => [c.fields.routine_id, c.fields.status ?? null]))
  const sortKeys = new Map(routines.map((r) => [r.id, r.fields.sort_key ?? '']))
  const adherence = await adherenceByRoutine(store, versions, today, s)

  const items: DayItem[] = []
  for (const v of routinesForDay(date, versions).values()) {
    const st = status.get(v.routine_id) ?? null
    const a = adherence.get(v.routine_id) ?? null
    items.push(routineItem(v, st, sortKeys.get(v.routine_id) ?? '', now, s, date === today, a))
  }
  const seen = new Set<string>()
  for (const row of [...planned, ...doneThatDay]) {
    if (seen.has(row.id) || row.fields.deleted) continue
    // A task done on another day but still dated here belongs to that other day.
    if (row.fields.done_on && row.fields.done_on !== date) continue
    seen.add(row.id)
    items.push(taskItem(row, moves.get(row.id) ?? 0, now, s, today))
  }
  // Done and skipped go after every open item, whatever part of the day they were planned for.
  items.sort(
    (a, b) =>
      Number(isClosed(a)) - Number(isClosed(b)) ||
      SECTIONS.indexOf(a.section) - SECTIONS.indexOf(b.section) ||
      compareItems(a, b),
  )
  return {
    date,
    items,
    done: items.filter((i) => i.done).length,
    total: items.filter((i) => !i.skipped).length,
  }
}

/** Non-empty groups of a loaded day in screen order; the items keep the day's order. */
export function dayGroups(items: DayItem[]): { id: DayGroupId; items: DayItem[] }[] {
  const open = items.filter((i) => !isClosed(i))
  return [
    ...SECTIONS.map((id) => ({ id, items: open.filter((i) => i.section === id) })),
    { id: 'done' as const, items: items.filter(isClosed) },
  ].filter((g) => g.items.length)
}

/** Top items for the "Now" screen: high priority and highest score first, topped up with the next open items. */
export function pickNow(day: DayView, max = 7, min = 5): DayItem[] {
  return pickTop(day.items, max, min)
}

export interface HeatCell {
  date: LocalDate
  count: number
  /** -1 for days after today. */
  level: number
}

export interface StatsView {
  streak: number
  totalDone: number
  record: DayRecord
  heatmap: HeatCell[]
}

/** Done/skipped per day. Same counting rule as domain dayStats (shared/domain-fixtures/day_stats.json), in one pass. */
async function statsByDay(store: Store): Promise<Record<LocalDate, DayStats>> {
  const [tasks, checks] = await Promise.all([store.rows('task'), store.rows('routine_check')])
  const byDay: Record<LocalDate, DayStats> = {}
  const bump = (d: LocalDate, key: keyof DayStats) => {
    byDay[d] ??= { done: 0, skipped: 0 }
    byDay[d][key] += 1
  }
  for (const t of tasks) if (t.fields.done_on) bump(t.fields.done_on, 'done')
  for (const c of checks) {
    if (c.fields.status === 'done') bump(c.fields.date!, 'done')
    else if (c.fields.status === 'skipped') bump(c.fields.date!, 'skipped')
  }
  return byDay
}

export async function loadStats(store: Store, today: LocalDate): Promise<StatsView> {
  const s = await store.settings()
  const byDay = await statsByDay(store)
  const grid = heatmapGrid(today)
  const past = grid.filter((d) => d <= today)
  const levels = heatmapLevels(past.map((d) => byDay[d]?.done ?? 0))
  const heatmap = grid.map((date, i) => ({
    date,
    count: byDay[date]?.done ?? 0,
    level: date <= today ? levels[i]! : -1,
  }))
  const totalDone = Object.values(byDay).reduce((n, d) => n + d.done, 0)
  return {
    streak: streak(today, byDay, s.streak_min_done),
    totalDone,
    record: dayRecord(today, byDay),
    heatmap,
  }
}

export async function loadRecord(store: Store, today: LocalDate): Promise<DayRecord> {
  return dayRecord(today, await statsByDay(store))
}

const RECORD_CELEBRATED = 'record_celebrated'

/**
 * True once per day on this device: when today's record is broken and it was not celebrated yet.
 * Marks the day as celebrated.
 */
export async function claimRecordCelebration(store: Store, record: DayRecord, today: LocalDate): Promise<boolean> {
  if (!record.broken || (await store.getMeta<LocalDate>(RECORD_CELEBRATED)) === today) return false
  await store.setMeta(RECORD_CELEBRATED, today)
  return true
}

export async function loadInbox(store: Store, now: LocalDateTime): Promise<DayItem[]> {
  const s = await store.settings()
  const today = logicalDay(now, s.day_start_hour)
  const moves = await moveCounts(store)
  return (await store.rows('task'))
    .filter((r) => r.fields.date === null && !r.fields.deleted && !r.fields.done_on)
    .map((r) => taskItem(r, moves.get(r.id) ?? 0, now, s, today))
    .sort(compareItems)
}

/** Every task as history for title suggestions; see domain/suggest. */
export async function loadTitleHistory(store: Store, today: LocalDate): Promise<TitleHistory> {
  const tasks = (await store.rows('task')).map((r) => {
    const t = r.fields
    return {
      id: r.id,
      title: t.title ?? '',
      emoji: t.emoji ?? null,
      color: t.color ?? 0,
      duration_min: t.duration_min ?? null,
      done_on: t.done_on ?? null,
      deleted: t.deleted ?? false,
      created_on: t.created_at ? localDateOf(t.created_at) : today,
    }
  })
  return titleHistory(tasks, today)
}

export interface RoutineListItem {
  id: string
  version: VersionWithMeta
  /** Set when an edit takes effect after today. */
  pendingFrom: LocalDate | null
  section: Section
  sort_key: string
  adherence: Adherence
}

export async function loadRoutines(store: Store, today: LocalDate): Promise<RoutineListItem[]> {
  const s = await store.settings()
  const [versions, routines] = await Promise.all([routineVersions(store), store.rows('routine')])
  const latest = new Map<string, VersionWithMeta>()
  for (const v of versions) {
    const cur = latest.get(v.routine_id)
    if (
      !cur ||
      v.effective_from > cur.effective_from ||
      (v.effective_from === cur.effective_from && v.hlc > cur.hlc)
    ) {
      latest.set(v.routine_id, v)
    }
  }
  const sortKeys = new Map(routines.map((r) => [r.id, r.fields.sort_key ?? '']))
  const adherence = await adherenceByRoutine(store, versions, today, s)
  return [...latest.values()]
    .filter((v) => !v.archived)
    .map((v) => ({
      id: v.routine_id,
      version: v,
      pendingFrom: v.effective_from > today ? v.effective_from : null,
      section: sectionOf(v as RoutineVersion, s),
      sort_key: sortKeys.get(v.routine_id) ?? '',
      adherence: adherence.get(v.routine_id)!,
    }))
    .sort((a, b) =>
      SECTIONS.indexOf(a.section) - SECTIONS.indexOf(b.section) ||
      priorityRank(a.version.priority) - priorityRank(b.version.priority) ||
      (a.version.time ?? '').localeCompare(b.version.time ?? '') ||
      a.sort_key.localeCompare(b.sort_key),
    )
}

/** Adherence of one routine, for its editor; null for a routine without versions. */
export async function loadRoutineAdherence(store: Store, routineId: string, today: LocalDate): Promise<Adherence | null> {
  const s = await store.settings()
  const [versions, checks] = await Promise.all([
    routineVersions(store, routineId),
    store.db.routine_check.where('fields.routine_id').equals(routineId).toArray(),
  ])
  const marks = checks.map((c) => ({ routine_id: routineId, date: c.fields.date!, status: c.fields.status ?? null }))
  return routineAdherence(today, versions, marks, s.routine_warn_below).get(routineId) ?? null
}
