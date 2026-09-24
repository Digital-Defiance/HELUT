export const u534CorpusJsonHref = '/horenberg/u534_corpus.json'
export const bgncWiderJsonHref = '/horenberg/bgnc_wider_corpus.json'
export const bgncCleanJsonHref = '/horenberg/bgnc_register_clean.json'
export const horenbergHome = 'https://www.enigma.hoerenberg.com'
export const horenbergU534Index =
  'https://www.enigma.hoerenberg.com/index.php?cat=The%20U534%20messages'

export type CorpusCollection = 'u534' | 'wider'

export type CorpusMessage = {
  id: string
  broken: boolean
  url?: string
  indicators?: string[]
  reflector?: string
  greek?: string
  wheels?: string
  wheel_positions?: string
  rings?: string
  plugs?: string
  date?: string
  ciphertext?: string
  plaintext?: string
  length?: number
  category?: string
  machine?: string
}

export type CorpusFile = {
  source: string
  note?: string
  credit?: string
  categories?: string[]
  messages: CorpusMessage[]
}

const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII']

export function formatWheels(wheels?: string): string {
  if (!wheels) return '—'
  if (/^[1-8]{3}$/.test(wheels)) {
    return `${wheels.split('').map((d) => ROMAN[Number(d)]).join('-')} (${wheels})`
  }
  return wheels
}

export function formatGroups(letters: string): string {
  return (letters.match(/.{1,4}/g) ?? []).join(' ')
}

export function jsonHrefFor(collection: CorpusCollection): string {
  return collection === 'u534' ? u534CorpusJsonHref : bgncWiderJsonHref
}

/**
 * Receipt of `python3 Scripts/enigma_m4.py Fixtures/u534_corpus.json`.
 * The Python M4 is a re-implementation of the Swift oracle, not Hörenberg's code.
 * This checks published keys against published plaintext. It is not an independent break.
 */
export const u534EngineReceipt = {
  command: 'python3 Scripts/enigma_m4.py Fixtures/u534_corpus.json',
  brokenWithKey: 48,
  exact: 31,
  prefixPerfectId: 'P1030694',
  clean: 32,
  mismatch: 16,
  mismatchIds: [
    'P1030659',
    'P1030664',
    'P1030675',
    'P1030693',
    'P1030695',
    'P1030699',
    'P1030700',
    'P1030701',
    'P1030702',
    'P1030705',
    'P1030706',
    'P1030707',
    'P1030708',
    'P1030709',
    'P1030710',
    'P1030711',
  ] as const,
}

export type EngineCheck = 'clean' | 'mismatch' | 'none'

export function u534EngineCheck(message: CorpusMessage): EngineCheck {
  if (!message.broken || message.id === 'P1030680') return 'none'
  return (u534EngineReceipt.mismatchIds as readonly string[]).includes(message.id)
    ? 'mismatch'
    : 'clean'
}

export function messageStatus(message: CorpusMessage, collection: CorpusCollection): string {
  if (collection === 'u534' && message.id === 'P1030680') return 'Unbroken'
  if (!message.ciphertext && !message.broken) return 'No Enigma body'
  if (collection === 'u534' && message.broken) {
    return u534EngineCheck(message) === 'clean' ? 'Broken · engine OK' : 'Broken · mismatch'
  }
  if (message.broken) return 'Broken'
  return collection === 'wider' ? 'Cipher-only' : 'Unbroken'
}

/** Published plaintext exists only on recovered pages. Unbroken `plaintext` is a scrape artifact. */
export function publishedPlaintext(message: CorpusMessage): string | undefined {
  if (!message.broken) return undefined
  return message.plaintext
}
