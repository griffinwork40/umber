# Git-status sidebar: seam precedent research

Repo: mac-terminal worktree `afk-add-git-sidebar` @ 0ebd717. Read-only research —
no files edited except this one. All primary sources read in full:
`ShellDirectory.swift`, `SpaceViewController+DirectoryFollow.swift`,
`SpaceDocument.swift`, `ShellHosting.swift`, `SpaceViewController+Delegates.swift`,
`SpaceWindowController.swift`, `Config.swift`, `Theme.swift`,
`SpaceViewController.swift`, `DocumentStatus+Presentation.swift`,
`FileTreeViewController+OutlineView.swift`, `FileNode.swift`, `StarterConfig.swift`,
`check-cwd-follow.sh`, `check-file-size.sh`.

Sibling scratch docs (`git-sidebar-mechanism.md`, `git-sidebar-verify.md`,
`git-sidebar-vscode-surface.md`, `git-sidebar-seam-layout.md`) cover the data-source
mechanism, verification surface, external prior art, and layout — not duplicated
here; this file is scoped strictly to the four assigned questions.

---

## 1. THE PRECEDENT TO COPY

### `ShellDirectory.swift` (162 lines)

- **Imports**: `Darwin` + `Foundation` only (lines 33-34). No AppKit, no SwiftTerm.
  Header, lines 5-10: "Pure and view-free on purpose... That is not tidiness: it is
  what lets `Scripts/check-cwd-follow.sh` compile this one file directly with
  `swiftc`... In a repo with no test target and no CI..., a concern that cannot be
  compiled alone cannot be gated alone, so the dependency-free boundary IS the
  testability."
- **Type**: `enum ShellDirectory` (line 42) — a namespace, not a type, deliberately
  NOT `@MainActor` (line 39): "these are pure functions over a pid and a `URL`, safe
  to call from anywhere."
- **Why not OSC 7** (lines 19-30): SwiftTerm parses OSC 7 into
  `hostCurrentDirectoryUpdate`, a wired-but-empty callback that "looks like the
  obvious home... It cannot work" — macOS's emitter lives in
  `/etc/zshrc_Apple_Terminal`, gated on `TERM_PROGRAM == Apple_Terminal`
  (`/etc/zshrc:74`), and SwiftTerm never sets `TERM_PROGRAM`
  (`Terminal.swift:5873`). "a stock zsh emits **zero** OSC 7 bytes... Asking the
  kernel instead needs no shell cooperation... and cannot be defeated by a user's
  dotfiles."
- **Public surface**: `current(foregroundOf:fallbackPid:) -> URL?` (line 54, read)
  and `cdCommand(to:) -> String` (line 92, write) — "inverse halves of one contract"
  (line 17), deliberately kept in one file. Plus `singleQuoted(_:)` (line 105),
  `internal` (not `private`) "so the gate script can exercise it directly."
- **Two private syscall wrappers** ("MARK: - The two syscalls", line 109):
  `foregroundPid` (tcgetpgrp, falls back to shell pid) and
  `workingDirectoryPath(of:)` (proc_pidinfo `PROC_PIDVNODEPATHINFO`, guards
  `written == size` against an exit race).
- Read-boundary `standardizedFileURL.resolvingSymlinksInPath()` (line 77) is
  "load-bearing rather than cosmetic" — it is what makes the unchanged-path check
  in `setRoot(_:)` actually fire.

### `SpaceViewController+DirectoryFollow.swift` (183 lines)

- **Import**: `AppKit` only (line 32) — impure by design; owns a `Timer` and
  touches the view controller.
- **Why its own file** (lines 5-10): "one whole concern with a lifecycle of its own
  (a timer that must start, stop, and not outlive its window), and because
  `SpaceViewController.swift` is at 323 lines — inside `check-file-size.sh`'s
  warning band already, with no room for a poller." Only the single stored property
  lives on the container, because **Swift extensions cannot add stored
  properties**; "everything that property *does* is here." (NOTE: verified today —
  `SpaceViewController.swift` is now 345 lines, `wc -l` confirmed; the "323" in this
  comment has drifted, unprompted evidence the ceiling is actively being pressed.)
- **Why polling, not a callback** (lines 12-21): "There is no event to subscribe
  to" — same OSC-7-is-dead argument. "the cost is a syscall pair every 750ms while
  a window is key, and nothing at all when it is not."
- **One-way data flow — the load-bearing invariant** (lines 23-29): "The UI never
  moves the tree itself... the tree moves only here, only after the shell has
  actually moved. So the shell is the single source of truth, the UI cannot
  disagree with it, and there is no second writer to race."
