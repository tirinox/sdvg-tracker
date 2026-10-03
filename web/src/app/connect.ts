import type { Store } from '../db/store'
import { saveSyncConfig, type SyncClient, type SyncState } from '../sync/client'
import { tr } from './i18n'

export type ConnectResult = 'ok' | 'bad-token' | 'offline'

const ONBOARDING_DONE = 'onboarding_done'

/** Checks the token against the server; on success saves it and starts a sync. */
export async function connectServer(
  store: Store,
  sync: SyncClient,
  baseUrl: string,
  token: string,
): Promise<ConnectResult> {
  const url = baseUrl.trim().replace(/\/$/, '')
  let result: ConnectResult
  try {
    const resp = await fetch(`${url}/api/auth/check`, {
      headers: { Authorization: `Bearer ${token.trim()}` },
      signal: AbortSignal.timeout(5000),
    })
    result = resp.ok ? 'ok' : resp.status === 401 ? 'bad-token' : 'offline'
  } catch {
    result = 'offline'
  }
  if (result === 'ok') {
    await saveSyncConfig(store, { baseUrl: url, token: token.trim() })
    await store.setMeta(ONBOARDING_DONE, true)
    void sync.sync()
  }
  return result
}

export async function isOnboardingDone(store: Store): Promise<boolean> {
  return Boolean(await store.getMeta<boolean>(ONBOARDING_DONE))
}

/** "Continue without a server": do not ask again on this device. */
export async function skipOnboarding(store: Store): Promise<void> {
  await store.setMeta(ONBOARDING_DONE, true)
}

/** The sync state in words, for the settings. */
export function syncStateText(state: SyncState): string {
  const texts: Record<SyncState, string> = {
    idle: tr('синхронизировано', 'synced'),
    syncing: tr('синхронизация…', 'syncing…'),
    offline: tr('сервер недоступен — работаем офлайн', 'server unreachable — working offline'),
    unauthorized: tr('неверный токен', 'wrong token'),
    unconfigured: tr('сервер не подключён', 'no server connected'),
    server_changed: tr('на паузе: данные на сервере сменились', 'paused: the data on the server changed'),
    error: tr('ошибка', 'error'),
  }
  return texts[state]
}
