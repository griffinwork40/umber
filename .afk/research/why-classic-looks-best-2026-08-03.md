# Why `classic` looks best — and why the gate cannot see it

**Date:** 2026-08-03
**Question:** the operator reports that `"preset": "classic"` looks better than `umber`, `afk-dark`,
`afk-light` and `tokyo-night`. `AFK.md` currently records classic as *"the worst-measured palette in
the repo"* (7 of 8 APCA floors failed). Both statements are true. This document explains how.

**Method:** every number below was computed by compiling the shipped `ThemeContrast.swift`
(`RGB`, `WCAG`, `APCA`, `OKLab`, `CVD`) against a scratch harness — the same instrument
`check-theme-contrast.sh` uses — plus an Ottosson OKLab→linear-sRGB inverse for the gamut ceiling.
Palette hexes read from `ThemeValues.swift`; classic's from vendored `SwiftTerm/Colors.swift`.

---

## 1. `classic` is not a palette. It is the absence of one.

`Config+Theme.swift:38-40` — `"classic"` is the only string that resolves `theme` to `nil`.
`TerminalPane.swift:170-177` — the whole `if let theme` block is skipped, so **four** SwiftTerm
writes never happen: `nativeBackgroundColor`, `nativeForegroundColor`, `caretColor`, `installColors`.

What stands instead (all set at view construction, `Apple/AppleTerminalView.swift:193-194`):

| Slot | Value | Source |
|---|---|---|
| background | `#000000` | `Colors.swift:37` |
| **foreground (plain text)** | **`#8A8A8A`** | `Colors.swift:36` (16-bit 35389) — reached at `AppleTerminalView.swift:332,773,787` |
| cursor | `NSColor.selectedControlColor` — **the user's macOS accent colour** | `MacCaretView.swift:97,99` |
| ANSI 0–15 | `Color.terminalAppColors` — macOS Terminal.app "Basic" | `Colors.swift:91-108` |

Ruled out as differentiators: window chrome is `.darkAqua` for classic, umber, afk-dark and
tokyo-night alike (`Config.swift:175-177`, cutoff 0.179 — only `afk-light` crosses it); selection is
hardcoded `#00A6B2` in every case (`ThemePalette.selection` is never wired to either engine);
git tints and file-tree text are system colours regardless (`GitStatus+Presentation.swift:47-74`).
**The entire difference is the four skipped writes.**

---

## 2. The measurements

```
pal            bgL    fgL   fg_Lc  |  meanC  maxC   minC  | Lrange  Lsd  | accentL-fgL  accentC/fgC
classic(nil)   0.000 0.633   39.6  |  0.213 0.294 0.113 | 0.939  0.256 |    +0.054     213.4x
umber          0.189 0.906   87.0  |  0.113 0.140 0.065 | 0.785  0.199 |    -0.087       8.2x
afk-dark       0.176 0.857   77.5  |  0.146 0.205 0.092 | 0.775  0.204 |    -0.122      10.3x
tokyo-night    0.226 0.846   73.8  |  0.129 0.159 0.105 | 0.643  0.193 |    -0.080       2.1x
```
(`meanC`/`maxC`/`minC` = OKLCh chroma over the 12 chromatic slots; `Lrange`/`Lsd` = OKLab lightness
spread over all 18 colours; `accentL-fgL` = mean accent lightness minus body-text lightness.)

### 2a. Figure/ground is **inverted** — this is the big one
> **[REVISED after adversarial verification — the number held, the framing did not.]**
> The original claim here was "classic is the only palette whose accents are lighter than its body
> text", resting on the all-12 mean of +0.054. A verifier reproduced that number to within 0.001 but
> showed the sign is **fragile to definition**: over the 6 *normal* slots alone it is −0.0005, a
> coin-flip. The all-12 lift comes **entirely from the bright half**. Corrected statement below.

Splitting the accents by half is what the single mean was hiding:

