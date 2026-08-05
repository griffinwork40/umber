# Git sidebar seam layout — VS Code-style git UI integration research

Scope: LAYOUT (sidebar construction) + FILE TREE (cell/model) seams for adding git
status decorations and/or a changed-files list. All claims carry file:line citations;
INFERRED marks anything not directly read/run this session.

## 1. Sidebar construction

`SpaceViewController` is `final class SpaceViewController: NSSplitViewController`
(SpaceViewController.swift:31). Sidebar item creation, `viewDidLoad()`
(SpaceViewController.swift:92-102):
```swift
let sidebarItem = NSSplitViewItem(sidebarWithViewController: fileTree)
sidebarItem.minimumThickness = Self.minSidebarWidth   // 150
sidebarItem.maximumThickness = Self.maxSidebarWidth   // 480
sidebarItem.canCollapse = true
sidebarItem.holdingPriority = .defaultLow
let contentItem = NSSplitViewItem(viewController: documentArea)
contentItem.minimumThickness = 240
splitViewItems = [sidebarItem, contentItem]
```
Default divider set explicitly after assembly: `splitView.setPosition(220, ofDividerAt: 0)`
(:111) — comment notes `minimumThickness` alone doesn't produce 220.

**Ownership**: `let fileTree: FileTreeViewController` stored property
(SpaceViewController.swift:58-59), constructed in `init` (:76):
`self.fileTree = FileTreeViewController(root: root)`. `SpaceViewController` is the
sole owner; `fileTree.delegate = self` (:104) wires the reverse channel.
`FileTreeViewController` IS the sidebar's installed view controller — there is no
existing container between them.

**⌘B**: not implemented in Umber code. `NSSplitViewItem(sidebarWithViewController:)`
supplies `toggleSidebar(_:)` as a free `NSSplitViewController` responder-chain action
(comment, SpaceViewController.swift:88-91). VERIFIED in AppMenu.swift:201-207:
```swift
// No custom action and no target: the responder chain reaches
// SpaceViewController, which is the window's contentViewController and
// inherits toggleSidebar(_:) from NSSplitViewController.
viewMenu.addItem(withTitle: "Toggle Sidebar",
    action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "b")
```
No target set — dispatch reaches whichever `NSSplitViewController` is in the
responder chain, which is `SpaceViewController` itself (the window's
`contentViewController`), not `fileTree`. **Consequence for layout options**:
`toggleSidebar` operates on `SpaceViewController.splitViewItems[0]` (the sidebar
item), not on whatever view controller populates it — so wrapping `fileTree` in a
new container view controller and installing *that* as the sidebar item's VC does
not touch ⌘B at all. Non-issue for options (b)/(d) below.

`DocumentAreaViewController` (82/350 lines) is a separate NSViewController for the
*document* area (contentItem, not sidebar) — irrelevant to sidebar layout except as
precedent: it was pulled out of `SpaceViewController` "only because it had nowhere
else to live; the 350-LOC ceiling supplied the reason to give it one"
(DocumentAreaViewController.swift:5-12). Same move is available for a sidebar
container.

### Headroom (verified via `wc -l`, matches AFK.md)
| File | LOC/350 | Headroom |
|---|---|---|
| SpaceViewController.swift | 345 | **5** |
| SpaceWindowController.swift | 300 | 50 (not touched by this feature — owns window/tab-strip, not the tree) |
| FileTreeViewController.swift | 300 | 50 |
| FileTreeViewController+OutlineView.swift | 159 | 191 |
| FileNode.swift | 110 | 240 |
| DocumentAreaViewController.swift | 82 | 268 (wrong owner — not sidebar) |

`check-file-size.sh` mechanics (full read, check-file-size.sh:41-88): `WARN_AT = LIMIT
* 90 / 100` = 315 (:42); `n -gt LIMIT` → violation, `exit 1` if any violations (:60-62,
74-81); `n -ge WARN_AT` → warning only, does NOT fail the build (:63-65, 84-88). So
SpaceViewController.swift at 345 is in WARN territory today, not failing — 5 more
lines (351) trips the hard fail. Scope is `Sources` + `Scripts`, `*.swift`/`*.sh`/`*.py`
only (:48); `.afk/plans/*.md` prose is exempt by the script's own header (:23-27).

