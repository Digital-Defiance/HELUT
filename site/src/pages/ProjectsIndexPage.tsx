import { Link } from 'react-router-dom'
import { projects } from '../projects/registry'
import type { Project, ProjectStatus } from '../projects/types'

const statusLabel: Record<ProjectStatus, string> = {
  active: 'Active',
  research: 'Research',
  queued: 'Queued',
  parked: 'Parked',
}

function ProjectCard({ project }: { project: Project }) {
  const journal = project.pages.find((p) => p.kind === 'journal')
  return (
    <article className="project-card">
      <div className="project-card-top">
        <span className="mono">{project.kicker}</span>
        <span className={`project-status project-status--${project.status}`}>
          {statusLabel[project.status]}
        </span>
      </div>
      <h3>
        <Link to={`/projects/${project.slug}`}>{project.title}</Link>
      </h3>
      <p className="project-subtitle">{project.subtitle}</p>
      <p>{project.summary}</p>
      <div className="project-card-actions">
        <Link className="btn" to={`/projects/${project.slug}`}>
          Open hub
        </Link>
        {journal ? (
          <Link className="btn ghost" to={journal.path}>
            Journal
          </Link>
        ) : null}
      </div>
    </article>
  )
}

export function ProjectsIndexPage() {
  const live = projects.filter((p) => p.status === 'active' || p.status === 'research')
  const queued = projects.filter((p) => p.status === 'queued' || p.status === 'parked')

  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Projects</div>
            <h2>Campaigns, pillars, and the next melts</h2>
            <p className="lede">
              Each project owns its hub, journal, and related pages. Pillar&nbsp;I (netlist-clocked
              FHE) lives in the stack and encrypted SING benches. The live campaign is still
              P1030680. Differentiable hardware and polymorphic Red/Blue ciphers get the same
              ledger treatment as they harden from research notes into public standards.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Live &amp; research</div>
            <h2>Where the Metal is pointed</h2>
          </div>
          <div className="project-grid">
            {live.map((p) => (
              <ProjectCard key={p.slug} project={p} />
            ))}
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Queued</div>
            <h2>Phase II &amp; III seats</h2>
            <p>
              Hubs exist so future journals have a home before the first experiment runs. No
              fake progress — just reserved structure.
            </p>
          </div>
          <div className="project-grid">
            {queued.map((p) => (
              <ProjectCard key={p.slug} project={p} />
            ))}
          </div>
        </div>
      </section>
    </main>
  )
}
