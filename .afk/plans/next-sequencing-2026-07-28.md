# Next sequencing — after the editor-UX research

**Date:** 2026-07-28 · **Branch:** `afk/research-editor-ux` · **Status:** proposed, nothing implemented
**Input:** three competing threads left unsequenced by the prior session, plus `/ground-state` ground truth.

This doc exists because the prior session's handoff named three threads and explicitly declined to
choose between them. One of the three turns out to rest on a claim that is **wrong**, which changes
the ordering. That correction is §1; the plan is §3.

---

## 1. Correction: "the container regenericization" is not one unblock, and not a blocker

`editor-ux-decision-2026-07-28.md` §5 item 2 says regenericizing the concrete casts *"de-risks
`CodeEditorPane` and `GhosttyPane` with the same change."* **That is false.** They are two disjoint
sets of touchpoints with zero overlap:

| Gates `CodeEditorPane` (editor-side) | Gates `GhosttyPane` (terminal-side) |
|---|---|
| `openFile` hardcodes `FileViewerPane(config:url:frame:)` — `SpaceViewController.swift:173` | `addTerminalDocument(...) -> TerminalPane` hardcodes the ctor + return type — `SpaceViewController.swift:142-143` |
| reuse dedupe `as? FileViewerPane` — `SpaceViewController.swift:161-165` | `focusedTerminalPane` / `terminalPanes` — `SpaceViewController.swift:114,123-124` |
| `FileViewerPaneDelegate` names the concrete type — `FileViewerPane.swift:9-12` | `TerminalPaneDelegate` callbacks name the concrete type — `SpaceViewController+Delegates.swift:49,56,65` |

No single change touches both columns. So "regenericize first, then probe" buys nothing for the
probe you *don't* run next. **Do each column as the first commit of its own probe, not as a
prerequisite sprint.**

### And the dangerous-sounding half is already safe

The prior framing implied a second document kind risks *silent* failure, including around unsaved
work. Checked against the protocol: it does not. `SpaceDocument` already declares **as protocol
members** `documentIsEdited`, `documentStatus`, `documentShouldClose()`, and `saveDocument()`
(`SpaceDocument.swift:133-155`), and that file's own comment states `documentShouldClose()` is
*"the single choke point between a dirty buffer and silent data loss"* — every close path funnels
through it. `FileViewerPaneDelegate` is **repaint-only** (`FileViewerPane.swift:10-11`: *"the Space
repaints the tab's dot"*), and its single call site just refreshes the strip
(`FileViewerPane+Editing.swift:34` → `SpaceViewController+Delegates.swift:24`).

So a new editor conformer that forgets the delegate has a **stale dot**, not lost work. Cosmetic.
Worst case in the editor column is the dedupe: a duplicate tab per re-open. Also cosmetic.

### One cast that must NOT be regenericized

`focusedTerminalPane` (`SpaceViewController.swift:118-125`) is deliberate and documented — shell-directed
actions ("insert this path into the shell") must land in a *terminal*, with a fallback so the feature
doesn't silently no-op when a file viewer is the front tab. If `GhosttyPane` lands, the correct change
is a **narrower protocol** for "document that hosts a shell", not widening to `SpaceDocument`.

## 2. The other two threads, resolved

**Tier-0 editor fixes: yes, first — and the top item has a better fix than the research found.**
The research doc correctly identifies the lone-document dirty indicator as the worst bug / smallest
fix, but the implied remedy (surface the strip) fights a deliberate decision:
`DocumentAreaViewController.swift:44-47` hides the strip at one document *on purpose* — *"with one
terminal open this app should still just look like a terminal."* Don't fight it. Use
**`NSWindow.isDocumentEdited`**, which draws the native macOS unsaved dot in the window's close
button, works with the strip hidden, and is **verified unused anywhere in the codebase** (grep,
2026-07-28). The hook already exists: `SpaceViewController+Delegates.swift:24` already receives the
edited-state change. ~3 lines, platform-correct, zero conflict with either probe.

**libghostty spike: pushed. Done, this session.** `afk/libghostty-spike` was local-only in a locked
worktree — the single unrecoverable item on the board. Verified safe to push first (8 objects unique
to it, largest blob 7,530 bytes; the 51.8MB `GhosttyKit.xcframework` is **not** in git, it is an SPM
artifact — commit `123919f` is 3 files / 228 insertions). Now at `origin/afk/libghostty-spike`.

**Does losing ⌘F change the libghostty calculus? It re-prices it, it does not flip it.** Per
`AFK.md`, SwiftTerm's search is *one match at a time, selection-based, no all-match highlighting*.
So the trade is not "good search → no search"; it is "placeholder search → no search, then build the
first good one." That weakens the strongest argument against Option D. *(Not re-derived by running
the app this session — repo-documented only.)*

## 3. Proposed sequence

**A. Tier-0 wave — now, engine-independent, orthogonal to both probes.**
1. Lone-document dirty indicator via `NSWindow.isDocumentEdited`.
2. Undo/Redo `NSMenuItem`s in `AppMenu.swift` (verified-absent; ⌘Z already works via
   `allowsUndo = true`, `FileViewerPane.swift:130` — the chord is simply undiscoverable).
3. Find **and replace**: wire the remaining `NSFindPanelAction` tags, same pattern as
   `AppMenu.swift:107-121`. Every find item must keep its `tag`.

**B. Land the research.** `afk/research-editor-ux` is 1 docs-only commit, pushed, in sync. Fast-forward
it into `main`. No PR — on a private solo repo with no CI, a PR for a docs commit is ceremony.

**C. Housekeeping (cheap, unblocks nothing but stops noise).** Add `.afk-worktree-meta.json` to
`.gitignore` (untracked in 5 worktrees). Then triage `afk/ux-integration` (broken upstream ref →
`[gone]`, 23 behind) and `afk/ux-tab-strip` (4 unique commits, 37 behind) — ground-state found their
patch-ids **do not** match main's same-titled commits, so this needs a real behavioral diff before
any delete, not a title match.

**D. Then pick ONE probe. Recommendation: libghostty, not the editor.** Rationale: the vendored
reflow defect silently mangles scrollback *history* in the product's primary surface
(`Buffer.swift:1171,1211` write `isWrapped` at a screen-relative index while adjacent content writes
use buffer-absolute `_y + _yBase`), Option D is already the recorded decision, and the spike already
renders a login shell. The editor's Tier-1 dependency still carries a live "not ready for production
use" banner and ~3 months without a tagged release — additive polish that can wait.

**E. Open decision worth taking first (cheap, independent).** The 2-line vendor patch for the
reflow defect. `AFK.md` declines it as *"moot post-libghostty"* — but that assumes libghostty lands
soon, which is precisely what is uncertain, and the bug corrupts history *today*. Recommend patching
under `patches/` (the repo already treats that as a deliberate, auditable surface) to decouple
correctness from the foundation timeline.

## 4. Explicitly deferred, with reasons

- **`TerminalPane.swift` split (339/350).** Does *not* gate libghostty — `GhosttyPane` is a new file.
  It gates only edits to `TerminalPane` itself. Split when something needs to touch it.
- **`CodeEditorPane` / CodeEditSourceEditor.** Behind (D). Nothing in Tier-0 depends on it.
- **The editor-column regenericization.** First commit of the `CodeEditorPane` probe, per §1.

## 5. Not checked

- No behavioral diff of `afk/ux-tab-strip` / `afk/ux-integration` against main (item C is the work).
- The search-quality claim is repo-documented, not observed at runtime.
- Nothing in §3 was implemented; the app was not built or run this session.
