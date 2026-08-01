#!/bin/bash
#
# Does a real shell run, render, and TALK BACK inside a real GhosttyPane?
#
# This is the libghostty probe's kill criterion made mechanical.
# `.afk/plans/emulator-foundation-probe-and-vendor-integrity.md:201` states it as: "no working
# shell rendering in `GhosttyPane` within 2 days ⇒ libghostty is not ready". Everything else in
# the swap is downstream of that sentence, so it should be a script rather than a memory of a
# demo someone once saw.
#
# WHAT IS UNDER TEST — the SHIPPED pane, not a restatement of it. The harness does
# `@testable import Umber` and links the module's own object files, so `GhosttyPane`,
# `GhosttyTerminalView`, `AppConfig` and `CursorStyle` are the real ones. That matters: the
# cheap version of this script would rebuild a libghostty surface inline with the same options
# GhosttyPane uses and assert THAT renders, which proves the engine works and proves nothing
# about our wiring — the exact "a check that restates the table proves only that the check
# agrees with itself" failure check-renderer-config.sh's header warns about. If the pane stops
# configuring its surface correctly, this goes red; a restating harness would not.
#
# WHY IT NEEDS A WINDOW SERVER. libghostty renders on the GPU and spawns its child through the
# `.exec` backend when a surface is attached to a view that is in a window. There is no
# headless path, so this is a GUI check like check-metal-renderer.sh and check-find-menu.sh.
# It uses `.accessory` activation and an offscreen frame, so it does NOT steal focus the way
# check-keys-e2e.sh does.
#
# THE CONTROL CASE IS THE REASON TO BELIEVE THE OTHERS. Case 5a asserts the shell reported a
# title within a timeout. On its own that is a claim a broken harness could make by accident — a
# stray title set by AppKit, a default that happens to be non-empty. So case 6 builds an
# identical pane, never calls `start()`, pumps the identical run loop for the identical duration,
# and requires SILENCE. If both fire, the harness is measuring something other than the shell and
# its verdict must be discarded — the same structure that makes check-altbuffer-resize.sh's two
# real cases worth believing.
#
# CASE 5b EXISTS BECAUSE THE DISJUNCTION IT WAS EXTRACTED FROM TOLD A LIE. Splitting `title ||
# OSC 7` into two cases did not merely make the gate stricter — it revealed that OSC 7 works.
# `pump` returns the moment its condition holds, and a zsh sends the title first, so the old
# combined condition stopped the run loop a beat before the OSC 7 sequence arrived and the gate
# printed `pwd=-` every time. PR #20's body dutifully recorded that as a corrected overclaim; the
# overclaim was correct and the correction was the artifact. A gate that cannot notice good news
# cannot notice the bad news sharing its channel.
#
# Usage:
#   ./Scripts/check-ghostty-pane.sh            # run all cases
#   ./Scripts/check-ghostty-pane.sh --quiet    # summary line and failures only
#
# Exit codes — the harness's own exit status, corroborated by its printed verdict. A status and
# verdict that disagree are treated as environmental, which is what closes the window where a
# crash AFTER printing "ALL-OK" read as green:
#   0  the pane builds, conforms, and a real shell renders and reports through it
#   1  a real failure — the kill criterion is unmet, or a conformance/mapping is wrong
#   2  environmental — no toolchain, no window server, no testable objects, harness would not
#      compile, or it died (before or after reporting). Never conflated with 1: a machine that
#      cannot run the check must not read as a green gate, and must not read as "libghostty is
#      not ready" either.

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { [[ "$QUIET" == "1" ]] || echo "$@"; }

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PRODUCTS="$ROOT/.build/out/Products/Debug"

command -v swiftc >/dev/null 2>&1 || {
  echo "error: swiftc not found — no Swift toolchain on PATH." >&2; exit 2; }

say "==> building (the harness links Umber's own objects, so they must be current)"
if ! swift build >/dev/null 2>&1; then
  echo "error: swift build failed — fix the build before running this gate." >&2
  swift build 2>&1 | grep -E 'error' | head -10 >&2
  exit 2
fi

# The testable variant is what exposes Umber's internal types to `@testable import`. A plain
# `swift build` refreshes it, but the directory carries a build-configuration hash, so glob for
# it rather than hardcoding one machine's.
TOBJ="$(find "$ROOT/.build/out/Intermediates.noindex" -type d \
  -path '*testable-t.build/Objects-normal/*' 2>/dev/null | head -1)"
