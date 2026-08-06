# Syntax highlighting, theming and chrome in the editor — feasibility brief

**Date:** 2026-08-03 · **Branch:** `afk/add-editor-syntax-highlighting` · **Status:** research complete, nothing implemented
**Question asked:** *"would we be able to add syntax highlighting / theme / ui stuff to the txt / code editor?"*

**Answer: yes — and cheaper than the 2026-07-28 brief implies, because that brief priced the work
against TextKit 2 and this editor is TextKit 1.** The theme half is already 90% wired and its remaining
gap is a colour the repo already measured and never used. The highlighting half is buildable in a shape
this repo can actually *gate*, which no dependency option offers.

Supersedes nothing. Reads as a delta against `.afk/research/editor-ux-decision-2026-07-28.md`, which
remains correct on every point except the one corrected in §2.

---

## 1. What already works — the theme plumbing is not the problem

The editor is not a second-class citizen of the config system. It is fully wired:

- `apply(config:)` (`FileViewerPane+Document.swift:33-42`) installs `config.effectiveBackground` /
  `effectiveForeground` and re-resolves the font size.
- ⌘R reaches it: `AppDelegate.reloadConfig` (`AppDelegate.swift:187-200`) → `SpaceViewController.apply(config:)`
  (`SpaceViewController.swift:294-299`) loops `documents` as `[SpaceDocument]`.
- ⌘+ / ⌘− / ⌘0 reach it: `AppDelegate.zoomAllDocuments` / `resetFont` (`AppDelegate.swift:247-263`) fan out
  over `allDocuments: [SpaceDocument]`.
- It already uses the *terminal's* font — `Self.resized(config.font, to: fontSize)`
  (`FileViewerPane.swift:261`, `+Document.swift:49`) — so it is monospaced and zoom-reactive for free.

Nothing about font or colour is hardcoded. So "add theming to the editor" is not new plumbing; it is
**more slots through plumbing that exists**.

### The one gap worth calling a bug

`ThemePalette.selection` is a designed, measured colour that **nothing in the app consumes**. Its own
doc comment says so: *"Not yet wired to either engine — both can express it"*
(`ThemeValues.swift:37-41`). AFK.md's Known Risks records the same gap. Grep confirms the three
palettes define it (`ThemeValues.swift:84,114,127`) and no consumer reads it.

`NSTextView` takes it directly, via `selectedTextAttributes`. **The editor can be the first consumer of
a colour this repo already designed and measured** — roughly five lines, closing a documented gap rather
than opening a new surface. This is the highest value-per-line item in the whole question.

## 2. The correction: this editor is TextKit 1, and that reprices everything

The 2026-07-28 brief's §5.4 says **"Do not hand-roll TextKit 2 highlighting"** and prices line numbers
and highlighting against *"TextKit 2's asynchronous, viewport-driven layout"* plus a Feedback bug list
(FB19698121 viewport layout, FB13290979/FB13291926 ruler geometry). That refusal is correct **about
TextKit 2** and it is not what this editor is.

Evidence, from the shipped source:

- `NSTextView()` — default init, no subclass (`FileViewerPane.swift:57`), inside a hand-built
  `NSScrollView()` (`:56`).
- Zero occurrences of `NSTextLayoutManager`, `textLayoutManager`, or `usesTextKit` anywhere in `app/`.
- It already calls the legacy surface directly: `textView.layoutManager?.ensureLayout(for:)`
  (`FileViewerPane.swift:280`), `textView.textContainer` (`:122-124`).
- `isRichText = false` (`:129`).

So the view runs in **TextKit 1 compatibility mode** — by API usage, not by a stated decision (there is
no flag; the absence is itself worth recording).

