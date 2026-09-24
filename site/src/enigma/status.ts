/**
 * Public P1030680 status. Flip only when BREAK_P1030680.md records BREAK FOUND.
 * The message page and Enigma hub read this so a decrypt does not require a redesign.
 */
export const p1030680Status = {
  state: 'unbroken' as const,
  label: 'Historically unbroken',
  date: '1 May 1945',
  length: 72,
  indicators: 'VROL NMKA',
  keyNet: 'M-Thetis (working assignment)',
  ciphertextHead: 'JCRSA…HVGF',
}
