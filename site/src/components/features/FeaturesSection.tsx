import React from 'react'
import { FEATURES } from '@/lib/constants'
import FeatureCard from './FeatureCard'

const sectionStyle: React.CSSProperties = {
  padding: 'var(--space-12) var(--space-6)',
  backgroundColor: 'var(--color-bg)',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 1100,
  margin: '0 auto',
}

const headingStyle: React.CSSProperties = {
  fontSize: '2rem',
  fontWeight: 700,
  marginBottom: 'var(--space-4)',
  color: 'var(--color-fg)',
}

const subheadStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  marginBottom: 'var(--space-8)',
  fontSize: '1rem',
}

const gridStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
  gap: 'var(--space-5)',
}

export default function FeaturesSection() {
  return (
    <section id="features" style={sectionStyle}>
      <div style={innerStyle}>
        <h2 style={headingStyle}>Features</h2>
        <p style={subheadStyle}>
          What works in v0.1 — no AI features, by design.
        </p>
        <div style={gridStyle}>
          {FEATURES.map((feature) => (
            <FeatureCard key={feature.title} feature={feature} />
          ))}
        </div>
      </div>
    </section>
  )
}
