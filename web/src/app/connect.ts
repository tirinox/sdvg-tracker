import type { Store } from '../db/store'
import { saveSyncConfig, type SyncClient } from '../sync/client'

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
