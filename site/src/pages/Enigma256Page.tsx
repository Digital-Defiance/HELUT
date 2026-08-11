import { Link } from 'react-router-dom'

export function Enigma256Page() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Blue Team · 2026</div>
            <h2>Fixing Enigma for a century that can melt silicon</h2>
            <p className="lede">
              The hunt for P1030680 is a ledger of how the 1945 machine leaks. Every clean negative, every ghost board, every Turing-shaped shortcut I weaponized against M4 is also a specification for what a rotor cipher must never do again. Enigma 256 (E256) is that rewrite: a base-256 polymorphic stream cipher whose datapath is SoftBus-backed Verilog on Apple Silicon and whose keys never sit in a water-soluble codebook.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              This is not nostalgia hardware. It is the Blue Team answer to a Red Team that already runs Welchman, Stochastic KPA, and TensorLUT on Apple Silicon—built from the same findings documented in the{' '}
              <Link to="/journal">campaign journal</Link>.
            </p>
          </div>

          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">Live field</div>
              <div className="value">Gen 5 · SoftBus</div>
            </div>
            <div className="stat">
              <div className="label">KDF / AEAD</div>
              <div className="value">HKDF-SHA512</div>
            </div>
            <div className="stat">
              <div className="label">Handshake</div>
              <div className="value">X25519 ‖ ML-KEM</div>
            </div>
            <div className="stat">
              <div className="label">Red surface</div>
              <div className="value">Past NLFF</div>
            </div>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Architecture</div>
            <h2>Three planes on one Mac</h2>
            <p>
              Control plane never enters BRAM. Data plane is SoftBus ↔ <code>enigma_256_core</code>. Red melts synthesizable cones and grades SoftBus oracles; Blue rolls genes only under pressure.
            </p>
          </div>

          <figure className="arch-figure" aria-label="E256 architecture diagram">
            <svg viewBox="0 0 920 520" role="img" className="arch-svg">
              <title>E256 control plane, data plane, and Red/Blue field</title>
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
              </defs>

              {/* Control plane */}
              <rect x="24" y="24" width="872" height="118" rx="4" fill="url(#archCp)" />
              <text x="44" y="52" className="arch-label">Control plane · Swift / CryptoKit</text>
              <rect x="44" y="68" width="190" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="54" y="90" className="arch-box">Handshake</text>
              <text x="54" y="108" className="arch-sub">X25519 ‖ ML-KEM · Ed25519</text>
              <path d="M240 94 H268" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#archArrow)" />
              <rect x="274" y="68" width="170" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="284" y="90" className="arch-box">HKDF-SHA512</text>
              <text x="284" y="108" className="arch-sub">day · msg · mac</text>
              <path d="M450 94 H478" stroke="#9ee0da" strokeWidth="1.5" />
              <rect x="484" y="68" width="170" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="494" y="90" className="arch-box">AEAD + nonce</text>
              <text x="494" y="108" className="arch-sub">HMAC-SHA512 · counter</text>
              <path d="M660 94 H688" stroke="#9ee0da" strokeWidth="1.5" />
              <rect x="694" y="68" width="178" height="52" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="704" y="90" className="arch-box">E2W1 · TCP</text>
              <text x="704" y="108" className="arch-sub">verify before fabric</text>

              {/* Arrow control → data */}
              <path d="M360 142 V168" stroke="var(--ink-soft, #2a374e)" strokeWidth="1.5" strokeDasharray="4 3" />
              <text x="372" y="162" className="arch-flow">day + message key · tables</text>

              {/* Data plane */}
              <rect x="24" y="172" width="560" height="180" rx="4" fill="url(#archDp)" />
              <text x="44" y="200" className="arch-label arch-label-light">Data plane · SoftBus ↔ enigma_256_core</text>
              <rect x="44" y="220" width="150" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="54" y="248" className="arch-box">Burst load</text>
              <text x="54" y="268" className="arch-sub">10×256 BRAM</text>
              <text x="54" y="286" className="arch-sub">AXIS / SoftBus</text>
              <text x="54" y="304" className="arch-sub">CTRL[1] arm</text>
              <path d="M200 270 H228" stroke="#d4833f" strokeWidth="1.5" />
              <rect x="234" y="220" width="200" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="244" y="248" className="arch-box">Core stream</text>
              <text x="244" y="268" className="arch-sub">plug → R1…R4 → UKW</text>
              <text x="244" y="286" className="arch-sub">→ rev → plug</text>
              <text x="244" y="304" className="arch-sub">scramble then NLFF step</text>
              <path d="M440 270 H468" stroke="#d4833f" strokeWidth="1.5" />
              <rect x="474" y="220" width="90" height="100" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(212,131,63,0.45)" />
              <text x="486" y="262" className="arch-box">CT</text>
              <text x="482" y="284" className="arch-sub">DATA_OUT</text>

              {/* Red / Blue */}
              <rect x="604" y="172" width="292" height="180" rx="4" fill="url(#archRed)" />
              <text x="624" y="200" className="arch-label">Red / Blue field</text>
              <text x="624" y="228" className="arch-box">ent · SoftBus KPA</text>
              <text x="624" y="252" className="arch-box">TensorLUT cones</text>
              <text x="624" y="276" className="arch-sub">NLFF → +lfsr_hi → +offsets</text>
              <text x="624" y="300" className="arch-sub">gen 5 genes · campaign gates</text>
              <text x="624" y="324" className="arch-sub">mutate only under pressure</text>

              {/* Byte path strip */}
              <rect x="24" y="372" width="872" height="124" rx="4" fill="#e8ecef" stroke="rgba(13,19,34,0.12)" />
              <text x="44" y="400" className="arch-label-dark">Reciprocal byte path</text>
              <text x="44" y="430" className="arch-path">PT → plug → R1±off → R2±off → R3±off → R4±off → un-reflector → rev path → plug → CT</text>
              <text x="44" y="458" className="arch-path-note">Un-reflector allows fixed points · encrypt ≡ decrypt · gen 5 cubic6 NLFF clocks all four offsets</text>
              <text x="44" y="482" className="arch-path-note">Full-core BRAM melt deferred · past-NLFF offset cone (~47 LUT6) is the live Red surface</text>
            </svg>
            <figcaption>
              SoftBus is the field fabric. Spec detail and mermaid sources live in{' '}
              <a href="https://github.com/Digital-Defiance/HELUT/blob/main/Enigma256.md">Enigma256.md</a>.
            </figcaption>
          </figure>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The machine</div>
            <h2>How the wheels and plugboard actually connect</h2>
            <p>
              Four active 256-entry rotors sit between a full-spectrum plugboard and an un-reflector. Offsets are not notches—they are bytes advanced by a Galois LFSR through NLFF step enables after every symbol.
            </p>
          </div>

          <figure className="arch-figure" aria-label="E256 machine internals diagram">
            <svg viewBox="0 0 960 640" role="img" className="arch-svg">
              <title>E256 rotor machine: plugboard, four rotors, un-reflector, LFSR stepping</title>
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

              {/* Day / message key strip */}
              <rect x="20" y="16" width="920" height="88" rx="4" fill="url(#machTeal)" />
              <text x="36" y="42" className="arch-label">Keying · day pool → message slot</text>
              <rect x="36" y="54" width="200" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="48" y="77" className="arch-box" style={{ fontSize: 14 }}>Day: 16-rotor pool</text>
              <rect x="252" y="54" width="200" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="264" y="77" className="arch-box" style={{ fontSize: 14 }}>Plug + un-reflector</text>
              <path d="M460 72 H488" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />
              <rect x="496" y="54" width="210" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="508" y="77" className="arch-box" style={{ fontSize: 14 }}>Nonce → 4 of 16 + offs</text>
              <path d="M714 72 H742" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />
              <rect x="750" y="54" width="170" height="36" rx="2" fill="rgba(255,255,255,0.08)" stroke="rgba(158,224,218,0.35)" />
              <text x="762" y="77" className="arch-box" style={{ fontSize: 14 }}>LFSR seed 64b</text>

              {/* Main chassis */}
              <rect x="20" y="120" width="920" height="360" rx="4" fill="url(#machInk)" />
              <text x="36" y="148" className="arch-label arch-label-light">Scramble path · base-256 · reciprocal</text>

              {/* PT */}
              <rect x="36" y="250" width="56" height="56" rx="2" fill="rgba(255,255,255,0.08)" stroke="#9ee0da" />
              <text x="50" y="275" className="arch-box" style={{ fontSize: 15 }}>PT</text>
              <text x="44" y="294" className="arch-sub">byte</text>

              {/* Plugboard in */}
              <path d="M98 278 H118" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />
              <rect x="124" y="220" width="72" height="116" rx="2" fill="rgba(20,129,119,0.35)" stroke="#22a89c" />
              <text x="134" y="250" className="arch-box" style={{ fontSize: 13 }}>Plug</text>
              <text x="132" y="270" className="arch-sub">256</text>
              <text x="132" y="288" className="arch-sub">invo-</text>
              <text x="132" y="306" className="arch-sub">lution</text>
              <text x="132" y="324" className="arch-sub">128 pr</text>

              {/* Forward rotors */}
              <path d="M202 278 H220" stroke="#f0c49a" strokeWidth="1.5" markerEnd="url(#machArrCu)" />
              {[
                { x: 226, label: 'R1', sub: 'fwd' },
                { x: 318, label: 'R2', sub: 'fwd' },
                { x: 410, label: 'R3', sub: 'fwd' },
                { x: 502, label: 'R4', sub: 'fwd' },
              ].map((r) => (
                <g key={`fwd-${r.label}`}>
                  <rect x={r.x} y="200" width="72" height="72" rx="2" fill="rgba(212,131,63,0.22)" stroke="#d4833f" />
                  <text x={r.x + 18} y="230" className="arch-box" style={{ fontSize: 16 }}>{r.label}</text>
                  <text x={r.x + 22} y="252" className="arch-sub">{r.sub} 256</text>
                  <text x={r.x + 8} y="180" className="arch-sub">+off −off</text>
                </g>
              ))}
              <path d="M298 236 H312" stroke="#f0c49a" strokeWidth="1.5" />
              <path d="M390 236 H404" stroke="#f0c49a" strokeWidth="1.5" />
              <path d="M482 236 H496" stroke="#f0c49a" strokeWidth="1.5" />

              {/* Un-reflector */}
              <path d="M580 236 H598" stroke="#f0c49a" strokeWidth="1.5" markerEnd="url(#machArrCu)" />
              <rect x="604" y="188" width="96" height="96" rx="2" fill="url(#machCopper)" />
              <text x="618" y="224" className="arch-box" style={{ fontSize: 14 }}>Un-UKW</text>
              <text x="616" y="246" className="arch-sub">fixed pts OK</text>
              <text x="622" y="266" className="arch-sub">involution</text>

              {/* Reverse rotors */}
              <path d="M652 300 V320" stroke="#f0c49a" strokeWidth="1.5" />
              <path d="M652 320 H574" stroke="#f0c49a" strokeWidth="1.5" />
              {[
                { x: 502, label: 'R4', sub: 'rev' },
                { x: 410, label: 'R3', sub: 'rev' },
                { x: 318, label: 'R2', sub: 'rev' },
                { x: 226, label: 'R1', sub: 'rev' },
              ].map((r) => (
                <g key={`rev-${r.label}`}>
                  <rect x={r.x} y="328" width="72" height="72" rx="2" fill="rgba(212,131,63,0.12)" stroke="rgba(240,196,154,0.7)" strokeDasharray="3 2" />
                  <text x={r.x + 18} y="358" className="arch-box" style={{ fontSize: 16 }}>{r.label}</text>
                  <text x={r.x + 22} y="380" className="arch-sub">{r.sub} 256</text>
                </g>
              ))}
              <path d="M502 364 H486" stroke="#f0c49a" strokeWidth="1.5" />
              <path d="M410 364 H394" stroke="#f0c49a" strokeWidth="1.5" />
              <path d="M318 364 H302" stroke="#f0c49a" strokeWidth="1.5" />

              {/* Plugboard out + CT */}
              <path d="M226 364 H202" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />
              <path d="M160 336 V364" stroke="#9ee0da" strokeWidth="1.5" />
              <path d="M160 364 H196" stroke="#9ee0da" strokeWidth="1.5" />
              <text x="132" y="360" className="arch-sub">same</text>
              <text x="132" y="376" className="arch-sub">table</text>
              <path d="M124 336 H98" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#machArr)" />
              <rect x="36" y="336" width="56" height="56" rx="2" fill="rgba(255,255,255,0.08)" stroke="#9ee0da" />
              <text x="50" y="361" className="arch-box" style={{ fontSize: 15 }}>CT</text>
              <text x="44" y="380" className="arch-sub">byte</text>

              {/* Stage math callout */}
              <rect x="720" y="200" width="200" height="168" rx="2" fill="rgba(255,255,255,0.06)" stroke="rgba(158,224,218,0.3)" />
              <text x="736" y="228" className="arch-box" style={{ fontSize: 14 }}>Per rotor stage</text>
              <text x="736" y="254" className="arch-sub">in  = x + offset</text>
              <text x="736" y="274" className="arch-sub">y  = table[in]</text>
              <text x="736" y="294" className="arch-sub">out = y − offset</text>
              <text x="736" y="320" className="arch-sub">mod 256 arithmetic</text>
              <text x="736" y="344" className="arch-sub">fwd then rev tables</text>
              <text x="736" y="364" className="arch-sub">are inverses</text>

              {/* Stepping engine */}
              <rect x="20" y="500" width="920" height="120" rx="4" fill="#e8ecef" stroke="rgba(13,19,34,0.12)" />
              <text x="36" y="528" className="arch-label-dark">After CT emits · step engine</text>
              <rect x="36" y="544" width="160" height="56" rx="2" fill="#0f3034" />
              <text x="52" y="568" className="arch-box" style={{ fontSize: 14 }}>Galois LFSR</text>
              <text x="48" y="588" className="arch-sub">64b · 0xD800…</text>
              <path d="M204 572 H228" stroke="#148177" strokeWidth="1.5" />
              <rect x="236" y="544" width="160" height="56" rx="2" fill="#1f6f6a" />
              <text x="260" y="568" className="arch-box" style={{ fontSize: 14 }}>NLFF cubic6</text>
              <text x="248" y="588" className="arch-sub">gen 5 bred taps</text>
              <path d="M404 572 H428" stroke="#148177" strokeWidth="1.5" />
              <rect x="436" y="544" width="220" height="56" rx="2" fill="#2a374e" />
              <text x="452" y="568" className="arch-box" style={{ fontSize: 14 }}>step_r1…r4</text>
              <text x="448" y="588" className="arch-sub">each ≈ ½ · low φ</text>
              <path d="M664 572 H688" stroke="#a86227" strokeWidth="1.5" />
              <rect x="696" y="544" width="224" height="56" rx="2" fill="#a86227" />
              <text x="712" y="568" className="arch-box" style={{ fontSize: 14 }}>offset_ri += step_ri</text>
              <text x="708" y="588" className="arch-sub">then LFSR clocks</text>
            </svg>
            <figcaption>
              Forward path (solid) through plugboard and four rotors to the un-reflector; return path (dashed) uses reverse tables and the same plugboard. Encrypt equals decrypt under one state.
            </figcaption>
          </figure>

          <ul className="stack-list" style={{ marginTop: '1.5rem' }}>
            <li>
              <span className="mono">POOL</span>
              <span>
                <strong>Day blueprint:</strong> HKDF expands a 16-rotor virtual warehouse plus plugboard and un-reflector. Only four rotors are selected per nonce (Walzenlage) and burst into SoftBus.
              </span>
            </li>
            <li>
              <span className="mono">OFFSET</span>
              <span>
                <strong>Not notches:</strong> each active rotor carries an 8-bit offset. Stage math is <code>(table[x+off] − off)</code> mod 256 — the classical “wiring through a turned wheel,” without odometer geometry.
              </span>
            </li>
            <li>
              <span className="mono">UKW</span>
              <span>
                <strong>Un-reflector:</strong> still an involution (so the machine stays reciprocal), but fixed points are legal. That kills the historical “never encrypts as itself” crib wedge.
              </span>
            </li>
            <li>
              <span className="mono">ORDER</span>
              <span>
                <strong>Scramble then step:</strong> CT is emitted under the current offsets; then NLFF decides which offsets advance and the LFSR clocks — matching <code>Enigma256Machine.process</code> and <code>enigma_256_core.v</code>.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Hard facts</div>
            <h2>What the ghost hunt taught the designer</h2>
            <p>
              Flaws that cost Bletchley months—and cost me GPU-weeks—become permanent design bans.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">NO SELF-MAP</span>
              <span>
                <strong>M4 forbade A→A.</strong> That law is the crib-alignment wedge: ciphertext never equals plaintext at a position, so menus lock. E256’s un-reflector is an involution that <em>permits</em> fixed points, blinding known-plaintext placement and ciphertext-only cribbing of that form.
              </span>
            </li>
            <li>
              <span className="mono">STATIC LEFT</span>
              <span>
                <strong>Greek and left rotors sit still on short traffic.</strong> Pinning them collapsed my search by 676×—Turing’s reduction, still true in 2026. E256 drives all four active rotors from a 64-bit Galois LFSR every byte, so the “left wheels never move” assumption is dead.
              </span>
            </li>
            <li>
              <span className="mono">TEN PLUGS</span>
              <span>
                <strong>The Steckerbrett was a 10-cable involution.</strong> Ghost menus die when they demand an eleventh pair; TensorLUT only rediscovers plugs when reciprocity is structural. E256 loads a full 128-pair base-256 plugboard from HKDF—no cable budget for a Welchman kill chain to exploit.
              </span>
            </li>
            <li>
              <span className="mono">CODEBOOK</span>
              <span>
                <strong>Day keys lived on paper that dissolved.</strong> Capture of one sheet burned the net. E256 derives session material from X25519 (optionally hybrid with ML-KEM-768) + <strong>HKDF-SHA512</strong>; Ed25519 identities bind hybrid HELLO/ACK against MitM. Ephemeral keys burn at session end.
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
              Each phase below is a finding from the U-534 campaign, then the architectural correction that became E256.
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
                  E256 replaces the alphabet with the full byte space <code>0x00…0xFF</code>. Rotors, plugboard, and reflector are 256-entry tables. The classical menu graph and letter-match objective do not transfer; the machine speaks octets, not Kriegsmarine spelling.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase B: Kill the self-stecker law</div>
              <h3>The un-reflector blinds crib alignment.</h3>
              <div className="prose">
                <p>
                  Every exact catalog negative and every Stochastic template bank still leaned on a machine that cannot encrypt a letter to itself. That invariant is how you place a crib before you search rings.
                </p>
                <p>
                  The E256 reflector is still an involution—reciprocal encrypt/decrypt survives—but fixed points are allowed. Self-mapping is no longer a forbidden residue that points a Boolean board at the right offset.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase C: Full-spectrum stecker</div>
              <h3>Stop giving the kill chain a cable count.</h3>
              <div className="prose">
                <p>
                  Phase 3 of the journal was the 10-plug trap: mathematical survivors that needed impossible boards. TensorLUT’s live arm freezes the M4 core and evolves a ≤10-pair involution by construction for the same reason—reciprocity and sparsity are the genotype.
                </p>
                <p>
                  E256’s plugboard is a complete base-256 involution: 128 pairs, Fisher–Yates-derived from the day-key OKM. There is no “eleventh cable” rejection rule. The stecker space is no longer a 47-bit pocket the Bombe can squeeze.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase D: LFSR stepping</div>
              <h3>Destroy the odometer that Turing pinned.</h3>
              <div className="prose">
                <p>
                  Historical rotors step like a mileage counter. On a 72-letter Thetis message the Greek wheel never turns; the left rotor’s notch drives nothing. That mechanical truth is why my engine pins those drums and why ring-AAAA and right-ring sweeps are even affordable.
                </p>
                <p>
                  E256 clocks a 64-bit Galois LFSR (primitive taps 64, 63, 61, 60 → feedback <code>0xD800_0000_0000_0000</code>) on every byte. Step enables are <strong>not</strong> raw LFSR bits—live gen 5 uses bred <strong>cubic6</strong> six-tap folds so observable rotor motion does not hand Berlekamp–Massey a linear system. All wheels can move every symbol; static-left assumptions die.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase E: Ephemeral day and message keys</div>
              <h3>No more dissolved key sheets.</h3>
              <div className="prose">
                <p>
                  M-Thetis died with its Grund table. Indicators <code>VROL NMKA</code> bought less than one bit because the starting-position book is gone. Sister traffic needed degarbling because paper and operators disagree.
                </p>
                <p>
                  E256 splits control and data planes. Software runs X25519 and, on macOS 26+, hybrid ML-KEM (or X-Wing), then <strong>HKDF-SHA512</strong> into a day-key blueprint: plugboard shuffle, 16-rotor virtual pool, un-reflector. Each packet carries a plaintext nonce; a micro-HKDF picks Walzenlage (4 of 16), Grundstellung, and LFSR seed. Capture of one session does not decrypt the next.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase F: Silicon datapath</div>
              <h3>Same contract in Swift and Verilog.</h3>
              <div className="prose">
                <p>
                  The Blue Team core is <code>enigma_256_core</code>: AXI-friendly BRAM load for plugboard / four rotors fwd+rev / reflector, then <code>load_state</code> for LFSR + positions, then a streaming <code>valid_in</code> byte path. Combinational scramble under current offsets, register the output, then step—matching the Swift oracle’s scramble-then-step order.
                </p>
                <p>
                  Control plane stays in Swift (CryptoKit HKDF, ECDH). Data plane is exercised on <strong>Apple Silicon SoftBus</strong> with iverilog/Yosys as the Red harness—no board on the critical path. Generation rolls ship as SoftBus genes plus NLFF Verilog rewrites.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase G: Red vs Blue</div>
              <h3>Evolve the cipher against the same engines that hunt M4.</h3>
              <div className="prose">
                <p>
                  HELUT already breeds alien netlists, melts LUT INIT tables, and scores stecker involutions. That Red Team is the continuous adversary on this Mac: SoftBus KPA, fail-closed <code>ent</code>, and TensorLUT against expanding cones (NLFF → offsets). If pressure crosses threshold, Blue mutates NLFF folds and HKDF generation labels via <code>--enigma256-campaign-mutate</code>.
                </p>
                <p>
                  Boundary rule: past-NLFF offset cone is fair game; full-core BRAM soft-map stays deferred. SoftBus is the field fabric—the cipher does not wait for a Zynq.
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
            <h2>What is on disk today</h2>
            <p>
              Spec in <code>Enigma256.md</code>. Oracle and KDF in <code>Sources/HELUTCore/Enigma256.swift</code>. FPGA datapath in <code>enigma_256_core.v</code>. Bridge and golden session export in <code>Enigma256Bridge.swift</code>. Reciprocity and HKDF round-trips are gated by <code>Enigma256Tests</code>.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">LOAD</span>
              <span>
                <strong>Table port:</strong> <code>wr_sel</code> 0…9 fills plugboard, R1–R4 forward/reverse, reflector. Software pushes the active slot only—day pool stays off-chip until Walzenlage picks four rotors.
              </span>
            </li>
            <li>
              <span className="mono">STEP</span>
              <span>
                <strong>Galois + NLFF:</strong> feedback <code>0xD800_0000_0000_0000</code>. Live field is gen 5 balanced cubic6 (~0.5 step rate, low φ). Blue evolves stronger stepping—not TensorLUT-only hardness. Genes in <code>Fixtures/enigma256_generation.json</code>. Zero seed forced to 1.
              </span>
            </li>
            <li>
              <span className="mono">AEAD</span>
              <span>
                <strong>Integrity:</strong> HMAC-SHA512 tag on <code>nonce‖ciphertext</code> (E256 v2). Wire verifies before SoftBus/AXI. <code>Enigma256ProtectedSession</code> forbids nonce reuse under one IKM.
              </span>
            </li>
            <li>
              <span className="mono">BURST</span>
              <span>
                <strong>Table DMA:</strong> AXIS loader wired into <code>enigma_256_axi</code> (CTRL[1] arm, 2,560 B). SoftBus burst + optional <code>SCA_CTRL</code> jitter. Co-sim default is AXIS.
              </span>
            </li>
            <li>
              <span className="mono">RED</span>
              <span>
                <strong>TensorLUT cones:</strong> NLFF (4 LUT6) → +<code>lfsr_next_hi</code> (8) → <strong>past NLFF</strong> offset next-state (~47 LUT6, <code>enigma_256_nlff_offset_combo.v</code>). Full BRAM flatten deferred.
              </span>
            </li>
            <li>
              <span className="mono">GATE</span>
              <span>
                <strong>Fail-closed:</strong> SoftBus <code>ent</code> (PRNG PT) + structured KPA (partial leak + day-only joint). Campaign default; <code>--no-gates</code> to skip.
              </span>
            </li>
            <li>
              <span className="mono">RB</span>
              <span>
                <strong>Campaign:</strong> <code>Scripts/enigma256_rb_campaign.sh</code> — gates, SoftBus KPA ledger, <code>--hard-red</code> / <code>--wide</code> (offset cone) with TensorLUT <code>expect-hold</code>.
              </span>
            </li>
            <li>
              <span className="mono">PATH</span>
              <span>
                <strong>Byte scrambler:</strong> plugboard → four forward rotors with offset add/sub → un-reflector → four reverse rotors → plugboard. Encrypt equals decrypt under the same state machine.
              </span>
            </li>
            <li>
              <span className="mono">HOLD</span>
              <span>
                <strong>Full-core melt:</strong> NLFF cone is fair game; do not soft-map the BRAM datapath until a campaign generation explicitly asks for it.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Plan</div>
            <h2>What ships next, in order of honesty</h2>
            <p>
              A cipher that claims to outrun HELUT must be graded the way the journal grades the Bombe: controls first, then adversarial pressure, then SoftBus generation rolls on Apple Silicon.
            </p>
          </div>

          <div className="timeline">
            <article className="tl-item">
              <div className="when">1 — Done</div>
              <h3>Lock the reciprocal oracle and Verilog contract.</h3>
              <div className="prose">
                <p>
                  Identity and HKDF-derived wirings round-trip; LFSR feedback matches the core; scramble-before-step order is shared. That is the existence proof of a correct machine.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">2 — Done</div>
              <h3>Control plane: SHA-512 KDF, hybrid PQ, Ed25519 auth.</h3>
              <div className="prose">
                <p>
                  HKDF-SHA512 and PBKDF2-HMAC-SHA512 feed the day key. Hybrid <code>X25519_SS ‖ ML-KEM_SS</code> resists store-now-decrypt-later; Ed25519-signed hybrid wire frames close MitM—still zero Verilog change on that path.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">3 — Done</div>
              <h3>Data-plane hardening: NLFF, AEAD, nonce guard, burst, jitter.</h3>
              <div className="prose">
                <p>
                  NLFF stepping in Verilog and Swift; HMAC-SHA512 AEAD on wire/file with verify-before-fabric; monotonic nonce sessions; AXIS/SoftBus table burst; optional stream jitter for DPA. Dual-rail masked LUTs remain the high-assurance synthesis path.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">4 — Done</div>
              <h3>AXIS table burst + deliberate TensorLUT on NLFF cone.</h3>
              <div className="prose">
                <p>
                  <code>enigma_256_axi</code> loads day tables over AXI-Stream (2,560 bytes; CTRL[1] arms). Yosys keeps BRAMs for FPGA-style synth; TensorLUT hits the 4-LUT NLFF cone—baseline crypto 0, and λ=0 explore + discrete polish recovers a binary elite (`squeeze_survived`). Listen/connect default to hybrid+AEAD. Full-core soft-map stays deferred.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">5 — Live</div>
              <h3>Gen 5 SoftBus field with fail-closed gates.</h3>
              <div className="prose">
                <p>
                  Balanced cubic6 genes; <code>ent</code> + structured KPA gate every campaign; gen-5 Red battery holds. No Zynq on the critical path.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">6 — Live</div>
              <h3>Push Red past NLFF: offset next-state cone.</h3>
              <div className="prose">
                <p>
                  <code>enigma_256_nlff_offset_combo</code> exposes step enables plus <code>next_ri = offset_ri + step_ri</code> (~47 LUT6). Campaign <code>--wide</code> expects TensorLUT <code>blue_hold</code>. Full-core BRAM melt stays deferred.
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
              Turing’s reductions still work on 1945 metal because the metal never changed. Rebuilding Enigma without deleting those reductions would be theater. E256 is the opposite gesture: take every wedge the journal proved—self-stecker law, static left wheels, thin plugboards, paper day keys—and engineer them out, then invite the same HELUT stack to try again.
            </p>
          </div>
          <div className="prose">
            <p>
              The ghost message remains historically unbroken. The machine that produced it does not get a sequel that fails the same way. Spec, oracle, and core are the first Blue Team commit; the Red Team loop is the promise that this cipher keeps evolving under fire.
            </p>
            <p>
              Campaign ledger:{' '}
              <Link to="/journal">Turing Complete</Link>
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