```
palette         fg_L    normal(1-6)   bright(9-14)    all-12     ANSI7_L   fg-ANSI7
classic         0.633    -0.0015       +0.1094       +0.0539     0.845     -0.211
umber           0.906    -0.1328       -0.0406       -0.0867     0.851     +0.055
afk-dark        0.857    -0.1394       -0.1049       -0.1222     0.857     +0.000
tokyo-night     0.846    -0.0802       -0.0802       -0.0802     0.767     +0.079
```

The real structure, which is stronger than the original claim:

- **Classic's normal accents sit LEVEL with its body text** (−0.0015 — identical to three decimals),
  and its **bright accents sit clearly above it** (+0.109). Brightness is a working *promotion
  channel*: bold and bright output genuinely advances out of the page.
- **In all three designed palettes, both halves sit BELOW body text.** Even umber's *brightest*
  accents are 0.041 dimmer than its plain text; afk-dark's are 0.105 dimmer. Colour is a visual
  **demotion** — a red error is dimmer than the `ls` output above it — and the bright half cannot
  rescue it. Tokyo-night is the extreme: normal and bright are the *same hexes* (dE-OK 0.000), so it
  has no promotion channel at all.

The last column explains the mechanism, and it is the sharpest single fact in this document:
**`fg − ANSI7` is −0.211 for classic and ≈ 0 or positive for all three designed palettes.** Classic
is the only palette here that reserves a **dim neutral for plain text that is distinct from, and far
darker than, its own "white"**. The others set foreground ≈ ANSI 7, so plain text *is* white and
there is no headroom left above it. That deliberate gap is what every other finding in §2 rests on.

(Credit where due: this correction came out of a verifier's attempt to *refute* the claim by
substituting ANSI 7 for the foreground constant. That substitution does not describe what the
terminal actually paints — see §1 and the verification note in §6 — but chasing why the sign flipped
is what exposed the `fg − ANSI7` gap as the real underlying property.)

Measured against the **body text** rather than the background:

```
                mean |Lc| vs body   mean dE-OK vs body   min dE-OK vs body
classic                 18.4              0.255               0.147
afk-dark                18.7              0.198               0.115
umber                   12.8              0.151               0.069
tokyo-night             10.9              0.156               0.074
```

Classic's **worst** accent separates from its body text more than twice as well as umber's worst
(0.147 vs 0.069). Tokyo is worst of all — its foreground `#C0CAF5` is itself chromatic, so accents
are only **2.1×** more colourful than plain text; colour barely registers *as* colour.

### 2b. Classic is 1.9× more colourful, and uses more of the gamut

Mean chroma 0.213 vs umber 0.113. Peak 0.294 vs umber 0.140 — **2.1×**. And it is not merely darker:
at the lightness each palette chose, classic spends **89%** of the chroma sRGB makes available,
against umber's 80% and tokyo's 81%. It is a more *committed* palette.

### 2c. Widest dynamic range, on a true-black ground

L-range 0.939 (`#000000` → `#EAEC23`), lightness SD 0.256 — the highest of the five. Tokyo is
flattest (0.643 / 0.193). Classic has tonal rhythm; the designed palettes are compressed into a
bright band because every slot was pushed up to clear a floor.

`#000000` also matters on its own: on an OLED or local-dimming display it is pixels **off**, so
saturated colours read as *emissive* rather than *printed*. Umber's `#19120D` is a lit dark brown.
(Display-dependent — asserted as mechanism, not measured here.)

### 2d. The caret is the user's own accent colour

Nil theme leaves `caretColor` unwritten, so the block cursor is `NSColor.selectedControlColor` —
whatever the user picked in System Settings. Every other preset overrides it (umber forces
`#FF9B5A`). Classic is the only one that looks like it belongs to *this* Mac.

---

## 3. Why the gate optimises the beauty away — the sRGB squeeze

Max in-gamut chroma as OKLab lightness rises, per hue:

```
  L    red 31°   yellow 109°  green 142°  cyan 204°  blue 277°  magenta 328°
0.55   0.214       0.119       0.185       0.094      0.252       0.253
0.70   0.192       0.152       0.236       0.119      0.159       0.321
0.85   0.082       0.184       0.286       0.145      0.075       0.140
```

