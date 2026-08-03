//
//  check-theme-contrast-harness.swift
//  The assertions for check-theme-contrast.sh. Copied to main.swift and compiled
//  against the SHIPPED ThemeValues.swift + ThemeContrast.swift — never a copy of them.
//
//  Two files rather than one for the same reason check-git-status.sh is two files: inline,
//  the shell half and the assertions run past the repo's 350-LOC ceiling, and the rule for
//  that is to find the seam rather than shave comments.
//
//  The verdict is this program's EXIT CODE. It also prints ALL-OK, but the shell half
//  checks the status, because a harness that crashes after printing its verdict would
//  otherwise read as a green gate — a real bug that shipped in check-ghostty-pane.sh.
//

import Foundation

var failures: [String] = []
var checks = 0

func expect(_ ok: Bool, _ what: String, _ detail: String) {
    checks += 1
    if !ok { failures.append("\(what): \(detail)") }
}

func rgb(_ hex: String, _ label: String) -> RGB? {
    guard let c = RGB(hex: hex) else {
        failures.append("\(label): '\(hex)' is not parseable as #rrggbb")
        checks += 1
        return nil
    }
    checks += 1
    return c
}

// ---------------------------------------------------------------- 1. parseability
// Every hex in every shipped palette must parse. Theme.swift force-unwraps all of them
// via NSColor.fromHex, so an unparseable literal is a launch-time trap; here it is a
// failed gate instead. This is the one case that must run before anything else.
for p in ThemePalette.all {
    for (label, hex) in [("background", p.background), ("foreground", p.foreground),
                         ("cursor", p.cursor), ("selection", p.selection)] {
        _ = rgb(hex, "\(p.name).\(label)")
    }
    expect(p.ansi.count == 16, "\(p.name).ansi", "has \(p.ansi.count) entries, not 16 — "
           + "SwiftTerm's installColors silently no-ops off-16")
    for (i, hex) in p.ansi.enumerated() { _ = rgb(hex, "\(p.name).ansi[\(i)]") }
}

// ------------------------------------------------------- 2. reachability from config
// A preset that exists but no config string resolves to is invisible; a name that
// resolves to nothing falls back to a DIFFERENT theme with only a warning. The two lists
// live in different files (ThemeValues.all, Theme.preset(named:)) and must not drift.
// Theme.swift imports AppKit so it cannot be linked here — instead assert the canonical
// names this harness knows about, and let the shell half grep the switch for each one.
let expectedNames = ["umber", "afk-dark", "tokyo-night"]
expect(Set(ThemePalette.all.map(\.name)) == Set(expectedNames),
       "preset names", "ThemePalette.all is \(ThemePalette.all.map(\.name)), expected \(expectedNames)")

// ------------------------------------------------ 3. the two luminance models agree
// Config.appearance derives the window's light/dark chrome from NSColor.relativeLuminance
// (AppKit); every threshold below uses WCAG.luminance (pure). If they ever disagree the
// chrome and the measurements are describing different colours. Assert on a fixed vector
// with values computed from the WCAG 2.1 definition.
for (hex, want) in [("#000000", 0.0), ("#FFFFFF", 1.0), ("#808080", 0.2158605),
                    ("#FF0000", 0.2126), ("#00FF00", 0.7152), ("#0000FF", 0.0722)] {
    if let c = RGB(hex: hex) {
        expect(abs(WCAG.luminance(c) - want) < 0.0005, "WCAG.luminance(\(hex))",
               "got \(WCAG.luminance(c)), want ~\(want)")
    }
}

// ------------------------------------------------------ 4. APCA's loClip is real
// ANSI 0 is judged by OKLab distance, never by APCA, because APCA reports exactly 0 below
// its invisibility threshold. If that stopped being true the ANSI-0 rule below would be
// measuring the wrong thing. Assert the clip directly so the reasoning stays checked.
if let a = RGB(hex: "#19120D"), let b = RGB(hex: "#1B140F") {
    expect(APCA.lc(text: b, background: a) == 0, "APCA loClip",
           "two near-identical darks gave Lc \(APCA.lc(text: b, background: a)), expected exactly 0")
}

