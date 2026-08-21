import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi } from 'vitest'
import Button from './Button'

describe('Button', () => {
  it('renders without throwing', () => {
    render(<Button>Click me</Button>)
  })

  it('renders as a button element by default', () => {
    render(<Button>Click me</Button>)
    expect(screen.getByRole('button', { name: 'Click me' })).toBeInTheDocument()
  })

  it('renders as a link when href is provided', () => {
    render(<Button href="#install">Install</Button>)
    expect(screen.getByRole('link', { name: 'Install' })).toBeInTheDocument()
  })

  it('link has correct href', () => {
    render(<Button href="#install">Install</Button>)
    expect(screen.getByRole('link')).toHaveAttribute('href', '#install')
  })

  it('applies primary variant data attribute', () => {
    render(<Button variant="primary">Primary</Button>)
    expect(screen.getByRole('button')).toHaveAttribute('data-variant', 'primary')
  })

  it('applies secondary variant data attribute', () => {
    render(<Button variant="secondary">Secondary</Button>)
    expect(screen.getByRole('button')).toHaveAttribute('data-variant', 'secondary')
  })

  it('calls onClick handler when clicked', async () => {
    const handleClick = vi.fn()
    render(<Button onClick={handleClick}>Click me</Button>)
    await userEvent.click(screen.getByRole('button'))
    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('responds to Enter key', async () => {
    const handleClick = vi.fn()
    render(<Button onClick={handleClick}>Click me</Button>)
    screen.getByRole('button').focus()
    await userEvent.keyboard('{Enter}')
    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('renders children text', () => {
    render(<Button>GitHub →</Button>)
    expect(screen.getByText('GitHub →')).toBeInTheDocument()
  })

  it('defaults to primary variant', () => {
    render(<Button>Default</Button>)
    expect(screen.getByRole('button')).toHaveAttribute('data-variant', 'primary')
  })
})
