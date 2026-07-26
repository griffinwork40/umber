//
//  Config.swift
//  User configuration and theming.
//
//  Config lives at ~/.config/macterminal/config.json. Every field is optional;
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

    /// Tokyo Night. Chosen as the default because it is legible at small sizes
    /// and does not fight the macOS window chrome.
    static let tokyoNight = Theme(
        background: NSColor.fromHex("#1a1b26")!,
        foreground: NSColor.fromHex("#c0caf5")!,
        cursor: NSColor.fromHex("#c0caf5")!,
        ansi: [
            "#15161e", "#f7768e", "#9ece6a", "#e0af68",
            "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#f7768e", "#9ece6a", "#e0af68",
            "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
        ].map { NSColor.fromHex($0)! }
    )
}

// MARK: - Config file shape

/// On-disk config. All fields optional — see `AppConfig.resolved`.
private struct ConfigFile: Decodable {
    struct FontSpec: Decodable {
        var family: String?
        var size: Double?
    }
    struct ThemeSpec: Decodable {
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

/// Resolved, ready-to-use configuration. Never fails: a missing, malformed, or
/// partially-invalid config file yields defaults for whatever could not be read,
/// and the reasons are surfaced in `warnings` rather than thrown.
struct AppConfig {
    var font: NSFont
    var theme: Theme
    var cursorStyle: CursorStyle
    var scrollback: Int
    var shell: String
    var optionAsMeta: Bool
    /// Human-readable notes about anything in the config that was ignored.
    var warnings: [String] = []

    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/macterminal/config.json")
    }

    /// A default that is intended to look good with zero configuration.
    static func defaults() -> AppConfig {
        AppConfig(
            font: preferredMonoFont(family: nil, size: 13),
            theme: .tokyoNight,
            cursorStyle: .blinkBlock,
            scrollback: 10_000,
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

        // Font
        let size = file.font?.size ?? 13
        config.font = preferredMonoFont(family: file.font?.family, size: size)
        if let requested = file.font?.family, config.font.familyName != requested {
            config.warnings.append("font.family '\(requested)' unavailable — fell back to \(config.font.familyName ?? "system mono")")
        }

        // Theme, field by field so one bad hex does not lose the rest.
        if let t = file.theme {
            var theme = config.theme
            if let raw = t.background {
                if let c = NSColor.fromHex(raw) { theme.background = c }
                else { config.warnings.append("theme.background '\(raw)' is not a hex colour") }
            }
            if let raw = t.foreground {
                if let c = NSColor.fromHex(raw) { theme.foreground = c }
                else { config.warnings.append("theme.foreground '\(raw)' is not a hex colour") }
            }
            if let raw = t.cursor {
                if let c = NSColor.fromHex(raw) { theme.cursor = c }
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
                        theme.ansi = parsed
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

    /// Resolve a monospaced font, preferring the requested family, then SF Mono,
    /// then Menlo, then the system monospaced face. Never returns nil — a
    /// terminal with no font is not a useful failure mode.
    private static func preferredMonoFont(family: String?, size: Double) -> NSFont {
        let candidates = [family, "SF Mono", "Menlo", "Monaco"].compactMap { $0 }
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
