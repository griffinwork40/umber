# Verification Checklist — Discoverable Sidebar Toggle Button

Written before implementation (TDD-equivalent for a no-test-target Swift/AppKit
app — see `AFK.md:42`). Everything mechanically checkable has since moved into
`app/Scripts/check-sidebar-toggle.sh`; what is left here is the part no harness
in this repo can reach, which is pixels.

## Automated

- [x] `cd app && swift build` exits 0, zero new warnings attributable to
      `SidebarToggleAccessory.swift` or the touched lines of
      `SpaceWindowController.swift`.
- [x] `./Scripts/check-file-size.sh` exits 0; `SidebarToggleAccessory.swift` and
      `SpaceWindowController.swift` both print under the 350-line ceiling.
- [x] `./Scripts/check-sidebar-toggle.sh` exits 0 — five cases: the accessory is
      installed exactly once, the button's shape (nil target, `toggleSidebar:`,
      accessibility label, tooltip, image), the button's OWN action resolving to
      a live responder, `isCollapsed` flipping in both directions, and a control
      case proving the rig can return nil.

## Manual (`swift run Umber`)

**Correction, 2026-08-05.** An earlier draft of this file recorded the launch
smoke as passing "after correcting the invalid `.leading` layout attribute and
wrapping the button in a fixed-footprint root view". That attributed one
observation to two simultaneous changes, and the first of them was not a fix at
all: `.leading` is valid for an app linked on 10.12 or later
(`NSTitlebarAccessoryViewController.h:27`), this app links against macOS 14, and
`.leading` was since observed attaching and pumping a run loop cleanly at
`-target arm64-apple-macos14`. So the container wrap was the whole fix, which is
also the only story consistent with the assertion actually raised —
`_auxiliaryViewFrameChanged:` is AppKit refusing a *moved accessory origin*, and
an `NSButton` used as the root view has alignment-rect insets that invite
exactly that. See the reasoning already written at
`SidebarToggleAccessory.swift` `loadView()`. This repo ships control cases in
`check-altbuffer-resize.sh` and a falsification case in
`check-metal-renderer.sh` precisely so a two-variable change cannot be read as a
one-variable result; that discipline was not applied to this file's own evidence
until now.

Items (b), (c) and (d) below, plus the functional half of (a), are now asserted
mechanically on every run of `check-sidebar-toggle.sh` and are ticked on that
basis. What remains is visual, and no gate in this repo can see a pixel.

- [x] (b) Clicking it collapses/expands the sidebar with the same
      `NSSplitViewItem` state ⌘B produces, in both directions — gate case 4.
      The *animation* itself is still only ever seen by a human.
- [x] (c) A "Toggle Sidebar" tooltip is set — gate case 2. Whether it actually
      appears on hover is AppKit's business and remains unobserved.
- [x] (d) A non-empty accessibility label is set — gate case 2. Whether
      VoiceOver reads it usefully in context is not something the gate can say.
- [ ] (a) Button **visible** in the titlebar's leading edge, beside the traffic
      lights, on every newly opened Space window, with no menu opened first.
      (That it is *installed* on every window is gate case 1; that it is
      *drawn where a person expects* is this item.)
- [ ] (e) Open a second Space as a native tab (⌘N), switch between tabs, and
      confirm exactly one accessory button is visible per frontmost tab — not
      stacked/duplicated.
- [ ] (f) Regression: ⌘B and View → Toggle Sidebar still behave identically to
      before this change.
- [ ] (g) No other icon/button appearance regression around the traffic lights
      across light/dark themes and `umber`/`afk-light`/`classic` presets (quick
      visual spot-check only).

## Known limits, not blockers

1. **No state indication.** The glyph is static — it never distinguishes
   collapsed from expanded. Finder does the same, so this matches the platform
   rather than missing a feature; noted so nobody "fixes" it by accident.
2. **Absent in full screen.** `grep NSToolbar` matches nothing app-wide, so
   there is no toolbar to host the control; a `.left` accessory lives in the
   titlebar strip, which auto-hides in full screen (⌃⌘F, `AppMenu.swift:195-199`).
   The affordance disappears exactly where the menu bar is also hidden.
3. **Tab-stacking visuals unverified** — item (e). Only one window's titlebar is
   ever visible per native tab group, so duplication is not expected, but that
   is an inference about AppKit rather than an observation.
