/** Poll Digital-Defiance/HELUT-turing-status for a live ttyd broadcast. */

export const TURING_TERMINAL_URL = 'https://turing.helut.org'

/** Raw JSON; cache-bust query is appended at fetch time. Repo must be public. */
export const TURING_STATUS_URL =
  'https://raw.githubusercontent.com/Digital-Defiance/HELUT-turing-status/main/status.json'

/** If lastStatus is older than this while live=true, treat as stale (crash without off). */
export const TURING_STATUS_MAX_AGE_SEC = 2 * 60 * 60

export const TURING_STATUS_POLL_MS = 60_000

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
  const bust = `${url}${url.includes('?') ? '&' : '?'}t=${Date.now()}`
  const res = await fetch(bust, { cache: 'no-store' })
  if (!res.ok) return null
  return parseTuringStatus(await res.json())
}