## 2. The file tree

### FileNode.swift (110 lines) — the model
`final class FileNode`: `let url: URL`, `let isDirectory: Bool`, `let isHidden: Bool`,
`private(set) var children: [FileNode]?` (FileNode.swift:24-34). Plain Foundation
object — no AppKit, no git awareness.

**`.git` is hardcoded-excluded**, FileNode.swift:106-109:
```swift
private static func isVisible(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    return name != ".git" && name != ".DS_Store"
}
```
Applied inside `reloadChildren()`'s `.filter { Self.isVisible($0) }` (:63) against
the raw `contentsOfDirectory` listing (:56-59). Name-only test — doesn't care if
`.git` is a dir or a file — so `.git` never becomes a `FileNode` at any tree level.

**Identity-preserving reload** — the load-bearing mechanism, FileNode.swift:50-53,
73-78:
```swift
func reloadChildren() {
    guard isDirectory else { return }
    let existing = Dictionary((children ?? []).map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    // ... per listed entry:
    if let reused = existing[child], reused.isDirectory == isDir, reused.isHidden == isHidden {
        return reused                      // SAME OBJECT
    }
    return FileNode(url: child, isDirectory: isDir, isHidden: isHidden)   // NEW OBJECT
```
Recursion only into already-expanded children (:97-99). The file's own header states
why this matters: `NSOutlineView` "tracks disclosure state by item identity"
(FileNode.swift:9-11) — i.e. pointer/`ObjectIdentifier` equality of the `FileNode`
instance the data source hands back, not any Equatable value.

**Implication for attaching git status**: a `var gitStatus: GitFileStatus?` stored
directly on `FileNode`, mutated in place, rides the existing reuse path exactly like
`isHidden`/`isDirectory` already do — reused nodes keep whatever was set on them,
new nodes get a freshly computed value. **Failure mode if done wrong** (INFERRED,
by direct extension of the documented invariant, not separately tested): if a git
layer instead replaced/re-fetched `FileNode` objects on each status poll rather than
mutating existing instances, `NSOutlineView` would see "new" identities for
unchanged paths and silently drop expansion/selection state — the same class of bug
`refresh()`'s design note already guards against for the base tree.

### FileTreeViewController.swift (300/350, 50 headroom) — the controller
`refresh()` (:123-140): snapshots expanded nodes + selected URL from current outline
state, calls `root.reloadChildren()` + `outlineView.reloadData()`, then restores.
Driven by window-become-key (`SpaceViewController.swift:325`, `fileTree.refresh()`)
— **no git signal drives it today**; confirmed no FSEvents, no git-targeted timer in
this file.

`setRoot(_:)` (:176-182) is the cwd-follow repoint — confirmed as the single call
site for tree-root changes (see §3 DirectoryFollow evidence below). Deliberately does
**not** preserve expansion/selection: builds a wholly new `FileNode` graph, so any
per-node git-status cache would be discarded along with everything else on a root
change (by design, per the comment at :142-175).

**The URL-vs-.path equality trap**, setRoot(_:) guard, :176-178:
```swift
func setRoot(_ url: URL) {
    guard url.resolvingSymlinksInPath().path != root.url.resolvingSymlinksInPath().path
    else { return }
```
Comment (:166-175, quoted verbatim): "`URL` equality includes the directory marker (a
trailing slash), and `resolvingSymlinksInPath()` drops that marker when the last
component is itself a symlink: measured, `URL(fileURLWithPath:
"/private/tmp").resolvingSymlinksInPath()` is `file:///tmp/` while
`URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()` is `file:///tmp` — same
`.path`, and `==` is **false**." Consequence stated in-file: a `URL`-based comparison
would make the 750ms poller rebuild the tree and discard expansion/selection twice a
second — "the damage the guard exists to prevent, in the shape of a passing test."
**This exact bug class applies to any new git-root-equality check** — a naive `URL
==` test in a git-status poller ("has the repo root changed?") would silently
reintroduce it. Must compare canonicalized `.path` strings, matching this precedent.

