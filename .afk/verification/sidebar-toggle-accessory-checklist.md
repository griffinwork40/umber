# Verification Checklist — Discoverable Sidebar Toggle Button

Written before implementation (TDD-equivalent for a no-test-target Swift/AppKit
app — see `AFK.md:42`). Two automated gates must stay green; the rest is a
pass/fail manual walkthrough run once the build succeeds.

## Automated

- [x] `cd app && swift build` exits 0, zero new warnings attributable to
      `SidebarToggleAccessory.swift` or the touched lines of
      `SpaceWindowController.swift`.
- [x] `./Scripts/check-file-size.sh` exits 0; `SidebarToggleAccessory.swift` and
      `SpaceWindowController.swift` both print under the 350-line ceiling
      (`SpaceWindowController.swift` expected ~311–313).

## Manual (`swift run Umber`)

Launch smoke passed on 2026-08-05: after correcting the invalid `.leading`
layout attribute and wrapping the button in a fixed-footprint root view, the app
remained alive until the 12-second command timeout instead of raising AppKit's
`_auxiliaryViewFrameChanged:` assertion. Visual and interaction items remain for
a human-attended pass.

- [ ] (a) Button visible in the titlebar's leading edge, beside the traffic
      lights, on every newly opened Space window, with no menu opened first.
- [ ] (b) Clicking it collapses/expands the sidebar with the same animation and
      `NSSplitViewItem` state ⌘B produces (spot-check both directions).
- [ ] (c) Hovering shows a "Toggle Sidebar" tooltip.
- [ ] (d) Accessibility Inspector (or `ax` dump) reports a non-empty, meaningful
      label for the button.
- [ ] (e) Open a second Space as a native tab (⌘N), switch between tabs, and
      confirm exactly one accessory button is visible per frontmost tab — not
      stacked/duplicated.
- [ ] (f) Regression: ⌘B and View → Toggle Sidebar still behave identically to
      before this change.
- [ ] (g) No other icon/button appearance regression around the traffic lights
      across light/dark themes and `umber`/`afk-light`/`classic` presets (quick
      visual spot-check only).

## Blockers to watch for

1. Titlebar accessory rendering unverified against this exact window config
   (opaque titlebar, no `.fullSizeContentView`, native tabs) — if `.leading`
   renders misaligned or overlapping the traffic lights, flag before switching
   to the sidebar-header fallback.
2. Tab-stacking behavior unverified — confirm one accessory per window, not
   accumulating across tabs.
3. LOC headroom is tight — keep `SpaceWindowController.swift`'s edit to one call
   + a short comment.
