import { afterEach, describe, expect, it, vi } from 'vitest'
import { completeTask, createTask, postponeTask, runRollover, updateTask } from '../db/actions'
import { Store } from '../db/store'
import { FakeServer } from '../test/fakeServer'
import { SyncClient, saveSyncConfig } from './client'
import { startSyncScheduler } from './scheduler'

const TODAY = '2026-09-22'
const stores: Store[] = []

async function device(server: FakeServer, batchSize?: number) {
  const store = await Store.open(crypto.randomUUID())
  stores.push(store)
  await saveSyncConfig(store, { baseUrl: '', token: server.token })
  const client = new SyncClient(store, { fetchFn: (...a) => server.fetch(...a), batchSize })
  return { store, client }
}

async function snapshot(store: Store) {
  const out: Record<string, unknown> = {}
  for (const table of store.entityTables()) {
    out[table.name] = (await table.toArray()).sort((a, b) => a.id.localeCompare(b.id))
  }
  return out
}

afterEach(() => {
  for (const s of stores.splice(0)) s.close()
})

describe('SyncClient', () => {
  it('is unconfigured without a token', async () => {
    const store = await Store.open(crypto.randomUUID())
    stores.push(store)
    const client = new SyncClient(store, { fetchFn: vi.fn() })
    await client.sync()
    expect(client.status.state).toBe('unconfigured')
  })

  it('two devices converge after offline edits', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const phone = await device(server)

    const id = await createTask(web.store, { title: 'Починить коляску', date: TODAY })
    await web.client.sync()
    await phone.client.sync()

    await updateTask(phone.store, id, { title: 'Починить колесо коляски' })
    await completeTask(web.store, id, TODAY)
    await web.client.sync()
    await phone.client.sync()
    await web.client.sync()

    expect(await snapshot(web.store)).toEqual(await snapshot(phone.store))
    expect(await web.store.get('task', id)).toMatchObject({
      title: 'Починить колесо коляски',
      done_on: TODAY,
    })
    expect(await web.store.db.outbox.count()).toBe(0)
    expect(web.client.status.state).toBe('idle')
  })

  it('double rollover on two devices counts each day once', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const phone = await device(server)
    const id = await createTask(web.store, { title: 'Висит', date: '2026-09-20' })
    await web.client.sync()
    await phone.client.sync()

    await runRollover(web.store, TODAY)
    await runRollover(phone.store, TODAY)
    await web.client.sync()
    await phone.client.sync()
    await web.client.sync()

    expect(await web.store.db.task_move.count()).toBe(2)
    expect(await snapshot(web.store)).toEqual(await snapshot(phone.store))
    expect(server.row('task', id)?.fields.date).toBe(TODAY)
  })

  it('a local write made while a sync is in flight is not lost', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const id = await createTask(web.store, { title: 'a', date: TODAY })
    server.beforeApply = async () => {
      server.beforeApply = async () => {}
      await updateTask(web.store, id, { title: 'b' })
    }
    // The write lands in the outbox after the batch was read; the same run sends it next round.
    await web.client.sync()
    expect(server.requests).toBe(2)
    expect(server.row('task', id)?.fields.title).toBe('b')
    expect(await web.store.db.outbox.count()).toBe(0)
  })

  it('offline keeps the outbox and resumes later', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'Офлайн', date: TODAY })
    server.down = true
    await web.client.sync()
    expect(web.client.status.state).toBe('offline')
    expect(await web.store.db.outbox.count()).toBe(1)

    server.down = false
    await web.client.sync()
    expect(web.client.status.state).toBe('idle')
    expect(server.size).toBe(1)
  })

  it('wrong token keeps the outbox', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'a' })
    server.token = 'rotated'
    await web.client.sync()
    expect(web.client.status.state).toBe('unauthorized')
    expect(await web.store.db.outbox.count()).toBe(1)
  })

  it('a rejected change is quarantined and the rest still syncs', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const good = await createTask(web.store, { title: 'Хорошая' })
    const bad = await createTask(web.store, { title: 'Плохая' })
    server.reject = (c) => c.id === bad
    await web.client.sync()

    expect(web.client.status.state).toBe('idle')
    expect(server.row('task', good)).toBeDefined()
    expect(server.row('task', bad)).toBeUndefined()
    const [rejected] = await web.store.db.rejected.toArray()
    expect(rejected).toMatchObject({ id: bad, error: 'changes[1]: rejected' })
  })

  it('pages through large pushes and pulls', async () => {
    const server = new FakeServer()
    const web = await device(server, 7)
    for (let i = 0; i < 30; i++) await createTask(web.store, { title: `Задача ${i}`, date: TODAY })
    await web.client.sync()
    expect(server.size).toBe(30)

    const phone = await device(server, 4)
    await phone.client.sync()
    expect(await snapshot(phone.store)).toEqual(await snapshot(web.store))
  })

  it('pauses on a reset server and sends it nothing', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'Старая', date: TODAY })
    await web.client.sync()

    server.reset()
    await createTask(web.store, { title: 'Новая', date: TODAY })
    await web.client.sync()
    expect(web.client.status.state).toBe('server_changed')
    expect(web.client.status.serverChange).toEqual({
      kind: 'changed',
      serverId: server.serverId,
      server: { task: 0, routine: 0 },
      local: { task: 2, routine: 0 },
    })
    expect(server.size).toBe(0)
    expect(await web.store.db.outbox.count()).toBe(1)

    const seen: (string | undefined)[] = []
    web.client.onStatus((st) => seen.push(st.serverChange?.serverId))
    await web.client.sync() // asks again, still sends nothing; the question never disappears
    expect(web.client.status.state).toBe('server_changed')
    expect(seen).toEqual([server.serverId, server.serverId])
    expect(server.size).toBe(0)
  })

  it('takes the server data as it is', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'Тестовая', date: TODAY })
    await web.client.sync()

    server.reset()
    const phone = await device(server)
    const real = await createTask(phone.store, { title: 'Настоящая', date: TODAY })
    await phone.client.sync()
    await web.client.sync()
    expect(web.client.status.state).toBe('server_changed')

    await web.client.takeServerData()
    expect(web.client.status.state).toBe('idle')
    expect((await web.store.rows('task')).map((r) => r.id)).toEqual([real])
    expect(await snapshot(web.store)).toEqual(await snapshot(phone.store))
    expect(server.size).toBe(1)
  })

  it('merges this device into the new data set when asked', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const id = await createTask(web.store, { title: 'Починить коляску', date: TODAY })
    await postponeTask(web.store, id, TODAY)
    await web.client.sync()

    server.reset()
    await web.client.sync()
    await web.client.mergeWithServer()
    expect(web.client.status.state).toBe('idle')
    expect(server.size).toBe(2)

    const phone = await device(server)
    await phone.client.sync()
    expect(await snapshot(phone.store)).toEqual(await snapshot(web.store))
  })

  it('asks on the first connection when both sides have data', async () => {
    const server = new FakeServer()
    const phone = await device(server)
    await createTask(phone.store, { title: 'С телефона', date: TODAY })
    await phone.client.sync()

    const web = await device(server)
    await createTask(web.store, { title: 'Из браузера', date: TODAY })
    await web.client.sync()
    expect(web.client.status.state).toBe('server_changed')
    expect(web.client.status.serverChange).toMatchObject({ kind: 'first', server: { task: 1 }, local: { task: 1 } })
    expect(server.size).toBe(1)

    await web.client.mergeWithServer()
    await phone.client.sync()
    expect(server.size).toBe(2)
    expect(await snapshot(web.store)).toEqual(await snapshot(phone.store))
  })

  it('connects to an empty server without asking', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'Первая', date: TODAY })
    await web.client.sync()
    expect(web.client.status.state).toBe('idle')
    expect(server.size).toBe(1)
  })

  it('gives a restored server back what its backup lacks', async () => {
    const server = new FakeServer()
    const web = await device(server)
    const phone = await device(server)
    const id = await createTask(web.store, { title: 'Починить коляску', date: TODAY })
    await web.client.sync()
    await phone.client.sync()
    const backup = server.backup()

    await updateTask(phone.store, id, { title: 'После бэкапа' })
    const later = await createTask(phone.store, { title: 'Тоже после', date: TODAY })
    await phone.client.sync()
    await web.client.sync()

    server.restore(backup)
    await web.client.sync() // rewind: sends every row it has
    expect(web.client.status.state).toBe('idle')
    expect(server.row('task', id)?.fields.title).toBe('После бэкапа')
    expect(server.row('task', later)).toBeDefined()

    await phone.client.sync()
    expect(await snapshot(phone.store)).toEqual(await snapshot(web.store))
    const fresh = await device(server)
    await fresh.client.sync()
    expect(await snapshot(fresh.store)).toEqual(await snapshot(web.store))
  })

  it('concurrent sync calls share one run plus one follow-up', async () => {
    const server = new FakeServer()
    const web = await device(server)
    await createTask(web.store, { title: 'a' })
    await Promise.all([web.client.sync(), web.client.sync(), web.client.sync()])
    expect(server.requests).toBe(2)
  })
})

