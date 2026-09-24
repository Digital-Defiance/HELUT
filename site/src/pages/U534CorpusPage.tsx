import { useEffect, useMemo, useState } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import {
  bgncCleanJsonHref,
  bgncWiderJsonHref,
  formatGroups,
  formatWheels,
  horenbergHome,
  horenbergU534Index,
  jsonHrefFor,
  messageStatus,
  publishedPlaintext,
  u534CorpusJsonHref,
  u534EngineCheck,
  u534EngineReceipt,
  type CorpusCollection,
  type CorpusFile,
  type CorpusMessage,
} from '../enigma/corpus'
import { enigmaPaths } from '../enigma/paths'

type Filter = 'all' | 'broken' | 'open' | 'hunt'

function matchesQuery(message: CorpusMessage, query: string, collection: CorpusCollection): boolean {
  if (!query) return true
  const hay = [
    message.id,
    messageStatus(message, collection),
    ...(message.indicators ?? []),
    message.ciphertext ?? '',
    publishedPlaintext(message) ?? '',
    message.wheels ?? '',
    message.date ?? '',
    message.category ?? '',
    message.machine ?? '',
  ]
    .join(' ')
    .toLowerCase()
  return hay.includes(query)
}

function rowDomId(id: string): string {
  return `msg-${id.replace(/[^A-Za-z0-9_-]/g, '_')}`
}

function parseCollection(raw: string | null): CorpusCollection {
  return raw === 'wider' ? 'wider' : 'u534'
}

