# libghostty Phase 4 — make the engine reachable, and make closing a tab free it

**Status.** Proposed 2026-08-01, written against `5b0b1ee` in worktree `afk/libghostty-phase4`
(cut from `origin/main`). Companion to `.afk/plans/libghostty-swap-sequencing-2026-07-28.md`
(§5 Phase 4, §6 Phase 5 gate, §7 delete order), which remains the sequencing authority.

Phase 3 left both emulators linked and `GhosttyPane` rendering a real shell **in a gate only** —
nothing in `app/Sources/` constructs one, so the engine is unreachable from the app and §7's
"the operator has actually lived in `GhosttyPane`" cannot begin.

---

## 1. Two of the four open questions are already answered by the code

The Phase 3 handoff listed four candidate directions. Reading the code closes two of them, and
that changes what Phase 4 is actually for.

### (a) OSC 7 → the file tree already works. It needs no new code, and the "two masters" problem is prospective, not present.

`focusedShellHost` is `(activeDocument as? ShellHosting) ?? shellHosts.last`
(`ShellHosting.swift:166-168`) — a protocol lookup, never a concrete cast. `GhosttyPane` conforms
(`GhosttyPane+Document.swift:76-99`) and answers `currentDirectory` from `reportedDirectory`,
which `terminalDidChangeWorkingDirectory` fills from OSC 7 (`:137-140`). The 750ms tick reads
exactly that property (`SpaceViewController+DirectoryFollow.swift:110-127`) and `followDirectory(_:)`
keeps its single caller (`:188-190`).

So a focused Ghostty pane **already moves the sidebar**, at ≤750ms, with the single-writer
invariant intact. The tree gains two masters only if someone wires the OSC 7 delegate to call
`followDirectory` directly. Nobody should. What remains is latency, not correctness, and the
cheapest fix preserves the invariant: have the delegate call `directoryFollowPollNow()`
(`:169-171`) so the *trigger* moves and the *writer* does not. Sequenced last, as a nice-to-have.

### (b) OSC 133 → `DocumentStatus` needs no new enum case and no new switch arm.

`.running` / `.succeeded` / `.failed` already exist and are already coloured
(`SpaceDocument.swift:26-64`, `DocumentStatus+Presentation.swift:36-54`, drawn at
`DocumentTabStrip+Drawing.swift:152-155`). The signal already arrives with its exit code and
duration (`GhosttyPane+Document.swift:184-190`). What is missing is a mutator and a **policy** —
so the code is small and the decision is the entire content. See D3.

**Therefore Phase 4's real content is:** the construction site + teardown (D1, D2), then a status
policy (D3), then the instrument (D4).

---

## 2. Decisions

### D1 — Engine choice is a config field, `TerminalEngine`, in its own file. Default stays `swiftterm`.

Config field rather than a dev-only build switch, for three reasons that a build switch cannot
give: one config line and ⌘T flips it with no rebuild; the operator can run a Ghostty tab
**beside** a SwiftTerm tab in the same window, which is what an A/B evaluation actually needs;
and §7 requires living in the engine, which means being able to switch back mid-session when
something breaks.

Shape copies `Renderer.swift` exactly — Foundation-only `String` enum, generous parsing,
`nil` → fail-soft warning at the Config seam (`Config.swift:272-278` is the precedent). It gets
its **own file** rather than living in `Config.swift`, for two reasons: `Config.swift` is at
311/350 and a Renderer-shaped field lands it inside the warning band; and a Foundation-only enum
in its own file is compilable by a headless gate, which is the only reason
`check-renderer-config.sh` exists at all.

Honest limitation, to be stated in the file header: changing `engine` and hitting ⌘R affects
**new documents only**. A live pane keeps its engine, because rebuilding a running shell's engine
underneath it would discard scrollback and the child process. `apply(config:)` must not try.

### D2 — Teardown is a required member on `SpaceDocument`, `documentWillClose()`, shipped in the same commit as the construction site.

`AFK.md` already argues the coupling: a teardown verb with no caller is the same dead-mitigation
failure class as the `diagnoseResolvedState()` that shipped uncalled. So they land together.

**Required member, not an optional companion protocol matched by cast** (the
`SpaceDocumentReporting` idiom, `SpaceDocument.swift:213-220`). The failure mode of a missed
conformance here is a silent leak of a surface *and its child process*. A required member with no
default forces all three conformers to answer in their own file: `GhosttyPane` frees the surface,
`FileViewerPane` states why it has nothing to free, and `TerminalPane` has to say what happens to
**its** child process — a question nobody has asked yet. Making that visible is a benefit of this
shape, not a cost.

Symmetry with the existing seam: `documentShouldClose() -> Bool` asks; `documentWillClose()` commits.

