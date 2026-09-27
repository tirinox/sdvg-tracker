import { afterEach, describe, expect, it, vi } from 'vitest'
import { createTask, updateTask } from '../db/actions'
import { Store } from '../db/store'
import { saveSyncConfig } from './client'
import { autoEmoji, suggestEmoji } from './emoji'

const stores: Store[] = []

async function openStore(configured = true) {
  const store = await Store.open(crypto.randomUUID())
  stores.push(store)
  if (configured) await saveSyncConfig(store, { baseUrl: 'https://sdvg.test', token: 'tok' })
  return store
}

function answer(pick: string | null, ...emoji: string[]) {
  return vi.fn<typeof fetch>(async () =>
    Response.json({ suggestions: emoji.map((e, i) => ({ emoji: e, score: 0.95 - i / 100 })), pick }),
  )
}

afterEach(() => {
  for (const s of stores.splice(0)) s.close()
})

describe('suggestEmoji', () => {
  it('asks the configured server, title in the body', async () => {
    const store = await openStore()
    const fetchFn = answer('🦷', '🦷', '🩺')
    expect(await suggestEmoji(store, '  Записаться к стоматологу ', { fetchFn })).toEqual({
      emoji: ['🦷', '🩺'],
      pick: '🦷',
    })
    const [url, init] = fetchFn.mock.calls[0]
    expect(url).toBe('https://sdvg.test/api/suggest-emoji')
    expect(init?.method).toBe('POST')
    expect((init?.headers as Record<string, string>).Authorization).toBe('Bearer tok')
    expect(JSON.parse(String(init?.body))).toEqual({ text: 'Записаться к стоматологу', limit: 5 })
  })

  it('stays quiet without a server or a title', async () => {
    const fetchFn = answer('🦷', '🦷')
    expect(await suggestEmoji(await openStore(false), 'Стоматолог', { fetchFn })).toEqual({ emoji: [], pick: null })
    expect(await suggestEmoji(await openStore(), '   ', { fetchFn })).toEqual({ emoji: [], pick: null })
    expect(fetchFn).not.toHaveBeenCalled()
  })

  it('treats a loading model or no network as no suggestions', async () => {
    const store = await openStore()
    const loading = vi.fn<typeof fetch>(async () => Response.json({ detail: { error: 'emoji_loading' } }, { status: 503 }))
    const offline = vi.fn<typeof fetch>(async () => {
      throw new TypeError('Failed to fetch')
    })
    expect(await suggestEmoji(store, 'Стоматолог', { fetchFn: loading })).toEqual({ emoji: [], pick: null })
    expect(await suggestEmoji(store, 'Стоматолог', { fetchFn: offline })).toEqual({ emoji: [], pick: null })
  })
})

describe('autoEmoji', () => {
  it("sets the server's pick on a task without an emoji", async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Выгулять собаку', date: null })
    await autoEmoji(store, id, 'Выгулять собаку', { fetchFn: answer('🐕', '🐕', '🚶') })
    expect((await store.get('task', id))?.emoji).toBe('🐕')
  })

  it('leaves the task alone when the model is unsure', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Кружки клеить на стулья', date: null })
    await autoEmoji(store, id, 'Кружки клеить на стулья', { fetchFn: answer(null, '🛏️') })
    expect((await store.get('task', id))?.emoji).toBeNull()
  })

  it('keeps an emoji chosen while the server was answering', async () => {
    const store = await openStore()
    const id = await createTask(store, { title: 'Выгулять собаку', date: null })
    const fetchFn = vi.fn<typeof fetch>(async () => {
      await updateTask(store, id, { emoji: '🦮' })
      return Response.json({ suggestions: [{ emoji: '🐕', score: 0.99 }], pick: '🐕' })
    })
    await autoEmoji(store, id, 'Выгулять собаку', { fetchFn })
    expect((await store.get('task', id))?.emoji).toBe('🦮')
  })
})
