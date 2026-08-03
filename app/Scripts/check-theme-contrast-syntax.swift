//
//  check-theme-contrast-syntax.swift
//  The syntax-role assertions for check-theme-contrast.sh, and their falsification.
//
//  A THIRD file rather than a longer harness, for the same reason there was a second one:
//  §5k took the assertions past this repo's 350-line ceiling, and the documented response to
//  the ceiling is to find the seam rather than shave comments. The seam here is obvious — the
//  syntax roles are the one section whose subject is a different shipped file
//  (`SyntaxPalette.swift`) rather than a palette or a derived piece of chrome.
//
//  Compiled as a plain module file, NOT as main.swift: Swift only allows top-level statements
//  in a file literally named main.swift, so this cannot be a second script of statements.
//  `expect` is taken as a PARAMETER rather than read as a main.swift global — the counters and
//  the failure list stay owned by the harness, and the dependency is visible in the signature
//  instead of resting on the subtlety that main.swift's top-level `var`s are module-scope.
//  That is the pattern `check-theme-contrast-registry.swift` uses (PR #24); one pattern per
//  gate is worth more than either file's independent preference.
//
//  Both functions are called from main.swift at the point their section used to occupy, so the
//  section order a reader follows is still 1…6.
//

import Foundation

/// §5k — the syntax role mapping, asserted for ALL THREE palettes.
func checkSyntaxRoles(_ expect: (Bool, String, String) -> Void) {
    // ------------------------------------- 5k. the editor's SYNTAX roles, all palettes
    // `SyntaxPalette` maps five syntax roles onto slots of whichever ANSI ring is installed,
    // rather than adding five hex literals per palette. Asserted for ALL THREE palettes for the
    // same reason §5j is: the MAPPING is app policy, not a palette's property, so a failure here
    // is the mapping's fault and must not be launderable by relaxing the rule for one theme.
    //
    // This is the section that made the mapping choosable at all. All 360 assignments of the four
    // chromatic roles to the six chromatic ANSI slots were measured
    // (.afk/research/editor-syntax-2026-08-03/rank_mappings.py); the optimum is a 24-way tie whose
    // members all use exactly {green, yellow, blue, cyan}, because red and magenta measure Lc 41.4
    // under afk-dark and are therefore unreadable there. Convention broke the tie.
    let syntaxRoles = SyntaxRole.allCases
    // 5k-i. Structural: a role must not read from a slot that is not text. ANSI 0 is a surface
    // (§5d holds it 0.05…0.14 from the background — that is furniture, not a glyph), and 7/15 ARE
    // the plain foreground, so a role wearing one is a role you cannot see as a role.
    for role in syntaxRoles {
        let i = SyntaxPalette.ansiIndex(for: role)
        expect(i != 0 && i != 7 && i != 15, "syntax role \(role.rawValue) slot",
               "reads ansi[\(i)], which is a surface (0) or plain text (7/15), not a colour")
        expect(i >= 0 && i < 16, "syntax role \(role.rawValue) slot", "ansi[\(i)] is out of range")
    }
    // 5k-ii. Distinctness: two roles sharing a slot is a mapping that silently merges two
    // meanings. Cheap to assert, impossible to see by reading the switch.
    expect(Set(syntaxRoles.map(SyntaxPalette.ansiIndex(for:))).count == syntaxRoles.count,
           "syntax role slots", "two roles share an ANSI slot: "
           + syntaxRoles.map { "\($0.rawValue)=\(SyntaxPalette.ansiIndex(for: $0))" }.joined(separator: " "))
    // 5k-iii…v. Per palette: readable, distinguishable, and de-emphasised in the right direction.
    for p in ThemePalette.all {
        guard let pbg = RGB(hex: p.background), let pfg = RGB(hex: p.foreground) else { continue }
        let resolved = SyntaxPalette.resolved(for: p)
        expect(resolved.count == syntaxRoles.count, "\(p.name) syntax resolution",
               "resolved \(resolved.count) of \(syntaxRoles.count) roles — a palette hex did not parse")
        let bodyLc = APCA.lc(text: pfg, background: pbg)
        for role in syntaxRoles {
            guard let c = resolved[role] else { continue }
            // Every role must be readable at ANY size. This is the floor the tab strip's inactive
            // label was raised to clear, and code is smaller and denser than a tab label.
            let lc = APCA.lc(text: c, background: pbg)
            expect(lc >= SyntaxPalette.readableFloor, "\(p.name) syntax \(role.rawValue)",
                   "\(c.hex) is APCA Lc \(String(format: "%.1f", lc)) against the background, below "
                   + "the Lc \(Int(SyntaxPalette.readableFloor)) floor for text readable at any size")
        }
        // A comment must read as SECONDARY. Legible is not enough: a comment as prominent as code
        // inverts the emphasis the colour exists to express.
        if let comment = resolved[.comment] {
            let cLc = APCA.lc(text: comment, background: pbg)
            expect(bodyLc - cLc >= 15, "\(p.name) syntax comment emphasis",
                   "comment Lc \(String(format: "%.1f", cLc)) vs body \(String(format: "%.1f", bodyLc)) "
                   + "— only \(String(format: "%.1f", bodyLc - cLc)) Lc apart, so comments do not read "
                   + "as de-emphasised")
        }
        // Adjacent roles must be tellable apart. `let x: Int = 3` puts keyword, type and number on
        // one line; `{"k": 1}` puts string beside number. dE-OK 0.05 is the floor for "not the
        // same colour" — well below the 0.085 ring rule, because these are simultaneous rather
        // than remembered comparisons.
        for (x, y) in [(SyntaxRole.keyword, SyntaxRole.type), (.string, .number),
                       (.keyword, .string), (.type, .number), (.comment, .keyword)] {
            guard let cx = resolved[x], let cy = resolved[y] else { continue }
            let de = OKLab.distance(cx, cy)
            expect(de >= 0.05, "\(p.name) syntax \(x.rawValue)/\(y.rawValue)",
                   "dE-OK \(String(format: "%.3f", de)) — \(cx.hex) and \(cy.hex) are effectively "
                   + "the same colour, so the two roles are not distinguishable")
        }
    }
    // 5k-vi. Umber alone carries the DESIGN floors, exactly as §5e/§5g do: the two ports fail
    // several (tokyo-night's string/number collapses to dichromatic dE 0.011, green vs yellow) and
    // that is a property of a verbatim port, not of this mapping. Pinned at the measured values so
    // umber cannot silently degrade toward them.
    let uSyntax = SyntaxPalette.resolved(for: .umber)
    for (x, y, floor) in [(SyntaxRole.keyword, SyntaxRole.type, 0.100),
                          (.string, .number, 0.100), (.keyword, .string, 0.200),
                          (.type, .number, 0.100), (.comment, .type, 0.060)] {
        guard let cx = uSyntax[x], let cy = uSyntax[y] else { continue }
        let w = CVD.worstDistance(cx, cy)
        expect(w >= floor, "Umber syntax CVD \(x.rawValue)/\(y.rawValue)",
               "worst dichromacy dE-OK \(String(format: "%.3f", w)) < \(floor)")
    }
    // 5k-vii. BOTH branches of the comment clamp must still be reachable. Without this the
    // fallback could rot untested the moment a palette changed, which is the failure
    // check-metal-renderer.sh guards against by hiding its own shader: a branch nothing exercises
    // is a branch nothing verifies. umber's ANSI 8 was DESIGNED as a comment colour (Lc 51.5) and
    // must be used as-is; tokyo-night ships Lc 10.3 and must be clamped.
    if let ubg = RGB(hex: ThemePalette.umber.background),
       let uAnsi8 = RGB(hex: ThemePalette.umber.ansi[8]) {
        expect(APCA.lc(text: uAnsi8, background: ubg) >= SyntaxPalette.readableFloor,
               "clamp reachability (umber takes the ANSI-8 path)",
               "umber's ANSI 8 measures Lc \(String(format: "%.1f", APCA.lc(text: uAnsi8, background: ubg)))"
               + " — it would now be clamped, so the un-clamped path is untested")
        expect(uSyntax[.comment].map { $0.hex == uAnsi8.hex } ?? false,
               "clamp reachability (umber comment is ANSI 8)",
               "umber's comment resolved to \(uSyntax[.comment]?.hex ?? "nil"), not its ANSI 8 "
               + "\(uAnsi8.hex)")
    }
    if let tbg = RGB(hex: ThemePalette.tokyoNight.background),
       let tAnsi8 = RGB(hex: ThemePalette.tokyoNight.ansi[8]) {
        expect(APCA.lc(text: tAnsi8, background: tbg) < SyntaxPalette.readableFloor,
               "clamp reachability (tokyo-night takes the fallback)",
               "tokyo-night's ANSI 8 now measures Lc "
               + "\(String(format: "%.1f", APCA.lc(text: tAnsi8, background: tbg))) — nothing "
               + "exercises the clamp any more")
        expect(SyntaxPalette.resolved(for: .tokyoNight)[.comment].map { $0.hex != tAnsi8.hex } ?? false,
               "clamp reachability (tokyo-night comment is clamped)",
               "tokyo-night's comment resolved to its raw ANSI 8 despite being below the floor")
    }
}

