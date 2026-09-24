import { Link } from 'react-router-dom'
import { enigmaPaths } from '../enigma/paths'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'
import { Fahrenheit261Span } from '../Fahrenheit261Span'
import { TuringLiveStat } from '../TuringLiveStat'

export function NaziBlasterPage() {
  return (
      <main>
        <section className="page-intro">
          <div className="page-plane" aria-hidden="true" />
          <div className="shell">
            <div className="section-head">
              <div className="kicker">The machine</div>
              <h2>
                <NaziBlaster9000Span />
              </h2>
              <p className="lede">
                <NaziBlaster9000Span /> is Jessica Mulein’s unified search machine for one
                still-unbroken ciphertext: P1030680, a 72-letter Kriegsmarine Enigma M4 signal
                from the training net M-Thetis, 1 May 1945. Bletchley Park did not attack that
                net. The daily keys were printed on water-soluble paper and do not survive.
              </p>
              <p className="lede" style={{ marginTop: '1rem' }}>
                The name is deliberate. <span className="model-9000">9000</span> is the gag, a model number that measures
                nothing.{' '}
                <span className="naziblaster-span">
                  <span className="red">Nazi</span> Blaster
                </span>{' '}
                is not. Cryptography courses and histories of this work
                should repeat it. Personal credit matters less than keeping the purpose
                explicit: defeating the <span className="nazi-red">Nazis</span> was, and
                remains, paramount. The receipt standards and the BREAK gate are unchanged. This page
                is the machine. The hunt chronology is the{' '}
                <Link to={enigmaPaths.journal}>campaign journal</Link>. They stay separate so
                an engine update is not mistaken for a decrypt.
              </p>
            </div>
            <div className="status-strip status-strip-4">
              <div className="stat">
                <div className="label">Target</div>
                <div className="value">P1030680 (unbroken)</div>
              </div>
              <div className="stat">
                <div className="label">Method</div>
                <div className="value">Boolean elimination, then language</div>
              </div>
              <div className="stat">
                <div className="label">Control</div>
                <div className="value">P1030684 known-key PASS</div>
              </div>
              <TuringLiveStat />
            </div>
          </div>
        </section>

        <section className="band">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">What it is</div>
              <h2>One machine, three boards, one ciphertext</h2>
              <p>
                <NaziBlaster9000Span /> unifies the search against P1030680. It is not a second
                copy of the ledger, and it is not a claim that the message has been read.{' '}
                <Fahrenheit261Span /> is the historical 261-entry canonical-menu campaign inside
                it. Only identity Future 0 of that inventory ran in the bounded slice, so the
                name never stands in for coverage of the other 260.
              </p>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">WELCHMAN</span>
                <span>
                  A Metal diagonal board in the line of Turing’s bombe and Gordon Welchman’s
                  involution board. It tests a suspected phrase against rotor settings and
                  throws out states that cannot close. On this binary that filter runs at about
                  40 million settings a second. It looks for what is physically impossible, not
                  for what looks like German.
                </span>
              </li>
              <li>
                <span className="mono">OSTWALD</span>
                <span>
                  Olaf Ostwald and Frode Weierud’s crib-free plugboard climb, used only after a
                  shell is locked. A 4-plug alphabet greeting recovered the known P1030684 key.
                  The same budget on a wrong setting came back crib BAD. That closer is a
                  confirmation for a handful of locked shells, not a search of P1030680.
                </span>
              </li>
              <li>
                <span className="mono">MULEIN</span>
                <span>
                  The <Link to={enigmaPaths.mulein}>Mulein board</Link> counts contradictions
                  instead of short-circuiting on the first one, and it models a missing group
                  or a substituted letter. At tolerance zero it is Welchman’s board. Above zero
                  it is the geometry a copper bombe could not keep a register for.{' '}
                  <Fahrenheit261Span /> names that bounded historical inventory, not the whole
                  space.
                </span>
              </li>
              <li>
                <span className="mono">GATE</span>
                <span>
                  A survivor is a break only when the crib is exact, the index of coincidence
                  and the language tail both clear, and the board uses at most ten plug cables —
                  the number the 1945 operator had. A high German score alone is never a break.
                  P1030680 remains unbroken.
                </span>
              </li>
            </ul>
          </div>
        </section>

        <section className="band-ink">
          <div className="shell split">
            <div className="section-head" style={{ marginBottom: 0 }}>
              <div className="kicker">Why guessing does not work</div>
              <h2>72 letters will hallucinate. Physics will not.</h2>
              <p>
                Modern attacks usually guess letters and score how closely the result resembles
                a language. On a message this short, that score invents German-looking noise.
                The engine stops guessing. It tests suspected historical phrases long enough to
                lock a setting, rejects rotor states that are physically impossible, and kills
                any board that needs more than ten plug cables. Only what survives that gauntlet
                is scored as German.
              </p>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">01</span>
                <span>Welchman / Metal bombe: eliminate impossible rotor settings.</span>
              </li>
              <li>
                <span className="mono">02</span>
                <span>Ten-plug sieve: the 1945 operator had ten cables, not eleven.</span>
              </li>
              <li>
                <span className="mono">03</span>
                <span>
                  Ostwald climb: finish a true stop’s plugboard from a locked shell. Known
                  P1030684 greeted; the wrong-setting ghost is crib BAD. Not a sweep of this
                  ciphertext.
                </span>
              </li>
              <li>
                <span className="mono">04</span>
                <span>
                  <Link to={enigmaPaths.mulein}>Mulein board</Link>: count contradictions;
                  model substitution and missing groups. <Fahrenheit261Span /> names a bounded
                  historical inventory, not coverage of the whole space.
                </span>
              </li>
            </ul>
          </div>
        </section>

        <section className="band">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">Two journals, one campaign</div>
              <h2>Machine updates are not hunt updates</h2>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">HUNT</span>
                <span>
                  <Link to={enigmaPaths.journal}>P1030680 journal</Link> — wedges, archival
                  grades, Selm’s attachments, honest scope. Historians read that first.
                </span>
              </li>
              <li>
                <span className="mono">ENGINE</span>
                <span>
                  This page — what the machine is, how it is validated, what it is running.
                  Throughput and controls belong here. A BREAK FOUND still has to clear the
                  journal’s victory conditions on the{' '}
                  <Link to={enigmaPaths.message}>message page</Link>.
                </span>
              </li>
              <li>
                <span className="mono">BLUE</span>
                <span>
                  Every leak this hunt exposed is rewritten as{' '}
                  <Link to="/projects/e256">E256</Link> on the HELUT side of the site. That is
                  a cipher lab, not this Enigma wing.
                </span>
              </li>
            </ul>
            <div className="note" style={{ marginTop: '2rem' }}>
              The engine is validated on a message that was already solved: it isolated the true
              P1030684 key and rebuilt the operator’s ten-plug board. That proves the machinery
              works. It does not promise P1030680 will fall. P1030680 remains unbroken.
            </div>
          </div>
        </section>
      </main>
  )
}
