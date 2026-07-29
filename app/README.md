# Umber

A native macOS terminal, in Swift, with no AI features. Built to host
[`agent-afk`](https://github.com/griffinwork40/agent-afk) well.

Named **Umber**, after the warm earth pigment that matches its own accent colour
(`#E67E4C`, see `Sources/Umber/Config.swift`). See
[`../.afk/research/naming-decision-2026-07-27.md`](../.afk/research/naming-decision-2026-07-27.md)
for how that was chosen.

Step 2 of [`../.afk/plans/native-swift-terminal-afk-host.md`](../.afk/plans/native-swift-terminal-afk-host.md).

## Build and run

```sh
./Scripts/make-app-bundle.sh          # debug
./Scripts/make-app-bundle.sh release  # optimised
open build/Umber.app
```

Or, for a quick iteration loop without bundling:

```sh
swift run Umber
```

The bundle path is what you want for real use — it gets a Dock icon, appears in
Spotlight, and behaves like an app rather than a stray process.

## Checks

There is no test target: this app is mostly AppKit glue, and what has actually
broken here is *observable state* — the font that silently fell back to Menlo, the
collapsed scrollbar thumb, the key that wrote no bytes — none of which a unit test
of pure logic would have caught. So the checks are six scripts and a diagnostic
env var, each aimed at something that has really gone wrong:

```sh
./Scripts/verify-vendor.sh       # is vendor/SwiftTerm the pinned revision, WITH both patches?
./Scripts/check-file-size.sh     # enforces the 350-LOC ceiling on Sources/ + Scripts/ — headless
./Scripts/check-keybindings.sh   # truth table for the ⌘ line-editing map — fast, headless
./Scripts/check-space-restore.sh # truth table for OpenSpaceRoots (Space restore) — fast, headless
./Scripts/check-reflow.sh        # does narrowing corrupt scrollback? (#494) — headless
./Scripts/check-find-menu.sh     # do Undo/Redo/Find-and-Replace actually reach anything?
                                 # needs a GUI session; window is offscreen, steals no focus
./Scripts/check-keys-e2e.sh      # real NSEvents → real pty bytes; opens a window,
                                 # needs Accessibility permission for your terminal
UMBER_DIAG=1 swift run Umber   # dumps resolved font/theme/scrollback state to stderr
```

`verify-vendor.sh` runs first inside `make-app-bundle.sh`, and exists because the two
vendor failure modes were asymmetric. A **missing** `vendor/` fails loudly — SwiftPM
cannot resolve the path dependency. A **re-vendored but unpatched** tree failed
*silently*: it compiled and ran, because patch 0001 only drops a build-time resource, so
following the recreation steps below and forgetting the patch produced a green build
against a different dependency than the tested one. Nothing in git recorded otherwise —
`vendor/` is gitignored, `vendor/SwiftTerm` is not a git repo, `Package.resolved` is
ignored, and `Package.swift`'s path dependency is unpinned. Exit codes: `2` = present but
unpatched, `3` = unknown revision, `1` = missing vendor or missing pin.

It checks **two** files now, and both are hard failures. `Buffer.swift` was a warn-only
version tripwire until 2026-07-29, when patch `0002` made it load-bearing: a tree missing
that patch compiles, runs, passes every other check, and silently corrupts scrollback on
every window narrowing. Warn-only would have meant the single check able to catch that
printing to stderr and exiting `0` — the exact silent-failure asymmetry this script exists
to kill. `check-reflow.sh` is the behavioural half of the same guarantee: it fails 6 of its
8 cases against an unpatched tree, so the patch cannot be quietly lost.

`check-space-restore.sh` follows `check-keybindings.sh`'s pattern — compile the shipped
source, run a truth table — and is the exception that proves the rule above rather than a
contradiction of it. Restoring Spaces only *pays off* across a quit/relaunch boundary, and
that half (real window tab grouping) is genuinely not verifiable headlessly. But the half
that decides **what** comes back is ordinary logic over (stored strings, what exists on
disk), including the fail-soft cases whose only other discovery path is a user whose app
opens to nothing. It runs against a temp directory and a bundle-less binary's own defaults
domain, so it cannot disturb your real remembered Spaces — and asserts that isolation as
its last case instead of trusting it.

`check-reflow.sh` is the gate for SwiftTerm #494 and for local patch `0002`. It compiles a
harness against the **vendored emulator itself** (not a file from `Sources/Umber`), seeds
more lines than `rows` so the scrollback offset `_yBase` is non-zero, uses absolute CUP to
put the cursor above the last row — the only state in which the faulty branch at
`Buffer.swift:1167`/`:1205` executes at all — writes a wrapping line, narrows, then asserts
over the **whole normal buffer including scrollback** via `getBufferAsData`
(`Terminal.swift:5947`, whose loop is `for row in 0..<b.lines.count` at `:5953`). It exists
because the *previous* reflow gate was blind three ways, and each is inverted deliberately:
it never produced `_yBase > 0` together with the faulty branch; it read back with
`getLine(row:)`, which returns nil for `row >= rows` (`Terminal.swift:759`) and so can only
see the visible screen, never the scrollback where the corruption lands; and it asserted
only that tokens were not duplicated, never that they were not missing. All of missing,
duplicated, reordered, interior-blank-row and merged-row are asserted here. Exit codes are
split so an environment problem cannot read as a pass: `1` = real assertion failure,
`2` = environment (no `vendor/`, no toolchain, harness would not compile, or a case's own
scrollback-capacity precondition failed).

The load-bearing assertion is the **interior blank row**, not the token counts: the
observed corruption keeps every token exactly once and still wrecks history, splicing a
blank row into the middle of scrollback and shifting everything below it. Token counts
alone would have been another green-but-blind gate. Missing tokens *are* asserted, but only
because every case sizes scrollback with headroom and the harness checks that headroom as a
precondition — a token vanishing is unambiguous corruption only when legitimate trimming is
impossible, which is the confound the old gate cited as its reason for dropping the
assertion entirely.

`check-find-menu.sh` covers the three Edit-menu items with **no Umber code behind them** —
Undo, Redo, and Find and Replace are AppKit responder actions reached with `target = nil`,
so all three are correct only as long as an assumption about the SDK holds. It checks that
`undo:`/`redo:` are answered by NSWindow (not NSTextView, which does not implement them),
that the find tags are still the `NSFindPanelAction` raw values the menu reads off the SDK,
and — behaviourally, against a real offscreen `NSTextView` — that tag 12
(`NSTextFinder.Action.showReplaceInterface`, which `NSFindPanelAction` has no case for)
genuinely produces the replace row. That last one is why the script exists: a menu item
wired to an unanswered selector or an unrecognised tag renders, highlights, clicks, and
does nothing, and nothing else in this repo would notice. It sends each tag in its own
process, because sharing one text view let the bar keep the previous action's state and a
dead tag passed; and it distinguishes "no window server" (exit 2) from "tag 1 worked but
tag 12 did nothing" (exit 1), so a real dead item cannot hide behind an environment excuse.

## What works today (v0.1)

- Real `.app` bundle, ad-hoc signed
- Your login shell (`$SHELL -l`, so your real `PATH` and rc files load)
- **Spaces and documents — two tab levels.** A **Space** is a project root and is
  a real native macOS window tab (⌘N), so ⌘⇧[ / ⌘⇧] cycling, the tab overview,
  drag-to-reorder, drag-out-to-detach and Merge All Windows all work without being
  implemented. **Documents** live in a hand-rolled strip inside a Space (⌘T,
  ⌘⌥←/⌘⌥→, ⌘1–⌘9), because a system window tab *is* an `NSWindow` and could
  therefore never share one sidebar across a mixed terminal/editor strip. The strip
  hides itself at a single document. See plan §12.3.
- **Every open Space reopens on relaunch**, as one native tab group, each rooted where
  it was — *not* its documents, because a shell has no resumable state and four fresh
  prompts dressed up as your last session would be theatre. Window geometry is
  remembered per project root. First launch, or every remembered root having been
  deleted, gives you one Space at `$HOME`.
- **Sidebar file tree** (⌘B) — lazy `NSOutlineView` rooted at the Space, Finder
  icons, dotfiles shown (`.git`/`.DS_Store` excluded), refreshed when the window
  becomes key. Double-clicking a file types its quoted path into the focused
  terminal — the pre-editor affordance; when an editor document kind exists it will
  open in a tab instead.
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

Lives at `~/.config/umber/config.json`. It does not exist until you create
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

Depends on `../vendor/SwiftTerm` — upstream **v1.15.0** with **two** local patches:

1. `0001-exclude-metal-shader-from-target.patch` — the optional Metal GPU shader is
   excluded from the build, because Xcode 26.6 moved the Metal toolchain to a separate
   downloadable component that is not installed here. The Core Text renderer is used
   instead; `MetalTerminalRenderer` probes for the shader bundle at runtime and returns
   nil when absent, so nothing traps.
2. `0002-index-iswrapped-buffer-absolute.patch` — fixes SwiftTerm
   [#494](https://github.com/migueldeicaza/SwiftTerm/issues/494) by indexing the
   wrapped-line flag buffer-absolute (`_lines[_y + _yBase]`) at `Buffer.swift:1171` and
   `:1211`, which previously used the screen-relative `_lines[_y]` and so corrupted
   scrollback on every narrowing. See "Known upstream risk" below.

`vendor/` is gitignored, so the patches are committed as real artifacts instead —
`../patches/swiftterm/0001-exclude-metal-shader-from-target.patch` and
`../patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch`, both pinned by
`../patches/swiftterm/SwiftTerm.pin`. Recreate the tree with:

```sh
git clone --depth 1 --branch v1.15.0 \
    https://github.com/migueldeicaza/SwiftTerm.git vendor/SwiftTerm
chmod -R u+w vendor/SwiftTerm      # SPM checkouts are read-only; patch fails otherwise
patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0001-exclude-metal-shader-from-target.patch
patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch
app/Scripts/verify-vendor.sh       # confirms the result matches the pin (both patches)
(cd app && ./Scripts/check-reflow.sh)   # proves 0002 actually took
```

Both patches are required. `verify-vendor.sh` exits `2` naming the specific file if
either is missing.

Earlier revisions of this file said to "exclude the shader resource in its
`Package.swift` (the change is annotated in place)" — i.e. the only description of the
patch lived *inside the ignored file*, so it could not survive losing that file. That is
fixed: the patch is now reproducible from git, and `verify-vendor.sh` proves the result
byte-for-byte.

Provenance is mechanically established rather than assumed: a full recursive diff of the
vendored tree against the upstream `v1.15.0` tarball (commit `dd2fb8a`) reported **exactly
one** differing entry, `Package.swift`. Every other file — including `Buffer.swift` — was
byte-identical to upstream, which is why the #494 defect is upstream's and not something
introduced here. As of 2026-07-29 there are **two** differing entries, `Package.swift` and
`Buffer.swift`, the second being patch `0002`; the pin records the upstream hash of
`Buffer.swift` alongside the patched one precisely so "re-vendored, patch forgotten" stays
a nameable state rather than an unexplained hash mismatch.

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
"Buffer reflow produces duplicate/orphan lines when narrowing terminal" — is still
**open upstream**, and is now **patched and gated locally** (2026-07-29). It is no longer
untested here; the history of how it came to be *claimed* tested is kept below on purpose.

This section previously said the Step 0 harness "could not reproduce it across
three deterministic reflow tests," and concluded the risk was reduced. **That
conclusion was wrong; corrected 2026-07-27.** The defect requires a non-zero
scrollback offset to manifest, and the harness never established one —
`git show 1e84dd0~1:spike/Tests/SpikeGatesTests/ReflowGateTests.swift | grep -c yBase`
returns `0`. Two of the three cases ran at `_yBase == 0`, where the defect is
*structurally inexpressible*; the third had scrollback but asserted only
duplicate-token counts, so the orphaning half went unchecked. A blind test
passing is absence of evidence, not evidence of absence.

The defect is real and present in the vendored tree. `Buffer.swift:1171` and
`:1211` set `_lines[_y].isWrapped = true` with a **screen-relative** index, five
and thirteen lines from `:1176`/`:1224` which correctly use the
**buffer-absolute** `_lines[_y + _yBase]` (`_y` is screen-relative —
`Buffer.swift:22,42-43`). Since `isWrapped` is the only flag reflow consults for
logical-line boundaries, a non-empty scrollback makes it join a falsely-wrapped
line to an unrelated neighbour and split a genuinely-wrapped one. That mangles
history silently rather than visibly. Upstream's partial fix (`protectedLines`)
is on unmerged branch `reflow` @ `0619254f`; vendored v1.15.0 lacks it.

**Resolution (2026-07-29): patched locally, with a gate that can fail.** Of the options
triaged in `../.afk/plans/emulator-foundation-probe-and-vendor-integrity.md` §5–6, "patch
locally" was chosen. `../patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch` makes
both sites buffer-absolute; `./Scripts/check-reflow.sh` is the gate, and `verify-vendor.sh`
now hard-fails a tree missing the patch.

The plan rejected local patching on the grounds that *core buffer surgery in a repo with
zero tests buys correctness that cannot be verified* — so the gate, not the two-line diff,
is the actual deliverable. It was validated by falsification rather than by passing: against
the **unpatched** vendored tree it fails **6 of 8** cases (exit `1`), naming the corruption
concretely, e.g. row 5 of scrollback reading `|T0006sss|` before narrowing and `||` after;
against the patched tree all 8 pass (exit `0`). Reverting the patch reproduces the failures.
A gate that had passed both ways would have been worth nothing, which is exactly what
happened the first time.

The fix is **local, not upstream**. Upstream's own partial fix (`protectedLines`) is still
on unmerged branch `reflow` @ `0619254f`, and #494 remains open, so a SwiftTerm upgrade will
*not* bring this fix with it — it will bring back the defect unless `0002` is re-applied.
That is what the dual hashes in `SwiftTerm.pin` and the hard failure in `verify-vendor.sh`
are for. If duplicated or orphaned lines ever appear after narrowing a window with
scrollback present, `TerminalPane.sizeChanged` is still the hook to instrument.
