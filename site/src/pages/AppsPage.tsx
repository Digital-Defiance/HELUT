import { Link } from 'react-router-dom'

/** Nine-slot gallery — mirrors directives/application-gallery.md (Phase 0.6). */
const pillars = [
  {
    name: 'Pillar I · Netlist-clocked FHE',
    slots: [
      {
        idx: 'I.1',
        title: 'Encrypted full_adder SING',
        body: 'Multi-LUT Metal SING at production-shaped N=1024: boolean wavefront 10.6 s/8 (C20); crypto ℓ=2 11.38 s/8 (C21). Equivalence to clear is C6.',
        meta: 'Scripts/helut_encrypted_sing.sh · logs/helut-encrypted-n1024-metal-sing-*.log',
      },
      {
        idx: 'I.2',
        title: 'Encrypted tree / regex SING',
        body: 'Same compiler on non-adder netlists at demo N (C6). Proves encrypted ticks are not full_adder-specialized.',
        meta: 'tree_netlist.json · regex_netlist.json · --bench-encrypted --sing',
      },
      {
        idx: 'I.3',
        title: 'Hardness + noisy-BK certificates',
        body: 'Calibrated hardness + Sage fill-in (C23). Covering-gadget noisy BK at N≤128 (C22). Covering Track A at N=1024 σ=128 k=7 is C52–C54 (ε + SING). cryptoPublicMS inject at N=1024 is still a graded failure (C26). Native k=1 at that inject is still C37. Do not quote “176-bit secure” (H1).',
        meta: '--hardness-table · --measure-bk-noise · Scripts/helut_sage_estimate.sh',
      },
    ],
  },
  {
    name: 'Pillar II · Differentiable hardware',
    slots: [
      {
        idx: 'II.1',
        title: 'M4 TensorLUT baseline emit',
        body: 'Unmutated Enigma M4 stream locks F_crypto=0 and emits LUT6 Verilog (C8).',
        meta: 'enigma_m4_tensorlut_baseline.v · tensorlut.md',
      },
      {
        idx: 'II.2',
        title: 'Involution sandwich / formal',
        body: 'Blind 3-pair PASS (C9). Theorem 1 + corollary: continuous→discrete structure and emitter/freeze completeness (C19, C25).',
        meta: 'testTensorLUTFormalCertificate · testTensorLUTFormalCorollaryCertificate',
      },
      {
        idx: 'II.3',
        title: 'Shatter vs hold under λ',
        body: 'Seminar empirics from campaign Phase 21. Shatter is science about continuous shortcuts—not a U-534 decrypt (H6).',
        meta: 'BREAK_P1030680.md · TensorLUT cold-start / stecker logs',
      },
    ],
  },
  {
    name: 'Pillar III · Polymorphic SoftBus',
    slots: [
      {
        idx: 'III.1',
        title: 'SoftBus reciprocity / bijection',
        body: 'Frozen scramble is a permutation and an involution; stream round-trip under identical keys (C10, Theorem 2 / C24).',
        meta: 'testEnigma256FormalCertificate · Scripts/enigma256_bijection.sh',
      },
      {
        idx: 'III.2',
        title: 'Red battery grades',
        body: 'TensorLUT cones, SoftBus KPA, and ent on the keystream—empirical grades on the same Mac that rolls Blue.',
        meta: 'Scripts/enigma256_red_battery.sh · logs/enigma256-*',
      },
      {
        idx: 'III.3',
        title: 'Fail-closed NLFF harden',
        body: 'hardenedCubic() rejects coupledCubic6 and rolls back to independent cubic6 (C24 clause 5). Structural SoftBus contract—not IND-CPA.',
        meta: 'Enigma256Formal.checkFailClosedCoupling',
      },
    ],
  },
]

const shapeLab = [
  {
    idx: 'Shape',
    title: 'PicoRV32 / tree / regex (oracle)',
    body: 'Cleartext / mock-torus clocks prove CPU-scale netlists fit the host DFF contract (C1). Not the FHE claim.',
    meta: 'picorv32_netlist.json · boolean benches',
  },
]

export function AppsPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Application gallery</div>
            <h2>Nine slots across three pillars</h2>
            <p>
              Every slot maps to a claim ID and a reproduce path (
              <code>directives/application-gallery.md</code>). Oracle shape labs stay labeled
              distinct from encrypted FHE.
            </p>
          </div>
        </div>
      </section>

      {pillars.map((pillar) => (
        <section className="band" key={pillar.name}>
          <div className="shell">
            <div className="section-head">
              <div className="kicker">{pillar.name}</div>
            </div>
            <div className="app-grid">
              {pillar.slots.map((app) => (
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
      ))}

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Shape laboratory (not FHE)</div>
          </div>
          <div className="app-grid">
            {shapeLab.map((app) => (
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
              The Enigma hunt uses cleartext Metal batch—not encrypted tick rate (N6). TensorLUT is
              a third surface aimed at genotypes, not P1030680 plaintext (H6).
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">WELCHMAN</span>
              <span>
                <strong>Which keys are impossible?</strong> Crib menus, closed loops, dead drums.
                Catalog rings parked at originalIndex 417; resume{' '}
                <code>--bombe-from 418</code>.
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
            <strong>Reproduce:</strong> claim inventory in <code>directives/claim-sheet.md</code>;
            commands in <code>REPRODUCE.md</code>. Encrypted equivalence:{' '}
            <code>--bench-encrypted --sing</code>. Formal certs: C19 / C24 / C25 filters. Parameter
            and remaining H4 notes (native k=1 / cryptoPublicMS): <code>directives/parameter-cookbook.md</code>.
          </div>

          <p style={{ marginTop: '1.75rem' }}>
            <Link to="/enigma">The hunt for U-534 →</Link>
          </p>
        </div>
      </section>
    </main>
  )
}
