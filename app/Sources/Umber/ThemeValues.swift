//
//  ThemeValues.swift
//  The shipped palettes, as hex strings, and nothing else.
//
//  **Pure and view-free — Foundation only, on purpose.** This is the half of theming
//  that `check-theme-contrast.sh` can compile standalone, which is the repo's only
//  mechanical gate (see `GitStatus.swift` and `Renderer.swift` for the same trick and
//  the same reason). `Theme.swift` imports AppKit *and* SwiftTerm, so a palette living
//  there is unreachable by any check — and a palette is exactly the kind of thing that
//  wants checking, because "is this legible" is a number and a number nobody computed
//  is a taste claim wearing a lab coat.
//
//  Why hex strings rather than parsed colours: the two engines want the same palette in
//  two different shapes — SwiftTerm takes a typed `SwiftTerm.Color`, libghostty takes a
//  `String` (`GhosttyPane+Appearance.swift`, and `NSColor.hexString`'s note in
//  `Theme.swift`). Hex is the common ancestor of both, it is what every upstream theme
//  publishes, and it is what a gate can assert on without linking a UI framework.
//
//  The OKLCH triple each colour was derived from is recorded in the comment beside it.
//  That is the actual design decision; the hex is a rendering of it. Full derivation,
//  the measurement tooling and the rejected alternatives are in
//  `.afk/research/theme-design-2026-08-03/`.
//

import Foundation

/// A 16-colour ANSI palette plus background/foreground/cursor, held as `#rrggbb`.
///
/// Deliberately a *value* with no behaviour: `Theme` (AppKit) converts one of these
/// into `NSColor`s, and `ThemeContrast` (pure) measures one. Neither concern belongs
/// here, so that adding a preset stays a one-line edit that cannot break either.
struct ThemePalette {
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    /// The selection background. Not yet wired to either engine — both can express it
    /// (`TerminalView.selectedTextBackgroundColor`; libghostty's `.selectionBackground`)
    /// and neither is told, which is a real gap recorded in the design doc rather than
    /// quietly omitted. Carried here so the value exists when the wiring lands.
    let selection: String
    /// Exactly 16: 8 normal then 8 bright. SwiftTerm's `installColors` silently does
    /// nothing if the array is not 16 long, so `Config` validates before `Theme` builds.
    let ansi: [String]
}

extension ThemePalette {
    /// **Umber** — the theme designed for this app, and the only one here that was
    /// measured rather than transcribed.
    ///
    /// Three things make it different from the field, each verified by
    /// `check-theme-contrast.sh` rather than asserted:
    ///
    /// 1. **The base is warm.** OKLCH hue 56 (raw-umber earth pigment, which is what
    ///    the app is named after) at chroma 0.016 — enough to read warm beside macOS's
    ///    cool sidebar material, low enough not to read brown. Every widely-used dark
    ///    theme measured sits at hue 219–291 (cold) or at chroma 0.000 (neutral grey);
    ///    gruvbox looks warm and measures `#282828`, a pure neutral. The niche is empty.
    ///
    /// 2. **ANSI 8 is legible.** It is the colour nearly every tool uses for de-emphasised
    ///    output — compiler progress, timings, paths — and every theme measured leaves it
    ///    unreadable: APCA Lc 0.0 for Solarized Dark, 10.3 for Tokyo Night and Nord, 13.1
    ///    for this repo's own afk-dark, against a floor of 45. Umber's is 51.5. For a
    ///    terminal whose job is hosting a coding agent's output, this is the single
    ///    biggest legibility win available.
    ///
    /// 3. **Bright is actually brighter.** Tokyo Night, Catppuccin, Nord and Rosé Pine
    ///    all ship *identical* values in the normal and bright chromatic slots (measured
    ///    dE-OK 0.000), so bold text — which SwiftTerm renders from the bright half by
    ///    default (`useBrightColors`) — is indistinguishable from plain. Umber's
    ///    smallest normal→bright separation is 0.088.
    ///
    /// Lightness is *staggered* across the ring rather than constant. That is not
    /// sloppiness: constant OKLCH lightness and constant readability are mutually
    /// exclusive in sRGB, because APCA weights luminance per channel (R .213, G .715,
    /// B .072), so a saturated red at a green's lightness is far less readable. The
    /// stagger is also what keeps red and green apart for a red-green colour-blind
    /// reader, where hue is gone and lightness is the only surviving signal.
    static let umber = ThemePalette(
        name: "umber",
        background: "#19120D",   // OKLCH 0.190 0.016  56 — warm umber-black
        foreground: "#E5DFD6",   // OKLCH 0.905 0.014  80 — warm paper, Lc 87.0
        cursor:     "#FF9B5A",   // OKLCH 0.780 0.145  52 — umber-orange caret
        selection:  "#453021",   // OKLCH 0.330 0.040  56 — a warm lift of the background
        ansi: [
            "#342C26",  //  0 black          0.300 0.016  56 — a surface, not text
            "#EF7F74",  //  1 red            0.720 0.140  27
            "#8AE49E",  //  2 green          0.844 0.131 150
            "#D7AA32",  //  3 yellow         0.759 0.140  87
            "#739EF0",  //  4 blue           0.702 0.130 262
            "#FFACE9",  //  5 magenta        0.843 0.123 337
            "#42CBC8",  //  6 cyan           0.770 0.115 193
            "#D3CDC5",  //  7 white          0.851 0.013  74
            "#AAA19B",  //  8 bright black   0.715 0.014  56 — the comment colour
            "#FDAAA0",  //  9 bright red     0.816 0.100  27
            "#B4FCC3",  // 10 bright green   0.929 0.106 150
            "#F7D179",  // 11 bright yellow  0.875 0.115  87
            "#9DBEFC",  // 12 bright blue    0.800 0.096 262
            "#FFD2F2",  // 13 bright magenta 0.912 0.078 337
            "#80E5E2",  // 14 bright cyan    0.860 0.095 193
            "#F9F6F2",  // 15 bright white   0.974 0.006  74
        ]
    )

