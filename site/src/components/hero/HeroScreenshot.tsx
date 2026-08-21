import React from 'react'
import Image from 'next/image'

const screenshotWrapStyle: React.CSSProperties = {
  flex: 1.4,
  minWidth: 0,
  maxWidth: 720,
  position: 'relative',
}

const screenshotImgStyle: React.CSSProperties = {
  width: '100%',
  height: 'auto',
  display: 'block',
  borderRadius: 'var(--radius-3)',
  boxShadow: '0 20px 60px var(--color-shadow)',
}

export default function HeroScreenshot() {
  return (
    <div style={screenshotWrapStyle} className="hero-screenshot contour-frame">
      <Image
        src="/images/umber-screenshot.png"
        alt="Umber running agent-afk with sidebar file tree and syntax-highlighted output"
        width={720}
        height={472}
        style={screenshotImgStyle}
        priority
      />
    </div>
  )
}
