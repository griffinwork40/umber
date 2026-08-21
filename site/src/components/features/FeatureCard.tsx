import React from 'react'
import type { Feature } from '@/lib/constants'

interface FeatureCardProps {
  feature: Feature
}

const cardStyle: React.CSSProperties = {
  backgroundColor: 'var(--color-surface)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-3)',
  padding: 'var(--space-6)',
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-3)',
  transition: 'border-color var(--motion-duration) ease',
}

const iconWrapStyle: React.CSSProperties = {
  width: 40,
  height: 40,
  borderRadius: 'var(--radius-2)',
  backgroundColor: 'var(--color-bg)',
  border: '1px solid var(--color-border)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontSize: '1.25rem',
  flexShrink: 0,
}

const titleStyle: React.CSSProperties = {
  fontSize: '1rem',
  fontWeight: 600,
  color: 'var(--color-fg)',
  lineHeight: 1.3,
}

const descStyle: React.CSSProperties = {
  fontSize: '0.875rem',
  color: 'var(--color-muted)',
  lineHeight: 1.6,
  margin: 0,
}

// Map icon name strings to emoji/unicode icons
// Keeps icon resolution in one place; no SVG import needed for MVP
const ICON_MAP: Record<string, string> = {
  apple:   '',
  tabs:    '⊟',
  sidebar: '▥',
  palette: '◎',
  cpu:     '⚙',
  shell:   '⬡',
}

export default function FeatureCard({ feature }: FeatureCardProps) {
  const icon = ICON_MAP[feature.icon] ?? '●'

  return (
    <article style={cardStyle}>
      <div style={iconWrapStyle} aria-hidden="true">
        <span>{icon}</span>
      </div>
      <h3 style={titleStyle}>{feature.title}</h3>
      <p style={descStyle}>{feature.description}</p>
    </article>
  )
}
