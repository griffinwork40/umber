# mac-terminal

A native macOS terminal, written in Swift/AppKit, with **no AI features** — built
to host [`agent-afk`](https://github.com/griffinwork40/agent-afk)'s REPL properly.

The "no AI" part is a deliberate design constraint, not an omission. The agent
lives *in* the terminal; the terminal itself should be a fast, correct, native
window that gets out of the way. The bar is that it be beautiful and
user-friendly as hell before it is clever.

Personal project. `MacTerminal` in the source is a **placeholder name** — only
`app/Scripts/make-app-bundle.sh` and the `Info.plist` it generates reference it.

## Status — v0.1

Launchable and usable. Not yet daily-driven long enough to trust.

**Works:** real `.app` bundle (ad-hoc signed) · your login shell (`$SHELL -l`, so
your real `PATH` and rc files load) · **native macOS window tabs**, which means
⌘⇧[ / ⌘⇧] cycling, the tab overview, drag-to-reorder, drag-out-to-detach and
Merge All Windows all work without being implemented · JSON config with live
reload (⌘R) and per-field soft failure · font sizing · full screen ·
copy/paste/select-all · window position restored across launches · Tokyo Night
by default.

**Not built:** splits · app icon · preferences UI (config is a JSON file) · shell
integration (OSC 7/133) · search · URL clicking · profiles.

**No test target.** Verification so far is a deleted Step 0 gate harness (results
retained in the plan, below) plus use.

## Build and run

```sh
cd app
./Scripts/make-app-bundle.sh release   # omit "release" for a debug build
open build/MacTerminal.app
```

`swift run MacTerminal` is a faster iteration loop, but the bundle is what you
want for real use — Dock icon, Spotlight, behaves like an app rather than a
stray process.

First stop after launching is **⌘,**, which writes a commented starter config to
`~/.config/macterminal/config.json` and opens it. **⌘R** reloads it live.

## Layout

| Path | What |
|------|------|
| `app/` | The application. SwiftPM package, five source files. See `app/README.md` for configuration reference and the dependency note. |
| `vendor/SwiftTerm` | **Gitignored.** Upstream SwiftTerm v1.15.0 plus one local patch. Recreation is documented in `app/README.md` — it needs `chmod -R u+w`, since SPM checkouts are read-only. |
| `.afk/plans/native-swift-terminal-afk-host.md` | Plan of record: approach, cited evidence, rejected alternatives, and the Step 0 gate results. Read it before making structural changes. |

There is no `.xcodeproj` — the project is deliberately all text, so it stays
diffable and scriptable.

## Known risks

**SwiftTerm [#494](https://github.com/migueldeicaza/SwiftTerm/issues/494) is
open** — "buffer reflow produces duplicate/orphan lines when narrowing
terminal". Three deterministic reflow tests could not reproduce it, so it is
*reduced, not closed*; the reporter describes an intermittent defect. If
duplicated or orphaned lines ever appear after narrowing a window with
scrollback present, that is #494, and `TerminalPane.sizeChanged` is the hook to
instrument. This is the one bug that would invalidate the premise.

**G6 — the multi-hour soak — is not closed.** It can only be retired by real
daily use, not by a test.
