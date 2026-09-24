import { Link } from 'react-router-dom'
import { enigmaPaths } from '../enigma/paths'
import { p1030680Status } from '../enigma/status'
import { horenbergHome } from '../enigma/corpus'
import { selmAllPublicFiles, SELM_CREDIT } from '../journal/selmSources'
import { JournalAttachments } from '../journal/JournalCite'

export function P1030680Page() {
  return (
      <main>
        <section className="page-intro">
          <div className="page-plane" aria-hidden="true" />
          <div className="shell">
            <div className="section-head">
              <div className="kicker">The message</div>
              <h2>P1030680</h2>
              <p className="lede">
                A 72-letter Kriegsmarine Enigma M4 ciphertext, dated 1 May 1945, preserved among
                the{' '}
                <a href={horenbergHome} target="_blank" rel="noreferrer">
                  Hörenberg
                </a>{' '}
                / U-534 radio and cipher papers. This page is the public dossier for the message
                itself. It is not the hunt log, and it is not a decrypt.
              </p>
            </div>
            <div className="status-strip status-strip-4">
              <div className="stat">
                <div className="label">Status</div>
                <div className="value">
                  <em>{p1030680Status.label}</em>
                </div>
              </div>
              <div className="stat">
                <div className="label">Indicators</div>
                <div className="value">{p1030680Status.indicators}</div>
              </div>
              <div className="stat">
                <div className="label">Key-net</div>
                <div className="value">M-Thetis</div>
              </div>
              <div className="stat">
                <div className="label">Ciphertext</div>
                <div className="value">{p1030680Status.length} letters ({p1030680Status.ciphertextHead})</div>
              </div>
            </div>
          </div>
        </section>

        <section className="band">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">What is on the paper</div>
              <h2>Facts that do not depend on a break</h2>
            </div>
            <ul className="stack-list">
              <li>
                <span className="mono">NET</span>
                <span>
                  Kenngruppe <code>ACH</code> maps to M-Thetis on the later Zuteilungsliste used
                  by Hörenberg. That is the working assignment. A reported earlier Forelle list
                  maps column 645 differently; the later list’s date and provenance remain open.
                </span>
              </li>
              <li>
                <span className="mono">TAFEL</span>
                <span>
                  1 May 1945 Kenngruppen table selection is Kennwort Quelle, Tafel A
                  (Tauschtafelplan Bruno, Prüfnr. 1772a). Tafel A pairs are photographed in a
                  different edition (Prüfnr. 2499). Edition compatibility is not demonstrated.
                </span>
              </li>
              <li>
                <span className="mono">BOAT</span>
                <span>
                  Recovery among U-534’s papers is provenance, not recipient. Whether the signal
                  was addressed to U-534 is open. P1030680 may not have been intended for that
                  boat.
                </span>
              </li>
              <li>
                <span className="mono">NO BREAK</span>
                <span>
                  No key, no plaintext, no implied decrypt. A claimed break on this site will
                  name the key, the plaintext, the log, and the victory conditions (crib exact,
                  IC, tail, ≤10 plugs) on this page. Until then every clean negative stays in
                  the <Link to={enigmaPaths.journal}>journal</Link>.
                </span>
              </li>
            </ul>
          </div>
        </section>

        <section className="band">
          <div className="shell">
            <div className="section-head">
              <div className="kicker">Sources</div>
              <h2>Named files, credited to {SELM_CREDIT}</h2>
              <p>
                Scans and reconstructions recovered or authored by the archival arm. Direct
                quotations live on the journal entries they belong to.
              </p>
            </div>
            <JournalAttachments
              kicker={`Attachments · ${SELM_CREDIT}`}
              files={selmAllPublicFiles}
              previewImages={false}
            />
            <p style={{ marginTop: '1.5rem' }}>
              <Link className="btn" to={enigmaPaths.journal}>
                Campaign journal
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
