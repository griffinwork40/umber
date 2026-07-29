# Umber editor UX — local-inspection findings (2026-07-28)

**Lens:** LOCAL-INSPECTION (repo/code reading only — no external library research; a sibling agent
covers that in `.afk/research/editor-ux-external-2026-07-28.md`).
**Scope:** what Umber's file-viewer editor does and does not do today, the seam it plugs into, every
container touchpoint an editor swap must preserve, LOC headroom, and prior planning commitments.
**Constraint honoured:** read-only on Swift sources and plan docs; no edits, no git mutations; this file
and `check-file-size.sh` output are the only artifacts produced.

---

## 1. Gap inventory

Each item: **verified-present** (read the code that does it), **verified-absent** (read the code and
confirmed no such path exists), or **could-not-determine**.

| Capability | Verdict | Evidence |
|---|---|---|
| Syntax highlighting | **verified-absent** | `FileViewerPane.swift:19-22` states it in the type doc comment ("no syntax highlighting and no tree-sitter"); `textView.isRichText = false` at `FileViewerPane.swift:129` — plain `NSTextView`, single font/color run, no `NSTextStorage` tokenizing. Zero references to `NSAttributedString` runs, tree-sitter, or any highlighter type anywhere in `FileViewerPane*.swift` (grep confirmed empty). `AFK.md:123` corroborates: "no code intelligence." |
| Line numbers / any gutter | **verified-absent** | No `NSRulerView`, no `verticalRulerView`, no gutter type anywhere in `FileViewerPane*.swift` or elsewhere in `Sources/Umber/` (grep for `gutter\|Gutter\|lineNumber\|LineNumber\|ruler\|Ruler\|verticalRulerView` returned nothing). Plain `NSScrollView` + `NSTextView`, `FileViewerPane.swift:56-57,149-158`. |
| Find & replace inside the editor | **verified-present, but borrowed, and find-only, no replace** | `textView.usesFindBar = true; textView.isIncrementalSearchingEnabled = true` at `FileViewerPane.swift:146-147`, with the adjoining comment (`:140-145`) explaining the mechanism: the same three `AppMenu.swift:107-121` Edit-menu items that drive SwiftTerm's terminal find (`performFindPanelAction:` with an `NSFindPanelAction` tag) also drive `NSTextView`'s **built-in, Apple-implemented** find bar, because `NSTextView` natively implements that selector — no Umber code runs. This is genuinely present (⌘F/⌘G/⌘⇧G/⌘E all work in the file viewer) but it is find-only: `NSTextView`'s stock find bar has no replace field, and nothing in `FileViewerPane*.swift` adds one. `AFK.md:90` calls the terminal side "one match at a time... no all-match highlighting" — a different limitation on a different document kind — but confirms search across both kinds is SwiftTerm/AppKit's, not Umber's own code. |
| Undo/redo and undo grouping | **verified-present (basic), verified-absent (explicit grouping / discoverability)** | `textView.allowsUndo = true` (`FileViewerPane.swift:130`), so `NSTextView`'s standard `NSUndoManager` integration is live — ⌘Z/⌘⇧Z work via the default responder chain (`NSResponder.undo(_:)`/`redo(_:)`, which `NSTextView` implements) even though **no Undo/Redo `NSMenuItem` exists anywhere** in `AppMenu.swift` (grep for `Undo\|Redo\|action: #selector(undo\|action: #selector(redo` across all of `Sources/Umber/*.swift` returned nothing) — confirmed empirically against `/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict` on this machine, which contains no `undo:`/`redo:` bindings either (they are hardwired into `NSTextView`/`NSUndoManager`, not the key-binding dict), so ⌘Z is real but **has no menu-bar affordance at all** — a user who doesn't know the chord has no way to discover it. No custom undo *grouping* logic exists in Umber's own code (no `NSUndoManager.beginUndoGrouping`/`setActionName` calls anywhere in `FileViewerPane*.swift`) — grouping is whatever `NSTextView`'s default per-keystroke/per-word coalescing gives for free, not tuned. The undo stack is explicitly cleared on every reload/external-change (`FileViewerPane.swift:253` `textView.undoManager?.removeAllActions()`) — deliberate, to stop ⌘Z resurrecting a stale disk revision, per the comment at `:250-252`. |
| Soft wrap | **verified-absent (by design)** | `FileViewerPane.swift:114-124`: `textView.isHorizontallyResizable = true`, `textContainer?.widthTracksTextView = false`, `containerSize` set to `.greatestFiniteMagnitude` in both dimensions — the comment (`:114-117`) states this explicitly: "Non-wrapping, horizontally scrollable: this is code, and soft-wrapping code re-flows indentation into nonsense." A deliberate choice, not an oversight, but it means long lines scroll horizontally rather than wrapping — no user-facing toggle either way. |
| Auto-indent / indent-on-newline | **verified-absent** | No `NSTextViewDelegate` method touches indentation. The only delegate callback implemented is `textDidChange(_:)` at `FileViewerPane+Editing.swift:20-22`, which only calls `setDirty(true)`. `textView(_:shouldChangeTextIn:replacementString:)` — the hook that would intercept a newline to insert leading whitespace — is not implemented anywhere. Pressing Return inserts a bare newline with zero carried-over indentation. |
| Tabs vs. spaces (insertion behaviour, tab-width) | **verified-absent** | No `defaultParagraphStyle`, no `tabWidth`, no override of `insertTab:`/`insertBacktab:` handling anywhere in `FileViewerPane*.swift`. The macOS default `NSTextView` tab-stop behaviour (a `defaultTabInterval` render width, and the raw `\t` character on Tab-key press) is whatever AppKit's stock un-configured view does — Umber neither sets a project tab width nor offers spaces-for-tabs. |
| Encoding detection and write-back encoding | **verified-present** | Read path at `FileViewerPane.swift:206-219`: tries UTF-8 first, then `String(contentsOf:usedEncoding:)` (Foundation's own charset-sniffing) as a fallback, else a placeholder message. `savedEncoding` (`FileViewerPane.swift:83`) records what the read actually used. Write path re-encodes with that *same* encoding (`FileViewerPane+Editing.swift:98-99`), and if the current buffer no longer round-trips into it (e.g. an emoji typed into a Latin-1 file), it explicitly asks the user via an `NSAlert` before silently rewriting as UTF-8 (`FileViewerPane+Editing.swift:100-111`). This is a genuinely more careful implementation than most simple viewers. |
| Large-file behaviour: is the whole file read into memory? Any size guard? | **verified-present (guard), verified-present (whole-file read within the guard)** | `FileViewerPane.swift:96-101`: hard 4 MiB ceiling (`maxBytes = 4 << 20`), with the type doc (`:96-100`) explaining why — `NSTextView` lays out the whole string up front, so a huge file would hang, not scroll slowly. `read()` (`:178-220`) does a pre-read `.fileSizeKey` stat check *and* a post-read re-check on `data.count` (`:196-199`, guarding a TOCTOU race the comment attributes to "PR #2 review, finding 3" — a file that grows between the stat and the read completing). Over the ceiling, `tooLargePlaceholder(bytes:)` (`:224-231`) substitutes an explanatory placeholder string instead of the real content. Below the ceiling, yes — the whole file is read into a `Data`/`String` and handed to `NSTextView.string` (`:186,210,214,249`) in one shot; there is no chunked/virtualized rendering. So: bounded, fail-soft, but binary at 4 MiB — no progressive loading, no "view first N lines of a huge log" affordance. |
| Dirty-state affordance (what does the user SEE when unsaved?) | **verified-present** | `isDirty` (`FileViewerPane.swift:65`) flips via `setDirty()` (`FileViewerPane+Editing.swift:31-35`) on every `textDidChange`, and the sole writer notifies `delegate?.fileViewerDidChangeEditedState(self)`, which `SpaceViewController+Delegates.swift:23-27` uses to call `syncStrip()`. The strip then draws a small unsaved dot in the tab's close-box slot (`DocumentTabStrip+Drawing.swift:156,163-168` `drawEditedDot`) — visible only when the tab is not hovered/active (hover shows the close glyph instead, `:157-158`). **No other affordance exists**: no macOS-standard "dot in the traffic-light close button" (`NSWindow.isDocumentEdited` / `representedURL`) is set anywhere — grep for `isDocumentEdited`/`representedURL` across `Sources/Umber/*.swift` returned nothing — because a Space's `NSWindow` represents a project root, not one document, so that native affordance doesn't map here; the tab-strip dot is the only signal, and the tab strip itself is **hidden entirely at a single open document** (`DocumentAreaViewController.swift:44-58`), so a lone dirty file viewer in an otherwise single-document Space shows no persistent unsaved indicator at all beyond the ⌘S menu item's enabled state (`AppDelegate.swift:44-47`). |
| The save and confirm-discard flow | **verified-present, and unusually careful** | `write()` (`FileViewerPane+Editing.swift:43-94`) is the single path to disk: no-op if not dirty/is-placeholder (`:46-47`), asks via `confirmOverwriteOfChangedFile()` (`:117-133`) if disk moved underneath the buffer since load, handles an encoding mismatch via a second alert (`:98-111`), preserves POSIX permission bits across the atomic write (`:53-83`, since `.atomic` creates a new inode), and re-stamps `loadedStamp` so the save itself is never mistaken for an external change (`:85-91`). Close-time confirm-discard is `documentShouldClose()` (`FileViewerPane+Document.swift:94-109`): a three-button alert (Save/Cancel/Don't Save) in HIG order, and it is the **single choke point** every close path in the app funnels through (`SpaceDocument.swift:146-149` states this as the protocol's contract; `SpaceViewController.closeDocument(at:)` at `SpaceViewController.swift:205-210` and `AppDelegate.applicationShouldTerminate` at `AppDelegate.swift:66-70` both call it). |
| Scroll position and selection persistence across tab switches | **verified-present for scroll position, verified-absent for selection** | Scroll: `reload(preservingScroll:)` (`FileViewerPane.swift:242-286`) captures `scrollView.contentView.bounds.origin` before reloading and restores it after forcing layout (`:274-286`), and this is called from `documentWindowDidBecomeKey()`/`refresh(diskChanged:)` (`FileViewerPane+Document.swift:64-90`) — i.e. scroll position across a *disk re-read* is preserved. But switching *tabs* does not re-run `reload()` at all on a clean, unchanged buffer — `selectDocument(at:)` (`SpaceViewController.swift:178-195`) calls `document.documentWindowDidBecomeKey()` and `documentDidBecomeActive()`, neither of which touches scroll unless disk actually changed — so scroll position survives a tab switch **only because nothing resets it**, not because it is explicitly saved/restored per-tab; the moment the file changes on disk, `reload(preservingScroll: true)` is what keeps you roughly in place. Text **selection** has no persistence logic anywhere — `documentDidBecomeActive()` (`FileViewerPane+Document.swift:27-31`) only does `makeFirstResponder(textView)`; there is no stored selection range saved/restored per document. |
| Keyboard bindings the editor adds or lacks | **verified-present (borrowed system + app chords), verified-absent (editor-specific bindings)** | Gets ⌘F/⌘G/⌘⇧G/⌘E (via `NSTextView`'s native find, see above), ⌘C/⌘V/⌘A (`AppMenu.swift:86-88`, standard `NSText` selectors, responder-chain routed), ⌘Z/⌘⇧Z (native `NSTextView`/`NSUndoManager`, no menu item), ⌘S (`AppMenu.swift:70-71` → `AppDelegate.saveDocument(_:)` → `SpaceDocument.saveDocument()`), ⌘W/⌘⌥←/⌘⌥→/⌘1-9/⌘B (all Space/document-level, not editor-specific — `AppMenu.swift:75,171-190`). `MacLineEditing.controlBytes` (`KeyBindings.swift:38-64`) — the ⌘⌫/⌘←/⌘→ line-editing byte table — is consumed **only** by `UmberTerminalView.performKeyEquivalent` (`UmberTerminalView.swift:81-107`; confirmed by grep, the only two references to `MacLineEditing`/`controlBytes` in the whole source tree are its declaration and this one call site). The file viewer gets **none of it** — ⌘⌫ (delete to start of line) and ⌘←/⌘→ (start/end of line) in the editor are whatever plain `NSTextView` does by default (its own `StandardKeyBinding.dict`-driven behaviour: `deleteToBeginningOfLine:`/`moveToLeftEndOfLine:` etc., which for a plain `NSTextView` actually already do the right thing since it isn't a terminal), so this gap is functionally harmless for the editor even though it is a real code-level gap (no editor-specific chords were ever added; it inherits, not extends). No custom editor bindings — no "duplicate line," "move line up/down," "comment/uncomment," "go to line," or any code-editing chord exists anywhere in the source. |
| Accessibility | **verified-present (baseline via NSTextView), verified-absent (any editor-specific work)** | `FileViewerPane*.swift` contains **zero** references to `Accessib`/`accessib` (grep confirmed) — no custom `NSAccessibilityElement`, no overridden accessibility methods, unlike the tab strip which has an entire dedicated file (`DocumentTabStrip+Accessibility.swift`, 226 LOC) for exactly this reason. Whatever VoiceOver support exists is 100% inherited from stock `NSTextView`/`NSScrollView`, which is generally reasonable for plain text (a real `NSTextView` is VoiceOver-navigable out of the box) — but nothing was built or verified for it, so this is "free but unverified," not "built and tested." |
| Theme integration (`Theme.swift` / `AppConfig`) | **verified-present, but narrow** | `apply(config:)` (`FileViewerPane+Document.swift:33-42`) sets `scrollView.backgroundColor`/`textView.backgroundColor` to `config.effectiveBackground`, `textView.textColor` to `config.effectiveForeground`, and re-resolves font size — so background/foreground/font DO track the active theme and ⌘R live-reload. But there is exactly one foreground colour for the *entire* buffer (`reload()`, `FileViewerPane.swift:262-264`, sets `textView.textColor` once for the whole string) — there is no concept of syntax-token colour at all, so "theme integration" here means "background/foreground/cursor tint," not "this theme's comment/string/keyword colours." Insertion point colour uses `config.theme?.cursor` (`:265`). Not system-default appearance — it does read `AppConfig`. |
| Font and zoom participation (does app-wide ⌘+/⌘−/⌘0 reach it?) | **verified-present** | `FileViewerPane` conforms to `SpaceDocument`'s zoom members (`currentFontSize`, `setFontSize(_:persist:)`, `resetFontSize()` — `FileViewerPane+Document.swift:44-58`), and `AppDelegate.zoomAllDocuments(by:)` (`AppDelegate.swift:247-256`) fans out over `allDocuments: [SpaceDocument]` (`AppDelegate.swift:235-237`, explicitly typed as the protocol, not `[TerminalPane]`, with a comment at `:230-234` naming exactly this bug class as the reason). So yes — ⌘+/⌘−/⌘0 reach the file viewer today, not just terminals. This is confirmed both by the protocol conformance and by the fan-out being over the kind-agnostic list. |

### Verified vs inferred (§1)
Every row above cites a specific line range I read directly; "verified-absent" rows are backed by an
explicit grep across the relevant file(s) returning zero hits, not by failing to notice something.
The one soft inference: I did not build/run the app to *observe* VoiceOver behaviour, ⌘Z discoverability,
or exact `NSTextView` default tab-stop width in situ — those are inferred from documented `NSTextView`/
AppKit default behaviour plus the absence of any Umber-side override, not from a captured runtime trace.
That is flagged per-row above ("whatever the stock view does") rather than asserted as directly observed.

---

## 2. Seam surface area — the `SpaceDocument` protocol, verbatim

Full protocol at `app/Sources/Umber/SpaceDocument.swift:91-154` (`@MainActor protocol SpaceDocument: AnyObject`), with its default-implementation extension at `:156-170`. Quoted verbatim by member, with the exact line each requirement sits at:

```swift
// SpaceDocument.swift:97
var documentView: NSView { get }

// SpaceDocument.swift:99
var documentTitle: String { get }

// SpaceDocument.swift:103
var documentSymbolName: String { get }

// SpaceDocument.swift:107
func documentDidBecomeActive()

// SpaceDocument.swift:111
func apply(config: AppConfig)

// SpaceDocument.swift:115
var currentFontSize: CGFloat { get }

// SpaceDocument.swift:119
func setFontSize(_ size: CGFloat, persist: Bool)

// SpaceDocument.swift:122
func resetFontSize()

// SpaceDocument.swift:130
func documentWindowDidBecomeKey()

// SpaceDocument.swift:133
var documentIsEdited: Bool { get }

// SpaceDocument.swift:144
var documentStatus: DocumentStatus { get }

// SpaceDocument.swift:150
func documentShouldClose() -> Bool

// SpaceDocument.swift:153
func saveDocument() -> Bool
```

**Hard requirements with no default** (must be written by any new conformer or it is a compile error):
`documentView`, `documentTitle`, `documentSymbolName`, `documentDidBecomeActive()`, `apply(config:)`,
`currentFontSize`, `setFontSize(_:persist:)`, `resetFontSize()` — 8 members. The doc comment at
`SpaceDocument.swift:86-90` states this is deliberate: "A default no-op would restore exactly the
failure mode just removed... Requiring them turns that into a build error at the moment the conformer
is written," referencing the historical bug where `TerminalPane`-only fan-outs silently ignored
`FileViewerPane` (`:79-84`).

**Members with a default, hence optional to override** (extension at `:156-170`):
`documentWindowDidBecomeKey()` → `{}` (no-op, `:161`), `documentIsEdited` → `false` (`:162`),
`documentShouldClose()` → `true` (`:163`), `saveDocument()` → `true` (`:164`), `documentStatus` →
`.idle` (`:169`). So a trivial read-only conformer (e.g. a diff viewer with nothing to save) can
implement only the 8 hard members and inherit sane defaults for the rest — 5 optional, 8 mandatory,
13 total.

**Is the protocol genuinely engine-agnostic, or does it leak `NSTextView`/terminal assumptions?**
Read start to finish: **no leakage found.** `SpaceDocument.swift` imports only `AppKit` (`:6`) — no
`SwiftTerm` import, no `NSTextView` type anywhere in the signature list. Every member is either a
primitive (`String`, `CGFloat`, `Bool`), an `NSView` (needed by any AppKit container — `documentView`),
or an `AppConfig`/`DocumentStatus` value type Umber itself owns. The doc comment at `:139-143` makes
this an explicit design goal: `documentStatus`'s type is "Engine-agnostic for the same reason the zoom
members are... the foundation under `TerminalPane` is already scheduled for replacement by libghostty...
and a status enum shaped around SwiftTerm's callbacks would be rewritten with it." This is corroborated
externally: the emulator-foundation plan (§8.2, quoted in §5 below) independently re-verifies "`SpaceDocument`
is genuinely clean — 4 requirements... declared in a file that imports only AppKit, with no SwiftTerm
type anywhere in it" (that count of 4 is stale relative to the current 194-line file — it predates the
`DocumentStatus`/font/close members being folded in — but the *qualitative* claim, no engine leakage,
still checks out against the file as it stands today).

