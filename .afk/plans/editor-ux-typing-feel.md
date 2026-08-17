# Editor UX — "Typing Feel" Sprint

**Status:** Approved 2026-08-11
**Branch:** `editor-ux-typing-feel`
**Scope:** 8 features that transform `FileViewerPane` from "text area" to "code editor"

## Context

The editor (FileViewerPane) ships syntax highlighting, find/replace, undo/redo,
encoding detection, dirty tracking, and font zoom. What it lacks is *typing
feel* — the behaviours that make a developer recognise "this is a code editor"
within two keystrokes. Every feature here is engine-independent (plain
NSTextView, TextKit 1), additive, and reversible.

## Features — in dependency order

### 1. Config+Editor.swift (new file, ~60 LOC)

Three new fields in config.json:

```json
{ "editor": { "tabWidth": 4, "softTabs": true, "wordWrap": "auto" } }
```

- `tabWidth: Int` — 1–16, default 4. Values outside range → default + warning.
- `softTabs: Bool` — default true. Tab key inserts spaces.
- `wordWrap: WordWrapMode` — `.auto` / `.on` / `.off`, default `.auto`.
  Auto = `.markdown` family wraps, code doesn't.

Follows `Config+Theme.swift` pattern: `AppConfig.resolveEditor(…)` taking
primitives from the private `ConfigFile.EditorSpec`, fail-soft per field.

### 2. Config.swift modifications (+12 LOC → ~344)

- Add `struct EditorSpec: Decodable` to private `ConfigFile`
- Add `tabWidth: Int`, `softTabs: Bool`, `wordWrap: WordWrapMode` to `AppConfig`
- Add `WordWrapMode` enum (auto/on/off, RawRepresentable from String)
- Wire `resolveEditor()` in `load()`
- Defaults: `tabWidth: 4, softTabs: true, wordWrap: .auto`

### 3. LineNumberRulerView.swift (new file, ~170 LOC)

NSRulerView subclass. Self-contained — imports AppKit only.

**Key design decisions:**
- `clipsToBounds = true` (macOS 14+ requirement)
- `enumerateLineFragments` + `Set<Int>` dedup for wrapped-line handling
- Line-start cache: `[Int]` of UTF-16 offsets, O(n) rebuild on text change,
  O(log n) binary search per visible line during draw
- `monospacedDigitSystemFont` at 0.85× editor font size — tabular figures,
  scales with zoom
- Thickness changes deferred via `RunLoop.main.perform` (cannot tile during draw)
- Minimum 2-digit gutter width
- Extra line fragment handled (cursor on trailing blank line)
- Background matches `effectiveBackground`, subtle separator line
- Right-aligned numbers with 8pt padding

**Notifications:** `NSText.didChangeNotification`, `NSView.boundsDidChangeNotification`
(contentView — needs `postsBoundsChangedNotifications = true`),
`NSView.frameDidChangeNotification` (textView).

### 4. FileViewerPane+SmartEditing.swift (new file, ~180 LOC)

Takes the `NSTextViewDelegate` conformance from `+Editing.swift` (both
`textDidChange` and new `shouldChangeTextIn` must be in the same extension).

**Auto-indent (in `shouldChangeTextIn`):**
- When `replacementString == "\n"`: carry forward current line's leading
  whitespace
- Smart indent: after `{`, `(`, `[`, `:` → add one tabWidth of extra spaces
- Smart dedent: `}`, `)`, `]` on a line of only whitespace → remove one level

**Tab → spaces (in `shouldChangeTextIn`):**
- When `replacementString == "\t"` and `config.softTabs`: substitute tabWidth
  spaces

**Bracket/quote auto-pairing (in `shouldChangeTextIn`):**
- Pairs: `{}`, `()`, `[]`, `""`, `''`, `` `` ``
- On opener: insert pair, cursor between. With selection: wrap selection.
- On closer over existing close: skip (move cursor, reject insertion)
- On backspace between empty pair: delete both
- Don't pair inside strings/comments (check foreground colour attribute)

