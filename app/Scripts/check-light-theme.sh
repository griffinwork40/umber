#!/bin/bash
#
# check-light-theme.sh — the shipped palettes are well-formed, and `afk-light` is
# actually light enough to flip the window chrome.
#
# WHAT IS UNDER TEST. `Sources/Umber/ThemeCatalog.swift` only. That file is
# Foundation-only BY DESIGN — its header says so — precisely so it can be compiled on
# its own with swiftc and never link AppKit or SwiftTerm. Same trick
# check-renderer-config.sh plays on Renderer.swift and check-cursor-style.sh plays on
# CursorStyle.swift. Compiling the SHIPPED file, not a copy of its values, is the whole
# point: a check that restates the palette proves only that the check agrees with itself.
#
# `Theme.swift` is deliberately NOT the subject and cannot be: it imports AppKit *and*
# SwiftTerm, so `swiftc Sources/Umber/Theme.swift` exits 1 on `no such module 'SwiftTerm'`
# and nothing in it has ever been gateable. That is why the palettes and the luminance
# formula were moved out — the split is what created something checkable.
#
# WHY IT EXISTS AT ALL. `AppConfig.appearance` (`Config.swift:141`) derives the window's
# light/dark chrome from the theme background's relative luminance:
#
#     NSAppearance(named: effectiveBackground.relativeLuminance > lightChromeCutoff
#                        ? .aqua : .darkAqua)
#
# So a "light" preset whose background lands at or below that cutoff installs its
# colours and leaves the sidebar, titlebar and scrollers DARK. The result is a config
# line that parses, warns about nothing, and half-works — the quietest possible failure
# and exactly the class check-renderer-config.sh exists to prevent for `renderer`.
# Nothing else in this repo can catch it, because the deciding comparison lives in a
# file that imports AppKit. Case 2 below is that assertion, and it is why this script
# exists; the other six are there to stop case 2 passing for the wrong reason.
#
# WHAT THIS CANNOT SEE, stated plainly the way check-cwd-follow.sh states its blindness:
# it never renders a pixel. It cannot tell you the sidebar's vibrant material actually
# changed, that the tab strip picked the right rail blend, that the caret is visible
# inside a selection, or that `.aqua` chrome looks right against #FFFFFF. Those import
# AppKit and are UMBER_DIAG and daily-drive territory. It also says nothing about ANSI
# 16-255: Umber pins `ansi256PaletteStrategy = .xterm` (`TerminalPane.swift:165`) so
# those 240 indices are the emulator's fixed xterm cube, not ours — and being dark-tuned,
# many of them are low-contrast on a white background. That is a known, documented
# limitation (app/README.md), not something this gate can measure or fix.
#
# Usage:
#   ./Scripts/check-light-theme.sh            # run all cases
#   ./Scripts/check-light-theme.sh --quiet    # summary line and failures only
#
# Exit codes:
#   0  every palette is well-formed, afk-light flips the chrome, the dark ones do not,
#      and every content slot is legible on its own background
#   1  a real failure — a malformed palette, a light theme that would render dark
#      chrome, a broken luminance formula, or an illegible slot
#   2  environmental — no swiftc, source file missing, or a harness that would not
#      compile. Never conflated with 1: a broken environment must not read as a green
#      gate.

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { [[ "$QUIET" == "1" ]] || echo "$@"; }

cd "$(dirname "$0")/.."
SRC="Sources/Umber/ThemeCatalog.swift"

