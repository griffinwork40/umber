# Can Umber's editor UX be improved? — decision brief

**Date:** 2026-07-28 · **Branch:** `afk/research-editor-ux` · **Status:** research complete, nothing implemented
**Question asked:** *"would it be impossible to improve the ui/ux of the editor?"*

**Answer: no — and the framing is inverted. The architecture is the easiest part of this problem. The
engine was already chosen a year ago. The genuinely hard part is the part no library ships.**

Evidence base, both written the same day and both independently verified:
- `.afk/research/editor-ux-local-2026-07-28.md` — 393 lines, every claim line-cited against source
- `.afk/research/editor-ux-external-2026-07-28.md` — 194 lines + a post-hoc correction pass; 6 engine
  options, URL + version on every claim
- Three independent shadow verifiers re-derived the load-bearing external claims from primary sources;
  one claim was **partially refuted** and is corrected in place (see that file's header table).

---

## 1. Why it is not impossible — three structural facts

**The seam is proven, not theoretical.** `SpaceDocument` (`SpaceDocument.swift:91-154`) is 8 mandatory
members + 5 defaulted, in a file that imports **only AppKit** — no SwiftTerm type, no `NSTextView` type,
nothing engine-shaped anywhere in the signature list. A replacement editor engine implements those 8
members around whatever view it owns. `FileViewerPane` itself is the existence proof: it was added
without the container learning anything about it (`FileViewerPane+Document.swift:5-11`).

**The container is already mostly generic.** 8 of 13 integration touchpoints route through the protocol
(activation, tab-strip status, ⌘S validation, close/dirty interception, config fan-out, window-key
fan-out, zoom fan-out, window subtitle). Zoom already reaches the editor today —
`AppDelegate.zoomAllDocuments(by:)` (`AppDelegate.swift:247-256`) fans out over `[SpaceDocument]`, not
`[TerminalPane]`, with a comment naming exactly that bug class as the reason.

**The 350-LOC ceiling is a discipline cost, not a blocker.** `FileViewerPane.swift` is 295/350 and the
three editor files total 549. Syntax highlighting will not fit in place — but the repo's convention says
it shouldn't: new concerns arrive as new files. There is direct precedent (`a083f5f` split
`FileViewerPane` from 486 LOC into the current three). `check-file-size.sh` currently exits 0 across 34
files, with only `TerminalPane.swift` (339) in the warning band.

## 2. The finding that reframes the question

**The plan of record already made this decision, in 2026-07, and this research independently
re-confirmed it a year later with current data.**

`native-swift-terminal-afk-host.md` §4.3 and §5 already record:

| Option | Plan's recorded verdict |
|---|---|
| CodeEditTextView + CodeEditSourceEditor | **"Take off the shelf if/when an editor is built"** — but flags its "not ready for production use" README |
| STTextView | **"Rejected"** — *"GPLv3-or-paid-commercial. Fine personally, a license trap on any future distribution."* |
| Runestone | **"iOS-only as shipped. Out."** |
| CodeEdit as a fork base | **"Rejected."** *"Read it, don't fork it."* |
| Zed | *"Rust + GPUI, not Swift. The non-native alternative."* |

§5's committed approach: *"Assemble, don't build… **Editor (later, optional):** CodeEditTextView +
CodeEditSourceEditor + SwiftTreeSitter."*

And §12, as an explicit self-correction after operator pushback:
**"The editor and file tree are not scope creep. They are the product."**

So there is no open engine question. This research's real contribution is four things the plan did not have:

1. **The plan's biggest unstated risk is now closed.** "Take off the shelf" assumed
   CodeEditSourceEditor is usable from pure AppKit. That is now **verified from the literal source**:
   `public class TextViewController: NSViewController` (line 19, `import AppKit` line 8, tag `0.15.2`,
   commit `424453d2`). The SwiftUI `SourceEditor` is a thin `NSViewControllerRepresentable` *around* it —
   AppKit is the primary surface, SwiftUI the convenience layer. MIT, `.macOS(.v13)`.