Mechanism inside `GhosttyPane`: nil `view.controller`, the only route to
`TerminalSurfaceCoordinator.tearDownSurface`, which does `surface?.setFocus(false)`,
`surface?.free()`, `surface = nil` (`TerminalSurfaceCoordinator.swift:311-325`). Must be
idempotent, and must not rely on `deinit` — the dependency deleted its own deinit safety net on
purpose (quoted in `GhosttyPane.swift:32-41`), and a `@MainActor` type cannot safely reach
MainActor state from `deinit` under Swift 6 regardless.

**Call sites: two. The third is deliberately refused.**

1. `closeDocument(at:)` (`SpaceViewController.swift:257-272`) — covers ⌘W, the tab-strip ×, and
   shell-exit via `documentDidTerminate` (`SpaceViewController+Delegates.swift:51-56`). This is
   the leak that matters: a long session opening and closing tabs.
2. The whole-Space close path, which today has **no document loop at all**. `windowShouldClose`
   only vetoes (`SpaceWindowController.swift:287-289`) and `windowWillClose` only persists roots
   (`:291-299`), so documents are freed by ARC alone — ⌘⇧W on a Space with five Ghostty tabs
   leaks five surfaces. This needs a loop that does not exist yet.
3. App termination (`AppDelegate.applicationShouldTerminate`, `:66-86`) is **not** wired, on
   purpose: the process is exiting, the pty master closes with it, and the child gets SIGHUP.
   A loop there buys nothing and would run teardown during quit, which is where AppKit is least
   predictable — the repo already records `windowWillClose` as unreliable on quit
   (`SpaceWindowController.swift:40-43`). Written down so a later reader does not mistake the
   absence for an oversight.

### D3 — OSC 133 status policy (the part the pane's own header left open)

`GhosttyPane+Document.swift:177-183` declines to guess at this policy and names the three open
questions. Answering them:

On `terminalDidFinishCommand(exitCode:durationNanos:)`:

| condition | status |
|---|---|
| this is the active document | **nothing** — the user is watching; a marker on the tab you are reading trains the eye to ignore markers. Same guard as the bell (`:148`). |
| `exitCode != 0` | `.failed`, regardless of duration. A fast failure is the most useful thing this signal carries. |
| `exitCode == 0` and duration ≥ 10s | `.succeeded`. This is what gives `.succeeded` a job worth having: "the build you walked away from finished." The only use of `durationNanos`. |
| `exitCode == 0` and duration < 10s | leave status alone. A green dot after every `ls` is noise. |
| `exitCode == nil` | nothing. An incomplete OSC 133 `D` marker is not evidence of failure. |

Cleared on read: `documentDidBecomeActive()` resets to `.idle`. The marker's whole job is to
label a tab you are **not** looking at; once you look, it is done.

The 10s threshold is the one taste-dependent knob. It ships as a named constant with a rationale
comment, **not** a config field — config is for decisions a user must make, and this is a default
that should be corrected by use rather than by JSON.

### D4 — The instrument: probe first, then `check-reflow-ghostty.sh` in `check-ghostty-pane.sh`'s mould

The read-back API **exists**. `ghostty_surface_read_text(surface, ghostty_selection_s, ghostty_text_s*)`
is in the pinned header (`ghostty.h:1179-1181`; `read_selection` at `:1178`, `free_text` at `:1182`),
and the dependency already calls it once: `InMemoryTerminalSession.readViewportText()` builds a
`(VIEWPORT, TOP_LEFT)…(VIEWPORT, BOTTOM_RIGHT)` selection and says in its own doc comment that it
"reads exactly the visible rows and **ignores scrollback**" (`InMemoryTerminalSession.swift:74-87`).

So the whole gate turns on **one unverified token**. `ghostty_point_tag_e` offers
`GHOSTTY_POINT_SCREEN` (`ghostty.h:417-422`) with no doc comment, no call site, and no doc-page
mention anywhere in the checkout. If `SCREEN` spans scrollback, the gate is close to a
transliteration of `check-reflow.sh`'s 8 cases. If it does not, the instrument changes shape.

**Step 0 is therefore a throwaway probe, not a commit**: seed known rows, scroll them into
history, read with `SCREEN`, and see whether history comes back. Two further unknowns ride along,
cheaper to answer in the same probe than to design around:

- **Headlessness is plausible and unproven.** `InMemoryTerminalSession` is Foundation-only
  (`InMemoryTerminalSession.swift:8-10`) and `buildSurface` wires it in
  (`TerminalController+Surface.swift:136-138`) — but `platformSetup` is still called
  unconditionally (`:131`) and the only implementations set a real `nsview`
  (`AppTerminalView.swift:84-92`).
- **Resize is pixels, not cols/rows** (`ghostty_surface_set_size`), so the harness must resolve
  cell metrics before narrowing — a failure surface `check-reflow.sh` never had.

