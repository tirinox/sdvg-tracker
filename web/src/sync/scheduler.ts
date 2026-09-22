import type { Store } from '../db/store'
import type { SyncClient } from './client'

export interface SchedulerOptions {
  intervalMs?: number
  debounceMs?: number
  target?: Pick<Window, 'addEventListener' | 'removeEventListener'> & {
    document?: { visibilityState: string }
  }
}

/**
 * Sync triggers: start, local writes (debounced), tab becoming visible, network back online,
 * and a periodic timer. Returns a stop function.
 */
export function startSyncScheduler(
  client: SyncClient,
  store: Store,
  { intervalMs = 60_000, debounceMs = 2_000, target = window }: SchedulerOptions = {},
): () => void {
  let debounce: ReturnType<typeof setTimeout> | undefined
  const run = () => void client.sync()

  const offWrite = store.onLocalWrite(() => {
    clearTimeout(debounce)
    debounce = setTimeout(run, debounceMs)
  })
  const onVisible = () => {
    if (target.document?.visibilityState !== 'hidden') run()
  }
  target.addEventListener('visibilitychange', onVisible)
  target.addEventListener('online', run)
  const timer = setInterval(run, intervalMs)
  run()

  return () => {
    offWrite()
    clearTimeout(debounce)
    clearInterval(timer)
    target.removeEventListener('visibilitychange', onVisible)
    target.removeEventListener('online', run)
  }
}
