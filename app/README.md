# MacTerminal

A native macOS terminal, in Swift, with no AI features. Built to host
[`agent-afk`](https://github.com/griffinwork40/agent-afk) well.

`MacTerminal` is a **placeholder name** — rename freely. Only
`Scripts/make-app-bundle.sh` and the `Info.plist` it generates reference it.

Step 2 of [`../.afk/plans/native-swift-terminal-afk-host.md`](../.afk/plans/native-swift-terminal-afk-host.md).

## Build and run

```sh
./Scripts/make-app-bundle.sh          # debug
./Scripts/make-app-bundle.sh release  # optimised
open build/MacTerminal.app
```

Or, for a quick iteration loop without bundling:

```sh
swift run MacTerminal
```

The bundle path is what you want for real use — it gets a Dock icon, appears in
Spotlight, and behaves like an app rather than a stray process.

## What works today (v0.1)

- Real `.app` bundle, ad-hoc signed
- Your login shell (`$SHELL -l`, so your real `PATH` and rc files load)
- **Native macOS window tabs** — ⌘T for a tab, ⌘N for a window. Because these
  are real system tabs, ⌘⇧[ / ⌘⇧] cycling, the tab overview, drag-to-reorder,
  drag-out-to-detach, and Merge All Windows all work without being implemented.
- Config file with live reload (⌘R), font sizing (⌘+ / ⌘- / ⌘0), full screen (⌘F)
- Copy/paste/select-all, window position restored across launches
- Tokyo Night by default, because it should look good before you configure it

## Not built yet

Splits. A real app icon. Preferences UI (config is a JSON file). Shell
integration (OSC 7/133). Search. URL clicking. Profiles.

## Configuration

Lives at `~/.config/macterminal/config.json`. It does not exist until you create
it — **Settings… (⌘,) writes a commented starter file** and opens it. ⌘R reloads
without restarting.

Every field is optional and every field fails **soft**: a bad value degrades to
the default and prints a reason to stderr rather than crashing or silently doing
nothing. Verified — a config with six bad fields yields six warnings and a
working terminal.

```json
{
  "font": { "family": "SF Mono", "size": 13 },
  "cursor": "block",
  "scrollback": 10000,
  "optionAsMeta": true,
  "theme": {
    "background": "#1a1b26",
    "foreground": "#c0caf5",
    "cursor": "#c0caf5",
    "ansi": ["#15161e", "#f7768e", "…16 total…"]
  }
}
```

| Field | Notes |
|---|---|
| `font.family` | Any installed monospaced family. Omitted, or set to `SF Mono`/`system`, gives the system monospaced face (SF Mono) — the default. An unavailable family warns and falls back to it. Note `NSFont(name: "SF Mono")` returns nil, so SF Mono is only reachable via that alias, never by name |
| `cursor` | `block`, `steady-block`, `bar`, `steady-bar`, `underline`, `steady-underline` |
| `scrollback` | Lines retained. `0` disables scrollback |
| `shell` | Defaults to `$SHELL`. Must be executable or it is ignored |
| `optionAsMeta` | `true` makes Option act as Meta instead of typing accented characters |
| `theme.ansi` | **Exactly 16** colours, 8 normal then 8 bright. SwiftTerm's `installColors` silently no-ops on any other length, so a wrong count is rejected with a warning instead |

## Dependency note

Depends on `../vendor/SwiftTerm` — upstream **v1.15.0** with one local patch: the
optional Metal GPU shader is excluded from the build, because Xcode 26.6 moved
the Metal toolchain to a separate downloadable component that is not installed
here. The Core Text renderer is used instead; `MetalTerminalRenderer` probes for
the shader bundle at runtime and returns nil when absent, so nothing traps.

`vendor/` is gitignored. To recreate it: copy an upstream v1.15.0 checkout to
`vendor/SwiftTerm`, then `chmod -R u+w` it — SPM checkouts are read-only and the
patch will fail otherwise — and exclude the shader resource in its
`Package.swift` (the change is annotated in place).

To restore the stock dependency once
`xcodebuild -downloadComponent MetalToolchain` has run, change `Package.swift`
back to:

```swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0")
```

Note that **upstream** is correct here — CodeEdit pins `thecoolwinter/SwiftTerm`,
a fork last pushed 2025-07-17.

## Known upstream risk

[SwiftTerm #494](https://github.com/migueldeicaza/SwiftTerm/issues/494) —
"Buffer reflow produces duplicate/orphan lines when narrowing terminal" — is
**open**. The Step 0 harness could not reproduce it across three deterministic
reflow tests (evidence retained in `../.afk/plans/native-swift-terminal-afk-host.md`
§11; the harness itself has since been deleted), but the reporter describes an
intermittent defect, so it is reduced, not closed. If duplicated or orphaned lines ever appear after
narrowing a window with scrollback present, that is #494, and
`TerminalPane.sizeChanged` is the hook to instrument.
