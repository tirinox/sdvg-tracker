// Runs against a real backend: `make test-live` starts one on a throwaway database.
import { afterAll, describe, expect, it } from 'vitest'
import { routineCheckId } from '../core/ids'
import {
  completeTask,
  createRoutine,
  createTask,
  runRollover,
  setRoutineCheck,
  updateTask,
} from '../db/actions'
import { Store } from '../db/store'
import { SyncClient, saveSyncConfig } from './client'

const baseUrl = process.env.SDVG_LIVE_URL
const token = process.env.SDVG_LIVE_TOKEN ?? ''
const TODAY = '2026-09-22'
const stores: Store[] = []

async function device() {
  const store = await Store.open(crypto.randomUUID())
  stores.push(store)
  await saveSyncConfig(store, { baseUrl: baseUrl!, token })
  return { store, client: new SyncClient(store) }
}

async function snapshot(store: Store) {
  const out: Record<string, unknown> = {}
  for (const table of store.entityTables()) {
    out[table.name] = (await table.toArray()).sort((a, b) => a.id.localeCompare(b.id))
  }
  return out
}

afterAll(() => {
  for (const s of stores) s.close()
})

describe.skipIf(!baseUrl)('live backend', () => {
  it('two devices converge through the real server', async () => {
    const web = await device()
    const phone = await device()

    const task = await createTask(web.store, { title: 'Починить коляску', date: '2026-09-20' })
    const lunch = await createRoutine(web.store, { title: 'Пообедать', emoji: '🍲' }, TODAY)
    await web.client.sync()
    expect(web.client.status).toMatchObject({ state: 'idle', error: null })
    await phone.client.sync()

    // Offline on both: rollover twice, lunch marked twice, different fields edited.
    await runRollover(web.store, TODAY)
    await runRollover(phone.store, TODAY)
    await setRoutineCheck(web.store, lunch, TODAY, 'done')
    await setRoutineCheck(phone.store, lunch, TODAY, 'done')
    await updateTask(phone.store, task, { title: 'Починить колесо коляски' })
    await completeTask(web.store, task, TODAY)

    await web.client.sync()
    await phone.client.sync()
    await web.client.sync()

    expect(phone.client.status.state).toBe('idle')
    expect(await snapshot(web.store)).toEqual(await snapshot(phone.store))
    expect(await web.store.get('task', task)).toMatchObject({
      title: 'Починить колесо коляски',
      done_on: TODAY,
      date: TODAY,
    })
    expect(await web.store.db.task_move.count()).toBe(2)
    expect(await web.store.db.routine_check.count()).toBe(1)
    expect(await web.store.get('routine_check', routineCheckId(lunch, TODAY))).toMatchObject({
      status: 'done',
    })
    expect(await web.store.db.rejected.count()).toBe(0)
  })

  it('rejects a wrong token without losing data', async () => {
    const store = await Store.open(crypto.randomUUID())
    stores.push(store)
    await saveSyncConfig(store, { baseUrl: baseUrl!, token: 'wrong-token-0000000000' })
    const client = new SyncClient(store)
    await createTask(store, { title: 'a' })
    await client.sync()
    expect(client.status.state).toBe('unauthorized')
    expect(await store.db.outbox.count()).toBe(1)
  })
})
