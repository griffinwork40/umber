'use client'

import React, { useEffect, useState } from 'react'
import HeroContent from './HeroContent'
import HeroScreenshot from './HeroScreenshot'

const sectionStyle: React.CSSProperties = {
  minHeight: '100vh',
  display: 'flex',
  alignItems: 'center',
  padding: 'var(--space-12) var(--space-6)',
  backgroundColor: 'var(--color-bg)',
  position: 'relative',
  overflow: 'hidden',
}

const innerStyle: React.CSSProperties = {
  maxWidth: 1100,
  margin: '0 auto',
  width: '100%',
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-10)',
  flexWrap: 'wrap',
}

export default function HeroSection() {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    // Trigger entrance animation after mount
    const timer = setTimeout(() => setVisible(true), 50)
    return () => clearTimeout(timer)
  }, [])

  return (
    <section
      aria-labelledby="hero-heading"
      style={{
        ...sectionStyle,
        opacity: visible ? 1 : 0,
        transform: visible ? 'translateY(0)' : 'translateY(16px)',
        transition: `opacity var(--motion-duration) ease, transform var(--motion-duration) ease`,
      }}
    >
      <div style={innerStyle}>
        <HeroContent />
        <HeroScreenshot />
      </div>
    </section>
  )
}
