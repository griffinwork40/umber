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

    /// AFK Dark — a preset, selected with `"theme": {"preset": "afk-dark"}`.
    /// It was briefly the default; it is not any more, because SwiftTerm's own
    /// defaults (see `AppConfig.theme == nil`) measurably render better and were
    /// what the Step 0 spike showed. Taken verbatim from the `terminal` block of
    /// `themes/terax/afk-dark.terax-theme` in the agent-afk repo, which is
    /// itself a 1:1 port of that project's Cursor/VS Code and Ghostty themes:
    /// a GitHub-Dark skeleton with the AFK warm-orange accent (#E67E4C) — which
    /// is also the caret here, matching afk's brand tone.
    static let afkDark = Theme(
        background: NSColor.fromHex("#0D1117")!,
        foreground: NSColor.fromHex("#C9D1D9")!,
        cursor: NSColor.fromHex("#E67E4C")!,
        ansi: [
            "#161B22", "#F85149", "#9CB04A", "#E5C07B",
            "#5BA8FF", "#9F7CE0", "#56B5A8", "#C9D1D9",
            "#484F58", "#F85149", "#A8E060", "#E67E4C",
            "#5BA8FF", "#F08AC4", "#5FE0C0", "#ECEFF4",
        ].map { NSColor.fromHex($0)! }
    )

    /// Tokyo Night — the v0.1 default, kept as a preset: `"preset": "tokyo-night"`.
    static let tokyoNight = Theme(
        background: NSColor.fromHex("#1A1B26")!,
        foreground: NSColor.fromHex("#C0CAF5")!,
        cursor: NSColor.fromHex("#C0CAF5")!,
        ansi: [
            "#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
            "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5",
        ].map { NSColor.fromHex($0)! }
    )

    /// Resolve a `"preset"` name. `"classic"` is deliberately absent: it maps to
    /// `nil`, meaning "install nothing and let SwiftTerm's own defaults stand".
    static func preset(named name: String) -> Theme? {
        switch name.lowercased() {
        case "afk-dark", "afkdark": return .afkDark
        case "tokyo-night", "tokyonight": return .tokyoNight
        default: return nil
        }
    }
}