command -v swiftc >/dev/null 2>&1 || {
  echo "error: swiftc not found — no Swift toolchain on PATH." >&2
  exit 2
}
[[ -f "$SRC" ]] || { echo "error: $SRC missing." >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Swift only allows top-level code in a file literally named main.swift, hence the subdir
# rather than a descriptive filename.
mkdir -p "$TMP/pure"
cat > "$TMP/pure/main.swift" <<'SWIFT'
import Foundation

var bad = 0
func fail(_ m: String) { print("FAIL \(m)"); bad += 1 }

// ---- 1. Every shipped hex parses, and every palette is exactly 16 long. ----
// SwiftTerm's installColors is a NO-OP unless the array is exactly 16
// (`vendor/SwiftTerm/Sources/SwiftTerm/Terminal.swift:717-723`), so a 15-entry preset
// would install bg/fg and silently keep the previous palette. This case is also what
// makes `Theme.init(_:)`'s force-unwraps safe: it parses every literal before ship.
for t in ThemeCatalog.all {
    if t.ansi.count != 16 { fail("\(t.configName): ansi has \(t.ansi.count) entries, need exactly 16") }
    for (i, h) in ([t.background, t.foreground, t.cursor] + t.ansi).enumerated() {
        if ThemeCatalog.luminance(hex: h) == nil { fail("\(t.configName): slot \(i) '\(h)' is not parseable hex") }
    }
}

// ---- 2. THE KILL CRITERION. ----
// `AppConfig.appearance` (`Config.swift:140-142`) picks .aqua only when
// background.relativeLuminance > lightChromeCutoff. A "light" preset whose background
// lands at or below that cutoff installs its colours and leaves the sidebar, titlebar
// and scrollers dark — a config line that parses, warns about nothing, and half-works.
// This is the assertion the whole feature rests on.
let cutoff = ThemeCatalog.lightChromeCutoff
func assertSide(_ name: String, wantLight: Bool) {
    guard let t = ThemeCatalog.named(name), let l = ThemeCatalog.luminance(hex: t.background) else {
        fail("\(name): not resolvable, or its background is not hex"); return
    }
    let isLight = l > cutoff
    if isLight != wantLight {
        fail("\(name): background \(t.background) luminance \(String(format: "%.5f", l)) "
             + "is \(isLight ? "ABOVE" : "at or BELOW") the \(cutoff) cutoff, so chrome would be "
             + "\(isLight ? "light" : "DARK") — wanted \(wantLight ? "light" : "dark")")
    }
}
assertSide("afk-light", wantLight: true)

// ---- 3. CONTROL for case 2. ----
// Both dark presets must stay BELOW the cutoff. If a bug made `luminance` return
// something monotonic-but-wrong (or a constant above the cutoff), the light assertion
// above would pass for the wrong reason and this catches it. A gate that can only say
// "yes" is measuring nothing.
assertSide("afk-dark", wantLight: false)
assertSide("tokyo-night", wantLight: false)

// ---- 4. The formula itself, against values computable by hand. ----
// Guards the gamma expansion specifically: a version that skipped it would return
// 0.5 for mid-grey instead of 0.21586, and would still order the presets correctly —
// so cases 2 and 3 would both stay green while every contrast number was wrong.
if abs(ThemeCatalog.luminance(red: 1, green: 1, blue: 1) - 1.0) > 1e-9 { fail("luminance(white) != 1.0") }
if abs(ThemeCatalog.luminance(red: 0, green: 0, blue: 0)) > 1e-9 { fail("luminance(black) != 0.0") }
if let g = ThemeCatalog.luminance(hex: "#808080"), abs(g - 0.2158605) > 1e-5 {
    fail("luminance(#808080) = \(g), want ~0.21586 — the gamma expansion is missing or wrong")
}

// ---- 5. Name resolution, and the values that must stay unresolvable. ----
for t in ThemeCatalog.all where ThemeCatalog.named(t.configName)?.configName != t.configName {
    fail("round-trip: '\(t.configName)' does not resolve back to itself")
}
if ThemeCatalog.named("afklight")?.configName != "afk-light" { fail("'afklight' should fold to afk-light") }
if ThemeCatalog.named("AFK-Light")?.configName != "afk-light" { fail("case folding") }
// `classic` MUST stay nil — it is the one accepted value meaning "install nothing".
// `AppConfig.load()` (`Config.swift:215-219`) distinguishes it from a typo by testing
// the raw string BEFORE resolving, so merging the two nils in a tidy-up would turn a
// mistyped preset into a silent no-theme.
if ThemeCatalog.named("classic") != nil { fail("'classic' must resolve to nil, not a preset") }
if ThemeCatalog.named("bogus") != nil { fail("unknown preset must resolve to nil so load() can warn") }
if !ThemeCatalog.configNames.contains("classic") { fail("configNames must name 'classic' — the warning lists it") }
if !ThemeCatalog.configNames.contains("afk-light") { fail("configNames must name 'afk-light'") }

// ---- 6. Legibility of the light palette against its OWN background. ----
// Dark-theme ANSI on a light background is the failure this preset exists to avoid, so
// assert it is actually avoided rather than assuming the source was good. WCAG 3.0 is
// the floor for non-body marks; the twelve slots below are the ones a TUI colours text
// with (0/7/8/15 are structural bg/fg tones and are exempt).
func contrast(_ a: String, _ b: String) -> Double {
    guard let x = ThemeCatalog.luminance(hex: a), let y = ThemeCatalog.luminance(hex: b) else { return 0 }
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
let contentSlots = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14]
if let light = ThemeCatalog.named("afk-light") {
    for i in contentSlots {
        let c = contrast(light.ansi[i], light.background)
        if c < 3.0 {
            fail("afk-light ANSI \(i) (\(light.ansi[i])) is CR \(String(format: "%.2f", c)) on "
                 + "\(light.background) — below the WCAG 3.0 floor, i.e. illegible")
        }
    }
    if contrast(light.foreground, light.background) < 4.5 {
        fail("afk-light foreground is below WCAG AA 4.5 on its own background")
    }
}

// ---- 7. CONTROL for case 6. ----
// The dark palette on the LIGHT background must FAIL the same test — that is the entire
// reason a separate light preset is needed rather than reusing afk-dark. If a dark
// palette read as legible on white, the contrast function is not measuring contrast and
// every green assertion in case 6 is void.
if let dark = ThemeCatalog.named("afk-dark"), let light = ThemeCatalog.named("afk-light") {
    let illegible = contentSlots.filter { contrast(dark.ansi[$0], light.background) < 3.0 }
    if illegible.count < 4 {
        fail("CONTROL: only \(illegible.count) afk-dark ANSI slots are illegible on "
             + "\(light.background). Expected many. The contrast function is not measuring contrast.")
    }
}

print(bad == 0 ? "ALL-OK" : "SOME-FAILED")
SWIFT

if ! swiftc -O -o "$TMP/lightcheck" "$SRC" "$TMP/pure/main.swift" 2>"$TMP/compile.log"; then
  echo "error: $SRC would not compile standalone — the gate cannot run." >&2
  echo "  That file is Foundation-only on purpose so this is possible. If it now needs" >&2
  echo "  AppKit or SwiftTerm, the palettes-as-data and the live NSColor bridging have" >&2
  echo "  been re-merged and the split that made ThemeCatalog.swift checkable is gone —" >&2
  echo "  that is the thing to fix, not this script." >&2
  sed 's/^/    /' "$TMP/compile.log" >&2
  exit 2
fi

out="$("$TMP/lightcheck" 2>&1)"
if [[ "$out" == *"ALL-OK"* ]]; then
  say "  ok  every shipped hex parses; every palette is exactly 16 colours"
  say "  ok  afk-light clears the lightChromeCutoff, so the window chrome goes .aqua"
  say "  ok  afk-dark and tokyo-night stay below it — the cutoff still discriminates"
  say "  ok  luminance is gamma-expanded: white 1.0, black 0.0, #808080 ~0.21586"
  say "  ok  every preset name round-trips; classic and typos both stay nil"
  say "  ok  all 12 content slots clear WCAG 3.0 on afk-light's own background"
  say "  ok  control: afk-dark's ANSI is illegible on white, as it must be"
  echo
  echo "all light-theme cases passed (7 cases over 3 presets)"
  exit 0
fi

echo "✗ FAIL: $SRC's palettes or luminance maths are wrong:" >&2
echo "$out" | sed 's/^/    /' >&2
exit 1
