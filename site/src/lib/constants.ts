/**
 * Site-wide constants for the Umber landing page.
 *
 * Hex colour values are drawn verbatim from ThemeValues.swift — the canonical source.
 * This is the ONLY file on the site that may contain hex values; all component files
 * must reference tokens from tokens.css or data from this file.
 */

export const SITE_META = {
  title: 'Umber',
  tagline: 'A native macOS terminal built for agent-afk',
  version: 'v0.1',
  repoUrl: 'https://github.com/griffinwork40/umber',
} as const

export interface Feature {
  title: string
  description: string
  icon: string
}

export const FEATURES: Feature[] = [
  {
    title: 'Native macOS App',
    description:
      'Real .app bundle, ad-hoc signed. Your login shell ($SHELL -l) with your real PATH and rc files.',
    icon: 'apple',
  },
  {
    title: 'Two-Level Tabs',
    description:
      'Spaces are native macOS window tabs (⌘N). Documents live in a hand-rolled strip inside each Space (⌘T, ⌘1–⌘9).',
    icon: 'tabs',
  },
  {
    title: 'Sidebar File Tree',
    description:
      'Lazy NSOutlineView rooted at the Space (⌘B). Double-clicking a file types its quoted path into the terminal.',
    icon: 'sidebar',
  },
  {
    title: 'Umber Palette',
    description:
      'Designed — not ported. Warm umber-black base, legible dim text (APCA Lc 51.5), and bright colours that are actually brighter.',
    icon: 'palette',
  },
  {
    title: 'Dual Emulator Cores',
    description:
      'SwiftTerm (vendored, patched) or libghostty. Switch with a config line; both cores can run side by side.',
    icon: 'cpu',
  },
  {
    title: 'Shell Integration',
    description:
      'OSC 7 working-directory tracking and OSC 133 command boundaries via the ghostty engine. Config reloads live (⌘R).',
    icon: 'shell',
  },
]

export interface InstallStep {
  step: number
  description: string
  code: string
  language: string
}

export const INSTALL_STEPS: InstallStep[] = [
  {
    step: 1,
    description: 'Clone the repository',
    code: 'git clone https://github.com/griffinwork40/umber.git',
    language: 'bash',
  },
  {
    step: 2,
    description: 'Enter the app directory',
    code: 'cd umber/app',
    language: 'bash',
  },
  {
    step: 3,
    description: 'Bootstrap the vendored SwiftTerm dependency (clones and applies all 6 patches)',
    code: './Scripts/bootstrap-vendor.sh',
    language: 'bash',
  },
  {
    step: 4,
    description: 'Build a release bundle and launch',
    code: './Scripts/make-app-bundle.sh release\nopen build/Umber.app',
    language: 'bash',
  },
]

export const GATEKEEPER_COMMAND =
  'xattr -dr com.apple.quarantine build/Umber.app'

export interface KeymapEntry {
  shortcut: string
  description: string
}

export interface KeymapGroup {
  group: string
  entries: KeymapEntry[]
}

export const KEYMAP: KeymapGroup[] = [
  {
    group: 'Spaces & Documents',
    entries: [
      { shortcut: '⌘N', description: 'New Space (window tab)' },
      { shortcut: '⌘T', description: 'New document in current Space' },
      { shortcut: '⌘⇧[', description: 'Previous Space' },
      { shortcut: '⌘⇧]', description: 'Next Space' },
      { shortcut: '⌘⌥←', description: 'Previous document' },
      { shortcut: '⌘⌥→', description: 'Next document' },
      { shortcut: '⌘1–⌘9', description: 'Jump to document by index' },
    ],
  },
  {
    group: 'View',
    entries: [
      { shortcut: '⌘B', description: 'Toggle sidebar' },
      { shortcut: '⌘F', description: 'Full screen' },
      { shortcut: '⌘R', description: 'Reload config' },
      { shortcut: '⌘,', description: 'Open Settings (writes starter config)' },
    ],
  },
  {
    group: 'Font Size',
    entries: [
      { shortcut: '⌘+', description: 'Zoom in (persists across tabs and relaunches)' },
      { shortcut: '⌘-', description: 'Zoom out' },
      { shortcut: '⌘0', description: 'Reset zoom to config font.size' },
    ],
  },
  {
    group: 'Line Editing',
    entries: [
      { shortcut: '⌘⌫', description: 'Delete to start of line (^U)' },
      { shortcut: '⌘⌦', description: 'Delete to end of line (^K)' },
      { shortcut: '⌘←', description: 'Jump to start of line (^A)' },
      { shortcut: '⌘→', description: 'Jump to end of line (^E)' },
      { shortcut: '⌥←', description: 'Jump back one word' },
      { shortcut: '⌥→', description: 'Jump forward one word' },
    ],
  },
]

