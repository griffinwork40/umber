# Umber

## What This Is

A native macOS terminal written in Swift 6 / AppKit, deliberately with **no AI features** — built to host [`agent-afk`](https://github.com/griffinwork40/agent-afk)'s REPL properly. The agent lives *in* the terminal; the terminal is a fast, correct, native window that gets out of the way. The bar is "beautiful and user-friendly as hell" before clever. Rendering is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (vendored, v1.15.0 + one patch); everything else is ~7 small AppKit files. Personal project, private repo `griffinwork40/umber`, single `main` branch.

Naming: the app was renamed from MacTerminal to **Umber** on 2026-07-27 (commit `faf1291`). Code, scripts, bundle id, env var, and config path are all `umber`/`Umber`/`UMBER_` — but the **checkout directory and this repo's local path are still `mac-terminal`**. Remaining `MacTerminal`/`MT_DIAG` strings in `.afk/` are historical records, not stale code; `MacTerminalView` in `KeyBindings.swift` is SwiftTerm's own upstream type name.

## Commands

```sh
cd app
./Scripts/make-app-bundle.sh           # debug bundle → build/Umber.app
./Scripts/make-app-bundle.sh release   # optimised
open build/Umber.app

swift build                            # compile only
swift run Umber                        # fast iteration loop (no Dock icon / Spotlight)
UMBER_DIAG=1 swift run Umber           # + dump resolved font/theme/scrollback to stderr

./Scripts/check-keybindings.sh         # headless: compiles shipped KeyBindings.swift, runs a 17-case truth table
./Scripts/check-keys-e2e.sh            # real NSEvents → real pty bytes; LAUNCHES the app, steals focus
```

**There is no test target and no CI.** The two `check-*.sh` scripts plus `UMBER_DIAG` are the whole verification surface — see `app/README.md` ("Checks") for why. `check-keys-e2e.sh` needs Accessibility permission for the invoking terminal and exits `2` without it, `3` if the app never becomes frontmost. Prefer `check-keybindings.sh` for routine work; it is fast and headless.

There is no `.xcodeproj` by design — the project stays all-text, diffable, and scriptable. Do not add one.

## Architecture

| Path | Purpose |
|------|---------|
| `app/` | The application: SwiftPM package (`swift-tools-version: 6.0`, macOS 14+), 7 source files |
| `app/Sources/Umber/` | All Swift source |
| `app/Scripts/` | Bundle assembly + the two verification scripts |
| `vendor/SwiftTerm` | **Gitignored.** Upstream v1.15.0 + one local patch (Metal shader resource excluded). Recreation documented in `app/README.md` ("Dependency note") — needs `chmod -R u+w`, SPM checkouts are read-only |
| `.afk/plans/native-swift-terminal-afk-host.md` | **Plan of record** — approach, cited evidence, rejected alternatives, Step 0 gate results (§11). Read before any structural change |
| `.afk/research/naming-decision-2026-07-27.md` | Naming rationale and availability checks |

| Source file | Owns |
|-------------|------|
| `main.swift` | Manual `NSApplication` bootstrap — **not** `@main`. Sets `.regular` activation policy, assigns delegate, runs the loop |
| `AppDelegate.swift` | Lifecycle, the entire `NSMenu` tree (`buildMenu()`), config reload/open actions, app-wide zoom fan-out, the embedded starter-config template |
| `SpaceWindowController.swift` | One window == one native macOS tab == one **Space** (project root): `tabbingIdentifier`, `addTabbedWindow`, frame autosave, the static open-Space registry, title/subtitle. Owns no PTY and no documents |
| `SpaceViewController.swift` | The container — `NSSplitViewController` with a sidebar item (file tree) and the document area. Owns the document list, is `TerminalPaneDelegate`, fans config/zoom out. Nested private `DocumentAreaViewController` lays out strip + active document |
| `SpaceDocument.swift` | The `SpaceDocument` protocol (the seam heterogeneous tabs plug into) + `TerminalPane` conformance |
| `DocumentTabStrip.swift` | The hand-rolled in-window document tab strip: single-view custom drawing, rect hit-testing, hover, close/new affordances |
| `FileTreeViewController.swift` | Sidebar `NSOutlineView` + lazy `FileNode` tree, identity-preserving `refresh()` on window-became-key |
| `TerminalPane.swift` | The shell process + SwiftTerm view binding: `startProcess($SHELL, ["-l"])`, `apply(config:)`, font clamping/zoom, DECSCUSR cursor style, `LocalProcessTerminalViewDelegate` callbacks |
| `UmberTerminalView.swift` | `LocalProcessTerminalView` subclass whose only job is `performKeyEquivalent(with:)` interception (SwiftTerm declares `keyDown` `public`, not `open`) |
| `KeyBindings.swift` | Pure, view-free `MacLineEditing.controlBytes(keyCode:modifiers:)` — the single ⌘-chord → control-byte table |
| `Config.swift` | Hex parsing, `Theme` presets, private `ConfigFile` Decodable, `FontZoom` UserDefaults store, `AppConfig` defaults + fail-soft `load()` |

**There are two tab levels, on purpose** (plan §12.3, branch (C) — settled 2026-07-27).

- **Spaces = native macOS window tabs.** One `NSWindow` per project root. Because these are real system tabs, ⌘⇧[ / ⌘⇧] cycling, the tab overview, drag-to-reorder, drag-out-to-detach and Merge All Windows work without being implemented. **Do not replace this level with a custom tab bar** — it is load-bearing, and it is why (C) was chosen over a full in-window strip.
- **Documents = a hand-rolled strip** (`DocumentTabStrip`) inside each Space. This level *must* be custom: a system window tab **is** an `NSWindow`, so a mixed terminal/editor strip would give every document its own `contentView` and there could be no shared, full-height sidebar (plan §12.2). The strip is hidden at a single document so one-terminal Umber still just looks like a terminal.

Adding a new document kind (editor, diff, observer panel) means writing a `SpaceDocument` conformer — **not** touching the container. That is the whole payoff of the restructure.

**Keymap:** ⌘N new Space · ⌘⇧N new Space in a new window · ⌘T new document · ⌘W close document (falls through to the Space when it is the last) · ⌘⇧W close Space · ⌘⌥← / ⌘⌥→ cycle documents · ⌘1–⌘9 select document · ⌘B toggle sidebar · ⌘0 Actual Size (predates the above). ⌘⌥arrows are safe because `MacLineEditing.controlBytes` guards on `intent == [.command]` — *exact* equality — and `check-keybindings.sh` case 13 asserts ⌘⌥← passes through.

## Configuration

- On disk: `~/.config/umber/config.json`. Does not exist until created; **⌘,** writes a commented starter file and opens it, **⌘R** reloads live. The app never rewrites an existing file.
- UserDefaults: `Umber.fontSizeOverride` (live zoom), AppKit frame autosave `UmberWindow`. Bundle id `com.griffinlong.umber`.
- Full field reference (font, cursor, scrollback, shell, optionAsMeta, theme) is in `app/README.md` — including why **no palette is installed by default** (any theme regenerates ANSI 16–255 by interpolating bg/fg, replacing the standard 256-colour cube). Leave that default alone unless the change is deliberate.

## Conventions

- **Comments explain *why*, and cite their evidence** — vendor source lines (`Terminal.swift:725`), upstream issue numbers (SwiftTerm #494), cross-repo files, plan sections (`plan §4.1`). Match this density: nearly every non-obvious line carries a rationale. A patch with no *why* comment on a non-obvious line is under-written for this repo.
- **Config parsing fails soft, per field.** `AppConfig.load()` never throws: a bad value degrades to the default and appends a warning printed to stderr. Six bad fields ⇒ six warnings and a working terminal. Preserve this — do not introduce a throwing config path.
- **One source of truth for defaults**: `AppConfig.defaults()` and the `defaultFontSize` / `minFontSize` / `maxFontSize` statics in `Config.swift`. Read them; never re-hardcode.
- **Keybindings live in one table** (`KeyBindings.swift`), not scattered switches — deliberately, so `check-keybindings.sh` can compile the shipped file directly. Adding a chord means editing the table and the truth table.
- `@MainActor` on every type; `@preconcurrency` on the SwiftTerm conformance with an inline note why. No `Sendable` annotations.
- Force-unwraps are confined to compile-time-known constants (literal UTF-8, literal hex palettes). **No `try!`** — filesystem writes use `try?`. Keep it that way.
- `Umber` is the only prefix in code; the diagnostic env var is `UMBER_DIAG` (any non-nil value).
- Commit style: conventional-ish, lowercase, scope in parens, em-dash rationale — `feat(app): make font size actually configurable — 14pt default, zoom that sticks`.

## Known Risks

- **SwiftTerm [#494](https://github.com/migueldeicaza/SwiftTerm/issues/494) is OPEN** — "buffer reflow produces duplicate/orphan lines when narrowing terminal". Three deterministic reflow tests could not reproduce it, so it is *reduced, not closed*. If duplicate or orphaned lines ever appear after narrowing a window with scrollback present, that is #494 — instrument `TerminalPane.sizeChanged`. This is the one bug that would invalidate the project's premise.
- **G6, the multi-hour soak, is not closed.** It retires only through real daily use, never a test.
- Scrollback above ~3,500 lines pins SwiftTerm's scrollbar thumb at its 1% floor and makes `Buffer.resize` walk every line three times per window resize. Default is 1000 for that reason.
- **The plan doc still contains 3 absolute `/Users/griffinlong` paths** (one naming an unrelated fork). Scrub them before any `gh repo edit --visibility public`.

## Not Built Yet

Splits · app icon · preferences UI (config is a JSON file) · shell integration (OSC 7/133) · search · URL clicking · profiles. Next step per the plan is **Step 3 — Observer panel**.
