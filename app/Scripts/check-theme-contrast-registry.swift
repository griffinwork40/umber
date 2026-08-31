//
//  check-theme-contrast-registry.swift
//  The preset-registry half of the theme-contrast gate.
//
//  Split out of check-theme-contrast-harness.swift on 2026-08-03, when reconciling PR #24
//  pushed that file to 370 lines — 20 over this repo's hard 350-LOC ceiling. The rule for
//  that is to find the seam and move a whole concern, never to shave comments to fit
//  (`AFK.md`, Conventions), and this is the natural seam: everything here is about WHICH
//  palettes exist and HOW a config string reaches one, and nothing here measures a colour.
//
//  Swift only allows top-level code in a file literally named main.swift, so this cannot
//  be a second script of statements — it is one function the harness calls, taking `expect`
//  as a parameter so the counters and failure list stay owned by the harness.
//

import Foundation

/// Assert the palette registry and the config-string resolver.
func checkPresetRegistry(_ expect: (Bool, String, String) -> Void) {
    // A preset that exists but no config string resolves to is invisible; a name that
    // resolves to nothing falls back to a DIFFERENT theme with only a warning. The two lists
    // live in different files (ThemeValues.all, Theme.preset(named:)) and must not drift.
    // Theme.swift imports AppKit so it cannot be linked here — instead assert the canonical
    // names this harness knows about, and let the shell half grep the switch for each one.
    let expectedNames = ["umber", "classic-repaired", "afk-dark", "tokyo-night", "afk-light",
                         "catppuccin-mocha", "nord", "dracula", "gruvbox-dark", "rose-pine"]
    expect(Set(ThemePalette.all.map(\.name)) == Set(expectedNames),
           "preset names", "ThemePalette.all is \(ThemePalette.all.map(\.name)), expected \(expectedNames)")

    // The reachability half USED to be a grep of Theme.preset(named:)'s switch in the shell half,
    // because the mapping lived behind AppKit. It no longer does: `ThemePalette.named(_:)` is
    // Foundation-only as of 2026-08-03 (reconciling PR #24), so the resolver users actually reach
    // is callable right here and the two lists collapsed into one — `all` is the sole registry.
    // Strictly stronger than the grep it replaces, which could only confirm a spelling APPEARED
    // somewhere, never what it returned.
    for pal in ThemePalette.all {
        expect(ThemePalette.named(pal.name)?.name == pal.name, "\(pal.name) round-trip",
               "named(\"\(pal.name)\") gave \(ThemePalette.named(pal.name)?.name ?? "nil")")
        let stripped = pal.name.replacingOccurrences(of: "-", with: "")
        expect(ThemePalette.named(stripped)?.name == pal.name, "\(pal.name) hyphen-stripped",
               "'\(stripped)' should fold to \(pal.name)")
        let underscored = pal.name.replacingOccurrences(of: "-", with: "_")
        expect(ThemePalette.named(underscored)?.name == pal.name, "\(pal.name) underscored",
               "'\(underscored)' should fold to \(pal.name)")
        expect(ThemePalette.named(pal.name.uppercased())?.name == pal.name, "\(pal.name) case-folded",
               "'\(pal.name.uppercased())' should fold to \(pal.name)")
    }
    // `classic` and a typo must BOTH resolve to nil; the distinction is made one layer up in
    // AppConfig.resolveTheme, where classic stays nil and a typo warns and falls back to umber.
    // If `classic` ever resolved to a palette, "install nothing" would silently install something.
    expect(ThemePalette.named("classic") == nil, "classic resolves to nil",
           "'classic' gave \(ThemePalette.named("classic")?.name ?? "nil") — it must install nothing")
    expect(ThemePalette.named("umbre") == nil, "typo resolves to nil", "a typo must not resolve")
    expect(ThemePalette.configNames.contains("classic"), "configNames names classic",
           "the fail-soft warning must list 'classic' — a user who typo'd needs to see it")
    for pal in ThemePalette.all {
        expect(ThemePalette.configNames.contains(pal.name), "configNames names \(pal.name)",
               "the warning would not list \(pal.name)")
    }
}