**What a new document kind — or a replacement editor engine — must implement:** exactly the 8 mandatory
members above, wrapped around whatever its own view is (`NSTextView`, `STTextView`, `CodeEditSourceEditor`'s
`TextViewController`'s view, anything). Nothing in the protocol itself blocks a non-`NSTextView` engine.

### Verified vs inferred (§2)
Fully verified by direct quotation with line numbers; the one inference is the "genuinely engine-agnostic"
conclusion, which is a judgment call built on the verified absence of any SwiftTerm/NSTextView type in
the protocol file — a structural read, not a runtime test.

---

## 3. Container touchpoints — checklist an editor swap/rewrite must preserve

Verified by reading `SpaceViewController.swift`, `SpaceViewController+Delegates.swift`,
`DocumentAreaViewController.swift`, `AppDelegate.swift`, `AppMenu.swift`, `FileTreeViewController.swift`,
`SpaceWindowController.swift`.

1. **Construction / factory.** `SpaceViewController.openFile(url:)` (`SpaceViewController.swift:158-176`)
   is the *only* construction path for a `FileViewerPane` — hardcoded to that concrete type
   (`FileViewerPane(config:url:frame:)` at `:171`), not a polymorphic `add(document:)`. There is no
   generic factory; a new editor kind needs either a parallel method or this one refactored. (The
   sibling plan doc §8.2, quoted in §5, independently flags the equivalent gap on the terminal side —
   `addTerminalDocument()` hardcodes `TerminalPane(config:frame:)` the same way, `SpaceViewController.swift:141-151`
   in the current file.)
2. **Reuse-on-reopen dedupe.** `openFile(url:)` (`:159-169`) checks `documents` for an existing
   `FileViewerPane` at the resolved URL via `as? FileViewerPane` and resurfaces it instead of opening a
   duplicate tab. A concrete-type cast, not protocol-driven — an editor swap must either keep
   `FileViewerPane` as the concrete cast target or generalize this check.
3. **Activation / selection.** `selectDocument(at:)` (`:178-195`) calls `documentArea.present(documentView:)`,
   `syncStrip()`, the space delegate's title callback, then `document.documentWindowDidBecomeKey()` and
   `document.documentDidBecomeActive()` — all through the protocol, so this one is already
   engine-agnostic and needs no changes for a new conformer.
4. **Delegate callback: unsaved-state.** `FileViewerPaneDelegate.fileViewerDidChangeEditedState(_:)`
   (`FileViewerPane.swift:9-12`, implemented at `SpaceViewController+Delegates.swift:23-27`) is a
   **concrete-type delegate protocol** — it names `FileViewerPane` in its own signature, not
   `SpaceDocument`. A new editor kind needs its own delegate protocol (mirroring the pattern) plus a
   new conformance in `+Delegates.swift`, OR a generalized `SpaceDocument`-typed callback. Compare to
   `TerminalPaneDelegate` (`TerminalPane.swift:10-17`), which has the exact same concrete-type shape —
   this is a repeat-the-pattern touchpoint, not a one-off.
5. **Tab strip status.** `syncStrip()` (`SpaceViewController.swift:228-237`) reads `documentTitle`,
   `documentSymbolName`, `documentIsEdited`, `documentStatus` off every document via the protocol —
   already generic, no changes needed for a new conformer.
6. **File-tree double-click routing.** `FileTreeViewController` double-click (`FileTreeViewController.swift:119-134`)
   calls `delegate?.fileTree(self, didActivate: node.url)`, which `SpaceViewController+Delegates.swift:80-82`
   forwards straight to `openFile(url:)` — see touchpoint 1, this is the entry point that would need to
   route to a different/configurable document kind if Umber ever supported opening a file as more than
   one kind of document (e.g. "open as diff" vs "open as edit").
7. **Menu-item validation and action.** `AppDelegate.saveDocument(_:)` (`AppDelegate.swift:35-37`) and
   `validateMenuItem(_:)` (`:44-47`) both go through `focusedSpace?.activeDocument?.saveDocument()` /
   `.documentIsEdited` — protocol-typed, no concrete cast, so ⌘S already works generically for any
   conformer. No changes needed here for an editor swap.
8. **Close / dirty interception.** `documentShouldClose()` is the single choke point (see §1's
   save/confirm-discard row) — called from `SpaceViewController.closeDocument(at:)` (`:205-210`),
   `spaceShouldClose()` (`:262-265`), and transitively from `AppDelegate.applicationShouldTerminate`
   (`AppDelegate.swift:66-70`) via `hasEditedDocuments`/`spaceShouldClose()`. Fully protocol-driven —
   preserved automatically by any conformer that implements (or correctly relies on the default for)
   `documentShouldClose()`.
9. **Config/theme fan-out.** `SpaceViewController.apply(config:)` (`:241-246`) iterates `documents`
   (the full array, `[SpaceDocument]`) calling `.apply(config:)` on each — protocol-driven, no cast.
10. **Window-key fan-out (staleness re-check).** `SpaceViewController.windowDidBecomeKey()` (`:251-257`)
    iterates all documents calling `documentWindowDidBecomeKey()` — protocol-driven.
11. **Zoom fan-out.** `AppDelegate.zoomAllDocuments(by:)` (`:247-256`) — protocol-driven, see §1's font row.
12. **Window subtitle.** `SpaceWindowController.spaceViewController(_:didChangeDocumentTitle:)`
    (`SpaceWindowController.swift:257-259`) sets `window?.subtitle = title` from the protocol's
    `documentTitle` — already generic.
13. **`focusedTerminalPane` fallback logic.** `SpaceViewController.focusedTerminalPane`
    (`SpaceViewController.swift:116-125`) explicitly casts `activeDocument as? TerminalPane`, falling
    back to `terminalPanes.last` — this is a concrete-type dependency used by the file-tree's
    "insert path in terminal" gesture (`SpaceViewController+Delegates.swift:90-109`). Not an editor
    touchpoint per se (it is terminal-specific), but it demonstrates the same class of `as?`-cast
    fragility the seam otherwise avoids; any second *terminal-like* kind (e.g. `GhosttyPane`) would need
    this widened, and it is direct evidence the container is not 100% cast-free even today.

### Checklist summary (13 touchpoints, verified)
| # | Touchpoint | Protocol-generic already? |
|---|---|---|
| 1 | Construction/factory | ❌ concrete `FileViewerPane(...)` call |
| 2 | Reuse-on-reopen dedupe | ❌ `as? FileViewerPane` cast |
| 3 | Activation/selection | ✅ |
| 4 | Unsaved-state delegate | ❌ concrete-typed delegate protocol |
| 5 | Tab strip status | ✅ |
| 6 | File-tree double-click routing | ➡️ routes to touchpoint 1 |
| 7 | Menu validation/action (⌘S) | ✅ |
| 8 | Close/dirty interception | ✅ |
| 9 | Config/theme fan-out | ✅ |
| 10 | Window-key fan-out | ✅ |
| 11 | Zoom fan-out | ✅ |
| 12 | Window subtitle | ✅ |
| 13 | `focusedTerminalPane` cast (terminal-side precedent) | ❌ concrete cast (not an editor path today) |

**8 of 13 are already protocol-generic** (the `SpaceDocument`-typed fan-outs); the 3 concrete-cast ones
(construction, dedupe, the delegate) are exactly the class of gap the emulator-foundation plan
independently found on the *terminal* side (§5 below, §8.2) — i.e. this is a known, named, and
previously-diagnosed pattern in this codebase, not a new discovery unique to the editor.

### Verified vs inferred (§3)
All 13 touchpoints are cited to a specific line range I read. No inference beyond noting the structural
parallel to §8.2's terminal-side findings (which is a direct textual comparison, not a guess).

---

## 4. LOC headroom

Ran `./app/Scripts/check-file-size.sh` from `app/` (2026-07-28). **Full output:**

```
   LOC  FILE
 -----  ----
    88  Scripts/check-file-size.sh
    83  Scripts/check-keybindings.sh
   188  Scripts/check-keys-e2e.sh
   172  Scripts/check-space-restore.sh
   109  Scripts/make-app-bundle.sh
   281  Scripts/make-icon.py
   135  Scripts/verify-vendor.sh
   264  Sources/Umber/AppDelegate.swift
   214  Sources/Umber/AppMenu.swift
   289  Sources/Umber/Config.swift
   183  Sources/Umber/Defaults.swift
    82  Sources/Umber/DocumentAreaViewController.swift
    55  Sources/Umber/DocumentStatus+Presentation.swift
   276  Sources/Umber/DocumentTabStrip.swift
   226  Sources/Umber/DocumentTabStrip+Accessibility.swift
   275  Sources/Umber/DocumentTabStrip+Drawing.swift
   170  Sources/Umber/DocumentTabStrip+Mouse.swift
   110  Sources/Umber/FileNode.swift
   218  Sources/Umber/FileTreeViewController.swift
   159  Sources/Umber/FileTreeViewController+OutlineView.swift
   295  Sources/Umber/FileViewerPane.swift
   112  Sources/Umber/FileViewerPane+Document.swift
   142  Sources/Umber/FileViewerPane+Editing.swift
    65  Sources/Umber/KeyBindings.swift
    19  Sources/Umber/main.swift
   194  Sources/Umber/SpaceDocument.swift
    93  Sources/Umber/SpaceRestore.swift
   268  Sources/Umber/SpaceViewController.swift
   126  Sources/Umber/SpaceViewController+Delegates.swift
   293  Sources/Umber/SpaceWindowController.swift
    47  Sources/Umber/StarterConfig.swift
   339  Sources/Umber/TerminalPane.swift  ⚠ within 11 of the ceiling
   124  Sources/Umber/Theme.swift
   108  Sources/Umber/UmberTerminalView.swift

OK: all 34 source files within the 350-line ceiling (1 approaching it).
```
Exit code: `0`.

### Headroom table for files an editor change would plausibly touch

| File | Current LOC | Distance to 350 ceiling | Warning band (315)? | Natural seam if it grows |
|---|---|---|---|---|
| `FileViewerPane.swift` | 295 | **55** | Already inside warning band (315 − 295 = 20 short of the warning threshold itself — i.e. **already only 20 LOC from the 90% warning line**) | Pull the `read()`/`Contents`/`tooLargePlaceholder` file-loading logic (currently `:164-231`, ~68 LOC) into a new file, e.g. **`FileViewerPane+Loading.swift`**, mirroring the existing `+Editing`/`+Document` split. This is the next concern the type-doc's own "why is this longer than an editable text view has any right to be" (`:24-28`) argument would point at once syntax-highlighting or a gutter arrives — those are new concerns entirely and should be **new files from day one**, not additions to this one. |
| `FileViewerPane+Editing.swift` | 142 | 208 | No | Room to grow moderately (e.g. an encoding-picker UI) before a split is needed. |
| `FileViewerPane+Document.swift` | 112 | 238 | No | Plenty of headroom; this is the `SpaceDocument` conformance and should stay minimal by the repo's own convention (`:5-11` states it deliberately). |
| `SpaceDocument.swift` | 194 | 156 | No | If a new engine needs new protocol requirements (e.g. a gutter-toggle or a "supports syntax highlighting" capability flag), they land here; 156 LOC of headroom is comfortable unless several members are added with the repo's typical dense why-comments. |
| `SpaceViewController.swift` | 268 | 82 | No | The construction/dedupe touchpoints (§3, items 1–2) live here (`:141-176`); adding a second constructible kind (a generic `add(document:)` factory) is the most likely growth vector — moderate headroom. |
| `SpaceViewController+Delegates.swift` | 126 | 224 | No | Adding a new concrete delegate conformance (e.g. `EditorPaneDelegate`, mirroring `FileViewerPaneDelegate`) fits easily. |
| `AppDelegate.swift` | 264 | 86 | No | Already split once (`ebd79fd`, per git log) from 534 LOC down to this; an editor-specific menu action would go through `AppMenu.swift` instead per the existing convention, keeping this file's growth minimal. |
| `AppMenu.swift` | 214 | 136 | No | New editor menu items (e.g. an explicit Undo/Redo pair, "Toggle Line Numbers") land here; comfortable headroom. |
| `DocumentAreaViewController.swift` | 82 | 268 | No | Unlikely to need editor-specific changes; the strip/container split is engine-agnostic already. |
| `DocumentTabStrip.swift` | 276 | 74 | No | Owner-facing surface only, per the prompt's scope note — no editor-specific growth expected here. |
| `FileTreeViewController.swift` | 218 | 132 | No | Only touched if "open as" (edit vs. diff vs. preview) becomes a menu choice; moderate headroom. |
| `TerminalPane.swift` | 339 | **11** ⚠ | **Yes — already in the warning band, flagged by the script itself** | Not an editor file, but cited for CONTRAST per the prompt: this is the file the repo's own tooling is already telling maintainers to split *before* touching further (script output shows the ⚠ live). Illustrates how much closer the terminal-side file already is to the ceiling than any editor file. |

**Overall LOC read:** the three current editor files total 295+142+112 = **549 LOC**, none over or in
the 315 warning band except `FileViewerPane.swift` sitting 20 LOC short of it. There is real headroom
today, but it is not generous: syntax highlighting alone (tokenizing, attributed-range application, a
`NSTextStorage` subclass or a delegate hook) is very unlikely to fit inside the existing 295-line
`FileViewerPane.swift` without tripping the ceiling, and the repo's own stated convention (AFK.md:101-102,
"when a file approaches the ceiling, find its seam and pull one whole concern out... new behaviour... should
arrive as a new file conforming to an existing protocol") already anticipates this: a highlighting engine
should be its own file/type from the start (e.g. **`SyntaxHighlighter.swift`** or, if using an off-the-shelf
package, a thin `FileViewerPane+Highlighting.swift` adapter), not an addition to `FileViewerPane.swift`
itself. This is consistent with how the file split already happened once (commit `a083f5f`, "split
FileViewerPane at its seams — 486 LOC over the new 350 ceiling," confirmed via `git log --oneline` on the
three files) — i.e. **the repo has direct precedent for exactly this kind of split having already worked**.

### Verified vs inferred (§4)
The script output, exit code, and every current LOC figure are directly captured tool output, not
estimates. The "natural seam" recommendations are my inference/judgment applying the repo's own stated
convention (quoted, AFK.md:101-102) to the current file contents I read in §1 — reasonable engineering
judgment, not a citation of a decision already made in the repo.

---

## 5. Prior commitment — do the plan docs commit to, or rule out, an editor direction?

### `native-swift-terminal-afk-host.md` — the plan of record

- **Editor is explicitly named as part of the product**, not scope creep: `native-swift-terminal-afk-host.md:498`
  — *"**The editor and file tree are not scope creep. They are the product.**"* — written as a
  self-correction (§12) after the operator pushed back on an earlier (wrong) framing that had demoted
  the editor to "explicitly optional" (`:334-336`, Step 4 header, superseded by §12's correction).
- **A specific engine was investigated and explicitly deferred, not rejected**: `:198-199` — *"Editor
  (later, optional): CodeEditTextView + CodeEditSourceEditor + SwiftTreeSitter."* The evaluation table
  at `:156-166` records the same conclusion for each alternative considered: CodeEditSourceEditor's own
  README "not ready for production use" (`:160`); STTextView rejected for GPLv3-or-paid-commercial
  licensing (`:161`); Runestone rejected as iOS-only (`:162`); forking CodeEdit wholesale explicitly
  **rejected** as a base — not deferred, rejected — due to active AI/Copilot PRs and a stale SwiftTerm
  pin (`:165`), with the phrase *"Read it, don't fork it"* (`:165`).
- **`FileViewerPane` is presented as proof the seam works, with an explicit remaining gap**: `AFK.md:123`
  (not the plan doc itself, but the architecture map that tracks the plan's state) — *"editor —
  `FileViewerPane` reads and saves a file, but there is no code intelligence. `SpaceDocument` now has
  two conformers, so the seam is proven, not theoretical."*
- **No line in either document rules out improving the editor.** The closest thing to a caution is
  Step 4's original framing (superseded) and risk 4 (`:401-404` — *"'Beautiful and user-friendly as hell'
  is the actual hard part and no library provides it. The failure mode is scope-creeping into an IDE."*),
  which is a caution about scope discipline, not a prohibition on editor UX work.

### `emulator-foundation-probe-and-vendor-integrity.md` — the companion doc

- Primarily about the **terminal** engine choice (SwiftTerm vs. libghostty), not the editor — but its
  central mechanism, "probe alongside, keep it reversible," is directly transferable and the doc itself
  frames it generically:
  - `:161-165` (§5 header and opening) — *"### 5. Chosen approach: don't decide, probe — the seam makes
    the bet reversible... `SpaceDocument`... is a four-method protocol, and a second *emulator* is simply
    another document kind. Umber can host both at once, in one window, and let real use decide. This is
    exactly what plan §12.3 claimed the restructure bought — 'adding a new document kind means writing a
    conformer, not touching the container.' §5 spends that credit."*
  - `:192-193` (Step 1) — *"Add `libghostty-spm`; write `GhosttyPane: SpaceDocument` alongside — **not
    instead of** — `TerminalPane`; add a config field selecting the default document kind. Then run both
    side by side on real `agent-afk` work and answer with hands rather than theory."*
- **This pattern is stated in general terms about the protocol, not terminal-specific terms** — the
  opening sentence of §5 (quoted above) explicitly says "a second *emulator* is simply another document
  kind," generalizing the claim to "document kind," of which an editor engine is one. The mechanism —
  write the new engine as a second conformer, keep the old one live, add a config switch, decide from
  real use, delete the loser (`:203`, Step 2: *"Remove whichever conformer loses. Keeping both
  permanently is the failure mode."*) — has no `SpaceDocument`-external dependency that would make it
  terminal-specific. It would generalize to an editor-engine probe (e.g. `CodeEditorPane: SpaceDocument`
  alongside `FileViewerPane`) with the same shape: same protocol, same "8 hard members" surface (§2),
  same kill-criterion structure.
- **One important qualifier the doc itself surfaces (§8.2, quoted in full below) is that "conforming is
  not integrating."** This is the load-bearing caveat for anyone tempted to read "it's just 4 methods" as
  the whole cost: `:409-416` — *"`SpaceDocument` is genuinely clean — 4 requirements... Conforming
  `GhosttyPane` really is trivial. **But conforming is not integrating.** Every app-wide behaviour is
  routed through *concrete* `TerminalPane` types, and two `as?` casts are the whole reason a second
  conformer would be silently inert rather than loudly broken"* — followed by a table of exactly the
  same *class* of touchpoint gaps this document's own §3 found on the file-viewer/editor side
  (construction, cast-based routing, concrete-typed delegates). This is strong internal corroboration:
  the repo's own prior research, done for a different document kind, independently reached the same
  structural conclusion I reached in §3 for the editor kind.
- **Explicit refusals that bound scope regardless of which engine wins**: `:210-215` (§5, "Refuse
  regardless") name Warp-style command blocks, renderer pools, a 55-field preferences window, theme
  editors, 1300-line file-icon tables, LSP, and destructive git operations in a GUI as things not to
  build "regardless" of the SwiftTerm/libghostty decision — none of these directly veto editor UX work
  (syntax highlighting, a gutter, find/replace), though "LSP" is adjacent to "code intelligence" and is
  named as an explicit non-goal.

### Verified vs inferred (§5)
All quotations above are copied verbatim from the two plan docs with line numbers; no paraphrase
substitutes for a quote. The one inferential step is the claim that the "probe alongside, keep it
reversible" pattern *would generalize* to an editor-engine probe — that is my synthesis of the verified
quotes (the mechanism is genuinely protocol-generic, per §2's independent finding), not a line in either
document that says "and this applies to editors too." No line in either doc explicitly extends the
libghostty-probe pattern to an editor-engine decision; the generalization is architecturally sound given
what both documents independently establish about `SpaceDocument`, but it is not itself a quoted
commitment.

---

## Summary answer

**Is it hard or blocked?** Not blocked. The gap list in §1 is long (no syntax highlighting, no gutter,
no auto-indent, no replace, no accessibility work, undo present but not discoverable), but every item is
additive UI/UX work behind an already-proven, already-engine-agnostic seam (§2), with a container that is
already 8-of-13 touchpoints protocol-generic (§3) and has direct, working precedent for exactly this
kind of change (`FileViewerPane` itself, added without the container "learning anything about it" —
`FileViewerPane+Document.swift:5-11`). The binding constraint is not architecture; it is (a) the 350-LOC
ceiling forcing new concerns into new files from day one (§4) — a discipline cost, not a blocker — and
(b) the same "conforming is not integrating" tax the sibling plan doc already discovered and paid for the
terminal engine (§5) — 3 concrete-cast touchpoints (construction, dedupe, delegate) that a new editor
engine would need addressed, exactly as `GhosttyPane` needed the container regenericized first (§8.4 of
the companion plan). No prior commitment in either plan document rules out improving the editor; §12 of
the plan of record explicitly names editor + file tree as "the product," not scope creep.