Why this matters: attribute-based highlighting on TextKit 1 is a fourteen-year-old, well-documented
recipe, not the frontier the cited maintainer quotes describe. Both quotes the prior brief leans on are
explicitly about TK2 — krzyzanowskim's 2025-08-14 postmortem (*"TextKit 2 might not be the best tool for
text editing UI"*) and Neon's README (*"extremely hard with TextKit 2… may not be possible without new
API"*). Neither is an argument against TK1 highlighting. The strongest external datapoint for TK1:
**CotEditor — 8k stars, mature, shipping — still uses a regex-based highlighter today** and is only now
migrating to tree-sitter for v7.0, citing nested/injected syntax as the reason
([coteditor#1919](https://github.com/coteditor/CotEditor/issues/1919)).

The same correction applies to line numbers: the ruler-geometry FBs are TK2 bugs. On TK1 a gutter is
`scrollView.hasVerticalRuler = true` plus an `NSRulerView` subclass measuring through `NSLayoutManager`.

**Known trap, and it is the whole difficulty:** never restyle inside `NSTextStorage.processEditing()` —
that is what produces caret jumps and scroll jiggle (documented 2012 → 2017, Christian Tietze's writeup
is the definitive one). Drive from `textDidChange(_:)`, scope to the edited paragraph, fall back to a
full re-highlight only when a block delimiter (`/*`, `"""`) is touched. Wrap writes in
`beginEditing()`/`endEditing()`.

## 3. The three things asked about, separated by cost

| Piece | Shape | Rough cost | Gateable? |
|---|---|---|---|
| **Theme — selection colour** | `selectedTextAttributes` from `ThemePalette.selection` | ~5 lines, 1 file | data already gated |
| **Theme — syntax colour slots** | new fields on `ThemePalette` (`ThemeValues.swift`, Foundation-only) | ~30 lines | **yes**, `check-theme-contrast.sh` |
| **Highlighting — tokenizer** | new `SyntaxRules.swift`, pure Foundation: text + language → ranges | ~150–250 lines/language family | **yes**, new single-file harness |
| **Highlighting — application** | `textDidChange` → paragraph-scoped `textStorage.setAttributes` | ~60–100 lines in a new `FileViewerPane+Highlighting.swift` | no (imports AppKit) |
| **Chrome — line numbers** | new `LineNumberRulerView.swift`, `NSRulerView` subclass | ~150–200 lines | no (imports AppKit) |
| **Config** | `syntax`/`editor` section, fail-soft per field | ~40 lines in a new `Config+Editor.swift` | partially |

## 4. The strongest argument for building rather than adopting: this repo's gates

This project has **no test target and no CI**. Its entire verification surface is single-file `swiftc`
harnesses that compile *one shipped, view-free source file standalone* and assert a truth table —
`check-theme-contrast.sh` hard-fails if its unit imports AppKit (`:66-73`).

That constraint selects the answer:

- A **pure Foundation tokenizer** ("given this text and this language, which ranges are keyword / string
  / comment / number") is exactly the shape of `KeyBindings.swift`, `ShellDirectory.swift`,
  `GitStatus.swift`, `CommandOutcome.swift`, `Renderer.swift` — files written view-free *specifically*
  so a harness can compile them. A syntax highlighter's hard part is a **string-to-ranges function**,
  which is the most testable thing in the app. It would arrive with a real truth table on day one.
- Every dependency option puts that function behind something the harness cannot compile alone:
  tree-sitter behind a C target, Highlightr behind JavaScriptCore + minified JS, CodeEditSourceEditor
  behind a prebuilt binary and 12 transitive packages. Adopting means the tokenizer is **permanently
  ungateable here** — the same accepted-unverified category as the file tree's icons.
- The colour half lands in `ThemeValues.swift`, which `check-theme-contrast.sh` already compiles. Note
  the reachability is real but **not automatic**: the harness's loops name fields explicitly
  (`check-theme-contrast-harness.swift:39-47` and onward), so a new slot compiles but stays *inert*
  until asserted by hand.
- And it is the right place for the measurement. Syntax colours are precisely where unmeasured colour
  choices fail — comment grey is the canonical APCA Lc-36 failure, and this repo fixed that exact bug in
  tab labels six days ago (0.55 → 0.72 alpha). A syntax palette that ships through this gate is a
  measured claim; one that ships inside a dependency's theme file is a taste claim.

Counter-argument, stated plainly: a regex/scanner tokenizer will be *wrong* where tree-sitter is right —
nested interpolation, injected languages (JS in HTML), and anything needing a real parse. CotEditor's
v7.0 migration is that argument made by the most credible possible source. The honest framing is that a
hand-rolled tokenizer is correct for **5 languages at ~90% fidelity**, and that the ceiling is real.

## 5. The dependency options, and one new cost on the recommended path

| Candidate | License | Dep shape | Maintained | Verdict here |
|---|---|---|---|---|
| **CodeEditSourceEditor** | MIT | source + **prebuilt binary XCFramework** for all grammars (CodeEditLanguages), 12 transitive deps, transitive SwiftUI link | last tag `0.15.2` 2025-09-16; live *"not ready for production use"* banner | plan of record's choice — **but see below** |
| **SwiftTreeSitter + Neon** | BSD-3 | source-text; one SPM package per language; C targets; Neon has an explicit TK1 interface | active, v0.10.0 2026-03-18 | the correct answer *if* many languages / nested syntax is the goal |
| **STTextView** | **GPLv3 or paid** | source | very active | already rejected in plan §4.3; still right |
| **Highlightr** | MIT (+ BSD js) | minified `highlight.min.js` in JavaScriptCore | **self-declared unmaintained** | no |
| **Splash** | MIT | pure Swift, zero deps, emits `NSAttributedString` | frozen, last tag 2021 | Swift-only grammar; useful as a *reference*, not a dep |
| **Apple first-party** | — | — | — | **no public API exists** — absent from three consecutive WWDC TextKit sessions; Xcode's own lives in private `IDESourceEditor` |

**The new cost the 2026-07-28 brief did not have:** CodeEditSourceEditor's grammars ship as a single
**prebuilt binary XCFramework** (`CodeLanguagesContainer.xcframework.zip`, via
[CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages)). That brief flagged the
production banner and the transitive SwiftUI link but not the binary shape. This repo took exactly that
trade three days ago with libghostty and recorded it in AFK.md as *"a real convention loss with no
mitigation"* (probe plan §7 risk 3). Taking it a **second** time, on a dependency that ships its own
"not ready for production" warning, to obtain a function that could otherwise be the most gate-friendly
file in the app, is a materially worse deal than the brief's table suggests.

Also worth knowing: there is currently an open SPM import regression in core tree-sitter on Xcode 26 /
Swift 6.3 ([tree-sitter#5523](https://github.com/tree-sitter/tree-sitter/issues/5523)) — UNCONFIRMED
whether it affects SwiftTreeSitter consumers specifically.

## 6. The constraints that actually bite

1. **LOC ceiling, measured directly (AFK.md's table is stale for two entries).** `Config.swift` is
   **327/350** — already past `check-file-size.sh`'s 315 warning band (AFK.md says 316) — so a new config
   section *must* get its own `Config+Editor.swift`, the precedent `Config+Theme.swift` set at 355 LOC.
   `ThemeContrast.swift` is **204** (AFK.md says 186). `SpaceDocument.swift` (342) and `TerminalPane.swift`
   (346) are effectively out of room; neither needs to change for this work. The editor files have room:
   295 / 142 / 126.
2. **No gate touches `FileViewerPane` today — at all.** The only mention is a comment beside
   `check-find-menu.sh`'s own throwaway `NSTextView` (`:96`). So highlighting ships unverified *unless*
   the tokenizer is split out as a pure file with its own harness. That split is the deliverable, not the
   diff.
3. **Fail-soft config is non-negotiable.** One bad field → one stderr warning → that field defaults.
   Never throws (`Config+Theme.swift:19-22`).
4. **Gate reachability splits at the `import AppKit` line.** Tokenizer and palette: verifiable.
   Attribute application and the gutter: not, and saying so is the house convention.
5. **The three concrete-cast touchpoints matter only if a second editor *kind* is the route.**
   Construction is hardcoded (`SpaceViewController.swift:192`), reopen-dedupe casts
   `as? FileViewerPane` (`:183-184`), and `FileViewerPaneDelegate` names the concrete type
   (`FileViewerPane.swift:9`). Highlighting *inside* `FileViewerPane` touches none of them; a
   `CodeEditorPane: SpaceDocument` probe touches all three, and the prior brief's warning applies
   verbatim — *"conforming is not integrating"*, a second editor kind would be silently inert rather
   than loudly broken.

## 7. Recommendation

**Build it in place, as a pure tokenizer plus a gated palette, not behind a new document kind and not
behind a dependency.** Ordered:

1. **`ThemePalette.selection` → `selectedTextAttributes`.** ~5 lines, closes a documented gap, gives a
   measured colour its first consumer.
2. **Syntax colour slots on `ThemePalette` + assertions in `check-theme-contrast-harness.swift`.** The
   colours become a measured claim before any code paints with them. Cheapest possible ordering: the
   gate precedes the feature.
3. **`SyntaxRules.swift` — Foundation-only, view-free — plus `check-syntax-rules.sh`.** Start with the
   languages this repo is edited in: Swift, JSON, Markdown, shell. Validate by falsification, house
   style: a deliberately naive rule set must *fail* the harness.
4. **`FileViewerPane+Highlighting.swift`** — `textDidChange`-driven, paragraph-scoped,
   `beginEditing`/`endEditing`. Never `processEditing`.
5. **`Config+Editor.swift`** — fail-soft `syntax` on/off + per-language enable.
6. **Line numbers last**, as `LineNumberRulerView.swift`. Independent of 1–5; ungateable; daily-drive
   territory.

Revisit tree-sitter **only** if step 3 hits its documented ceiling in real use — nested interpolation or
an injected language actually annoying the operator. That is the falsifier: if a week of editing in
Umber produces a highlighting bug that a regex cannot fix in principle, adopt SwiftTreeSitter + Neon
(source-text, BSD, TK1 interface) and delete `SyntaxRules.swift`. Not before.

## 8. What was not checked

- Nothing was built or run. No `swift build`, no bundle, no observation of the editor at runtime.
- No performance measurement. The 4 MiB read guard is verified present (`FileViewerPane.swift:96-101`);
  how paragraph-scoped re-highlighting behaves at that ceiling is unmeasured, and is the first thing a
  harness should measure once it exists.
- `vendor/SwiftTerm` is gitignored and absent from this worktree, so "no reusable tokenizer in the
  dependencies" rests on `Package.swift` plus a zero-hit grep across `app/`, not a vendor read.
- Sizes not confirmed: tree-sitter generated `parser.c` per language, `highlight.min.js`, Splash total
  LOC. Whether Neon's historical TK2 invalidation bug (#20) is fixed today: UNCONFIRMED, and irrelevant
  under a TK1 path.
- No claim is made about *taste*. The 2026-08-03 theme work established that four automated passes each
  satisfied more constraints while producing noise, pastels, neon, then mint. A syntax palette that
  passes the contrast gate is legible, not good.
