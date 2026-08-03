#!/bin/bash
#
# Assert that the shipped `umber` palette is measurably legible — and that the rules
# doing the asserting are strict enough to reject a palette known to be bad.
#
# WHAT IS UNDER TEST. `Sources/Umber/ThemeValues.swift`, `Sources/Umber/ThemeContrast.swift`
# and `Sources/Umber/SyntaxPalette.swift` only. All three are Foundation-only BY DESIGN — their
# headers say so — precisely so they can be
# compiled here with swiftc and never link AppKit, SwiftTerm, or the app. Same trick
# check-renderer-config.sh plays on Renderer.swift and check-cwd-follow.sh plays on
# ShellDirectory.swift. Compiling the SHIPPED files, not copies, is the whole point: a check
# that restates the palette proves only that the check agrees with itself.
#
# WHY IT EXISTS. Every claim a theme makes about itself — "legible", "colour-blind safe",
# "the bright colours are actually brighter" — is a number, and a number nobody computed is
# a taste claim wearing a lab coat. Measured with this code, the well-regarded palettes fail
# badly and silently: Solarized Dark's comment colour is APCA Lc 0.0 (invisible), Tokyo
# Night's and Nord's are 10.3, and Tokyo Night, Catppuccin, Nord and Rosé Pine all ship
# *identical* values in their normal and bright chromatic slots, so bold text — which
# SwiftTerm draws from the bright half by default — is indistinguishable from plain. None of
# that is visible by reading hex. This gate is how Umber's palette avoids joining them.
#
# WHAT IT CANNOT REACH. Everything that needs AppKit: whether `Theme.swift` actually hands
# these values to either engine, whether `installColors` took, the sidebar's git tints (which
# are macOS system colours by design and deliberately do NOT follow the theme —
# GitStatus+Presentation.swift argues why), and anything about how the palette LOOKS. The
# last one is real: four automated search passes each satisfied more constraints than the
# last while producing, in order, noise, pastels, neon, and a green that measured well and
# read as mint. The rendered previews in .afk/research/theme-design-2026-08-03/ are the
# record of that, and taste remains a human gate. This script guards the floor, not the bar.
#
# Usage:
#   ./Scripts/check-theme-contrast.sh            # run all cases
#   ./Scripts/check-theme-contrast.sh --quiet    # summary line and failures only
#
# Exit codes:
#   0  every palette parses, and `umber` meets every contrast, ring and colour-vision rule
#   1  a real failure — a threshold missed, a palette that will not parse, a preset that is
#      unreachable from config, or the falsification case PASSING (which would mean the
#      thresholds are too loose for any of the other results to mean anything)
#   2  environmental — no swiftc, a source file missing, or a harness that would not compile.
#      Never conflated with 1: a broken environment must not read as a green gate.

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { [[ "$QUIET" == "1" ]] || echo "$@"; }

cd "$(dirname "$0")/.."

VALUES="Sources/Umber/ThemeValues.swift"
CONTRAST="Sources/Umber/ThemeContrast.swift"
SYNTAX="Sources/Umber/SyntaxPalette.swift"
HARNESS="Scripts/check-theme-contrast-harness.swift"
SYNHARNESS="Scripts/check-theme-contrast-syntax.swift"
THEME="Sources/Umber/Theme.swift"

command -v swiftc >/dev/null 2>&1 || {
  echo "error: swiftc not found — no Swift toolchain on PATH." >&2
  exit 2
}
for f in "$VALUES" "$CONTRAST" "$SYNTAX" "$HARNESS" "$SYNHARNESS" "$THEME"; do
  [[ -f "$f" ]] || { echo "error: $f not found (run from the app/ directory)." >&2; exit 2; }
done

