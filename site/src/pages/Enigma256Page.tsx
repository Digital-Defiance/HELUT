import { Link } from 'react-router-dom'
import { E256Span } from '../E256Span'
import { HelutSpan } from '../HELUTSpan'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'

export function Enigma256Page() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">
              <Link to="/projects/e256" style={{ color: 'inherit', textDecoration: 'none' }}>
                Project · <E256Span />
              </Link>
              {' · '}Blue Team · 2026
            </div>
            <h2>Fixing Enigma for a century that can melt silicon</h2>
            <p className="lede">
              The hunt for P1030680 is a ledger of how the 1945 machine leaks. Every clean negative, every ghost board, every Turing-shaped shortcut I weaponized against M4 is also a specification for what a rotor cipher must never do again. Enigma 256 (<E256Span />) is that rewrite: a base-256 polymorphic stream cipher whose datapath is SoftBus-backed Verilog on Apple Silicon and whose keys never sit in a water-soluble codebook.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              This is not nostalgia hardware. It is the Blue Team answer to a Red Team that already runs Welchman, Stochastic KPA, and TensorLUT on Apple Silicon—built from the same findings documented in the{' '}
              <Link to="/projects/p1030680/journal">campaign journal</Link>.
            </p>
          </div>

          <div className="note" style={{ marginBottom: '1.5rem' }}>
            <strong>Experimental research fixture—not for real data.</strong>{' '}
            <code>E256-003</code> is <strong>OPEN</strong> pending human acceptance. The bounded
            fixture-v4 receipt is functional evidence only: it is not an IND-CPA claim, an
            HMAC-security proof, external cryptanalysis, a security level, or a work factor.
          </div>

          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">Live profile</div>
              <div className="value">fixture-v4</div>
            </div>
            <div className="stat">
              <div className="label">Center</div>
              <div className="value">XOR conjugate</div>
            </div>
            <div className="stat">
              <div className="label">Receipt</div>
              <div className="value">49/49 · formal 1/1</div>
            </div>
            <div className="stat">
              <div className="label">Review</div>
              <div className="value">E256-003 OPEN</div>
            </div>
          </div>
          <p className="mono" style={{ marginTop: '1rem', overflowWrap: 'anywhere' }}>
            E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4
          </p>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Architecture</div>
            <h2>The fixture-v4 host/RTL boundary</h2>
            <p>
              The host derives and transports <code>(payload, centerMask, absoluteByteCounter)</code>.
              RTL validates the absolute counter before processing the byte; it does not implement
              HMAC. The day key contains a plugboard plus 16 forward/reverse rotor pools and no
              reflector.
            </p>
          </div>

          <figure className="arch-figure" aria-label="E256 fixture-v4 architecture diagram">
            <svg viewBox="0 0 920 520" role="img" className="arch-svg">
              <title>E256 fixture-v4 host schedule, RTL datapath, and bounded TensorLUT cone</title>
              <defs>
                <linearGradient id="archCp" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stopColor="#0f3034" />
                  <stop offset="100%" stopColor="#1f6f6a" />
                </linearGradient>
                <linearGradient id="archDp" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#2a374e" />
                  <stop offset="100%" stopColor="#0d1322" />
                </linearGradient>
                <linearGradient id="archRed" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="#a86227" />
                  <stop offset="100%" stopColor="#d4833f" />
                </linearGradient>
                <marker id="archArrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                  <path d="M0,0 L6,3 L0,6 Z" fill="#9ee0da" />
                </marker>
              </defs>

              <rect x="24" y="24" width="872" height="118" rx="4" fill="url(#archCp)" />
              <text x="44" y="52" className="arch-label">Host · derive and transport the byte schedule</text>
              <rect x="44" y="68" width="238" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="54" y="90" className="arch-box">payload</text>
              <text x="54" y="108" className="arch-sub">one scheduled byte</text>
              <path d="M288 94 H316" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#archArrow)" />
              <rect x="322" y="68" width="238" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="332" y="90" className="arch-box">centerMask</text>
              <text x="332" y="108" className="arch-sub">independent center input</text>
              <path d="M566 94 H594" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#archArrow)" />
              <rect x="600" y="68" width="272" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="610" y="90" className="arch-box">absoluteByteCounter</text>
              <text x="610" y="108" className="arch-sub">transported; checked by RTL</text>

              <path d="M360 142 V168" stroke="var(--ink-soft, #2a374e)" strokeWidth="1.5" strokeDasharray="4 3" />
              <text x="372" y="162" className="arch-flow">host tuple + active tables</text>

              <rect x="24" y="172" width="560" height="180" rx="4" fill="url(#archDp)" />
              <text x="44" y="200" className="arch-label arch-label-light">RTL · SoftBus ↔ enigma_256_core</text>
              <rect x="44" y="220" width="150" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="54" y="248" className="arch-box">Burst load</text>
              <text x="54" y="268" className="arch-sub">9×256 tables</text>
              <text x="54" y="286" className="arch-sub">2,304 bytes</text>
              <text x="54" y="304" className="arch-sub">10 accesses</text>
              <path d="M200 270 H228" stroke="#d4833f" strokeWidth="1.5" />
              <rect x="234" y="220" width="200" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="244" y="248" className="arch-box">Reciprocal core</text>
              <text x="244" y="268" className="arch-sub">plug → R1…R4 → center</text>
              <text x="244" y="286" className="arch-sub">→ R4⁻¹…R1⁻¹ → plug</text>
              <text x="244" y="304" className="arch-sub">counter validation · no HMAC</text>
              <path d="M440 270 H468" stroke="#d4833f" strokeWidth="1.5" />
              <rect x="474" y="220" width="90" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="486" y="262" className="arch-box">CT</text>
              <text x="482" y="284" className="arch-sub">DATA_OUT</text>

              <rect x="604" y="172" width="292" height="180" rx="4" fill="url(#archRed)" />
              <text x="624" y="200" className="arch-label">Bounded TensorLUT test</text>
              <text x="624" y="228" className="arch-box">366-LUT6 scramble cone</text>
              <text x="624" y="252" className="arch-box">independent center_mask</text>
              <text x="624" y="278" className="arch-sub">blue_hold</text>
              <text x="624" y="300" className="arch-sub">crypto −291592.781250</text>
              <text x="624" y="322" className="arch-sub">nonbinary 1217 · optimizer only</text>

              <rect x="24" y="372" width="872" height="124" rx="4" fill="#e8ecef" stroke="rgba(13,19,34,0.12)" />
              <text x="44" y="400" className="arch-label-dark">Reciprocal byte path · no reflector</text>
              <text x="44" y="430" className="arch-path">PT → plug → R1±off → R2±off → R3±off → R4±off → A_i^-1(A_i(x) XOR k_i)</text>
              <text x="44" y="458" className="arch-path-note">→ reverse rotor path → the same plugboard → CT</text>
              <text x="44" y="482" className="arch-path-note">9 unique tables · plugboard accessed twice · centerMask supplied independently</text>
            </svg>
            <figcaption>
              The live identity is{' '}
              <code>E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4</code>.
              The bounded receipt is <code>logs/e256-v2-gen0-fixture-v4-validation.json</code>.
            </figcaption>
          </figure>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The machine</div>
            <h2>How the fixture-v4 tables and center connect</h2>
            <p>
              Four active forward/reverse rotor pairs sit between two accesses to one plugboard.
              The center is an XOR conjugated through the selected forward composition; there is no
              reflector or reserved-pair mode.
            </p>
          </div>

          <figure className="arch-figure" aria-label="E256 fixture-v4 machine internals diagram">
            <svg viewBox="0 0 960 520" role="img" className="arch-svg">
              <title>E256 fixture-v4: plugboard, forward and reverse rotors, conjugated-XOR center, host schedule</title>
              <defs>
                <linearGradient id="machInk" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#1a2438" />
                  <stop offset="100%" stopColor="#0d1322" />
                </linearGradient>
                <linearGradient id="machTeal" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stopColor="#0f3034" />
                  <stop offset="100%" stopColor="#1f6f6a" />
                </linearGradient>
                <linearGradient id="machCopper" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="#a86227" />
                  <stop offset="100%" stopColor="#d4833f" />
                </linearGradient>
                <marker id="machArr" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                  <path d="M0,0 L6,3 L0,6 Z" fill="#9ee0da" />
                </marker>
                <marker id="machArrCu" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                  <path d="M0,0 L6,3 L0,6 Z" fill="#f0c49a" />
                </marker>
              </defs>

              <rect x="20" y="16" width="920" height="88" rx="4" fill="url(#machTeal)" />
              <text x="36" y="42" className="arch-label">Day key · table pool</text>
              <rect x="36" y="54" width="250" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="48" y="77" className="arch-box" style={{ fontSize: 14 }}>Plugboard · 1 unique table</text>
              <rect x="304" y="54" width="344" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="316" y="77" className="arch-box" style={{ fontSize: 14 }}>16 forward/reverse rotor pools</text>
              <rect x="666" y="54" width="254" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="678" y="77" className="arch-box" style={{ fontSize: 14 }}>No reflector table</text>

              <rect x="20" y="120" width="920" height="260" rx="4" fill="url(#machInk)" />
              <text x="36" y="148" className="arch-label arch-label-light">Active slot · 9 unique tables / 10 accesses</text>

              <rect x="36" y="218" width="56" height="56" rx="2" fill="rgba(255,255,255,0.08)" stroke="#9ee0da" />
              <text x="50" y="243" className="arch-box" style={{ fontSize: 15 }}>PT</text>
              <text x="44" y="262" className="arch-sub">byte</text>
              <path d="M98 246 H118" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />

              <rect x="124" y="194" width="72" height="104" rx="2" fill="rgba(20,129,119,0.35)" stroke="#22a89c" />
              <text x="134" y="226" className="arch-box" style={{ fontSize: 13 }}>Plug</text>
              <text x="132" y="248" className="arch-sub">access 1</text>
              <text x="132" y="270" className="arch-sub">same table</text>

              <path d="M202 246 H220" stroke="#f0c49a" strokeWidth="1.5" markerEnd="url(#machArrCu)" />
              {['R1 fwd', 'R2 fwd', 'R3 fwd', 'R4 fwd'].map((label, index) => {
                const x = 226 + index * 92
                return (
                  <g key={label}>
                    <rect x={x} y="210" width="72" height="72" rx="2" fill="rgba(212,131,63,0.22)" stroke="#d4833f" />
                    <text x={x + 10} y="250" className="arch-box" style={{ fontSize: 13 }}>{label}</text>
                  </g>
                )
              })}

              <path d="M574 246 H596" stroke="#f0c49a" strokeWidth="1.5" markerEnd="url(#machArrCu)" />
              <rect x="602" y="190" width="166" height="112" rx="2" fill="url(#machCopper)" />
              <text x="620" y="222" className="arch-box" style={{ fontSize: 14 }}>Conjugated XOR</text>
              <text x="620" y="248" className="arch-sub">A_i^-1(</text>
              <text x="620" y="268" className="arch-sub">A_i(x) XOR k_i)</text>
              <text x="620" y="288" className="arch-sub">k_i = centerMask</text>

              <path d="M685 308 V328 H574" stroke="#f0c49a" strokeWidth="1.5" markerEnd="url(#machArrCu)" />
              <text x="226" y="344" className="arch-sub">R4 rev → R3 rev → R2 rev → R1 rev → same plug (access 2) → CT</text>

              <rect x="20" y="400" width="920" height="96" rx="4" fill="#e8ecef" stroke="rgba(13,19,34,0.12)" />
              <text x="36" y="428" className="arch-label-dark">Per-byte host schedule</text>
              <text x="36" y="458" className="arch-path">payload + independent centerMask + absoluteByteCounter → RTL counter validation → output</text>
              <text x="36" y="482" className="arch-path-note">The RTL boundary validates ordering; it contains no HMAC.</text>
            </svg>
            <figcaption>
              The active transfer is one plugboard, four forward tables, and four reverse tables:
              nine unique tables and a 2,304-byte burst. The plugboard appears at both ends, so one
              byte performs ten table accesses.
            </figcaption>
          </figure>

          <ul className="stack-list" style={{ marginTop: '1.5rem' }}>
            <li>
              <span className="mono">POOL</span>
              <span>
                <strong>Day blueprint:</strong> one plugboard plus 16 forward/reverse rotor pools.
                Four pairs populate the active slot; fixture-v4 has no reflector.
              </span>
            </li>
            <li>
              <span className="mono">CENTER</span>
              <span>
                <strong>XOR conjugate:</strong>{' '}
                <code>A_i^-1(A_i(x) XOR k_i)</code>, with <code>k_i</code> supplied as the independent
                <code> centerMask</code> for the byte.
              </span>
            </li>
            <li>
              <span className="mono">TABLES</span>
              <span>
                <strong>Bounded transfer:</strong> 9 unique 256-byte tables, 2,304 bytes total, and
                10 accesses because the same plugboard is traversed twice.
              </span>
            </li>
            <li>
              <span className="mono">ORDER</span>
              <span>
                <strong>Host schedule:</strong> the host derives and transports <code>payload</code>,{' '}
                <code>centerMask</code>, and <code>absoluteByteCounter</code>. RTL validates the
                counter; that boundary is not an HMAC implementation.
              </span>
            </li>
          </ul>
        </div>

        <div className="shell imagining">
          <div className="section-head">
            <div className="kicker">Imagining The Machine</div>
            <p>While the Enigma 256 is unlikely to be built, I wanted to imagine what it might look like, or might have looked like if it were to have been built in the time of Turing.</p>
            <figure className="arch-figure">
              <figcaption>AI Rotor Imagining</figcaption>
              <img src="/Rotor.svg" alt="Rotor" />
            </figure>
            <figure className="arch-figure">
              <figcaption>AI Plugboard Imagining</figcaption>
              <img src="/Plugboard.svg" alt="Plugboard" />
            </figure>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Hard facts</div>
            <h2>What the ghost hunt taught the designer</h2>
            <p>
              Flaws that cost Bletchley months—and cost me GPU-weeks—become explicit test surfaces.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">NO SELF-MAP</span>
              <span>
                <strong>M4 forbade A→A.</strong> That law is the crib-alignment wedge: ciphertext never equals plaintext at a position, so menus lock. Fixture-v4 does not use a reflector or a reserved-pair mode; its bounded reciprocal center is <code>A_i^-1(A_i(x) XOR k_i)</code>.
              </span>
            </li>
            <li>
              <span className="mono">STATIC LEFT</span>
              <span>
                <strong>Greek and left rotors sit still on short traffic.</strong> Pinning them collapsed my search by 676×—Turing’s reduction, still true in 2026. Fixture-v4 publishes a host-derived per-byte schedule, but the receipt does not establish resistance to an analogous external reduction.
              </span>
            </li>
            <li>
              <span className="mono">TEN PLUGS</span>
              <span>
                <strong>The Steckerbrett was a 10-cable involution.</strong> Ghost menus die when they demand an eleventh pair; TensorLUT only rediscovers plugs when reciprocity is structural. Fixture-v4 uses one full-byte plugboard at both ends of its path; that is an architecture fact, not cryptanalytic evidence.
              </span>
            </li>
            <li>
              <span className="mono">CODEBOOK</span>
              <span>
                <strong>Day keys lived on paper that dissolved.</strong> Capture of one sheet burned the net. E256’s host-side key derivation and transport sit outside the bounded fixture-v4 RTL receipt; no deployment-security claim follows from the KAT.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Chronology</div>
            <h2>From M4 wound to 256-bit machine, step by step</h2>
            <p>
              Each phase below is a finding from the U-534 campaign, then the bounded fixture-v4
              response. The response is experimental architecture, not proof of a secure cipher.
            </p>
          </div>
          <div className="timeline">
            <article className="tl-item">
              <div className="when">Phase A: Expand the alphabet</div>
              <h3>26 letters were a gift to the diagonal board.</h3>
              <div className="prose">
                <p>
                  Welchman menus, Naval trigrams, and Thetis cribs all assume a 26-symbol ring. A Metal cleartext batch can score every <code>26⁴</code> message key against a template in one shot. That density is why stochastic KPA is even thinkable on M4.
                </p>
                <p>
                  <E256Span /> uses the full byte space <code>0x00…0xFF</code>. The live day key has a plugboard plus 16 forward/reverse rotor pools and no reflector. The fixture-v4 receipt checks this implementation boundary; it does not claim that classical objectives cannot transfer or report external cryptanalysis.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase B: Replace the self-stecker law</div>
              <h3>A conjugated-XOR center replaces the historical reflector.</h3>
              <div className="prose">
                <p>
                  Every exact catalog negative and every Stochastic template bank still leaned on a machine that cannot encrypt a letter to itself. That invariant is how you place a crib before you search rings.
                </p>
                <p>
                  Fixture-v4 uses <code>A_i^-1(A_i(x) XOR k_i)</code>, where the host supplies
                  <code> k_i</code> as an independent <code>centerMask</code>. There is no reflector,
                  parity-selected center, or reserved pair in the live profile.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase C: Full-spectrum stecker</div>
              <h3>Stop giving the test fixture a cable count.</h3>
              <div className="prose">
                <p>
                  Phase 3 of the journal was the 10-plug trap: mathematical survivors that needed impossible boards. TensorLUT’s live arm freezes the M4 core and evolves a ≤10-pair involution by construction for the same reason—reciprocity and sparsity are the genotype.
                </p>
                <p>
                  Fixture-v4’s plugboard is one 256-entry table used at ingress and egress. It is
                  one of nine unique active tables but accounts for two of ten accesses. Those
                  counts are functional facts, not a claim about a Bombe or external attack.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase D: Per-byte schedule</div>
              <h3>Make ordering an explicit host/RTL contract.</h3>
              <div className="prose">
                <p>
                  Historical rotors step like a mileage counter. On a 72-letter Thetis message the Greek wheel never turns; the left rotor’s notch drives nothing. That mechanical truth is why my engine pins those drums and why ring-AAAA and right-ring sweeps are even affordable.
                </p>
                <p>
                  For every fixture-v4 byte, the host derives and transports <code>payload</code>,{' '}
                  <code>centerMask</code>, and <code>absoluteByteCounter</code>. RTL validates the
                  absolute counter. The center mask is independent; it is not selected by a
                  captured rotor-step parity.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase E: Host-derived day and byte material</div>
              <h3>No reflector hidden in the day blueprint.</h3>
              <div className="prose">
                <p>
                  M-Thetis died with its Grund table. Indicators <code>VROL NMKA</code> bought less than one bit because the starting-position book is gone. Sister traffic needed degarbling because paper and operators disagree.
                </p>
                <p>
                  The live day key contains a plugboard plus 16 forward/reverse rotor pools. The
                  host selects the active material and transports the per-byte tuple; fixture-v4
                  does not contain a reflector. The validation receipt is not an HMAC-security or
                  session-security proof.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase F: Silicon datapath</div>
              <h3>One compatibility tuple across host and RTL.</h3>
              <div className="prose">
                <p>
                  The Blue Team core loads the active plugboard and four forward/reverse rotor pairs:
                  9 unique tables and a 2,304-byte burst. One byte performs 10 table accesses because
                  the plugboard is used twice. RTL validates <code>absoluteByteCounter</code> and has
                  no HMAC.
                </p>
                <p>
                  The exact live tuple is{' '}
                  <code>E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4</code>.
                  Profile and KAT publication guards fail closed on mismatches; human acceptance is
                  still open.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase G: Red vs Blue</div>
              <h3>Record one bounded optimizer result without turning it into security.</h3>
              <div className="prose">
                <p>
                  The fixture-v4 TensorLUT target is a 366-LUT6 scramble cone with independent
                  <code> center_mask</code>. Its recorded verdict is <code>blue_hold</code>, with
                  <code> final_crypto -291592.781250</code> and <code>final_nonbinary 1217</code>.
                </p>
                <p>
                  This is only bounded optimizer failure. The target is not HMAC or the full E256
                  core, and the result is not a security level, work factor, IND-CPA claim, or
                  external cryptanalysis result.
                </p>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Implementation</div>
            <h2>What the fixture-v4 receipt establishes</h2>
            <p>
              The atomic KAT covers 1,024 bytes, 9 tables, 10 traces, and 25 artifacts. Equality is
              260/65536 with z=0.250; formal is 1/1 and the suite is 49/49. The receipt is{' '}
              <code>logs/e256-v2-gen0-fixture-v4-validation.json</code>.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">PROFILE</span>
              <span>
                <strong>Exact identity:</strong>{' '}
                <code>E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4</code>.
              </span>
            </li>
            <li>
              <span className="mono">CENTER</span>
              <span>
                <strong>Reciprocal center:</strong> <code>A_i^-1(A_i(x) XOR k_i)</code>, with the
                host-supplied <code>centerMask</code> as <code>k_i</code>. No reflector or
                reserved-pair mode is present.
              </span>
            </li>
            <li>
              <span className="mono">WIRE</span>
              <span>
                <strong>Host/RTL boundary:</strong> host derives and transports <code>payload</code>,{' '}
                <code>centerMask</code>, and <code>absoluteByteCounter</code>; RTL validates the
                counter and contains no HMAC.
              </span>
            </li>
            <li>
              <span className="mono">LOAD</span>
              <span>
                <strong>Active tables:</strong> plugboard plus R1–R4 forward/reverse, 9 unique
                tables, 2,304-byte burst, and 10 accesses because the plugboard is used twice.
              </span>
            </li>
            <li>
              <span className="mono">KAT</span>
              <span>
                <strong>Bounded parity:</strong> 1,024 bytes / 9 tables / 10 traces / 25 artifacts;
                equality 260/65536 (z=0.250), formal 1/1, suite 49/49.
              </span>
            </li>
            <li>
              <span className="mono">GUARD</span>
              <span>
                <strong>Publication fails closed:</strong>{' '}
                <code>testCanonicalGoldenPublicationRejectsMismatchedProfile</code>,{' '}
                <code>testProfileKATSplitPublicationFailsClosed</code>, and formal integrity guard
                the bounded profile/KAT publication path.
              </span>
            </li>
            <li>
              <span className="mono">RED</span>
              <span>
                <strong>TensorLUT scope:</strong> 366-LUT6 scramble cone with independent
                <code> center_mask</code>; <code>blue_hold</code>, final_crypto -291592.781250,
                final_nonbinary 1217. Not HMAC, not the full core, and not a work factor.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <span>
                <strong>E256-003:</strong> pending human acceptance. Until that review closes, this
                remains experimental, not for real data, and not a secure-deployment claim.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Plan</div>
            <h2>What remains, in order of honesty</h2>
            <p>
              Receipt completion and optimizer failure are evidence cells, not a security proof.
              Human review remains a separate gate.
            </p>
          </div>

          <div className="timeline">
            <article className="tl-item">
              <div className="when">1 — Receipt complete</div>
              <h3>Publish the bounded fixture-v4 functional evidence.</h3>
              <div className="prose">
                <p>
                  The 1,024-byte KAT, 9-table/10-trace/25-artifact bundle, equality check, formal
                  check, and 49/49 suite are recorded in the fixture-v4 validation receipt.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">2 — Bounded result</div>
              <h3>Keep the TensorLUT verdict inside its tested cone.</h3>
              <div className="prose">
                <p>
                  The 366-LUT6 scramble cone with independent <code>center_mask</code> ended
                  <code> blue_hold</code>. That says this bounded optimizer did not finish a binary
                  solution; it says nothing about HMAC, the full core, deployment security, or a
                  cryptanalytic work factor.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">3 — OPEN</div>
              <h3>E256-003 awaits human acceptance.</h3>
              <div className="prose">
                <p>
                  Keep fixture-v4 experimental and away from real data until the receipt receives
                  explicit human acceptance. No production or secure-deployment status is implied.
                </p>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Why rebuild it</div>
            <h2>The same footsteps, facing forward</h2>
            <p>
              Turing’s reductions still work on 1945 metal because the metal never changed. The
              fixture-v4 exercise turns those historical wedges into explicit architecture and
              test boundaries, then asks the same <HelutSpan /> stack a bounded question. It does
              not establish that the resulting experimental cipher is secure.
            </p>
          </div>
          <div className="prose">
            <p>
              The ghost message remains historically unbroken. Fixture-v4 is a research artifact
              with an open human-review gate, not a deployed successor and not a claim that the
              historical weaknesses have been eliminated under external cryptanalysis.
            </p>
            <p>
              Campaign ledger:{' '}
              <Link to="/projects/p1030680/journal"><NaziBlaster9000Span /></Link>
              {' · '}
              Hunt overview:{' '}
              <Link to="/enigma">Enigma</Link>
              {' · '}
              Spec:{' '}
              <a href="https://github.com/Digital-Defiance/HELUT/blob/main/Enigma256.md">Enigma256.md</a>
              .
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}
