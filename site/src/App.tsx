import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { HomePage } from './pages/HomePage'
import { StackPage } from './pages/StackPage'
import { AppsPage } from './pages/AppsPage'
import { EnigmaPage } from './pages/EnigmaPage'
import { Enigma256Page } from './pages/Enigma256Page'
import { Enigma256JournalPage } from './pages/Enigma256JournalPage'
import { JournalPage } from './pages/JournalPage'
import { MuleinBoardPage } from './pages/MuleinBoardPage'
import { ProjectsIndexPage } from './pages/ProjectsIndexPage'
import { ProjectHubPage } from './pages/ProjectHubPage'
import {
  DifferentiableHardwareJournalPage,
  DifferentiableHardwareParadigmPage,
} from './pages/DifferentiableHardwarePages'
import {
  PolymorphicCiphersJournalPage,
  PolymorphicRedBluePage,
} from './pages/PolymorphicCiphersPages'
import { QueuedProjectJournalPage } from './pages/QueuedProjectJournalPage'
import { NetlistFheJournalPage } from './pages/NetlistFheJournalPage'

function Nav() {
  return (
    <header className="topnav">
      <div className="shell">
        <NavLink to="/" className="brand" end>
          HE<span>LÜT</span>
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
              <NavLink to="/projects">Projects</NavLink>
            </li>
            <li>
              <NavLink to="/enigma">Enigma</NavLink>
            </li>
            <li>
              <NavLink to="/projects/p1030680/journal">Nazi Blaster 9000</NavLink>
            </li>
            <li>
              <NavLink to="/projects/p1030680/mulein-board">Mulein Board</NavLink>
            </li>
            <li>
              <NavLink to="/projects/e256">E256</NavLink>
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
          {' · '}
          <a href="https://github.com/Digital-Defiance/HELUT/blob/main/SECURITY.md">Security</a>
          {' · '}
          <a href="https://github.com/Digital-Defiance/HELUT/blob/main/AI_DISCLOSURE.md">
            AI disclosure
          </a>
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

        <Route path="/projects" element={<ProjectsIndexPage />} />
        <Route path="/projects/:slug" element={<ProjectHubPage />} />
        <Route path="/projects/p1030680/journal" element={<JournalPage />} />
        <Route
          path="/projects/p1030680/mulein-board"
          element={<MuleinBoardPage />}
        />
        <Route path="/projects/netlist-fhe/journal" element={<NetlistFheJournalPage />} />
        <Route path="/projects/e256/design" element={<Enigma256Page />} />
        <Route path="/projects/e256/journal" element={<Enigma256JournalPage />} />
        <Route
          path="/projects/differentiable-hardware/journal"
          element={<DifferentiableHardwareJournalPage />}
        />
        <Route
          path="/projects/differentiable-hardware/paradigm"
          element={<DifferentiableHardwareParadigmPage />}
        />
        <Route
          path="/projects/polymorphic-ciphers/journal"
          element={<PolymorphicCiphersJournalPage />}
        />
        <Route
          path="/projects/polymorphic-ciphers/red-blue"
          element={<PolymorphicRedBluePage />}
        />
        <Route path="/projects/:slug/journal" element={<QueuedProjectJournalPage />} />

        {/* Legacy aliases */}
        <Route path="/journal" element={<Navigate to="/projects/p1030680/journal" replace />} />
        <Route path="/e256" element={<Navigate to="/projects/e256/design" replace />} />
        <Route path="/enigma-256" element={<Navigate to="/projects/e256/design" replace />} />
      </Routes>
      <Footer />
    </>
  )
}
