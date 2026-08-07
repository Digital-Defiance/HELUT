import { Navigate, Route, Routes } from 'react-router-dom'
import { HomePage } from './pages/HomePage'

function Nav() {
  return (
    <header className="topnav">
      <div className="shell">
        <a className="brand" href="/">
          HE<span>LÜT</span>
        </a>
        <nav>
          <ul className="nav-links">
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
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <Footer />
    </>
  )
}
