import { useEffect, useState } from 'react'
import {
  TURING_STATUS_POLL_MS,
  TURING_TERMINAL_URL,
  fetchTuringStatus,
  isTuringLive,
  type TuringPresence,
} from './turingStatus'

/**
 * Status-strip tile: polls HELUT-turing-status and links to the live terminal when on.
 */
export function TuringLiveStat() {
  const [presence, setPresence] = useState<TuringPresence>('checking')

  useEffect(() => {
    let cancelled = false

    const tick = async () => {
      try {
        const status = await fetchTuringStatus()
        if (cancelled) return
        setPresence(isTuringLive(status) ? 'live' : 'offline')
      } catch {
        if (!cancelled) setPresence('offline')
      }
    }

    void tick()
    const id = window.setInterval(() => void tick(), TURING_STATUS_POLL_MS)
    const onVis = () => {
      if (document.visibilityState === 'visible') void tick()
    }
    document.addEventListener('visibilitychange', onVis)

    return () => {
      cancelled = true
      window.clearInterval(id)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [])

  return (
    <div className="stat" aria-live="polite">
      <div className="label">Terminal</div>
      <div className="value">
        {presence === 'checking' && <span className="turing-muted">Checking…</span>}
        {presence === 'offline' && <span className="turing-muted">Offline</span>}
        {presence === 'live' && (
          <a
            className="turing-live-link"
            href={TURING_TERMINAL_URL}
            target="_blank"
            rel="noreferrer"
          >
            <em>Live</em>
            <span className="turing-live-hint"> · open</span>
          </a>
        )}
      </div>
    </div>
  )
}
