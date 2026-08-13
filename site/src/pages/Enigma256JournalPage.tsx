import { Link } from 'react-router-dom'
import { ProjectJournalShell } from './ProjectJournalShell'

export function Enigma256JournalPage() {
  return (
    <ProjectJournalShell
      kicker="E256 · Field journal"
      title="Generation grades under Red pressure"
      lede="Enigma256 is the Blue answer to a Red team that already runs Welchman, Stochastic KPA, and TensorLUT on Apple Silicon. This journal tracks SoftBus field grades, bijection controls, and generation rolls — sibling to the P1030680 campaign ledger that named the leaks."
      hubPath="/projects/e256"
    >
      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Open ledger</div>
            <h2>Seed entries</h2>
            <p>
              Architecture lives on the{' '}
              <Link to="/projects/e256/design">design page</Link>; spec in{' '}
              <code>Enigma256.md</code>. Expand chronology here as generations ship.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">GEN 5</span>
              <span>
                Live SoftBus field — control plane (X25519 ‖ ML-KEM, HKDF-SHA512, AEAD) never
                enters datapath BRAMs; <code>enigma_256_core</code> is scramble-then-step.
              </span>
            </li>
            <li>
              <span className="mono">RECIPROCAL</span>
              <span>
                Encrypt ≡ decrypt under the same machine state. Rotor contract kept; 26-letter
                menus, self-stecker ban, thin plugboards, and paper day keys deleted.
              </span>
            </li>
            <li>
              <span className="mono">RED</span>
              <span>
                Surface past NLFF: TensorLUT cones, SoftBus KPA, <code>ent</code> gate. Blue rolls
                genes only under pressure (<code>Fixtures/enigma256_generation.json</code>).
              </span>
            </li>
            <li>
              <span className="mono">BIJECTION</span>
              <span>
                Byte-wide bijection harnesses and SoftBus oracles gate reciprocity before a
                generation is allowed to ship.
              </span>
            </li>
            <li>
              <span className="mono">PILLAR</span>
              <span>
                Feeds the{' '}
                <Link to="/projects/polymorphic-ciphers">Polymorphic Ciphers</Link> standard —
                fail-closed Red/Blue evolution, not a one-off product.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