# A pure file that has quietly acquired a UI import is a real regression in the split that
# makes this gate possible, so name it as that rather than as a compile error later.
for f in "$VALUES" "$CONTRAST" "$SYNTAX"; do
  if grep -qE '^\s*import\s+(AppKit|SwiftUI|Cocoa|SwiftTerm|GhosttyTerminal)' "$f"; then
    echo "error: $f imports a UI framework — it is supposed to be Foundation-only." >&2
    echo "  That split is the only reason this gate can compile it standalone. Fix the" >&2
    echo "  import, not this script." >&2
    exit 2
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pure"
cp "$HARNESS" "$TMP/pure/main.swift"

if ! swiftc -O -o "$TMP/themecheck" "$VALUES" "$CONTRAST" "$SYNTAX" "$SYNHARNESS" \
     "$TMP/pure/main.swift" \
     2>"$TMP/compile.log"; then
  echo "error: the pure theme sources would not compile standalone — the gate cannot run." >&2
  sed 's/^/    /' "$TMP/compile.log" >&2
  exit 2
fi

# The harness's EXIT CODE is the verdict. It also prints ALL-OK, but trusting the string
# alone would let a crash *after* the verdict read as a pass — a bug that really shipped in
# check-ghostty-pane.sh, where the shell forgave any status if ALL-OK appeared anywhere.
out="$("$TMP/themecheck" 2>&1)"; status=$?

if [[ $status -ne 0 && $status -ne 1 ]]; then
  echo "error: the harness died with status $status rather than reporting a verdict." >&2
  echo "$out" | sed 's/^/    /' >&2
  exit 2
fi

if [[ $status -eq 1 ]]; then
  echo "✗ FAIL: the shipped palette does not meet its own stated rules:" >&2
  echo "$out" | sed 's/^/    /' >&2
  exit 1
fi

if [[ "$out" != *"ALL-OK"* ]]; then
  echo "error: harness exited 0 without printing a verdict — cannot confirm it ran." >&2
  echo "$out" | sed 's/^/    /' >&2
  exit 2
fi

# Reachability from config lives in Theme.preset(named:), which imports AppKit and so cannot
# be linked into the harness. Grep it instead: a preset nobody can select is invisible, and
# a name that resolves to nothing silently falls back to a DIFFERENT theme with a warning.
#
# Comments are stripped FIRST, and the match is anchored to a `case` line. The obvious
# version of this check — grep for the bare quoted name — was written first and was BLIND:
# every preset name also appears in a doc comment in this file (`"preset": "umber"`), so
# deleting the real switch case still passed. Found by deliberately deleting it; the lesson
# is that a grep-based assertion has to match the CONSTRUCT, not the vocabulary.
STRIPPED="$TMP/theme-nocomments.swift"
sed -e 's|//.*$||' "$THEME" > "$STRIPPED"
missing=()
for name in umber afk-dark tokyo-night; do
  grep -qE "^[[:space:]]*case[[:space:]].*\"$name\"" "$STRIPPED" || missing+=("$name")
