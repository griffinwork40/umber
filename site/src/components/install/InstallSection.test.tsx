import { render, screen } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import InstallSection from './InstallSection'
import { INSTALL_STEPS, GATEKEEPER_COMMAND } from '@/lib/constants'

describe('InstallSection', () => {
  beforeEach(() => {
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
      writable: true,
      configurable: true,
    })
  })

  it('renders without throwing', () => {
    render(<InstallSection />)
  })

  it('renders h2 heading "Install"', () => {
    render(<InstallSection />)
    expect(screen.getByRole('heading', { level: 2, name: 'Install' })).toBeInTheDocument()
  })

  it('renders "macOS 14+" badge', () => {
    render(<InstallSection />)
    expect(screen.getByText('macOS 14+')).toBeInTheDocument()
  })

  it('renders all 4 install step descriptions', () => {
    render(<InstallSection />)
    INSTALL_STEPS.forEach((step) => {
      expect(screen.getByText(step.description)).toBeInTheDocument()
    })
  })

  it('renders the git clone code snippet', () => {
    render(<InstallSection />)
    expect(
      screen.getByText((content) => content.includes('git clone'))
    ).toBeInTheDocument()
  })

  it('renders the bootstrap-vendor script', () => {
    render(<InstallSection />)
    expect(
      screen.getByText((content) => content.includes('bootstrap-vendor.sh'))
    ).toBeInTheDocument()
  })

  it('renders the make-app-bundle script', () => {
    render(<InstallSection />)
    expect(
      screen.getByText((content) => content.includes('make-app-bundle.sh'))
    ).toBeInTheDocument()
  })

  it('renders the Gatekeeper xattr command', () => {
    render(<InstallSection />)
    expect(
      screen.getByText((content) => content.includes('xattr -dr com.apple.quarantine'))
    ).toBeInTheDocument()
  })

  it('renders the Gatekeeper callout aside', () => {
    render(<InstallSection />)
    expect(screen.getByRole('complementary', { name: 'Gatekeeper note' })).toBeInTheDocument()
  })

  it('has section element with id="install"', () => {
    const { container } = render(<InstallSection />)
    expect(container.querySelector('section#install')).toBeInTheDocument()
  })

  it('renders 5 copy buttons (4 install steps + Gatekeeper)', () => {
    render(<InstallSection />)
    // 4 steps + 1 gatekeeper = 5 copy buttons
    const copyButtons = screen.getAllByRole('button', { name: 'Copy code' })
    expect(copyButtons.length).toBe(5)
  })
})
