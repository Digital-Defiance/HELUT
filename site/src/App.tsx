import { NavLink, Route, Routes } from 'react-router-dom'
import { HomePage } from './pages/HomePage'
import { StackPage } from './pages/StackPage'
import { AppsPage } from './pages/AppsPage'
import { EnigmaPage } from './pages/EnigmaPage'
import { JournalPage } from './pages/JournalPage'

function Nav() {
  return (
    <header className="topnav">
      <div className="shell">
        <NavLink to="/" className="brand" end>
          HE<span>LUT</span>
        </NavLink>
        <nav>
          <ul className="nav-links">
            <li>
              <NavLink to="/stack">The stack</NavLink>
            </li>
            <li>
              <NavLink to="/apps">Applications</NavLink>
            </li>
            <li>
              <NavLink to="/enigma">Enigma</NavLink>
            </li>
            <li>
              <NavLink to="/journal">Turing Complete</NavLink>
            </li>
            <li>
              <a
                href="https://github.com/Digital-Defiance/HELUT"
                target="_blank"
                rel="noreferrer"
              >
                GitHub
              </a>
            </li>
          </ul>
        </nav>
      </div>
    </header>
  )
}

function Footer() {
  return (
    <footer className="site-footer">
      <div className="shell">
        <div>
          © 2026 Digital Defiance · MIT License ·{' '}
          <a href="https://github.com/Digital-Defiance/HELUT">Source</a>
        </div>
        <div className="mono">Homomorphic Edge Look-Up Tensors</div>
      </div>
    </footer>
  )
}

export default function App() {
  return (
    <>
      <Nav />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/stack" element={<StackPage />} />
        <Route path="/apps" element={<AppsPage />} />
        <Route path="/enigma" element={<EnigmaPage />} />
        <Route path="/journal" element={<JournalPage />} />
      </Routes>
      <Footer />
    </>
  )
}