// ------------------------------------------------------------- 5. Umber's thresholds
// Only Umber is held to these. afk-dark and tokyo-night are verbatim upstream ports and
// they FAIL several of them (measured: tokyo-night's ANSI 8 is Lc 10.3, and six of its
// eight normal/bright pairs are identical) — that is recorded in ThemeValues.swift and is
// the point of the comparison, not a defect to launder by relaxing the rule for everyone.
let u = ThemePalette.umber
guard let bg = RGB(hex: u.background), let fg = RGB(hex: u.foreground),
      let cur = RGB(hex: u.cursor), let sel = RGB(hex: u.selection) else {
    print("FAIL: Umber's own base colours do not parse")
    exit(1)
}
let a = u.ansi.compactMap { RGB(hex: $0) }
guard a.count == 16 else { print("FAIL: Umber ansi did not parse to 16"); exit(1) }

// 5a. Background must keep the window's chrome DARK. Config.lightChromeCutoff is 0.179.
expect(WCAG.luminance(bg) <= 0.179, "Umber background",
       "luminance \(WCAG.luminance(bg)) is above Config.lightChromeCutoff 0.179, so the "
       + "window would adopt LIGHT chrome against a dark terminal")

// 5b. Background must actually be WARM — this is the design thesis, so it is asserted, not
// just described. OKLab b > 0 means yellow-ward; a > 0 means red-ward. A cold or neutral
// background silently turns Umber into another GitHub Dark.
let bgLab = OKLab.from(bg)
expect(bgLab.b > 0.008 && bgLab.a > 0.001, "Umber background warmth",
       "OKLab a=\(String(format: "%.4f", bgLab.a)) b=\(String(format: "%.4f", bgLab.b)) — "
       + "the background is not measurably warm")

// 5c. Body text. APCA 90 is 'preferred body'; 85 leaves room for the hex rounding.
expect(APCA.lc(text: fg, background: bg) >= 85, "Umber foreground",
       "APCA Lc \(String(format: "%.1f", APCA.lc(text: fg, background: bg))) < 85")

// 5d. ANSI 0 is a surface: visible against the background, but not a second background.
let d0 = OKLab.distance(a[0], bg)
expect(d0 >= 0.05 && d0 <= 0.14, "Umber ANSI 0",
       "dE-OK \(String(format: "%.3f", d0)) from background is outside 0.05…0.14")

// 5e. Per-slot APCA floors, by ROLE. The chromatic slots are categorical markers layered
// on an already-readable foreground, so APCA's large/headline tier (45) is the right floor,
// lifted for the ones that routinely carry whole lines. ANSI 8 is the comment colour and
// is the field's universal failure — floor 48, where every theme measured scores 0–34.
let floors: [Int: Double] = [1: 50, 2: 60, 3: 58, 4: 48, 5: 56, 6: 60, 7: 74, 8: 48,
                             9: 65, 10: 75, 11: 73, 12: 63, 13: 71, 14: 75, 15: 92]
let slotNames = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                 "bright black", "bright red", "bright green", "bright yellow",
                 "bright blue", "bright magenta", "bright cyan", "bright white"]
for (i, floor) in floors.sorted(by: { $0.key < $1.key }) {
    let lc = APCA.lc(text: a[i], background: bg)
    expect(lc >= floor, "Umber ANSI \(i) (\(slotNames[i]))",
           "APCA Lc \(String(format: "%.1f", lc)) < floor \(Int(floor))")
}

// 5f. Bright must be distinguishable from normal. SwiftTerm renders BOLD text from the
// bright half by default (useBrightColors), so a collapsed pair makes bold invisible —
// which is exactly what Tokyo Night, Catppuccin, Nord and Rosé Pine all ship (dE 0.000).
for i in 0..<8 {
    let de = OKLab.distance(a[i], a[i + 8])
    expect(de >= 0.085, "Umber ring \(i)/\(i + 8) (\(slotNames[i]))",
           "normal→bright dE-OK \(String(format: "%.3f", de)) < 0.085 — bold text would "
           + "be indistinguishable from plain")
    expect(OKLab.lightness(a[i + 8]) > OKLab.lightness(a[i]),
           "Umber ring \(i)/\(i + 8) direction", "the bright slot is not lighter")
}

