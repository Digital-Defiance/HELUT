export type ProjectStatus = 'active' | 'research' | 'queued' | 'parked'

export type ProjectPageLink = {
  /** Absolute path in the SPA */
  path: string
  label: string
  kind: 'hub' | 'journal' | 'essay' | 'lab' | 'docs'
  blurb?: string
}

export type Project = {
  slug: string
  title: string
  subtitle: string
  pillar?: 'turing' | 'schneier' | 'grand-challenge' | 'campaign'
  phase: 'I' | 'II' | 'III' | 'campaign'
  status: ProjectStatus
  kicker: string
  summary: string
  /** Short bullets for the hub / index */
  stakes: string[]
  pages: ProjectPageLink[]
  relatedDocs?: string[]
}
