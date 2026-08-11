import { Link } from 'react-router-dom'

const apps = [
  {
    idx: 'App 01',
    title: 'The Virtual Brain: Encrypted RISC-V',
    body: 'My capstone existence proof. I loaded a synthesized PicoRV32 processor (~4.8k LUTs / ~1.5k DFFs) and stepped the core under mock encryption. Steady-state ticks in the harness ran at ~90 ms. It proved that CPU-scale netlists fit my clock loop without crashing.',
    meta: 'picorv32.v · picorv32_netlist.json · PRD_App1_RISCV.md',
  },
  {
    idx: 'App 02',
    title: 'The Bandwidth Test: Batched Search',
    body: 'A 3-character pattern matcher evaluated across thousands of data streams in a single tensor pass. This stresses unified-memory bandwidth, proving my system can seamlessly broadcast batched placeholders against static negacyclic LUT matrices and reduce them back.',
    meta: 'regex_matcher.v · regex_netlist.json · PRD_App2.md',
  },
  {
    idx: 'App 03',
    title: 'The Logic Test: Decision Tree Classify',
    body: 'Computers struggle with complex branching choices without relying on floating-point math. I built an exact non-linear classify circuit over a batch of records (two 4-bit features, one-bit high-risk output) to prove HELUT can handle strict decision branching gracefully.',
    meta: 'decision_tree.v · tree_netlist.json · PRD_App3.md',
  },
  {
    idx: 'App 04',
    title: 'The Generative Loop: TensorLUT Enigma',
    body: 'Melt a 925-LUT / 49-DFF Enigma M4 netlist into continuous INIT tensors, stream-evaluate under crypto fitness, squeeze toward binary with λ, and emit gate-level LUT6 Verilog. Baseline locks perfect stream fitness before any wipe; cold-start from 0.5 is the live melt.',
    meta: 'enigma_m4_tensorlut_baseline.v · tensorlut.md · adversarial-synthesis.md',
  },
]

export function AppsPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Proving Grounds</div>
            <h2>Circuits before—and inside—the Enigma hunt</h2>
            <p>
              The first three apps proved HELUT is a general netlist runtime, not an Enigma toy. They remain the scaffolding for true Torus Fully Homomorphic Encryption (TFHE). App 04 closes the other loop: a continuous–discrete adversarial compiler that evolves LUT INIT tables and writes physical Verilog.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Before I flip the switch to introduce the heavy cryptographic noise of real Programmable Bootstrapping (PBS), I had to prove my datapath could handle CPU-scale logic under &quot;mock&quot; encryption—and that the same silicon can re-synthesize gate logic from continuous ambiguity. Each circuit pushes a different limit: sequential scale, batch bandwidth, exact non-linear classify, and generative INIT discovery.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="app-grid">
            {apps.map((app) => (
              <article className="app" key={app.idx}>
                <div className="idx">{app.idx}</div>
                <h3>{app.title}</h3>
                <p>{app.body}</p>
                <div className="meta">{app.meta}</div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">What the GPU Points At</div>
            <h2>Three attack surfaces, one Apple Silicon</h2>
            <p>
              The early apps proved the compiler. The Enigma campaign uses a boolean-faithful Metal cleartext path—tens of millions of settings per second—not mock-PBS fitness. TensorLUT is the third surface: evolve the netlist itself.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">WELCHMAN</span>
              <span>
                <strong>Turing’s question:</strong> Given a crib, which keys are physically impossible? Closed electrical loops kill drums. This is what Bletchley could build in 1940 with relays and a known plaintext wedge.
              </span>
            </li>
            <li>
              <span className="mono">STOCHASTIC</span>
              <span>
                <strong>The dual question:</strong> Given a hypothesized plaintext template, which keys decrypt closer? A genetic loop evolves stecker/shell while the GPU scores letter-match across all \(26^4\) message keys per candidate. 1945 could not afford that—no massively parallel cleartext scoring, no gradient over “better.” We can. See <code>stochastic-bombe.md</code>.
              </span>
            </li>
            <li>
              <span className="mono">TENSORLUT</span>
              <span>
                <strong>The generative question:</strong> Given a ciphertext stream and a fitness, which LUT INIT tables decrypt it—and can they cool into real <code>LUT6</code> gates? Continuous weights, λ binary squeeze, reverse Verilog emit. See <code>adversarial-synthesis.md</code>.
              </span>
            </li>
            <li>
              <span className="mono">NOT \(26^{72}\)</span>
              <span>
                <strong>The constraint:</strong> We do not invent random 72-letter plaintext. Welchman and stochastic search keys against small Thetis-shaped hypotheses. TensorLUT rediscovers gate tables under a short known crib—it does not invent P1030680’s missing plaintext.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell">
          <div className="note" style={{ marginTop: 0, background: 'rgba(196, 120, 58, 0.14)', color: 'rgba(232, 236, 239, 0.88)' }}>
            <strong>The Endgame:</strong> Re-synthesize with Yosys when you change Verilog; the CLI accepts arbitrary JSON via <code>--compile-only</code>. Emit TensorLUT baselines with <code>--emit-tensorlut-verilog</code>; melt with <code>--tensorlut-cold-start</code>. While the day-to-day <code>helut</code> UX is currently Enigma-first, <strong>HELUTCore</strong> remains the shared foundational compiler. When I swap the mock torus polynomials for real TFHE ciphertexts, these exact same applications will run fully homomorphically. HELUT is Enigma-oriented as a research convenience at the moment since I am the only user. That will change once my research is concluded.
          </div>

          <p style={{ marginTop: '1.75rem' }}>
            <Link to="/enigma">Then the bombe entered the chat →</Link>
          </p>
        </div>
      </section>
    </main>
  )
}
