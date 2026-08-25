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
        /// "umber" | "classic-repaired" | "afk-dark" | "afk-light" | "tokyo-night" |
        /// "classic". Omitted with other
        /// fields present means "umber, with my overrides on top" — see
        /// `Config+Theme.swift` for why the fallback is the measured palette.
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
    var mouseReporting: Bool?
    var renderer: String?

    struct EditorSpec: Decodable {
        var tabWidth: Int?
        var softTabs: Bool?
        var wordWrap: String?
        var indentRainbow: Bool?
        var columnGuide: Int?
        var showTrailingWhitespace: Bool?
        var stickyScroll: Bool?
    }
    var editor: EditorSpec?

    // `padding` accepts two forms:
    //   "padding": 4               → uniform 4px on all sides
    //   "padding": { "x": 8, "y": 4 } → separate horizontal / vertical
    // Both decode via a custom Decodable that tries a plain Double first.
    struct PaddingSpec: Decodable {
        let x: CGFloat
        let y: CGFloat

        private struct XY: Decodable {
            let x: CGFloat
            let y: CGFloat
        }

        init(from decoder: Decoder) throws {
            let single = try? decoder.singleValueContainer().decode(CGFloat.self)
            if let v = single {
                x = v; y = v
            } else {
                let xy = try XY(from: decoder)
                x = xy.x; y = xy.y
            }
        }
    }
    var padding: PaddingSpec?
}

/// Resolved, ready-to-use configuration. Never fails: a missing, malformed, or
/// partially-invalid config file yields defaults for whatever could not be read,
/// and the reasons are surfaced in `warnings` rather than thrown.
struct AppConfig {
    var font: NSFont
    /// `nil` means "do not install any colours" — SwiftTerm's own defaults stand.
    /// That is still the default, but **the reason it used to give was stale and is
    /// corrected here** (2026-08-03).
    ///
    /// The old note said installing a background or foreground makes SwiftTerm
    /// regenerate ANSI 16–255 by interpolating them out of your bg/fg, replacing the
    /// standard 256-colour cube. That is true of SwiftTerm's *library default* and
    /// false of this app: `TerminalPane.apply(config:)` sets
    /// `ansi256PaletteStrategy = .xterm` unconditionally before any colour
    /// (`TerminalPane.swift:165`), `Terminal.swift:523,538` gate the rebuild on
    /// `!= .xterm`, and `installPalette` under `.xterm` routes to
    /// `generateXtermPalette` (`Colors.swift:169-190`), which appends the literal
    /// standard cube and never reads bg/fg. **A custom palette is free of that
    /// defect**; installing one is now only a question of taste.
    ///
    /// **The default is `.classicRepaired` as of 2026-08-20** (was `.umber` since 2026-08-03),
    /// and the reasoning that kept it `nil`
    /// was wrong in a specific way worth recording. It treated "install nothing" as the
    /// conservative choice pending real use. It is not conservative — it is unmeasured.
    /// `nil` renders SwiftTerm's `Color.terminalAppColors` (`Colors.swift:91-108`) on
    /// black, which fails **7 of the 8** slots `check-theme-contrast.sh` has floors for:
    /// ANSI 4 blue `#492EE1` at APCA Lc 16.9, ANSI 1 red at 25.8, ANSI 8 — the colour
    /// nearly every tool uses for de-emphasised output — at 36.0 against a floor of 48,
    /// and a normal→bright ring separation of 0.054 against 0.085. For scale, that gate's
    /// own falsification case asserts xterm's `#0000EE` at Lc 14.0 must be REJECTED as the
    /// canonical unreadable blue; the old default's blue sat 2.9 points from it.
    /// "Daily-drive it first" is the right bar for choosing between two *good* palettes,
    /// not for keeping a measurably bad incumbent.
    ///
    /// `"preset": "classic"` still selects `nil` — install nothing — for anyone who wants
    /// the engine's own colours. See `ThemeValues.swift` for what `umber` is and
    /// `.afk/research/theme-design-2026-08-03/` for how it was derived.
    var theme: Theme?
    var cursorStyle: CursorStyle
    var scrollback: Int
    var shell: String
    var optionAsMeta: Bool
    /// Whether programs may request mouse events (DECSET 1000/1002/1003). Default
    /// `true`. When `false`, SwiftTerm's `allowMouseReporting` is cleared and clicks
    /// always start text selection — programs like tmux and vim lose their mouse
    /// support but the user can select and copy freely. The Shift-click bypass
    /// (`shiftBypassesMouseReporting`) still works when this is `true`.
    var mouseReporting: Bool
    /// Which drawing back end terminals use. See `Renderer.swift` for the two paths and
    /// why the default is the conservative one.
    var renderer: Renderer