2. **Two integration caveats the plan could not have known.** `gutterView`/`minimapView` are
   **internal**, not public cross-module — the gutter is configurable but not directly manipulable
   without a fork or upstream PR. And the package links SwiftUI.framework transitively (its find panel
   uses `NSHostingView`), even though the caller writes zero SwiftUI.
3. **The STTextView rejection is re-confirmed, and the platform risk beneath it is now documented.**
   GPLv3-or-commercial re-verified from `LICENSE.md`. More interestingly, STTextView's maintainer — the
   person with the deepest TextKit 2 expertise on the platform — published on **2025-08-14**: *"the
   TextKit 2 API and its implementation are lacking and unexpectedly difficult to use correctly… I've
   started to think that TextKit 2 might not be the best tool for text layout, especially when it comes
   to text editing UI."* (verified by fetching the post directly). ChimeHQ's Neon README converges
   independently: flicker-free viewport highlighting is *"extremely hard with TextKit 2… may not be
   possible without new API."* **Two maintainer-level sources agree the hard part is Apple's framework,
   not any wrapper — which is precisely why "assemble, don't build" was the right call.**
4. **A maintenance-tempo signal that is the one real argument against the plan's choice.**
   CodeEditSourceEditor's last tagged release is `0.15.2` (2025-09-16); last push 2026-04-20 — roughly
   three months quiet — and the maintainers' own **"not ready for production use"** banner is still live
   as of today. Not abandoned. Not reassuring either.

## 3. What the research changes about *sequencing*

The instinct "improve the editor UX ⇒ swap the engine" is wrong on cost ordering. Most of what makes an
editor feel bad here is **not** engine-gated.

### Tier 0 — cheap wins, zero engine change, available on today's plain `NSTextView`

Ranked by embarrassment-per-line-of-code:

| Win | Why it's cheap | Current state |
|---|---|---|
| **Dirty indicator for a lone document** | The tab strip is hidden at a single document (`DocumentAreaViewController.swift:44-58`), and the unsaved dot lives *in the strip* (`DocumentTabStrip+Drawing.swift:156,163-168`). So a single unsaved file in a Space shows **no persistent unsaved indicator at all**. Worst UX bug found; smallest fix. | verified-absent |
| **Undo/Redo menu items** | ⌘Z/⌘⇧Z work via `allowsUndo = true` (`FileViewerPane.swift:130`), but **no Undo/Redo `NSMenuItem` exists anywhere** in `AppMenu.swift`. A user who doesn't know the chord cannot discover it. Two menu items. | verified-absent |
| **Find *and replace*** | Find already works — `usesFindBar = true` (`:146-147`) means AppKit's own find bar responds to the same tagged Edit-menu items that drive SwiftTerm's terminal find. Replace needs the remaining `NSFindPanelAction` tags wired as menu items — the identical pattern `AppMenu.swift:107-121` already uses. | find-only today |
| **Jump-to-line** | Pure application code against `scrollRangeToVisible`; engine-independent. | verified-absent |
| **Soft-wrap toggle** | Currently hard-disabled *by design* with a good reason (`:114-124`: soft-wrapping code "re-flows indentation into nonsense") — but there is no toggle either way. Config field + one call. | no toggle |
| **Selection persistence across tab switches** | Scroll position survives only because nothing resets it; selection has no persistence logic at all (`FileViewerPane+Document.swift:27-31` only sets first responder). | verified-absent |
| **Tab width / spaces-for-tabs** | No `defaultParagraphStyle`, no tab-width setting, no `insertTab:` handling — stock AppKit defaults. | verified-absent |

None of these require a dependency, a probe, or a decision. Several are single-digit-LOC.

### Tier 1 — the two affordances that genuinely justify the engine swap

**Line numbers** and **syntax highlighting**. Hand-rolling either on plain `NSTextView` means writing an
`NSRulerView`/overlay synced to TextKit 2's *asynchronous, viewport-driven* layout — exactly the surface
where the cited bug list lives (FB19698121 viewport-layout, FB13290979/FB13291926 ruler-geometry, the
latter noted "fixed again in macOS 15.6", implying it regressed between fixes). This is the work
CodeEditSourceEditor has already absorbed.

