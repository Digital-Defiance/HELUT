import { NavLink, Outlet } from 'react-router-dom'
import { enigmaPaths } from './paths'

const links: { to: string; label: string; end?: boolean }[] = [
  { to: enigmaPaths.hub, label: 'Overview', end: true },
  { to: enigmaPaths.message, label: 'P1030680' },
  { to: enigmaPaths.corpus, label: 'Corpus' },
  { to: enigmaPaths.journal, label: 'Journal' },
  { to: enigmaPaths.machine, label: 'Nazi Blaster 9000' },
  { to: enigmaPaths.mulein, label: 'Mulein Board' },
]

/** Layout for the historian Enigma wing. HELUT FHE pages do not render this. */
export function EnigmaLayout() {
  return (
    <>
      <nav className="enigma-subnav" aria-label="Enigma section">
        <div className="shell">
          <div className="enigma-subnav-kicker">Enigma · P1030680</div>
          <ul>
            {links.map((link) => (
              <li key={link.to}>
                <NavLink to={link.to} end={link.end}>
                  {link.label}
                </NavLink>
              </li>
            ))}
          </ul>
        </div>
      </nav>
      <Outlet />
    </>
  )
}
