import React from 'react'
import { SITE_META } from '@/lib/constants'

const footerStyle: React.CSSProperties = {
  borderTop: '1px solid var(--color-border)',
  backgroundColor: 'var(--color-surface)',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 1100,
  margin: '0 auto',
  padding: 'var(--space-6) var(--space-6)',
  display: 'flex',
  flexWrap: 'wrap',
  alignItems: 'center',
  gap: 'var(--space-4)',
}

const brandStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-2)',
  fontWeight: 600,
  color: 'var(--color-fg)',
}

const metaStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-4)',
  marginLeft: 'auto',
  flexWrap: 'wrap',
}

const linkStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  textDecoration: 'none',
  fontSize: '0.875rem',
}

const textStyle: React.CSSProperties = {
  color: 'var(--color-muted)',
  fontSize: '0.875rem',
}

export default function Footer() {
  return (
    <footer style={footerStyle}>
      <div style={innerStyle}>
        {/* Brand */}
        <div style={brandStyle}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/images/icon-1024.png"
            alt="Umber app icon"
            width={32}
            height={32}
            style={{ borderRadius: 'var(--radius-2)' }}
          />
          <span>{SITE_META.title}</span>
        </div>

        {/* Meta links */}
        <div style={metaStyle}>
          <a
            href={`${SITE_META.repoUrl}/blob/main/LICENSE`}
            style={linkStyle}
            target="_blank"
            rel="noopener noreferrer"
          >
            MIT License
          </a>
          <a
            href={SITE_META.repoUrl}
            style={linkStyle}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="GitHub repository"
          >
            GitHub
          </a>
          <span style={textStyle}>Built by Griffin Long</span>
        </div>
      </div>
    </footer>
  )
}
