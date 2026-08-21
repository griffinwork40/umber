import React from 'react'
import { SITE_META } from '@/lib/constants'
import Button from '@/components/ui/Button'

const contentStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-6)',
  maxWidth: 520,
}

const iconWrapStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-3)',
}

const versionStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  fontFamily: 'var(--font-mono)',
  fontSize: '0.8125rem',
}

const h1Style: React.CSSProperties = {
  fontSize: 'clamp(3rem, 8vw, 5rem)',
  fontWeight: 800,
  letterSpacing: '-0.04em',
  lineHeight: 1,
  color: 'var(--color-fg)',
  margin: 0,
}

const taglineStyle: React.CSSProperties = {
  fontSize: '1.125rem',
  color: 'var(--color-muted)',
  lineHeight: 1.6,
  maxWidth: 460,
}

const ctaGroupStyle: React.CSSProperties = {
  display: 'flex',
  gap: 'var(--space-3)',
  flexWrap: 'wrap',
}

export default function HeroContent() {
  return (
    <div style={contentStyle}>
      {/* Icon + version badge */}
      <div style={iconWrapStyle}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/images/icon-1024.png"
          alt="Umber app icon"
          width={48}
          height={48}
          style={{ borderRadius: 'var(--radius-3)' }}
        />
        <span style={versionStyle}>{SITE_META.version}</span>
      </div>

      {/* Heading */}
      <h1 id="hero-heading" style={h1Style}>
        {SITE_META.title}
      </h1>

      {/* Tagline */}
      <p style={taglineStyle}>{SITE_META.tagline}</p>

      {/* CTAs */}
      <div style={ctaGroupStyle}>
        <Button href="#install" variant="primary">
          Install
        </Button>
        <Button href={SITE_META.repoUrl} variant="secondary">
          GitHub →
        </Button>
      </div>
    </div>
  )
}
