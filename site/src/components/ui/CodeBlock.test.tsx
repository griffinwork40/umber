import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import CodeBlock from './CodeBlock'

describe('CodeBlock', () => {
  beforeEach(() => {
    // Mock clipboard API
    Object.defineProperty(navigator, 'clipboard', {
      value: {
        writeText: vi.fn().mockResolvedValue(undefined),
      },
      writable: true,
      configurable: true,
    })
  })

  it('renders without throwing', () => {
    render(<CodeBlock code="git clone https://example.com" />)
  })

  it('displays the code content', () => {
    render(<CodeBlock code="git clone https://example.com" />)
    expect(screen.getByText('git clone https://example.com')).toBeInTheDocument()
  })

  it('renders a copy button with accessible label', () => {
    render(<CodeBlock code="pnpm install" />)
    expect(screen.getByRole('button', { name: 'Copy code' })).toBeInTheDocument()
  })

  it('calls clipboard writeText when copy button is clicked', async () => {
    render(<CodeBlock code="pnpm install" />)
    await userEvent.click(screen.getByRole('button', { name: 'Copy code' }))
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('pnpm install')
  })

  it('shows Copied! text after clicking copy', async () => {
    render(<CodeBlock code="pnpm install" />)
    await userEvent.click(screen.getByRole('button', { name: 'Copy code' }))
    expect(screen.getByText('Copied!')).toBeInTheDocument()
  })

  it('triggers copy on Space key', async () => {
    render(<CodeBlock code="npm test" />)
    screen.getByRole('button', { name: 'Copy code' }).focus()
    await userEvent.keyboard(' ')
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('npm test')
  })

  it('triggers copy on Enter key', async () => {
    render(<CodeBlock code="npm test" />)
    screen.getByRole('button', { name: 'Copy code' }).focus()
    await userEvent.keyboard('{Enter}')
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('npm test')
  })

  it('applies language class to code element', () => {
    const { container } = render(<CodeBlock code="echo hello" language="bash" />)
    expect(container.querySelector('.language-bash')).toBeInTheDocument()
  })

  it('renders a kbd element when variant="kbd"', () => {
    const { container } = render(<CodeBlock variant="kbd" code="⌘T" />)
    const kbd = container.querySelector('kbd')
    expect(kbd).toBeInTheDocument()
    expect(kbd).toHaveTextContent('⌘T')
  })

  it('does not render a copy button when variant="kbd"', () => {
    render(<CodeBlock variant="kbd" code="⌘T" />)
    expect(screen.queryByRole('button', { name: 'Copy code' })).not.toBeInTheDocument()
  })

  it('renders multiline code correctly', () => {
    const multiline = './Scripts/make-app-bundle.sh release\nopen build/Umber.app'
    render(<CodeBlock code={multiline} />)
    // Use a function matcher to handle whitespace normalization by RTL
    expect(
      screen.getByText((content) => content.includes('./Scripts/make-app-bundle.sh release'))
    ).toBeInTheDocument()
  })
})