### FileTreeViewController+OutlineView.swift (159/350, 191 headroom) — cell construction
`outlineView(_:viewFor:item:)` (:64-77) is the row-cell builder and **the exact seam
for status decorations**:
```swift
func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? FileNode else { return nil }
    let identifier = NSUserInterfaceItemIdentifier("FileCell")
    let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        ?? Self.makeCell(identifier: identifier)
    cell.textField?.stringValue = node.name
    cell.imageView?.image = Self.symbol(named: Self.symbolName(for: node))
    return cell
}
```
Two concrete attachment points: (1) `cell.textField?.textColor = ...` keyed off
`node.gitStatus` (VS Code colors the filename); (2) a badge letter/dot subview added
once in `makeCell(identifier:)` (:129-158, where the imageView/textField pair and
their Auto Layout constraints are built), then its text/visibility set fresh per row
inside `viewFor` — mirroring how `textField.stringValue` is already set fresh every
call. `FileCellView` (:52-61) already re-tints its icon on `backgroundStyle` change
(selection) — a badge color would need the same re-tint treatment to stay legible in
the selection pill. `symbolCache` (:115) is keyed by symbol name only; a
status-aware icon variant would need a compound key.

## 3. What breaks

**a) Non-repo directory**: zero git-detection code exists anywhere in this codebase
(confirmed by grep, below) — `FileNode`/`FileTreeViewController` only exclude the
*name* `.git`, never check for its existence or contents. So today "sidebar behavior
on a non-repo dir" == "sidebar behavior on any dir": no distinction is made because
none is computed. A new feature owns 100% of repo-detection; nothing to reuse or to
break.

**b) This checkout IS a worktree — VERIFIED, `.git` is a FILE, not a directory.**
Directly verified this session: `cat .git` at repo root →
`gitdir: <repo>/.git/worktrees/afk-add-git-sidebar`;
`file .git` → "ASCII text". Standard git-worktree(1) mechanism: the real `.git`
directory (refs/objects/config) lives at the main checkout; each worktree gets only
a pointer file. **Implication**: any repo-detection that does `isDirectory(root/.git)`
returns false here and wrongly concludes "not a repo" — which, per this repo's own
architecture, is exactly how Umber's own dev tree is structured
(`.afk-worktrees/<name>`, this very session's cwd). Correct detection must accept
`.git` as EITHER a directory OR a `gitdir:`-prefixed file, or shell out to `git
rev-parse --git-dir`/`--show-toplevel` instead of hand-rolling a directory check.
**This is the single biggest landmine**: it would pass a quick manual test from an
ordinary clone and silently fail on every worktree, including Umber's own.

**c) Does repo root move with the tree on setRoot/cwd-follow, and should it?**
`SpaceViewController+DirectoryFollow.swift` (183 lines, fully read) confirms the
mechanism: `DirectoryFollow` (:40-128) polls every 0.75s (:74), `tick()` (:110-127)
reads `space.focusedShellHost?.currentDirectory` (:119) and, on change, calls
`space.followDirectory(directory)` (:126), whose entire body is:
```swift
func followDirectory(_ directory: URL) {
    fileTree.setRoot(directory)
}
```
(:180-182) — confirming `FileTreeViewController.setRoot(_:)` is the single
chokepoint for all tree-root changes, cwd-follow included. `setRoot` has no git
awareness today. A git layer must hook this same call site (and `refresh()`, for
re-polling status without a root change, e.g. after an edit). **Should repo root
move with it?** Logically no: cwd-follow can walk into a *subdirectory* of the same
repo (`cd app/Sources/Umber`) where the repo root is unchanged — only the tree's
displayed root moves. Correct git-root resolution is a nearest-ancestor walk-up from
the tree's current root searching for `.git`, decoupled from exact-match against the
Space's original or currently-displayed root (INFERRED design reasoning; no such
logic exists yet to read).

