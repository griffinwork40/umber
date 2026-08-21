import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import FeaturesSection from './FeaturesSection'
import { FEATURES } from '@/lib/constants'

describe('FeaturesSection', () => {
  it('renders without throwing', () => {
    render(<FeaturesSection />)
  })

  it('renders the h2 heading', () => {
    render(<FeaturesSection />)
    expect(screen.getByRole('heading', { level: 2, name: 'Features' })).toBeInTheDocument()
  })

  it('renders exactly 6 feature cards', () => {
    render(<FeaturesSection />)
    expect(screen.getAllByRole('article')).toHaveLength(6)
  })

  it('renders all 6 feature titles as h3 headings', () => {
    render(<FeaturesSection />)
    FEATURES.forEach((feature) => {
      expect(screen.getByRole('heading', { level: 3, name: feature.title })).toBeInTheDocument()
    })
  })

  it('renders all 6 feature descriptions', () => {
    render(<FeaturesSection />)
    FEATURES.forEach((feature) => {
      expect(screen.getByText(feature.description)).toBeInTheDocument()
    })
  })

  it('has section element with id="features"', () => {
    const { container } = render(<FeaturesSection />)
    expect(container.querySelector('section#features')).toBeInTheDocument()
  })

  it('renders "Native macOS App" feature', () => {
    render(<FeaturesSection />)
    expect(screen.getByText('Native macOS App')).toBeInTheDocument()
  })

  it('renders "Umber Palette" feature', () => {
    render(<FeaturesSection />)
    expect(screen.getByText('Umber Palette')).toBeInTheDocument()
  })

  it('renders "Dual Emulator Cores" feature', () => {
    render(<FeaturesSection />)
    expect(screen.getByText('Dual Emulator Cores')).toBeInTheDocument()
  })
})
