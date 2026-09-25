import { Link } from 'react-router-dom'
import { E256Span } from '../E256Span'
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
              The hunt for P1030680 is a ledger of how the 1945 machine leaks. Enigma 256
              is the rewrite of those leaks. The research standard is a 256-bit
              round: sixteen words of 16 bits, a field inverse, a public constant, and a
              multiplier chosen by the key and the block. Decrypt is the inverse path. There is
              no reflector.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              This is not nostalgia hardware. It is the Blue Team answer to a Red Team that already runs Welchman, Stochastic KPA, and TensorLUT on Apple Silicon—built from the same findings documented in the{' '}
              <Link to="/enigma/journal">campaign journal</Link>.
            </p>
          </div>

          <div className="note" style={{ marginBottom: '1.5rem' }}>
            <strong>Research round — not for real data.</strong> Twenty-five rounds, multiplier-only
            keying, public constant 1. The measurements below are not an IND-CPA claim, a security
            level, or a work factor. Outside review has not been done.
          </div>

          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">Words</div>
              <div className="value">16 × 16 bits</div>
            </div>
            <div className="stat">
              <div className="label">Width</div>
              <div className="value">25 rounds</div>
            </div>
            <div className="stat">
              <div className="label">Integral</div>
              <div className="value">dies at round 4</div>
            </div>
            <div className="stat">
              <div className="label">Peel</div>
              <div className="value">misses from round 2</div>
            </div>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Research standard · 24 September 2026</div>
            <h2>From the M4 defects to a 16-bit round</h2>
            <p>
              M4 was broken by its shape: a reflector, a path that is its own inverse, and a
              letter that never encrypts to itself. The loaded byte-walk kept a conjugated XOR
              in the center, and that map is an involution for every nonzero mask. An 8-bit
              rotor lands on the AES S-box and cannot beat it. The research round uses the
              inverse in GF(2^16), keys each word by a field multiplier, and adds the public
              constant 1 so the inverse does not undo itself. Decrypt walks backwards. This round
              is the loaded profile. This is not a security claim.
            </p>
          </div>
          <figure className="arch-figure" aria-label="Path from M4 Enigma to the 16-bit research round">
            <svg viewBox="0 0 920 200" role="img" className="arch-svg">
              <title>M4 defects, the byte-walk, the 8-bit rotor, and the 16-bit round</title>
              <defs>
                <marker id="stdArrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                  <path d="M0,0 L6,3 L0,6 Z" fill="#9ee0da" />
                </marker>
              </defs>
              <rect x="16" y="28" width="200" height="140" rx="4" fill="#2a374e" />
              <text x="28" y="58" fill="#f4efe6" fontSize="14">M4</text>
              <text x="28" y="84" fill="#d5ddd8" fontSize="12">reflector</text>
              <text x="28" y="106" fill="#d5ddd8" fontSize="12">path is an involution</text>
              <text x="28" y="128" fill="#d5ddd8" fontSize="12">a letter never maps</text>
              <text x="28" y="148" fill="#d5ddd8" fontSize="12">to itself</text>
              <path d="M216 98 H248" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#stdArrow)" />
              <rect x="252" y="28" width="200" height="140" rx="4" fill="#0f3034" />
              <text x="264" y="58" fill="#f4efe6" fontSize="14">Byte-walk</text>
              <text x="264" y="84" fill="#d5ddd8" fontSize="12">center XOR</text>
              <text x="264" y="106" fill="#d5ddd8" fontSize="12">is an involution</text>
              <text x="264" y="128" fill="#d5ddd8" fontSize="12">for every nonzero mask</text>
              <text x="264" y="150" fill="#d5ddd8" fontSize="12">more rotors do not fix it</text>
              <path d="M452 98 H484" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#stdArrow)" />
              <rect x="488" y="28" width="180" height="140" rx="4" fill="#1f6f6a" />
              <text x="500" y="58" fill="#f4efe6" fontSize="14">8-bit rotor</text>
              <text x="500" y="84" fill="#d5ddd8" fontSize="12">ties the AES S-box</text>
              <text x="500" y="106" fill="#d5ddd8" fontSize="12">differential 4</text>
              <text x="500" y="128" fill="#d5ddd8" fontSize="12">degree 7</text>
              <text x="500" y="150" fill="#d5ddd8" fontSize="12">cannot beat that box</text>
              <path d="M668 98 H700" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#stdArrow)" />
              <rect x="704" y="28" width="200" height="140" rx="4" fill="#a86227" />
              <text x="716" y="58" fill="#f4efe6" fontSize="14">16-bit round</text>
              <text x="716" y="84" fill="#fff4e8" fontSize="12">inverse in GF(2^16)</text>
              <text x="716" y="106" fill="#fff4e8" fontSize="12">multiplier, constant 1</text>
              <text x="716" y="128" fill="#fff4e8" fontSize="12">25 rounds</text>
              <text x="716" y="150" fill="#fff4e8" fontSize="12">inverse decrypt</text>
            </svg>
            <figcaption>
              Each box is a measured defect, then the change that removes it. The orange box is
              the research standard.
            </figcaption>
          </figure>
          <figure className="arch-figure" aria-label="One round of the 16-bit research standard">
            <svg viewBox="0 0 920 180" role="img" className="arch-svg">
              <title>Sixteen-bit round: scale, inverse, constant, shift, mix</title>
              <defs>
                <marker id="rndArrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                  <path d="M0,0 L6,3 L0,6 Z" fill="#9ee0da" />
                </marker>
              </defs>
              <rect x="16" y="36" width="130" height="72" rx="4" fill="#2a374e" />
              <text x="28" y="68" fill="#f4efe6" fontSize="14">16-bit word</text>
              <text x="28" y="90" fill="#d5ddd8" fontSize="12">× multiplier</text>
              <path d="M146 72 H170" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#rndArrow)" />
              <rect x="174" y="36" width="120" height="72" rx="4" fill="#0f3034" />
              <text x="190" y="68" fill="#f4efe6" fontSize="14">Inverse</text>
              <text x="190" y="90" fill="#d5ddd8" fontSize="12">GF(2^16)</text>
              <path d="M294 72 H318" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#rndArrow)" />
              <rect x="322" y="36" width="110" height="72" rx="4" fill="#1f6f6a" />
              <text x="338" y="68" fill="#f4efe6" fontSize="14">XOR 1</text>
              <text x="338" y="90" fill="#d5ddd8" fontSize="12">public</text>
              <path d="M432 72 H456" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#rndArrow)" />
              <rect x="460" y="36" width="150" height="72" rx="4" fill="#2a374e" />
              <text x="476" y="68" fill="#f4efe6" fontSize="14">Shift rows</text>
              <text x="476" y="90" fill="#d5ddd8" fontSize="12">0, 1, 2, 3</text>
              <path d="M610 72 H634" stroke="#9ee0da" strokeWidth="1.5" markerEnd="url(#rndArrow)" />
              <rect x="638" y="36" width="160" height="72" rx="4" fill="#a86227" />
              <text x="654" y="68" fill="#f4efe6" fontSize="14">Mix columns</text>
              <text x="654" y="90" fill="#fff4e8" fontSize="12">branch number 5</text>
              <text x="16" y="150" fill="#2a374e" fontSize="13">
                Twenty-five rounds. The key and the block index reselect every multiplier. Decrypt inverts the mix, the shift, the constant, and the multiplier.
              </text>
            </svg>
            <figcaption>
              Polynomial <code>0x1100B</code>. Schedule domain <code>E256-v6/schedule/v2</code>.
              A zero multiplier is replaced by 1. Reproduce with <code>make e256-v6</code>.
            </figcaption>
          </figure>
          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">Integral</div>
              <div className="value">dies at round 4</div>
            </div>
            <div className="stat">
              <div className="label">Peel</div>
              <div className="value">hits at 1, misses at 2</div>
            </div>
            <div className="stat">
              <div className="label">One-word degree</div>
              <div className="value">15, the ceiling</div>
            </div>
            <div className="stat">
              <div className="label">20 input bits</div>
              <div className="value">degree 19 at 3 rounds</div>
            </div>
          </div>
          <p style={{ marginTop: '1rem' }}>
            One word difference, all 65536 values: after one round the heaviest output difference
            occurs 4 times. After 2, 3, and 25 rounds it occurs twice, which is the floor of that
            test, because a value and that value with the difference always share an output
            difference. A one-round formula recovers the multiplier. The same formula misses at 2,
            3, 4, and 25 rounds. All 16 integral words die at round 4 and stay dead. The sum of
            every trail, and the degree of one output bit over all 256 inputs, were not computed.
          </p>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The round</div>
            <h2>What one block does</h2>
            <p>
              A block is 32 bytes, read as 16 words. The key is 32 bytes. The block index is part
              of the schedule, so block 0 and block 1 are different permutations. SHAKE-256, domain
              <code>E256-v6/schedule/v2</code>, draws a nonzero multiplier for every word of every
              round. A drawn zero is replaced by 1.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">01</span>
              <span>
                Multiply the word by its multiplier in GF(2<sup>16</sup>), polynomial <code>0x1100B</code>.
              </span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>Invert the product. Zero stays zero.</span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>XOR the public constant 1. It is the same for every key. It is not a mask.</span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>Shift the four rows by 0, 1, 2, and 3.</span>
            </li>
            <li>
              <span className="mono">05</span>
              <span>
                Mix each column with the AES matrix over that field. All 69 minors are nonzero, so
                the branch number is 5.
              </span>
            </li>
          </ul>
          <p>
            That is one round. The experimental width is 25 rounds. Decrypt inverts the mix, the
            shift, the constant, and the multiplier. There is no reflector, no reverse rotor walk,
            and no second plugboard. Messages are padded with <code>0x80</code> and then zeros out
            to 32 bytes. <code>make e256-v6</code>.
          </p>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Why each piece is there</div>
            <h2>The defect, then the change</h2>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">M4</span>
              <span>
                A reflector makes the path an involution, and a letter never encrypts to itself.
                The research round has no reflector. Encrypting the ciphertext does not return the
                plaintext.
              </span>
            </li>
            <li>
              <span className="mono">XOR</span>
              <span>
                A conjugated XOR is an involution for every nonzero mask, and later rounds cancel
                out of that quotient. Keyed XOR masks were removed. Changing a multiplier drops the
                quotient to 0 of 8 blocks. Grafting an XOR back on brings the involution back, on 8
                of 8.
              </span>
            </li>
            <li>
              <span className="mono">8-bit</span>
              <span>
                A keyed 8-bit rotor matches the AES S-box: differential 4, Walsh 32, degree 7.
                Degree 7 is the ceiling for one output bit of an 8-bit permutation. The substitution
                moved to the inverse in GF(2<sup>16</sup>): differential 4/65536, degree 15,
                coordinate bias 2<sup>−7</sup>.
              </span>
            </li>
            <li>
              <span className="mono">+1</span>
              <span>
                The pure inverse undoes itself, and a one-word integral stayed balanced for all 25
                rounds. The public constant 1 breaks that cancellation. All 16 words then die at
                round 4 and stay dead through round 25.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">What was measured</div>
            <h2>Reduced-round results</h2>
            <p>
              These are the attacks that fit in one process. They are not a claim that the 25-round
              width has survived outside review.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">PEEL</span>
              <span>
                One known pair recovers the first-round multiplier when a single word is nonzero.
                The same formula misses at 2, 3, 4, and 25 rounds. A key with one flipped bit does
                not decrypt.
              </span>
            </li>
            <li>
              <span className="mono">INTEGRAL</span>
              <span>
                Each of the 16 words, run through all 65536 values, is balanced for three rounds
                and on no words from round 4 through round 25.
              </span>
            </li>
            <li>
              <span className="mono">TRAIL</span>
              <span>
                Four rounds activate at least 25 inverses. One inverse is at most 2<sup>−14</sup>{' '}
                differential and correlation 2<sup>−7</sup>, so four rounds are at most 2<sup>−350</sup>{' '}
                on a single differential trail. The first 24 rounds are six of those windows: 150
                inverses, differential 2<sup>−2100</sup>. That is one trail, not the sum of every trail.
              </span>
            </li>
            <li>
              <span className="mono">DEGREE</span>
              <span>
                One input word stays at degree 15, the ceiling for a 16-bit permutation. At three
                rounds, 16, 17, 18, and 20 input bits give degrees 15, 16, 17, and 19. The degree
                over all 256 input bits was not computed.
              </span>
            </li>
            <li>
              <span className="mono">DIFF</span>
              <span>
                One word difference, all 65536 values: after one round the heaviest output
                difference occurs 4 times. After 2, 3, and 25 rounds it occurs twice. Two is the
                floor of this test, because a value and that value with the difference always share
                an output difference.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Loaded profile</div>
            <h2>E256/v6/gen0 is the golden</h2>
            <p>
              Compatibility key{' '}
              <code>E256/v6/gen0/c2abdbe580bad275838fc2650f81fdb14cb5ae3865cb74c5087f488ca51a35b9/fixture-v6</code>.
              The golden KAT is <code>Fixtures/enigma256_golden</code>: one 32-byte ciphertext of
              the sentence “E256-v6 loaded profile KAT” under the key <code>00 01 … 1f</code>, 25
              rounds. <code>enigma_256_core.v</code> is this round. The byte-walk receipt, including
              its 49/49 suite and formal 1/1, is historical under{' '}
              <code>E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4</code>.
              E256-003 remains open. This profile is not for real data.
            </p>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">What this page is</div>
            <h2>A design for comment</h2>
            <p>
              The round is frozen here as the research standard: 25 rounds, multiplier-only keying,
              public constant 1. The margin over the integral is 21 rounds. The single-trail bound
              clears a 256-bit key at 4 rounds. Outside review has not been done.
            </p>
          </div>
          <div className="prose">
            <p>
              Campaign ledger:{' '}
              <Link to="/enigma/nazi-blaster-9000"><NaziBlaster9000Span /></Link>
              {' · '}
              Field journal:{' '}
              <Link to="/projects/e256/journal">E256 journal</Link>
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
