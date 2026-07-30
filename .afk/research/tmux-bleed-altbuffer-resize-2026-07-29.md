# Why content bleeds across tmux panes and windows in Umber

**Date:** 2026-07-29 · **Status:** root cause CONFIRMED, reproduced deterministically, **FIXED** by `patches/swiftterm/0003-trim-lines-on-narrowing-for-all-buffers.patch` and gated by `app/Scripts/check-altbuffer-resize.sh` · **Verified against:** `e3dc2f5`, vendored SwiftTerm v1.15.0 + patches 0001/0002, tmux 3.6a, `TERM=tmux-256color`

## The symptom

Running tmux inside one Umber terminal (5 panes: 3 across the top, 2 below, each a text-heavy agent REPL), stale text appears **inside the wrong pane's rectangle**, laid out at a width unrelated to the pane containing it, and it **survives switching tmux windows**. Observed instances: a ~10-column ribbon (`pull --ff-` / `only o` / `rigin main`) inside a wide pane; a ~20-column ribbon (`gent) [subagent] — 3` / `0 tool calls · 2959`); a ~7-column ribbon (`ng only` / `the cl` / `aim and`).

## Root cause

**The alternate screen buffer never narrows its lines on a resize, so a later widening resurrects cells from before the narrowing.** This is an **upstream SwiftTerm defect**, not something the local patches introduced.

The chain, all citations in `vendor/SwiftTerm/Sources/SwiftTerm/`:

1. `Buffer.swift:419-421` — `isReflowEnabled` is *nothing but* `hasScrollback`:
   ```swift
   public var isReflowEnabled: Bool {
       return hasScrollback
   }
   ```
2. `Terminal.swift:694` — the alt buffer is built with no scrollback, so `hasScrollback == false` (`Buffer.swift:285`) and therefore `isReflowEnabled == false`:
   ```swift
   altBuffer = Buffer (cols: cols, rows: rows, tabStopWidth: tabStopWidth, scrollback: nil)
   ```
3. `Buffer.swift:522-531` — but the loop that **trims each line down to the new width** lives *inside* the `isReflowEnabled` branch:
   ```swift
   if isReflowEnabled {
       reflow (newCols, newRows)
       // Trim the end of the line off if cols shrunk
       if cols > newCols {
           for i in 0..<lines.count {
               lines [i].resize (cols: newCols, fillData: CharData.Null)
           }
       }
   }
   ```
   So on a **narrowing** resize of the alt buffer, `cols` shrinks (`Buffer.swift:547`) while every `BufferLine.dataSize` stays at the old, wider value. `resizeBuffers` calls it unconditionally for both buffers (`Terminal.swift:843`).
4. Those over-wide cells are **invisible** while they sit outside `cols`, because the renderer clamps: `Apple/AppleTerminalView.swift:887` — `let maxCol = max(0, min(terminal.cols - 1, line.count - 1))`.
5. On the next **widening**, the widen loop at `Buffer.swift:437-447` fires `lines[i].resize(cols: newCols, …)`. Because `dataSize` is still larger than the new `cols`, this takes `BufferLine.resize`'s **shrink** branch (`BufferLine.swift:197+`), which copies `data[0..<cols]` **verbatim** — preserving the stale cells and pulling them back inside the visible grid.

**Ghost band = columns `[oldNarrowCols, min(newCols, originalWideCols))` of every row**, carrying text from before the narrowing. tmux painted only columns `0..<oldNarrowCols`; everything to the right of that is history the emulator invented on tmux's behalf.

### Why it looks like narrow ribbons of wrapped prose

Each resize cycle deposits one band, at the column offset and width of *that* era. Umber calls `terminal.resize` on **every** cols/rows change — `processSizeChange` (`Apple/AppleTerminalView.swift:233`) on each pixel-size change (live window drag fires once per frame that crosses a cell boundary, plus ⌘B sidebar toggle and full-screen), and `resetFont` (`:151`) on ⌘+ / ⌘- / ⌘0 zoom and ⌘R reload. A day of resizing leaves several bands, each holding text that a *differently-sized tmux pane layout* wrapped at *its* width. Rendered inside today's layout, that reads exactly as narrow ribbons of wrapped prose sitting in the wrong pane.

### Why tmux does not repaint over it

tmux owns the screen and repaints only the deltas its own screen model says changed. The emulator mutated cells tmux never wrote, so tmux's model and the grid disagree with no event to reconcile them, and a window switch is redrawn from that same stale model. `Terminal.resize` does call `refresh(startRow:0, endRow:rows-1)` (`Terminal.swift:5541`) — but that only marks Umber's *view* dirty so it redraws **from the corrupted grid**; it asks the child for nothing.

## Reproduction (deterministic, headless)

Harness: `app/Scripts/check-altbuffer-resize.sh` (four cases, 262 lines, under the ceiling). Same idiom as `check-reflow.sh`: link `.build/out/Products/Debug/SwiftTerm.o` and run a truth table. Sequence per case — enter the alt buffer with `\e[?1049h` (what tmux does once at startup), paint all rows at 80 cols via absolute CUP, `resize(cols:40)`, repaint all rows at 40 cols (what tmux does on SIGWINCH), `resize(cols:70)`, repaint again, then read back with `getBufferAsData(kind: .alt)`.

