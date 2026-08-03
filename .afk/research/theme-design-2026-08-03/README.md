# Designing Umber's theme — 2026-08-03

The question was "design the best possible theme for Umber". This is the argument, the
measurements behind it, and an honest account of the four ways the process was wrong before
it was right. The shipped result is `ThemePalette.umber` in
`app/Sources/Umber/ThemeValues.swift`, gated by `app/Scripts/check-theme-contrast.sh`.

**Thesis.** Umber's best theme is a *warm* umber-black base — the pigment the app is named
for, against a field of uniformly cold blue-blacks — with an ANSI 16 whose lightness is
placed so that every claim it makes is a measured number: contrast per slot, normal-versus-
bright separation, and colour-blind separation on the pairs a terminal's meaning rides on.

---

## 0. The blocker that had already been lifted (and never propagated)

The repo said a custom palette could not ship as the default. `AFK.md`, `Config.swift:59-62`
and `StarterConfig.swift:46-52` all carried the same reason:

> installing a background or foreground makes SwiftTerm regenerate ANSI indices 16–255 by
> interpolating them

**That is true of SwiftTerm and false of Umber, and has been false for a while.**

**Credit where it is due: this was already known.** `~/.config/umber/config.json` records it
under `// theme`, dated 2026-08-02 — *"that cost is gone, TerminalPane sets
ansi256PaletteStrategy = .xterm first (TerminalPane.swift:165)"*. So this section is a
re-derivation, not a discovery. Its value is that the correction never propagated: `AFK.md`,
`Config.swift:57-62`, `StarterConfig.swift:46`, `app/README.md` and
`GitStatus+Presentation.swift:40-42` all still asserted the old claim, and one of them was
using it as a live argument. Those are now fixed. Verified independently on the main path,
three ways:

1. `TerminalPane.swift:165` sets `view.getTerminal().ansi256PaletteStrategy = .xterm`
   unconditionally, *before* any colour is installed.
2. `Terminal.swift:523,538` gate the rebuild on `if options.ansi256PaletteStrategy != .xterm`
   — so under `.xterm`, setting background or foreground rebuilds nothing.
3. `installPalette` → `rebuildAnsiPalette` → `setupDefaultAnsiColors(strategy: .xterm)` →
   `generateXtermPalette` (`Colors.swift:169-190`) appends the **literal** standard cube
   (`0x00,0x5f,0x87,0xaf,0xd7,0xff`) plus 24 greys and never reads bg/fg at all.

So a 16-colour palette can be installed today and indices 16–255 stay the exact xterm cube.
The stated blocker is stale documentation, not a live constraint. Two consequences:

- Shipping a designed palette is viable. (Whether it becomes the *default* is §7.)
- `GitStatus+Presentation.swift:40-42` cites this same stale claim as one of two reasons the
  sidebar refuses to source its git tints from the ANSI palette. That reason is now void.
  **The refusal is still correct** — the surviving reasons (at `theme == nil` there is no
  palette to read; system colours adapt to Increase Contrast and to the window's appearance)
  are the load-bearing ones. It is right for fewer reasons than it claims.

### 0a. This also answers an open question in the config

The same file carries a `// theme-history` note from 2026-08-02: `afk-dark` was tried on a
**ghostty** pane, *"looked muddy, so it was reverted"*, then paired back with swiftterm — with
the stated discriminator that if the muddiness follows the palette across engines then the
palette is the cause, and if it does not then ghostty's rendering is (bold-to-bright mapping
and glyph rasterisation being the two things that differ).

The measurements say **the palette is a sufficient cause, and no engine needs to be blamed.**
`afk-dark` scores second-worst of nine on the normal ring (min Lc 41.4) and, more to the point,
fails the two axes that produce exactly the percept "muddy":

- **ANSI 8 at Lc 13.1.** Dim text — compiler progress, timings, paths, `--stat` separators —
  sits barely above the background. That is what a muddy terminal looks like.
- **Six of its eight normal/bright pairs are identical** (`#F85149`/`#F85149`,
  `#5BA8FF`/`#5BA8FF`, …), so bold collapses onto plain and the output loses a whole level of
  visual hierarchy.

Both are properties of the 19 hex values alone and are engine-independent, which is why the
discriminator would have read "follows the palette". `umber` was designed against precisely
these two failures: ANSI 8 at Lc 51.5, and all eight ring pairs separated and correctly
ordered. If muddiness on ghostty *also* has a rendering component, it will now show up as a
residual on a palette that no longer contributes one — which makes `umber` a better probe for
that question than `afk-dark` was.

