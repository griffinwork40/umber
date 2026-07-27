//
//  Config.swift
//  User configuration and theming.
//
//  Config lives at ~/.config/umber/config.json. Every field is optional;
//  anything absent falls back to a default that is meant to already look good,
//  because the point of this app is that it is beautiful before you configure it.
//
//  Deliberately plain JSON rather than a bespoke format: it is diffable,
//  machine-editable, and needs no parser of its own.
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

// MARK: - Config file shape

/// On-disk config. All fields optional — see `AppConfig.resolved`.
private struct ConfigFile: Decodable {
    struct FontSpec: Decodable {
        var family: String?
        var size: Double?
    }
    struct ThemeSpec: Decodable {
        /// "afk-dark" | "tokyo-night" | "classic". Omitted with other fields
        /// present means "afk-dark, with my overrides on top".
        var preset: String?
        var background: String?
        var foreground: String?
        var cursor: String?
        var ansi: [String]?
    }
    var font: FontSpec?
    var theme: ThemeSpec?
    var cursor: String?
    var scrollback: Int?
    var shell: String?
    var optionAsMeta: Bool?
}

// MARK: - Font zoom

/// The live ⌘+ / ⌘− zoom level, app-wide and persisted.
///
/// Deliberately **not** written back into `config.json`: that file is
/// hand-edited and carries the user's own comments, so an app that rewrote it
/// would clobber them. `UserDefaults` is the idiomatic home for transient UI
/// state of exactly this kind.
///
/// `nil` means "no zoom — use the configured size", which is what ⌘0 restores.
/// It is app-wide rather than per-pane because the alternative is what v0.1
/// shipped: zooming in one tab left every other tab, every tab opened
/// afterwards, and every subsequent launch back at the configured size.
enum FontZoom {
    private static let key = "Umber.fontSizeOverride"

