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
              The hunt for P1030680 is a ledger of how the 1945 machine leaks. Every clean negative, every ghost board, every Turing-shaped shortcut I weaponized against M4 is also a specification for what a rotor cipher must never do again. Enigma 256 is that rewrite: a base-256 polymorphic stream cipher whose datapath lives in FPGA fabric and whose keys never sit in a water-soluble codebook.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              This is not nostalgia hardware. It is the Blue Team answer to a Red Team that already runs Welchman, Stochastic KPA, and TensorLUT on Apple Silicon—built from the same findings documented in the{' '}
              <Link to="/journal">campaign journal</Link>.
            </p>
          </div>

          <div className="status-strip">
            <div className="stat">
              <div className="label">Alphabet</div>
              <div className="value">Base-256 bytes</div>
            </div>
            <div className="stat">
              <div className="label">KDF</div>
              <div className="value">HKDF-SHA512</div>
            </div>
            <div className="stat">
              <div className="label">Handshake</div>
              <div className="value">X25519 ‖ ML-KEM</div>
            </div>
            <div className="stat">
              <div className="label">Datapath</div>
              <div className="value">enigma_256_core.v</div>
            </div>
          </div>
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
                <strong>M4 forbade A→A.</strong> That law is the crib-alignment wedge: ciphertext never equals plaintext at a position, so menus lock. Enigma 256’s un-reflector is an involution that <em>permits</em> fixed points, blinding known-plaintext placement and ciphertext-only cribbing of that form.
              </span>
            </li>
            <li>
              <span className="mono">STATIC LEFT</span>
              <span>
                <strong>Greek and left rotors sit still on short traffic.</strong> Pinning them collapsed my search by 676×—Turing’s reduction, still true in 2026. Enigma 256 drives all four active rotors from a 64-bit Galois LFSR every byte, so the “left wheels never move” assumption is dead.
              </span>
            </li>
            <li>
              <span className="mono">TEN PLUGS</span>
              <span>
                <strong>The Steckerbrett was a 10-cable involution.</strong> Ghost menus die when they demand an eleventh pair; TensorLUT only rediscovers plugs when reciprocity is structural. Enigma 256 loads a full 128-pair base-256 plugboard from HKDF—no cable budget for a Welchman kill chain to exploit.
              </span>
            </li>
            <li>
              <span className="mono">CODEBOOK</span>
              <span>
                <strong>Day keys lived on paper that dissolved.</strong> Capture of one sheet burned the net. Enigma 256 derives session material from X25519 (optionally hybrid with ML-KEM-768) + <strong>HKDF-SHA512</strong>; Ed25519 identities bind hybrid HELLO/ACK against MitM. Ephemeral keys burn at session end.
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
              Each phase below is a finding from the U-534 campaign, then the architectural correction that became Enigma 256.
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
                  Enigma 256 replaces the alphabet with the full byte space <code>0x00…0xFF</code>. Rotors, plugboard, and reflector are 256-entry tables. The classical menu graph and letter-match objective do not transfer; the machine speaks octets, not Kriegsmarine spelling.
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
                  The Enigma 256 reflector is still an involution—reciprocal encrypt/decrypt survives—but fixed points are allowed. Self-mapping is no longer a forbidden residue that points a Boolean board at the right offset.
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
                  Enigma 256’s plugboard is a complete base-256 involution: 128 pairs, Fisher–Yates-derived from the day-key OKM. There is no “eleventh cable” rejection rule. The stecker space is no longer a 47-bit pocket the Bombe can squeeze.
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
                  Enigma 256 clocks a 64-bit Galois LFSR (primitive taps 64, 63, 61, 60 → feedback <code>0xD800_0000_0000_0000</code>) on every byte. Step enables are <strong>not</strong> raw LFSR bits—they pass a non-linear fold <code>(bit_a &amp; bit_b) ^ bit_c</code> so observable rotor motion does not hand Berlekamp–Massey a linear system. All wheels can move every symbol; static-left assumptions die.
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
                  Enigma 256 splits control and data planes. Software runs X25519 and, on macOS 26+, hybrid ML-KEM (or X-Wing), then <strong>HKDF-SHA512</strong> into a day-key blueprint: plugboard shuffle, 16-rotor virtual pool, un-reflector. Each packet carries a plaintext nonce; a micro-HKDF picks Walzenlage (4 of 16), Grundstellung, and LFSR seed. Capture of one session does not decrypt the next.
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
                  Control plane stays on the CPU (CryptoKit HKDF, ECDH libraries). Data plane stays in programmable logic on COTS SoCs—no custom ASIC. Mutation parameters (LFSR taps, expansion labels) can ship as software; the node recompiles and flashes its own fabric.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase G: Red vs Blue</div>
              <h3>Evolve the cipher against the same engines that hunt M4.</h3>
              <div className="prose">
                <p>
                  HELUT already breeds alien netlists, melts LUT INIT tables, and scores stecker involutions. That Red Team becomes the continuous adversary: time-to-crack metrics against the current Enigma 256 generation. If a tensor reduction drops below threshold, the Blue Team breeds new LFSR taps and rotor-generation rules and rolls them to the field.
                </p>
                <p>
                  Boundary rule, written into the spec and the Verilog header: do <em>not</em> TensorLUT-melt <code>enigma_256_core.v</code> until golden encrypt/decrypt vectors exist and Yosys synthesis is clean. TensorLUT remains the attack harness for M4 and evolved netlists; Enigma 256 first needs a correct reciprocal machine, then a deliberate adversarial loop—not a premature stecker-style melt.
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
                <strong>Galois + NLFF:</strong> feedback <code>0xD800_0000_0000_0000</code>; step enables <code>(lfsr[i] &amp; lfsr[i+7]) ^ lfsr[i+12]</code> for bases 0, 15, 31, 47. Zero seed forced to 1.
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
                <strong>TensorLUT:</strong> NLFF combo → 4 LUT6 baseline (<code>enigma_256_tensorlut_baseline.v</code>). Cold-start smoke in <code>logs/tensorlut-enigma256-nlff.log</code>. Full BRAM flatten deferred.
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
                <strong>TensorLUT hold line:</strong> melt only after golden vectors and a clean Yosys netlist. Until then, Red Team pressure stays on M4 TensorLUT / Welchman / Stochastic arms documented in the journal.
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
              A cipher that claims to outrun HELUT must be graded the way the journal grades the Bombe: controls first, then adversarial pressure, then field mutation.
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
                  <code>enigma_256_axi</code> loads day tables over AXI-Stream (2,560 bytes; CTRL[1] arms). Yosys keeps BRAMs for FPGA; TensorLUT hits the 4-LUT NLFF cone—baseline crypto 0, and λ=0 explore + discrete polish recovers a binary elite (`squeeze_survived`). Listen/connect default to hybrid+AEAD. Full-core soft-map stays deferred.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">5 — Field</div>
              <h3>COTS SoC data plane + OTA mutation.</h3>
              <div className="prose">
                <p>
                  Burst-load day-key tables on real fabric; keep hybrid KEM, HKDF-SHA512, and AEAD on the control plane; flash polymorphic updates without new silicon.
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
              Turing’s reductions still work on 1945 metal because the metal never changed. Rebuilding Enigma without deleting those reductions would be theater. Enigma 256 is the opposite gesture: take every wedge the journal proved—self-stecker law, static left wheels, thin plugboards, paper day keys—and engineer them out, then invite the same HELUT stack to try again.
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
