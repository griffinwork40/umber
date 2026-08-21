import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import HeroSection from './HeroSection'
import { SITE_META } from '@/lib/constants'

describe('HeroSection', () => {
  it('renders without throwing', () => {
    render(<HeroSection />)
  })

  it('renders h1 with text "Umber"', () => {
    render(<HeroSection />)
    expect(screen.getByRole('heading', { level: 1, name: 'Umber' })).toBeInTheDocument()
  })

  it('renders the tagline', () => {
    render(<HeroSection />)
    expect(screen.getByText(SITE_META.tagline)).toBeInTheDocument()
  })

  it('renders the Install CTA with href="#install"', () => {
    render(<HeroSection />)
    expect(screen.getByRole('link', { name: 'Install' })).toHaveAttribute('href', '#install')
  })

  it('renders the GitHub CTA with correct href', () => {
    render(<HeroSection />)
    expect(screen.getByRole('link', { name: 'GitHub →' })).toHaveAttribute(
      'href',
      SITE_META.repoUrl
    )
  })

  it('renders app icon with correct alt text', () => {
    render(<HeroSection />)
    expect(screen.getByAltText('Umber app icon')).toBeInTheDocument()
  })

  it('renders screenshot with correct alt text', () => {
    render(<HeroSection />)
    expect(screen.getByAltText('Umber terminal screenshot')).toBeInTheDocument()
  })

  it('has aria-labelledby="hero-heading" on the section', () => {
    const { container } = render(<HeroSection />)
    const section = container.querySelector('section')
    expect(section).toHaveAttribute('aria-labelledby', 'hero-heading')
  })

  it('renders the terminal mockup', () => {
    render(<HeroSection />)
    expect(screen.getByLabelText('Umber terminal screenshot')).toBeInTheDocument()
  })
})
