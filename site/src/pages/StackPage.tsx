import { Link } from 'react-router-dom'

export function StackPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The stack</div>
            <h2>Three evaluation paths, one Yosys ingest</h2>
            <p>
              Every path starts the same way: IEEE Verilog → Yosys → flattened{' '}
              <code>$lut</code> / DFF JSON. What differs is the arithmetic under the wire—cleartext
              Metal batch for campaign search, graduated torus FHE for encrypted ticks, and
              TensorLUT when INIT tables themselves are the search space.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Path A · Cleartext tensor</div>
            <h2>Campaign-scale Metal batch</h2>
            <p>
              Boolean-faithful orthogonal state vectors and block-diagonal LUT tensors. No
              ciphertext noise. This is what drives Welchman and Stochastic Bombe at ~40M machine
              settings per second on M4 Max unified memory—fitness is letter-match / diagonal-board
              elimination, not HELUT encrypted tick rate.
            </p>
          </div>
          <ul className="stack-list pipeline-list">
            <li>
              <span className="mono">01</span>
              <span>
                <strong>Yosys ingest:</strong> standard RTL → k-LUT / DFF netlist JSON.
              </span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>
                <strong>State vectors:</strong> bits as orthogonal columns; LUT eval is a bilinear
                form, not an <code>if</code>.
              </span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>
                <strong>Layer flatten:</strong> topological depth slices → sparse block-diagonal{' '}
                <em>W</em>; batch keys as columns of <em>X</em>; <span>Y = W · X</span> on Metal.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                <strong>Host clock:</strong> DFFs ping-pong on the host so multi-tick streams (Enigma
                rotors, PicoRV32) stay sequential where physics demands it.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Path B · Graduated FHE</div>
            <h2>Netlist-clocked torus samples</h2>
            <p>
              Mock torus polynomials (trivial encoding) were the dynamometer. The encrypted path now
              uses LWE/GLWE samples, GGSW bootstrap keys, and per-<code>$lut</code> blind-rotate
              (CPU and Metal), with public modulus-switch or secret re-encrypt between LUTs.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">SAMPLES</span>
              <span>
                <strong>LWE / GLWE / GGSW:</strong> binary secret; boolean or crypto-shaped gadgets;
                public-MS paths use <code>g₀ = δ = q/(2N)</code> so refresh stays on-lattice.
              </span>
            </li>
            <li>
              <span className="mono">CERTS</span>
              <span>
                <strong>Issued per tick:</strong> discrete ∞-norm noise budget, Gaussian ingest{' '}
                <em>ε</em> target, calibrated classical hardness (≥128-bit bar at production{' '}
                <em>N</em>), noisy-BK depth model (HELUT BK encrypt is still noiseless today).
              </span>
            </li>
            <li>
              <span className="mono">SING</span>
              <span>
                <strong>Equivalence:</strong>{' '}
                <code>--bench-encrypted --sing</code> checks encrypted outputs against the clear
                netlist simulator (full_adder, tree, regex). Metal microbench:{' '}
                <code>--bench-encrypted-micro</code> (~50&nbsp;s/BR at <em>N</em>=64 measured).
              </span>
            </li>
            <li>
              <span className="mono">LIMITS</span>
              <span>
                <strong>Not claimed yet:</strong> lattice-estimator attack cost (Sage fill pending);
                production key sizes until that table lands; side-channel / GPU power analysis.
                Large-<em>N</em> encrypted Metal wall-clock is an engineering target, not a
                marketing number.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Path C · TensorLUT</div>
            <h2>Continuous–discrete adversarial synthesis</h2>
            <p>
              Pad every Yosys LUT to a 64-wide Float32 INIT vector; evaluate with a multilinear
              kernel; evolve under crypto fitness; squeeze with λ; emit <code>LUT6</code> hex. This
              is Pillar&nbsp;II—not FHE.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">FORWARD</span>
              <span>
                <strong>Melt:</strong> Yosys JSON → TensorLUT levels → Metal stream
                (inject→forward→clockTick→sample). Unmutated <code>enigma_m4</code> scores{' '}
                <em>F<sub>crypto</sub> = 0</em> on a known crib.
              </span>
            </li>
            <li>
              <span className="mono">FRICTION</span>
              <span>
                <strong>Loss:</strong> <em>F = F<sub>crypto</sub> − λ · P<sub>binary</sub></em>.
                Explore at λ=0; ramp λ to force discreteness.
              </span>
            </li>
            <li>
              <span className="mono">REVERSE</span>
              <span>
                <strong>Emit:</strong> threshold elite INITs → gate-level Verilog. Live arm: freeze
                known-good silicon, evolve a reciprocal stecker involution by construction.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Cryptanalysis datapath</div>
            <h2>Still cleartext Metal for the hunt</h2>
            <p>
              P1030680 uses Path&nbsp;A. Encrypted Path&nbsp;B does not grade campaign fitness. That
              separation is deliberate and permanent for the premiere claim surface.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">WELCHMAN</span>
              <span>
                <strong>Eliminate:</strong> crib menus form loops; impossible settings die (~40M/s).
                Needs a connected wedge ≥16 letters.
              </span>
            </li>
            <li>
              <span className="mono">STOCHASTIC</span>
              <span>
                <strong>Rank:</strong> hypothesized plaintext template + GPU letter-match across
                message-key lanes. Dual of 1945 yes/no drums.
              </span>
            </li>
            <li>
              <span className="mono">HONEST</span>
              <span>
                <strong>Not 26<sup>72</sup>:</strong> templates and keys, not invented plaintext.
                TensorLUT does not invent P1030680’s missing letters.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Docs</div>
            <h2>Where the receipts live</h2>
            <p>
              Paper: <code>paper/helut.tex</code>. Results inventory:{' '}
              <code>directives/claim-sheet.md</code>. Reproduce:{' '}
              <code>REPRODUCE.md</code>. Trajectory:{' '}
              <code>directives/research-trajectory.md</code>. Cookbook:{' '}
              <code>directives/parameter-cookbook.md</code>. Campaign:{' '}
              <Link to="/projects/p1030680/journal">Turing Complete</Link>.
            </p>
            <p style={{ marginTop: '1rem' }}>
              <Link to="/apps">Application circuits →</Link>
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}
