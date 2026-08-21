import type { Metadata } from 'next'
import { SITE_META } from '@/lib/constants'
import './globals.css'

export const metadata: Metadata = {
  title: SITE_META.title,
  description: SITE_META.tagline,
  openGraph: {
    title: SITE_META.title,
    description: SITE_META.tagline,
    type: 'website',
  },
}

interface RootLayoutProps {
  children: React.ReactNode
}

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    <html lang="en">
      <body>
        <a
          href="#main-content"
          className="sr-only"
          style={{
            position: 'absolute',
            top: 'var(--space-2)',
            left: 'var(--space-2)',
            zIndex: 100,
            padding: 'var(--space-2) var(--space-4)',
            backgroundColor: 'var(--color-accent)',
            color: 'var(--color-bg)',
            borderRadius: 'var(--radius-2)',
            fontWeight: 600,
          }}
        >
          Skip to content
        </a>
        {children}
      </body>
    </html>
  )
}