**Recommended shape, following the house pattern:** write `CodeEditorPane: SpaceDocument` *alongside*
`FileViewerPane`, not instead of it — the same reversible-probe structure
`emulator-foundation-probe-and-vendor-integrity.md` §5 defines for `GhosttyPane`, whose §5 opening
generalises itself: *"a second emulator is simply another document kind."* Note this generalisation to
editors is **architecturally sound but not a quoted commitment** — no line in either plan doc extends
the probe pattern to editors.

**And heed that doc's own caveat, which applies verbatim here: "conforming is not integrating."**
(`:409-416`). Three touchpoints use concrete casts and would leave a second editor kind *silently inert
rather than loudly broken*:
- construction — `FileViewerPane(config:url:frame:)` hardcoded at `SpaceViewController.swift:171`
- reuse-on-reopen dedupe — `as? FileViewerPane` at `SpaceViewController.swift:162-163`
- the unsaved-state delegate — `FileViewerPaneDelegate` names the concrete type (`FileViewerPane.swift:9-12`)

(Independently re-derived by grep, not taken on the sub-agent's word. `SpaceViewController.swift:114,124`
show the identical pattern already biting on the terminal side.)

## 4. The honest counter-argument

Two, both worth stating plainly.

**The engine is not the UX.** The plan's own risk 4 says it best: *"'Beautiful and user-friendly as hell'
is the actual hard part and no library provides it. The failure mode is scope-creeping into an IDE."*
Adopting CodeEditSourceEditor buys highlighting, a gutter, folding, a minimap, find, and jump-to-definition.
It buys **zero** taste. Every Tier-0 item above is taste work, which is why they should come first —
they are also the items that would still be missing after a successful engine swap.

**The recommended dependency carries its maintainers' own production warning.** A live "not ready for
production use" banner plus ~3 months without a tagged release is a real risk on the critical path of a
"beautiful and user-friendly as hell" product. It is mitigated — not erased — by the protocol seam
making the choice reversible, and by MIT licensing making a vendor-and-patch fallback legal (unlike
STTextView, where GPLv3 makes that the expensive option).

## 5. Recommendation

1. **Ship Tier 0 first.** Cheap, engine-independent, immediately felt, and orthogonal to any later swap.
   Start with the lone-document dirty indicator and the missing Undo/Redo menu items.
2. **Regenericize the three concrete-cast touchpoints before any engine work** — it de-risks
   `CodeEditorPane` and `GhosttyPane` with the same change, and the companion plan already reached this
   ordering independently for the terminal side (§8.4).
3. **Then, and only then**, run a timeboxed `CodeEditorPane: SpaceDocument` probe against
   CodeEditSourceEditor, kept alongside `FileViewerPane` with a config switch, decided by real use —
   and delete the loser, because keeping both permanently *is* the failure mode (§5 Step 2).
4. **Do not** hand-roll TextKit 2 highlighting, adopt STTextView (licensing, already rejected), embed
   Neovim (modal editing directly contradicts the product bar), or reach for a WKWebView editor. Each is
   argued with sources in the external file.

## 6. What was not checked

- The app was not built or run; no runtime observation of VoiceOver, undo discoverability, or actual tab
  width. Those rows are inferred from stock AppKit behaviour plus verified absence of any override.
- No controlled performance benchmark exists (or was found) for CodeEditSourceEditor or STTextView on
  macOS 14/15 with large files. The 4 MiB read guard (`FileViewerPane.swift:96-101`) is verified present;
  how a real engine behaves at that ceiling is unmeasured.
- CodeEditSourceEditor was **not** actually compiled against this package. Everything in §2 is a source
  read, not a build. The probe in step 3 is what converts that into evidence.
- Scintilla/ScintillaCocoa was surfaced late by a verifier and is dated but not source-verified; it is
  recorded in the external file for completeness and is **not** recommended.