done
if (( ${#missing[@]} )); then
  echo "✗ FAIL: preset(s) not reachable from config in $THEME: ${missing[*]}" >&2
  echo "    ThemePalette.all lists them, but Theme.preset(named:) has no case, so" >&2
  echo "    \"theme\": {\"preset\": \"${missing[0]}\"} would warn and fall back." >&2
  exit 1
fi

# CONSTANT-DRIFT GUARD. The harness measures the tab strip's derived colours from its own
# copies of three constants, and asserts the app's DEFAULT palette. If either file drifts,
# the harness keeps passing while testing numbers the app no longer draws — which is worse
# than having no harness, because it reads as a green gate.
#
# Comments are stripped before matching, for the same reason as the preset check below and
# with a sharper edge here: the rationale comment beside `textAlpha` names the OLD value
# (0.55) and the new one, so a naive grep would match prose and pass whatever the code said.
DRAW="Sources/Umber/DocumentTabStrip+Drawing.swift"
[[ -f "$DRAW" ]] || { echo "error: $DRAW not found." >&2; exit 2; }
STRIP_DRAW="$TMP/draw-nocomments.swift"
STRIP_CFG="$TMP/config-nocomments.swift"
sed -e 's|//.*$||' "$DRAW" > "$STRIP_DRAW"
sed -e 's|//.*$||' "Sources/Umber/Config.swift" > "$STRIP_CFG"

drift=()
grep -qE 'isActive \? 0\.95 : 0\.72' "$STRIP_DRAW" \
  || drift+=("tab label alpha is no longer 'isActive ? 0.95 : 0.72' — update ALPHA_ACTIVE/ALPHA_INACTIVE in the harness")
grep -qE 'blended\(withFraction: 0\.07' "$STRIP_DRAW" \
  || drift+=("railBackground no longer lifts by 0.07 — update RAIL_LIFT in the harness")
grep -qE '^[[:space:]]*theme: \.umber,' "$STRIP_CFG" \
  || drift+=("AppConfig.defaults() no longer installs .umber — the gate's floors no longer describe what the app ships by default")

# CONSUMER GUARD. A measured colour with no consumer is the failure this repo has already
# shipped once: `ThemePalette.selection` was designed, measured and asserted from the day the
# palettes landed, and for the whole time it reached NOTHING — `Theme` had no such field, so
# the value could not cross the AppKit bridge even in principle, and no check noticed because
# every check was about the number rather than about its reaching anything. Measuring a colour
# nobody draws is the same class of error as drawing a colour nobody measured.
#
# So: assert the wiring exists. Necessarily a grep — `Theme.swift` and the pane import AppKit
# and cannot be linked here — and therefore weak: it proves the expression is present, not
# that a selected range renders in it. That remains daily-drive territory. Comments stripped
# first and matched on the CONSTRUCT for the reason the preset check below documents at length.
VIEWER="Sources/Umber/FileViewerPane+Document.swift"
[[ -f "$VIEWER" ]] || { echo "error: $VIEWER not found." >&2; exit 2; }
STRIP_VIEWER="$TMP/viewer-nocomments.swift"
STRIP_THEME="$TMP/theme-nocomments-fields.swift"
sed -e 's|//.*$||' "$VIEWER" > "$STRIP_VIEWER"
sed -e 's|//.*$||' "$THEME" > "$STRIP_THEME"
grep -qE 'selection = NSColor\.fromHex\(palette\.selection\)' "$STRIP_THEME" \
  || drift+=("Theme no longer builds .selection from the palette — the measured value has stopped crossing the AppKit bridge, which is exactly how it went unused before")
grep -qE 'selectedTextAttributes' "$STRIP_VIEWER" \
  || drift+=("FileViewerPane no longer sets selectedTextAttributes — the editor has stopped consuming theme.selection and nothing else does")
if (( ${#drift[@]} )); then
  echo "✗ FAIL: the harness's assumptions have drifted from the shipped code:" >&2
  for d in "${drift[@]}"; do echo "    - $d" >&2; done
  exit 1
fi

say "  ok  all 3 shipped palettes parse; 16 ANSI entries each"
say "  ok  WCAG luminance agrees with the WCAG 2.1 definition on a fixed vector"
say "  ok  APCA loClip confirmed, so ANSI 0 is judged by OKLab distance not by APCA"
say "  ok  umber: warm background, dark chrome, body text Lc >= 85"
say "  ok  umber: every ANSI slot clears its role floor (comments Lc >= 48)"
say "  ok  umber: all 8 normal->bright pairs separated and correctly ordered"
say "  ok  umber: colour-vision floors met, incl. tier-1 red/green >= 0.105"
say "  ok  falsification: xterm's #0000EE on black is correctly REJECTED"
say "  ok  every shipped preset is reachable from config"
say "  ok  tab-strip chrome measured for all 3 palettes; harness constants match the shipped ones"
say "  ok  syntax roles: distinct non-surface slots, readable in all 3 palettes, comments dimmer"
say "  ok  syntax clamp: both branches reachable (umber raw, tokyo-night clamped) and it raises Lc"
echo
echo "${out%%$'\n'*}"
echo "all theme-contrast cases passed"
exit 0
