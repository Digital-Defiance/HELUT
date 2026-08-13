import { Link } from 'react-router-dom'
import { ProjectJournalShell } from './ProjectJournalShell'

export function PolymorphicCiphersJournalPage() {
  return (
    <ProjectJournalShell
      kicker="Schneier Pillar · Journal"
      title="Red / Blue campaign notes"
      lede="Polymorphic ciphers are not a product SKU. They are a design rule: under adversarial melt, the system must fail closed and mutate its non-linear guts until the attack no longer yields reciprocal structure. This journal will track that loop as it standardizes."
      hubPath="/projects/polymorphic-ciphers"
    >
      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Open ledger</div>
            <h2>Seed entries</h2>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">RED</span>
              <span>
                Differentiable melt + Boolean sieves as attack surfaces — whatever recovers
                stecker-like involutions or collapses keystream state.
              </span>
            </li>
            <li>
              <span className="mono">BLUE</span>
              <span>
                Hardening: involution constraints, fail-closed mutation of feedback / S-box
                structure, refusal to emit silicon that only works as an identity codec.
              </span>
            </li>
            <li>
              <span className="mono">LAB</span>
              <span>
                Early material lives in the <Link to="/projects/e256">Enigma256</Link> project —
                Gen-5 SoftBus field cipher and bijection controls.
              </span>
            </li>
            <li>
              <span className="mono">NEXT</span>
              <span>
                Essay draft on the{' '}
                <Link to="/projects/polymorphic-ciphers/red-blue">Red / Blue loop</Link>; then
                reproducible harnesses that both sides share.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </ProjectJournalShell>
  )
}

export function PolymorphicRedBluePage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Schneier Pillar · Essay</div>
            <h2>Standardize polymorphic ciphers</h2>
            <p className="lede">
              Bruce Schneier&apos;s long argument for open cryptographic design meets HELUT&apos;s
              adversarial compiler: publish the Red/Blue evolutionary loop so ciphers are born under
              the same pressure that will later audit them.
            </p>
            <p style={{ marginTop: '1rem' }}>
              <Link to="/projects/polymorphic-ciphers">← Project hub</Link>
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The loop</div>
            <h2>Attack, mutate, fail closed</h2>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">RED</span>
              <span>
                <strong>Melt the structure.</strong> Continuous INIT search, Boolean boards, and
                stochastic KPA share one job: force the cipher to yield reciprocal pairs or
                collapsed state. A win for Red is a recovered discrete object that decrypts.
              </span>
            </li>
            <li>
              <span className="mono">BLUE</span>
              <span>
                <strong>Mutate under fire.</strong> Non-linear feedback, S-boxes, and key schedules
                change so that the successful Red path no longer exists — or the system refuses to
                ship silicon that only imitates identity.
              </span>
            </li>
            <li>
              <span className="mono">CLOSED</span>
              <span>
                <strong>Fail closed.</strong> If the squeeze cannot produce a cryptographically
                honest discrete netlist, Blue does not “approximate security.” It rejects the
                candidate.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <span>
                <strong>Open the philosophy.</strong> The pillar is the shared framework and
                harnesses, not a secret algorithm. Industry baseline = everyone can run the same
                Red against the same Blue rules.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell prose">
          <p>
            Differentiable hardware cryptanalysis (Turing Pillar) supplies Red&apos;s sharpest tool.
            Polymorphic design (Schneier Pillar) is Blue&apos;s answer. The Grand Challenge aims both
            at ZKP and PQC-scale circuits once those two pillars are formal enough to share.
          </p>
        </div>
      </section>
    </main>
  )
}