Clearing APCA Lc ≈ 60 on a near-black background needs roughly **L ≥ 0.70**. Pushing there costs
**red −62%** chroma, **blue −70%**, **magenta −45%**, while yellow/green/cyan lose nothing.

> **[REVISED — two overstatements corrected by verification.]**
> **(i) The "+54.5% gain" for yellow/green/cyan was numerology, not measurement.** All three come out
> to *identically* 54.545% because at those hues the gamut boundary is set by a channel pinned at
> exactly 0; scaling (L, C) by *t* scales linear sRGB by *t³*, and 0·*t³* = 0, so the boundary is
> scale-invariant and the percentage is forced to equal (0.85/0.55) − 1 for *any* such hue. It is one
> geometric fact reported three times, not three measurements. The honest version: those hues lose
> nothing by getting lighter. Absolute ceilings also diverge — magenta 0.321, blue 0.297, green
> 0.291, red 0.247, yellow 0.208, **cyan just 0.148** — so cyan's "gain" is on the smallest base of
> the six.
> **(ii) "Chroma falls as L rises" is not monotonic for two of the three.** Red peaks at L ≈ 0.635 and
> magenta at L ≈ 0.70; only blue declines across the whole window (its peak is at L ≈ 0.48). The
> defensible statement is not a trend but a **position**: red, blue and magenta have their chroma
> peaks at or below L ≈ 0.70, and yellow, green and cyan have theirs far above (0.865–0.96). Moving a
> palette up to L ≥ 0.70 therefore moves the first group *past* its peak and the second group *toward*
> its own.

So the squeeze is **hue-selective**. Now overlay classic's per-slot APCA scores against its own
background (floor 45):

```
pal              blk  red  grn  yel  blu  mag  cyn  wht  BLK  RED  GRN  YEL  BLU  MAG  CYN  WHT
classic            0   26   53   55   17   36   57   76   36   39   74   91   22   46   84   95
umber              0   50   78   59   49   72   64   76   52   68   94   81   66   87   80  101
```

**Classic fails exactly red (26), blue (17) and magenta (36) — and passes green (53), yellow (55)
and cyan (57).** For the six *normal* slots this split is robust at thresholds 40, 45 **and** 50.

> **[REVISED — the "perfect match" claim needs one qualifier.]** Across all twelve chromatic slots
> the split is *not* clean at 45: **bright-magenta scores 46.2 and crosses the line**, landing with
> the passing group. Move the threshold to 50 and the family pattern holds for all twelve. So: clean
> at any threshold for the normal half, clean at 50 for both halves, one crossing at exactly 45.

**And the correspondence is geometry, not intent.** It is tempting to read this as classic having
*chosen* the max-chroma side of the trade on the three hues where a trade exists. There is no
evidence for that and the timing argues against it: these are macOS Terminal.app's ~2001 defaults,
predating OKLab (2020) and APCA entirely. The real explanation is that both halves of §3 are
reflections of **one** fact about the shape of the sRGB gamut — red, blue and magenta are
intrinsically *dark*-saturated, green, yellow and cyan intrinsically *light*-saturated — so the
APCA scores and the chroma ceilings are not two independent confirmations, they are the same
geometry measured twice.

That makes the conclusion stronger, not weaker. It means **any** palette that picks vivid versions of
these six hues lands where classic landed, and any palette forced above the floors gives up the
reds, blues and magentas specifically. Classic's seven "failures" are not carelessness and not
cleverness — they are simply **what saturation costs on those three hues in this colour space**.
`check-theme-contrast.sh` scores that cost as failure because it has no term for chroma, none for
dynamic range, and none for the accent-vs-body relationship — the three axes on which classic wins.
`AFK.md` already says this in one line — *"It guards the floor, not the bar"* — but the default flip
on 2026-08-03 read the floor as the bar.

---

## 4. What classic genuinely gets wrong

Not everything here is a measurement artifact. Three findings survive:

1. **Blue at Lc 17 and bright-blue at Lc 22 are real defects.** The gate's own falsification case
   rejects xterm `#0000EE` at Lc 14.0 as canonically unreadable; classic's `#492EE1` is 2.9 points
   from it. A blue path in `ls` output is genuinely hard to read.
