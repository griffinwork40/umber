# Sequencing the libghostty swap (plan option D)

**Date:** 2026-07-28 · **Status:** Phase 0 open (operator decision), Phase 1 authorised and in progress
**Supersedes for ordering purposes:** `emulator-foundation-probe-and-vendor-integrity.md` §8.4, which this doc
keeps but re-scopes — §8.4's item 0 is smaller than it claims, and its line citations are stale (see §2).
**Prerequisite reading:** `emulator-foundation-probe-and-vendor-integrity.md` §6 (option table + recorded
verdict), §7 (risks), §8 (dependency, container, pane, ordering); `next-sequencing-2026-07-28.md` §1
(why the editor and terminal columns are disjoint).

---

## 0. Why this doc exists, and what changed today

The recorded decision (§6.2, 2026-07-27) is "proceed with D" — replace vendored SwiftTerm with
libghostty, writing `GhosttyPane: SpaceDocument` alongside `TerminalPane` so the foundation choice
stays reversible instead of becoming a bet.

**The single strongest argument for that decision was retired on 2026-07-28.** `next-sequencing-2026-07-28.md`
§3-D justified picking libghostty over the editor thread on the grounds that *"the vendored reflow defect
silently mangles scrollback history in the product's primary surface."* That defect is now patched and
gated — `patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch` plus `app/Scripts/check-reflow.sh`,
which fails 6 of 8 cases against the unpatched tree and passes 8 of 8 against the patched one.

So D must now be justified on its remaining merits. They are real, but they are **capability** merits, not
a correctness rescue. That distinction is load-bearing: it changes the acceptance bar. There is no longer
pressure to swap fast in order to stop data loss, which means search parity can be demanded *before*
`TerminalPane` is deleted rather than promised after.

### The honest ledger, post-#494-fix

| For D | Against D |
|---|---|
| OSC 7 / OSC 133 shell integration arrives ~free; `TerminalPane.hostCurrentDirectoryUpdate` stops being a wired-but-empty callback | **Search is lost entirely.** Spike Q2 disproved it — all 8 binding spellings rejected by `performBindingAction`; only `scroll_to_top` and `jump_to_prompt:-1` accepted. Rebuild on `ghostty_surface_read_text` estimated 2–4 days (§6.1, §6.2) |
| Active upstream; no vendored-fork maintenance burden, no local patches to re-apply on upgrade | XCFramework is **not auditable text** — contradicts `AFK.md`'s all-text/diffable/scriptable convention. §7.3 records "no mitigation" |
| ~27 peer macOS-native agent terminals shipped on libghostty, most matching the shape Umber was heading for | ABI is **pre-stable**; docs state it "must be kept in sync with Zig counterparts" (§8.1) |
| The `.exec` backend owns spawn, `workingDirectory`, and `envVars` itself — retires the `Pty.swift:103` silent-`chdir` risk documented in `AFK.md` Known Risks | libghostty's keybind table is a Zig black box; chord collisions with Umber's ⌘-chords are **not statically knowable** (§8.3) |
| | We just invested in SwiftTerm correctness and a reflow gate that D eventually deletes |

## 1. Phase 0 — the decision gate (operator, not agent)

**Question:** does losing ⌘F on the primary daily driver for an estimated 2–4 days clear the bar?

This is not an agent decision. It trades a shipped (if placeholder-grade) capability against a
foundation improvement, on the machine the operator actually works in all day.

- **If yes** → Phases 2–6 proceed as written.
- **If no** → D waits; Phase 1 still ships (it is engine-independent, see below), and the editor probe
  or issue #8 goes next.

Phase 1 is deliberately placed *before* this gate because it is valuable and provable regardless of the
answer, and it is the step that makes the answer cheap to change later.

## 2. Phase 1 — regenericize the terminal column (engine-independent)

**Smaller than §8.4 item 0 claims.** §8.2's zoom and config-reload rows are **already resolved**:
`AppDelegate.swift:230-237,247-263` (zoom fan-out) and `SpaceViewController.swift:262-267`
(`apply(config:)` fan-out) already iterate `[SpaceDocument]`, and AppDelegate's own comment is
past-tense — "this *used to* flatten `terminalPanes`." Commit `3ed7c5c` (2026-07-27) fixed those when
`FileViewerPane` landed as the second conformer, roughly two hours after §8.2 was written. §8.2's
per-line evidence for those two paths is therefore stale.

Four sites remain live:

