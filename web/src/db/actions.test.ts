import { afterEach, describe, expect, it } from 'vitest'
import { routineCheckId, taskMoveId } from '../core/ids'
import {
  archiveRoutine,
  completeTask,
  createRoutine,
  createTask,
  deleteTask,
  editRoutine,
  moveCount,
  postponeTask,
  rescheduleTask,
  routinesOn,
  runRollover,
  setRoutineCheck,
  updateSettings,
  updateTask,
} from './actions'
import { Store } from './store'

const TODAY = '2026-09-22'
const stores: Store[] = []

async function openStore(name = crypto.randomUUID(), nowMs?: () => number): Promise<Store> {
  const store = await Store.open(name, nowMs)
  stores.push(store)
  return store
}

afterEach(() => {
  for (const s of stores.splice(0)) s.close()
})

describe('store', () => {
  it('writes go to the outbox with one clock per change', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Починить коляску', date: TODAY })
    const [entry] = await store.db.outbox.toArray()
    expect(entry).toMatchObject({ entity: 'task', id })
    expect(new Set(Object.values(entry!.clocks)).size).toBe(1)
    expect(Object.keys(entry!.clocks).sort()).toEqual(Object.keys(entry!.fields).sort())
  })

  it('remote changes are merged but not queued', async () => {
    const store = await openStore()
    await store.db.transaction('rw', store.syncTables(), () =>
      store.applyRemote([
        {
          entity: 'task',
          id: '0192f0a0-0000-7000-8000-000000000001',
          fields: { title: 'С сервера' },
          clocks: { title: '1790000000000-0000-bbbbbbbbbbbbbbbb' },
        },
      ]),
    )
    expect(await store.db.outbox.count()).toBe(0)
    expect((await store.get('task', '0192f0a0-0000-7000-8000-000000000001'))?.title).toBe('С сервера')
  })

  it('keeps node id and clock across reopen, even if the wall clock goes back', async () => {
    const name = crypto.randomUUID()
    const first = await openStore(name, () => 1_790_000_000_000)
    const id = await createTask(first, { title: 'a' })
    const firstClock = (await first.db.outbox.toArray())[0]!.clocks.title!
    first.close()

    const second = await openStore(name, () => 1_700_000_000_000)
    expect(second.nodeId).toBe(first.nodeId)
    await updateTask(second, id, { title: 'b' })
    const secondClock = (await second.db.outbox.toArray())[1]!.clocks.title!
    expect(secondClock > firstClock).toBe(true)
  })

  it('settings fall back to defaults', async () => {
    const store = await openStore()
    expect((await store.settings()).day_start_hour).toBe(4)
    await updateSettings(store, { day_start_hour: 5 })
    expect(await store.settings()).toMatchObject({ day_start_hour: 5, part_day_from: 12 })
  })
})