2. **Body text at Lc 39.6 is under-contrasted** by any standard — below even the Lc 45 "any size"
   floor. It reads as *atmosphere* at 14pt on a good display; it will read as *strain* at small
   sizes, in bright rooms, or for anyone with reduced contrast sensitivity.
3. **Normal→bright separation min 0.054** (floor 0.085), so some bold text is nearly
   indistinguishable from plain. Still far better than tokyo-night's **0.000** — that palette ships
   literally identical normal and bright hexes in every chromatic slot.

**Confound worth naming:** `terminalAppColors` *is* macOS Terminal.app's Basic profile. Twenty years
of familiarity is a real driver of "looks right" and is not separable from the optical argument
above by any measurement in this repo.

---

## 5. Implication

The three properties that make classic attractive — dim neutral body text, true-black ground,
high-chroma accents — are **independent** of its two real defects (the blue, the bold ring). Nothing
requires a palette to choose between them. The unbuilt option is a preset with classic's *structure*
and only the broken slots repaired: keep `#000000`, keep a deliberately quiet neutral foreground,
keep accents below L 0.70 where red/blue/magenta still have chroma, and fix only blue and the
normal→bright ring.

That is also the honest fix for the gate. It currently cannot express "body text should be quieter
than accents", so any palette satisfying it will invert figure and ground. Two floors would encode
what the operator's eye detected, and §2a says exactly what they should be:

- **`fg − ANSI7 ≤ some negative bound`** — force a real gap between plain text and "white", so the
  palette has headroom above body text to promote things into.
- **`mean L(bright 9-14) − L(fg) > 0`** — require that the bright half actually advances. Every
  shipped preset fails this today (umber −0.041, afk-dark −0.105, tokyo −0.080).

## 6. Verification

Every claim above was re-derived by three adversarial verifiers dispatched under `/shadow-verify`,
each given only the bare claim — not this document's reasoning or citations — and required to hunt
for refutation.

| Claim | Verdict | Outcome |
|---|---|---|
| Plain text renders `#8A8A8A`, not white or ANSI 7 | **CONFIRMED** | Independent end-to-end trace: `Colors.swift:36` → skipped `if let theme` at `TerminalPane.swift:170-177` → `AppleTerminalView.swift:193-194` (runs at construction, *before* `apply(config:)`) → `CharData.defaultAttr` `.defaultColor` → `mapColor` `:330-335`. Confirmed for **both** renderers (Metal: `MetalTerminalRenderer.swift:1196`). Refutation attempts on `useBrightColors` and `configureNativeColors()` both failed to break it — the latter has **zero call sites** repo-wide. |
| Figure/ground inversion (+0.054 vs three negatives) | **CONFIRMED number, REFUTED framing** | All four values reproduced to within 0.001, and sign cross-checked against an independently implemented CIE L*. But the sign is fragile: normal-slots-only gives −0.0005. §2a rewritten. |
| Hue-selective gamut squeeze + APCA correspondence | **CONFIRMED with three corrections** | Gamut table reproduced independently in Python from Ottosson's matrices. The +54.5% "gain" is a scale-invariance artifact; red/magenta are non-monotonic; bright-magenta crosses at threshold 45. §3 rewritten. |

**Bonus defect found during verification (unrelated to the theme question):**
`Config.swift:144-147` falls back to `.white` with the comment *"SwiftTerm's default foreground is
white."* That comment is **wrong** — the default is `#8A8A8A` (`Colors.swift:36`), as established
above. The property (`effectiveForeground`) is never consulted by the terminal's glyph painter, only
by chrome and the file viewer (`FileViewerPane.swift:263-265`), so nothing renders incorrectly today
— but the stated rationale is false and the fallback value is 0.27 OKLab-lightness away from the
thing it claims to match. Worth fixing when that file is next touched.

**Not done here.** This document is diagnosis only; no source file was changed, and the `Config.swift`
comment defect above is recorded, not repaired.