export function U534CorpusPage() {
  const { hash } = useLocation()
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const collection = parseCollection(params.get('set'))
  const [u534, setU534] = useState<CorpusFile | null>(null)
  const [wider, setWider] = useState<CorpusFile | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<Filter>('all')
  const [query, setQuery] = useState('')
  const [openId, setOpenId] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    Promise.all([
      fetch(u534CorpusJsonHref).then((r) => {
        if (!r.ok) throw new Error(`U-534 HTTP ${r.status}`)
        return r.json() as Promise<CorpusFile>
      }),
      fetch(bgncWiderJsonHref).then((r) => {
        if (!r.ok) throw new Error(`wider HTTP ${r.status}`)
        return r.json() as Promise<CorpusFile>
      }),
    ])
      .then(([a, b]) => {
        if (cancelled) return
        setU534(a)
        setWider(b)
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load corpus')
      })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    const id = decodeURIComponent(hash.replace(/^#/, ''))
    if (!id || !u534 || !wider) return
    setOpenId(id)
    const inU534 = u534.messages.some((m) => m.id === id)
    const inWider = wider.messages.some((m) => m.id === id)
    if (inWider && !inU534 && collection !== 'wider') {
      setParams({ set: 'wider' }, { replace: true })
    }
  }, [hash, u534, wider, collection, setParams])

  useEffect(() => {
    if (!openId) return
    document.getElementById(rowDomId(openId))?.scrollIntoView({ block: 'nearest' })
  }, [openId, collection, u534, wider])

  const corpus = collection === 'u534' ? u534 : wider
  const messages = corpus?.messages ?? []
  const brokenCount = messages.filter((m) => m.broken).length

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return messages.filter((message) => {
      if (filter === 'broken' && !message.broken) return false
      if (filter === 'open' && message.broken) return false
      if (filter === 'hunt' && message.id !== 'P1030680') return false
      return matchesQuery(message, q, collection)
    })
  }, [messages, filter, query, collection])

  function choose(next: CorpusCollection) {
    setFilter('all')
    setQuery('')
    setOpenId(null)
    navigate({ pathname: enigmaPaths.corpus, search: next === 'wider' ? '?set=wider' : '', hash: '' })
  }

  function toggle(id: string) {
    const next = openId === id ? null : id
    setOpenId(next)
    navigate(
      {
        search: collection === 'wider' ? '?set=wider' : '',
        hash: next ? encodeURIComponent(next) : '',
      },
      { replace: true },
    )
  }

  const chips: [Filter, string][] =
    collection === 'u534'
      ? [
          ['all', 'All'],
          ['broken', 'Broken'],
          ['open', 'Not broken'],
          ['hunt', 'P1030680'],
        ]
      : [
          ['all', 'All'],
          ['broken', 'Broken'],
          ['open', 'Cipher-only'],
        ]

  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Hörenberg / BGNC scrapes</div>
            <h2>Two corpora, kept separate</h2>
            <p className="lede">
              Public intercept pages from{' '}
              <a href={horenbergHome} target="_blank" rel="noreferrer">
                Michael Hörenberg’s Breaking German Navy Ciphers
              </a>
              {' '}
              (
              <a href={horenbergU534Index} target="_blank" rel="noreferrer">
                The U534 messages
              </a>
              {' '}
              and the other BGNC categories). HELUT scraped the HTML for research. The originals
              remain the source. The U-534 fixture is load-bearing for this campaign; the wider
              scrape is a second file and is not mixed into it.
            </p>
          </div>
          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">U-534 pages</div>
              <div className="value">{u534 ? u534.messages.length : '…'}</div>
            </div>
            <div className="stat">
              <div className="label">Wider BGNC</div>
              <div className="value">{wider ? wider.messages.length : '…'}</div>
            </div>
            <div className="stat">
              <div className="label">P1030680</div>
              <div className="value">
                <em>Unbroken</em>
              </div>
            </div>
            <div className="stat">
              <div className="label">Source</div>
              <div className="value">
                <a href={horenbergHome} target="_blank" rel="noreferrer">
                  Hörenberg
                </a>
              </div>
            </div>
          </div>
          <p style={{ marginTop: '1.5rem' }}>
            <a className="btn" href={jsonHrefFor(collection)} download>
              Download this JSON
            </a>{' '}
            <a className="btn ghost" href={horenbergHome} target="_blank" rel="noreferrer">
              Hörenberg originals
            </a>
          </p>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">What this is</div>
            <h2>A scrape, not an edition</h2>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">SOURCE</span>
              <span>
                <strong>
                  <a href={horenbergHome} target="_blank" rel="noreferrer">
                    Michael Hörenberg
                  </a>
                </strong>{' '}
                hosts Breaking German Navy Ciphers at{' '}
                <a href={horenbergHome} target="_blank" rel="noreferrer">
                  enigma.hoerenberg.com
                </a>
                . Recovered traffic there is the work of Hörenberg and collaborators, including
                Dan Girard and Frode Weierud. HELUT did not transcribe the scans. Each row links
                back to its Hörenberg page. Publication of these copies must credit BGNC.
              </span>
            </li>
            <li>
              <span className="mono">VERIFY</span>
              <span>
                U-534 recovered keys were independently checked on HELUT’s M4 (
                <code>Scripts/enigma_m4.py</code>, same stepping as the Swift oracle — not
                Hörenberg’s code). Receipt:{' '}
                <strong>
                  {u534EngineReceipt.clean}/{u534EngineReceipt.brokenWithKey} clean
                </strong>{' '}
                ({u534EngineReceipt.exact} letter-for-letter, {u534EngineReceipt.prefixPerfectId}{' '}
                prefix-perfect on a truncated transcript). {u534EngineReceipt.mismatch} documented
                mismatches (multi-part keys, indels, thin isolated substitution); none scramble from
                letter 0. That is a check of published keys, not a claim HELUT broke those 48.{' '}
                <Link to={enigmaPaths.message}>P1030680</Link> has no key to check. The campaign
                control P1030684 was also recovered blind (Welchman board; Ostwald 4-plug greeting).
                The wider scrape is structurally graded (12 of 13 German usable), not
                M4-engine-verified.
              </span>
            </li>
            <li>
              <span className="mono">U-534</span>
              <span>
                <code>scrape_u534.py</code> → <code>u534_corpus.json</code>: 50 pages from “The
                U534 messages” and “Unbroken.” 48 recovered keys. <Link to={enigmaPaths.message}>P1030680</Link>{' '}
                is the unbroken 72-letter M4 ciphertext this campaign hunts. P1030670 has no
                Enigma body in that scrape. This file is the campaign fixture. Do not merge the
                wider scrape into it.
              </span>
            </li>
            <li>
              <span className="mono">WIDER</span>
              <span>
                <code>scrape_bgnc_wider.py</code> → <code>bgnc_wider_corpus.json</code>: 25 pages
                from Norrköping, Spanish Enigma, M4 Project 2006, Reservehandverfahren, and
                Breaking the M4 — names the U-534 scraper’s <code>Pddddddd</code> filter dropped.
                Mostly Enigma I. 13 recovered keys in the scrape; a structurally validated German
                subset of 12 is{' '}
                <a href={bgncCleanJsonHref} download>
                  bgnc_register_clean.json
                </a>
                . Not a P1030680 decrypt.
              </span>
            </li>
            <li>
              <span className="mono">NO BREAK</span>
              <span>
                A <code>plaintext</code> field on an unbroken page is a scraper artifact, not a
                decrypt. This display does not show it. P1030680 remains historically unbroken.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Messages</div>
            <h2>Open a row. Download the rest.</h2>
          </div>

          {error ? <p className="note">Could not load the corpus ({error}).</p> : null}

          <div className="corpus-toolbar">
            <div className="corpus-chips" role="group" aria-label="Which scrape">
              <button
                type="button"
                className={collection === 'u534' ? 'active' : undefined}
                onClick={() => choose('u534')}
              >
                U-534
              </button>
              <button
                type="button"
                className={collection === 'wider' ? 'active' : undefined}
                onClick={() => choose('wider')}
              >
                Wider BGNC
              </button>
            </div>
            <div className="corpus-chips" role="group" aria-label="Filter messages">
              {chips.map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  className={filter === id ? 'active' : undefined}
                  onClick={() => setFilter(id)}
                >
                  {label}
                </button>
              ))}
            </div>
            <label className="corpus-search">
              <span className="visually-hidden">Search messages</span>
              <input
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search id, indicators, text…"
              />
            </label>
          </div>

          <div className="corpus-table-wrap">
            <table className="corpus-table">
              <thead>
                <tr>
                  <th>Id</th>
                  <th>Indicators</th>
                  <th>Length</th>
                  <th>Wheels</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((message) => {
                  const open = openId === message.id
                  const huntRow = collection === 'u534' && message.id === 'P1030680'
                  return (
                    <tr
                      key={`${collection}-${message.id}`}
                      id={rowDomId(message.id)}
                      className={`${open ? 'is-open' : ''} ${huntRow ? 'is-hunt' : ''}`}
                    >
                      <td colSpan={5}>
                        <button type="button" className="corpus-row" onClick={() => toggle(message.id)}>
                          <span className="mono">{message.id}</span>
                          <span className="mono">
                            {message.indicators?.join(' ') ?? '—'}
                          </span>
                          <span>{message.length ?? '—'}</span>
                          <span>
                            {collection === 'wider'
                              ? (message.category ?? formatWheels(message.wheels))
                              : formatWheels(message.wheels)}
                          </span>
                          <span>{messageStatus(message, collection)}</span>
                        </button>
                        {open ? (
                          <MessageDetail message={message} isHunt={huntRow} collection={collection} />
                        ) : null}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          {corpus ? (
            <p className="corpus-count">
              Showing {visible.length} of {messages.length} pages
              {collection === 'u534' ? ` · ${brokenCount} broken` : ` · ${brokenCount} recovered keys`}.
            </p>
          ) : (
            <p className="corpus-count">Loading…</p>
          )}
        </div>
      </section>
    </main>
  )
}

function MessageDetail({
  message,
  isHunt,
  collection,
}: {
  message: CorpusMessage
  isHunt: boolean
  collection: CorpusCollection
}) {
  const plaintext = publishedPlaintext(message)
  return (
    <div className="corpus-detail">
      {isHunt ? (
        <p>
          Campaign target.{' '}
          <Link to={enigmaPaths.message}>Message dossier</Link>
          {' · '}
          <Link to={enigmaPaths.journal}>Journal</Link>
          . Not a decrypt.
        </p>
      ) : null}
      {message.category ? (
        <p>
          <span className="mono">CAT</span> {message.category}
          {message.machine ? ` · ${message.machine}` : ''}
        </p>
      ) : null}
      {message.date ? (
        <p>
          <span className="mono">DATE</span> {message.date}
        </p>
      ) : null}
      {message.broken ? (
        <p>
          <span className="mono">KEY</span> UKW {message.reflector ?? '—'} · Greek{' '}
          {message.greek ?? '—'} · {formatWheels(message.wheels)} · pos{' '}
          {message.wheel_positions ?? '—'} · rings {message.rings ?? '—'} · plugs{' '}
          {message.plugs ?? '—'}
        </p>
      ) : null}
      {collection === 'u534' && u534EngineCheck(message) === 'clean' ? (
        <p>
          <span className="mono">ENGINE</span> HELUT’s M4 decrypts this published key to the
          published plaintext
          {message.id === u534EngineReceipt.prefixPerfectId
            ? ' through the truncated transcript prefix'
            : ''}
          . That is a check of Hörenberg’s key, not a second break.
          {message.id === 'P1030684'
            ? ' The campaign also recovered this key blind on the Welchman board and the Ostwald 4-plug greeting.'
            : ''}
        </p>
      ) : null}
      {collection === 'u534' && u534EngineCheck(message) === 'mismatch' ? (
        <p>
          <span className="mono">ENGINE</span> The published key does not reproduce the whole
          published plaintext end-to-end (Phase 50.9: multi-part keys, indels, or thin isolated
          substitution). Leading letters still agree; the simulator is not scrambling from the
          first letter.
        </p>
      ) : null}
      {collection === 'wider' && message.broken ? (
        <p>
          <span className="mono">ENGINE</span> Wider recovered keys are not round-tripped on the
          HELUT M4 engine (most of this scrape is Enigma I). Structural checks only: length, no
          self-encipherment, legal plugs, German vs Spanish.
        </p>
      ) : null}
      {message.ciphertext ? (
        <div>
          <div className="mono">CIPHERTEXT</div>
          <p className="corpus-letters">{formatGroups(message.ciphertext)}</p>
        </div>
      ) : (
        <p>
          No ciphertext in this scrape.{' '}
          {message.url ? (
            <a href={message.url} target="_blank" rel="noreferrer">
              Hörenberg page
            </a>
          ) : (
            'See the Hörenberg page.'
          )}
        </p>
      )}
      {plaintext ? (
        <div>
          <div className="mono">PLAINTEXT (as published on Hörenberg)</div>
          <p className="corpus-letters">{formatGroups(plaintext)}</p>
        </div>
      ) : null}
      {message.url ? (
        <p>
          <a href={message.url} target="_blank" rel="noreferrer">
            Hörenberg page
          </a>
        </p>
      ) : null}
      {collection === 'wider' ? (
        <p>
          Wider BGNC scrape. Not mixed into the U-534 campaign fixture.
        </p>
      ) : null}
    </div>
  )
}
