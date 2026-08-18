# Umber Editor — Competitive Analysis & Roadmap

**Date:** 2026-08-17  
**Goal:** Make Umber's built-in editor the best code editor experience in a native terminal app  
**Method:** Parallel web research (20+ editors) + full codebase audit (21 source files, 1,532 LOC editor surface)

---

## Executive Summary

Umber's editor is already **surprisingly capable** for a terminal app's built-in editor — 1,532 LOC across 8 well-factored files delivering syntax highlighting (15 language families), auto-indent, bracket pairing, go-to-line, line numbers, find/replace (via NSTextView), font zoom, theme-aware selection, and dirty-buffer protection. The architecture is clean: `SpaceDocument` protocol proven with two conformers, one-concern-per-file discipline, and 345 headless gate assertions on colour legibility.

The competitive landscape splits into two failure modes Umber should avoid:
- **Too much** (VS Code, Cursor, Windsurf): feature-rich but heavy, non-native, slow to start, and full of surfaces nobody asked for. Users who chose Umber already rejected this.
- **Too little** (plain NSTextView, TextEdit, most terminal editors): functional but reads as unfinished.

Umber sits in a unique position: **terminal-first with a native macOS editor** that shares the terminal's palette, git state, and cwd tracking. No other native macOS editor (Nova, BBEdit, CotEditor) has this handshake. The strategy is **CotEditor's philosophy applied to Nova's feature set**: behave exactly as macOS expects, be measurably correct rather than impressively clever, and let the terminal context be what makes it distinctive.

---

## Part 1: What We Have Today

### Current Feature Inventory

| Feature | Status | Quality |
|---------|--------|---------|
| Read files | ✅ | UTF-8/Latin-1/UTF-16, binary+size guards, 4 MiB cap |
| Edit and save | ✅ | ⌘S, encoding negotiation, permission preservation |
| Undo/Redo | ✅ | NSTextView built-in, stack cleared on reload |
| Find/Replace | ✅ | ⌘F/⌘G/⌘⇧G + Find and Replace — native NSTextView find bar |
| Syntax highlighting | ✅ | 15 lang families, 5 roles, regex-based, APCA-gated |
| Line numbers | ✅ | `LineNumberRulerView`, theme-aware, O(log n) draw, wrap-aware |
| Soft-wrap toggle | ✅ | Per-file from config; auto-wraps .md/.txt |
| Tab-width config | ✅ | 1–16, fail-soft per field |
| Soft tabs (tab→spaces) | ✅ | Intercepted at `shouldChangeTextIn` |
| Auto-indent | ✅ | Preserves leading WS; adds level after `{`, `(`, `[`, `:` |
| Bracket/quote auto-pairing | ✅ | `{}`, `()`, `[]`, `""`, `''`, `` `` `` |
| Skip-close | ✅ | Advances past existing closer instead of inserting |
| Delete-pair | ✅ | Backspace between empty pair removes both |
| Go-to-line | ✅ | ⌘L sheet, line→offset math |
| Font zoom | ✅ | ⌘+/⌘-/⌘0, shared with terminal zoom |
| Theme/selection colour | ✅ | Per-palette, APCA-checked, system-pair fallback |
| External change detection | ✅ | mtime+size on every focus/tab-switch |
| Close protection | ✅ | Save/Cancel/Don't Save on all close paths |
| Tab deduplication | ✅ | Re-activates existing tab by URL |
| Binary/large file handling | ✅ | NUL-byte sniff + 4 MiB cap → placeholder |
| Permission preservation | ✅ | Reads mode before atomic write, re-applies after |

### Known Limitations (from source)

