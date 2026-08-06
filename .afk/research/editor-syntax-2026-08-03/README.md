# The editor's syntax colours — derivation and falsification

**Date:** 2026-08-03 · **Branch:** `afk/add-editor-syntax-highlighting`
**Shipped result:** `app/Sources/Umber/SyntaxPalette.swift`, gated by §5k of `app/Scripts/check-theme-contrast.sh`
**Companion:** `.afk/research/editor-highlighting-feasibility-2026-08-03.md` (the build-vs-adopt argument)

**Thesis.** Syntax colours here are a **role mapping onto the ANSI ring each palette already
ships**, not five new hex values per palette. That choice is forced by a contract the repo
already wrote down, and once made, the mapping itself is decidable by measurement rather than
by taste — which is the opposite of how the palette it sits on had to be designed.

---

## 1. Why a mapping, and not new colours

`ThemeValues.swift` states the contract two of the three shipped palettes are held to:

> a preset's job is to be the thing it claims to be — silently "fixing" a port makes it a
> different theme wearing the same name

`afk-dark` and `tokyo-night` are declared verbatim upstream ports. Inventing ten syntax
colours for them breaks exactly that, and there is no upstream syntax palette to transcribe
instead — the terminal themes they were ported from do not publish one. A role mapping:

- invents nothing, so the ports stay ports;
- works unchanged for hex a user typed into their own config, which five new `ThemePalette`
  fields would not (they would be preset-only, and `theme.selection` is already the one field
  a user cannot override — see §6);
- inherits whatever legibility the palette was already measured for;
- agrees with the tools running in the terminal beside it. base16, every 16-colour vim scheme,
  `bat --theme=ansi` and `delta` all express syntax as ANSI roles. An editor that disagreed
  with `git diff` two panes over would be the odd one out.

## 2. Which slots — decided by exhaustive search, not by convention

`rank_mappings.py` measures **all 360** assignments of the four chromatic roles (keyword,
string, number, type) to the six chromatic ANSI indices, ranked by worst-case dichromatic
separation under `umber`, then minimum APCA Lc under `umber`, then how many roles fall below
APCA 45 across the two ports.

**The optimum is a 24-way tie, and every member of it uses the same slot set: green, yellow,
blue, cyan.** That is the whole finding. Red and magenta are excluded *by the numbers* —
under `afk-dark` both measure APCA **Lc 41.4**, below the Lc 45 floor at which text stops
being readable at any size. Where the conventional answers land:

| mapping | rank | umber min CVD dE | umber min Lc | roles unreadable in the ports |
|---|---|---|---|---|
| base16 (kw=magenta, type=cyan) | #229 | 0.077 | 59.1 | 1 |
| base16-strict (type=yellow) | #141 | 0.083 | 50.2 | 2 |
| **kw-blue (shipped)** | **#13 (optimal tier)** | **0.119** | **49.5** | **0** |

So the most-cited convention is measurably worse here — 0.077 vs 0.119 dichromatic separation,
and it puts an unreadable keyword colour on one shipped palette. Two consequences of the
optimal slot set were not designed for and are both wanted:

1. Every role clears the readable floor in **all three** palettes.
2. **Red stays free.** That is the colour an editor wants for diagnostics and a diff for
   deletion. Spending it on `number` would have been the expensive mistake, and no contrast
   metric would ever have flagged it.

Numbers could not break the 24-way tie, so convention did: `string` = green (base16 `0B`,
`grep`'s match, a diff's addition — close to universal), and `keyword` = blue with `type` =
cyan following VS Code Dark+.

## 3. Comments — the one place the palette is overridden

ANSI 8 is the comment colour by near-universal convention, and `umber`'s was *designed* for
the job (`ThemeValues.swift`: "the comment colour", measured Lc 51.5). It is also the field's
universal failure:

| palette | ANSI 8 | APCA Lc | verdict |
|---|---|---|---|
| umber | `#AAA19B` | 51.5 | used as-is |
| afk-dark | `#484F58` | 13.1 | clamped |
| tokyo-night | `#414868` | 10.3 | clamped |

