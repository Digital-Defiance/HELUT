import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

/** Shared shell for project journals that are not yet the full P1030680 ledger. */
export function ProjectJournalShell({
  kicker,
  title,
  lede,
  children,
  hubPath,
}: {
  kicker: string
  title: string
  lede: string
  children: ReactNode
  hubPath: string
}) {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">{kicker}</div>
            <h2>{title}</h2>
            <p className="lede">{lede}</p>
            <p style={{ marginTop: '1rem' }}>
              <Link to={hubPath}>← Project hub</Link>
            </p>
          </div>
        </div>
      </section>
      {children}
    </main>
  )
}
