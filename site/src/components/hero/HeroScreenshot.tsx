import React from 'react'
import TerminalMockup from '@/components/ui/TerminalMockup'

const screenshotWrapStyle: React.CSSProperties = {
  flex: 1,
  minWidth: 0,
  maxWidth: 600,
}

export default function HeroScreenshot() {
  return (
    <div style={screenshotWrapStyle}>
      <TerminalMockup aria-label="Umber terminal screenshot">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/images/umber-screenshot.png"
          alt="Umber terminal screenshot"
          width={580}
          height={380}
          style={{
            width: '100%',
            height: 'auto',
            display: 'block',
            borderRadius: 'var(--radius-2)',
          }}
          onError={(e) => {
            // Fallback to icon if screenshot fails to load
            const img = e.currentTarget
            img.src = '/images/icon-1024.png'
            img.alt = 'Umber app icon'
            img.style.width = '80px'
            img.style.height = '80px'
            img.style.margin = 'var(--space-8) auto'
          }}
        />
      </TerminalMockup>
    </div>
  )
}
