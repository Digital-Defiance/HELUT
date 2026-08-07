import { Link } from 'react-router-dom'

export function HomePage() {
  return (
    <main>
      <section className="hero hero--home">
        <div className="hero-plane" aria-hidden="true" />
        <div className="shell hero-copy">
          <div className="brand-mark">
            HE<em>LUT</em>
          </div>
          <div className="hero-readable">
            <h1>Turning Silicon into Mathematics</h1>
            <p className="lede">
              Imagine taking the physical blueprints of a computer chip, translating its wiring into pure mathematical equations, and running it at lightning speed on Apple Silicon. That is HELUT. My ultimate destination is real homomorphic encryption—computing on data while it remains completely secure. But to prove my engine can carry that cryptographic weight, I aimed it at an 80-year-old unbroken WWII ghost.
            </p>
            <div className="cta-row">
              <Link className="btn" to="/stack">
                How the engine works
              </Link>
              <Link className="btn ghost" to="/enigma">
                The hunt for U-534
              </Link>
            </div>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Trajectory</div>
            <h2>From Mock-PBS to True Homomorphic Encryption</h2>
            <p>
              HELUT was not built to be an Enigma cracking tool. It is a systems prototype designed to evaluate real hardware netlists under homomorphic tensor arithmetic. I am currently using "mock" Programmable Bootstrapping (PBS) to prove that my datapath, batching mechanics, and logic gates can run at CPU-scale without collapsing.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Once the plumbing is perfected, I introduce true cryptographic noise budgets, actual Torus PBS, and key-switching. The Enigma campaign is just my ultimate stress test.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">01</span>
              <span>
                <strong>The Virtual Brain (Encrypted RISC-V)</strong> — I successfully booted a full RISC-V processor under mock encryption to prove my logic gates scale to the size of a real computer.
              </span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>
                <strong>The Parallel Searcher</strong> — A batched pattern matcher across thousands of streams simultaneously, proving my engine can handle overwhelming amounts of data in a single pass.
              </span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>
                <strong>The Blind Decision Tree</strong> — An exact non-linear classification circuit, proving I don't have to take floating-point shortcuts to make complex logical choices.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                <strong>The Welchman Bombe</strong> — The ultimate datapath test: weaponizing the engine to deterministically dismantle an unbroken 1945 message from a German U-boat.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </main>
  )
}
