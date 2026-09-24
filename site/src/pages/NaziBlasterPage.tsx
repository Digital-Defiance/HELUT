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
                Jessica Mulein’s unified P1030680 search engine: a Metal Welchman diagonal
                board, Ostwald plugboard climb, and the Mulein tolerant/indel geometry. This
                page is the machine. The hunt chronology is the{' '}
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

        <section className="band-ink">
          <div className="shell split">
            <div className="section-head" style={{ marginBottom: 0 }}>
              <div className="kicker">Why guessing does not work</div>
              <h2>72 letters will hallucinate. Physics will not.</h2>
              <p>
                Statistical search on a message this short invents German-looking noise. The
                engine tests suspected historical phrases long enough to lock a setting, rejects
                rotor states that are physically impossible, and kills any board that needs more
                than ten plug cables. Survivors are then scored as German. A high score alone is
                never a break.
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
                  Ostwald climb: finish a true stop’s plugboard from a locked shell. A 4-plug
                  alphabet greeting recovered known P1030684; the wrong-setting ghost is the
                  next control. Not pointed at P1030680 until that ghost is crib BAD.
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