### 5. FileViewerPane+Navigation.swift (new file, ~80 LOC)

Go-to-line: `@objc goToLine(_:)` action. Sheet with NSTextField + Go/Cancel.
Line→offset via `lineRange(for:)` iteration. `scrollRangeToVisible` + set
insertion point.

### 6. FileViewerPane.swift modifications (+30 LOC → ~332)

- Install ruler in `init` (4 lines: create, assign to scroll view, enable)
- Add `setWrapping(_:)` method (~15 lines: toggle widthTracksTextView,
  containerSize, isHorizontallyResizable)
- Set `defaultParagraphStyle` for tab width in `reload()` or `apply(config:)`
- Expose ruler for theme/font updates
- `postsBoundsChangedNotifications = true` on contentView

### 7. FileViewerPane+Editing.swift modification (−5 LOC → ~138)

Extract `NSTextViewDelegate` conformance to `+SmartEditing.swift`. Keep
`setDirty()`, `write()`, all alerts.

### 8. FileViewerPane+Document.swift modification (+8 LOC → ~191)

In `apply(config:)`: call ruler theme/font update, call `setWrapping()` based
on config + file type.

### 9. AppMenu.swift modification (+15 LOC → ~276)

- Edit menu: "Go to Line…" (⌘L) after find items, action `goToLine:`,
  target nil
- View menu: "Word Wrap" toggle, action `toggleWordWrap:`, target nil

### 10. StarterConfig.swift modification (+5 LOC → ~62)

Add editor section to starter JSON template.

## What's OUT (deferred)

- Current line highlight (NSTextView subclass decision)
- Minimap (engine-swap territory)
- Markdown formatting shortcuts (⌘B conflicts with sidebar toggle)
- Live markdown preview
- Whitespace visualization
- Selection persistence across tab switches

## LOC budget

| File | Before | After | Ceiling | Headroom |
|------|--------|-------|---------|----------|
| Config.swift | 332 | ~344 | 350 | ~6 |
| FileViewerPane.swift | 302 | ~332 | 350 | ~18 |
| FileViewerPane+Editing.swift | 143 | ~138 | 350 | ~212 |
| FileViewerPane+Document.swift | 183 | ~191 | 350 | ~159 |
| AppMenu.swift | 261 | ~276 | 350 | ~74 |
| StarterConfig.swift | 57 | ~62 | 350 | ~288 |
| LineNumberRulerView.swift | — | ~170 | 350 | ~180 |
| FileViewerPane+SmartEditing.swift | — | ~180 | 350 | ~170 |
| FileViewerPane+Navigation.swift | — | ~80 | 350 | ~270 |
| Config+Editor.swift | — | ~60 | 350 | ~290 |

## Risks

1. **Config.swift at ~344 LOC** — in warning band. Next addition → extract.
2. **NSTextViewDelegate single-extension rule** — clean extraction, tested by build.
3. **Ruler coordinate math** — 10 documented pitfalls in research; mitigated by
   `enumerateLineFragments` + `convert(from:)` approach.
4. **Bracket pairing in strings/comments** — foreground-colour heuristic, not a
   parse. Acceptable for regex-based highlighting.

## Alternatives considered

- **ChimeHQ TextFormation** for auto-pair/indent: rejected — dependency for ~100
  LOC of work.
- **CodeEditSourceEditor** for everything: rejected — foundation-level decision,
  not a polish sprint.
- **Separate `+Ruler.swift` wiring file**: rejected — only 4–6 lines of wiring,
  not worth a file.
- **Tree-sitter for string/comment detection**: overkill for regex highlighter.

## Verification

- `swift build` must pass
- `./Scripts/check-file-size.sh` must pass (350-LOC ceiling)
- `./Scripts/check-find-menu.sh` must pass (menu tag integrity)
- Manual: .swift file (line numbers, auto-indent, Tab→spaces, bracket pairs),
  .md file (soft-wraps, line numbers correct), ⌘L (go-to-line), ⌘R (config
  reload applies editor settings), font zoom (gutter scales)
