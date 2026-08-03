//
//  Theme.swift
//  Hex colour parsing and the shipped `Theme` presets.
//
//  Its own file because this is the only *pure value* layer in the config path:
//  `NSColor.fromHex` and the two presets have no UserDefaults, no filesystem and
//  no AppConfig behind them, so they are the one part of theming that can be read
//  and judged without holding the loader in context. `relativeLuminance` and
//  `asSwiftTermColor` live here rather than next to their callers because they are
//  colour-space conversions on `NSColor` with two consumers each, across files:
//  `TerminalPane.apply(config:)` installs the palette and logs bg luminance
//  (`TerminalPane.swift:86,111`), while `AppConfig.appearance` derives the window's
//  light/dark chrome from it (`Config.swift`, "Derived chrome").
//

import AppKit
import SwiftTerm

// MARK: - Hex colors

extension NSColor {
    /// Parse `#rrggbb` / `rrggbb` (and the 3-digit shorthand). Returns nil on
    /// anything unparseable so a typo in config degrades to the default rather
    /// than crashing the terminal.
    static func fromHex(_ raw: String) -> NSColor? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    /// The inverse of `fromHex`, as `#rrggbb`.
    ///
    /// Exists because libghostty's configuration takes every colour as a **string** —
    /// `TerminalConfigCommand.background(String)`, `.cursorColor(String)`,
    /// `.palette(index:color:)` — rather than as a typed colour
    /// (`Configuration/TerminalConfiguration.swift:22-34`). SwiftTerm takes a typed
    /// `SwiftTerm.Color` instead, which is what `asSwiftTermColor` below is for; the two
    /// engines want the same `Theme` in two different shapes, and both conversions belong
    /// here beside the parsing rather than in whichever pane needed one first.
    ///
    /// Converted to sRGB first for the same reason the other two conversions do it: the
    /// no-theme fallback is `NSColor.black`, which lives in a generic grey colour space
    /// where `.redComponent` traps rather than returning 0.
    ///
    /// Emitted WITH the leading `#`. libghostty's own shipped presets are inconsistent
    /// about it (`TerminalTheme+Defaults.swift` mixes `"F7F7F7"` and `"#000000"`), so the
    /// prefixed form is chosen because it is the one both spellings in that file agree is
    /// accepted, and it round-trips through `fromHex` above.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// WCAG 2.1 relative luminance, 0…1. Used to decide whether the window's
    /// system chrome (sidebar, titlebar, scrollers) should render dark or light.
    ///
    /// Converted to sRGB first for the same reason `asSwiftTermColor` does it: the
    /// no-theme fallback is `NSColor.black`, which lives in a generic *grey* colour
    /// space, and asking a grey colour for `.redComponent` traps rather than
    /// returning 0.
    var relativeLuminance: CGFloat {
        let c = usingColorSpace(.sRGB) ?? self
        // Gamma-expand each channel before weighting — luminance is defined on
        // linear light, and skipping this misjudges mid-tones badly.
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent)
            + 0.7152 * linear(c.greenComponent)
            + 0.0722 * linear(c.blueComponent)
    }

    /// SwiftTerm's palette type wants 16-bit components.
    var asSwiftTermColor: SwiftTerm.Color {
        let c = usingColorSpace(.sRGB) ?? self
        return SwiftTerm.Color(
            red: UInt16(c.redComponent * 65535),
            green: UInt16(c.greenComponent * 65535),
            blue: UInt16(c.blueComponent * 65535)
        )
    }
}

// MARK: - Theme

/// A 16-colour ANSI palette plus background/foreground/cursor.
struct Theme {
    var background: NSColor
    var foreground: NSColor
    var cursor: NSColor
    /// Exactly 16 entries: 8 normal then 8 bright. SwiftTerm's `installColors`
    /// silently does nothing if the array is not 16 long, so this is validated
    /// at construction rather than trusted.
    var ansi: [NSColor]

    /// Build from a `ThemePalette` — the pure, Foundation-only hex values in
    /// `ThemeValues.swift`.
    ///
    /// The hex used to live *here*, inline, which meant the palettes sat behind this
    /// file's `import AppKit` and `import SwiftTerm` and were therefore unreachable by
    /// any check (`check-theme-contrast.sh` compiles Foundation-only files standalone —
    /// the same argument `GitStatus+Presentation.swift` makes about its own narrowing).
    /// Now this file does one thing: bridge measured values into the two engines' colour
    /// types. The force-unwraps are safe by the same rule as the rest of this file —
    /// compile-time-known literals — and `check-theme-contrast.sh` parses every one of
    /// them independently, so a typo fails the gate rather than trapping at launch.
    init(_ palette: ThemePalette) {
        background = NSColor.fromHex(palette.background)!
        foreground = NSColor.fromHex(palette.foreground)!
        cursor = NSColor.fromHex(palette.cursor)!
        ansi = palette.ansi.map { NSColor.fromHex($0)! }
    }

    /// **Umber** — designed for this app and measured, not transcribed. Selected with
    /// `"theme": {"preset": "umber"}`. Rationale and the numbers behind it are on
    /// `ThemePalette.umber`; the derivation is in `.afk/research/theme-design-2026-08-03/`.
    static let umber = Theme(.umber)

    /// AFK Dark — `"preset": "afk-dark"`. A verbatim port; see `ThemePalette.afkDark`.
    static let afkDark = Theme(.afkDark)

    /// Tokyo Night — the v0.1 default, kept as a preset: `"preset": "tokyo-night"`.
    static let tokyoNight = Theme(.tokyoNight)

    /// Resolve a `"preset"` name. `"classic"` is deliberately absent: it maps to
    /// `nil`, meaning "install nothing and let SwiftTerm's own defaults stand".
    ///
    /// Every name accepted here must correspond to a palette in `ThemePalette.all`, and
    /// vice versa — `check-theme-contrast.sh` asserts the two cannot drift, because a
    /// preset that exists but is unreachable from config is invisible, and a name that
    /// resolves to nothing falls back to a *different* theme with only a warning.
    static func preset(named name: String) -> Theme? {
        switch name.lowercased() {
        case "umber": return .umber
        case "afk-dark", "afkdark": return .afkDark
        case "tokyo-night", "tokyonight": return .tokyoNight
        default: return nil
        }
    }
}
