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
            <h2>The 16-bit round is the research standard</h2>
            <p>
              Sixteen words, a field inverse, the public constant 1, and a multiplier chosen by
              the key and the block. That round is the loaded profile,
              E256/v6/gen0/c2abdbe580bad275838fc2650f81fdb14cb5ae3865cb74c5087f488ca51a35b9/fixture-v6.
              The byte-walk receipt is historical.
              This is not a security claim, and it is not the staged v3 fixture-v5 lane.
            </p>
          </div>
          <div className="timeline">
            <article className="tl-item">
              <div className="when">Current</div>
              <h3>The 16-bit round is the research standard.</h3>
              <div className="prose">
                <p>
                  Sixteen words of 16 bits. Each word is multiplied by a field element, inverted in
                  GF(2^16), and XORed with the public constant 1, then shifted and mixed. Decrypt
                  is the inverse path. The integral dies at round 4 on all 16 words. A one-round
                  peel recovers the multiplier and misses from round 2 on. Twenty-five rounds is
                  the width. <code>make e256-v6</code>. The 8-bit rotor tied the AES S-box.
                  <code>enigma_256_core.v</code> is this round. The byte-walk core is historical.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Research</div>
              <h3>E256-v6 puts the inverse in a 16-bit word.</h3>
              <div className="prose">
                <p>
                  The research standard is the 16-bit round. v5 is the 8-bit step that tied the
                  AES S-box. Thirty-two bytes are sixteen words. Each word is scaled, inverted in
                  GF(2^16), and XORed with the public constant 1. There is no keyed mask. Decrypt
                  is the inverse path. The experimental width is 25 rounds. All 16 words of the
                  integral die at round 4 and stay dead. One round peels the multiplier. The same
                  formula misses at 2 rounds and at 25. One input word stays degree 15. With 20
                  input bits the degree is 19. A one-word difference at 25 rounds is at the floor
                  of that test: each pair has its own output difference. An XOR grafted back on is
                  an involution on 8 of 8 blocks. Changing the multiplier drops that to
                  0 of 8. One key bit and a new block each reselect all 400 multipliers. Verilog
                  matches Python on 2 blocks of 25 rounds.{' '}
                  <code>make e256-v6</code>. Not a security claim, and not fixture-v4.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">What changed</div>
              <h3>One wide round, encrypt and decrypt on different paths.</h3>
              <div className="prose">
                <p>
                  The loaded byte-walk walks a byte through forward rotors, a center XOR, and the
                  reverse rotors. This research module left that file alone. Its state is 32
                  bytes. Each round XORs a 32-byte mask, runs the AES S-box on all 32 lanes,
                  shifts rows by <code>(0,1,3,4)</code>, and mixes the eight columns. Decrypt
                  runs the inverse mix, the inverse shift, the inverse S-box, and then the mask.
                  There is no reflector, no walk back through the rotors, and no second plugboard pass.
                </p>
                <p>
                  The masks come from SHAKE-256 over the key and the block number, one mask per
                  round. The experimental width is <strong>14 rounds</strong>. Verilog and a second
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
              <div className="when">E256-v5</div>
              <h3>The patched multi-byte rotor machine has its own research core.</h3>
              <div className="prose">
                <p>
                  E256-v5 is a 32-byte state. Each round is a keyed rotor on every byte, a row
                  shift of <code>(0,1,3,4)</code>, MixColumns, and a mask. Decrypt is the inverse
                  path. A new block reselects the rotors. Four, eight, and fourteen rounds all
                  round-trip. A mask change alone is still an involution at each of those widths,
                  and replacing one rotor is not. The lane-0 integral dies at round 4. Verilog
                  matches Python on 2 blocks of 14 rounds. This is not fixture-v4, and it is not
                  the staged v3 fixture-v5 lane. <code>make e256-v5</code>.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Fourteen rounds</div>
              <h3>The machine now runs fourteen. That is the Rijndael width for this block.</h3>
              <div className="prose">
                <p>
                  Fourteen-round encrypt and decrypt agree in both Python models and in Verilog,
                  16 blocks. The integral dies at round 4 on all 32 input lanes. After that the
                  busiest round has 2 balanced bytes, never all 32. The identity S-box stays
                  fully balanced for all 14 rounds.
                </p>
                <p>
                  The same four-round certificate applies three times, and the two-round tail
                  adds five active S-boxes: at least <strong>80</strong> on a single trail, at most{' '}
                  <code>2^-480</code> differential and <code>2^-240</code> linear. An output bit’s
                  algebraic degree is 7 after one round and 14 after three rounds inside a 16-bit
                  window. The upper bound reaches 255 at round 3 and stays there. One known pair
                  recovers a one-round mask and does not recover the first mask of a 14-round
                  ciphertext. One exhibited bundle carried through all fourteen is still about
                  2.97× its best trail, through 372 S-boxes, near <code>2^-2230</code>. That is
                  one path, not the sum of every trail.
                </p>
                <p>
                  Each round mask is now its own SHAKE-256 call, and a final whitening mask sits
                  after the last MixColumns. The fifteen masks on the planted key are pairwise
                  distinct. Stripping the last linear layer no longer shows the last S-box output.
                  A one-byte guess recovers a two-round mask and recovers nothing from fourteen
                  rounds. The sum of every trail, a full-state meet-in-the-middle, and the exact
                  degree of one 256-bit output bit do not fit in this process. This fourteen-round
                  machine is the 8-bit step. The loaded profile is the 16-bit round. The byte-walk
                  receipt is historical.
                </p>
              </div>
            </article>
          </div>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
