import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import Footer from './Footer'
import { SITE_META } from '@/lib/constants'

describe('Footer', () => {
  it('renders without throwing', () => {
    render(<Footer />)
  })

  it('has footer landmark role (contentinfo)', () => {
    render(<Footer />)
    expect(screen.getByRole('contentinfo')).toBeInTheDocument()
  })

  it('renders app icon with correct alt text', () => {
    render(<Footer />)
    expect(screen.getByAltText('Umber app icon')).toBeInTheDocument()
  })

  it('renders GitHub link with correct href', () => {
    render(<Footer />)
    expect(screen.getByRole('link', { name: 'GitHub repository' })).toHaveAttribute(
      'href',
      SITE_META.repoUrl
    )
  })

  it('renders MIT License link', () => {
    render(<Footer />)
    expect(screen.getByRole('link', { name: 'MIT License' })).toBeInTheDocument()
  })

  it('renders "Built by Griffin Long" text', () => {
    render(<Footer />)
    expect(screen.getByText('Built by Griffin Long')).toBeInTheDocument()
  })

  it('renders the Umber brand name', () => {
    render(<Footer />)
    expect(screen.getByText('Umber')).toBeInTheDocument()
  })
})
