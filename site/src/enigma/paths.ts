/** Canonical Enigma-section URLs. Keep historian links here, not scattered. */
export const enigmaPaths = {
  hub: '/enigma',
  message: '/enigma/p1030680',
  corpus: '/enigma/corpus',
  journal: '/enigma/journal',
  machine: '/enigma/nazi-blaster-9000',
  mulein: '/enigma/mulein-board',
} as const

export type EnigmaPath = (typeof enigmaPaths)[keyof typeof enigmaPaths]
