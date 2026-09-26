import type { ReactNode } from 'react'

/** Attributed wording from a named source. Prefer her sentences over HELUT paraphrase. */
export function JournalQuote({
  speaker,
  source,
  children,
}: {
  speaker: string
  source?: string
  children: ReactNode
}) {
  return (
    <blockquote className="journal-quote">
      {typeof children === 'string' ? <p>{children}</p> : children}
      <footer>
        <span className="journal-quote-speaker">{speaker}</span>
        {source ? <cite className="journal-quote-source">{source}</cite> : null}
      </footer>
    </blockquote>
  )
}

export type JournalAttachment = {
  href: string
  title: string
  kind: 'pdf' | 'image' | 'archive' | 'csv'
  credit: string
  creditLine?: string
  caption?: string
  bytesLabel?: string
  origin?: string
}

/** Attributed paraphrase when the exact email is not on file. Labelled so it is not a fake quote. */
export function JournalParaphrase({
  speaker,
  source,
  children,
}: {
  speaker: string
  source?: string
  children: ReactNode
}) {
  return (
    <div className="journal-paraphrase">
      <div className="journal-paraphrase-kicker">
        Paraphrase · {speaker}
        {source ? ` · ${source}` : ''}
      </div>
      {typeof children === 'string' ? <p>{children}</p> : children}
    </div>
  )
}

/** Downloadable / inline files credited to a named contributor. */
export function JournalAttachments({
  files,
  kicker = 'Sources',
  previewImages = true,
}: {
  files: JournalAttachment[]
  kicker?: string
  previewImages?: boolean
}) {
  const images = previewImages ? files.filter((file) => file.kind === 'image') : []
  return (
    <div className="journal-attachments">
      <div className="journal-attachments-kicker">{kicker}</div>
      <ul>
        {files.map((file) => (
          <li key={file.href}>
            <a href={file.href} target="_blank" rel="noreferrer">
              {file.title}
            </a>
            <span className="journal-attachments-meta">
              {file.kind === 'pdf' ? 'PDF' : file.kind === 'image' ? 'Image' : file.kind === 'csv' ? 'CSV' : 'Archive'}
              {file.bytesLabel ? ` · ${file.bytesLabel}` : ''}
              {` · ${file.credit}`}
            </span>
            {file.origin ? (
              <span className="journal-attachments-origin">{file.origin}</span>
            ) : null}
          </li>
        ))}
      </ul>
      {images.map((file) => (
        <figure key={`${file.href}-fig`} className="journal-attachments-figure">
          <a href={file.href} target="_blank" rel="noreferrer">
            <img src={file.href} alt={file.title} />
          </a>
          <figcaption>
            {file.caption ?? file.title}
            {file.creditLine ? (
              <>
                <br />
                {file.creditLine}
              </>
            ) : null}
          </figcaption>
        </figure>
      ))}
    </div>
  )
}
