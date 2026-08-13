import { Link, Navigate, useParams } from 'react-router-dom'
import { getProject } from '../projects/registry'
import { ProjectJournalShell } from './ProjectJournalShell'

/**
 * Placeholder journal for queued projects — keeps URLs stable before content exists.
 */
export function QueuedProjectJournalPage() {
  const { slug } = useParams<{ slug: string }>()
  const project = slug ? getProject(slug) : undefined

  if (!project) {
    return <Navigate to="/projects" replace />
  }

  // Projects with dedicated journal components should not hit this route.
  if (project.slug === 'p1030680') {
    return <Navigate to="/projects/p1030680/journal" replace />
  }
  if (project.slug === 'e256') {
    return <Navigate to="/projects/e256/journal" replace />
  }
  if (project.slug === 'differentiable-hardware') {
    return <Navigate to="/projects/differentiable-hardware/journal" replace />
  }
  if (project.slug === 'polymorphic-ciphers') {
    return <Navigate to="/projects/polymorphic-ciphers/journal" replace />
  }

  return (
    <ProjectJournalShell
      kicker={`${project.kicker} · Journal`}
      title={`${project.title} — journal reserved`}
      lede="No graded runs yet. This URL is reserved so the project can grow a ledger without renaming routes later."
      hubPath={`/projects/${project.slug}`}
    >
      <section className="band">
        <div className="shell prose">
          <p>{project.summary}</p>
          <p>
            <Link to={`/projects/${project.slug}`}>Return to hub</Link> ·{' '}
            <Link to="/projects">All projects</Link>
          </p>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
