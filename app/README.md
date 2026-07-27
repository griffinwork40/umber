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

## Checks

There is no test target: this app is mostly AppKit glue, and what has actually
broken here is *observable state* — the font that silently fell back to Menlo, the
collapsed scrollbar thumb, the key that wrote no bytes — none of which a unit test
of pure logic would have caught. So the checks are two scripts and a diagnostic
env var, each aimed at something that has really gone wrong:

```sh
./Scripts/check-keybindings.sh   # truth table for the ⌘ line-editing map — fast, headless
./Scripts/check-keys-e2e.sh      # real NSEvents → real pty bytes; opens a window,
                                 # needs Accessibility permission for your terminal
MT_DIAG=1 swift run MacTerminal   # dumps resolved font/theme/scrollback state to stderr
```

## What works today (v0.1)

- Real `.app` bundle, ad-hoc signed
- Your login shell (`$SHELL -l`, so your real `PATH` and rc files load)
- **Native macOS window tabs** — ⌘T for a tab, ⌘N for a window. Because these
  are real system tabs, ⌘⇧[ / ⌘⇧] cycling, the tab overview, drag-to-reorder,
  drag-out-to-detach, and Merge All Windows all work without being implemented.
- Config file with live reload (⌘R), full screen (⌘F)
- **Font sizing that sticks** — ⌘+ / ⌘- zoom every tab at once and the level
  survives new tabs and relaunches; ⌘0 clears the zoom and hands control back
  to `font.size`. Default is 14pt
- **Mac line-editing keys** — ⌘⌫ deletes to the start of the line, ⌘⌦ to the
  end, ⌘←/⌘→ jump to the ends of the line. macOS resolves these to text-view
  selectors (`deleteToBeginningOfLine:`, …) that SwiftTerm drops, so ⌘⌫ used to
  write nothing at all and ⌘←/⌘→ moved by *word* — already ⌥←/⌥→'s job. They now
  send the readline bytes (`^U ^K ^A ^E`) that bash, zsh, fish and afk's own REPL
  all bind to those operations
- Copy/paste/select-all, window position restored across launches
- **No palette installed by default** — and that is the considered choice, not a
  gap. SwiftTerm generates ANSI indices 16–255 by interpolating between the
  terminal's background and foreground (`.base16Lab`), so installing *any* custom
  background or foreground silently replaces the standard 256-colour cube with
  synthesised approximations. Leaving it alone keeps the colours every other
  terminal shows. `afk-dark` and `tokyo-night` remain one config line away

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
  "font": { "family": "SF Mono", "size": 16 },
  "cursor": "block",
  "scrollback": 1000,
  "optionAsMeta": true,
  "theme": { "preset": "afk-dark", "cursor": "#E67E4C" }
}
```

Omit `theme` entirely — the default — and no colours are installed at all.

| Field | Notes |
|---|---|
| `font.family` | Any installed monospaced family. Omitted, or set to `SF Mono`/`system`, gives the system monospaced face (SF Mono) — the default. An unavailable family warns and falls back to it. Note `NSFont(name: "SF Mono")` returns nil, so SF Mono is only reachable via that alias, never by name |
| `font.size` | Points, **6–48**, default **14**. Out of range warns and uses the default rather than silently clamping. ⌘+ / ⌘- zoom on top of this and persist; ⌘0 clears the zoom so this value applies again |
| `cursor` | `block`, `steady-block`, `bar`, `steady-bar`, `underline`, `steady-underline` |
| `scrollback` | Lines retained, default `1000`. `0` disables it. Raising it is not free: SwiftTerm sizes the scrollbar thumb as `max(rows / lines, 0.01)`, so past ~3,500 lines the thumb sticks at the 1% floor and stops tracking position, and `Buffer.resize` walks every line three times on each window resize |
| `shell` | Defaults to `$SHELL`. Must be executable or it is ignored |
| `optionAsMeta` | `true` makes Option act as Meta instead of typing accented characters |
| `theme` | **Omitted by default.** Present at all ⇒ colours get installed, which regenerates ANSI 16–255 out of your bg/fg. See the note above |
| `theme.preset` | `afk-dark`, `tokyo-night`, or `classic`. `classic` means "install nothing", identical to omitting `theme`. Other fields override the preset; supplying colours without a preset bases them on `afk-dark` |
| `theme.ansi` | **Exactly 16** colours, 8 normal then 8 bright. SwiftTerm's `installColors` silently no-ops on any other length, so a wrong count is rejected with a warning instead |

Both former defaults survive as presets — no hex-pasting required:

```json
"theme": { "preset": "tokyo-night" }
```

`tokyo-night` was the v0.1 default, `afk-dark` briefly replaced it. Either
installs a full palette, with the 256-colour trade-off described above.

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