## 1. What the field actually scores

Nine palettes, transcribed from their own published values, measured by the same code that
judges Umber (`benchmark_themes.py`). Full table in that script's output.

| | fg Lc | ANSI 1–6 mean | min | ANSI 8 | ring dE | CVD min |
|---|---|---|---|---|---|---|
| catppuccin-mocha | 80.0 | 72.6 | 54.7 | 16.9 | **0.000** | 0.070 |
| **UMBER** | **87.0** | 62.0 | 49.5 | **51.5** | **0.078** | 0.083 |
| tokyo-night | 73.8 | 59.2 | 49.4 | 10.3 | **0.000** | **0.000** |
| rose-pine | 86.8 | 57.8 | 24.9 | 25.0 | **0.000** | 0.064 |
| github-dark | 77.5 | 53.8 | 52.1 | 29.3 | 0.048 | 0.025 |
| afk-dark | 77.5 | 52.5 | 41.4 | 13.1 | **0.000** | 0.045 |
| nord | 80.3 | 49.7 | 27.9 | 10.3 | **0.000** | 0.033 |
| xterm-default | 107.9 | 44.9 | 14.0 | 34.3 | 0.078 | 0.129 |
| gruvbox-dark | 81.9 | 35.2 | 22.8 | 33.9 | 0.110 | 0.033 |
| solarized-dark | **39.5** | 34.7 | 27.7 | **0.0** | 0.042 | 0.055 |

Four facts fell out, none of them visible by reading hex:

1. **Every one of the nine leaves its comment colour unreadable.** ANSI 8 is what nearly
   every tool uses for de-emphasised output — compiler progress, timings, paths. APCA's floor
   for readable non-body text is 45. The field scores 0.0–34.3. Solarized Dark's is *exactly
   zero*: literally invisible. For a terminal whose job is hosting a coding agent's output,
   this is the largest legibility win available anywhere in the palette.
