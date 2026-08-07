import { Link } from 'react-router-dom'

export function StackPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Engine Room</div>
            <h2>A datapath for encrypted-shaped circuit evaluation</h2>
            <p>
              HELUT compiles Yosys gate-level netlists into a single <code>MPSGraph</code> and evaluates every component as a dense matrix-vector product on Apple Silicon. I am translating the physical blueprints of a computer chip into pure math.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="prose">
            <p>
              The design deliberately avoids floating-point approximations. When you are dealing with cryptography, a single floating-point rounding error breaks the entire system. Instead, torus arithmetic is realized by native <code>UInt32</code> wraparound. Every calculation is perfectly, ruthlessly precise.
            </p>
            <p>
              Right now, the values in my Metal GPU path are <strong>mock torus polynomials</strong>—vectors shaped exactly like Fully Homomorphic Encryption (TFHE) ciphertexts, but without the final cryptographic noise. Think of it like testing a heavy race car on a dynamometer before putting it on the track. I am proving that massive, CPU-scale netlists can be successfully clocked on commodity silicon before I turn on the military-grade encryption.
            </p>
            <div className="note">
              Homomorphic follow-through is intentional. The mock-PBS path is industrial scaffolding for eventual real torus PBS and key-switching. The applications I have built already exercise the shapes that matter: wide logic fanout, state retention, and large parallel batches.
            </div>
          </div>

          <ul className="stack-list">
            <li>
              <span className="mono">LUT (Look-Up Table)</span>
              <span>
                <strong>The Logic Gates:</strong> Each Yosys <code>$lut</code> becomes one Toeplitz matvec (<code>N = 1024</code>). I convert the tiny decisions a computer makes into a massive, unified mathematical grid.
              </span>
            </li>
            <li>
              <span className="mono">DFF (D Flip-Flop)</span>
              <span>
                <strong>The Memory:</strong> Sequential cells are clocked on the host with ping-pong state buffers. This keeps perfect track of time, allowing virtual circuits to "tick" forward through multi-tick boot loops.
              </span>
            </li>
            <li>
              <span className="mono">BATCH</span>
              <span>
                <strong>The Multiplier:</strong> Axis <code>B</code> allows for massive parallelism. I can run thousands of independent instances of the same circuit in a single <code>graph.run</code>.
              </span>
            </li>
            <li>
              <span className="mono">CORE</span>
              <span>
                <strong>The Foundation:</strong> <code>HELUTCore</code> is the general compiler. While the <code>helut</code> CLI currently leads with my Enigma attack, the core handles any standard netlist.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Roadmap</div>
            <h2>From mock PBS to real homomorphic evaluation</h2>
            <p>
              Today: an existence proof. Next: integrating strict noise budgets, key switching, and honest performance envelopes—without abandoning the netlist-first discipline that made my applications and the bombe possible.
            </p>
          </div>
          <div className="prose">
            <p>
              Deep technical specifications live in <code>paper/helut.tex</code>. Design progression maps through <code>PRD.md</code> → <code>phase-2.md</code> → <code>phase-3.md</code>.
            </p>
            <p>
              <Link to="/apps">See the three application circuits →</Link>
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}
