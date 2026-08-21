import React from 'react'
import { KEYMAP } from '@/lib/constants'
import CodeBlock from '@/components/ui/CodeBlock'

const sectionStyle: React.CSSProperties = {
  padding: 'var(--space-12) var(--space-6)',
  maxWidth: 1100,
  margin: '0 auto',
}

const headingStyle: React.CSSProperties = {
  fontSize: '2rem',
  fontWeight: 700,
  marginBottom: 'var(--space-8)',
  color: 'var(--color-fg)',
}

const groupsStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
  gap: 'var(--space-7)',
}

const groupStyle: React.CSSProperties = {
  backgroundColor: 'var(--color-surface)',
  borderRadius: 'var(--radius-3)',
  border: '1px solid var(--color-border)',
  overflow: 'hidden',
}

const groupHeadingStyle: React.CSSProperties = {
  padding: 'var(--space-3) var(--space-5)',
  backgroundColor: 'var(--color-bg)',
  borderBottom: '1px solid var(--color-border)',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.75rem',
  fontWeight: 600,
  color: 'var(--color-muted)',
  textTransform: 'uppercase',
  letterSpacing: '0.08em',
}

const tableStyle: React.CSSProperties = {
  width: '100%',
  borderCollapse: 'collapse',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.875rem',
}

const thStyle: React.CSSProperties = {
  padding: 'var(--space-2) var(--space-5)',
  textAlign: 'left',
  color: 'var(--color-muted)',
  fontSize: '0.75rem',
  fontWeight: 500,
  borderBottom: '1px solid var(--color-border)',
}

const tdStyle: React.CSSProperties = {
  padding: 'var(--space-2) var(--space-5)',
  color: 'var(--color-fg)',
  borderBottom: '1px solid var(--color-border)',
  fontSize: '0.875rem',
}


export default function KeymapSection() {
  return (
    <section id="keymap" className="earned-path" style={{ backgroundColor: 'var(--color-bg)', position: 'relative' as const }}>
      <div style={sectionStyle}>
        <h2 style={headingStyle}>Keyboard Shortcuts</h2>
        <div style={groupsStyle} className="keymap-grid">
          {KEYMAP.map((group) => (
            <div key={group.group} style={groupStyle}>
              <div style={groupHeadingStyle}>{group.group}</div>
              <table style={tableStyle}>
                <caption style={{ display: 'none' }}>
                  {group.group} keyboard shortcuts
                </caption>
                <thead>
                  <tr>
                    <th scope="col" style={thStyle}>Shortcut</th>
                    <th scope="col" style={thStyle}>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {group.entries.map((entry) => (
                    <tr key={entry.shortcut}>
                      <td style={tdStyle}>
                        <CodeBlock variant="kbd" code={entry.shortcut} />
                      </td>
                      <td style={tdStyle}>{entry.description}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
