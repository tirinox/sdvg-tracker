import { afterEach, describe, expect, it, vi } from 'vitest'
import { Store } from '../db/store'
import { loadSyncConfig, SyncClient } from '../sync/client'
import { connectServer, isOnboardingDone, skipOnboarding } from './connect'

const stores: Store[] = []

async function setup(response: Response | Error) {
  const store = await Store.open(crypto.randomUUID())
  stores.push(store)
  const sync = new SyncClient(store, { fetchFn: vi.fn().mockRejectedValue(new TypeError('offline')) })
  vi.stubGlobal('fetch', vi.fn(async () => {
    if (response instanceof Error) throw response
    return response
  }))
  return { store, sync }
}

afterEach(() => {
  vi.unstubAllGlobals()
  for (const s of stores.splice(0)) s.close()
})

describe('connectServer', () => {
  it('saves a working token and finishes onboarding', async () => {
    const { store, sync } = await setup(new Response('{"ok":true}', { status: 200 }))
    expect(await connectServer(store, sync, ' http://host:8420/ ', ' secret-token ')).toBe('ok')
    expect(await loadSyncConfig(store)).toEqual({ baseUrl: 'http://host:8420', token: 'secret-token' })
    expect(await isOnboardingDone(store)).toBe(true)
    await sync.sync() // let the sync it started finish before the store closes
  })

  it('reports a wrong token and saves nothing', async () => {
    const { store, sync } = await setup(new Response('', { status: 401 }))
    expect(await connectServer(store, sync, '', 'nope')).toBe('bad-token')
    expect(await loadSyncConfig(store)).toBeNull()
    expect(await isOnboardingDone(store)).toBe(false)
  })

  it('reports an unreachable server', async () => {
    const { store, sync } = await setup(new TypeError('Failed to fetch'))
    expect(await connectServer(store, sync, '', 'x')).toBe('offline')
  })

  it('skipping onboarding is remembered', async () => {
    const { store } = await setup(new Response(''))
    await skipOnboarding(store)
    expect(await isOnboardingDone(store)).toBe(true)
  })
})
