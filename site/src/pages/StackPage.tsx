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
              HELUT compiles Yosys gate-level netlists into tensor form and evaluates them on Apple Silicon. One path keeps mock-PBS torus shapes for eventual TFHE. A parallel path—<strong>TensorLUT</strong>—melts LUT INIT tables into continuous floats, evolves them under crypto fitness, and emits physical Verilog.
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
                <strong>Topological Sorting:</strong> Verilog is sequential; GPUs are parallel. HELUT performs a topological sort on the Yosys AST, slicing the physical circuit horizontally into discrete &quot;depth layers.&quot; It concatenates all the individual tensor LUTs in a layer into one massive, sparse block-diagonal matrix.
              </span>
            </li>
            <li>
              <span className="mono">05: THE BATCH MULTIPLIER</span>
              <span>
                <strong>40M/s Execution:</strong> Because the entire circuit depth is now just a matrix <em>W</em>, it doesn&apos;t care if it evaluates one state or millions. Utilizing the 64 gigabytes of unified memory on the M4 Max architecture, HELUT stacks millions of cryptographic keys into a single giant input matrix <em>X</em>. Apple&apos;s Metal pipeline executes <span>Y = W &middot; X</span>, smashing the hardware netlist against millions of parallel universes in a single clock tick.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="prose">
            <p>
              This mathematical translation deliberately avoids floating-point approximations on the mock-PBS path. When you are dealing with cryptography, a single rounding error breaks the entire system. Instead, torus arithmetic is realized by native <code>UInt32</code> wraparound. Every layer calculation is perfectly, ruthlessly precise.
            </p>
            <p>
              Right now, the values in my Metal mock-PBS path are <strong>mock torus polynomials</strong>—vectors shaped exactly like Fully Homomorphic Encryption (TFHE) ciphertexts, but without the final cryptographic noise. Think of it like testing a heavy race car on a dynamometer before putting it on the track. I am proving that massive, CPU-scale netlists can be successfully clocked on commodity silicon before I turn on the encryption.
            </p>
            <div className="note-glow">
              Homomorphic follow-through is intentional. The mock-PBS path is industrial scaffolding for eventual real torus PBS and key-switching. TensorLUT is the sibling path that treats INIT tables as learnable parameters and writes silicon back out.
            </div>
          </div>

          <ul className="stack-list">
            <li>
              <span className="mono">DFF (D Flip-Flop)</span>
              <span>
                <strong>The Memory:</strong> Sequential cells are clocked on the host with ping-pong state buffers. This keeps perfect track of time, allowing virtual circuits to &quot;tick&quot; forward through multi-tick boot loops and Enigma rotor streams.
              </span>
            </li>
            <li>
              <span className="mono">CORE</span>
              <span>
                <strong>The Foundation:</strong> <code>HELUTCore</code> is the generalized compiler. While the <code>helut</code> CLI currently leads with my Enigma attack, the core handles any standard netlist—and now emits TensorLUT Verilog.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">TensorLUT</div>
            <h2>Continuous–discrete adversarial synthesis</h2>
            <p>
              A parallel Metal pipeline pads every Yosys LUT to a 64-wide Float32 INIT vector and evaluates it with a multilinear extension kernel. Weights can sit anywhere in [0, 1]. Evolution mutates them; λ forces them back toward binary; the emitter writes <code>LUT6</code> hex.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">FORWARD</span>
              <span>
                <strong>Melt:</strong> Compile Yosys JSON → TensorLUT levels → Metal stream (inject → forward → clockTick → sample). Unmutated <code>enigma_m4</code> scores <em>F<sub>crypto</sub> = 0</em> on a known crib.
              </span>
            </li>
            <li>
              <span className="mono">FRICTION</span>
              <span>
                <strong>Adversarial loss:</strong> <em>F = F<sub>crypto</sub> − λ · P<sub>binary</sub></em>. Explore with λ=0; ramp λ to squeeze fractions. Discrete jumps and live-width mutation keep the search on reachable truth tables.
              </span>
            </li>
            <li>
              <span className="mono">REVERSE</span>
              <span>
                <strong>Instantiate:</strong> Threshold elite INITs → MSB-nibble hex → gate-level Verilog. Baseline artifact: <code>enigma_m4_tensorlut_baseline.v</code> (925×LUT6 + 49 DFFs).
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Cryptanalysis Datapath</div>
            <h2>Reversing Turing on the same silicon</h2>
            <p>
              Mock-PBS never assigns fitness for a break. The campaign engines use a separate boolean-faithful Metal cleartext batch—the same stepping as a real M4—so every score is a real decrypt.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">WELCHMAN BOMBE</span>
              <span>
                <strong>Eliminate the impossible:</strong> Crib menus form loops; dead settings die. This is Turing and Welchman’s question, accelerated to ~40M settings/s. It needs a connected wedge ≥16 letters.
              </span>
            </li>
            <li>
              <span className="mono">STOCHASTIC BOMBE</span>
              <span>
                <strong>Climb the possible:</strong> Fix a hypothesized plaintext template; evolve stecker/shell while <code>m4_kpa_batch</code> scores letter matches across 26 × 17,576 lanes. 1945 drums could only say yes/no to a crib. They could not rank millions of “almost” decrypts. That dual is what modern GPUs buy—and why a training-net message without a rigid crib is still attackable in principle.
              </span>
            </li>
            <li>
              <span className="mono">HONEST LIMIT</span>
              <span>
                <strong>Templates, not magic:</strong> Searching \(26^{72}\) plaintext is still impossible. Cold-start stecker search without a near-truth seed parks on false peaks (control: 22/72). What unlocks P1030680 is a small Thetis-shaped template bank plus key search—not more generations of German n-grams, and not TensorLUT inventing the missing letters.
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
              Today: an existence proof plus a generative INIT compiler. Next: integrating strict noise budgets, key switching, and honest performance envelopes—without abandoning the netlist-first discipline that made my applications and the bombe possible.
            </p>
          </div>
          <div className="prose">
            <p>
              Deep technical specifications live in <code>paper/helut.tex</code>. Design progression maps through <code>PRD.md</code> → <code>phase-2.md</code> → <code>phase-3.md</code>. Stochastic Bombe notes: <code>stochastic-bombe.md</code>. TensorLUT: <code>tensorlut.md</code>, <code>adversarial-synthesis.md</code>, <code>PRD_tensorlut*.md</code>.
            </p>
            <p>
              <Link to="/apps">See the application circuits →</Link>
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}