    /// AFK Dark — a 1:1 port of the `terminal` block of `themes/terax/afk-dark.terax-theme`
    /// in the agent-afk repo: a GitHub-Dark skeleton with that project's warm-orange
    /// accent (#E67E4C). Kept verbatim, including its measured weaknesses (ANSI 8 at
    /// Lc 13.1, and normal/bright pairs that are identical in six of eight slots), because
    /// a preset's job is to be the thing it claims to be — silently "fixing" a port makes
    /// it a different theme wearing the same name.
    static let afkDark = ThemePalette(
        name: "afk-dark",
        background: "#0D1117", foreground: "#C9D1D9", cursor: "#E67E4C",
        selection: "#264F78",
        ansi: [
            "#161B22", "#F85149", "#9CB04A", "#E5C07B",
            "#5BA8FF", "#9F7CE0", "#56B5A8", "#C9D1D9",
            "#484F58", "#F85149", "#A8E060", "#E67E4C",
            "#5BA8FF", "#F08AC4", "#5FE0C0", "#ECEFF4",
        ]
    )

    /// **AFK Light** — `"preset": "afk-light"`, and the only light palette here.
    ///
    /// A verbatim port of GitHub's Light Default, so it is NOT held to umber's floors
    /// below — the same exemption `afkDark` and `tokyoNight` get, and for the same
    /// reason: measuring someone else's published palette against a standard it was
    /// never designed for tells you about them, not about this app. `check-light-theme.sh`
    /// gates it on WCAG ratios (3.0/4.5), which is what its source targeted.
    ///
    /// Its real job is structural: it is the first shipped preset whose background sits
    /// ABOVE `WCAG.lightChromeCutoff` (0.179, `ThemeContrast.swift`), so it is the only thing that exercises
    /// `AppConfig.appearance` returning `.aqua` and the whole light-chrome derivation
    /// underneath it. Before this existed that path was written but never run.
    ///
    /// `selection` is the one value NOT copied verbatim: GitHub publishes its selection
    /// as `#0969DA26` — a 15%-alpha blue — and `ThemePalette.selection` is opaque, so
    /// this is Primer's `blue.2` (`#B6E3FF`), the flattened equivalent of that tint over
    /// a white background. Noted because it is the single hex here that is derived
    /// rather than ported.
    static let afkLight = ThemePalette(
        name: "afk-light",
        background: "#FFFFFF", foreground: "#1F2328", cursor: "#0969DA",
        selection: "#B6E3FF",
        ansi: [
            "#24292F", "#CF222E", "#116329", "#4D2D00",
            "#0969DA", "#8250DF", "#1B7C83", "#6E7781",
            "#57606A", "#A40E26", "#1A7F37", "#633C01",
            "#218BFF", "#A475F9", "#3192AA", "#8C959F",
        ]
    )

    /// Tokyo Night — the v0.1 default, kept as a preset. Also transcribed verbatim.
    static let tokyoNight = ThemePalette(
        name: "tokyo-night",
        background: "#1A1B26", foreground: "#C0CAF5", cursor: "#C0CAF5",
        selection: "#283457",
        ansi: [
            "#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
            "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
            "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5",
        ]
    )

    /// Every shipped palette, so the gate can iterate them without a second list to
    /// forget to update. `preset(named:)` in `Theme.swift` resolves config strings; this
    /// is the enumeration, and the two must not drift — `check-theme-contrast.sh`
    /// asserts that every name here is reachable from config.
    static let all: [ThemePalette] = [.umber, .afkDark, .tokyoNight, .afkLight]

    /// Resolve a `"preset"` string to a palette. Case-insensitive, reads `_` as `-`, and
    /// accepts the hyphen-stripped spelling (`afkdark`), which is what users actually type.
    ///
    /// This lives in the pure file rather than as a `switch` in `Theme.swift` deliberately:
    /// `Theme.swift` imports AppKit *and* SwiftTerm, so a mapping there is unreachable by
    /// any gate and could only be checked by grepping the source for `case` lines — a proxy
    /// that passes whenever the spelling is present and says nothing about what it returns.
    /// Here both gates call the real resolver. It also removes the second list: `all` is now
    /// the only place a palette is registered, so a preset cannot exist while being
    /// unreachable from config, which was previously a drift the gate could only approximate.
    ///
    /// `"classic"` is deliberately absent and must resolve to nil — it means "install
    /// nothing and let the engine's own defaults stand". A typo also yields nil; the two are
    /// told apart one layer up in `AppConfig.resolveTheme` (`Config+Theme.swift`), where
    /// classic stays nil and a typo warns and falls back to `umber`.
    static func named(_ raw: String) -> ThemePalette? {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        return all.first { $0.name == key || $0.name.replacingOccurrences(of: "-", with: "") == key }
    }

    /// The canonical spellings, for the fail-soft warning in `AppConfig.resolveTheme`.
    /// `classic` is appended by hand because it is the one accepted value resolving to no
    /// palette at all — a user who typo'd needs to see it listed.
    static var configNames: [String] { all.map(\.name) + ["classic"] }
}
