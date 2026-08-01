//
//  Config.swift
//  The on-disk config shape and the resolved `AppConfig` it loads into.
//
//  Config lives at ~/.config/umber/config.json. Every field is optional;
//  anything absent falls back to a default that is meant to already look good,
//  because the point of this app is that it is beautiful before you configure it.
//
//  Deliberately plain JSON rather than a bespoke format: it is diffable,
//  machine-editable, and needs no parser of its own.
//
//  This file is the *loader* and the single source of truth for defaults. The
//  values it resolves into live next door: colour parsing and the presets are in
//  `Theme.swift`, and the UserDefaults stores (zoom, remembered Space roots) are
//  in `Defaults.swift` — none of which this file's fail-soft contract depends on.
//  `ConfigFile` stays `private` here because nothing outside the loader may see
//  the wire format; every other file reads the resolved `AppConfig` instead.
//

import AppKit
// No `import SwiftTerm`. It was here for exactly one symbol, `CursorStyle`, which is
// now this project's own type in CursorStyle.swift — see that file's header for why an
// app-wide config type must not name the emulator.

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
    var renderer: String?
    var engine: String?
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
    /// Which drawing back end terminals use. See `Renderer.swift` for the two paths and
    /// why the default is the conservative one.
    var renderer: Renderer
    /// Which emulator core backs a NEW terminal document. See `TerminalEngine.swift`.
    ///
    /// Read once per document, at construction, and deliberately never re-read: ⌘R applies a
    /// new config to every LIVE pane (`apply(config:)`), but a live pane cannot change engine
    /// — rebuilding the core underneath a running shell would discard its scrollback and its
    /// child process. So editing this and hitting ⌘R affects the next ⌘T, not the tab you are
    /// looking at, and that is the honest behaviour rather than a limitation to work around.
    var engine: TerminalEngine
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

    /// Resize the configured face. Derived from the resolved font's **descriptor**,
    /// not re-resolved from its family name: the system monospaced face is
    /// `.AppleSystemUIFontMonospaced`, a dot-prefixed internal family that is not
    /// guaranteed to survive `NSFont(name:)`, and the old code's fallback for that
    /// miss was hardcoded Menlo — the exact silent substitution that made v0.1
    /// render worse than the spike (see `preferredMonoFont`). The descriptor
    /// carries the resolved face, so zooming cannot change it.
    ///
    /// Lives here rather than on one pane because every document kind zooms
    /// (`SpaceDocument.setFontSize`), and a second private copy in `FileViewerPane`
    /// is a second place for this fallback to rot.
    static func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        NSFont(descriptor: base.fontDescriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

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
            cursorStyle: .default,
            // 1,000 (iTerm2's default), not 10,000. SwiftTerm sizes the scrollbar
            // thumb as `max(rows / lines.count, 0.01)`
            // (`AppleTerminalView.swift:2002`), so past ~3,500 lines the thumb
            // hits the 1% floor and degenerates into a fixed hairline that no
            // longer tracks position. `Buffer.resize` also walks every line TWICE
            // per resize — reflow, then the narrowing trim (vendor patch 0003) — so
            // a 10k buffer made window resizing far more expensive than it needed
            // to be. It was THREE walks until 2026-07-31: vendor patch 0004 removed
            // the third, an ungated upstream debug assertion that walked the whole
            // scrollback and called abort() in release builds.
            // Raise it if you want; know the cost.
            scrollback: 1_000,
            shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            optionAsMeta: true,
            renderer: .default,
            engine: .default
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
            // Same fail-soft shape as `renderer` below: an unrecognised value degrades to
            // the default and says so, rather than throwing. The spellings themselves moved
            // to `CursorStyle.named(_:)` so the mapping is compilable without AppKit.
            if let style = CursorStyle.named(raw) { config.cursorStyle = style }
            else { config.warnings.append("cursor '\(raw)' unrecognised — using block") }
        }

        if let sb = file.scrollback {
            if sb >= 0 { config.scrollback = sb }
            else { config.warnings.append("scrollback must be >= 0 — using \(config.scrollback)") }
        }
        if let sh = file.shell {
            // A newline is rejected as well as a non-executable, because `shell` is not only
            // exec'd. `GhosttyPane+Appearance.swift` renders it into a `key = value` line of a
            // ghostty config whose lines are joined with "\n", so a legal macOS filename
            // containing one would inject arbitrary further config keys. Caught here so the
            // result is one fail-soft warning rather than engine-specific silent corruption.
            if sh.contains(where: \.isNewline) {
                config.warnings.append("shell path contains a newline — using \(config.shell)")
            } else if FileManager.default.isExecutableFile(atPath: sh) { config.shell = sh }
            else { config.warnings.append("shell '\(sh)' is not executable — using \(config.shell)") }
        }
        if let meta = file.optionAsMeta { config.optionAsMeta = meta }
        if let raw = file.renderer {
            if let r = Renderer.named(raw) { config.renderer = r }
            else {
                config.warnings.append(
                    "renderer '\(raw)' unrecognised (expected one of: \(Renderer.configNames))"
                        + " — using \(config.renderer.configName)")
            }
        }
        if let raw = file.engine {
            if let e = TerminalEngine.named(raw) { config.engine = e }
            else {
                config.warnings.append(
                    "engine '\(raw)' unrecognised (expected one of: \(TerminalEngine.configNames))"
                        + " — using \(config.engine.configName)")
            }
        }

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