    static var override: CGFloat? {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            return stored > 0 ? CGFloat(stored) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Double(newValue), forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// Resolved, ready-to-use configuration. Never fails: a missing, malformed, or
/// partially-invalid config file yields defaults for whatever could not be read,
/// and the reasons are surfaced in `warnings` rather than thrown.
struct AppConfig {
    var font: NSFont
    /// `nil` means "do not install any colours" — SwiftTerm's own defaults stand.
    /// That is the default, and it is not laziness: installing a background or
    /// foreground makes SwiftTerm regenerate ANSI indices 16–255 by interpolating
    /// them out of your bg/fg (`Terminal.swift:513-542` → `rebuildAnsiPalette`),
    /// so a custom theme silently replaces the standard 256-colour cube with
    /// synthesised approximations. See `TerminalPane.apply(config:)`.
    var theme: Theme?
    var cursorStyle: CursorStyle
    var scrollback: Int
    var shell: String
    var optionAsMeta: Bool
    /// Human-readable notes about anything in the config that was ignored.
    var warnings: [String] = []

    /// 14pt, not 13. The default has to be comfortable on a Retina display
    /// without touching a config file, and 13 read as cramped in use. Both
    /// `font.size` and ⌘+ / ⌘− override this.
    static let defaultFontSize: Double = 14

    /// Bounds for both `font.size` and the live zoom. Below ~6pt the glyphs stop
    /// being legible; above ~48 a standard window holds too few columns for a TUI
    /// to lay out. Shared so the config path and the zoom path cannot disagree.
    static let minFontSize: Double = 6
    static let maxFontSize: Double = 48

    // MARK: - Derived chrome

    /// The background the terminal will *actually* paint, theme or no theme.
    ///
    /// `theme == nil` means "install nothing and let SwiftTerm's own defaults
    /// stand", and those default to black (`Colors.swift:37` defaultBackground).
    /// Every piece of chrome that has to agree with the terminal was open-coding
    /// `theme?.background ?? .black`; four copies of that fallback is four places
    /// for the chrome and the content to drift apart.
    var effectiveBackground: NSColor { theme?.background ?? .black }

    /// As `effectiveBackground`, for text. SwiftTerm's default foreground is white.
    var effectiveForeground: NSColor { theme?.foreground ?? .white }

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
    var appearance: NSAppearance? {
        NSAppearance(named: effectiveBackground.relativeLuminance > Self.lightChromeCutoff ? .aqua : .darkAqua)
    }

    /// WCAG 2.1's contrast crossover: above this luminance a background reads
    /// better with black text than white, which is exactly the question
    /// "should this window's chrome be light or dark?" asks. All three shipped
    /// themes sit far below it (afk-dark ≈ 0.008, tokyo-night ≈ 0.012, black = 0),
    /// so this only starts discriminating once someone configures a light theme.
    static let lightChromeCutoff: CGFloat = 0.179

    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/umber/config.json")
    }

    /// A default that is intended to look good with zero configuration.
    static func defaults() -> AppConfig {
        AppConfig(
            font: preferredMonoFont(family: nil, size: defaultFontSize).font,
            theme: nil,
            cursorStyle: .blinkBlock,
            // 1,000 (iTerm2's default), not 10,000. SwiftTerm sizes the scrollbar
            // thumb as `max(rows / lines.count, 0.01)`
            // (`AppleTerminalView.swift:2002`), so past ~3,500 lines the thumb
            // hits the 1% floor and degenerates into a fixed hairline that no
            // longer tracks position. `Buffer.resize` also walks every line three
            // times per resize, so a 10k buffer made window resizing ~20x more
            // expensive than it needed to be. Raise it if you want; know the cost.
            scrollback: 1_000,
            shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            optionAsMeta: true
        )
    }

    /// Resolve the user's config, falling back field-by-field.
    static func load() -> AppConfig {
        var config = defaults()
        let url = configURL
        guard let data = try? Data(contentsOf: url) else {
            return config  // No config file is the normal case, not an error.
        }
        guard let file = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            config.warnings.append("\(url.path): not valid JSON — using defaults")
            return config
        }

        // Font. An out-of-range size is reported rather than silently clamped:
        // every other field in this file explains itself when it is ignored, and
        // a size that quietly did nothing is precisely the failure that makes a
        // configurable setting feel unconfigurable.
        var size = defaultFontSize
        if let requested = file.font?.size {
            if requested >= minFontSize && requested <= maxFontSize {
                size = requested
            } else {
                config.warnings.append(
                    "font.size \(requested) is outside \(Int(minFontSize))–\(Int(maxFontSize)) — using \(Int(size))")
            }
        }
        let resolvedFont = preferredMonoFont(family: file.font?.family, size: size)
        config.font = resolvedFont.font
        if let warning = resolvedFont.warning { config.warnings.append(warning) }

        // Theme, field by field so one bad hex does not lose the rest.
        if let t = file.theme {
            // Pick the base. "classic" (and only "classic") stays nil, which is
            // the one setting that leaves SwiftTerm's defaults genuinely untouched.
            let wantsClassic = t.preset?.lowercased() == "classic"
            var theme: Theme? = wantsClassic ? nil : (t.preset.flatMap(Theme.preset(named:)) ?? .afkDark)
            if let raw = t.preset, !wantsClassic, Theme.preset(named: raw) == nil {
                config.warnings.append("theme.preset '\(raw)' unrecognised — using afk-dark")
            }
            // Any explicit colour needs a full palette to sit on; classic + an
            // override cannot stay nil, so promote it to afk-dark first.
            let hasOverride = t.background != nil || t.foreground != nil || t.cursor != nil || t.ansi != nil
            if theme == nil && hasOverride {
                config.warnings.append("theme.preset 'classic' cannot take colour overrides — using afk-dark as the base")
                theme = .afkDark
            }
            // Optional-chained: if `theme` is still nil there are no overrides to
            // apply (we just promoted the only case where both could be true).
            if let raw = t.background {
                if let c = NSColor.fromHex(raw) { theme?.background = c }
                else { config.warnings.append("theme.background '\(raw)' is not a hex colour") }
            }
            if let raw = t.foreground {
                if let c = NSColor.fromHex(raw) { theme?.foreground = c }
                else { config.warnings.append("theme.foreground '\(raw)' is not a hex colour") }
            }
            if let raw = t.cursor {
                if let c = NSColor.fromHex(raw) { theme?.cursor = c }
                else { config.warnings.append("theme.cursor '\(raw)' is not a hex colour") }
            }
            if let rawList = t.ansi {
                // installColors is a no-op unless there are exactly 16, so reject
                // a wrong-sized palette loudly instead of silently ignoring it.
                if rawList.count != 16 {
                    config.warnings.append("theme.ansi needs exactly 16 colours, got \(rawList.count) — keeping default palette")
                } else {
                    let parsed = rawList.compactMap { NSColor.fromHex($0) }
                    if parsed.count == 16 {
                        theme?.ansi = parsed
                    } else {
                        config.warnings.append("theme.ansi contains \(16 - parsed.count) unparseable colour(s) — keeping default palette")
                    }
                }
            }
            config.theme = theme
        }

        if let raw = file.cursor {
            switch raw.lowercased() {
            case "block": config.cursorStyle = .blinkBlock
            case "block-steady", "steady-block": config.cursorStyle = .steadyBlock
            case "bar", "underline-bar": config.cursorStyle = .blinkBar
            case "bar-steady", "steady-bar": config.cursorStyle = .steadyBar
            case "underline": config.cursorStyle = .blinkUnderline
            case "underline-steady", "steady-underline": config.cursorStyle = .steadyUnderline
            default: config.warnings.append("cursor '\(raw)' unrecognised — using block")
            }
        }

        if let sb = file.scrollback {
            if sb >= 0 { config.scrollback = sb }
            else { config.warnings.append("scrollback must be >= 0 — using \(config.scrollback)") }
        }
        if let sh = file.shell {
            if FileManager.default.isExecutableFile(atPath: sh) { config.shell = sh }
            else { config.warnings.append("shell '\(sh)' is not executable — using \(config.shell)") }
        }
        if let meta = file.optionAsMeta { config.optionAsMeta = meta }

        return config
    }

