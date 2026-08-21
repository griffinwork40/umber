import { render, screen, within } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import KeymapSection from './KeymapSection'

describe('KeymapSection', () => {
  it('renders without throwing', () => {
    render(<KeymapSection />)
  })

  it('renders the h2 heading', () => {
    render(<KeymapSection />)
    expect(screen.getByRole('heading', { level: 2, name: 'Keyboard Shortcuts' })).toBeInTheDocument()
  })

  it('renders multiple tables (one per group)', () => {
    render(<KeymapSection />)
    const tables = screen.getAllByRole('table')
    expect(tables.length).toBeGreaterThanOrEqual(4)
  })

  it('each table has th elements with scope="col"', () => {
    render(<KeymapSection />)
    const headers = screen.getAllByRole('columnheader')
    expect(headers.length).toBeGreaterThan(0)
    headers.forEach((th) => {
      expect(th).toHaveAttribute('scope', 'col')
    })
  })

  it('renders ⌘N shortcut', () => {
    render(<KeymapSection />)
    expect(screen.getByText('⌘N')).toBeInTheDocument()
  })

  it('renders ⌘T shortcut', () => {
    render(<KeymapSection />)
    expect(screen.getByText('⌘T')).toBeInTheDocument()
  })

  it('renders ⌘B shortcut', () => {
    render(<KeymapSection />)
    expect(screen.getByText('⌘B')).toBeInTheDocument()
  })

  it('renders ⌘⌫ shortcut', () => {
    render(<KeymapSection />)
    expect(screen.getByText('⌘⌫')).toBeInTheDocument()
  })

  it('renders group names as headings in the UI', () => {
    render(<KeymapSection />)
    expect(screen.getByText('Spaces & Documents')).toBeInTheDocument()
    expect(screen.getByText('View')).toBeInTheDocument()
    expect(screen.getByText('Font Size')).toBeInTheDocument()
    expect(screen.getByText('Line Editing')).toBeInTheDocument()
  })

  it('renders kbd elements for shortcuts', () => {
    const { container } = render(<KeymapSection />)
    const kbdElements = container.querySelectorAll('kbd')
    expect(kbdElements.length).toBeGreaterThan(0)
  })

  it('has a section element with id="keymap"', () => {
    const { container } = render(<KeymapSection />)
    expect(container.querySelector('section#keymap')).toBeInTheDocument()
  })
})
