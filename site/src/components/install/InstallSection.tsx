'use client'

import React, { useState } from 'react'
import { INSTALL_STEPS, GATEKEEPER_COMMAND, SITE_META } from '@/lib/constants'
import CodeBlock from '@/components/ui/CodeBlock'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const sectionStyle: React.CSSProperties = {
  padding: 'var(--space-12) var(--space-6)',
  backgroundColor: 'var(--color-bg)',
  position: 'relative',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 800,
  margin: '0 auto',
  position: 'relative',
  zIndex: 1,
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

const downloadBoxStyle: React.CSSProperties = {
  padding: 'var(--space-8)',
  backgroundColor: 'var(--color-surface)',
  borderRadius: 'var(--radius-3)',
  border: '1px solid var(--color-border)',
  textAlign: 'center' as const,
  marginBottom: 'var(--space-8)',
}

const downloadSubStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  fontSize: '0.8125rem',
  marginTop: 'var(--space-3)',
}

const dividerStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-4)',
  margin: 'var(--space-6) 0',
  color: 'var(--color-muted)',
  fontSize: '0.8125rem',
}

const dividerLineStyle: React.CSSProperties = {
  flex: 1,
  height: 1,
  backgroundColor: 'var(--color-border)',
}

const toggleBtnStyle: React.CSSProperties = {
  background: 'none',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-3)',
  color: 'var(--color-muted)',
  padding: 'var(--space-2) var(--space-5)',
  cursor: 'pointer',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.875rem',
  transition: 'all var(--motion-duration) ease',
}

const stepsListStyle: React.CSSProperties = {
  listStyle: 'none',
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-6)',
  marginTop: 'var(--space-6)',
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
  const [showSource, setShowSource] = useState(false)
  const [showGatekeeper, setShowGatekeeper] = useState(false)

  return (
    <section id="install" className="scope-rule elevated-field" style={sectionStyle}>
      <div style={innerStyle}>
        <h2 style={headingStyle}>Install</h2>

        <div style={requirementsStyle}>
          <span style={requirementsLabelStyle}>Requirements:</span>
          <Badge>macOS 14+</Badge>
        </div>

        {/* DMG download — primary path */}
        <div style={downloadBoxStyle}>
          <Button href={SITE_META.dmgUrl} variant="primary">
            Download Umber v0.2.0
          </Button>
          <p style={downloadSubStyle}>
            Universal binary · 1.9 MB · signed &amp; notarized
          </p>
        </div>

        {/* Gatekeeper callout — collapsed by default */}
        <div style={{ textAlign: 'center' as const, marginBottom: 'var(--space-4)' }}>
          <button
            style={toggleBtnStyle}
            onClick={() => setShowGatekeeper(!showGatekeeper)}
            aria-expanded={showGatekeeper}
            type="button"
          >
            {showGatekeeper ? 'Hide' : 'Having trouble opening it?'}
          </button>
        </div>

        {showGatekeeper && (
          <aside style={calloutStyle} aria-label="Gatekeeper note">
            <p style={calloutHeadingStyle}>Troubleshooting</p>
            <p style={calloutTextStyle}>
              The DMG is signed and notarized, so macOS should open it without
              complaint. If you still see a Gatekeeper prompt, run this once:
            </p>
            <CodeBlock code={GATEKEEPER_COMMAND} language="bash" />
          </aside>
        )}

        {/* Build from source — secondary path */}
        <div style={dividerStyle}>
          <div style={dividerLineStyle} />
          <span>or</span>
          <div style={dividerLineStyle} />
        </div>

        <div style={{ textAlign: 'center' as const }}>
          <button
            style={toggleBtnStyle}
            onClick={() => setShowSource(!showSource)}
            aria-expanded={showSource}
            type="button"
          >
            {showSource ? 'Hide' : 'Build from source'}
          </button>
        </div>

        {showSource && (
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
        )}
      </div>
    </section>
  )
}