[[ -n "$TOBJ" && -f "$TOBJ/GhosttyPane.o" ]] || {
  echo "error: no testable Umber objects under .build — cannot @testable import the real pane." >&2
  echo "  Looked for '*testable-t.build/Objects-normal/*/GhosttyPane.o'. Try: swift build" >&2
  exit 2; }
for o in GhosttyTerminal.o GhosttyKit.o libghostty.a; do
  [[ -e "$PRODUCTS/$o" ]] || { echo "error: $PRODUCTS/$o missing after build." >&2; exit 2; }
done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import AppKit
import GhosttyTerminal  // for TerminalCursorStyle — the type the pane's bridging maps ONTO
@testable import Umber

// Offscreen and non-activating: this gate must not steal the operator's focus.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var bad = 0
func fail(_ m: String) { print("FAIL \(m)"); bad += 1 }

@MainActor
func makePane(cwd: String) -> (GhosttyPane, NSWindow) {
    let pane = GhosttyPane(
        config: AppConfig.defaults(),
        frame: NSRect(x: 0, y: 0, width: 800, height: 400),
        workingDirectory: URL(fileURLWithPath: cwd))
    // Far offscreen rather than merely unmapped: libghostty needs a real window to attach a
    // surface to, and an ordered-out window does not reliably get one.
    let w = NSWindow(
        contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 400),
        styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView?.addSubview(pane.documentView)
    pane.documentView.frame = w.contentView!.bounds
    w.orderBack(nil)
    return (pane, w)
}

/// Pump the main run loop for `seconds`, returning early once `done()` is true.
@MainActor
func pump(_ seconds: Double, until done: () -> Bool = { false }) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if done() { return }
    }
}

