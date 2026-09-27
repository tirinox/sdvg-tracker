import { inject, type ComputedRef, type InjectionKey, type Ref } from 'vue'
import type { LocalDate, LocalDateTime, Settings } from '../core/types'
import type { NewTask } from '../db/actions'
import type { Store } from '../db/store'
import type { CelebrationLevel } from '../domain/tasks'
import type { SyncClient, SyncStatus } from '../sync/client'

export type EditorState =
  | { kind: 'task'; id: string | null; defaults: Partial<NewTask> }
  | { kind: 'routine'; id: string | null }

/** A task just marked done after postpones; see celebrationLevel. */
export interface Celebration {
  id: number
  level: Exclude<CelebrationLevel, 0>
  moves: number
  /** Viewport point the confetti bursts from: the check button. */
  x: number
  y: number
}

export interface AppContext {
  store: Store
  sync: SyncClient
  syncStatus: Ref<SyncStatus>
  /** Local wall clock, refreshed at the start of every minute. */
  now: Ref<LocalDateTime>
  settings: Ref<Settings>
  today: ComputedRef<LocalDate>
  editor: Ref<EditorState | null>
  celebration: Ref<Celebration | null>
  openTask(id?: string | null, defaults?: Partial<NewTask>): void
  openRoutine(id?: string | null): void
  celebrate(c: Omit<Celebration, 'id'>): void
}

export const APP: InjectionKey<AppContext> = Symbol('app')

export function useApp(): AppContext {
  const ctx = inject(APP)
  if (!ctx) throw new Error('App context is not provided')
  return ctx
}
