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
]

export function AppsPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Proving Grounds</div>
            <h2>Three circuits before Enigma (and true PBS)</h2>
            <p>
              These were the proofs that HELUT is a general netlist runtime, not an Enigma toy. More importantly, they are the scaffolding for my ultimate goal: <strong>true Torus Fully Homomorphic Encryption (TFHE)</strong>.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Before I flip the switch to introduce the heavy cryptographic noise of real Programmable Bootstrapping (PBS), I had to prove my datapath could handle CPU-scale logic under "mock" encryption. I couldn't point an unproven system at a historically unbreakable cypher, so each of these circuits was designed to push a different part of the architecture to its limit: sequential scale, batch bandwidth, and exact non-linear classify.
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

      <section className="band-ink">
        <div className="shell">
          <div className="note" style={{ marginTop: 0, background: 'rgba(196, 120, 58, 0.14)', color: 'rgba(232, 236, 239, 0.88)' }}>
            <strong>The Endgame:</strong> Re-synthesize with Yosys when you change Verilog; the CLI accepts arbitrary JSON via <code>--compile-only</code>. While the day-to-day <code>helut</code> UX is currently Enigma-first, <strong>HELUTCore</strong> remains the shared foundational compiler. When I swap the mock torus polynomials for real TFHE ciphertexts, these exact same applications will run fully homomorphically. HELUT is Enigma-oriented as a research convenience at the moment since I am the only user. That will change once my research is concluded.
          </div>

          <p style={{ marginTop: '1.75rem' }}>
            <Link to="/enigma">Then the bombe entered the chat →</Link>
          </p>
        </div>
      </section>
    </main>
  )
}