MainActor.assumeIsolated {
    // ---- case 1: the pane constructs and satisfies SpaceDocument -----------------------
    let cwd = NSTemporaryDirectory()
    let (pane, win) = makePane(cwd: cwd)
    _ = win
    if pane.documentTitle != "Terminal" {
        fail("case1 title: expected the pre-OSC-0/2 fallback \"Terminal\", got \(pane.documentTitle)")
    }
    if pane.documentSymbolName != "terminal" {
        fail("case1 symbol: expected \"terminal\" (engine must not leak into the UI), "
             + "got \(pane.documentSymbolName)")
    }
    if pane.documentStatus != .idle { fail("case1 status: a fresh pane must be .idle") }
    if pane.documentIsEdited { fail("case1 edited: a terminal has no unsaved buffer") }
    if !pane.documentShouldClose() { fail("case1 close: a terminal must not veto a close") }

    // ---- case 2: it is reachable through the engine-agnostic seams ----------------------
    // The whole point of the SpaceDocument restructure is that the container never names a
    // concrete pane. If either cast fails, a Ghostty tab would render and then be invisible to
    // zoom fan-out (SpaceDocument) or to the file tree's "insert path" (ShellHosting).
    if (pane as? any SpaceDocument) == nil { fail("case2: GhosttyPane is not a SpaceDocument") }
    if (pane as? any ShellHosting) == nil { fail("case2: GhosttyPane is not a ShellHosting") }
    if (pane as? any SpaceDocumentReporting) == nil {
        fail("case2: GhosttyPane is not SpaceDocumentReporting — the container would leave its "
             + "documentDelegate nil and the tab would never retitle")
    }

    // ---- case 3: cursor-style bridging, all six cases -----------------------------------
    // CursorStyle.swift is Foundation-only and cannot name TerminalCursorStyle, so the
    // translation lives in GhosttyPane.swift and is only checkable here.
    let expected: [(CursorStyle, TerminalCursorStyle, Bool)] = [
        (.blinkBlock, .block, true), (.steadyBlock, .block, false),
        (.blinkUnderline, .underline, true), (.steadyUnderline, .underline, false),
        (.blinkBar, .bar, true), (.steadyBar, .bar, false),
    ]
    for (style, wantShape, wantBlink) in expected where
        style.ghosttyStyle != wantShape || style.blinks != wantBlink {
        fail("case3 cursor: \(style) -> \(style.ghosttyStyle)/blink=\(style.blinks), "
             + "want \(wantShape)/blink=\(wantBlink)")
    }

    // ---- case 4: ShellHosting answers before the shell has reported ---------------------
    // currentDirectory must fall back to the launch root, or a brand-new tab would answer nil
    // and `cd Here` would have nowhere to go.
    if pane.currentDirectory?.standardizedFileURL.path
        != URL(fileURLWithPath: cwd).standardizedFileURL.path {
        fail("case4 cwd fallback: expected the launch root \(cwd), "
             + "got \(pane.currentDirectory?.path ?? "nil")")
    }

    // ---- case 5a: THE KILL CRITERION — a real shell runs and reports --------------------
    // The title ALONE, deliberately. This used to be `title || OSC 7`, which meant no case in
    // the file could move if OSC 7 went from working to dead or from dead to working — the
    // disjunction was satisfied by the title either way. OSC 7 is asserted separately in 5b.
    pane.start()
    // Waits for the CONJUNCTION, then asserts the two halves separately. `||` was the bug (see
    // 5b); a fixed settling pump after the title would only have narrowed it, since the budget
    // for OSC 7 would then be a guess rather than the same 12s the title gets. `pump` still
    // returns the moment both have landed, so the common case costs nothing.
    pump(12.0) { !pane.currentTitle.isEmpty && pane.reportedDirectory != nil }
    let titled = !pane.currentTitle.isEmpty
    print("  shell reported: title=\(pane.currentTitle.isEmpty ? "-" : pane.currentTitle) "
          + "pwd=\(pane.reportedDirectory ?? "-")")
    if !titled {
        fail("case5a KILL CRITERION: no OSC 0/2 title within 12s — a shell did not come up in a "
             + "real GhosttyPane. This is the condition the probe plan says means libghostty is "
             + "not ready.")
    }

    // ---- case 5b: OSC 7 — the capability this engine is being evaluated FOR --------------
    // REQUIRED, and separating it from 5a is what made it visible at all. `pump` returns as soon
    // as its condition holds; the old condition was `title || pwd`, and a zsh sends the title
    // first — so the harness stopped pumping a beat before OSC 7 landed and printed `pwd=-`.
    // PR #20's body records that as "OSC 7 is wired but the gate reports pwd=-, so it is
    // inherited from the spike, not re-confirmed". THAT WAS AN ARTIFACT OF THIS HARNESS, not a
    // fact about libghostty: with the settling pump in 5a, OSC 7 arrives every run. The
    // disjunction was not merely weak, it was actively reporting a false negative — which is the
    // strongest argument in this file for why a gate must never fold two signals into one `||`.
    //
    // The PATH is asserted, not just its presence. A surface that reports the app's own cwd
    // instead of the pane's is the exact bug case 6 caught once already (a pane started in
    // `init` against default options), and it would sail through a nil-check.
    if titled {
        if let reported = pane.reportedDirectory {
            let want = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
            let got = URL(fileURLWithPath: reported).resolvingSymlinksInPath().path
            if got != want {
                fail("case5b OSC 7 reported the wrong directory: \(got), want \(want). The shell "
                     + "is talking, but not about this pane's root.")
            }
        } else {
            fail("case5b: no OSC 7 within 12s. This is the capability GhosttyPane's header "
                 + "names as the engine's advantage over TerminalPane, which has to ask the "
                 + "KERNEL for the same fact (ShellDirectory.swift). It was observed working at "
                 + "d22e7e8, so this is a regression — fix it, or make the header and AFK.md "
                 + "stop claiming it, before relaxing this case.")
        }
    }

    // ---- case 6: THE CONTROL — an unstarted pane must stay silent -----------------------
    let (quiet, win2) = makePane(cwd: cwd)
    _ = win2
    pump(12.0)  // identical duration, identical loop, no start()
    if !quiet.currentTitle.isEmpty || quiet.reportedDirectory != nil {
        fail("case6 CONTROL: a pane that was never started reported "
             + "title=\(quiet.currentTitle) pwd=\(quiet.reportedDirectory ?? "-"). "
             + "Case 5 is therefore measuring something other than the shell — DISCARD its "
             + "verdict and fix this harness.")
    }

    // ---- case 7: zoom is live and must not restart the shell ----------------------------
    // setFontSize goes through the controller, never through TerminalSurfaceOptions.fontSize,
    // because the latter is part of the options' isEquivalent and would REBUILD the surface —
    // discarding scrollback on every ⌘+. If the shell died here, that regressed.
    let before = pane.currentFontSize
    pane.setFontSize(before + 3, persist: false)
    if pane.currentFontSize != before + 3 {
        fail("case7 zoom: currentFontSize is \(pane.currentFontSize), want \(before + 3)")
    }
    pump(1.5)
    if !titled {
        // Said out loud rather than skipped silently: the assertion below needs a shell that
        // spoke BEFORE the font change to have anything to compare against, so when 5a failed
        // this is unevaluated — which is not the same as passing.
        print("  case7 rebuild assertion UNEVALUATED — case5a never reported a title")
    } else if pane.currentTitle.isEmpty {
        fail("case7 zoom rebuilt the surface: the shell had reported before the font change and "
             + "has gone silent after it — scrollback would be discarded on every ⌘+")
    }
    pane.resetFontSize()
    if pane.currentFontSize != AppConfig.defaults().font.pointSize {
        fail("case7 reset: ⌘0 must return to the configured size, "
             + "got \(pane.currentFontSize)")
    }

    print(bad == 0 ? "ALL-OK" : "SOME-FAILED")
}
// The EXIT CODE is the verdict; the printed line only corroborates it. This was `exit(0)`
// unconditionally, which made a stdout substring the sole channel — and the shell half then
// forgave a nonzero status whenever "ALL-OK" appeared anywhere in the output, so a crash during
// teardown AFTER the verdict printed read as a green gate. `check-metal-renderer.sh` never had
// that hole because it counts failures and exits on the count.
exit(bad == 0 ? 0 : 1)
SWIFT