- **`DirectoryFollow` class** (line 40): `weak var space` — load-bearing weak
  (lines 41-45): a strong ref "would keep the whole view controller — and its
  panes, and their ptys — alive after the window was gone." `timer: Timer?`.
  `lastPushed: URL?` is explicitly a pre-filter, NOT the correctness mechanism
  (lines 50-56): "`setRoot(_:)` already early-returns on an unchanged root, so this
  is not what makes the feature correct... Correctness lives in `setRoot`."
- **Interval 0.75s** (line 74): "the work per tick is `tcgetpgrp` + `proc_pidinfo`
  on one process — microseconds — so the interval is chosen for perceived latency,
  not for load."
- **Lifecycle**: `start()` (line 67) idempotent (`guard timer == nil`), polls once
  immediately (line 86). `stop()` (line 95) on **resign-key, not window close**:
  "a background Space cannot be looked at, so following it is pure cost... the
  poller is not a per-pane concern — N terminals in a Space share one timer."
  `pollNow()` (line 106) forces an out-of-rhythm poll on document-tab switches.
  `tick()` (line 110): `guard let space else { return stop() }`; reads
  `space.focusedShellHost?.currentDirectory` (reusing the exact rule Insert
  Path/cd-Here use, "so all three features agree"); short-circuits on
  `directory != lastPushed`.
- **Extension on `SpaceViewController`** (line 132) exposes
  `startDirectoryFollow()`/`stopDirectoryFollow()`/`windowDidResignKey()`
  (called from `SpaceWindowController.windowDidResignKey(_:)`,
  `SpaceWindowController.swift:280-282`)/`directoryFollowPollNow()`, and
  **`followDirectory(_:)`** (line 180) — **the single mutation point**:
  ```swift
  func followDirectory(_ directory: URL) {
      fileTree.setRoot(directory)
  }
  ```
  "The only place in the app that moves the tree, and it is reached only from a
  shell's reported cwd — never directly from a click."

### The mirrored git-status design

**Two-file split, mirroring exactly:**

| File | Mirrors | Owns | Import | LOC budget |
|---|---|---|---|---|
| `GitStatus.swift` | `ShellDirectory.swift` | Pure read: run `git status --porcelain=v2` as a subprocess (`Foundation.Process`), parse stdout into a value type (branch, ahead/behind, per-path codes) | `Foundation` only | ~140-170 |
| `SpaceViewController+GitStatusFollow.swift` | `+DirectoryFollow.swift` | Poller: `GitStatusFollow` class, start/stop on key/resign, `tick()`, single mutation point `applyGitStatus(_:)` | `AppKit` | ~150-180 |

Both clear 350 alone; neither pushes any existing file over. One caveat on the
"pure" label: `ShellDirectory.swift` itself never spawns a subprocess (only two
syscalls); `GitStatus.swift` would. This is not disqualifying — `check-cwd-follow.sh`'s
own harness (compiled `swiftc`-only alongside `ShellDirectory.swift`, importing just
`Darwin`/`Foundation`) already uses `Foundation.Process` directly (`check-cwd-follow.sh`,
the `let proc = Process()` block, executed-not-string-matched `cd` verification) —
proof `Process` is usable in this exact "headless swiftc, no AppKit" harness shape.
But it is a difference in *kind* from the existing precedent (syscalls vs. exec), not
just degree, and should be named as such rather than glossed over.

**Pure/impure split rule** (generalized): a file counts as "pure" here if it
imports only `Foundation`/`Darwin` (no `AppKit`, no `SwiftTerm`) and is not
`@MainActor` — the two properties that let a headless `swiftc` compile gate it
alone, the same trick `check-keybindings.sh` plays on `KeyBindings.swift`.

**Shared vs. separate poller — verdict: SEPARATE poller, own interval, shared
lifecycle call sites.** Reasoning:
1. `DirectoryFollow`'s class doc (lines 36-38) states its bundling reason as "one
   object with one owner" for ONE concern. Adding git-status to the same `tick()`
   makes that object own two concerns bound only by "runs on a timer" — the "one
   concern per file" convention argues against this at the class level,
   independent of LOC headroom.
