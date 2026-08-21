import React from 'react'

export type ButtonVariant = 'primary' | 'secondary'

interface ButtonProps {
  variant?: ButtonVariant
  children: React.ReactNode
  href?: string
  onClick?: () => void
  className?: string
  type?: 'button' | 'submit' | 'reset'
}

const styles: Record<ButtonVariant, React.CSSProperties> = {
  primary: {
    backgroundColor: 'var(--color-accent)',
    color: 'var(--color-bg)',
    border: '1px solid var(--color-accent)',
  },
  secondary: {
    backgroundColor: 'var(--color-surface)',
    color: 'var(--color-fg)',
    border: '1px solid var(--color-border)',
  },
}

const baseStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 'var(--space-3) var(--space-6)',
  borderRadius: 'var(--radius-3)',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.9375rem',
  fontWeight: 600,
  textDecoration: 'none',
  cursor: 'pointer',
  transition: 'opacity var(--motion-duration) ease',
  lineHeight: 1.5,
}

export default function Button({
  variant = 'primary',
  children,
  href,
  onClick,
  className,
  type = 'button',
}: ButtonProps) {
  const combinedStyle = { ...baseStyle, ...styles[variant] }

  if (href) {
    return (
      <a
        href={href}
        style={combinedStyle}
        className={className}
        data-variant={variant}
      >
        {children}
      </a>
    )
  }

  return (
    <button
      type={type}
      onClick={onClick}
      style={combinedStyle}
      className={className}
      data-variant={variant}
    >
      {children}
    </button>
  )
}
