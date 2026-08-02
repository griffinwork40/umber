//
//  Theme.swift
//  Hex colour parsing, and the AppKit half of a theme.
//
//  The palettes themselves are NOT here any more — they are pure data in
//  `ThemeCatalog.swift`, along with the name resolver and the WCAG luminance
//  formula. This file is what turns that data into live `NSColor` and
//  `SwiftTerm.Color`. The split is forced by verification: this file imports
//  AppKit *and* SwiftTerm, so `swiftc Sources/Umber/Theme.swift` alone exits 1 on
//  `no such module 'SwiftTerm'` and nothing in it has ever been gateable, while
//  `ThemeCatalog.swift` is Foundation-only and `check-light-theme.sh` compiles it.
//  Same decision as `Renderer.swift` / `TerminalPane+Renderer.swift`: the pure
//  decision is checkable, the live action is not, so they live apart.
//
//  Its own file because this is the only *pure value* layer in the config path:
//  `NSColor.fromHex` and the presets have no UserDefaults, no filesystem and
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
    ///
    /// The maths itself is `ThemeCatalog.luminance` and not inlined here, so there is
    /// exactly one implementation of the formula and `check-light-theme.sh` can
    /// compile it. This wrapper is the sRGB conversion and nothing else.
    var relativeLuminance: CGFloat {
        let c = usingColorSpace(.sRGB) ?? self
        return CGFloat(ThemeCatalog.luminance(
            red: Double(c.redComponent),
            green: Double(c.greenComponent),
            blue: Double(c.blueComponent)))
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

    /// Build a live `Theme` from a `ThemeRecord`'s hex strings.
    ///
    /// Force-unwrapped, and safe here in the one way this repo allows: the strings
    /// are compile-time-known literals in `ThemeCatalog`, which is exactly the
    /// "literal hex palettes" carve-out (`AFK.md:152`). What is new is that the
    /// promise is now checked — `check-light-theme.sh` case 1 parses every shipped
    /// hex and asserts every `ansi` array is exactly 16 long before this can ship,
    /// so a typo becomes a red gate rather than a launch crash.
    ///
    /// The `precondition` below is a second, runtime backstop for the same invariant
    /// the gate checks at ship time, not a duplicate concern: `Theme.init` is called
    /// ONLY from `Theme.preset(named:)` and the `afkDark`/`afkLight`/`tokyoNight`
    /// statics below, every one of them resolving a fixed `ThemeCatalog` record — a
    /// user's `theme.ansi` override is validated separately, in `AppConfig.load()`
    /// (`Config.swift`), and lands here as a direct `theme?.ansi = parsed` mutation
    /// AFTER construction, never through this initialiser. So a count violation
    /// reaching this line can only mean `check-light-theme.sh` was not run before a
    /// `ThemeCatalog` edit shipped — a programmer error, not user input, which is
    /// exactly the trap/crash-not-silently-corrupt trade a `precondition` is for
    /// (PR #24 review, item 6).
    init(_ record: ThemeRecord) {
        precondition(record.ansi.count == 16,
            "ThemeRecord '\(record.configName)' has \(record.ansi.count) ANSI colours, need exactly 16 — "
                + "check-light-theme.sh case 1 should have caught this before ship")
        self.background = NSColor.fromHex(record.background)!
        self.foreground = NSColor.fromHex(record.foreground)!
        self.cursor = NSColor.fromHex(record.cursor)!
        self.ansi = record.ansi.map { NSColor.fromHex($0)! }
    }

    /// AFK Dark — `"theme": {"preset": "afk-dark"}`. Briefly the default; it is not
    /// any more, because SwiftTerm's own defaults (see `AppConfig.theme == nil`)
    /// measurably render better and were what the Step 0 spike showed.
    static var afkDark: Theme { Theme(ThemeCatalog.afkDark) }

    /// AFK Light — `"theme": {"preset": "afk-light"}`. The only light preset, and
    /// the one that makes `AppConfig.appearance` (`Config.swift:149`) return `.aqua`,
    /// so the sidebar and titlebar follow the terminal instead of fighting it.
    static var afkLight: Theme { Theme(ThemeCatalog.afkLight) }

    /// Tokyo Night — the v0.1 default, kept as a preset: `"preset": "tokyo-night"`.
    static var tokyoNight: Theme { Theme(ThemeCatalog.tokyoNight) }

    /// Resolve a `"preset"` name. `"classic"` is deliberately absent: it maps to
    /// `nil`, meaning "install nothing and let SwiftTerm's own defaults stand".
    ///
    /// The spellings live in `ThemeCatalog.named(_:)` rather than in a switch here,
    /// so the mapping compiles without AppKit and `check-light-theme.sh` can assert
    /// it — including that `classic` and a typo BOTH stay nil, which is the
    /// distinction `AppConfig.load()` (`Config.swift:215-219`) is built on.
    static func preset(named name: String) -> Theme? {
        ThemeCatalog.named(name).map(Theme.init)
    }
}
