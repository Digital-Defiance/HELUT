import { Link } from 'react-router-dom'
import { ProjectJournalShell } from './ProjectJournalShell'

export function NetlistFheJournalPage() {
  return (
    <ProjectJournalShell
      kicker="Pillar I · Field journal"
      title="What the encrypted netlist has graded"
      lede="This is the chronology for netlist-clocked torus FHE — SING receipts, noisy-BK certificates, and honest remainders. It is not the U-534 hunt. P1030680 is still unbroken; that ledger lives on Turing Complete."
      hubPath="/projects/netlist-fhe"
    >
      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Proven</div>
            <h2>Closed bars (claim-sheet IDs)</h2>
            <p>
              Numbers follow <code>directives/claim-sheet.md</code>. Trivial Metal is not FHE.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">C20/C21</span>
              <span>
                Encrypted <code>full_adder</code> Metal SING at production-shaped <em>N</em>=1024:
                boolean wavefront and crypto ℓ=2. Equivalence to clear is C6.
              </span>
            </li>
            <li>
              <span className="mono">C23</span>
              <span>
                Sage fill-in on the hardness table. Quote HELUT vs Sage on the named row (175.7 vs
                180.2 on prod-n1024-s16). Do not quote “176-bit secure” (H1).
              </span>
            </li>
            <li>
              <span className="mono">C52–C54</span>
              <span>
                Covering Track A at <em>N</em>=1024, σ=128, stride-<em>k</em>=7: adder ε + SING
                (C52), counter (C53), toy ISA (C54). Public-MS is native-δ refresh on {'{0,k}'}{' '}
                wires, not the historical /kδ path (C43).
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Remainders</div>
            <h2>Open science — not site bugs</h2>
            <p>
              If a public page does not claim these as done, that is correct. Do not “fix” the
              gallery by inventing production SING.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">I.2</span>
              <span>
                Encrypted tree / regex SING exists at <strong>demo N</strong> (C6). Metal SING at
                production <em>N</em> is not graded.
              </span>
            </li>
            <li>
              <span className="mono">C37</span>
              <span>
                Native <em>k</em>=1 torus-scale at <em>N</em>=1024 covering-b1 σ=128 is still
                undecodable at <em>n</em>=1024 (C37, 8 trials). Cutting LWE <em>n</em> (C55) makes
                identity decodable but ε stays above −64.
              </span>
            </li>
            <li>
              <span className="mono">C26</span>
              <span>
                <code>cryptoPublicMS</code> inject at production <em>N</em> is still a graded
                failure (C26). Stride-<em>k</em>=7 makes tiny <em>B</em>=1 identity-decodable but
                Metal SING fails (C56).
              </span>
            </li>
            <li>
              <span className="mono">PicoRV</span>
              <span>
                Encrypted PicoRV32 SING is demo <em>N</em>=8 (C45–C51). Covering noisy BK at{' '}
                <em>N</em>=1024 is not claimed (LUT-tax from C52 × 4785 LUTs is hours per tick).
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell prose">
          <p>
            Reproduce: <code>REPRODUCE.md</code> · gallery:{' '}
            <Link to="/apps">Applications</Link> · campaign (still open):{' '}
            <Link to="/projects/p1030680/journal">Turing Complete</Link>.
          </p>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
