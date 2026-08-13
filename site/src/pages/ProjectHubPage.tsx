import { Link, Navigate, useParams } from 'react-router-dom'
import { getProject } from '../projects/registry'
import type { ProjectStatus } from '../projects/types'

const statusLabel: Record<ProjectStatus, string> = {
  active: 'Active',
  research: 'Research',
  queued: 'Queued',
  parked: 'Parked',
}

export function ProjectHubPage() {
  const { slug } = useParams<{ slug: string }>()
  const project = slug ? getProject(slug) : undefined

  if (!project) {
    return <Navigate to="/projects" replace />
  }

  const pages = project.pages.filter((p) => p.kind !== 'hub')

  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">
              Project · Phase {project.phase} · {statusLabel[project.status]}
            </div>
            <h2>{project.title}</h2>
            <p className="lede">{project.subtitle}</p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              {project.summary}
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Stakes</div>
            <h2>What this project must prove</h2>
          </div>
          <ul className="stack-list">
            {project.stakes.map((s, i) => (
              <li key={s}>
                <span className="mono">{String(i + 1).padStart(2, '0')}</span>
                <span>{s}</span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Pages</div>
            <h2>Journal and related work</h2>
            <p>
              Add essays and labs under this project as they earn a URL. The registry is the
              source of truth.
            </p>
          </div>
          {pages.length === 0 ? (
            <p className="prose">
              Hub only for now — journal and essays will land here when the first gradeable run
              exists.
            </p>
          ) : (
            <ul className="stack-list">
              {pages.map((page) => (
                <li key={page.path}>
                  <span className="mono">{page.kind.toUpperCase()}</span>
                  <span>
                    <strong>
                      <Link to={page.path}>{page.label}</Link>
                    </strong>
                    {page.blurb ? <> — {page.blurb}</> : null}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {project.relatedDocs && project.relatedDocs.length > 0 ? (
            <p className="prose" style={{ marginTop: '1.5rem' }}>
              <span className="mono">REPO</span> {project.relatedDocs.join(' · ')}
            </p>
          ) : null}
        </div>
      </section>

      <section className="band-ink">
        <div className="shell">
          <Link className="btn ghost" to="/projects">
            All projects
          </Link>
        </div>
      </section>
    </main>
  )
}
