import React from 'react'
import { AGENT_TOOLS, type AgentPoint } from '@/lib/constants'

const sectionStyle: React.CSSProperties = {
  padding: 'var(--space-12) var(--space-6)',
  backgroundColor: 'var(--color-bg)',
  position: 'relative',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 1100,
  margin: '0 auto',
  position: 'relative',
  zIndex: 1,
}

const headingStyle: React.CSSProperties = {
  fontSize: '2rem',
  fontWeight: 700,
  marginBottom: 'var(--space-3)',
  color: 'var(--color-fg)',
}

const leadStyle: React.CSSProperties = {
  fontSize: '1.125rem',
  color: 'var(--color-muted)',
  lineHeight: 1.7,
  maxWidth: 640,
  marginBottom: 'var(--space-8)',
}

const gridStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
  gap: 'var(--space-4)',
  marginBottom: 'var(--space-8)',
}

const toolCardStyle: React.CSSProperties = {
  backgroundColor: 'var(--color-surface)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-3)',
  padding: 'var(--space-5)',
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-2)',
}

const toolNameStyle: React.CSSProperties = {
  fontSize: '0.9375rem',
  fontWeight: 600,
  color: 'var(--color-fg)',
  fontFamily: 'var(--font-mono)',
}

const toolDescStyle: React.CSSProperties = {
  fontSize: '0.8125rem',
  color: 'var(--color-muted)',
  lineHeight: 1.5,
  margin: 0,
}

const pointsStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-4)',
  maxWidth: 640,
}

const pointStyle: React.CSSProperties = {
  display: 'flex',
  gap: 'var(--space-3)',
  alignItems: 'baseline',
}

const bulletStyle: React.CSSProperties = {
  color: 'var(--color-accent)',
  fontFamily: 'var(--font-mono)',
  fontSize: '0.875rem',
  flexShrink: 0,
  lineHeight: 1.6,
}

const pointTextStyle: React.CSSProperties = {
  fontSize: '0.9375rem',
  color: 'var(--color-fg)',
  lineHeight: 1.6,
}

const emphStyle: React.CSSProperties = {
  color: 'var(--color-accent)',
  fontWeight: 600,
  fontStyle: 'normal',
}

const SELLING_POINTS = [
  {
    text: 'agents run in terminals',
    detail: ' — the terminal shouldn\'t compete with them for CPU, RAM, or your attention.',
  },
  {
    text: 'OSC 133 command tracking',
    detail: ' — see which agent task succeeded or failed at a glance, across every tab.',
  },
  {
    text: 'Split panes',
    detail: ' — run an agent and its supervisor side by side. ⌘⇧\\ to split, ⌘⇧H/J/K/L to navigate.',
  },
  {
    text: 'Dual engines',
    detail: ' — SwiftTerm or libghostty, same window. Pick the emulator that fits the workload.',
  },
]

function ToolCard({ tool }: { tool: AgentPoint }) {
  return (
    <div style={toolCardStyle}>
      <span style={toolNameStyle}>{tool.name}</span>
      <p style={toolDescStyle}>{tool.description}</p>
    </div>
  )
}

export default function AgentSection() {
  return (
    <section id="agents" className="earned-path deep-field" style={sectionStyle}>
      <div style={innerStyle}>
        <h2 style={headingStyle}>Built for AI agents</h2>
        <p style={leadStyle}>
          The best terminal agents run in your shell, not in a browser. Umber
          gives them a fast, native host that stays out of their way.
        </p>

        <div style={gridStyle}>
          {AGENT_TOOLS.map((tool) => (
            <ToolCard key={tool.name} tool={tool} />
          ))}
        </div>

        <div style={pointsStyle}>
          {SELLING_POINTS.map((point) => (
            <div key={point.text} style={pointStyle}>
              <span style={bulletStyle}>→</span>
              <p style={pointTextStyle}>
                <em style={emphStyle}>{point.text}</em>
                {point.detail}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
