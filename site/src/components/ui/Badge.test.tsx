import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import Badge from './Badge'

describe('Badge', () => {
  it('renders without throwing', () => {
    render(<Badge>macOS 14+</Badge>)
  })

  it('renders children content', () => {
    render(<Badge>macOS 14+</Badge>)
    expect(screen.getByText('macOS 14+')).toBeInTheDocument()
  })

  it('renders as a span element', () => {
    const { container } = render(<Badge>test</Badge>)
    expect(container.querySelector('span')).toBeInTheDocument()
  })

  it('applies className when provided', () => {
    const { container } = render(<Badge className="custom-class">test</Badge>)
    expect(container.querySelector('.custom-class')).toBeInTheDocument()
  })
})