describe('scheduler', () => {
  it('syncs on start, debounces local writes, reacts to online', async () => {
    // fake-indexeddb schedules with setImmediate, keep that real.
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval'] })
    try {
      const server = new FakeServer()
      const web = await device(server)
      const spy = vi.spyOn(web.client, 'sync').mockResolvedValue()
      const target = new EventTarget() as EventTarget & { document?: { visibilityState: string } }
      const stop = startSyncScheduler(web.client, web.store, {
        target,
        debounceMs: 2000,
        intervalMs: 60_000,
      })
      expect(spy).toHaveBeenCalledTimes(1)

      await createTask(web.store, { title: 'a' })
      await createTask(web.store, { title: 'b' })
      vi.advanceTimersByTime(1999)
      expect(spy).toHaveBeenCalledTimes(1)
      vi.advanceTimersByTime(1)
      expect(spy).toHaveBeenCalledTimes(2)

      target.dispatchEvent(new Event('online'))
      expect(spy).toHaveBeenCalledTimes(3)
      vi.advanceTimersByTime(60_000)
      expect(spy).toHaveBeenCalledTimes(4)

      stop()
      target.dispatchEvent(new Event('online'))
      vi.advanceTimersByTime(120_000)
      expect(spy).toHaveBeenCalledTimes(4)
    } finally {
      vi.useRealTimers()
    }
  })
})