OBJS=$(ls "$TOBJ"/*.o | grep -v '/main\.o$' | tr '\n' ' ')
if ! swiftc -o "$TMP/panecheck" "$TMP/main.swift" \
    -I "$TOBJ" -I "$PRODUCTS" -I "$PRODUCTS/include" -L "$PRODUCTS" \
    $OBJS "$PRODUCTS/SwiftTerm.o" "$PRODUCTS/GhosttyTerminal.o" "$PRODUCTS/GhosttyKit.o" \
    "$PRODUCTS/MSDisplayLink.o" "$PRODUCTS/libghostty.a" \
    -framework AppKit 2>"$TMP/compile.log"; then
  echo "error: the harness would not compile — the gate cannot run." >&2
  echo "  If this names a missing member on GhosttyPane, the pane's surface changed and this" >&2
  echo "  script is what needs updating. If it names a linker symbol, the object list above" >&2
  echo "  is stale." >&2
  grep -E 'error' "$TMP/compile.log" | head -10 | sed 's/^/    /' >&2
  exit 2
fi

out="$("$TMP/panecheck" 2>&1)"
status=$?

# Status and verdict must AGREE, and disagreement is environmental rather than a verdict. The
# harness exits 0 with ALL-OK or 1 with SOME-FAILED; anything else means it died — including
# dying after printing, which is why the status is checked and never forgiven by the substring.
if ! { [[ $status -eq 0 && "$out" == *"ALL-OK"* ]] \
    || [[ $status -eq 1 && "$out" == *"SOME-FAILED"* ]]; }; then
  echo "error: the harness exited $status without a matching verdict — treating as" >&2
  echo "  environmental. A crashed process is telling you about the machine (no window server," >&2
  echo "  no GPU), not about whether libghostty is ready. If it printed a verdict and STILL" >&2
  echo "  exited nonzero, it crashed during teardown — real, but not a statement about the pane." >&2
  echo "$out" | tail -12 | sed 's/^/    /' >&2
  exit 2
fi

echo "$out" | grep -E '^  (shell reported:|case7 rebuild assertion)' | sed 's/^/  /'
if [[ $status -eq 0 ]]; then
  say "  ok  pane constructs; SpaceDocument surface correct (title, symbol, status, close)"
  say "  ok  reachable as SpaceDocument, ShellHosting and SpaceDocumentReporting"
  say "  ok  all 6 cursor styles bridge to the right ghostty shape + blink"
  say "  ok  currentDirectory falls back to the launch root before OSC 7"
  say "  ok  KILL CRITERION: a real shell came up in a real GhosttyPane and set a title"
  say "  ok  OSC 7 arrived AND named this pane's root — the engine's advantage, now observed"
  say "  ok  control: an unstarted pane stayed silent for the same 12s"
  say "  ok  zoom is live — font changed without restarting the shell; ⌘0 restores"
  echo
  echo "all ghostty-pane cases passed (4 static + kill criterion + OSC-7 pin + control + zoom)"
  exit 0
fi

echo "✗ FAIL: GhosttyPane did not satisfy the probe's own criteria:" >&2
echo "$out" | grep -E '^FAIL' | sed 's/^/    /' >&2
exit 1
