'use client'

import React, { useState } from 'react'

interface CodeBlockProps {
  code: string
  language?: string
  className?: string
}

const wrapperStyle: React.CSSProperties = {
  position: 'relative',
  backgroundColor: 'var(--color-surface)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-3)',
  overflow: 'hidden',
}

const preStyle: React.CSSProperties = {
  padding: 'var(--space-4) var(--space-7) var(--space-4) var(--space-4)',
  overflowX: 'auto',
  margin: 0,
  fontFamily: 'var(--font-mono)',
  fontSize: '0.875rem',
  lineHeight: 1.6,
  color: 'var(--color-fg)',
}

const copyButtonStyle: React.CSSProperties = {
  position: 'absolute',
  top: 'var(--space-2)',
  right: 'var(--space-2)',
  padding: 'var(--space-1) var(--space-3)',
  backgroundColor: 'var(--color-bg)',
  color: 'var(--color-muted)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-2)',
  fontFamily: 'var(--font-sans)',
  fontSize: '0.75rem',
  cursor: 'pointer',
  transition: 'color var(--motion-duration) ease, border-color var(--motion-duration) ease',
}

export default function CodeBlock({ code, language, className }: CodeBlockProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // Clipboard API unavailable (e.g. in test environments without mock)
    }
  }

  return (
    <div style={wrapperStyle} className={className}>
      <pre style={preStyle}>
        <code className={language ? `language-${language}` : undefined}>
          {code}
        </code>
      </pre>
      <button
        type="button"
        onClick={handleCopy}
        style={copyButtonStyle}
        aria-label="Copy code"
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            handleCopy()
          }
        }}
      >
        {copied ? 'Copied!' : 'Copy'}
      </button>
    </div>
  )
}
