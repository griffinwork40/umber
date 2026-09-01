# Umber Visual Design Roadmap

*Research-backed list of what would make Umber the best-looking terminal app.*
*Generated 2026-08-25 from parallel external + local codebase research.*

---

## The Thesis

The best-looking terminals share three properties: **the chrome disappears** (you notice the content, not the frame), **the defaults are beautiful out of the box** (no theme-hunting required), and **the details are crisp at every zoom level** (typography, hairlines, spacing all hold up). Umber already leads on measured legibility (345 contrast assertions, APCA-gated palettes). What it lacks is the *spatial polish* and *typographic control* that make users say "this feels premium."

---

## Tier 1 — High Impact, Achievable Now

These are the changes people would notice immediately. Each is a single-file or two-file concern.

### 1. Terminal Padding / Inner Margins
**What:** Configurable inset (padding) around the terminal content area — e.g. 4–12px on each side.
**Why:** This is the single most-cited visual improvement across r/unixporn, terminal setup blogs, and design discussions. Edge-to-edge terminal text touching the window frame looks cramped and "unfinished." Every praised terminal (Ghostty, Warp, Kitty, WezTerm) ships padding controls. Ghostty's `window-padding-x` / `window-padding-y` plus `window-padding-balance = true` (auto-center) are the gold standard.
**Config shape:** `"padding": 8` (uniform) or `"padding": { "x": 12, "y": 8 }`. Add `"paddingBalance": true` for auto-centering.
**Scope:** `TerminalPane.swift` (SwiftTerm view insets), `GhosttyPane.swift` (libghostty has native padding config), container layout.
**Default:** 4px. Subtle but immediate difference.

### 2. Font Weight / Thickening Control
**What:** A `fontWeight` or `fontThicken` config option to control text rendering weight on dark backgrounds.
**Why:** White-on-black text renders perceptibly thinner than black-on-white due to antialiasing bleed direction. Terminal.app uses `CGContextSetFontSmoothingStyle(48)` (medium dilation). Ghostty has `font-thicken`. iTerm2 has "Thin Strokes." This is especially noticeable with SF Mono at 12–14pt. Users switching from Terminal.app to Umber would immediately notice "the text looks thinner."
**Config shape:** `"fontThicken": true` (boolean, like Ghostty) or `"fontWeight": "medium"`.
**Scope:** `TerminalPane.swift` — needs `CGContextSetFontSmoothingStyle` in the SwiftTerm drawing path. Private API but used by iTerm2, MacVim, Emacs, and Terminal.app itself.

### 3. More Shipped Themes — The Big Five
**What:** Add Catppuccin Mocha, Dracula, Nord, Gruvbox Dark, and Rosé Pine as built-in presets.
**Why:** These are the top 5 most-used terminal themes globally. Users expect to type `"preset": "catppuccin-mocha"` and have it work. Catppuccin alone has ports for 500+ apps — it's the theme people match their entire desktop to. Shipping these signals "this terminal understands its audience." Each is just 20 hex values in `ThemeValues.swift`.
**Gate:** Each new palette goes through `check-theme-contrast.sh` — same 345-assertion bar as the existing five.
**Priority order:** Catppuccin Mocha (most requested) → Nord (calm crowd) → Dracula (high-energy crowd) → Gruvbox (long-session crowd) → Rosé Pine (aesthetic crowd).

### 4. Tab Strip Refinement
**What:** Visual polish pass on the document tab strip.
**Why:** The strip is functional but utilitarian. Specific improvements:
- **Tab open/close animation** — a 150ms ease-out width transition. Every native macOS tab bar animates; static insert/remove feels jarring.
- **Drag-to-reorder** — Space-level tabs get this free from AppKit; document tabs don't have it. Users expect it.
- **Active tab indicator** — a subtle 2px accent line at the bottom of the active tab (colored from theme cursor or accent), replacing the current "fill with content background" approach. This is what Ghostty and VS Code do — a small, bright signal rather than a large fill change.
- **Rounded tab corners** — a 4px corner radius on the active tab fill, matching the system aesthetic.