2. **Tokyo Night, Catppuccin, Nord and Rosé Pine ship identical normal and bright chromatic
   slots** (dE-OK 0.000). SwiftTerm renders bold from the bright half by default
   (`useBrightColors`), so bold text in those themes is indistinguishable from plain. This
   independently reproduces the upstream bug reports (microsoft/terminal#14887,
   catppuccin/catppuccin#1961, cli/cli#1743).
3. **Every one has a colour-blind collision** on a pair a terminal depends on. Tokyo Night's
   blue/magenta is 0.000 — identical under dichromacy.
4. **No theme has a warm-chromatic background.** The field is hue 219–291° (cold). Gruvbox
   *looks* warm and measures `#282828` — chroma 0.000, a pure neutral grey. The niche the
   app's own name points at is empty.

WCAG hides all of this. It rates Tokyo Night's normal slots 4.9–9.2:1 — "AA pass" — while
APCA puts the worst at Lc 49, below the readable floor. On near-black backgrounds WCAG
overstates contrast, which its own successor documentation says outright. Every threshold
here is written against APCA; WCAG is reported alongside and not trusted alone.

## 2. The physics, which set the targets

`frontier.py` maps what is reachable rather than assuming a round number is.

- At chroma ≥ 0.10 the APCA ceiling is **red 68.3 / blue 66.6** but **green 96.6 / cyan
  92.3**. APCA weights luminance per channel (R .213, G .715, B .072), so a saturated red or
  blue is luminance-starved. A uniform Lc floor across six hues is a demand to desaturate
  red and blue into pastels.
- At L 0.78, yellow has 0.159 chroma available and blue has 0.112 and falling. **Equal
  lightness and equal saturation are not simultaneously purchasable in sRGB.**

This kills the conventional constant-lightness ring and produces the design's central claim:
**the right invariant for a terminal palette is constant *readability*, not constant
lightness — and it necessarily has varying OKLCH L.** No theme in the field does this. The
staggered lightness is also what carries red-versus-green for a colour-blind reader, since
dichromacy destroys hue and leaves lightness as the only surviving channel.

## 3. Four wrong answers, in order

Kept because the failure modes are the transferable part, and because each one satisfied more
constraints than the last.

| Pass | Outcome | Why it was wrong |
|---|---|---|
| `optimize_umber.py` | unguided noise | One constraint — ANSI 0 judged in APCA — was **mathematically unsatisfiable**: APCA's `loClip` returns exactly 0.0 below the invisibility threshold, and ANSI 0 is a surface a hair above the background by definition. A max-min objective with one infeasible term has no gradient anywhere. |
| `optimize_umber2.py` | pastel | Met a uniform Lc ≥ 60 normal ring by pushing red to `#FFA771` at hue 51.7° — peach, not red — **pinned against its hue bound**, and magenta to near-white. When an optimiser pins a parameter at its bound, the constraint set is infeasible in the region you wanted and the bound is the only thing still holding the design together. |
| `optimize_umber3.py` | pale bright ring | A chroma floor bounded the *request*, not the gamut-mapped *result*: bright magenta asked for 0.075 and shipped 0.037. A bound on what you ask for is not a bound on what you get when a projection sits in between. |
| `optimize_umber4.py` | neon | Satisfied **all 60+ constraints** by maxing chroma everywhere, because chroma helps colour-blind separation and nothing penalised garishness. `#6BE160` lime, `#22FDFF` electric cyan. |

The lesson, and the reason the final palette is hand-placed: **the measurement suite maps the
feasible region and prices the trade-offs; it cannot express taste, and an optimiser will
exploit whichever axis you forgot to bound.** The tool's real output was `frontier.py`.

`place_final.py` then searched *only* lightness and hue with chroma pinned at aesthetic
values, which makes garishness structurally impossible — and added the tier system in §5.

## 4. Where the numbers and the eye disagreed

The search put red at hue 18.2° and green at 157.2°, both pinned at their bounds, because
that maximised red/green separation. Rendered on realistic content (`preview.py` →
`preview.html`) they read as **salmon-pink** and **mint**. Corrected to 27° and 150°.

That correction broke three tier assertions. Rather than relax them, `impossibility.py` asked
whether tier 1 was reachable at all — and **it was**: red L 0.72 / yellow 0.85 / green 0.95,
min pairwise 0.147. `solve_warm.py` then found a version where both rings comply (yellow L
0.810, green L 0.890). Rendered side by side (`preview2.html`), that version's green is
visibly washed and its bright green `#D9FFE0` is near-white — worse on `git diff` and `✔`,
which is precisely the output the separation was meant to protect.

**So taste won, on the record.** The shortfalls are declared in `final.py`'s `SHORTFALL`
table and in the gate, with the reason and the rejected alternative named, so a reviewer can
overturn the call by reading the same two artifacts. That is different in kind from lowering
a threshold because a run failed.

## 5. Colour-blind pairs, tiered by whether confusion misreads output

Red–green deficiency affects ~8% of men, and red-versus-green is the exact axis `git diff`,
test results, and error-versus-success ride on. But weighting all 12 pairs equally is 48
constraints on 18 parameters and is simply infeasible — it trades red/green against
magenta/cyan at par. Tiers, set before measuring:

- **Tier 1 — 0.105.** red/green. Confusing it misreads the diff.
- **Tier 2 — 0.080.** blue/magenta, green/cyan, blue/cyan, red/magenta, red/blue. Adjacent
  in prompts and `ls`; confusion is annoying, not misleading. red/yellow and green/yellow
  land here as the §4 accepted shortfalls.
- **Tier 3 — 0.050.** magenta/cyan, yellow/magenta, yellow/cyan, blue/green. Syntax-
  highlighting adjacency only. Nothing is misread if they converge. (magenta/cyan is pinned
  at its measured 0.025.)

Umber's tier-1 red/green measures **0.120 normal / 0.109 bright** under the worse of
protanopia and deuteranopia. The field's best real theme is 0.070.

**The structural point matters more than the numbers**: colour must not be the only carrier.
Umber's git sidebar already gets this right — every decorated row carries a **letter** badge
(`M`/`A`/`D`/`U`) plus a tooltip, which is legible with no colour at all.

## 6. The shipped palette

```
background #19120D   OKLCH 0.190 0.016  56    foreground #E5DFD6   Lc 87.0
cursor     #FF9B5A   OKLCH 0.780 0.145  52    selection  #453021
 0 #342C26   1 #EF7F74   2 #8AE49E   3 #D7AA32   4 #739EF0   5 #FFACE9   6 #42CBC8   7 #D3CDC5
 8 #AAA19B   9 #FDAAA0  10 #B4FCC3  11 #F7D179  12 #9DBEFC  13 #FFD2F2  14 #80E5E2  15 #F9F6F2
```

Held to, and verified by, `check-theme-contrast.sh` (135 assertions):

- background luminance 0.0067, safely under `Config.lightChromeCutoff` 0.179, so the window
  keeps dark chrome — and **measurably warm** (OKLab a > 0.001, b > 0.008), asserted because
  it is the thesis and a cold background silently turns Umber into another GitHub Dark;
- body text Lc 87.0; ANSI 8 (comments) Lc **51.5** against a field best of 34.3;
- every slot clears a role-derived floor; all 8 normal→bright pairs separated (min 0.088)
  **and correctly ordered**;
- selected text still readable on the selection background (Lc ≥ 60);
- and a **falsification case**: the same rules must *reject* xterm's `#0000EE` on black, the
  canonical unreadable blue. If that passed, the thresholds would be too loose for any other
  result to mean anything.

The gate was itself falsified — seven deliberate breakages, each required to exit 1. That
found a **real bug in the gate**: the reachability check grepped for the bare quoted preset
name, which also appears in a doc comment, so deleting the actual `switch` case still passed.
It now strips comments and anchors to a `case` line. A grep-based assertion has to match the
construct, not the vocabulary.

## 7. What was NOT done, and why

- **The default is unchanged.** `theme == nil` still means "install nothing". §0 removes the
  technical objection, but flipping a default is a taste judgement that should follow real
  use, not a measurement run — and the honest gap is that *nobody has daily-driven this
  palette yet*. One config line and ⌘R switches to it: `"theme": {"preset": "umber"}`.
- **Selection and cursor-text colours are still unwired.** `ThemePalette.selection` carries a
  measured value, but neither engine is told. Both can express it
  (`TerminalView.selectedTextBackgroundColor`, which defaults to a hardcoded teal `#00A6B2`;
  libghostty's `.selectionBackground`/`.selectionForeground`). This is a real gap, recorded
  rather than omitted — the value exists for when the wiring lands.
- **A light preset.** `Config.lightChromeCutoff` has **never been exercised** by a shipped
  theme (all three sit far below it), so the entire light-chrome path is untested in practice.
  A measured light Umber is the natural next step and the only way to test it.
- **libghostty's 256-colour behaviour is UNVERIFIED.** `GhosttyPane+Appearance.swift` sends
  only indices 0–15 and asserts in a comment that ghostty generates 16–255 as the standard
  cube. The executing code is inside the prebuilt 51.8 MB `GhosttyKit.xcframework`; it cannot
  be read from this checkout. Treat it as a claim about upstream, not a verified fact.
- **Perceived speed, glyph rendering, ligatures and CJK cells** are untouched by any of this.

## 8. Files

| File | What it is |
|---|---|
| `design_theme.py` | The instrument: OKLab/OKLCH ↔ sRGB with CSS Color 4 gamut mapping, WCAG 2.1, APCA 0.98G-4g, Viénot–Brettel–Mollon dichromacy. Everything else imports this. |
| `benchmark_themes.py` | The nine reference palettes and the §1 calibration table. |
| `frontier.py` | The §2 feasibility frontier — per-hue APCA ceilings and per-lightness chroma limits. |
| `optimize_umber{,2,3,4}.py` | The four failed passes, kept for §3. |
| `place_lightness.py`, `place_final.py` | Chroma pinned; lightness and hue searched; pairs tiered. |
| `impossibility.py`, `solve_warm.py` | The §4 check that tier 1 was reachable, and at what cost. |
| `verify_umber.py`, `final.py` | The hand-placed palette and its verification. `final.py` exits non-zero on any unmet assertion. |
| `preview.py`, `preview2.py` | Render candidates as a real terminal beside a mock native sidebar. |
| `umber-palette.json` | The shipped values, machine-readable, with the OKLCH triples they came from. |

Re-run everything: `python3 final.py` (exits 0), then `cd app && ./Scripts/check-theme-contrast.sh`.

## 9. Runtime verification

The gate is headless and cannot prove the preset reaches the app. Checked separately, and
falsified rather than assumed — `~/.config/umber/config.json` was backed up, swapped, and
restored byte-identical:

| `theme.preset` | result |
|---|---|
| `umber` | resolves, no warning |
| `tokyo-night` | resolves, no warning |
| `umberr` | `config: theme.preset 'umberr' unrecognised — using afk-dark` |
| `nonsense-theme` | `config: theme.preset 'nonsense-theme' unrecognised — using afk-dark` |

Without the last two rows the first two would prove nothing: "no warning" is only evidence if
a wrong name *does* warn. Note the operator's active config sets `engine: ghostty`, so `umber`
reaches the terminal through `GhosttyPane+Appearance.swift` (hex strings), not the SwiftTerm
path — both are fed from the same `ThemePalette`.
