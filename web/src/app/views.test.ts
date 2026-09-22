import { afterEach, describe, expect, it } from 'vitest'
import { completeTask, createRoutine, createTask, postponeTask, setRoutineCheck } from '../db/actions'
import { Store } from '../db/store'
import { DEMO_OPEN_TASK_COUNT, DEMO_ROUTINE_COUNT, clearDemo, generateDemo } from '../demo/demo'
import { claimRecordCelebration, loadDay, loadInbox, loadRecord, loadRoutines, loadStats, pickNow } from './views'

const TODAY = '2026-09-22' // Tuesday
const NOW = `${TODAY}T14:40`
const stores: Store[] = []

async function openStore() {
  const store = await Store.open(crypto.randomUUID())
  stores.push(store)
  return store
}

afterEach(() => {
  for (const s of stores.splice(0)) s.close()
})

describe('loadDay', () => {
  it('mixes routines and tasks, sections and order', async () => {
    const store = await openStore()
    await createRoutine(store, { title: 'Пообедать', time_kind: 'exact', time: '13:00' }, TODAY)
    await createRoutine(store, { title: 'Душ', time_kind: 'part', part_of_day: 'morning' }, TODAY)
    const late = await createTask(store, { title: 'Созвон', date: TODAY, time_kind: 'exact', time: '15:00' })
    const any = await createTask(store, { title: 'Лампочка', date: TODAY })
    await createTask(store, { title: 'Завтра', date: '2026-09-23' })
    await completeTask(store, any, TODAY)

    const day = await loadDay(store, TODAY, NOW)
    expect(day.items.map((i) => [i.title, i.section, i.done])).toEqual([
      ['Лампочка', 'anytime', true],
      ['Душ', 'morning', false],
      ['Пообедать', 'day', false],
      ['Созвон', 'day', false],
    ])
    expect(day).toMatchObject({ done: 1, total: 4 })
    expect(day.items.find((i) => i.id === late)).toMatchObject({ score: 100, reasons: ['now'] })
  })

  it('shows move counts and attention', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Коляска', date: TODAY })
    for (let i = 0; i < 3; i++) await postponeTask(store, id, TODAY)
    const later = await loadDay(store, '2026-09-25', NOW)
    expect(later.items[0]).toMatchObject({ moves: 3, attention: 2 })
  })

  it('a skipped routine does not count towards the total', async () => {
    const store = await openStore()
    const r = await createRoutine(store, { title: 'Спортзал' }, TODAY)
    await setRoutineCheck(store, r, TODAY, 'skipped')
    expect(await loadDay(store, TODAY, NOW)).toMatchObject({ done: 0, total: 0 })
  })
})

describe('day record', () => {
  it('counts tasks and routines of any kind and celebrates once a day', async () => {
    const store = await openStore()
    const YESTERDAY = '2026-09-21'
    await completeTask(store, await createTask(store, { title: 'Вчера', date: YESTERDAY }), YESTERDAY)
    const r = await createRoutine(store, { title: 'Душ' }, YESTERDAY)
    await setRoutineCheck(store, r, YESTERDAY, 'done')

    expect(await loadRecord(store, TODAY)).toMatchObject({ best_date: YESTERDAY, best_done: 2, to_beat: 3 })

    await setRoutineCheck(store, r, TODAY, 'done')
    for (const title of ['Раз', 'Два']) await completeTask(store, await createTask(store, { title, date: TODAY }), TODAY)
    const record = await loadRecord(store, TODAY)
    expect(record).toMatchObject({ today_done: 3, to_beat: 0, broken: true })
    expect(await claimRecordCelebration(store, record, TODAY)).toBe(true)

    await completeTask(store, await createTask(store, { title: 'Три', date: TODAY }), TODAY)
    expect(await claimRecordCelebration(store, await loadRecord(store, TODAY), TODAY)).toBe(false)
  })
})

describe('demo data', { timeout: 60_000 }, () => {
  it('fills a realistic day and history', async () => {
    const store = await openStore()
    await generateDemo(store, TODAY, NOW)
    const day = await loadDay(store, TODAY, NOW)
    const routines = day.items.filter((i) => i.kind === 'routine')
    const tasks = day.items.filter((i) => i.kind === 'task')
    expect(routines.length).toBeGreaterThanOrEqual(20)
    expect(routines.length).toBeLessThanOrEqual(DEMO_ROUTINE_COUNT)
    expect(tasks.length).toBeGreaterThanOrEqual(30)
    expect(tasks.some((t) => t.attention === 4)).toBe(true)
    expect(tasks.some((t) => t.deadline === 'overdue')).toBe(true)
    expect(await loadInbox(store, NOW)).toHaveLength(5)
    expect(await loadRoutines(store, TODAY)).toHaveLength(DEMO_ROUTINE_COUNT)

    const now = pickNow(day)
    expect(now.length).toBeGreaterThanOrEqual(5)
    expect(now.length).toBeLessThanOrEqual(7)
    expect(now[0]!.score).toBeGreaterThanOrEqual(now.at(-1)!.score)

    const stats = await loadStats(store, TODAY)
    expect(stats.streak).toBeGreaterThanOrEqual(20)
    expect(stats.streak).toBeLessThanOrEqual(25) // the empty day 25 days ago breaks it
    expect(stats.totalDone).toBeGreaterThan(1500)
    expect(stats.heatmap).toHaveLength(371)
    expect(stats.heatmap.filter((c) => c.level > 0).length).toBeGreaterThan(100)
  })

  it('seeding twice changes nothing but clocks', async () => {
    const store = await openStore()
    await generateDemo(store, TODAY, NOW)
    const rows = await store.db.task.count()
    await generateDemo(store, TODAY, NOW)
    expect(await store.db.task.count()).toBe(rows)
    expect(DEMO_OPEN_TASK_COUNT).toBe(40)
  })

  it('clearDemo removes it from every view', async () => {
    const store = await openStore()
    const mine = await createTask(store, { title: 'Моя задача', date: TODAY })
    await generateDemo(store, TODAY, NOW)
    await clearDemo(store)

    const day = await loadDay(store, TODAY, NOW)
    expect(day.items.map((i) => i.id)).toEqual([mine])
    expect(await loadInbox(store, NOW)).toEqual([])
    expect(await loadRoutines(store, TODAY)).toEqual([])
    const stats = await loadStats(store, TODAY)
    expect(stats.totalDone).toBe(0)
    expect(await loadDay(store, '2026-08-01', NOW)).toMatchObject({ items: [] })
  })
})