1. **Syntax highlighting only works with shipped presets** — user-typed hex colours get no syntax colour (issue #28, no `Theme`→`ThemePalette` bridge)
2. **Multi-line token mis-highlighting** — block comments and raw strings spanning paragraphs mis-colour after edits until next full reload
3. **YAML/TOML backtick false positives** — mapped to `.shell` family, accepted imprecision
4. **Classic Repaired comment gap** — PINNED at Lc 21.9 vs floor 45, not a bug
5. **Selection colour doesn't reach terminal engines** — only in the editor
6. **TextKit 1 throughout** — both `LineNumberRulerView` and `NSTextView` use `NSLayoutManager`

### Files Near the 350-LOC Ceiling

| File | LOC | Ceiling% | Action needed |
|------|-----|----------|---------------|
| `SpaceDocument.swift` | 350 | **100%** | 🚨 Must split before adding anything |
| `SpaceViewController.swift` | 337 | 96% | ⚠️ One method closes it |
| `FileViewerPane.swift` | 319 | 91% | ⚠️ Split `+IO` for read path |
| `Config.swift` | 312 | 89% | ⚠️ Next stored property closes it |
| `FileViewerPane+Highlighting.swift` | 289 | 83% | ⚠️ New language families force split |

---

## Part 2: The Competitive Landscape

### What the Best Editors Do — Ranked by User Impact

#### Tier 1: Users judge you on these immediately

| Feature | Who does it best | Why it matters | Umber status |
|---------|-----------------|----------------|--------------|
| **Search with live highlighting** | VS Code, BBEdit | Single most-praised feature across all editors. Seeing matches highlighted before committing, incremental match count, regex toggle. | ✅ NSTextView find bar has this. Polish opportunity: match count, regex toggle visibility |
| **Syntax highlighting that's "natural not neon"** | Nova | Restraint over saturation. Comments dim, keywords accent, strings warm. Visual hierarchy that informs without demanding attention. | ✅ Umber's palette is APCA-gated. Already better-measured than any competitor |
| **Bracket matching + auto-pair** | TextMate (pioneered) | Type `(` get `(\|)`. Visual highlight of matching bracket. Low cost, high perceived quality. | ✅ Auto-pair done. ❌ No visual bracket-match highlight yet |
| **Native macOS text conventions** | CotEditor, BBEdit | ⌥←/⌥→ word movement, ⌃A/⌃E line start/end, Services menu, spell check, system text replacements, native scroll bars | ✅ NSTextView gives most of this free. Verify Services menu works on editor text |

#### Tier 2: Users notice once they settle in

| Feature | Who does it best | Why it matters | Umber status |
|---------|-----------------|----------------|--------------|
| **Code folding** | Every serious editor | Click gutter triangle or keyboard shortcut to collapse blocks. Users of long files depend on it. | ❌ Not implemented |
| **Symbol outline / navigation** | CotEditor ("Outline Menu"), Nova | Jump to function/class/heading. Regex-based extraction (no LSP needed). | ❌ Not implemented |
| **Sticky scroll** | VS Code, Nova | Scroll past a function, its opening line stays pinned at top. Praised specifically by reviewers. | ❌ Not implemented |
| **Multi-cursor editing** | Sublime (pioneered), VS Code | ⌘D select next occurrence. Expected by VS Code refugees. | ❌ Not implemented (needs TextKit 2 or custom selection mgmt) |
| **Column indicator / print margin** | Most editors | Visual guide at column 80/120. Simple drawing. | ❌ Not implemented |
| **Minimap** | Sublime (pioneered), VS Code | Optional file overview. Controversial — many turn it off. Optional toggle is the right answer. | ❌ Not implemented |

#### Tier 3: Differentiators for power users

| Feature | Who does it best | Why it matters | Umber status |
|---------|-----------------|----------------|--------------|
| **Command palette** | Sublime (pioneered) | ⌘⇧P, fuzzy match all commands, shows keybindings. Strong quality signal. | ❌ Not implemented |
| **Project-wide search** | VS Code, Nova, BBEdit | ⌘⇧F across all files. BBEdit's multi-file grep is legendary. | ❌ Not implemented |
| **Breadcrumbs** | VS Code, Nova | File path + symbol hierarchy at top. Umber could anchor to OSC 7 cwd. | ❌ Not implemented |
| **Inline diagnostics** | VS Code, Zed, Helix | Error squiggles + hover messages. Needs LSP or linter. | ❌ Not implemented (no LSP) |

### What Makes an Editor Feel "Premium" — The Polish Details

From the research, the "premium feel" comes from three layers:

**1. The "Feel" Layer (invisible until absent)**
- **Typography**: BBEdit and CotEditor are praised because "text rendering feels native." NSTextView gives Umber this free — never replace it with a custom pipeline.
- **Cursor behaviour**: Blink rate matches system settings. Click registers on DOWN event, not UP. (Zed has a reported "cursor lag" bug from UP-event registration — users call it "30fps after 60fps.")
- **Scroll momentum**: macOS-native inertia curve. AppKit `NSScrollView` gives this free. Editors using custom scroll (Zed, Sublime) get this wrong and Mac users notice.
- **Find highlight contrast**: Current match visually distinct from other matches. "Find next" transitions instant without jarring scroll.

**2. The "Native" Layer (passes the Mac user's gut check)**
Chris Krycho's checklist (from BBEdit/Nova trial) — what knowledgeable Mac users evaluate:
- Standard menus in standard order ✅ (Umber has this)
- ⌘, opens a *window*, not a tab or JSON file (Umber opens the JSON — CotEditor and BBEdit open a window)
- Proxy icon in title bar you can drag or right-click
- Native scroll bars following System Preferences ✅ (NSScrollView)
- Text fields responding to system-wide Emacs keybindings ✅ (NSTextView)
- Services menu items working on selected text ✅ (NSTextView)

**3. The "Restraint" Layer (inverse of feature creep)**
Nova is praised for "not shouting." BBEdit for "not much there" at base chrome. CotEditor's principle: "Less is more — avoid unnecessary complexity." Sublime's philosophy: "The focus should be on the text, not fourteen different toolbars."

**For Umber:** The editor should feel like a clear window onto a file, with affordances that appear when needed and recede when not. The text is the center of gravity.

---

## Part 3: Umber's Unique Advantages

No other native macOS editor combines these:

### 1. The Tightest Editor↔Terminal Handshake
- OSC 7 cwd tracking means the terminal *already knows* where your files are
- Git status badges in the tree are live while you edit
- `ShellHosting.send(text:)` already supports sending text to the shell — a keyboard shortcut that sends the current file path to the terminal is trivial and no other native editor does it
- "Run this file" can send `python file.py` to the active terminal — no build system needed

### 2. Unified Palette
- Editor and terminal share the same `ThemePalette` — same background, foreground, ANSI colours, syntax roles
- VS Code users frequently discover editor/terminal theme drift. Umber can't have this bug.
- 345 gate assertions prove the colours are readable. "Umber doesn't just highlight your code — it guarantees the colours are readable."

### 3. Escape-Hatch Transparency
- Anti-Warp, anti-Cursor position: you can always see exactly what the editor will do
- No AI suggestions unless explicitly invoked
- Syntax highlighting is gated and documented
- Users who chose Umber *because* it's not an AI tool will specifically value this

### 4. Terminal-First File Awareness
- No other terminal editor can build a truthful breadcrumb: `~/Projects/app/Sources/Umber/SpaceVC.swift > SpaceViewController > add(document:)`
- It already knows git root, project root, and OSC 7 working directory
- The file tree IS the project — not a separate panel bolted on

---

## Part 4: Feature Roadmap — Recommended Priorities

### Wave 1: "Surprisingly Good" (make users say "wait, this actually works?")

These features have the highest ratio of user impact to implementation effort, and most play to Umber's NSTextView foundation.

| # | Feature | Effort | Impact | Notes |
|---|---------|--------|--------|-------|
| 1 | **Bracket match highlighting** | Low | High | Cursor on `{` → highlight matching `}`. NSTextView has `showsMatchingBraces` — may be one line. If not, a custom `insertionPointDidChange` handler. |
| 2 | **"Send path to terminal"** | Low | High | ⌘⇧C sends current file path to focused shell via `ShellHosting.send(text:)`. Unique to Umber. |
| 3 | **"Run in terminal"** | Low | High | Language-detected run command sent to active shell. `SyntaxLanguage` already knows the file type. |
| 4 | **Highlight current line** | Low | Medium | Subtle background tint on the line containing the cursor. Every modern editor does this. |
| 5 | **Column guide** | Low | Medium | Vertical line at column 80/120. Config field + one `draw()` override in the ruler or text view. |
| 6 | **Trailing whitespace visualization** | Low | Medium | Dim dots for trailing spaces. Config toggle. |
| 7 | **Status bar** | Low | Medium | Cursor position (Ln X, Col Y), file encoding, language name, indent mode. Below the text view. |

### Wave 2: "This is a real editor" (remove the "viewer" stigma)

| # | Feature | Effort | Impact | Notes |
|---|---------|--------|--------|-------|
| 8 | **Code folding** | Medium | High | Fold markers in the gutter. Indent-based folding (no AST needed) works for 90% of cases — Python, YAML, and all C-family languages. Nova and BBEdit use this approach for non-LSP languages. |
| 9 | **Symbol outline / jump-to-symbol** | Medium | High | Regex-based extraction: function/class/method declarations per language. CotEditor's "Outline Menu" model — a dropdown or ⌘⇧O panel showing symbols. `SyntaxLanguage.swift` already has the language; add extraction patterns. |
| 10 | **Breadcrumb bar** | Medium | Medium | File path from git root + current symbol. Uses OSC 7 cwd for relative path. Anchored at the top of the editor view. |
| 11 | **Multi-line block re-highlighting** | Medium | High | Fix the #1 known limitation. On any edit near a block comment/string delimiter, re-highlight up/down until the token boundary is resolved. |
| 12 | **Custom hex colour syntax support** | Medium | Medium | Issue #28. Build the `Theme`→`ThemePalette` reverse bridge so user-typed hex colours produce syntax highlighting. |
| 13 | **More language families** | Low | Low-Med | Lua, PHP, R, Dart, Elixir. Each is a `SyntaxLanguage.swift` edit only. |

### Wave 3: "I don't need a separate editor" (power features)

| # | Feature | Effort | Impact | Notes |
|---|---------|--------|--------|-------|
| 14 | **Sticky scroll** | Medium-High | Medium | Pin the enclosing function/class header at the top while scrolling. Needs indent-based or regex-based scope detection. |
| 15 | **⌘D select next occurrence** | High | High | The entry point to multi-cursor. Requires custom selection management (possibly TextKit 2 migration). Start with single-next, not arbitrary multi-cursor. |
| 16 | **Command palette** | Medium | Medium | ⌘⇧P with fuzzy match over all editor commands + menu items. Unique to Umber: can also surface terminal commands and file tree actions. |
| 17 | **Project-wide search** | High | High | ⌘⇧F across all files in the Space root. BBEdit's model: results in a panel, click to open file at match. Could shell out to `grep`/`rg` for the search. |
| 18 | **File tree enhancements** | Medium | Medium | New File, Rename, Delete from context menu. Not editor features per se, but users expect them alongside an editor. |
| 19 | **Indent rainbow** | Low | Low | Subtle colour bands per indent level. Popular VS Code extension. Config toggle. |

### Explicitly NOT Building (and why)

| Feature | Why not |
|---------|---------|
| **LSP / language server** | Complexity explosion. The right model is: Umber highlights and edits files; the agent in the terminal provides intelligence. Adding LSP would make Umber compete with VS Code on VS Code's terms. |
| **Extension system** | Same trap. Every extension system eventually becomes the product. Umber's value is in being complete without one. |
| **AI code completion** | Umber is explicitly NOT an AI tool. It hosts the agent, it doesn't contain one. This is a competitive advantage, not a gap. |
| **Git staging/commit UI** | Refused in the plan of record. Terminal users use `git` in the terminal. |
| **Split editor panes** | Would require significant layout surgery on SpaceViewController. Terminal tabs + editor tabs in one strip is already unusual and good. Defer. |
| **Minimap** | Controversial, many users turn it off, and the implementation cost (custom rendering of the entire file at tiny scale) is high. Defer until there's demand. |

---

## Part 5: The Competitive Positioning Statement

**For the README / marketing:**

> Umber's editor isn't trying to replace your IDE. It's the editor that's already open — in the same window as your terminal, sharing the same theme, seeing the same git state, watching the same files. It opens in 0ms because it's already there. It highlights your code because it knows what language you're writing. It saves with ⌘S and gets out of your way.
>
> Every syntax colour is measured for readability (APCA Lc 45+ floor, dichromacy-safe). Every palette is gated by 345 automated assertions. No other embedded editor — not Warp's, not VS Code's terminal views, not any terminal's built-in — applies this standard.

**The model to emulate:** CotEditor's philosophy (behave exactly as macOS expects) applied to Nova's feature set (competent and beautiful), with the terminal context (shared palette, cwd tracking, git badges, shell integration) as the unique differentiator.

---

## Coverage Assessment

| Dimension | Confidence | Gaps |
|-----------|------------|------|
| Competitive features | **High** | micro, Lite XL, Xcode source editor not researched in depth |
| User sentiment | **Medium-High** | No systematic Reddit/HN sentiment analysis; pattern themes are solid but quote frequency not measured |
| Umber codebase | **High** | 21 files read directly, all LOC counts verified |
| Visual appearance | **Low** | No runtime observation — only source analysis. How the gutter, syntax colours, and tab strip actually look on screen is unknown |
| Performance | **Low** | 4 MiB cap is stated but re-tokenise timing at that cap is unmeasured |
| Quantitative usage data | **None** | All assessments qualitative. No data on which features drive retention |

**Tacit knowledge risk: Medium.** What makes an editor "feel right" is partly measurable (APCA contrast, scroll inertia curves, click registration timing) and partly taste (colour temperature, animation duration, gutter spacing). The measurable parts are well-covered; the taste parts require daily-driving iterations.
