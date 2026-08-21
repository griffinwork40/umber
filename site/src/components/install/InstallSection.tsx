import React from 'react'
import { INSTALL_STEPS, GATEKEEPER_COMMAND } from '@/lib/constants'
import CodeBlock from '@/components/ui/CodeBlock'
import Badge from '@/components/ui/Badge'

const sectionStyle: React.CSSProperties = {
  padding: 'var(--space-12) var(--space-6)',
  backgroundColor: 'var(--color-bg)',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 800,
  margin: '0 auto',
}

const headingStyle: React.CSSProperties = {
  fontSize: '2rem',
  fontWeight: 700,
  marginBottom: 'var(--space-4)',
  color: 'var(--color-fg)',
}

const requirementsStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-3)',
  marginBottom: 'var(--space-8)',
}

const requirementsLabelStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  fontSize: '0.875rem',
}

const stepsListStyle: React.CSSProperties = {
  listStyle: 'none',
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-6)',
}

const stepStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'auto 1fr',
  gap: 'var(--space-4)',
  alignItems: 'start',
}

const stepNumberStyle: React.CSSProperties = {
  width: 32,
  height: 32,
  borderRadius: '50%',
  backgroundColor: 'var(--color-accent)',
  color: 'var(--color-bg)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontWeight: 700,
  fontSize: '0.875rem',
  flexShrink: 0,
  marginTop: 2,
}

const stepContentStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-3)',
}

const stepDescStyle: React.CSSProperties = {
  color: 'var(--color-fg)',
  fontWeight: 500,
}

const calloutStyle: React.CSSProperties = {
  marginTop: 'var(--space-8)',
  padding: 'var(--space-5)',
  backgroundColor: 'var(--color-surface)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-3)',
  borderLeft: '3px solid var(--color-accent)',
}

const calloutHeadingStyle: React.CSSProperties = {
  fontWeight: 600,
  marginBottom: 'var(--space-3)',
  color: 'var(--color-fg)',
  fontSize: '0.9375rem',
}

const calloutTextStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  fontSize: '0.875rem',
  marginBottom: 'var(--space-4)',
  lineHeight: 1.6,
}

export default function InstallSection() {
  return (
    <section id="install" style={sectionStyle}>
      <div style={innerStyle}>
        <h2 style={headingStyle}>Install</h2>

        <div style={requirementsStyle}>
          <span style={requirementsLabelStyle}>Requirements:</span>
          <Badge>macOS 14+</Badge>
          <Badge>Xcode CLT</Badge>
        </div>

        <ol style={stepsListStyle}>
          {INSTALL_STEPS.map((step) => (
            <li key={step.step} style={stepStyle}>
              <div style={stepNumberStyle} aria-hidden="true">
                {step.step}
              </div>
              <div style={stepContentStyle}>
                <p style={stepDescStyle}>{step.description}</p>
                <CodeBlock code={step.code} language={step.language} />
              </div>
            </li>
          ))}
        </ol>

        {/* Gatekeeper callout */}
        <aside style={calloutStyle} aria-label="Gatekeeper note">
          <p style={calloutHeadingStyle}>Gatekeeper warning?</p>
          <p style={calloutTextStyle}>
            If macOS prevents Umber from opening because it is from an unidentified
            developer, remove the quarantine attribute:
          </p>
          <CodeBlock code={GATEKEEPER_COMMAND} language="bash" />
        </aside>
      </div>
    </section>
  )
}
