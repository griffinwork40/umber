//
//  ThemeCatalog.swift
//  The shipped palettes as pure data, the name that selects one, and the WCAG
//  luminance formula that decides whether one is light or dark.
//
//  Foundation-only BY DESIGN, for the same reason as `Renderer.swift`,
//  `CursorStyle.swift` and `TerminalEngine.swift`: the *decision* — which hex values
//  a preset name selects, and whether that background reads as light — is a pure
//  mapping, and a pure mapping can be compiled into a check without AppKit in scope.
//  `Theme.swift` keeps the *action*: turning these strings into `NSColor` and
//  `SwiftTerm.Color`. That file imports AppKit AND SwiftTerm, so it cannot be
//  compiled standalone and nothing in it has ever been gateable.
//
//  THE FORMULA LIVES HERE, NOT IN `NSColor.relativeLuminance`, and that is the
//  point of the split. `AppConfig.appearance` (`Config.swift:149`) picks light vs
//  dark chrome by testing that luminance against `lightChromeCutoff`. If the
//  formula or a shipped background were ever wrong, a light theme would install
//  its colours and leave the sidebar dark — a silent, config-shaped no-op, the
//  exact failure class `check-renderer-config.sh` exists to prevent for `renderer`.
//  `NSColor.relativeLuminance` now converts to sRGB and calls this, so there is one
//  implementation of the maths and the gate compiles it.
//
//  `lightChromeCutoff` ALSO lives here now, not just the formula, and for the same
//  reason: it used to be a second literal in `Config.swift` too, with a doc comment
//  claiming this gate "asserts the two stay equal by reading the literal out of that
//  file" — false, because `check-light-theme.sh` compiles only this file plus its own
//  harness (`SRC` and the `swiftc` call) and never reads `Config.swift` at all. So
//  editing the `Config.swift` copy alone left the gate green while the shipped light
//  preset rendered dark window chrome (PR #24 review, item 1). `Config.swift:149` now
//  reads this symbol directly — one constant, and the gate's cases 2–3 constrain the
//  exact value production compares against, not a copy of it.
//

import Foundation

/// One shipped palette, as the hex strings it was published as.
///
/// Strings rather than parsed colours because this file must not import AppKit, and
/// because the published sources below are themselves hex — storing them verbatim
/// keeps the citation checkable by eye against its URL.
struct ThemeRecord {
    let configName: String
    let background: String
    let foreground: String
    let cursor: String
    /// Exactly 16: 8 normal then 8 bright. Enforced by `check-light-theme.sh`, not
    /// by the type, because a 16-tuple is unreadable and an array is what both
    /// engines want.
    let ansi: [String]
}

enum ThemeCatalog {
    // MARK: - Shipped presets

    /// AFK Dark. Every value moved verbatim from `Theme.swift:116-126` (where it
    /// lived until this file existed), which took them from the `terminal` block of
    /// `themes/terax/afk-dark.terax-theme` in the agent-afk repo: a GitHub-Dark
    /// skeleton with the AFK warm-orange accent (#E67E4C) as the caret. That file
    /// declares `variants: ['dark']` and has no light sibling, which is why
    /// `afkLight` below is sourced from a published palette instead of ported.
    static let afkDark = ThemeRecord(
        configName: "afk-dark",
        background: "#0D1117", foreground: "#C9D1D9", cursor: "#E67E4C",
        ansi: [
            "#161B22", "#F85149", "#9CB04A", "#E5C07B",
            "#5BA8FF", "#9F7CE0", "#56B5A8", "#C9D1D9",
            "#484F58", "#F85149", "#A8E060", "#E67E4C",
            "#5BA8FF", "#F08AC4", "#5FE0C0", "#ECEFF4",
        ])

    /// Tokyo Night — the v0.1 default, kept as a preset. Values moved verbatim from
    /// `Theme.swift:129-139`; upstream is enkia/tokyo-night-vscode-theme's
    /// `terminal.ansi*` keys (https://github.com/enkia/tokyo-night-vscode-theme).
    static let tokyoNight = ThemeRecord(
        configName: "tokyo-night",
        background: "#1A1B26", foreground: "#C0CAF5", cursor: "#C0CAF5",
        ansi: [
            "#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
            "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5",
        ])