    /// Names people write in a config when they mean the system monospaced face.
    /// None of these resolve through `NSFont(name:)`, so they must be mapped.
    private static let systemMonoAliases: Set<String> = [
        "sf mono", "sfmono", "sfmono-regular", "sf mono regular", "system", "system mono",
    ]

    /// Resolve a monospaced font, reporting a human-readable problem when a
    /// requested family cannot be honoured. Never returns nil — a terminal with
    /// no font is not a useful failure mode.
    ///
    /// With nothing requested this returns the **system monospaced face**, which
    /// is SF Mono and is also exactly what SwiftTerm's own `FontSet.defaultFont`
    /// uses. It is deliberately NOT reached via `NSFont(name: "SF Mono")`: that
    /// call returns nil, because SF Mono is not registered under that name (nor
    /// under "SFMono-Regular"). v0.1 asked for it by name, silently got Menlo as
    /// the next candidate, and therefore rendered visibly worse than the Step 0
    /// spike — which set no font at all and so kept SwiftTerm's default. The
    /// system-mono call used to sit at the BOTTOM of this function, unreachable,
    /// because Menlo always resolves first.
    private static func preferredMonoFont(family: String?, size: Double) -> (font: NSFont, warning: String?) {
        let systemMono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        guard let family, !systemMonoAliases.contains(family.lowercased()) else {
            return (systemMono, nil)
        }
        if let f = NSFont(name: family, size: size) { return (f, nil) }
        return (systemMono, "font.family '\(family)' unavailable — using the system monospaced face")
    }
}
