import React from 'react'
import HeroSection from '@/components/hero/HeroSection'
import FeaturesSection from '@/components/features/FeaturesSection'
import ThemeShowcase from '@/components/themes/ThemeShowcase'
import InstallSection from '@/components/install/InstallSection'
import KeymapSection from '@/components/keymap/KeymapSection'
import Footer from '@/components/footer/Footer'

const navStyle: React.CSSProperties = {
  position: 'absolute',
  left: '-9999px',
  width: 1,
  height: 1,
  overflow: 'hidden',
}

export default function Page() {
  return (
    <>
      <nav aria-label="Page sections" style={navStyle}>
        <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
          <li><a href="#main-content">Skip to content</a></li>
          <li><a href="#features">Features</a></li>
          <li><a href="#themes">Themes</a></li>
          <li><a href="#install">Install</a></li>
          <li><a href="#keymap">Keymap</a></li>
        </ul>
      </nav>
      <main id="main-content">
        <HeroSection />
        <FeaturesSection />
        <ThemeShowcase />
        <InstallSection />
        <KeymapSection />
      </main>
      <Footer />
    </>
  )
}
