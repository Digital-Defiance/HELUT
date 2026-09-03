import { Link } from 'react-router-dom'
import { ProjectJournalShell } from './ProjectJournalShell'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'

export function DifferentiableHardwareJournalPage() {
  return (
    <ProjectJournalShell
      kicker="Turing Pillar · Journal"
      title="Grades from the continuous–discrete loop"
      lede="TensorLUT is the laboratory. This journal records what the melt proved, what shattered, and what the involution sandwich recovered — the evidence trail toward a formal method for differentiable hardware cryptanalysis."
      hubPath="/projects/differentiable-hardware"
    >
      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Open ledger</div>
            <h2>Seed entries</h2>
            <p>
              Full chronology will grow here the way <NaziBlaster9000Span /> grew for P1030680. Starting
              points already exist in-repo.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">BASELINE</span>
              <span>
                Unmutated Enigma M4 stream locks <em>F<sub>crypto</sub> = 0</em> —
                <code>enigma_m4_tensorlut_baseline.v</code>.
              </span>
            </li>
            <li>
              <span className="mono">SHATTER</span>
              <span>
                Full cold-start and stecker-cone INIT melts collapse under λ (dependency shortcuts;
                cone LUTs behave as I/O codecs around identity plugboard).
              </span>
            </li>
            <li>
              <span className="mono">INVOLUTION</span>
              <span>
                Freeze the core; evolve ≤10 reciprocal pairs. Identity control passes; blind
                3-pair rediscovery on a short crib PASSed.
              </span>
            </li>
            <li>
              <span className="mono">NEXT</span>
              <span>
                Formal write-up on{' '}
                <Link to="/projects/differentiable-hardware/paradigm">The paradigm</Link>, then
                Phase II targets (stream melt, FHE gates) as separate project journals.
              </span>
            </li>
            <li>
              <span className="mono">PARKED</span>
              <span>
                <strong>bgpucap power analysis:</strong> future investigation — can GPU power /
                energy capture (bgpucap or a HELUT fork) while TensorLUT / HELUT cores run leak
                key-dependent structure that Boolean search misses? Needs a controlled known-key
                fixture before any break claim. Tracked in <code>roadmap-overall.md</code> (Phase
                II).
              </span>
            </li>
          </ul>
        </div>
      </section>
    </ProjectJournalShell>
  )
}

export function DifferentiableHardwareParadigmPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Turing Pillar · Essay</div>
            <h2>Differentiable hardware cryptanalysis</h2>
            <p className="lede">
              Combinatoric sieves reject impossible states. Differentiable hardware does something
              else: it relaxes discrete gates into continuous tensors, searches under cryptographic
              fitness, and squeezes back toward binary silicon that still implements the attack —
              or the defense.
            </p>
            <p style={{ marginTop: '1rem' }}>
              <Link to="/projects/differentiable-hardware">← Project hub</Link>
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The loop</div>
            <h2>Continuous → discrete → reciprocal</h2>
            <p>
              The method is not “train a neural net on ciphertext.” It is a compiler loop with a
              cryptanalytic objective.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">01</span>
              <span>
                <strong>Ingest:</strong> Yosys flattens Verilog to LUT6 / DFF netlists — the same
                substrate as HELUT&apos;s cleartext tensor and graduated FHE paths.
              </span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>
                <strong>Melt:</strong> INIT tables become 64-wide floats; Metal evaluates multilinear
                LUTs in a streaming inject→forward→clock→sample contract.
              </span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>
                <strong>Fit:</strong> Soft ciphertext×plaintext MSE (or keystream fitness) drives
                search while λ pushes fractions toward binary.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                <strong>Emit:</strong> Elite snaps clean → gate-level{' '}
                <code>{`LUT6 #(.INIT(64'h…))`}</code> Verilog. Reciprocal structure (stecker
                involution, pair constraints) is enforced by construction when unconstrained melt
                shatters.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell prose">
          <p>
            Enigma M4 is the existence proof that the datapath closes. Formalizing the pillar means
            stating when the squeeze recovers a cryptographically meaningful discrete object — and
            when shatter modes prove the unconstrained search found a cheat, not a key. That
            distinction is what turns TensorLUT from a lab trick into an audit method for hardware
            vulnerabilities.
          </p>
          <p>
            See also <Link to="/stack">The stack</Link> and the research journal under this project.
          </p>
        </div>
      </section>
    </main>
  )
}