describe('tasks', () => {
  it('sort keys increase', async () => {
    const store = await openStore()
    const a = await createTask(store, { title: 'a' })
    const b = await createTask(store, { title: 'b' })
    expect((await store.get('task', a))!.sort_key < (await store.get('task', b))!.sort_key).toBe(true)
  })

  it('planning an inbox task sets first_date once', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Когда-нибудь' })
    await updateTask(store, id, { date: '2026-09-25' })
    await updateTask(store, id, { date: '2026-09-26' })
    expect(await store.get('task', id)).toMatchObject({ date: '2026-09-26', first_date: '2026-09-25' })
  })

  it('postpone to tomorrow records a manual move', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Починить коляску', date: TODAY })
    await postponeTask(store, id, TODAY)
    expect((await store.get('task', id))!.date).toBe('2026-09-23')
    expect(await store.get('task_move', taskMoveId(id, TODAY))).toMatchObject({
      from_date: TODAY,
      to_date: '2026-09-23',
      kind: 'manual',
    })
    await postponeTask(store, id, TODAY)
    expect((await store.get('task', id))!.date).toBe('2026-09-24')
    expect(await moveCount(store, id)).toBe(2)
  })

  it('moving a planned task later counts once; earlier or from inbox does not', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Отчёт', date: TODAY })
    await rescheduleTask(store, id, '2026-09-30', TODAY)
    expect(await moveCount(store, id)).toBe(1)
    await rescheduleTask(store, id, '2026-09-25', TODAY)
    expect(await moveCount(store, id)).toBe(1)
    expect((await store.get('task', id))!.date).toBe('2026-09-25')
    const inbox = await createTask(store, { title: 'Когда-нибудь' })
    await rescheduleTask(store, inbox, '2026-09-30', TODAY)
    expect(await moveCount(store, inbox)).toBe(0)
  })

  it('postponing an inbox task plans it without a move', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Когда-нибудь' })
    await postponeTask(store, id, TODAY)
    expect((await store.get('task', id))!.date).toBe('2026-09-23')
    expect(await moveCount(store, id)).toBe(0)
  })

  it('rollover counts every missed day and is idempotent', async () => {
    const store = await openStore()
    const open = await createTask(store, { title: 'Висит', date: '2026-09-19' })
    const done = await createTask(store, { title: 'Сделано', date: '2026-09-19' })
    const gone = await createTask(store, { title: 'Удалено', date: '2026-09-19' })
    const inbox = await createTask(store, { title: 'Входящие' })
    await completeTask(store, done, '2026-09-19')
    await deleteTask(store, gone)

    expect(await runRollover(store, TODAY)).toBe(1)
    expect((await store.get('task', open))!.date).toBe(TODAY)
    expect(await moveCount(store, open)).toBe(3)
    for (const id of [done, gone, inbox]) expect(await moveCount(store, id)).toBe(0)

    const queued = await store.db.outbox.count()
    expect(await runRollover(store, TODAY)).toBe(0)
    expect(await store.db.outbox.count()).toBe(queued)
  })
})

describe('routines', () => {
  const titleOn = async (store: Store, routineId: string, date: string) =>
    (await routinesOn(store, date)).get(routineId)?.title

  it('edits apply from today when today is not marked yet', async () => {
    const store = await openStore()
    const id = await createRoutine(store, { title: 'Пообедать' }, '2026-09-20')
    await editRoutine(store, id, { title: 'Пообедать без телефона' }, TODAY)
    expect(await titleOn(store, id, '2026-09-21')).toBe('Пообедать')
    expect(await titleOn(store, id, TODAY)).toBe('Пообедать без телефона')
  })

  it('edits apply from tomorrow when today is already marked', async () => {
    const store = await openStore()
    const id = await createRoutine(store, { title: 'Пообедать' }, '2026-09-20')
    await setRoutineCheck(store, id, TODAY, 'done')
    await editRoutine(store, id, { title: 'Пообедать без телефона' }, TODAY)
    expect(await titleOn(store, id, TODAY)).toBe('Пообедать')
    expect(await titleOn(store, id, '2026-09-23')).toBe('Пообедать без телефона')
  })

  it('archiving keeps history', async () => {
    const store = await openStore()
    const id = await createRoutine(store, { title: 'Принять душ' }, '2026-09-20')
    await archiveRoutine(store, id, TODAY)
    expect(await titleOn(store, id, '2026-09-21')).toBe('Принять душ')
    expect(await titleOn(store, id, TODAY)).toBeUndefined()
  })

  it('weekdays limit the schedule', async () => {
    const store = await openStore()
    const id = await createRoutine(store, { title: 'Спортзал', weekdays: 0b0010101 }, '2026-09-20')
    expect(await titleOn(store, id, '2026-09-21')).toBe('Спортзал') // Monday
    expect(await titleOn(store, id, TODAY)).toBeUndefined() // Tuesday
  })

  it('marking twice keeps one row with a snapshot', async () => {
    const store = await openStore()
    const id = await createRoutine(store, { title: 'Пообедать', emoji: '🍲' }, TODAY)
    await setRoutineCheck(store, id, TODAY, 'done')
    await setRoutineCheck(store, id, TODAY, 'skipped')
    expect(await store.db.routine_check.count()).toBe(1)
    expect(await store.get('routine_check', routineCheckId(id, TODAY))).toMatchObject({
      status: 'skipped',
      done_at: null,
      snapshot: { title: 'Пообедать', emoji: '🍲' },
    })
  })
})
