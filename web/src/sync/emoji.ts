import { updateTask } from '../db/actions'
import type { Store } from '../db/store'
import { loadSyncConfig } from './client'

export interface EmojiSuggestions {
  /** Best first. */
  emoji: string[]
  /** The emoji to set without asking, or null: the server's model is not sure enough. */
  pick: string | null
}

const NONE: EmojiSuggestions = { emoji: [], pick: null }

/**
 * POST /api/suggest-emoji. Nothing on any failure: no server configured, offline, the model
 * still loading. Suggestions are a nicety, so there is no retry and no error state.
 */
export async function suggestEmoji(
  store: Store,
  text: string,
  { limit = 5, fetchFn = fetch }: { limit?: number; fetchFn?: typeof fetch } = {},
): Promise<EmojiSuggestions> {
  const title = text.trim().slice(0, 500)
  const config = await loadSyncConfig(store)
  if (!title || !config?.token) return NONE
  try {
    const resp = await fetchFn(`${config.baseUrl}/api/suggest-emoji`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${config.token}` },
      body: JSON.stringify({ text: title, limit }),
      signal: AbortSignal.timeout(5000),
    })
    if (!resp.ok) return NONE
    const body = (await resp.json()) as { suggestions: { emoji: string }[]; pick?: string | null }
    return { emoji: body.suggestions.map((s) => s.emoji), pick: body.pick ?? null }
  } catch {
    return NONE
  }
}

/**
 * A task created without an emoji gets the server's pick, unless one was set meanwhile
 * (here or, after a sync, on another device).
 */
export async function autoEmoji(
  store: Store,
  id: string,
  title: string,
  options: { fetchFn?: typeof fetch } = {},
): Promise<void> {
  const { pick } = await suggestEmoji(store, title, { limit: 1, ...options })
  if (!pick) return
  const task = await store.get('task', id)
  if (task && !task.emoji) await updateTask(store, id, { emoji: pick })
}
