export type ServerStatus = { online: true; apiVersion: number } | { online: false }

const TIMEOUT_MS = 3000

export async function fetchServerStatus(fetchFn: typeof fetch = fetch): Promise<ServerStatus> {
  try {
    const resp = await fetchFn('/api/health', { signal: AbortSignal.timeout(TIMEOUT_MS) })
    if (!resp.ok) return { online: false }
    const body = await resp.json()
    return { online: true, apiVersion: body.api_version }
  } catch {
    return { online: false }
  }
}
