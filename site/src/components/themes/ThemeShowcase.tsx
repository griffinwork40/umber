'use client'

import React, { useState } from 'react'
import { THEMES } from '@/lib/constants'
import TerminalMockup from '@/components/ui/TerminalMockup'
import Badge from '@/components/ui/Badge'

const sectionStyle: React.CSSProperties = {
  backgroundColor: 'var(--color-surface)',
  padding: 'var(--space-12) var(--space-6)',
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

const tabListStyle: React.CSSProperties = {
  display: 'flex',
  gap: 'var(--space-2)',
  marginBottom: 'var(--space-6)',
  flexWrap: 'wrap',
}

const getTabStyle = (isActive: boolean): React.CSSProperties => ({
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-2)',
  padding: 'var(--space-2) var(--space-4)',
  borderRadius: 'var(--radius-3)',
  border: `1px solid ${isActive ? 'var(--color-accent)' : 'var(--color-border)'}`,
  backgroundColor: isActive ? 'var(--color-selection)' : 'var(--color-bg)',
  color: isActive ? 'var(--color-fg)' : 'var(--color-muted)',
  cursor: 'pointer',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.875rem',
  fontWeight: isActive ? 600 : 400,
  transition: 'all var(--motion-duration) ease',
})

const previewStyle: React.CSSProperties = {
  borderRadius: 'var(--radius-4)',
  overflow: 'hidden',
}

function ThemePreview({ theme }: { theme: typeof THEMES[0] }) {
  const themeVars: Record<string, string> = {
    backgroundColor: theme.background,
    color: theme.foreground,
  }

  return (
    <TerminalMockup
      aria-label={`${theme.displayName} theme preview`}
      themeVars={themeVars}
      title={`zsh — ${theme.displayName}`}
    >
      <div style={{ fontFamily: 'var(--font-mono)', fontSize: '0.875rem', lineHeight: 1.8, color: theme.foreground }}>
        <div>
          <span style={{ color: theme.ansi[2] }}>✓</span>
          <span style={{ color: theme.foreground }}> umber </span>
          <span style={{ color: theme.ansi[4] }}>~/Projects/umber</span>
        </div>
        <div style={{ color: theme.ansi[8] }}>$ swift run Umber</div>
        <div style={{ color: theme.ansi[2] }}>Build complete (0.3s)</div>
        <div style={{ color: theme.ansi[0], backgroundColor: theme.cursor, display: 'inline' }}>▊</div>
      </div>
    </TerminalMockup>
  )
}

export default function ThemeShowcase() {
  const defaultTheme = THEMES.find((t) => t.isDefault) ?? THEMES[0]
  const [activeTheme, setActiveTheme] = useState(defaultTheme.name)

  const current = THEMES.find((t) => t.name === activeTheme) ?? THEMES[0]

  return (
    <section id="themes" style={sectionStyle}>
      <div style={innerStyle}>
        <h2 style={headingStyle}>Themes</h2>
        <p style={subheadStyle}>
          Five palettes ship out of the box. Umber is designed — not ported.
        </p>

        {/* Tab list */}
        <div role="tablist" aria-label="Theme selector" style={tabListStyle}>
          {THEMES.map((theme) => (
            <button
              key={theme.name}
              role="tab"
              aria-selected={theme.name === activeTheme}
              aria-controls={`theme-panel-${theme.name}`}
              id={`theme-tab-${theme.name}`}
              onClick={() => setActiveTheme(theme.name)}
              style={getTabStyle(theme.name === activeTheme)}
              type="button"
            >
              {theme.displayName}
              {theme.isDefault && (
                <Badge>default</Badge>
              )}
            </button>
          ))}
        </div>

        {/* Theme panel */}
        <div
          id={`theme-panel-${current.name}`}
          role="tabpanel"
          aria-labelledby={`theme-tab-${current.name}`}
          style={previewStyle}
        >
          <ThemePreview theme={current} />
        </div>
      </div>
    </section>
  )
}
