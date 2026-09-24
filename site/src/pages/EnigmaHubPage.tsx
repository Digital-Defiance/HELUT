import { Link } from 'react-router-dom'
import { enigmaPaths } from '../enigma/paths'
import { p1030680Status } from '../enigma/status'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'
import { horenbergHome } from '../enigma/corpus'

export function EnigmaHubPage() {
  return (
      <main>
        <section className="page-intro">
          <div className="page-plane" aria-hidden="true" />
          <div className="shell">
            <div className="section-head">
              <div className="kicker">Enigma · Kriegsmarine M4</div>
              <h2>An 80-year-old message, and the machine hunting it</h2>
              <p className="lede">
                HELUT is a homomorphic-netlist research project. This wing is something else:
                a public dossier on unbroken Kriegsmarine traffic recovered with U-534, and a
                graded Boolean search against one 72-letter M-Thetis ciphertext. Historians
                belong here. The FHE stack lives on the rest of the site.
              </p>
            </div>
            <div className="status-strip status-strip-4">
              <div className="stat">
                <div className="label">P1030680</div>
                <div className="value">
                  <em>{p1030680Status.label}</em>
                </div>
              </div>
              <div className="stat">
                <div className="label">Date</div>
                <div className="value">{p1030680Status.date}</div>
              </div>
              <div className="stat">
                <div className="label">Length</div>
                <div className="value">{p1030680Status.length} letters</div>
              </div>
              <div className="stat">
                <div className="label">Key-net</div>
                <div className="value">M-Thetis</div>
              </div>
            </div>
          </div>
        </section>

        <section className="band">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">Doors</div>
              <h2>Message, corpus, hunt, machine — kept apart on purpose</h2>
              <p>
                If this ciphertext breaks, the announcement will live on the message page. The
                journal stays the chronology of every clean negative. The machine page is how
                we search, not what we claim to have read.
              </p>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">MSG</span>
                <span>
                  <strong>
                    <Link to={enigmaPaths.message}>P1030680</Link>
                  </strong>
                  {' — '}
                  the ciphertext, indicators, working key-net, and what preservation among
                  U-534’s papers does and does not prove. Built for Enigma historians.
                </span>
              </li>
              <li>
                <span className="mono">CORPUS</span>
                <span>
                  <strong>
                    <Link to={enigmaPaths.corpus}>U-534 corpus</Link>
                  </strong>
                  {' — '}
                  fifty U-534 pages plus the wider BGNC scrape, from{' '}
                  <a href={horenbergHome} target="_blank" rel="noreferrer">
                    enigma.hoerenberg.com
                  </a>
                  . Two JSON files, not mixed. P1030680 sits in the U-534 file as unbroken.
                  Hörenberg remains the source.
                </span>
              </li>
              <li>
                <span className="mono">HUNT</span>
                <span>
                  <strong>
                    <Link to={enigmaPaths.journal}>Campaign journal</Link>
                  </strong>
                  {' — '}
                  every wedge, ghost, and archival grade. Selm Merel Wenselaers’s source files
                  are attached there with her credit.
                </span>
              </li>
              <li>
                <span className="mono">ENGINE</span>
                <span>
                  <strong>
                    <Link to={enigmaPaths.machine}>
                      <NaziBlaster9000Span />
                    </Link>
                  </strong>
                  {' — '}
                  the unified search machine (Welchman, Ostwald, Mulein). Parallel to the hunt,
                  not a second copy of the ledger. The{' '}
                  <Link to={enigmaPaths.mulein}>Mulein board</Link> is the tolerant/indel
                  mechanism inside it.
                </span>
              </li>
            </ul>
          </div>
        </section>

        <section className="band-ink">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">Team</div>
              <h2>Archival arm and mechanical arm</h2>
              <p>
                Two named people. The first-person journal is Jessica Mulein’s operational log.
                Neither arm mints a decrypt. P1030680 remains unbroken.
              </p>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">ARCHIVE</span>
                <span>
                  <strong>Selm Merel Wenselaers</strong> (Amsterdam / Antwerp) — historian and
                  curator. She recovers the scans and reconstructions, grades what those documents
                  can and cannot support, and decides which historical hypotheses are worth a
                  measurement.
                </span>
              </li>
              <li>
                <span className="mono">ENGINE</span>
                <span>
                  <strong>Jessica Mulein</strong> (US / Seattle) — mechanical arm. She designed and operates{' '}
                  <NaziBlaster9000Span />: the Welchman board, Ostwald climb, and Mulein
                  geometry, and the HELUT stack that hosts them. The{' '}
                  <Link to={enigmaPaths.journal}>campaign journal</Link> is her ledger.
                </span>
              </li>
            </ul>
            <p style={{ marginTop: '1.5rem' }}>
              <Link className="btn" to={enigmaPaths.message}>
                The message
              </Link>{' '}
              <Link className="btn ghost" to={enigmaPaths.corpus}>
                U-534 corpus
              </Link>
            </p>
          </div>
        </section>
      </main>
  )
}