### 5. Split Pane Visual Polish
**What:** Theme-aware split divider + unfocused pane dimming.
**Why:** The current 1px grey divider has no theme connection. Ghostty's `unfocused-split-opacity` (dims the inactive pane to e.g. 85% opacity) is the single most praised split-pane visual feature — it creates instant visual hierarchy showing which pane has focus.
**Config shape:** `"unfocusedPaneOpacity": 0.85` (0.0–1.0, default 1.0 = no dimming). Divider color: derive from `theme.foreground @ 15%`.

---

## Tier 2 — Meaningful Polish

These don't grab headlines but compound into "this feels considered."

### 6. Line Height / Cell Metrics Override
**What:** `"lineHeight": 1.2` (multiplier on the font's natural line height).
**Why:** Default terminal line height is tight. A 1.1–1.3x multiplier is consistently recommended for readability in long sessions. Ghostty exposes `adjust-cell-height`, which is this. Also useful for fonts whose natural metrics are cramped (Iosevka) or loose (Maple Mono).
**Config shape:** `"lineHeight": 1.0` (default, natural). `"cellWidth"` for horizontal spacing.

### 7. Cursor Blink Easing
**What:** Smooth fade-in/out on cursor blink instead of hard on/off toggle.
**Why:** iTerm2's `iTermCursorBlinkFadeAnimator` does this — a 150ms ease gives the cursor a breathing quality that feels alive without being distracting. Hard blink is a 1990s holdover.
**Config shape:** `"cursorBlinkStyle": "smooth"` (smooth fade) or `"cursorBlinkStyle": "classic"` (hard toggle, default for compatibility).

### 8. System Appearance Following
**What:** `"theme": { "preset": "auto", "dark": "umber", "light": "afk-light" }`.
**Why:** Ghostty's `theme = dark:ghostty,light:ghostty-light` sets the expectation. macOS power users consider auto-switching mandatory. The architecture is ready (`AppConfig.appearance` already derives from background luminance) — it needs an `effectiveAppearance` observer to respond to system changes at runtime.
**Scope:** `SpaceWindowController.swift` (observe appearance change), `AppDelegate.swift` (fan out config reload). Documented as a known deferred item.

### 9. Background Opacity for Window Chrome Only
**What:** Configurable opacity/vibrancy for the *sidebar and tab strip only*, never the terminal content area.
**Why:** The terminal grid must stay opaque (ANSI color contract, contrast gate). But a translucent sidebar showing the desktop through the file tree is beautiful and matches the Liquid Glass direction. This is what Umber's architecture already supports — `NSSplitViewItem` sidebar material is separate from the content area.
**Config shape:** `"sidebarOpacity": 0.9` or `"sidebarMaterial": "sidebar"` (AppKit material names).

### 10. Ligature Toggle
**What:** `"ligatures": true` (default false, to match current behavior).
**Why:** Ligatures (`->`, `=>`, `!=`, `===`) are increasingly expected. JetBrains Mono and Fira Code are popular specifically because of them. Alacritty's refusal to support ligatures is the most-cited reason users leave it. SwiftTerm's CoreText path may already render them if the font supports it — this might just be exposing the toggle.
**Scope:** SwiftTerm uses `CTLine` per row; ligatures are a CoreText layout feature that may need explicit enablement via `kCTLigatureAttributeName`.

---

## Tier 3 — Delight Features

These are the things that make people screenshot their setup and post it.

### 11. Font Codepoint Map (Nerd Font Fallback)
**What:** `"fontCodepointMap": { "U+E000-U+F8FF": "FiraCode Nerd Font" }` — use a Nerd Font only for Private Use Area icon glyphs, keeping the primary font clean.
**Why:** Ghostty's single most praised font feature. Eliminates the need to patch fonts or use a separate "non-ASCII font" setting. Users get their preferred coding font + full icon support without compromise.
**Scope:** Requires font fallback chain support in the rendering path. Non-trivial for SwiftTerm; libghostty has this natively.

### 12. Background Image / Blur
**What:** `"backgroundImage": "~/wallpaper.png"` with `"backgroundOpacity": 0.95`.
**Why:** iTerm2, Kitty, and Ghostty all support this. It's a minority feature but the people who want it *love* it. Umber's opaque-content-area principle makes this tricky — the image would need to sit behind the terminal content at low opacity without breaking ANSI color legibility.
**Config shape:** `"backgroundImage"`, `"backgroundImageOpacity"` (0.0–1.0), `"backgroundImageMode": "fill" | "fit" | "center" | "tile"`.

### 13. Command Palette Animation
**What:** Slide-down or fade-in animation for the ⌘⇧P command palette.
**Why:** Currently instant `orderFront`/`orderOut`. A 100ms spring animation matches the macOS system feel (Spotlight does this). Small but noticeable.

### 14. Theme Transition Animation
**What:** Cross-fade between themes on ⌘R reload.
**Why:** Currently instant color swap. A 200ms cross-fade is what VS Code and Warp do — it signals "intentional design" rather than "config just reloaded."

### 15. Selection Highlight Refinement
**What:** Rounded selection corners (2px radius on selection rects) and subtle selection animation on mouse-up.
**Why:** Native macOS text selection has rounded corners since Big Sur. Terminal selections are still hard rectangles. A small radius on the selection fill makes it feel native.

### 16. Inline Image Rendering (Sixel / Kitty Graphics Protocol)
**What:** Display images inline in the terminal output.
**Why:** Increasingly expected for tools like `img2sixel`, `chafa`, `timg`, and rich CLI dashboards. SwiftTerm has partial sixel support. This is complex but increasingly table-stakes for "modern terminal."

---

## Tier 4 — Future Considerations

These are real but lower priority or architecturally complex.

### 17. Profiles / Per-Window Themes
Different themes per Space, or per-tab overrides. Useful for visual separation of prod vs. dev environments.

### 18. Custom CSS/GLSL Shaders
Ghostty supports custom fragment shaders for effects (CRT scanlines, retro glow, color grading). Niche but beloved by the customization crowd.

### 19. GPU-Accelerated Smooth Scrolling
Pixel-smooth scrolling rather than line-by-line jumps. Ghostty and WezTerm do this via Metal/OpenGL. Requires the Metal renderer path to be mature.

### 20. Status Bar / Breadcrumbs
A configurable bottom bar showing git branch, current directory, shell integration status. Warp and Wave Terminal do this well. iTerm2's status bar has extensive widget support.

### 21. Tab Color Indicators
Per-tab color coding (Warp does this) — useful for visually separating servers/environments in a multi-tab workflow.

---

## What Umber Already Does Better Than Most

Worth preserving and not breaking in pursuit of the above:

1. **Measured legibility** — 345 contrast gate assertions. No other terminal has this.
2. **Theme coherence** — one background color drives the entire chrome chain. No competing surfaces.
3. **No-chrome-bleed principle** — content is opaque, glass stays in the frame. This is *correct* per Apple's Liquid Glass spec.
4. **The `umber` and `classic-repaired` palettes** — OKLCH-designed, dichromacy-safe, falsification-validated. `classic-repaired` is the current default (since 2026-08-20, was `umber` from 2026-08-03). Both are contrast-gated to a standard no other terminal matches.
5. **Native macOS tabs for Spaces** — real system tabs with all the behaviors people expect, for free.
6. **350-LOC ceiling** — every file stays readable, which means every file stays *editable*. Don't trade this for visual features.

---

## Suggested Implementation Order

If starting tomorrow, this sequence maximizes visible impact per commit:

1. **Terminal padding** (Tier 1, #1) — single biggest visual upgrade, probably < 50 LOC
2. **Catppuccin Mocha preset** (Tier 1, #3 partial) — ~20 hex values in ThemeValues.swift, instant community credibility
3. **Font thickening** (Tier 1, #2) — makes SF Mono look right, one CGContext call
4. **Unfocused pane dimming** (Tier 1, #5) — adds visual hierarchy to splits
5. **Tab strip active indicator** (Tier 1, #4 partial) — a 2px accent line, small code change
6. **Line height override** (Tier 2, #6) — readability multiplier
7. **System appearance following** (Tier 2, #8) — architecture is ready, just needs the observer
8. **The remaining Big Five themes** (Tier 1, #3) — one per commit, each gated

---

*Sources: r/unixporn, r/macOS, r/commandline, Hacker News terminal threads, Ghostty docs + GitHub issues, Warp design blog, iTerm2 source, Kitty docs, MOLTamp terminal design guide, oklch-terminal-themes project, Catppuccin ecosystem docs, Apple Liquid Glass WWDC25 sessions, init.Habits 2026 survey.*
