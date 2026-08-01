#!/bin/bash
#
# Assert that an `engine` string in config.json maps to the TerminalEngine it names — and that
# an unrecognised one maps to NOTHING, so AppConfig.load() can warn and fall back to `.default`
# instead of silently picking one.
#
# WHAT IS UNDER TEST. `Sources/Umber/TerminalEngine.swift` only. That file is Foundation-only BY
# DESIGN — its header says so, for the same reason `Renderer.swift`'s is: the *decision* (which
# engine a string names) is a pure mapping, kept apart from *acting* on it, which lives in
# `SpaceViewController+DocumentConstruction.swift` — the one file that names both `TerminalPane`
# and `GhosttyPane` concretely. A pure mapping compiles headless with swiftc: no NSView, no GPU,
# no window server, no `swift build`. Same trick check-renderer-config.sh plays on Renderer.swift,
# check-cursor-style.sh on CursorStyle.swift, check-keybindings.sh on KeyBindings.swift,
# check-cwd-follow.sh on ShellDirectory.swift. Compiling the SHIPPED file, not a copy of it, is
# the whole point: a check that restates the table proves only that the check agrees with itself.
#
# WHY IT EXISTS AT ALL. `TerminalEngine.swift`'s own header names the failure this prevents:
# `"engine": "ghosty"` (a dropped `t`) reads correctly as JSON, parses without a throw — the
# config layer is fail-soft per-field by design (see `Config.swift`'s header) — and silently
# falls back to `.default` (`.swiftTerm`). The user then evaluates the wrong emulator core for a
# week and reports on it. Nothing before this script would have caught the transcription slip:
# the mapping is a hand-maintained switch (`TerminalEngine.swift:68-77`), not a vendor API, so it
# can only go wrong by human typo and can only be caught by a check that types the same strings
# back at it.
#
# WHY SEPARATE FROM check-renderer-config.sh. Same technique, different file, different table.
# `Renderer` and `TerminalEngine` are hand-maintained independently — one enum, one switch, one
# file each — so folding this into the renderer gate would make a change to either table able to
# silently stop covering the other. Two small gates, each named for the one table it owns, is the
# same call this project already made for check-cursor-style.sh alongside check-renderer-config.sh.
#
# WHAT THIS DOES NOT COVER. `config.engine` is read exactly once, at document construction
# (`SpaceViewController+DocumentConstruction.swift:46-52`; the warning text itself lives at
# `Config.swift:290-295`). That call site imports AppKit and cannot be compiled standalone, so it
# has no gate. This script only proves the string-to-case decision is correct in isolation; it
# says nothing about whether ⌘T actually consults it, the same accepted-unverified boundary
# `check-cwd-follow.sh`'s header draws around `setRoot(_:)`.
#
# Usage:
#   ./Scripts/check-engine-config.sh            # run all cases
#   ./Scripts/check-engine-config.sh --quiet    # summary line and failures only
#
# Exit codes:
#   0  every documented spelling and alias maps as promised, every unknown one is rejected
#   1  a real failure — a mapping, the falsification pin, the round-trip, or the default is wrong
#   2  environmental — no swiftc, source file missing, or a harness that would not compile.
#      Never conflated with 1: a broken environment must not read as a green gate.

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { [[ "$QUIET" == "1" ]] || echo "$@"; }

cd "$(dirname "$0")/.."
SRC="Sources/Umber/TerminalEngine.swift"

