import { inject, type ComputedRef, type InjectionKey, type Ref } from 'vue'
import type { LocalDate, LocalDateTime, Settings } from '../core/types'
import type { NewTask } from '../db/actions'
import type { Store } from '../db/store'
import type { SyncClient, SyncStatus } from '../sync/client'

export type EditorState =
  | { kind: 'task'; id: string | null; defaults: Partial<NewTask> }
  | { kind: 'routine'; id: string | null }

export interface AppContext {
  store: Store
  sync: SyncClient
  syncStatus: Ref<SyncStatus>
  /** Local wall clock, refreshed every 30 s. */
  now: Ref<LocalDateTime>
  settings: Ref<Settings>
  today: ComputedRef<LocalDate>
  editor: Ref<EditorState | null>
  openTask(id?: string | null, defaults?: Partial<NewTask>): void
  openRoutine(id?: string | null): void
}

export const APP: InjectionKey<AppContext> = Symbol('app')

export function useApp(): AppContext {
  const ctx = inject(APP)
  if (!ctx) throw new Error('App context is not provided')
  return ctx
}