Until the probe answers headlessness, assume `check-ghostty-pane.sh`'s shape: an offscreen
accessory `NSWindow`; exit `1` for a real assertion failure and `2` for anything environmental;
waits expressed as **conjunctions**, never disjunctions; and the **exit code** as the verdict.
Those three are lessons that gate already paid for — a disjunctive wait truncated the slower
signal and produced a confident false negative about OSC 7, and a stdout-substring verdict let a
post-print crash read as green.

Non-negotiable from §6 (plan lines 154-159): keep the **interior-hole assertion**. Every failing
SwiftTerm case reported `missing 0 / dup 0` — token counting is structurally blind to this defect,
and that blindness is exactly how the deleted spike gate "cleared" SwiftTerm while it was broken.
Add `check-altbuffer-resize.sh`'s lesson too: a **control case** on a path that must pass, so a
harness measuring the wrong thing cannot return a verdict.

---

## 3. Sequence

- **Step 0 — read-back probe (no commit).** ~30 minutes, throwaway harness. Decides D4's shape.
  Can run concurrently with Commit 1.
- **Commit 1 — the engine becomes reachable, and closing a tab frees it.** `TerminalEngine.swift`;
  the construction branch in a new `SpaceViewController+DocumentConstruction.swift`;
  `documentWillClose()` on the seam plus its three conformers; the two call sites; and the stale
  OSC 7 doc comment (`GhosttyPane+Document.swift:122-129`) corrected — it still claims OSC 7 is
  "NOT YET OBSERVED IN THIS APP … reports `pwd=-`", which the split 5a/5b gate disproved 3/3.
  Gates: `check-file-size.sh`, a new headless `check-engine-config.sh` (mapping table, in
  `check-renderer-config.sh`'s mould), `check-ghostty-pane.sh` still green, and a manual
  ⌘T/⌘W surface-and-child-process observation under `UMBER_DIAG`.
- **Commit 2 — OSC 133 → `DocumentStatus`** per D3.
- **Commit 3 — `check-reflow-ghostty.sh`** per D4.
- Then Phase 5's full gate (§6: chord parity, ⌘R/zoom/text-inject reaching a `GhosttyPane`, the 8
  reflow cases) and the soak. **Note from §7: swapping the engine resets G6**, the multi-hour soak.
- **Deferred, explicitly:** the OSC 7 → `directoryFollowPollNow()` latency nudge. It buys ≤750ms
  and touches the one invariant most worth protecting.

**Why construction precedes the instrument**, given §6 calls the 8 reflow cases a hard acceptance
criterion: that criterion gates *deleting SwiftTerm* (§7), not *reaching the engine*. Nothing can
be evaluated and §7's "lived in it for a stretch of real work" cannot start until a pane can be
constructed — and the construction site is one small file. Step 0 is the hedge: it surfaces an
unbuildable instrument before Commits 2–3 are invested, not after.

**Practicality:** this worktree has no `app/.build`, so its first `swift build` re-fetches the
51.8 MB `GhosttyKit.xcframework`. The pinned revision `b146b73` is already materialised in
`.afk-worktrees/libghostty-phase2-3` and `.afk-worktrees/libghostty-spike` if a read-only
reference is wanted without a fetch.

---

## 4. Refused / out of scope

- No engine swap on a live pane (D1).
- No teardown loop at app termination (D2.3).
- No `followDirectory` call from the OSC 7 delegate, ever (§1a).
- No new `DocumentStatus` case and no `DocumentTabStrip+Drawing` change (§1b).
- No change to `TerminalPane`'s own child-process lifetime beyond making the question visible in
  its `documentWillClose()` (D2).

## 5. Falsifiers

- If Step 0 shows `GHOSTTY_POINT_SCREEN` is viewport-only and no other read-back reaches history,
  then "Ghostty passes the same 8 cases" is **not measurable with this pin**, and §6's hard
  criterion must be renegotiated in the open — fall back to a real pty plus visible-output diff,
  and say plainly that the interior-hole assertion is weaker there.
- If a week of daily use produces no OSC 133 status that was actually useful, cut D3 rather than
  tune the 10s constant.
- If `documentWillClose()` lands and `UMBER_DIAG` still shows a surviving child process after ⌘W,
  the teardown is wrong and nilling `view.controller` was not the route.

## 6. How the claims above were reached

Every citation was read at `5b0b1ee`. Two subagent reports **conflicted** and the conflict is
recorded rather than smoothed: one found the libghostty sources absent from this worktree (true —
`app/.build` does not exist here), while another quoted them freely (also true — they exist in the
`libghostty-phase2-3` and `libghostty-spike` worktrees at the same pinned revision `b146b73`,
verified against both `Package.resolved` files). Every dependency citation in this document was
re-read directly against `.afk-worktrees/libghostty-phase2-3/app/.build/`, not taken on report.

`GHOSTTY_POINT_SCREEN`'s scrollback semantics remain the one claim here that is **inference from a
name**. That is precisely what Step 0 exists to settle, and nothing downstream should be built as
though it were already known.
