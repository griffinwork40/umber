import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import TerminalMockup from './TerminalMockup'

describe('TerminalMockup', () => {
  it('renders without throwing', () => {
    render(<TerminalMockup>Hello</TerminalMockup>)
  })

  it('has default aria-label', () => {
    render(<TerminalMockup>content</TerminalMockup>)
    expect(screen.getByLabelText('Terminal mockup')).toBeInTheDocument()
  })

  it('accepts a custom aria-label', () => {
    render(<TerminalMockup aria-label="Umber theme preview">content</TerminalMockup>)
    expect(screen.getByLabelText('Umber theme preview')).toBeInTheDocument()
  })

  it('renders all three traffic-light dots', () => {
    render(<TerminalMockup>content</TerminalMockup>)
    expect(screen.getByTestId('dot-close')).toBeInTheDocument()
    expect(screen.getByTestId('dot-minimize')).toBeInTheDocument()
    expect(screen.getByTestId('dot-maximize')).toBeInTheDocument()
  })

  it('renders children inside the terminal body', () => {
    render(<TerminalMockup>Hello terminal!</TerminalMockup>)
    expect(screen.getByText('Hello terminal!')).toBeInTheDocument()
  })

  it('renders with custom title', () => {
    render(<TerminalMockup title="bash">content</TerminalMockup>)
    expect(screen.getByText('bash')).toBeInTheDocument()
  })

  it('renders complex children', () => {
    render(
      <TerminalMockup>
        <span data-testid="inner">inner content</span>
      </TerminalMockup>
    )
    expect(screen.getByTestId('inner')).toBeInTheDocument()
  })
})
