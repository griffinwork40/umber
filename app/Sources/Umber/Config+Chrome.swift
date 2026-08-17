//
//  Config+Chrome.swift
//  Chrome derived from the resolved theme: the colour the terminal actually
//  paints, its AppKit-text counterpart, and the system appearance the window
//  adopts so the sidebar matches the terminal.
//
//  Split out of Config.swift when that file crossed the 350-line ceiling
//  (2026-08-17, after the editor-config and mouseReporting fields landed). These
//  three are one concern — "given a resolved theme, or none, what does the
//  surrounding chrome paint" — and the loader (`defaults()` / `load()`) never
//  touches them, so they move cleanly. Kept as an extension on `AppConfig` so
//  every call site is unchanged: consumers still read `config.effectiveBackground`,
//  `.effectiveForeground` and `.appearance`. Each property keeps the doc comment
//  that carries its rationale — the stale-ANSI correction, the sidebar-appearance
//  derivation, and the one call site that reads `WCAG.lightChromeCutoff`.
//

import AppKit

extension AppConfig {
    /// The background the terminal will *actually* paint, theme or no theme.
    ///
    /// `theme == nil` means "install nothing and let SwiftTerm's own defaults
    /// stand", and those default to black (`Colors.swift:37` defaultBackground).
    /// Every piece of chrome that has to agree with the terminal was open-coding
    /// `theme?.background ?? .black`; four copies of that fallback is four places
    /// for the chrome and the content to drift apart.
    var effectiveBackground: NSColor { theme?.background ?? .black }

    /// As `effectiveBackground`, for AppKit text. SwiftTerm's actual default is `#8A8A8A`,
    /// not white (`SwiftTerm/Colors.swift:36`); a real theme normally follows its terminal
    /// foreground, with Classic Repaired's explicit readable-chrome exception.
    var effectiveForeground: NSColor { theme?.chromeForeground ?? NSColor.fromHex("#8A8A8A")! }

    /// The system appearance the window should adopt, derived from the theme.
    ///
    /// This is the setting that makes the *sidebar* match the terminal. The file
    /// tree is deliberately built out of system parts — `NSSplitViewItem(sidebar
    /// WithViewController:)` and `outlineView.style = .sourceList` (plan §12.4
    /// item 5) — so its material, its selection pill, its label colours and its
    /// scroller knob are all chosen by AppKit from the effective `NSAppearance`.
    /// Nothing used to set one, so they followed *System Settings*: on a Mac in
    /// Light Mode that put a light-grey tree with black text and full-colour
    /// Finder icons directly against a black terminal.
    ///
    /// Derived rather than hardcoded to `.darkAqua`: the theme is user hex, so a
    /// light background is expressible today even though no preset ships one, and
    /// pinning dark would simply invert the same bug. Deriving it also means the
    /// vibrant sidebar material samples `window.backgroundColor` — already the
    /// theme background — so the tree picks up the theme's tint for free, without
    /// hand-painting a single row.
    ///
    /// The comparison is spelled out as `Double` rather than leaning on
    /// CGFloat/Double bridging: `relativeLuminance` is `CGFloat` (it feeds AppKit
    /// APIs) and `WCAG.lightChromeCutoff` is `Double` (that file is
    /// Foundation-only and cannot spell `CGFloat`), and an implicit conversion at
    /// the comparison site would leave the two types silently doing the coercion
    /// instead of the reader seeing it happen. `ThemeContrast.swift`'s doc comment
    /// carries the WCAG rationale for the constant itself — this is the one
    /// call site that reads it, not a second definition of it (PR #24 review, item 1).
    var appearance: NSAppearance? {
        NSAppearance(named: Double(effectiveBackground.relativeLuminance) > WCAG.lightChromeCutoff ? .aqua : .darkAqua)
    }
}
