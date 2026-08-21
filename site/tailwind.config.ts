import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        'umber-bg': 'var(--color-bg)',
        'umber-fg': 'var(--color-fg)',
        'umber-cursor': 'var(--color-cursor)',
        'umber-selection': 'var(--color-selection)',
        'umber-accent': 'var(--color-accent)',
        'umber-surface': 'var(--color-surface)',
        'umber-muted': 'var(--color-muted)',
        'umber-border': 'var(--color-border)',
        'umber-ansi-green': 'var(--color-ansi-green)',
        'umber-ansi-blue': 'var(--color-ansi-blue)',
      },
      fontFamily: {
        mono: 'var(--font-mono)',
        sans: 'var(--font-sans)',
      },
      spacing: {
        '1': 'var(--space-1)',
        '2': 'var(--space-2)',
        '3': 'var(--space-3)',
        '4': 'var(--space-4)',
        '5': 'var(--space-5)',
        '6': 'var(--space-6)',
        '7': 'var(--space-7)',
        '8': 'var(--space-8)',
        '9': 'var(--space-9)',
        '10': 'var(--space-10)',
        '11': 'var(--space-11)',
        '12': 'var(--space-12)',
      },
      borderRadius: {
        'sm': 'var(--radius-1)',
        DEFAULT: 'var(--radius-2)',
        'md': 'var(--radius-3)',
        'lg': 'var(--radius-4)',
      },
      transitionDuration: {
        DEFAULT: 'var(--motion-duration)',
      },
    },
  },
  plugins: [],
}

export default config