    // Editor behaviour — see `Config+Editor.swift` for the resolver.
    var tabWidth: Int
    var softTabs: Bool
    var wordWrap: WordWrapMode
    /// Indent rainbow: subtle colour bands per indent level. Default: false.
    /// Configured via `editor.indentRainbow` in config.json.
    var indentRainbow: Bool
    /// Column guide position in characters. nil = no guide. Default: 80.
    /// Configured via `editor.columnGuide` in config.json; 0 means disabled.
    var columnGuideColumn: Int?
    /// Visualize trailing whitespace with dim dots. Default: true.
    /// Configured via `editor.showTrailingWhitespace` in config.json.
    var showTrailingWhitespace: Bool
    /// Pin the enclosing scope header at the top of the editor while scrolling.
    /// Default: true. Configured via `editor.stickyScroll` in config.json.
    var stickyScroll: Bool
    /// Inner margin around terminal content. See `Config+Padding.swift` for the full
    /// rationale and the parsing details (accepted forms, validation, fail-soft contract).
    /// Default (4, 4) — see `defaults()`.
    var terminalPadding: (x: CGFloat, y: CGFloat)
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

    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/umber/config.json")
    }

    /// A default that is intended to look good with zero configuration.
    static func defaults() -> AppConfig {
        AppConfig(
            font: preferredMonoFont(family: nil, size: defaultFontSize).font,
            theme: .classicRepaired,
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
            mouseReporting: true,
            renderer: .default,
            tabWidth: 4,
            softTabs: true,
            wordWrap: .auto,
            indentRainbow: false,
            columnGuideColumn: 80,
            showTrailingWhitespace: true,
            stickyScroll: true,
            terminalPadding: (x: 4, y: 4)
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

        // Theme. The whole per-field, fail-soft assembly lives in `Config+Theme.swift` —
        // pulled out when this file hit the 350-line ceiling, because "which palette do we
        // install given some optional strings a user typed" is one whole concern and needs
        // nothing else in `AppConfig`. Primitives rather than the spec itself, so
        // `ConfigFile` can stay `private` to this file.
        if let t = file.theme {
            config.theme = AppConfig.resolveTheme(preset: t.preset,
                                                  background: t.background,
                                                  foreground: t.foreground,
                                                  cursor: t.cursor,
                                                  ansi: t.ansi,
                                                  warnings: &config.warnings)
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
            // A newline in a shell path is rejected alongside non-executable: a legal macOS
            // filename containing one could cause subtle breakage if any downstream consumer
            // joins paths with newlines (config renderers, diagnostic output). Caught here so
            // the result is one fail-soft warning rather than silent corruption.
            if sh.contains(where: \.isNewline) {
                config.warnings.append("shell path contains a newline — using \(config.shell)")
            } else if FileManager.default.isExecutableFile(atPath: sh) { config.shell = sh }
            else { config.warnings.append("shell '\(sh)' is not executable — using \(config.shell)") }
        }
        if let meta = file.optionAsMeta { config.optionAsMeta = meta }
        if let mr = file.mouseReporting { config.mouseReporting = mr }
        if let raw = file.renderer {
            if let r = Renderer.named(raw) { config.renderer = r }
            else {
                config.warnings.append(
                    "renderer '\(raw)' unrecognised (expected one of: \(Renderer.configNames))"
                        + " — using \(config.renderer.configName)")
            }
        }
        if let e = file.editor {
            config.applyEditor(tabWidth: e.tabWidth, softTabs: e.softTabs,
                               wordWrap: e.wordWrap,
                               indentRainbow: e.indentRainbow,
                               columnGuide: e.columnGuide,
                               showTrailingWhitespace: e.showTrailingWhitespace,
                               stickyScroll: e.stickyScroll)
        }
        if let p = file.padding {
            config.applyPadding(x: p.x, y: p.y)
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
