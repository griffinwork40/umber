import React from 'react'

interface TerminalMockupProps {
  children: React.ReactNode
  themeVars?: Record<string, string>
  title?: string
  'aria-label'?: string
}

const chromeStyle: React.CSSProperties = {
  borderRadius: 'var(--radius-3)',
  overflow: 'hidden',
  boxShadow: '0 20px 60px var(--color-shadow)',
  border: '1px solid var(--color-border)',
}

const titleBarStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-2)',
  padding: 'var(--space-3) var(--space-4)',
  backgroundColor: 'var(--color-titlebar)',
}

const titleTextStyle: React.CSSProperties = {
  flex: 1,
  textAlign: 'center',
  color: 'var(--color-muted)',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.75rem',
  opacity: 0.7,
}

const dotBaseStyle: React.CSSProperties = {
  width: 12,
  height: 12,
  borderRadius: '50%',
  flexShrink: 0,
}

export default function TerminalMockup({
  children,
  themeVars,
  title = 'zsh',
  'aria-label': ariaLabel = 'Terminal mockup',
}: TerminalMockupProps) {
  const bodyStyle: React.CSSProperties = {
    backgroundColor: 'var(--color-bg)',
    color: 'var(--color-fg)',
    padding: 'var(--space-4)',
    minHeight: 200,
    fontFamily: 'var(--font-mono)',
    fontSize: '0.875rem',
    lineHeight: 1.6,
    ...(themeVars ? Object.fromEntries(
      Object.entries(themeVars).map(([k, v]) => [k, v])
    ) : {}),
  }

  return (
    <div style={chromeStyle} aria-label={ariaLabel}>
      {/* macOS title bar with traffic-light dots */}
      <div style={titleBarStyle} role="presentation" aria-hidden="true">
        <div
          data-testid="dot-close"
          style={{ ...dotBaseStyle, backgroundColor: 'var(--color-dot-close)' }}
        />
        <div
          data-testid="dot-minimize"
          style={{ ...dotBaseStyle, backgroundColor: 'var(--color-dot-minimize)' }}
        />
        <div
          data-testid="dot-maximize"
          style={{ ...dotBaseStyle, backgroundColor: 'var(--color-dot-maximize)' }}
        />
        {title && <span style={titleTextStyle}>{title}</span>}
      </div>
      {/* Terminal body */}
      <div style={bodyStyle}>
        {children}
      </div>
    </div>
  )
}
