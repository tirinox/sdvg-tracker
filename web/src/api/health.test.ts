import { describe, expect, it, vi } from 'vitest'
import { fetchServerStatus } from './health'

describe('fetchServerStatus', () => {
  it('reports online with api version', async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ status: 'ok', api_version: 1 }), { status: 200 }),
    )
    expect(await fetchServerStatus(fetchFn)).toEqual({ online: true, apiVersion: 1 })
    expect(fetchFn).toHaveBeenCalledWith('/api/health', expect.anything())
  })

  it('reports offline on HTTP error', async () => {
    const fetchFn = vi.fn().mockResolvedValue(new Response('', { status: 502 }))
    expect(await fetchServerStatus(fetchFn)).toEqual({ online: false })
  })

  it('reports offline when the network fails', async () => {
    const fetchFn = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'))
    expect(await fetchServerStatus(fetchFn)).toEqual({ online: false })
  })
})