2. Different cost profiles: cwd-follow's syscalls are "microseconds"; a `git
   status` subprocess (fork/exec, filesystem stat) is orders of magnitude more
   expensive and should not necessarily share a 750ms cadence.
3. Different scope: cwd-follow is keyed to `focusedShellHost` (a *document*); git
   status is keyed to the Space's `root` (`SpaceWindowController.root`,
   `SpaceViewController.root`, `SpaceViewController.swift:34`) — one repo per
   Space, not per focused pane. Conflating them makes `tick()` read two unrelated
   data sources under one name.
4. Mitigate the real lifecycle-duplication risk not by sharing the class, but by
   having the two existing call sites (`SpaceWindowController.windowDidBecomeKey`/
   `windowDidResignKey`, lines 270-282) fan out to both
   `space.startDirectoryFollow()` and a new `space.startGitStatusFollow()` — costs
   two one-line calls at already-shared sites, not a new abstraction.

Recommended interval: slower than 0.75s (INFERRED, no existing precedent pins a
number) — 2s is a reasonable starting point, to be justified in the new file's own
header the way 0.75s is justified inline.

---

## 2. THE DOCUMENT SEAM

### `SpaceDocument` — mandatory vs. defaulted (`SpaceDocument.swift`)

**Mandatory, no default (8, lines 92-153):** `documentView: NSView { get }`,
`documentTitle: String { get }`, `documentSymbolName: String { get }`,
`documentDidBecomeActive()`, `apply(config: AppConfig)`,
`currentFontSize: CGFloat { get }`, `setFontSize(_:persist:)`, `resetFontSize()`.
Deliberately hard requirements (lines 86-90): "A default no-op would restore
exactly the failure mode just removed: a future editor/diff/Ghostty conformer that
forgets font zoom would compile, render, and ignore ⌘+ forever."

**Defaulted (5, `extension SpaceDocument`, lines 222-236):**
```swift
func documentWindowDidBecomeKey() {}
var documentIsEdited: Bool { false }
func documentShouldClose() -> Bool { true }
func saveDocument() -> Bool { true }
var documentStatus: DocumentStatus { .idle }
```
"correct for a live document rather than merely convenient... A conformer that
ignores them is right by default, not broken by default" (line 224-226).

Pricing a new conformer: 8 required members, several trivially cheap for a
read-only viewer (symbol name, title are one-line computed properties;
font-zoom plumbing is nearly identical to `FileViewerPane`'s existing handling).

### Verdict: a git diff view is a THIRD `SpaceDocument` conformer, not sidebar UI

The protocol's own text already names this case, twice:
- `documentSymbolName`'s doc comment (lines 101-103): "SF Symbol drawn in the tab,
  so terminal / editor / **diff** tabs are distinguishable at a glance once the
  strip is genuinely mixed."
- The protocol's rationale (lines 68-75) cites Terax's tab strip as "a flat
  *heterogeneous* union of eight kinds — terminal, editor, preview, markdown, and
  **four diff/history kinds**" as the shape `SpaceDocument` exists to support.
- AFK.md, "Not Built Yet": "Adding a new document kind (editor, diff, observer
  panel) means writing a `SpaceDocument` conformer — **not** touching the
  container. That is the whole payoff of the restructure." Diff is named
  explicitly as the anticipated next conformer, not inferred.

Argued from the shape itself: a diff view is monospace, scrollable, read-only
text — `documentIsEdited`/`documentShouldClose`/`saveDocument` all take correct
defaults for free (nothing to lose, same reasoning given to `TerminalPane`).
`documentWindowDidBecomeKey()` is the one default worth overriding — "working
tree diff" goes stale the instant you look away, the same argument
`FileViewerPane` makes for re-reading on refocus. `openFile(url:)`'s existing
reuse-by-path dedup (`SpaceViewController.swift:204-222`, "Reuse is not an
optimisation — it is the behaviour") is the pattern a `GitDiffPane` would mirror,
keyed on path (+ maybe stage-state). Strictly cheaper than new sidebar chrome,
and the seam already proved cheap once (`FileViewerPane` "added without the
container learning anything about it" — AFK.md).

### `ShellHosting` — what it's for, and whether git actions should route through it

`ShellHosting.swift` header (lines 14-27): exists so the container can answer
"which document can I write shell input to?" without naming a concrete pane —
replacing a cast to `TerminalPane` that "blocked a second engine-backed document
kind." Deliberately NOT widened to `SpaceDocument`: "a shell-directed action must
land in a *shell*... widening would let the file tree's 'insert path' inject a
filesystem path into a text-editor buffer as if the user had typed it there — a
silent data-corrupting wrong target" (lines 21-27). Two members only (lines
67-101): `send(text:)` (write, no implied newline — caller decides submit vs.
compose) and `currentDirectory: URL? { get }` (read, a property not a callback,
"because there is nothing to push from" — same OSC-7-dead reasoning).

Verdict, split by action type:
- **"cd here" for a git action** (e.g. jump to repo root): already fully covered
  by the existing `didRequestChangeDirectory` path
  (`SpaceViewController+Delegates.swift:154-176`) — no new plumbing needed, reuse
  `ShellDirectory.cdCommand(to:)` verbatim.
- **"stage this file" (`git add <path>`)**: the *composing* case is explicitly
  already served — see §3 below, the anticipation comment names `git add <path>`
  directly as a use of the existing unsubmitted Insert-Path feature. A one-click
  "Stage This File" menu item (submitted, not composed) would be a straight
  structural copy of `didRequestChangeDirectory`'s shape: build
  `"git add " + ShellDirectory.singleQuoted(path) + "\n"` and call
  `host.send(text:)` on `focusedShellHost`, submitted like `cdCommand`, not left
  open like path-insert — no new protocol member required.
- **Reading git status itself does NOT go through `ShellHosting`** — it mirrors
  the existing read/write asymmetry: `ShellDirectory.current(...)` (the read) never
  touches `ShellHosting` and reads the pty directly, while `cdCommand(to:)` (the
  write) is delivered via `ShellHosting.send(text:)`. A `GitStatus.swift` read is
  keyed to the Space's root via a subprocess, entirely independent of which shell
  (if any) is focused — so it is a peer of `ShellDirectory.current`, not a
  `ShellHosting` consumer.

---

## 3. EXISTING ANTICIPATION

### `SpaceViewController+Delegates.swift`, lines 88-93 — quoted verbatim

```
/// The old behaviour, kept and given a name.
///
/// Inserting a quoted path is genuinely useful — it is what you want while
/// composing `nvim <path>` or `git add <path>` — it was just bound to the one
/// gesture that means "open". Now it is ⌥-double-click and a context-menu item,
/// which also makes it discoverable, which it never was.
```
This is on `fileTree(_:didRequestPathInsert:)` (line 94). It directly names `git
add <path>` as an intended use of "Insert Path in Terminal" (unsubmitted,
space-trailing — line 109's `host.send(text: quoted + " ")`). Constraint on
design: a bare "stage" affordance already half-exists via this generic mechanism;
a purpose-built "Stage This File" action would be additive (submitted git add),
not a replacement, and should reuse the same quoting/`ShellHosting` plumbing
rather than invent a second path-quoting convention (the file already warns,
`ShellDirectory.swift:101-104`, that "two different quoting conventions writing
to the same shell is how one of them ends up wrong").

### `SpaceWindowController.swift` — title/subtitle, exact mechanism

- `window.title = root.lastPathComponent` — set **once**, at `init`
  (`SpaceWindowController.swift:154`), never mutated again anywhere in the file
  (confirmed by repo-wide grep: the only other `window.title`-adjacent line is
  `titlebarAppearsTransparent`). Comment: "the title names the project and the
  *subtitle* carries the active document" (lines 150-153). Title is Space
  **identity**-scoped.
- `window.subtitle = title` — the ONLY subtitle write (line 259), inside
  `spaceViewController(_:didChangeDocumentTitle:)`
  (`SpaceViewControllerDelegate`, line 258-260). Driven from two call sites, both
  keyed to the **active document's** `documentTitle`:
  `SpaceViewController.selectDocument(at:)` (line 231) and
  `SpaceViewController+Delegates.document(_:didChangeTitle:)` (lines 58-64, gated
  `documents[activeIndex] === document` — a background tab's title change never
  touches the window).

Could branch+dirty land there instead of new UI? Scope argues yes for title, no
for subtitle: branch/dirty is a property of the **root** (one repo per Space,
`SpaceWindowController.root`), matching `window.title`'s identity scope — not
`window.subtitle`'s, which is explicitly **document**-scoped ("the active
document"). Overloading subtitle would conflate "which document is active" with
"what is this repo's state" and break for any Space with >1 document. `window.title`
fits the scope but is currently write-once-at-init; making it live is new code (an
`updateGitBranch(_:)` method on `SpaceWindowController`, called from the new
poller, mirroring `followDirectory` → `fileTree`), not reuse of existing wiring.
Worth naming as a real alternative, not a superior default: `DocumentStatus`
already routes "things worth flagging" through per-item chrome (tab dots) rather
than window strings, so sidebar/tab decoration is likely the better target for
per-file status, while a title-bar string stays plausible only for the
Space-wide branch+dirty summary.

---

## 4. CONFIG + THEME PLUMBING

### (a) The fail-soft pattern, quoted end-to-end (`Config.swift`)

Declare optional in the wire format:
```swift
var scrollback: Int?          // ConfigFile, line 43
```
Give a default users never have to touch (`defaults()`, line 155):
```swift
scrollback: 1_000,
```
Resolve in `load()`, validate, degrade to default + warn instead of throwing
(lines 249-252):
```swift
if let sb = file.scrollback {
    if sb >= 0 { config.scrollback = sb }
    else { config.warnings.append("scrollback must be >= 0 — using \(config.scrollback)") }
}
```
`load()` itself never throws (line 162): a missing file, invalid JSON, or any
single bad field each degrade independently — "Six bad fields ⇒ six warnings and
a working terminal" (AFK.md, Conventions). `shell` (lines 253-256) is the
filesystem-validated analogue, useful if a git binary path were ever
configurable: `if FileManager.default.isExecutableFile(atPath: sh) { ... } else {
config.warnings.append(...) }`.

**Does a new git field fit, or does it need a new file?** `Config.swift` is
289/350. A single boolean toggle (e.g. `git: Bool?`, "enable git status
polling") costs ~15-25 lines at this repo's comment density (matching the
`scrollback` field's ~4 code lines plus doc comments) — fits comfortably, no new
file needed for one field. If more than one or two git-config fields are wanted
(enable flag + poll interval, say), the existing precedent is to nest a private
sub-spec struct the way `ThemeSpec` does (`ConfigFile.ThemeSpec`, lines 31-39) —
still inside `Config.swift`, still cheap. If git config grows further still (e.g.
per-status colour overrides), the established move is the one already taken for
theme: split to a sibling pure-value file. `Config.swift`'s own header says
Theme.swift already carries "colour parsing and the presets... none of which
this file's fail-soft contract depends on" — i.e., Config.swift already
delegates non-loader concerns outward, so a `GitConfig.swift` sibling (if ever
needed) would be consistent, not novel.

### (b) Status colors: no new theme fields needed

`DocumentStatus+Presentation.swift` (55 lines) is the exact semantic-status-color
precedent this feature needs, just for document lifecycle instead of git file
state:
```swift
func dotColour(fallback: NSColor, isActive: Bool) -> NSColor? {
    switch self {
    case .idle: return nil
    case .running: return fallback.withAlphaComponent(isActive ? 0.55 : 0.45)
    case .succeeded: return fallback.withAlphaComponent(isActive ? 0.9 : 0.8)
    case .failed: return .systemRed
    case .attention: return .controlAccentColor
    }
}
```
Its doc comment states the rule directly (lines 27-30): "System colours, not hex
literals: they are the only ones that adapt to Increase Contrast and to the
window's effective appearance, and this app already derives its chrome from the
theme rather than hardcoding it." The identical shape applies to git file status
(modified/untracked/deleted/conflicted/staged): map each case to
`NSColor.systemGreen`/`.systemOrange`/`.systemRed`/etc. — no new `theme.json`
hex fields required.

Why an *ANSI-palette* color (e.g. "ANSI green") would be wrong, tying to the
AFK.md warning: with `theme == nil` (the default) Umber installs no palette and
SwiftTerm's own ANSI 16-255 stand untouched — no Umber-owned "green" exists to
reach for. The moment a user sets ANY `theme.background`/`.foreground`, SwiftTerm
**regenerates** ANSI 16-255 by interpolating out of that bg/fg
(`Config.swift:54-58`, "`Terminal.swift:513-542` → `rebuildAnsiPalette`") — so
"ANSI green" becomes a different, theme-dependent RGB the instant theming is on,
unstable for a color that must read as "modified" regardless of theme. AppKit
semantic system colors sit entirely outside that palette, in a separate,
dynamically-resolved space keyed to `NSAppearance` — already how the app colors
every other piece of non-terminal chrome (`FileTreeViewController+OutlineView.swift:53-60`,
the row-tint re-derived from `backgroundStyle`).

What makes this correct across both dark and light user themes is
`AppConfig.appearance` (`Config.swift:108-127`): it derives `window.appearance`
from `effectiveBackground.relativeLuminance` and sets it explicitly — "Nothing
used to set one, so they followed *System Settings*... which put a light-grey
tree... directly against a black terminal." The file tree is a child of that
window, so any `NSColor.system*` used in a git-status decoration resolves against
the theme-derived appearance for free — correct under `theme == nil`, a preset,
or custom hex overrides alike, no additional plumbing.

**Conclusion for (b): zero new theme fields. Add a `GitFileStatus`-shaped enum +
one `+Presentation.swift`-style extension using system colors, following
`DocumentStatus+Presentation.swift` verbatim as the template.**