| Site | Change | Why |
|---|---|---|
| `TerminalPane.swift:10-17` — `TerminalPaneDelegate`, 3 concrete-typed methods; impl at `SpaceViewController+Delegates.swift:50-70` | widen to a `SpaceDocument`-typed `SpaceDocumentDelegate` | a second engine-backed conformer needs the same callbacks without naming a concrete pane |
| `SpaceViewController.swift:142-151` — `addTerminalDocument() -> TerminalPane`, hardcoded ctor and return type | add a polymorphic `add(document:)` **beside** it | the container must be able to accept a document it did not construct |
| `SpaceViewController.swift:114` — `terminalPanes: [TerminalPane]`, feeding `focusedTerminalPane` at :123-125 | narrow, do **not** widen | see below |
| `SpaceViewController+Delegates.swift:96,103` — `focusedTerminalPane` → `pane.view.send(txt:)` | introduce a narrow `ShellHosting` protocol with a single `send(text:)` member | `SpaceDocument` has no text-injection member, and this action must reach a *shell* |

### The one cast that must NOT widen to `SpaceDocument`

`focusedTerminalPane` is deliberate and documented: shell-directed actions ("insert this path into the
shell", from the file-tree context menu) must land in a terminal, with a fallback so the feature does not
silently no-op when a file viewer is the front tab. Widening it to `SpaceDocument` would let a path be
injected into a text editor buffer.

The correct shape is a **narrower** protocol for "document that hosts a shell" — one member,
`send(text:)` — which both `TerminalPane` and a future `GhosttyPane` conform to and `FileViewerPane`
does not. This is `next-sequencing-2026-07-28.md` §1's conclusion and it still holds.

Note also that `pane.view.send(txt:)` is a **SwiftTerm-concrete** call. The protocol member is what
decouples the caller from that API; `GhosttyPane` will satisfy it via libghostty's own text write.

### Gate for Phase 1

`TerminalPane` remains the only conformer, so this phase is provably behaviour-preserving and is fully
verifiable by `check-keybindings.sh` + `check-file-size.sh` + `make-app-bundle.sh`, with no new
instrument required. That property is the reason Phase 1 is safe to run before Phase 0 resolves.

Fold in, same commit: repair `emulator-foundation-probe-and-vendor-integrity.md`'s stale citations
(`:95`, `:98`, `:102-109`, `:211-214` → `:114`, `:123`, `:142-151`, `:103`). A stale line cite silently
misdirects the next agent, which in a repo with no CI is a real defect rather than a cosmetic one.

## 3. Phase 2 — pin the dependency (first irreversible-ish step)

```swift
.package(url: "https://github.com/Lakr233/libghostty-spm.git", .exact("1.3.2"))
```

`.exact`, **not** `from:`. The spike used a floating `from: "1.2.0"`; §8.1 names that as precisely the
mistake not to repeat against a pre-stable ABI.

Amend `AFK.md`'s all-text/diffable/scriptable convention **honestly** in the same commit (§7 risk 3). A
binary XCFramework dependency contradicts a stated project rule; the rule should be edited to say what
is now true and why, not left standing while the code quietly violates it.

## 4. Phase 3 — `GhosttyPane` + `GhosttyTerminalView`

`SpaceDocument` has **8 hard requirements**, not the 4 §8.2 claims: `documentView` (:97),
`documentTitle` (:99), `documentSymbolName` (:103), `documentDidBecomeActive()` (:107),
`apply(config:)` (:111), `currentFontSize` (:115), `setFontSize(_:persist:)` (:119),
`resetFontSize()` (:122). Five more are defaulted in the protocol extension (:156-170) —
`documentWindowDidBecomeKey()`, `documentIsEdited`, `documentShouldClose()`, `saveDocument()`,
`documentStatus` — and a terminal wants most of them anyway.

Parity checklist against `TerminalPane`:

- process start `start()` (:115-119) + `resolvedWorkingDirectory()` (:139-152) — largely retired by the
  `.exec` backend, which honours `workingDirectory` itself
- `apply(config:)` (:156-209): palette (:168), theme (:173-179), scrollback (:182), font (:186),
  `UMBER_DIAG` dump (:192-208)
- font/zoom quartet `setFontSize` / `adjustFontSize` / `resetFontSize` / `currentFontSize` (:240-262)
- DECSCUSR cursor style (:213-224)
- delegate callbacks `sizeChanged` / `setTerminalTitle` / `hostCurrentDirectoryUpdate` /
  `processTerminated` (:266-290)
- status/attention: `status`, `clearAttention()`, `isActiveDocument` (:41-46, :311-323) and bell (:328-338)
- `UmberTerminalView`'s two overrides: `performKeyEquivalent` (:81-107) and `bellDelegate` /
  `bell(source:)` (:52, :65-79)

**Plan for two files from the start.** `TerminalPane.swift` carries this surface at 339/350 lines.
`GhosttyPane` will land in the same territory, so split it on arrival — `GhosttyPane.swift` +
`GhosttyPane+Document.swift`, following the `FileViewerPane` precedent (295 + 142 + 112) — rather than
writing 340 lines and splitting under ceiling pressure later.

**Do not port from the spike** (§8.4, doc:498-499): the `asyncAfter(.now() + 2.5)` shell-readiness guess,
the stderr-only logging, and the 8-string blind search probe. **Do** reuse as reference: the dependency
coordinates, the delegate protocol names, and the `TerminalSurfaceOptions(backend:workingDirectory:)` /
`performBindingAction` / `jumpToPrompt` / `scrollToRow` call shapes — all confirmed working at
`afk/libghostty-spike` @ `123919f`, which is a throwaway `GhosttySpike` executable target, not
mergeable code.

## 5. Phase 4 — wire the four delegates the spike proved live

`TerminalSurfacePwdDelegate` (OSC 7), `TerminalSurfaceCommandFinishedDelegate` (OSC 133),
`TerminalSurfaceTitleDelegate`, `TerminalSurfaceCloseDelegate` → the widened document delegate from
Phase 1. This is where "shell integration" stops being a `Not Built Yet` line.

## 6. Phase 5 — the gate

§8.4 item 4 requires "the narrowing-with-scrollback test ... passing" as an exit condition. **That test
did not exist when §8.4 was written.** It does now: `app/Scripts/check-reflow.sh`.

One precision, so this is not over-claimed: `check-reflow.sh` links `SwiftTerm.o` and drives the Swift
`Terminal` type directly, so the *harness* does not transfer to a C-API XCFramework. What transfers is
the part that matters — the 8 cases and, critically, the **interior-hole assertion**. Every failing case
in the SwiftTerm run reported `missing 0` and `dup 0`: the corruption preserves every token exactly once
and manifests as blank rows punched into scrollback. Token counting is structurally blind to it, which is
exactly how the deleted spike gate "cleared" SwiftTerm while the defect was live.

Budget a `check-reflow-ghostty.sh` sibling. Treat "Ghostty passes the same 8 cases" as a **hard
acceptance criterion**, not a nice-to-have — the whole reason to trust a new engine is an instrument that
can see this class of bug.

Full Phase 5 gate:
1. 17-case chord parity (§8.3) — `check-keybindings.sh` semantics against `GhosttyTerminalView`
2. ⌘R, zoom, and file-tree text-inject demonstrably reaching a `GhosttyPane`
3. the 8 reflow cases passing

## 7. Phase 6 — daily-drive both, then search, then delete

Both panes coexist behind the `SpaceDocument` seam. That is the entire point of the approach and the
reason it is reversible. Delete `TerminalPane`, `vendor/SwiftTerm`, `patches/swiftterm/`, and the pin
**only after** search is rebuilt on `ghostty_surface_read_text` and the operator has actually lived in
`GhosttyPane` for a stretch of real work.

Note the interaction with G6, the multi-hour soak that "retires only through real daily use": swapping
the engine resets G6. That is a cost worth naming rather than discovering.

## 8. Explicitly deferred

- **`TerminalPane.swift` split (339/350).** Does not gate this work — `GhosttyPane` is new files. Split
  when something needs to touch `TerminalPane` itself.
- **The editor column regenericization** (`openFile` hardcoding `FileViewerPane` at
  `SpaceViewController.swift:173`, the `as? FileViewerPane` dedupe at :161-165,
  `FileViewerPaneDelegate` at `FileViewerPane.swift:9-12`). Disjoint from this work per
  `next-sequencing-2026-07-28.md` §1 — it belongs to the `CodeEditorPane` probe's first commit.
- **Widening reflow.** `check-reflow.sh` gates narrowing only; a scratch probe suggested widen-back
  restores token order even unpatched, but that is unasserted.
- **Issue #8** (`isUsableSpaceRoot` accepts a directory that cannot be entered) and **issue #10**
  (no runtime verification of ⌘T cwd / tree context menu / bell). Independent of D; #8's stated
  blocker is already resolved by `5b19630`.

## 9. Not verified / open risks

- Sixel and kitty image support under libghostty is **an inference**, not checked (§6.1).
- Search may be *declinable* rather than absent — `performBindingAction` returning `false` may mean
  "declined," not "no such action" (spike Q2 caveat). Worth one more probe before budgeting 2–4 days.
- Chord collisions between libghostty's Zig keybind table and Umber's ⌘-chords cannot be enumerated
  statically; only the 17-case parity run will surface them.
- No GUI validation of the #494 fix was performed — correctness rests on the headless harness, and
  `TerminalPane.sizeChanged` remains uninstrumented.
- This repo has no test target and no CI. Every gate above is a script someone must actually run.
