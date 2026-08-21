import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect } from 'vitest'
import ThemeShowcase from './ThemeShowcase'
import { THEMES } from '@/lib/constants'

describe('ThemeShowcase', () => {
  it('renders without throwing', () => {
    render(<ThemeShowcase />)
  })

  it('renders all 5 theme names as tabs', () => {
    render(<ThemeShowcase />)
    THEMES.forEach((theme) => {
      expect(screen.getByRole('tab', { name: new RegExp(theme.displayName) })).toBeInTheDocument()
    })
  })

  it('marks umber as the default theme with a badge', () => {
    render(<ThemeShowcase />)
    // The default badge should appear
    expect(screen.getByText('default')).toBeInTheDocument()
  })

  it('umber tab is selected by default', () => {
    render(<ThemeShowcase />)
    expect(screen.getByRole('tab', { name: /Umber/ })).toHaveAttribute('aria-selected', 'true')
  })

  it('non-default themes are not selected initially', () => {
    render(<ThemeShowcase />)
    expect(screen.getByRole('tab', { name: /Tokyo Night/ })).toHaveAttribute('aria-selected', 'false')
  })

  it('clicking a theme tab selects it', async () => {
    render(<ThemeShowcase />)
    await userEvent.click(screen.getByRole('tab', { name: /Tokyo Night/ }))
    expect(screen.getByRole('tab', { name: /Tokyo Night/ })).toHaveAttribute('aria-selected', 'true')
  })

  it('clicking a theme tab deselects umber', async () => {
    render(<ThemeShowcase />)
    await userEvent.click(screen.getByRole('tab', { name: /Tokyo Night/ }))
    expect(screen.getByRole('tab', { name: /Umber/ })).toHaveAttribute('aria-selected', 'false')
  })

  it('renders a tabpanel for the active theme', () => {
    render(<ThemeShowcase />)
    expect(screen.getByRole('tabpanel')).toBeInTheDocument()
  })

  it('has section element with id="themes"', () => {
    const { container } = render(<ThemeShowcase />)
    expect(container.querySelector('section#themes')).toBeInTheDocument()
  })

  it('has h2 heading', () => {
    render(<ThemeShowcase />)
    expect(screen.getByRole('heading', { level: 2, name: 'Themes' })).toBeInTheDocument()
  })
})
