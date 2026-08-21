import React from 'react'

interface BadgeProps {
  children: React.ReactNode
  className?: string
}

const badgeStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  padding: 'var(--space-1) var(--space-3)',
  backgroundColor: 'var(--color-surface)',
  color: 'var(--color-muted)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-4)',
  fontFamily: 'var(--font-mono)',
  fontSize: '0.75rem',
  fontWeight: 500,
  lineHeight: 1.4,
  whiteSpace: 'nowrap',
}

export default function Badge({ children, className }: BadgeProps) {
  return (
    <span style={badgeStyle} className={className}>
      {children}
    </span>
  )
}
