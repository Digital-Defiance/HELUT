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

export const selmArgusV5: JournalAttachment = {
  href: '/selm/ARGUS_V5_JESS_TURING_2026-09-27.zip',
  title: 'ARGUS v5 Jess/Turing',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '247 KB',
  origin:
    '27 September 2026. Adds an open 1 May hypothesis about U3030, U3032, and U2540. Not an attribution of P1030680. Not a crib. Plaintext not found. The ROT07A grid in this package is withdrawn in v8.1.',
}

export const selmArgusV81: JournalAttachment = {
  href: '/selm/ARGUS_V8_1_ARCHIVAL_UPDATE_2026-09-28.zip',
  title: 'ARGUS v8.1 archival update',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '54 KB',
  origin:
    '28 September 2026. ZTPG 369139 reads 7A, not ROT07A. Volksliste III order and an Offizier card are recorded. Not an attribution. Not a crib.',
}

export const selmZuteilung3271: JournalAttachment = {
  href: '/selm/zuteilungsliste_pruefnr_3271.pdf',
  title: 'Zuteilungsliste Prüf-Nr. 3271',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '1.9 MB',
  origin:
    '2 October 2026. Frode Weierud, via Selm. Ausgabe 1941, Kennworte Dorsch, Forelle, Haifisch, Zander, distribution stamps 25 May 1943. Not the 4 March 1945 Hering list. Columns not transcribed.',
}

export const selmArgusV101: JournalAttachment = {
  href: '/selm/ARGUS_10_1_JUBILEE_2026-10-01.zip',
  title: 'ARGUS 10.1 / X.1',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '10 KB',
  origin:
    '1 October 2026. Administrative-provenance lane for who produced naval keys. P1030680 stays unbroken. Not a crib. Not a reason to restart compute.',
}

export const selmArgusV90: JournalAttachment = {
  href: '/selm/ARGUS_V9_0_ARCHIVAL_AUTHENTICATION_2026-09-28.zip',
  title: 'ARGUS v9.0',
  kind: 'archive',
  credit: SELM_CREDIT,
  bytesLabel: '59 KB',
  origin:
    '28 September 2026. Rolls up the DEFE 3 reading, the Mahon Kenngruppen example, and the open Kew and Swedish requests. Not a decrypt.',
}

export const selmTicomI38Cover: JournalAttachment = {
  href: '/selm/IMG_1234.jpeg',
  title: 'TICOM I-38 cover',
  kind: 'image',
  credit: SELM_CREDIT,
  bytesLabel: '340 KB',
  origin:
    'Interrogation of Lt. Hans-Joachim Frowein, 21 June 1945. Cover only. Section 31 is not on this page.',
}

export const selmTicomI38Page3: JournalAttachment = {
  href: '/selm/IMG_1235.jpeg',
  title: 'TICOM I-38 page 3',
  kind: 'image',
  credit: SELM_CREDIT,
  bytesLabel: '600 KB',
  origin:
    'Page 3. A crib of about 25 letters, and one turnover in the right-hand wheel against more than one. Not section 31.',
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

export const christofferCribCode: JournalAttachment = {
  href: '/christoffer/P1030680-crib-search-code.zip',
  title: 'P1030680 crib-search code',
  kind: 'archive',
  credit: 'Christoffer Duif',
  bytesLabel: '117 KB',
  origin:
    '7 October 2026. WebGPU bombe, kernel V5. Read, not run. Same 1.6×10^10 right-ring placement as HELUT. No deletions.',
}

export const selmSchluesselM323: JournalAttachment = {
  href: '/selm/Schluessel_M_Allgemeine_Bestimmungen_1941_62.pdf',
  title: 'M.Dv. Nr. 32/3 — Der Schlüssel M, Allgemeine Bestimmungen (1941, amended)',
  kind: 'pdf',
  credit: SELM_CREDIT,
  bytesLabel: '4.2 MB',
  origin:
    'Scan inspected October 2026. Page 34a, Deckbl. 8, is §157: Thetis for tactical U-boat exercises, Allgemein and Offizier, change at 0700 DGZ. The 17 March 1943 order covers Deckblätter 5–8. Not a May 1945 key sheet.',
}

export const christofferZtpgu39136: JournalAttachment = {
  href: '/christoffer/ztpgu-39136-1945-05-04.jpg',
  title: 'ZIP/ZTPGU/39136 — 4 May 1945',
  kind: 'image',
  credit: 'Sea War Museum, Thyborøn, via Christoffer Duif',
  bytesLabel: '294 KB',
  origin:
    'TOO 0935, TOI 0819/4/5/45, 4020 kc/s. Norway as headquarters of U-boat operational control. Not a 1 May Thetis intercept.',
}

export const christofferZtpgu39087: JournalAttachment = {
  href: '/christoffer/ztpgu-39087-1945-05-08.jpg',
  title: 'ZIP/ZTPGU/39087 — 8 May 1945',
  kind: 'image',
  credit: 'Sea War Museum, Thyborøn, via Christoffer Duif',
  bytesLabel: '274 KB',
  origin:
    'TOO 1215, TOI 1050/8/5/45, 5400 kc/s. Captain (U/B) West to B.D.U. asks the whereabouts of five boats, including U-3503. Not a 1 May Thetis intercept.',
}

export const christofferDefeOcr: JournalAttachment = {
  href: '/christoffer/DEFE3-577-579-OCR-index.zip',
  title: 'DEFE 3/577–579 OCR and dated index',
  kind: 'archive',
  credit: 'Christoffer Duif',
  bytesLabel: '978 KB',
  origin:
    '7 October 2026. 2,215 pages, 1,974 dated. Thetis, VROL, and NMKA are absent from the page texts. Not a stronger negative than Phase 76.',
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
  selmArgusV5,
  selmArgusV81,
  selmArgusV90,
  selmArgusV101,
  selmZuteilung3271,
  selmSchluesselM323,
  selmTicomI38Cover,
  selmTicomI38Page3,
  selmCribBatchA,
]
