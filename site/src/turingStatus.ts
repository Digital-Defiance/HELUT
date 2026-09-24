/** Poll Digital-Defiance/HELUT-turing-status for a live ttyd broadcast. */

export const TURING_TERMINAL_URL = 'https://turing.helut.org'

/**
 * GitHub Contents API (not raw.githubusercontent.com).
 * Raw is Fastly-cached for minutes and ignores ?t= busting; the API returns
 * the current blob quickly. Repo must be public. Unauthenticated limit is
 * 60 req/hr/IP — keep poll interval at or above ~90s.
 */
export const TURING_STATUS_URL =
  'https://api.github.com/repos/Digital-Defiance/HELUT-turing-status/contents/status.json?ref=main'

/** If lastStatus is older than this while live=true, treat as stale (crash without off). */
export const TURING_STATUS_MAX_AGE_SEC = 2 * 60 * 60

export const TURING_STATUS_POLL_MS = 90_000

export type TuringStatusJson = {
  live: boolean
  lastStatus: number
}

export type TuringPresence = 'checking' | 'live' | 'offline'

export function parseTuringStatus(data: unknown): TuringStatusJson | null {
  if (!data || typeof data !== 'object') return null
  const row = data as Record<string, unknown>
  if (typeof row.live !== 'boolean') return null
  if (typeof row.lastStatus !== 'number' || !Number.isFinite(row.lastStatus)) return null
  return { live: row.live, lastStatus: row.lastStatus }
}

/** live=true and lastStatus is a recent unix timestamp (not -1 / ancient). */
export function isTuringLive(
  status: TuringStatusJson | null,
  nowSec: number = Math.floor(Date.now() / 1000),
  maxAgeSec: number = TURING_STATUS_MAX_AGE_SEC,
): boolean {
  if (!status?.live) return false
  if (status.lastStatus < 0) return false
  return nowSec - status.lastStatus <= maxAgeSec
}

export async function fetchTuringStatus(
  url: string = TURING_STATUS_URL,
): Promise<TuringStatusJson | null> {
  const res = await fetch(url, {
    cache: 'no-store',
    headers: {
      Accept: 'application/vnd.github.raw+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  })
  if (!res.ok) return null
  return parseTuringStatus(await res.json())
}
