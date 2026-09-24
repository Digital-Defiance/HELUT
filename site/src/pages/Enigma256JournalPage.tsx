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
              <span className="mono">REWORK</span>
              <span>
                The repaired round is a separate research machine. Fixture-v4{' '}
                <code>enigma_256_core</code> is unchanged. The chronology is below.
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

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Research · 24 September 2026</div>
            <h2>The repaired machine</h2>
            <p>
              A 256-bit rotor round, checked as a datapath. Experimental. It does not replace
              fixture-v4, and it is not a security claim.
            </p>
          </div>
          <div className="timeline">
            <article className="tl-item">
              <div className="when">What changed</div>
              <h3>One wide round, encrypt and decrypt on different paths.</h3>
              <div className="prose">
                <p>
                  The live core still walks a byte through forward rotors, a center XOR, and the
                  reverse rotors. The research module leaves that file alone. Its state is 32
                  bytes. Each round XORs a 32-byte mask, runs the AES S-box on all 32 lanes,
                  shifts rows by <code>(0,1,3,4)</code>, and mixes the eight columns. Decrypt
                  runs the inverse mix, the inverse shift, the inverse S-box, and then the mask.
                  There is no reflector, no walk back through the rotors, and no second plugboard pass.
                </p>
                <p>
                  The masks come from SHAKE-256 over the key and the block number, one mask per
                  round. The experimental width is <strong>4 rounds</strong>. Verilog and a second
                  Python model, written as eight columns, agree on the bytes.{' '}
                  <code>make e256-repaired-round</code>.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">What was measured and left out</div>
              <h3>More rotors did not beat the AES S-box.</h3>
              <div className="prose">
                <p>
                  A stack of 256 mirrored rotors is an involution at every length. A keyed
                  namespace of AES-affine rotors ties the fixed AES S-box on the integral: both
                  stay balanced for 3 rounds and break at round 4. The power map <code>x^112</code>{' '}
                  is a legal 8-bit bijection and is worse than AES on the differential, linear, and
                  degree bounds. None of those is installed.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">What four rounds showed</div>
              <h3>The integral stops. A single trail is bounded. A pile of trails was only sampled.</h3>
              <div className="prose">
                <p>
                  On this schedule the integral’s balanced bytes are <strong>32, 32, 32, 0</strong>.
                  With the S-box replaced by the identity, it stays balanced for all 8 rounds, and
                  257 chosen blocks recover the whole map. The real S-box misses that recovery.
                </p>
                <p>
                  All 69 MixColumns minors are nonzero, so any single 4-round trail has at least{' '}
                  <strong>25</strong> active S-boxes. The S-box peaks are differential 4 and Walsh
                  32, which is where the single-trail figures <code>2^-150</code> and{' '}
                  <code>2^-75</code> come from. One exhibited bundle of 64 trails, carried through
                  all 4 rounds, is about <strong>2.97×</strong> its best trail, near{' '}
                  <code>2^-316</code>. The sum of every other trail was not counted.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Pinned</div>
              <h3>Eight rounds, then fourteen. Not started.</h3>
              <div className="prose">
                <p>
                  Four rounds is the first width where that integral goes quiet. The linear
                  single-trail figure there is <code>2^-75</code>. Eight rounds would stack a
                  second copy of the four-round trail. Fourteen is the width a 256-bit block of
                  this family uses in Rijndael. Both are pinned. Neither has been run. Fixture-v4
                  remains the live profile.
                </p>
              </div>
            </article>
          </div>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