// 5g. Colour-vision deficiency, tiered by whether a reader must tell the pair apart to
// read output CORRECTLY. Tier 1 is the load-bearing set: diff +/-, pass/fail/warn.
// The three accepted shortfalls are deliberate and argued — red/yellow/green cannot all
// clear 0.105 under deuteranopia without a ~0.21 lightness span, which washes green out
// (proved in .afk/research/theme-design-2026-08-03/solve_warm.py and rejected on the
// rendered evidence in preview2.html). They are pinned at their measured values so they
// cannot silently degrade further.
let cvdFloors: [(Int, Int, Double, String)] = [
    (1, 2, 0.105, "red/green — diff -/+, fail/pass"),
    (1, 3, 0.080, "red/yellow — accepted shortfall, see design doc"),
    (2, 3, 0.080, "green/yellow — accepted shortfall, see design doc"),
    (4, 5, 0.080, "blue/magenta"),
    (2, 6, 0.080, "green/cyan"),
    (4, 6, 0.080, "blue/cyan"),
    (1, 5, 0.080, "red/magenta"),
    (1, 4, 0.080, "red/blue"),
    (5, 6, 0.025, "magenta/cyan — tier 3, cosmetic adjacency only"),
    (3, 5, 0.050, "yellow/magenta"),
    (3, 6, 0.050, "yellow/cyan"),
    (2, 4, 0.050, "blue/green"),
]
for (x, y, floor, why) in cvdFloors {
    for off in [0, 8] {
        let w = CVD.worstDistance(a[x + off], a[y + off])
        let ring = off == 0 ? "normal" : "bright"
        expect(w >= floor, "Umber CVD \(ring) \(slotNames[x + off])/\(slotNames[y + off])",
               "worst dichromacy dE-OK \(String(format: "%.3f", w)) < \(floor) — \(why)")
    }
}

// 5h. Selection must be visible as a lift of the background without swallowing text.
let dSel = OKLab.distance(sel, bg)
expect(dSel >= 0.08 && dSel <= 0.22, "Umber selection",
       "dE-OK \(String(format: "%.3f", dSel)) from background is outside 0.08…0.22")
expect(APCA.lc(text: fg, background: sel) >= 60, "Umber foreground on selection",
       "APCA Lc \(String(format: "%.1f", APCA.lc(text: fg, background: sel))) < 60 — "
       + "selected text would be hard to read")

// 5i. The cursor must be visible against the background it sits on.
expect(APCA.lc(text: cur, background: bg) >= 45, "Umber cursor",
       "APCA Lc \(String(format: "%.1f", APCA.lc(text: cur, background: bg))) < 45")

// ------------------------------------------------------------------- 6. falsification
// A gate that cannot fail proves nothing. Feed it a palette known to be bad — the xterm
// default 16 on pure black, whose ANSI 4 (#0000EE) is the canonical unreadable blue — and
// require the SAME rules to reject it. If this passes, the thresholds are not doing work.
if let black = RGB(hex: "#000000"), let badBlue = RGB(hex: "#0000EE") {
    let lc = APCA.lc(text: badBlue, background: black)
    expect(lc < 48, "falsification",
           "xterm's #0000EE on black measured Lc \(String(format: "%.1f", lc)), which PASSES "
           + "the ANSI-4 floor — the thresholds are too loose to detect the canonical "
           + "unreadable-blue case, so the other results mean nothing")
}
// And a collapsed bright pair must be caught by the ring rule.
if let c = RGB(hex: "#F7768E") {
    expect(OKLab.distance(c, c) < 0.085, "falsification (ring)",
           "an identical normal/bright pair was not rejected by the 0.085 rule")
}

// ---------------------------------------------------------------------------- verdict
if failures.isEmpty {
    print("ALL-OK  \(checks) assertions passed")
    exit(0)
}
print("FAIL  \(failures.count) of \(checks) assertions failed:")
for f in failures { print("  - \(f)") }
exit(1)