| case | asserts | pristine vendor | with fix |
|---|---|---|---|
| 1 | alt lines trimmed to `cols` on narrowing | ✗ **10/10 rows still 80 chars at cols=40** | ✓ |
| 2 | no wide-era text after narrow+widen | ✗ **10/10 rows resurrected it** | ✓ |
| 3 | control: normal buffer stays consistent | ✓ | ✓ |
| 4 | while narrow, stale cells are out of render range | ✓ | ✓ |

Case 2's failing row is the symptom in one line — tmux's fresh 40-column paint, then the ghost:

```
W01wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwGHOSTggggggggggggggggggggggggg
|<------- tmux painted cols 0..39 ------>|<-- cols 40..69, from the 80-col era -->|
```

Case 3 passing is what makes cases 1–2 mean something: the same sequence on the normal buffer (where reflow, and therefore the trim, does run) is clean, so the harness is measuring the alt-buffer path and not failing unconditionally. Case 4 pins the visibility to the **widen** step, which is why the corruption appears when you make the window *bigger*.

## Candidate fix

Hoist the trim out of the `isReflowEnabled` branch in `Buffer.swift:522-531` — it must still run *after* `reflow`, which rewraps from the old width:

```swift
 if isReflowEnabled {
     reflow (newCols, newRows)
-    // Trim the end of the line off if cols shrunk
-    if cols > newCols {
-        for i in 0..<lines.count {
-            lines [i].resize (cols: newCols, fillData: CharData.Null)
-        }
-    }
 }
+
+// Trim the end of the line off if cols shrunk. Must run for EVERY buffer, not only the
+// reflowing one: `isReflowEnabled` is just `hasScrollback` (Buffer.swift:419) and the alt
+// buffer is built with `scrollback: nil` (Terminal.swift:694), so while this sat inside the
+// branch, alt-buffer BufferLines kept their OLD width while `cols` shrank underneath them,
+// and a later widen resurrected data[0..<cols] (BufferLine.swift:197) into the visible grid.
+// Must stay AFTER reflow: reflow rewraps from the OLD width.
+if cols > newCols {
+    for i in 0..<lines.count {
+        lines [i].resize (cols: newCols, fillData: CharData.Null)
+    }
+}
```

**Applied.** Gate 4/4 with it, and 2/4 without it (cases 1 and 2 fail, control and render-range stay green) — validated by falsification, like `check-reflow.sh`. `./Scripts/check-reflow.sh` still **8/8**, so the #494 fix is unaffected. `verify-vendor.sh` exited **3** ("vendored copy is unknown") while the pin was stale, which is the integrity mechanism doing its job; the pin's `patched_buffer_swift` is now `e5166175…efaced` and it exits 0 reporting "+ 3 local patches".

**Blast radius:** small and well-fenced. The behaviour change is confined to buffers with `hasScrollback == false`, which is only ever the alt buffer (`Terminal.swift:694`, and `changeScrollback` explicitly refuses to give the alt buffer scrollback at `:5551-5553`). For the normal buffer the emitted code is identical — same loop, same position relative to `reflow`. Discarding cells beyond the new width is the *correct* semantics for a buffer with no history: that content is gone and the full-screen app repaints. The `abort()` post-condition at `Buffer.swift:535-544` only fires when a line is *shorter* than `newCols`, and trimming to exactly `newCols` satisfies it.

**Shipped as** `patches/swiftterm/0003-trim-lines-on-narrowing-for-all-buffers.patch` + `app/Scripts/check-altbuffer-resize.sh` + a regenerated `SwiftTerm.pin` + `verify-vendor.sh` taught about the third patch + AFK.md and `app/README.md`. Still worth **upstreaming**: it is a plain SwiftTerm bug that reproduces without any Umber code, #494 is still open, and a re-vendor drops `0003` along with `0002`.

## What was NOT checked

- **The end-to-end causal link to the screenshot.** The emulator defect is proven; that it is the *sole* cause of that exact image is strong inference, not a driven GUI+tmux reproduction. Cheapest confirmation: in a haunted session run `tmux refresh-client -S` (or `prefix` + `r`). Expected — a full tmux repaint clears the ghosts, and they return after the next narrow-then-widen cycle. If they *survive* a forced full redraw, something additional is in play.
- **Glyph-width divergence** (SwiftTerm vs tmux `wcwidth` on the REPL's `◇ ◆ ⚡ ✓ ⏺ ♦ → ·`, `UnicodeWidthData.swift` is the file to read). Not investigated — the dispatched agent died on a 429. Would produce per-row *shifts*, not width-mismatched ribbons, so it is a poor fit for this artifact, but it could be a second, independent bug.
- **Sequence-level handling** — pending-wrap/DECAWM at the right margin, DECSTBM region scrolling, EL/ED/ECH/ICH/DCH bounds (`cols` vs `line.count`), DECSC/DECRC. Same 429. A too-long line means `line.count > cols` for the whole alt buffer, so any erase routine bounded by `line.count` instead of `cols` is worth an audit once the fix lands.
- **Whether rows (not cols) have an analogous hole**, and whether `savedX`/`savedY` clamping interacts.
- **Live-drag coalescing:** how many `terminal.resize` calls one window drag actually emits, and whether tmux's SIGWINCH coalescing means the last few land after tmux's final repaint. Would explain severity, not existence.
- **Whether tmux is the only victim.** Any full-screen TUI that resizes lives in the alt buffer — vim, less, htop. They redraw more eagerly than tmux, which is likely why tmux surfaced it first, but the defect was never tmux-specific.
