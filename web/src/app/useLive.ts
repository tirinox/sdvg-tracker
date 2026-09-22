import Dexie from 'dexie'
import { onScopeDispose, shallowRef, watch, type Ref, type WatchSource } from 'vue'

/**
 * A ref that follows the local database: the query re-runs after any write (in this tab or
 * another, via Dexie's 'storagemutated' event) and when any of `deps` change.
 *
 * Deliberately coarse instead of Dexie liveQuery: view models call several async helpers and
 * liveQuery loses track of reads across native awaits, silently missing updates. Re-running a
 * whole view model takes a few tens of milliseconds at this data size.
 */
export function useLive<T>(query: () => Promise<T>, initial: T, deps: WatchSource[] = []): Ref<T> {
  const result = shallowRef(initial) as Ref<T>
  let running = false
  let dirty = false
  let disposed = false

  const run = async () => {
    if (running) {
      dirty = true
      return
    }
    running = true
    try {
      do {
        dirty = false
        const value = await query()
        if (!disposed && !dirty) result.value = value
      } while (dirty && !disposed)
    } catch (e) {
      console.error('live query failed', e)
    } finally {
      running = false
    }
  }

  const onMutated = () => void run()
  Dexie.on('storagemutated', onMutated)
  watch(deps, run, { immediate: true })
  onScopeDispose(() => {
    disposed = true
    Dexie.on('storagemutated').unsubscribe(onMutated)
  })
  return result
}