    /// AFK Light — the light sibling of `afk-dark`, and the exact counterpart of how
    /// that preset was built: `afk-dark` is a GitHub *Dark* skeleton, so this is
    /// GitHub *Light Default*, verbatim.
    ///
    /// Every value below is copied from primer/github-vscode-theme's published
    /// `terminal.*` keys — nothing here was chosen or adjusted by hand. Fetched from
    /// https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/ghostty/GitHub%20Light%20Default
    /// (the Ghostty-format port), with the upstream confirmed by reading lines
    /// 283-299 of
    /// https://raw.githubusercontent.com/primer/github-vscode-theme/main/src/theme.js
    /// where `terminal.foreground` and all sixteen `terminal.ansi*` slots are
    /// defined from `color.ansi.*`.
    ///
    /// Note slots 3 (#4D2D00) and 11 (#633C01): GitHub deliberately darkens "yellow"
    /// to near-brown for a white background. That is the adaptation a transplanted
    /// dark palette cannot make, and it is this palette earning its keep — not a
    /// transcription error. One conflicting citation exists for the foreground
    /// (alacritty-theme's port says #0E1116); #1F2328 is used, matching primer and
    /// the Ghostty port, and the alternative is darker still so the choice is not
    /// load-bearing for legibility.
    ///
    /// The cursor is GitHub's own #0969DA and NOT the AFK orange #E67E4C that
    /// `afk-dark` uses, which was measured and rejected: #E67E4C on #FFFFFF is a
    /// WCAG contrast ratio of 2.82, below the 3.0 floor for a non-text mark, so the
    /// caret would be the least legible thing in a window whose whole selling point
    /// is legibility. Picking a darker brand orange is a design decision with no
    /// published source to cite, so it is deliberately not made here.
    ///
    /// Chosen over Solarized Light, Catppuccin Latte and Tokyo Night Day on measured
    /// contrast against their own backgrounds: of the twelve ANSI slots a TUI
    /// actually colours text with, the number falling under WCAG 3.0 is 5, 7 and 3
    /// respectively — and 0 here.
    static let afkLight = ThemeRecord(
        configName: "afk-light",
        background: "#FFFFFF", foreground: "#1F2328", cursor: "#0969DA",
        ansi: [
            "#24292F", "#CF222E", "#116329", "#4D2D00",
            "#0969DA", "#8250DF", "#1B7C83", "#6E7781",
            "#57606A", "#A40E26", "#1A7F37", "#633C01",
            "#218BFF", "#A475F9", "#3192AA", "#8C959F",
        ])

    /// Every preset, in the order a warning should list them. Drives the gate's
    /// round-trip and the `configNames` below, so adding a preset cannot leave
    /// either behind.
    static let all: [ThemeRecord] = [afkDark, afkLight, tokyoNight]

    /// The canonical spellings, for the fail-soft warning in `AppConfig.load()`.
    /// `classic` is appended by hand because it is the one accepted value that
    /// resolves to no record at all.
    static var configNames: [String] { all.map(\.configName) + ["classic"] }

    /// Resolve a `"preset"` name. `"classic"` is deliberately absent: it maps to
    /// `nil`, meaning "install nothing and let the engine's own defaults stand".
    static func named(_ raw: String) -> ThemeRecord? {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        return all.first { $0.configName == key || $0.configName.replacingOccurrences(of: "-", with: "") == key }
    }

    // MARK: - Luminance

    /// WCAG 2.1 relative luminance, 0…1, from sRGB components already in 0…1.
    ///
    /// The single implementation of this formula in the app. `NSColor.relativeLuminance`
    /// (`Theme.swift`) converts to sRGB and calls this; `AppConfig.appearance`
    /// (`Config.swift:149`) compares the result to `lightChromeCutoff`.
    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        // Gamma-expand each channel before weighting — luminance is defined on
        // linear light, and skipping this misjudges mid-tones badly.
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// As above, from a `#rrggbb` string. Returns nil on anything unparseable so the
    /// gate can assert every shipped hex is well-formed rather than trusting it.
    static func luminance(hex raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return luminance(
            red: Double((v >> 16) & 0xff) / 255.0,
            green: Double((v >> 8) & 0xff) / 255.0,
            blue: Double(v & 0xff) / 255.0)
    }

    /// WCAG 2.1's contrast crossover: above this luminance a background reads better
    /// with black text than white, which is exactly the question `AppConfig.appearance`
    /// (`Config.swift:149`) asks — "should this window's chrome be light or dark?" All
    /// three shipped dark themes sit far below it (afk-dark ≈ 0.008, tokyo-night ≈
    /// 0.012, black = 0), so this only starts discriminating once a light theme is
    /// configured.
    ///
    /// The constant lives here, not in `Config.swift`, because THIS is the file the
    /// gate can compile standalone — `Config.swift` imports AppKit and
    /// `check-light-theme.sh` cannot link it — and production reads this exact
    /// symbol (`Config.swift:149`), not a second copy of the number. One literal, one
    /// reader in the gate, one reader in production; a change to either sees the same
    /// value.
    static let lightChromeCutoff: Double = 0.179
}