/// §6, the syntax half — the rules above must be able to FAIL.
func checkSyntaxFalsification(_ expect: (Bool, String, String) -> Void) {
    // The syntax rules need their own falsification, because §5k's per-palette floors are the
    // only place in this file where a rule is applied to values the palettes do not state
    // literally — a clamp that silently returned its input would satisfy every "is it readable"
    // assertion above by measuring the colour it was supposed to replace.
    if let tbg = RGB(hex: ThemePalette.tokyoNight.background),
       let raw = RGB(hex: ThemePalette.tokyoNight.ansi[8]),
       let clamped = SyntaxPalette.resolved(for: .tokyoNight)[.comment] {
        // (a) The floor must REJECT the canonical bad comment colour. Tokyo Night's ANSI 8 is the
        // field's representative failure, the same role #0000EE plays for blue in §6 above.
        expect(APCA.lc(text: raw, background: tbg) < SyntaxPalette.readableFloor,
               "falsification (syntax floor)",
               "tokyo-night's raw ANSI 8 \(raw.hex) PASSES the readable floor at Lc "
               + "\(String(format: "%.1f", APCA.lc(text: raw, background: tbg))) — the floor is too "
               + "loose for the clamp results above to mean anything")
        // (b) The clamp must move the number the right way. Asserted rather than assumed because
        // `composited(over:alpha:)` toward a DARK foreground would reduce contrast, and the
        // assertions in 5k would still pass if the fallback happened to clear 45 by luck.
        expect(APCA.lc(text: clamped, background: tbg) > APCA.lc(text: raw, background: tbg),
               "falsification (clamp direction)",
               "clamping took Lc \(String(format: "%.1f", APCA.lc(text: raw, background: tbg))) to "
               + "\(String(format: "%.1f", APCA.lc(text: clamped, background: tbg))) — it did not improve "
               + "legibility, so it is not a minimum-contrast clamp")
    }
    // (c) And the role-distinctness rule must reject a colour against itself.
    if let c = RGB(hex: "#9ECE6A") {
        expect(OKLab.distance(c, c) < 0.05, "falsification (syntax distinctness)",
               "two identical colours were not rejected by the 0.05 role-separation rule")
    }
}