**d) Interaction with FileNode's `.git` exclusion**: purely cosmetic/orthogonal — the
exclusion (FileNode.swift:106-109) only hides a row named `.git` from the visible
listing; it has no relationship to and does not interfere with a git layer's own
direct filesystem read of `.git` (needed for repo detection and worktree
`gitdir:`-indirection), since that read is a distinct code path that must bypass
`isVisible` entirely.

**Grep confirmation (zero existing git-awareness)**: `grep -rn "git" app/Sources/Umber/*.swift -i`
matches only FileNode.swift:85,103,108 (the exclusion + its comments) and incidental
prose uses of "git" as a tool-name in unrelated rationale comments
(SpaceViewController+Delegates.swift:91,130; TerminalPane.swift:299; ShellDirectory.swift:115;
SpaceWindowController.swift:54; FileViewerPane.swift:103,209; Defaults.swift:165) — no
git status computation, no libgit2, no shell-out to `git`, no `.git` content reads
anywhere in `app/Sources/Umber`.

## Candidate layout evaluation

**(a) Decorations only, no new view** — cheapest. `FileTreeViewController+OutlineView.swift`
(191 headroom): extend `viewFor` + `makeCell`. `FileNode.swift` (240 headroom): add
one mutable `gitStatus` property, riding the proven identity-preservation path.
`FileTreeViewController.swift` (50 headroom): one small trigger call in `refresh()`
(:123) and/or `setRoot` (:176) into a new, non-ceiling-constrained status-provider
type. `SpaceViewController.swift` (5 headroom) untouched. All comfortably within
budget.

**(b) Nested vertical NSSplitView inside the sidebar (tree + changes list)** —
heaviest. No existing container sits inside the sidebar slot today — `fileTree` IS
that slot's view controller (SpaceViewController.swift:92). Needs a NEW container
(precedent: `DocumentAreaViewController`, pulled out for the same reason) holding
`fileTree` + a new changes-list VC in an inner `NSSplitView`. New file avoids the
ceiling, but the construction site (SpaceViewController.swift init :73-79, viewDidLoad
:92) must change to install the new container instead of `fileTree` directly — a
small diff (~5-10 changed lines) against only **5** lines of headroom. Survivable
only as a like-for-like swap (`fileTree` → `sidebarContainer.fileTree` accessor), not
new logic; tightest margin of the four.

**(c) Synthetic "Source Control" root row inside the EXISTING NSOutlineView** —
requires the data source (`+OutlineView.swift:20-41`) and `FileNode` to represent two
fundamentally different row kinds (filesystem entries vs. git-status entries) under
one root. Conflicts with `FileNode`'s own stated contract — "the only part of the
file tree that is not view code — a URL, two flags and a directory read"
(FileNode.swift:5-7) — since every synthetic row breaks the `node.url`/`isDirectory`/
`reloadChildren()` assumptions at the model level, not just the view level. Bigger
structural break than (a) or (b) for no clear payoff advantage; VS Code itself uses a
separate panel, not this shape.

**(d) Segmented control at sidebar top switching Files / Source Control** — same
construction-site touch on SpaceViewController.swift as (b) (same tight budget), but
the new container itself is simpler: a show/hide swap of one visible child at a
time, matching the already-proven `DocumentAreaViewController.setStripVisible`
pattern (DocumentAreaViewController.swift:48-58) rather than a nested `NSSplitView`.

## Recommendation

**(a) decorations-only**, first. It touches no near-zero-headroom file for anything
but a trivial trigger call, stays inside `+OutlineView.swift` (191 headroom) and
`FileNode.swift` (240 headroom), and reuses the already-proven identity-preservation
mechanism rather than fighting it. A changed-files list is real value but is
squarely a (d)-shaped follow-up (preferred over (b) — no nested-split chrome for
comparable function) once decorations prove the repo-detection/worktree plumbing
works.

## Confidence / not directly verified
`SpaceWindowController.swift` and `SpaceViewController+Delegates.swift` were not read
in full (grepped only) — neither owns the tree or the sidebar's construction per
AFK.md's file table, so this is believed non-load-bearing to the seam question.
Confidence: high, since `fileTree`'s ownership and construction site
(`SpaceViewController.swift`) were read in full and are the only relevant sites.
