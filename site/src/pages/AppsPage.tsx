import { Link } from 'react-router-dom'

const apps = [
  {
    idx: 'App 01',
    title: 'PicoRV32 · cleartext scale',
    body: 'Synthesized PicoRV32 (~4.8k LUTs / ~1.5k DFFs) stepped under the cleartext / mock-torus clock loop to prove CPU-scale netlists fit the host DFF contract. Steady ticks in the harness are on the order of ~90–173&nbsp;ms depending on degree and build. This remains a Path&nbsp;A existence proof—not an encrypted CPU claim.',
    meta: 'picorv32.v · picorv32_netlist.json · PRD_App1_RISCV.md',
  },
  {
    idx: 'App 02',
    title: 'Batched regex · bandwidth + encrypted SING',
    body: 'A small pattern-matcher netlist stresses batch broadcast against LUT tensors in the clear. The same JSON now also runs under --bench-encrypted (CPU SING) so ciphertext ticks must match the clear simulator on sampled stimuli.',
    meta: 'regex_matcher.v · regex_netlist.json · --bench-encrypted --sing',
  },
  {
    idx: 'App 03',
    title: 'Decision tree · exact classify + encrypted SING',
    body: 'Non-linear classify over batched records (two 4-bit features, one-bit high-risk out). Cleartext path proves branchless exactness; encrypted path is part of the multi-netlist SING suite.',
    meta: 'decision_tree.v · tree_netlist.json · --bench-encrypted --sing',
  },
  {
    idx: 'App 04',
    title: 'full_adder · encrypted equivalence harness',
    body: 'Three-LUT full adder is the fast encrypted regression: public-MS and secret refresh, boolean and crypto-shaped gadgets, CPU and Metal backends. Use --sing / Scripts/helut_encrypted_sing.sh. Metal microbench (--bench-encrypted-micro) isolates one blind-rotate at chosen N.',
    meta: 'netlist.json · HelutBench · logs/helut-encrypted-*.log',
  },
  {
    idx: 'App 05',
    title: 'TensorLUT Enigma · generative INIT',
    body: 'Melt a 925-LUT / 49-DFF Enigma M4 netlist into continuous INIT tensors, score crypto fitness, squeeze with λ, emit LUT6 Verilog. Baseline locks F_crypto = 0 before any wipe; live arm freezes silicon and evolves a reciprocal stecker involution.',
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
            <div className="kicker">Applications</div>
            <h2>Cleartext scale, encrypted equivalence, generative INIT</h2>
            <p>
              Early apps proved HELUT is a general netlist runtime, not an Enigma toy. Mock-torus
              shapes still carry CPU-scale cleartext work. Graduated FHE now owns the small-netlist
              equivalence benches. TensorLUT is the separate generative loop.
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
            <div className="kicker">Campaign surfaces</div>
            <h2>Three questions on the same silicon</h2>
            <p>
              The Enigma hunt uses cleartext Metal batch—not encrypted tick rate. TensorLUT is a
              third surface aimed at genotypes, not P1030680 plaintext invention.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">WELCHMAN</span>
              <span>
                <strong>Which keys are impossible?</strong> Crib menus, closed loops, dead drums.
              </span>
            </li>
            <li>
              <span className="mono">STOCHASTIC</span>
              <span>
                <strong>Which keys decrypt closer?</strong> Template + GPU letter-match. See{' '}
                <code>stochastic-bombe.md</code>.
              </span>
            </li>
            <li>
              <span className="mono">TENSORLUT</span>
              <span>
                <strong>Which INIT tables hold?</strong> Continuous weights, λ squeeze, reverse
                Verilog. See <code>adversarial-synthesis.md</code>.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell">
          <div
            className="note"
            style={{ marginTop: 0, background: 'rgba(196, 120, 58, 0.14)', color: 'rgba(232, 236, 239, 0.88)' }}
          >
            <strong>Reproduce:</strong> arbitrary netlist JSON via <code>--compile-only</code> /
            <code>--bench</code>. Encrypted equivalence:{' '}
            <code>--bench-encrypted --sing</code> (or <code>Scripts/helut_encrypted_sing.sh</code>).
            TensorLUT emit: <code>--emit-tensorlut-verilog</code>; melt:{' '}
            <code>--tensorlut-cold-start</code>. Parameter and hardness notes:{' '}
            <code>directives/parameter-cookbook.md</code>.
          </div>

          <p style={{ marginTop: '1.75rem' }}>
            <Link to="/enigma">The hunt for U-534 →</Link>
          </p>
        </div>
      </section>
    </main>
  )
}