export interface ThemePalette {
  name: string
  displayName: string
  background: string
  foreground: string
  cursor: string
  selection: string
  ansi: string[]
  isDefault: boolean
}

/**
 * Five theme palettes, hex values verbatim from ThemeValues.swift.
 * This is the canonical source on the site for all theme colours.
 */
export const THEMES: ThemePalette[] = [
  {
    name: 'umber',
    displayName: 'Umber',
    background: '#19120D',
    foreground: '#E5DFD6',
    cursor: '#FF9B5A',
    selection: '#453021',
    ansi: [
      '#342C26', '#EF7F74', '#8AE49E', '#D7AA32',
      '#739EF0', '#FFACE9', '#42CBC8', '#D3CDC5',
      '#AAA19B', '#FDAAA0', '#B4FCC3', '#F7D179',
      '#9DBEFC', '#FFD2F2', '#80E5E2', '#F9F6F2',
    ],
    isDefault: true,
  },
  {
    name: 'classic-repaired',
    displayName: 'Classic Repaired',
    background: '#000000',
    foreground: '#8A8A8A',
    cursor: '#A1A8FD',
    selection: '#262952',
    ansi: [
      '#000000', '#C23621', '#25BC24', '#ADAD27',
      '#818AFC', '#D338D3', '#33BBC8', '#CBCCCD',
      '#818383', '#FC391F', '#31E722', '#EAEC23',
      '#A1A8FD', '#F935F8', '#14F0F0', '#FFFFFF',
    ],
    isDefault: false,
  },
  {
    name: 'afk-dark',
    displayName: 'AFK Dark',
    background: '#0D1117',
    foreground: '#C9D1D9',
    cursor: '#E67E4C',
    selection: '#264F78',
    ansi: [
      '#161B22', '#F85149', '#9CB04A', '#E5C07B',
      '#5BA8FF', '#9F7CE0', '#56B5A8', '#C9D1D9',
      '#484F58', '#F85149', '#A8E060', '#E67E4C',
      '#5BA8FF', '#F08AC4', '#5FE0C0', '#ECEFF4',
    ],
    isDefault: false,
  },
  {
    name: 'afk-light',
    displayName: 'AFK Light',
    background: '#FFFFFF',
    foreground: '#1F2328',
    cursor: '#0969DA',
    selection: '#B6E3FF',
    ansi: [
      '#24292F', '#CF222E', '#116329', '#4D2D00',
      '#0969DA', '#8250DF', '#1B7C83', '#6E7781',
      '#57606A', '#A40E26', '#1A7F37', '#633C01',
      '#218BFF', '#A475F9', '#3192AA', '#8C959F',
    ],
    isDefault: false,
  },
  {
    name: 'tokyo-night',
    displayName: 'Tokyo Night',
    background: '#1A1B26',
    foreground: '#C0CAF5',
    cursor: '#C0CAF5',
    selection: '#283457',
    ansi: [
      '#15161E', '#F7768E', '#9ECE6A', '#E0AF68',
      '#7AA2F7', '#BB9AF7', '#7DCFFF', '#A9B1D6',
      '#414868', '#F7768E', '#9ECE6A', '#E0AF68',
      '#7AA2F7', '#BB9AF7', '#7DCFFF', '#C0CAF5',
    ],
    isDefault: false,
  },
]