command -v swiftc >/dev/null 2>&1 || {
  echo "error: swiftc not found — no Swift toolchain on PATH." >&2
  exit 2
}
[[ -f "$SRC" ]] || { echo "error: $SRC missing." >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Swift only allows top-level code in a file literally named main.swift, hence the subdir rather
# than a descriptive filename (same layout check-renderer-config.sh uses).
mkdir -p "$TMP/pure"
cat > "$TMP/pure/main.swift" <<'SWIFT'
import Foundation

var bad = 0
func expect(_ raw: String, _ want: TerminalEngine?, _ label: String) {
    let got = TerminalEngine.named(raw)
    if got != want {
        print("FAIL \(label): TerminalEngine.named(\"\(raw)\") -> \(String(describing: got)), "
              + "want \(String(describing: want))")
        bad += 1
    }
}

// The two canonical spellings TerminalEngine.swift's own doc comment promises, and the only two
// `Config.swift`'s warning text can ever name back via `configName`.
expect("swiftterm", .swiftTerm, "canonical swiftterm")
expect("ghostty", .ghostty, "canonical ghostty")

// Every alias TerminalEngine.named's switch lists (TerminalEngine.swift:70-73), asserted one at
// a time so a dropped alias fails on its own line rather than hiding behind a passing neighbour.
expect("swift-term", .swiftTerm, "hyphenated alias")
expect("swift", .swiftTerm, "short alias")
expect("legacy", .swiftTerm, "semantic alias — the name that predates a second engine existing")
expect("libghostty", .ghostty, "dependency-name alias (the SPM package's own name)")
expect("lib-ghostty", .ghostty, "hyphenated dependency-name alias")

// Case-insensitivity and underscore-to-hyphen normalisation, exercised across BOTH canonical
// spellings and aliases — a user typing "SwiftTerm" (Swift's own type-name casing) or
// "swift_term" (a shell-variable habit) must land in the same place as the forms above.
expect("SwiftTerm", .swiftTerm, "case folded canonical")
expect("GHOSTTY", .ghostty, "case folded canonical (upper)")
expect("Swift-Term", .swiftTerm, "case folded alias")
expect("Legacy", .swiftTerm, "case folded alias")
expect("swift_term", .swiftTerm, "underscore folded to hyphen")
expect("lib_ghostty", .ghostty, "underscore folded to hyphen (alias)")
expect("LIBGHOSTTY", .ghostty, "case folded alias (libghostty)")

// The failures that must STAY failures. nil is what lets AppConfig.load() append a warning and
// fall back to `.default`; a mapping that guessed here would turn a typo into a silent engine
// switch — precisely the "evaluates the wrong engine for a week" scenario TerminalEngine.swift's
// own header names.
expect("ghosty", nil, "the exact typo TerminalEngine.swift's header warns about — dropped t")
expect("", nil, "empty string rejected")
expect("GHOSTTY ", nil, "trailing space not silently trimmed")
expect("swift term", nil, "bare space is not normalised — only \"_\" folds to \"-\"")

// --- Falsification pin -------------------------------------------------------------------
// Every "canonical" expect() above already fails if named(_:)'s two switch branches are
// swapped. This pair is asserted independently anyway, as the one edit a future reader should
// make BY HAND to confirm the gate is not vacuous: in TerminalEngine.swift, trade the two
// `return` statements —
//     case "swiftterm", "swift-term", "swift", "legacy": return .ghostty    (was .swiftTerm)
//     case "ghostty", "libghostty", "lib-ghostty":       return .swiftTerm  (was .ghostty)
// — and both assertions below flip from passing to failing, which is what makes this gate fail
// rather than pass vacuously. Done and reverted while writing this script (the dispatching
// session's transcript records the exit code and the restored `git diff`); re-run it by hand
// again if in doubt.
if TerminalEngine.named("ghostty") == .swiftTerm {
    print("FAIL falsification-pin: named(\"ghostty\") resolved to .swiftTerm")
    bad += 1
}
if TerminalEngine.named("swiftterm") == .ghostty {
    print("FAIL falsification-pin: named(\"swiftterm\") resolved to .ghostty")
    bad += 1
}

// configName must round-trip, because it is the exact spelling AppConfig.load()'s warning
// tells the user to type back. Driven off allCases so a third engine cannot leave this behind.
for e in TerminalEngine.allCases where TerminalEngine.named(e.configName) != e {
    print("FAIL round-trip: \(e).configName = \"\(e.configName)\" does not map back to \(e)")
    bad += 1
}

// configNames is what Config.swift:294's warning interpolates. Checked both for non-emptiness
// AND for actually enumerating every case — derived from allCases, not a hardcoded count, so
// adding a third engine tomorrow cannot leave the user-facing message silently behind.
if TerminalEngine.configNames.isEmpty {
    print("FAIL configNames: empty, so AppConfig.load()'s warning would name no valid engines")
    bad += 1
}
for e in TerminalEngine.allCases where !TerminalEngine.configNames.contains(e.configName) {
    print("FAIL configNames: \"\(e.configName)\" missing from \"\(TerminalEngine.configNames)\"")
    bad += 1
}

// The default is the conservative one on purpose (TerminalEngine.swift:46-55): the incumbent
// with years of use and three locally-fixed upstream defects, over a probe with open gates
// (the Phase 5 reflow gate, the kitty-keyboard guard, the multi-hour soak). Flipping it is a
// deliberate decision for Phase 5 to make — never something that drifts in silently.
if TerminalEngine.default != .swiftTerm {
    print("FAIL default: TerminalEngine.default is \(TerminalEngine.default), expected .swiftTerm")
    bad += 1
}

print(bad == 0 ? "ALL-OK" : "SOME-FAILED")
SWIFT

if ! swiftc -O -o "$TMP/enginecheck" "$SRC" "$TMP/pure/main.swift" 2>"$TMP/compile.log"; then
  echo "error: $SRC would not compile standalone — the gate cannot run." >&2
  echo "  That file is Foundation-only on purpose so this is possible. If it now needs" >&2
  echo "  AppKit, SwiftTerm, or libghostty, the pure decision and the live action have been" >&2
  echo "  re-merged and the split that made TerminalEngine.swift checkable is gone — that is" >&2
  echo "  the thing to fix, not this script." >&2
  sed 's/^/    /' "$TMP/compile.log" >&2
  exit 2
fi

out="$("$TMP/enginecheck" 2>&1)"; status=$?
# BOTH the exit status and the verdict string, and neither alone is sufficient here.
#
# The string alone was the bug (PR #21 review, item 2): a harness that printed ALL-OK and then
# crashed exits nonzero while that substring is still sitting in $out, so a substring-only test
# reads a crash as a green gate. Not hypothetical — it is the defect check-ghostty-pane.sh
# shipped with, falsified there by patching its harness to SIGABRT after printing its verdict and
# watching the old logic exit 0. Both sibling gates added in this PR already do it right
# (check-command-outcome.sh:136-139, check-pane-teardown.sh:292-303).
#
# The status alone would be worse still, because THIS harness has no exit() — it prints ALL-OK or
# SOME-FAILED and falls off the end of main.swift, which exits 0 either way. So the substring is
# what catches a failed mapping and the status is what catches a crash, and dropping either one
# blinds the gate to a whole class of failure.
if [[ $status -eq 0 && "$out" == *"ALL-OK"* ]]; then
  say "  ok  every documented spelling and alias maps as promised; unknown values rejected"
  say "  ok  configName round-trips for every case; configNames enumerates both; default is swiftterm"
  say "  ok  falsification pin: swapping the switch's two branches would be caught"
  echo
  echo "all engine-config cases passed (18 mappings + falsification pin + round-trip + default)"
  exit 0
fi

# A harness that died rather than judged is telling you about the machine, not about the mapping
# — the same 1-vs-2 split check-pane-teardown.sh:298-302 draws, and the reason this script's
# header promises 2 is never conflated with 1. A crash leaves no FAIL line to print, so the
# absence of a verdict is what distinguishes the two.
if [[ $status -ne 0 && "$out" != *"FAIL "* ]]; then
  echo "error: the harness died before judging (exit $status) — treating as environmental." >&2
  echo "$out" | sed 's/^/    /' >&2
  exit 2
fi

echo "✗ FAIL: $SRC's config-string mapping is wrong:" >&2
echo "$out" | sed 's/^/    /' >&2
exit 1
