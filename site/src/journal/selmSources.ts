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

export const selmSchluesselMBauer: JournalAttachment = {
  href: '/selm/article-antiUbootRDF-AOB-97.pdf',
  title: 'Bauer, Ultra versus Enigma — Schlüssel M appendices (Hellschreiber scan)',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '72 MB',
  origin:
    'Scan recovered by Wenselaers, 24 September 2026. She reports that it reproduces M.Dv.Nr. 32/1 as Appendix E (pp. 299–313), a May 1945 Hydra key sheet as Appendix F (p. 314), and Tafel D, Kennwort Quelle, as Appendix G (p. 315). Not applied to VROL/NMKA.',
}

export const selmArgusV3Watchlist: JournalAttachment = {
  href: '/selm/ARGUS_V3_WATCHLIST_2026-09-26.zip',
  title: 'ARGUS v3 watchlist',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '211 KB',
  origin:
    '26 September 2026. Evidence ledger and watchlist. A watch item is not a crib and is not a decrypt.',
}

export const selmArgusV31: JournalAttachment = {
  href: '/selm/ARGUS_V3_1_PROVENANCE_2026-09-26.zip',
  title: 'ARGUS v3.1 provenance',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '216 KB',
  origin:
    'The crib export had been only the Hörenberg scrape. Batch B is a 1943 U-466 diary transcription and a Nixe sheet. Neither is queued.',
}

export const selmArgusV32: JournalAttachment = {
  href: '/selm/ARGUS_V3_2_JESS_TURING_2026-09-26.zip',
  title: 'ARGUS v3.2 Jess/Turing',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '228 KB',
  origin:
    'Coprocessor build. U-534 is not assumed, Teilfunkspruch stays allowed, Travemünde/ZTPG stays quarantined. Superseded by v4, which emits no crib.',
}

export const selmArgusV4: JournalAttachment = {
  href: '/selm/ARGUS_V4_JESS_TURING_2026-09-26.zip',
  title: 'ARGUS v4 Jess/Turing',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '235 KB',
  origin:
    '26 September 2026. Asking it for cribs returns none. All 121 stored candidates are marked ineligible.',
}

export const selmCribBatchA: JournalAttachment = {
  href: '/selm/P1030680_JESSICA_CRIB_BATCH_A.csv',
  title: 'Crib batch A (Hörenberg)',
  kind: 'csv',
  credit: SELM_CREDIT,
  bytesLabel: '7 KB',
  origin:
    'Solved Potsdam plaintext from the Hörenberg scrape. Not a Thetis crib. Not queued.',
}

export const selmAllPublicFiles: JournalAttachment[] = [
  selmU534LastDays,
  selmU3521Dossier,
  selmNidInterrogation,
  selmQuelle2499,
  selmSchluesselMBauer,
  selmArgusV3Watchlist,
  selmArgusV31,
  selmArgusV32,
  selmArgusV4,
  selmCribBatchA,
]
