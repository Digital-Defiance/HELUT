import type { JournalAttachment } from './JournalCite'

/** Named credit for every public file she recovered or authored. */
export const SELM_CREDIT = 'Selm Merel Wenselaers'

export const SELM_QUOTES = {
  thetisRefusal:
    'The pages below are useful for reconstructing U-3521\'s training and final-days context. They do not establish that U-3521 used M-Thetis, and no raw Thetis Funkspruch or Thetis key has been identified in this dossier.',
  neustadtSeparation:
    'The KTB material supports the 2 May sequence "crew leaves except Sprengkommando" and movement by T-boat to Neustadt. It does not itself state that this crew movement was to the 3. U-Lehrdivision. That association belongs to the separate Volksliste III / DEFE evidence and should remain a cross-source inference.',
  dossierHierarchy:
    'This dossier does not silently correct forum transcriptions or treat them as equivalent to the photographed primary documents.',
  notForU534:
    'P1030680 may not have been intended for U-534. It survives among U-534\'s radio/cipher papers, but the original recipient remains unknown.',
  unreadMessage: 'Even an unread message can tell a remarkable story.',
} as const

export const selmU534LastDays: JournalAttachment = {
  href: '/selm/u534-last-days-20260923.png',
  title: 'The last days of U-534, 1–5 May 1945',
  kind: 'image',
  credit: SELM_CREDIT,
  creditLine: 'Historical reconstruction by S. M. Wenselaers | 23 September 2026',
  caption:
    'P1030680 may not have been intended for U-534. It survives among U-534\'s radio/cipher papers, but the original recipient remains unknown.',
  bytesLabel: '2.2 MB',
}

export const selmU3521Dossier: JournalAttachment = {
  href: '/selm/u3521-source-dossier-revised.pdf',
  title: 'U-3521 source dossier (revised)',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '16 MB',
  origin:
    'Compiled 24 September 2026 from Axis History Forum topic 220141. Photographs of surviving KTB pages are primary; forum transcriptions are not treated as equivalent.',
}

export const selmNidInterrogation: JournalAttachment = {
  href: '/selm/nid-1-pw-rep-17-interrogation.pdf',
  title: 'NID 1/PW/REP/17 — U 413, U 1209, U 877, U 1199 interrogation',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '425 KB',
  origin:
    'Admiralty report, April 1945. Copy recovered by Wenselaers via Tony Cooper / U-boat Archive. POW statements are unconfirmed unless independently corroborated. The report never names Thetis.',
}

export const selmQuelle2499: JournalAttachment = {
  href: '/selm/quelle-doppeltafeln-pruefnr-2499.pdf',
  title: 'Doppelbuchstabentauschtafeln für Kenngruppen, Kennwort Quelle, Prüfnr. 2499',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '2.8 MB',
  origin:
    'Crypto Museum scan of the Quelle booklet (Zu M.Dv.Nr.98), recovered by Wenselaers. Tafel A pairs are photographed; the May Tauschtafelplan in hand remains Prüfnr. 1772a.',
}

export const selmAllPublicFiles: JournalAttachment[] = [
  selmU534LastDays,
  selmU3521Dossier,
  selmNidInterrogation,
  selmQuelle2499,
]