A comment at Lc 10 in a *terminal* is dim `ls` output. In an *editor* it is content, and prose
nobody can read is the worst outcome available. Both failing palettes are verbatim ports that
must not be edited — so the fallback is the foreground composited at `commentAlpha = 0.72`,
landing at Lc 46.4…57.0 across the three palettes while staying **27–35 Lc below body text**,
so a comment still reads as secondary rather than as code.

`0.72` is the tab strip's inactive-label alpha, and the same arithmetic, so the app has one
idea of what de-emphasised text looks like. It is **duplicated rather than shared** on purpose:
two independent decisions that happen to agree, and coupling them would let a tab-strip tweak
silently restyle every comment.

This is a clamp, and clamps hide things, so precisely what it does not do: it never touches hue
and never nudges gamut, which is the harder unbuilt version AFK.md defers. It swaps one
measured colour for another on a threshold the gate asserts — and the gate also asserts **both
branches stay reachable**, because a branch nothing exercises is a branch nothing verifies.

## 4. Falsification — six mutations, all caught

A gate that cannot fail proves nothing. Each mutation was applied to the shipped
`SyntaxPalette.swift`, the gate re-run, and the failure read to confirm it fails for the
*right* reason:

| mutation | caught by |
|---|---|
| two roles share a slot (`keyword` → green) | slot-distinctness, + 3 palettes' `keyword/string` dE 0.000, + umber CVD |
| a role reads plain text (`type` → ansi[7]) | "reads ansi[7], which is a surface (0) or plain text (7/15), not a colour" |
| the clamp returns its input (`if true`) | both ports' comment Lc 13.1/10.3 below floor, + clamp reachability, + clamp-direction falsification |
| `commentAlpha` 0.72 → 0.55 (the strip's old bad value) | both ports' comment at Lc 31.4/31.5 |
| `keyword` → magenta | afk-dark keyword Lc 41.4, + umber CVD keyword/type 0.063 |
| `readableFloor` 45 → 10 | **the falsification case** — the gate reports that its own floor is now too loose for the clamp results to mean anything |

The last is the one worth keeping. A threshold quietly relaxed is the most plausible way this
section rots, and it is the failure mode a suite of "does it clear the floor" assertions cannot
see by construction.

Two further mutations validate the **consumer guard** added in the same commit: deleting the
`selectedTextAttributes` line, or `Theme`'s `selection = …` line, each fail the gate. That
guard exists because of §5 below.

## 5. The bug this commit is really about

`ThemePalette.selection` was designed, measured, annotated with its OKLCH derivation, and
asserted by two gate cases (§5h) from the day the palettes landed — and it reached **nothing**
for the whole time. The recorded reason was "not yet wired to either engine". That was accurate
and it understated the cause: `Theme`, the AppKit bridge, had no `selection` field, so the
value could not cross into the app *even in principle*. No consumer could have read it if one
had tried.

The generalisable point, and the reason two greps now guard it: **a gate that measures a colour
says nothing about whether anything draws it.** Measuring a colour nobody draws is the same
class of error as drawing a colour nobody measured — this repo had a name for the second one
already and none for the first.

## 6. What was not done, and why

- **No config surface.** `theme.selection` and the syntax roles are not user-overridable. That
  leaves `selection` as the only `ThemePalette` field with no override, which is a real
  asymmetry — deferred rather than refused, because `Config.swift` is at 327/350 and a new
  field there wants the `Derived chrome` section extracted to `Config+Chrome.swift` first.
- **No `AppConfig.effectiveSelection`.** One consumer does not justify a derived accessor, and
  the correct no-theme answer here is the *system* selection colour (which tracks Increase
  Contrast), not the `?? .black` shape the other two accessors use. When an engine becomes the
  second consumer, add the accessor and do the `Config+Chrome` extraction together.
- **Nothing is painted.** No tokenizer, no `FileViewerPane+Highlighting.swift`. The colour half
  went first because it is the half a gate can hold to a number.
- **Not verified visually.** No screenshot, no daily use. `check-theme-contrast.sh` proves the
  numbers and two greps prove the wiring exists; that a selected range actually renders in
  `#453021` is a claim only running the app supports. Same accepted-unverified category as the
  file tree's icons — and note §5's lesson applies to this commit too, not just the last one.
- **`ThemeValues.swift` is duplicated into `measure_roles.py` by hand.** Acceptable for a design
  instrument (the gate compiles the shipped source); it would not be acceptable in the gate.
