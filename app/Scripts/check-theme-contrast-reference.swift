//
//  check-theme-contrast-reference.swift
//  The EXTERNAL reference-value assertions for check-theme-contrast.sh — §3b.
//
//  Split out of check-theme-contrast-harness.swift on 2026-08-05, when reconciling PR #26
//  (the editor syntax-role and selection-pairing sections) with main pushed that file to 355
//  lines — 5 over this repo's hard 350-LOC ceiling. The rule for that is to find the seam and
//  move a whole concern, never to shave comments to fit (`AFK.md`, Conventions), and this is
//  the natural seam: everything here checks the four hand-rolled numeric MODELS
//  (WCAG/APCA/OKLab/CVD) against a value this repo did not compute, and nothing here is about
//  a shipped palette.
//
//  Swift only allows top-level code in a file literally named main.swift, so this cannot be a
//  second script of statements — it is one function the harness calls, taking `expect` as a
//  parameter so the counters and failure list stay owned by the harness. Same pattern as
//  `check-theme-contrast-registry.swift` (PR #24) and `check-theme-contrast-syntax.swift`
//  (PR #26); one pattern per gate is worth more than any file's independent preference.
//

import Foundation

/// §3b — the hand-rolled models vs EXTERNAL reference values.
///
/// Four numeric models are re-implemented in `ThemeContrast.swift` from published matrices
/// and constants. Until this section existed, NONE of them was checked against a value from
/// outside this repo — a transposed matrix or a swapped constant would have produced
/// self-consistent nonsense that every threshold elsewhere in this gate happily passed. Added
/// after a devil's-advocate pass named that as the suite's structural blind spot.
func checkExternalReferenceValues(_ expect: (Bool, String, String) -> Void) {
    // OKLab: Ottosson's own published sRGB->Oklab values (bottosson.github.io/posts/oklab).
    // These are the strongest fixtures available anywhere in this file — they pin all nine
    // matrix coefficients plus the cube-root step against a third party.
    for (hex, wl, wa, wb) in [("#FFFFFF", 1.0000,  0.0000,  0.0000),
                              ("#000000", 0.0000,  0.0000,  0.0000),
                              ("#FF0000", 0.6279,  0.2249,  0.1258),
                              ("#00FF00", 0.8664, -0.2339,  0.1795),
                              ("#0000FF", 0.4520, -0.0324, -0.3115)] {
        if let c = RGB(hex: hex) {
            let g = OKLab.from(c)
            expect(abs(g.L - wl) < 0.002 && abs(g.a - wa) < 0.002 && abs(g.b - wb) < 0.002,
                   "OKLab reference \(hex)",
                   "got (\(String(format: "%.4f", g.L)) \(String(format: "%.4f", g.a)) "
                   + "\(String(format: "%.4f", g.b))), want (\(wl) \(wa) \(wb)) per Ottosson")
        }
    }

    // APCA: the canonical extremes, and — the point of including them — one pair in EACH
    // polarity. Every other APCA call in this file passes a dark background, so before this
    // the `yb > yt` branch (`ThemeContrast.swift`'s normBG/normTXT constants) was never
    // executed and a transposition there was undetectable. That was a real gap, not a
    // hypothetical: it was found by asking which lines the suite never reaches.
    for (t, b, want, why) in [("#000000", "#FFFFFF", 106.0, "black on white — dark-on-light branch"),
                              ("#FFFFFF", "#000000", 107.9, "white on black — light-on-dark branch"),
                              ("#888888", "#FFFFFF",  63.1, "mid-grey on white — dark-on-light"),
                              ("#888888", "#000000",  38.6, "mid-grey on black — light-on-dark")] {
        if let tc = RGB(hex: t), let bc = RGB(hex: b) {
            let got = APCA.lc(text: tc, background: bc)
            expect(abs(got - want) < 0.5, "APCA reference (\(why))",
                   "got Lc \(String(format: "%.2f", got)), want ~\(want)")
        }
    }

    // Dichromacy: structural invariants rather than published numbers, because no canonical
    // per-colour output exists to cite. These three still pin the LMS projection hard — a
    // transposed matrix breaks at least one of them.
    for grey in ["#000000", "#808080", "#FFFFFF"] {
        if let c = RGB(hex: grey) {
            for kind in CVD.Kind.allCases {
                let s = CVD.simulate(c, kind)
                let same = abs(s.r - c.r) < 0.01 && abs(s.g - c.g) < 0.01 && abs(s.b - c.b) < 0.01
                expect(same, "CVD invariant: grey \(grey) under \(kind.rawValue)",
                       "a grey has no chromatic content and must survive dichromacy unchanged")
            }
        }
    }
    if let r = RGB(hex: "#FF0000"), let g = RGB(hex: "#00FF00"),
       let bl = RGB(hex: "#0000FF"), let y = RGB(hex: "#FFFF00") {
        // Red/green MUST collapse under deuteranopia — that is the deficiency. If it does not,
        // the simulation is not simulating anything.
        let rgN = OKLab.distance(r, g)
        let rgD = OKLab.distance(CVD.simulate(r, .deuteranopia), CVD.simulate(g, .deuteranopia))
        expect(rgD < rgN * 0.65, "CVD invariant: red/green collapses",
               "normal dE \(String(format: "%.3f", rgN)) -> deuteranopic "
               + "\(String(format: "%.3f", rgD)); it should shrink substantially")
        // Blue/yellow MUST survive it — that axis is intact in dichromats.
        let byN = OKLab.distance(bl, y)
        let byD = OKLab.distance(CVD.simulate(bl, .deuteranopia), CVD.simulate(y, .deuteranopia))
        expect(byD > byN * 0.85, "CVD invariant: blue/yellow survives",
               "normal dE \(String(format: "%.3f", byN)) -> deuteranopic "
               + "\(String(format: "%.3f", byD)); it should be largely preserved")
    }
}
