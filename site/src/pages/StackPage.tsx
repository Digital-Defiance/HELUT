import { Link } from 'react-router-dom'

export function StackPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Engine Room</div>
            <h2>Translating silicon blueprints into linear algebra</h2>
            <p>
              HELUT compiles Yosys gate-level netlists into a single <code>MPSGraph</code> and evaluates every component as a dense matrix-vector product on Apple Silicon. I am literally translating the physical physics of a computer chip into continuous tensor mathematics.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Pipeline</div>
            <h2>How verilog2tensor works</h2>
            <p>
              To achieve execution speeds of 40 million settings per second, you cannot write standard sequential code. GPUs actively punish code that branches. The entire execution path must be flattened into branchless math. Here is the five-step pipeline that makes that possible.
            </p>
          </div>
          
          <ul className="stack-list pipeline-list">
            <li>
              <span className="mono">01: RTL INGESTION</span>
              <span>
                <strong>Industry Standard Yosys:</strong> The user workflow is completely standard. You write IEEE Verilog, and Yosys compiles it down to a flattened JSON netlist of generic gates and Look-Up Tables (k-LUTs). HELUT parses this AST directly.
              </span>
            </li>
            <li>
              <span className="mono">02: VECTORIZING TRUTH</span>
              <span>
                <strong>Geometrical States:</strong> In standard software, a bit is a scalar (0 or 1). To perform homomorphic tensor math without branching, a bit is expanded into an orthogonal state vector. False becomes <span>v<sub>0</sub> = [1, 0]<sup>T</sup></span> and True becomes <span>v<sub>1</sub> = [0, 1]<sup>T</sup></span>.
              </span>
            </li>
            <li>
              <span className="mono">03: THE TENSOR LUT</span>
              <span>
                <strong>Replacing the Logic Gate:</strong> Every Yosys gate is replaced by a weight tensor <em>W</em> holding its exact truth table. To evaluate a 2-input gate (like an XOR), HELUT does not use an IF statement. It computes a bilinear form against the input vectors: <span>y = x<sub>1</sub><sup>T</sup> &middot; W &middot; x<sub>2</sub></span>. The Metal shader blindly multiplies the geometry, and the logical truth naturally falls out.
              </span>
            </li>
            <li>
              <span className="mono">04: GRAPH FLATTENING</span>
              <span>
                <strong>Topological Sorting:</strong> Verilog is sequential; GPUs are parallel. HELUT performs a topological sort on the Yosys AST, slicing the physical circuit horizontally into discrete "depth layers." It concatenates all the individual tensor LUTs in a layer into one massive, sparse block-diagonal matrix.
              </span>
            </li>
            <li>
              <span className="mono">05: THE BATCH MULTIPLIER</span>
              <span>
                <strong>40M/s Execution:</strong> Because the entire circuit depth is now just a matrix <em>W</em>, it doesn't care if it evaluates one state or millions. Utilizing the 64 gigabytes of unified memory on the M4 Max architecture, HELUT stacks millions of cryptographic keys into a single giant input matrix <em>X</em>. Apple's Metal pipeline executes <span>Y = W &middot; X</span>, smashing the hardware netlist against millions of parallel universes in a single clock tick.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="prose">
            <p>
              This mathematical translation deliberately avoids floating-point approximations. When you are dealing with cryptography, a single rounding error breaks the entire system. Instead, torus arithmetic is realized by native <code>UInt32</code> wraparound. Every layer calculation is perfectly, ruthlessly precise.
            </p>
            <p>
              Right now, the values in my Metal GPU path are <strong>mock torus polynomials</strong>—vectors shaped exactly like Fully Homomorphic Encryption (TFHE) ciphertexts, but without the final cryptographic noise. Think of it like testing a heavy race car on a dynamometer before putting it on the track. I am proving that massive, CPU-scale netlists can be successfully clocked on commodity silicon before I turn on the encryption.
            </p>
            <div className="note-glow">
              Homomorphic follow-through is intentional. The mock-PBS path is industrial scaffolding for eventual real torus PBS and key-switching. The applications I have built already exercise the shapes that matter: wide logic fanout, state retention, and large parallel batches.
            </div>
          </div>

          <ul className="stack-list">
            <li>
              <span className="mono">DFF (D Flip-Flop)</span>
              <span>
                <strong>The Memory:</strong> Sequential cells are clocked on the host with ping-pong state buffers. This keeps perfect track of time, allowing virtual circuits to "tick" forward through multi-tick boot loops.
              </span>
            </li>
            <li>
              <span className="mono">CORE</span>
              <span>
                <strong>The Foundation:</strong> <code>HELUTCore</code> is the generalized compiler. While the <code>helut</code> CLI currently leads with my Enigma attack, the core handles any standard netlist.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
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