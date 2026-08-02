# Light mode for Umber — scope

Written 2026-08-02 against `afk/add-light-mode` @ `8fabf33`, worktree
`.afk-worktrees/afk-add-light-mode`. Every code claim below was re-verified by
reading the file; where the briefing I was given was wrong, it is called out in
**Corrections to the brief** and again in Risks. Nothing under `app/` was
touched. The prototype quoted in the Gate section was built and run in `/tmp`.

---

## Recommendation

Ship **one** light preset, `afk-light`, whose values are GitHub Light Default
copied verbatim from a published source — the exact mirror of how `afk-dark` was
built (that preset is a GitHub *Dark* skeleton, ported from
`themes/terax/afk-dark.terax-theme` in the agent-afk repo, which I read: it
declares `variants: ['dark']` and has no light sibling, so there is nothing
upstream to port and a published palette is the honest substitute). `theme.preset`
simply grows one name; **do not** add a light/dark axis or an `appearance` field
to the config — the derived-chrome mechanism at `Config.swift:140` already turns a
light background into light window chrome, so a light preset is a *data* change
riding an existing seam, and `Config.swift` has 16 lines of headroom it should
keep. Do **not** follow macOS System Settings in this PR: auto-switching needs an
`AppleInterfaceThemeChangedNotification` observer plus a live re-derivation path
through five files, it reopens a decision that was made for a real rendering bug,
and none of it is gateable by this repo's single-file `swiftc` harness — build the
seam now, wire the switch in PR 2. The structural work that makes both this PR and
that one cheap is one new Foundation-only file, `ThemeCatalog.swift`, which takes
the palettes-as-data and the WCAG luminance formula out of `Theme.swift` (which
imports AppKit *and* SwiftTerm and has therefore never been gateable, verified:
`swiftc Sources/Umber/Theme.swift` alone exits 1 on `no such module 'SwiftTerm'`)
and puts them where a check can compile them — the sixth instance of a pattern
this repo already runs five times. That file is what the new gate,
`check-light-theme.sh`, compiles; its kill criterion is that `afk-light`'s
background luminance must exceed `lightChromeCutoff`, because a light preset that
lands below it installs its colours and leaves the sidebar dark — a config line
that parses, warns about nothing, and half-works, which is the highest-risk
failure mode in this feature and the one nothing currently catches.

---

## Design decisions

### 1. Minimum credible light mode: one preset, `afk-light`

**Chosen:** exactly one new preset, named `afk-light`.

The naming falls out of the existing set with no argument needed: `afk-dark` and
`tokyo-night` are the shipped names (`Theme.swift:145-146`), `afk-dark` is the
house theme, and `afk-light` is the only spelling a user would guess. It also
makes the eventual pairing syntactically obvious if PR 2 ever wants
`light:afk-light,dark:afk-dark` — Ghostty's vocabulary, see Prior art.

**Rejected: two light presets** (e.g. `afk-light` + `solarized-light`). Two
reasons. First, the repo ships two dark presets and one of them, `tokyo-night`,
exists only because it *was the v0.1 default* (`Theme.swift:128`) — it is
retained history, not a curated pair, so "two dark therefore two light" is
pattern-matching on an accident. Second, and decisively, I measured the
candidates and they are not equally good. Counting the twelve ANSI slots a TUI
actually colours text with (1–6, 9–14; slots 0/7/8/15 are structural bg/fg tones),
the number falling below WCAG 3.0 contrast **against that scheme's own
background**:

| Scheme | bg | slots below CR 3.0 | worst |
|---|---|---|---|
| **GitHub Light Default** | `#FFFFFF` | **0** | 3.24 |
| Tokyo Night Day | `#E1E2E7` | 3 | 2.53 |
| Solarized Light | `#FDF6E3` | 5 | 2.48 |
| Catppuccin Latte | `#EFF1F5` | 7 | 1.91 |

Shipping a second preset means shipping one of the bottom three, i.e. shipping a
palette I have already measured as partly illegible, in a feature whose entire
purpose is legibility on a light background. One preset that is *measurably* good
beats two where the second is decoration. (Full numbers in §4.)

**Rejected: `afk-light` as a hand-tuned original.** The AFK brand orange
`#E67E4C` is `afk-dark`'s cursor. On `#FFFFFF` it is CR **2.82**, below the 3.0
floor for a non-text mark — so the caret would be the least legible thing in the
window. Fixing that means choosing a darker orange, which is a design decision
with no citable source, and this brief forbids inventing hex. So `afk-light`
takes GitHub's own `#0969DA` cursor and the brand accent is deliberately dropped;
that trade is recorded in the file's doc comment rather than left as a silent
difference from its dark sibling.

### 2. Config surface: `theme.preset` grows one name. No new axis.

**Chosen:** `"theme": {"preset": "afk-light"}`. Zero new fields. `Config.swift`
gains **0 lines** (see §5 — it actually loses one, because the hardcoded fallback
name in the warning at `:218` gets driven off the catalog).

The argument is that the expensive half is already built and paid for. `Config.swift:140-142`:

```swift
var appearance: NSAppearance? {
    NSAppearance(named: effectiveBackground.relativeLuminance > Self.lightChromeCutoff ? .aqua : .darkAqua)
}
```

That is a *derived* light/dark axis. It already exists, it is already consumed at
`SpaceWindowController.swift:166` and re-derived on every ⌘R at
`AppDelegate.swift:198`, and the comment at `Config.swift:136-138` states the
intent explicitly: *"the theme is user hex, so a light background is expressible
today even though no preset ships one"*. A user who pastes a light background
into `config.json` today already gets light chrome. The feature is not "build
light mode", it is "ship a light preset so nobody has to hand-write one" — and
the config surface for that is a string.

**Rejected: `"theme": {"light": {...}, "dark": {...}}` plus `appearance:
auto|light|dark`.** This is the more complex option and it is not earned:

- It buys nothing *this PR*. Two palettes in config only matter if something
  switches between them at runtime, and nothing does (§3). Landing the schema
  before the switch ships a field whose only legal value is the one that already
  worked — the definition of a config line that parses and does nothing, which is
  the exact class `check-renderer-config.sh` was written to catch.
- It contradicts a derived value with a declared one. `appearance: light` and
  `theme.background: "#000000"` are expressible together and disagree;
  `AppConfig.appearance` would have to pick a winner, and every resolution rule
  is a surprise to somebody. Today the question cannot be asked, because
  appearance *is* a function of the background.
- It costs the wrong file. `ConfigFile.ThemeSpec` (`Config.swift:33-41`) would
  gain a nested pair, `load()` would gain a branch per side, and `Config.swift`
  has 16 lines of headroom. Per the standing convention that would force a split
  of the loader — real work, to serve a field with no consumer.
- The repo's bar is *"beautiful and user-friendly as hell before clever"*
  (`AFK.md:5`). `{"preset": "afk-light"}` is the whole feature.

The seam that makes PR 2 cheap is **not** a config schema, it is
`ThemeCatalog.swift` — a pure list of records with names. When auto-switching
lands, `theme.preset` accepting `light:afk-light,dark:afk-dark` is a change to
one `named(_:)` function in a Foundation-only file the gate already compiles.
That is the right place to spend structure.

### 3. Follow macOS System Settings? **Not in this PR.** Build the seam, wire the switch in PR 2.

**Chosen: defer.** PR 1 ships the preset and the catalog. PR 2 ships auto-switching.

Verified ground truth: nothing in `Sources/Umber/` observes system appearance.
`grep -rn "effectiveAppearance\|NSAppearance"` returns exactly four sites —
`Config.swift:129,140-141` (deriving from the theme),
`FileTreeViewController+OutlineView.swift:124` (a cell reacting to an appearance
change it did not cause), and `TerminalPane.swift:204` (a `UMBER_DIAG` readout).
There is no `AppleInterfaceThemeChangedNotification` observer anywhere. The pin
at `SpaceWindowController.swift:164-166` is deliberate and its comment says why:
without it the sidebar *"all follow System Settings instead of the theme, which is
what put a Light-Mode grey file tree against a black terminal."* So this reopens a
settled decision that fixed a real bug, and the correct response is to reopen it
carefully in its own PR — not as a rider on a palette.

The blast radius, traced (this is the PR 2 checklist, not PR 1 work):

| Site | What must change in PR 2 | Notes |
|---|---|---|
| **New observer** | `NSApp` KVO on `effectiveAppearance`, or `DistributedNotificationCenter` `AppleInterfaceThemeChangedNotification` | Neither exists today. KVO on `NSApplication.effectiveAppearance` is the sanctioned route and does not need the distributed-notification string. |
| `AppConfig.appearance` (`Config.swift:140`) | Becomes a function of (theme, system state) instead of theme alone | This is the file with 16 lines of headroom. In PR 2 it must **not** grow a branch — the resolution belongs in the catalog/new file. |
| `SpaceWindowController.swift:164-166` | `window.appearance` re-assigned on the notification, not only at init | Currently written once. |
| `AppDelegate.swift:196-199` | The ⌘R fan-out already re-derives chrome per window; the observer wants the same loop | **This is the reusable piece.** It iterates `SpaceWindowController.open`, sets `backgroundColor` and `appearance`. An observer that calls the same code path gets four of these rows for free — which is the real argument for doing PR 2 second: PR 1 leaves this loop as the single funnel. |
| `TerminalPane.apply(config:)` (`:153`) | Must be re-invoked with the newly-resolved theme | Reachable today via `SpaceViewController.apply(config:)` at `:294-296`. **Caution:** it calls `view.changeScrollback` and `applyRenderer` too, so a naive re-apply on every appearance flip does more than recolour. PR 2 should confirm those are idempotent or narrow the path. |
| `GhosttyPane+Appearance.pushConfiguration()` (`:45`) | Same | Cheaper here: `setTerminalConfiguration` diffs the whole config and early-returns when equal (`TerminalController.swift:231`, per the comment at `:41-44`), so a redundant push is nearly free. |
| `DocumentTabStrip+Drawing.contentIsDark` (`:30`) | **Nothing.** | It reads `contentBackground`, written only by `DocumentTabStrip.apply(background:foreground:)` (`:124`), called from `SpaceViewController.apply(config:)` (`:297-298`). Fix the theme and the strip follows. |
| `FileTreeViewController+OutlineView.viewDidChangeEffectiveAppearance` (`:124`) | **Nothing.** | It already reacts to the window's appearance changing and re-derives the one `CGColor` that would otherwise be stranded. It is the piece of PR 2 that is *already built*. |
| `GitStatus+Presentation` | **Nothing.** | Confirmed below. |

**Rejected: do it now, in one PR.** Three reasons. (a) It is unverifiable here —
an appearance observer imports AppKit, and this repo's entire mechanical surface
is single-file `swiftc` harnesses (`AFK.md:40`); PR 2 ships with `UMBER_DIAG` and
daily-drive as its only evidence, and mixing that with a palette change means a
gateable thing and an ungateable thing land together and the green gate reads as
covering both. (b) The user's stated goal for this pass is *scalable, modular,
reusable structure*, and the structure that makes PR 2 easy is the catalog, which
PR 1 delivers. (c) It reopens a bug-driven decision; that deserves its own diff
and its own revert.

**One thing PR 1 should do to make PR 2 honest**: nothing in the config
vocabulary. But the `ThemeCatalog` record type should carry `configName` as data
(it does, §5), because `light:X,dark:Y` parsing in PR 2 is then a change to one
pure function with a gate already pointed at it.

### 4. ANSI 16 for a light theme: GitHub Light Default, verbatim

**Chosen palette — every value copied, none invented.**

Primary source fetched during this scope and reproduced byte-for-byte below:
`https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/ghostty/GitHub%20Light%20Default`
— the Ghostty-format port of primer/github-vscode-theme's published
`terminal.ansi*` keys. I confirmed primer is the upstream by fetching
`https://raw.githubusercontent.com/primer/github-vscode-theme/main/src/theme.js`
and reading lines 283–299, which define `terminal.foreground` and all sixteen
`terminal.ansi*` slots from `color.ansi.*`.

| Slot | Hex | Slot | Hex |
|---|---|---|---|
| bg | `#FFFFFF` | fg | `#1F2328` |
| cursor | `#0969DA` | | |
| 0 black | `#24292F` | 8 br.black | `#57606A` |
| 1 red | `#CF222E` | 9 br.red | `#A40E26` |
| 2 green | `#116329` | 10 br.green | `#1A7F37` |
| 3 yellow | `#4D2D00` | 11 br.yellow | `#633C01` |
| 4 blue | `#0969DA` | 12 br.blue | `#218BFF` |
| 5 magenta | `#8250DF` | 13 br.magenta | `#A475F9` |
| 6 cyan | `#1B7C83` | 14 br.cyan | `#3192AA` |
| 7 white | `#6E7781` | 15 br.white | `#8C959F` |

Note slot 3 (`#4D2D00`, a dark brown) and slot 11 (`#633C01`) — GitHub deliberately
darkens "yellow" for a white background, which is exactly the adaptation that
makes a dark palette unusable when transplanted. That is the palette earning its
keep, not an error.

**The luminance number the brief asked for.** Computed with `Theme.swift`'s own
formula (`:73-83`: convert to sRGB, gamma-expand each channel with
`c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4)`, then weight
`0.2126R + 0.7152G + 0.0722B`), re-implemented and run in `/tmp`:

> **`#FFFFFF` → relative luminance = 1.00000**
> `lightChromeCutoff` = **0.179** (`Config.swift:149`)
> **1.00000 > 0.179 → `.aqua`. The chrome flips. Margin above the cutoff: +0.821.**

This is the maximum possible margin — white is the luminance ceiling — which
makes the highest-risk failure mode structurally unreachable for this preset.
For calibration, the values on the other side: `afk-dark` `#0D1117` → 0.00548,
`tokyo-night` `#1A1B26` → 0.01143, black → 0.0. The cutoff bites at roughly
`#767676` (0.18116, light) vs `#6E6E6E` (0.15593, dark). The rejected candidates
would also have cleared it (Solarized Light 0.92340, Tokyo Night Day 0.76170,
Catppuccin Latte 0.87854) — they lost on ANSI contrast, not on chrome.

**Legibility, measured against its own background** (WCAG contrast; 4.5 = AA body
text, 3.0 = floor for large text and non-text marks):

- foreground `#1F2328` on `#FFFFFF`: **CR 15.80**
- all twelve content slots ≥ **3.24**; **zero** below 3.0
- lowest three: slot 15 `#8C959F` 3.04 (structural, exempt), 13 `#A475F9` 3.24,
  12 `#218BFF` 3.39

And the reason a separate light palette is needed at all, quantified — `afk-dark`'s
ANSI on a light background: `#E67E4C` CR 2.61, `#9CB04A` 2.23, `#E5C07B` 1.60,
`#A8E060` 1.44, `#5FE0C0` 1.51, `#ECEFF4` 1.07. Every one illegible. This is not
rhetoric; it is case 5's control in the gate (§6).

**Rejected: Solarized Light.** The obvious choice, and I expected to recommend it.
It has the strongest provenance of the four — I fetched
`https://raw.githubusercontent.com/altercation/solarized/master/README.md` and
confirmed `base3 #fdf6e3`, `base00 #657b83`, `yellow #b58900`, `red #dc322f`
directly, plus the `light` mixin line showing the light mode is the palette
inverted. But measured on its own background it puts **5 of 12** content slots
below CR 3.0 (green 2.97, yellow 2.98, cyan 2.93, br.blue 2.93, br.cyan 2.48) and
its *body foreground* `#657b83` is CR 4.13 — under AA. That is by design;
Schoonover's scheme optimises for low-contrast comfort, not for WCAG. It is a
legitimate taste, but "the default light theme has sub-AA body text" is not a
default this repo should ship, and there is a second, sharper problem: the
widely-distributed Solarized Light ANSI set has a **known upstream defect** in
slot 7 (ships `#bbb5a2`, canonical is `#eee8d5` — ghostty-org/ghostty discussions
#9323 and #9063), so "copy the standard port verbatim" would copy a bug.

**Rejected: Catppuccin Latte** (7 of 12 below 3.0 — the worst measured) and
**Tokyo Night Day** (3 below, and its slot 0 `#B4B5B9` is CR 1.58, so "black" text
is nearly invisible). Tokyo Night Day was also tempting for symmetry with the
existing `tokyo-night` preset; the symmetry is not worth three illegible slots.

**The ANSI 16–255 caveat — and here the brief is wrong, in the feature's favour.**
See Corrections, item 1. Summary: Umber sets `ansi256PaletteStrategy = .xterm`
before installing any colours (`TerminalPane.swift:165`), so **no interpolation
happens** and indices 16–255 keep the standard xterm cube. The trade-off the brief
describes as inherited is not inherited. But a *different* and real trade-off
takes its place, which nobody has written down: because 16–255 stay at their fixed
xterm values, they were designed for a dark background and do not adapt. Measured
against `#FFFFFF`, **144 of the 240** extended colours fall below CR 3.0 — including
the entire top of the greyscale ramp (indices 246–255, CR 2.81 down to 1.08). Any
program that reaches for 256-colour output (`ls --color` with a rich `LS_COLORS`,
`bat`, `delta`, most TUI dashboards) will have washed-out patches on a light
background, and **no palette choice in this PR can fix that**, because the cube is
not ours. Say so in `app/README.md` beside the preset. The honest framing: `.xterm`
was the right call for a dark default and remains the right call for correctness,
and the light-background cost of it is a known, stated limitation.

### 5. Where the code goes

The one structural decision: **`Theme.swift` cannot be gated and must not try to
be.** Verified: `swiftc -O -o /dev/null Sources/Umber/Theme.swift` exits **1** with
`error: no such module 'SwiftTerm'` at `Theme.swift:17` — it imports both AppKit
*and* SwiftTerm (11 references). By contrast `swiftc Sources/Umber/Renderer.swift`
exits 0. So the palettes and the luminance formula move into a Foundation-only
unit, and `Theme.swift` keeps the AppKit conversions. This is the same split the
repo has already made five times (`Renderer.swift`, `CursorStyle.swift`,
`TerminalEngine.swift`, `GitStatus+Rollup.swift`, `GitStatus+Phrasing.swift`) and
the argument is written out in `CursorStyle.swift:5-9` and `Renderer.swift:5-11`.

`GitStatus+Presentation.swift` needs **zero changes** — the brief's suspicion is
correct and I confirmed it by reading all 76 lines. Every branch of
`decorationColour` returns a system colour (`.systemOrange`, `.systemGreen`,
`.systemRed`, `.systemPink`, `.tertiaryLabelColor`), and its own doc comment at
`:30-36` says these were chosen precisely because *"they follow the window's
effective appearance"* and hex literals *"would look wrong in light mode."* The
window's appearance is already `config.appearance`, so a light theme moves these
for free. The standing comment is a prediction that this file already handles the
case, and it does.

| File | Action | Now | After | Δ |
|---|---|---|---|---|
| **`Sources/Umber/ThemeCatalog.swift`** | **NEW** | — | **149** | +149 |
| `Sources/Umber/Theme.swift` | edit | 150 | ~148 | −2 |
| `Sources/Umber/Config.swift` | edit | 334 | **334** | **0** |
| `Sources/Umber/StarterConfig.swift` | edit | 56 | 57 | +1 |
| `app/Scripts/check-light-theme.sh` | **NEW** | — | ~215 | +215 |
| `app/README.md` | edit | 479 | ~486 | +7 (exempt) |
| `AFK.md` | edit | 178 | ~181 | +3 (exempt) |
| `GitStatus+Presentation.swift` | **none** | 76 | 76 | 0 |
| `GhosttyPane+Appearance.swift` | **none** | 182 | 182 | 0 |
| `TerminalPane.swift` | **none** | 346 | **346** | **0** |
| `SpaceWindowController.swift` | **none** | 309 | 309 | 0 |
| `AppDelegate.swift` | **none** | 264 | 264 | 0 |

Nothing crosses 350. `TerminalPane.swift` (4 lines of headroom) and
`SpaceWindowController.swift` are untouched by design — the whole point of routing
this through data is that the two files closest to the ceiling do not participate.
`Config.swift` nets zero.

**`ThemeCatalog.swift` — "what this owns":** *the shipped palettes as pure data,
the name that selects one, and the WCAG luminance formula that decides whether one
is light or dark.* Foundation-only by design, so `check-light-theme.sh` can compile
it standalone.

I wrote this file for real in `/tmp/lmproto/` to get a true line count rather than
an estimate: **149 lines including the header comment and the per-preset
rationale**, and `swiftc -O -o /dev/null ThemeCatalog.swift` exits 0 with no
imports beyond Foundation. Contents:

- `struct ThemeRecord { configName, background, foreground, cursor, ansi: [String] }`
  — hex **strings**, not parsed colours, because the file must not import AppKit
  and because storing the published values verbatim keeps each one checkable by
  eye against its cited URL.
- `afkDark`, `afkLight`, `tokyoNight` as records (values moved from
  `Theme.swift:108-148`, unchanged, plus the new one).
- `all: [ThemeRecord]` and `configNames` — so a warning listing valid presets is
  derived, never re-typed. `"classic"` is appended by hand with a comment, being
  the one accepted value that resolves to no record.
- `named(_:)` — the resolver, with the same `afk-dark`/`afkdark` folding
  `Theme.preset(named:)` has today, generalised to strip `_` the way
  `Renderer.named` does.
- `luminance(red:green:blue:)` and `luminance(hex:)` — the WCAG formula, moved
  out of `NSColor.relativeLuminance`.
- `lightChromeCutoff: Double = 0.179`.

**`Theme.swift` (−2).** Loses the two inline preset literals and
`preset(named:)` (`:108-150`, 43 lines); gains a ~35-line bridge:
`init(_ r: ThemeRecord)` mapping strings to `NSColor` via the existing `fromHex`,
three computed statics, and `preset(named:) { ThemeCatalog.named(name).map(Theme.init) }`.
`relativeLuminance` (`:73-83`) keeps its signature and body shrinks to
"convert to sRGB, call `ThemeCatalog.luminance`" — so there is one implementation
of the maths and the gate compiles it. Every existing caller is unchanged:
`Config.swift:118,121,141`, `TerminalPane.swift:171-176,202`,
`GhosttyPane+Appearance.swift:66-76`, `SpaceWindowController.swift:160`,
`DocumentTabStrip+Drawing.swift:31`. The `NSColor.fromHex(...)!` force-unwraps
stay and get *stronger*: the convention permits them "confined to compile-time-known
constants (literal hex palettes)" (`AFK.md:152`), and case 1 of the new gate now
parses every shipped hex before the code can ship — a promise becomes a check.

**`Config.swift` (0).** The only edit is at `:216-219`. Today:

```swift
var theme: Theme? = wantsClassic ? nil : (t.preset.flatMap(Theme.preset(named:)) ?? .afkDark)
if let raw = t.preset, !wantsClassic, Theme.preset(named: raw) == nil {
    config.warnings.append("theme.preset '\(raw)' unrecognised — using afk-dark")
}
```

The literal `afk-dark` in that string becomes `ThemeCatalog.afkDark.configName`,
and the message gains `(expected one of: \(ThemeCatalog.configNames))` — matching
what `renderer` (`:286`) and `engine` (`:298`) already do, which is the repo's own
precedent for "a warning must name every spelling that would have worked". Same
line count. Everything else in `load()` — the classic-plus-override promotion at
`:222-226`, the four per-field overrides, the 16-colour check — is untouched, so
the fail-soft-per-field contract is preserved by not being edited. **No throwing
path is introduced.**

**`StarterConfig.swift` (+1).** `:49` `"// preset-values": "afk-dark | tokyo-night | classic"`
becomes `"afk-dark | afk-light | tokyo-night | classic"`, and one new commented
line notes that `afk-light` flips the window chrome light. Header already says
"keep the values here in step with `Config.swift`" (`:17`).

**`app/README.md` (+7, exempt).** `:321` gains `afk-light`; the `theme` row at
`:320` gets the correction from §4 (colours are installed but 16–255 stay xterm);
a short paragraph after `:331` states the light-background cost of the fixed cube
and names `check-light-theme.sh`.

**`AFK.md` (+3, exempt).** File table gains the `ThemeCatalog.swift` row and
updates `Theme.swift`'s "Owns"; the Commands list gains `check-light-theme.sh`;
the Configuration bullet at `:141` gets the same ANSI correction.

### 6. Gate: `app/Scripts/check-light-theme.sh`

**Shape copied from `check-renderer-config.sh`**, which I read end to end: `cd` to
`app/`, `command -v swiftc || exit 2`, `[[ -f $SRC ]] || exit 2`, `mktemp -d` with
a trap, harness written to `$TMP/pure/main.swift` (Swift only allows top-level code
in a file named `main.swift`), compile wrapped in
`if ! swiftc -O -o … "$SRC" "$TMP/pure/main.swift"; then … exit 2; fi`, run, match
`ALL-OK` in stdout, else print failures and `exit 1`.

**Exit contract:** `0` every case passes · `1` a real assertion failure · `2`
environmental — no `swiftc`, `ThemeCatalog.swift` missing, or a harness that would
not compile. Never conflated, per `AFK.md:40`.

**I built and ran this harness** (`/tmp/lmproto/pure/main.swift`, 97 lines, compiled
against the real prototype). It prints `ALL-OK` and exits 0. Cases:

1. **Well-formedness** — every shipped hex parses; every `ansi` array is exactly 16.
   Earns its place: `installPalette` is a no-op unless `colors.count == 16`
   (`vendor/SwiftTerm/…/Terminal.swift:717-723`), so a 15-entry preset would install
   bg/fg and silently keep the old palette.
2. **THE KILL CRITERION** — `afk-light`'s background luminance **must** exceed
   `lightChromeCutoff`, or `AppConfig.appearance` (`Config.swift:141`) returns
   `.darkAqua` and the whole feature half-works in silence.
3. **Control for case 2** — `afk-dark` and `tokyo-night` must stay **below** the
   cutoff. A `luminance` that returned a constant above the cutoff would make case
   2 pass for the wrong reason; this catches it.
4. **The formula, against hand-computable values** — white → 1.0, black → 0.0,
   `#808080` → 0.21586 ±1e-5. Specifically guards the gamma expansion.
5. **Name resolution** — round-trip for every record; `afklight`/`AFK-Light` fold;
   `classic` **must** stay `nil`; unknown stays `nil`; `configNames` contains both
   `classic` and `afk-light`.
6. **Legibility** — all twelve content slots ≥ CR 3.0 on their own background, and
   the foreground ≥ 4.5.
7. **Control for case 6** — `afk-dark`'s ANSI on `afk-light`'s background must fail
   the same test in ≥4 slots. If a dark palette reads as legible on white, the
   contrast function is not measuring contrast and every green case above is void.

**Falsification — the exact one-line reverts, all three executed:**

**(A) The bug the gate exists for.** In `ThemeCatalog.afkLight`, change
`background: "#FFFFFF"` → `background: "#0D1117"`. **Result: 7 cases fail**, led by
the kill criterion verbatim:

```
FAIL afk-light: background #0D1117 luminance 0.00548 is at or BELOW the 0.179
     cutoff, so chrome would be DARK — wanted light
```

…and, importantly, the case-7 control also fires
(`only 0 afk-dark ANSI slots are illegible on #0D1117`), which is the signature of
"the subject is no longer a light theme" rather than "one assertion tripped".

**(B) The plausible simplification.** In `ThemeCatalog.luminance`, replace the
gamma expansion `c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4)` with `c`.
**Result: 9 cases fail** — the `#808080` assertion first, then eight contrast
slots, because un-expanded luminance systematically misjudges mid-tones. Note
what does *not* fail: cases 2 and 3 both still pass, since the error is monotonic.
That is exactly why case 4 exists as a separate assertion.

**(C) A wrong-but-plausible palette.** Swap `afkLight`'s values for Catppuccin
Latte's. **Result: 7 cases fail**, each naming a slot and its CR
(`#DF8E1D is CR 2.31 on #EFF1F5`). This is the case that makes the gate a
*legibility* check and not a spell-checker: a real, popular, correctly-transcribed
light palette is rejected on measurement.

**What this gate cannot see**, stated in its header the way `check-cwd-follow.sh`
states its blindness: it never renders a pixel; it cannot tell you the sidebar
material actually changed, that the tab strip rail picked the right blend, or that
the caret is visible against a selection. Those import AppKit and are `UMBER_DIAG`
and daily-drive territory. It also cannot check ANSI 16–255, which are the
emulator's, not ours (§4).

### 7. Out of scope / refused

**Deferred to PR 2 (a real next step, planned):** following macOS System Settings.
§3 has the mechanism and the full file-by-file blast radius.

**Deferred, unplanned:** a `light:X,dark:Y` value for `theme.preset` (Ghostty's
syntax; adopt it *with* the switch, not before, or it is a field with no
consumer). Per-Space themes. Live theme preview.

**Refused:**

- **A second light preset.** §1 — the runners-up are measurably worse and I will
  not ship a palette I have measured as partly illegible.
- **Hand-tuning any hex, including an AFK-orange caret for light.** §4. No
  citable source, and the obvious candidate fails contrast at 2.82.
- **`appearance: auto|light|dark` as a config field.** §2 — it duplicates and can
  contradict a derived value.
- **Changing `ansi256PaletteStrategy`.** `.base16Lab` / `.base16LabHarmonious`
  would adapt 16–255 to a light background and superficially fix the 144-of-240
  problem in §4, and it must still be refused: it discards the standard xterm
  cube that `TerminalPane.swift:156-165` deliberately restored, for every theme
  and both light and dark. A light preset must not silently change how 256-colour
  output renders for existing dark users. If it is ever revisited it is its own
  decision with its own gate — note `.base16LabHarmonious` exists precisely for
  light themes (`vendor/…/Colors.swift:18-21`), so the option is real, just not
  this PR's.
- **Touching `theme == nil` as the default.** No theme installed remains the
  default; `afk-light` is opt-in exactly as `afk-dark` is.
- **A preferences UI / theme picker.** `AFK.md:174` lists it under Not Built Yet;
  config is a JSON file.
- **Reading the palette from disk (`.itermcolors`, Ghostty theme files).** New
  parser, new failure modes, no request.

---

## Prior art

**Ghostty** — directly relevant; Umber links libghostty 1.3.2. Separate light/dark
themes use `theme = light:<name>,dark:<name>`; the reference states *"To specify a
different theme for light and dark mode, use the following syntax:
`light:theme-name,dark:theme-name`… Whitespace around all values are trimmed and
order of light and dark does not matter. Both light and dark must be specified in
this form."* (https://ghostty.org/docs/config/reference; source
https://github.com/ghostty-org/ghostty/blob/main/src/config/Config.zig). Landed in
PR #2735 (merged 2024-11-20, https://github.com/ghostty-org/ghostty/pull/2735),
before the 1.0.0 release of 2024-12-26 — *inferred* from those dates, as the
reference carries no "available since" tag for `theme`; flagged as such.
`window-theme` takes `auto | system | light | dark | ghostty`, where *"auto —
Determine the theme based on the configured terminal background color. This has no
effect if the 'theme' configuration has separate light and dark themes. In that
case, the behavior of 'auto' is equivalent to 'system'."*
(https://github.com/ghostty-org/ghostty/discussions/8724). **`auto` is exactly
`AppConfig.appearance`** — derive the chrome from the background luminance. Umber
already implements Ghostty's default behaviour and has done since before this
scope; that is the strongest evidence that §2's answer is right. On macOS Ghostty
follows `NSAppearance`/`effectiveAppearance`
(https://github.com/ghostty-org/ghostty/issues/9360), with a history of flakiness
(https://github.com/ghostty-org/ghostty/issues/8282) — worth knowing before PR 2.
Ghostty ships **no default light theme** and has not chosen one
(https://github.com/ghostty-org/ghostty/discussions/4875). On ANSI: *"Any
additional colors specified via background, foreground, palette, etc. will override
the colors specified in the theme"*, and 16–255 generation
(`palette-generate`/`palette-harmonious`, since 1.3.0) is **off by default** —
matching what `GhosttyPane+Appearance.swift:69-76` assumes.

**VS Code** — the clearest opt-in model: `window.autoDetectColorScheme` (boolean,
**default `false`**, confirmed in source
`src/vs/workbench/services/themes/common/themeConfiguration.ts` and PR #87405)
plus `workbench.preferredLightColorTheme` / `workbench.preferredDarkColorTheme`
(https://code.visualstudio.com/docs/configure/themes#_automatically-switch-based-on-os-color-scheme).
Note the shape: **a toggle *plus* two theme slots** — following the OS is a
separate decision from having two themes. That is a direct argument for splitting
this into two PRs.

**iTerm2** — Profiles ▸ Colors has *"Use separate colors for light and dark mode"*,
added in 3.5.0 (https://iterm2.com/documentation-preferences-profiles-colors.html;
changelog https://iterm2.com/downloads/stable/iTerm2-3_5_0.changelog; internal key
`KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE`). Opt-in, off by default —
though "off by default" is corroborated only by a community walkthrough
(https://carloschac.in/2024/05/27/iterm2-dark-light-mode/), not an official page.
Distinct from Settings ▸ Appearance ▸ Theme, which governs window *chrome*
(https://iterm2.com/documentation-preferences-appearance.html) — the same
chrome-vs-content split Umber has between `appearance` and `theme`.

**WezTerm** — detection is built in, switching is the user's: `wezterm.gui.get_appearance()`
returns `"Light"`/`"Dark"`/`"LightHighContrast"`/`"DarkHighContrast"`
(https://wezterm.org/config/lua/wezterm.gui/get_appearance.html), and the docs'
own example defines a *user* function to map it onto `color_scheme`
(https://wezterm.org/config/appearance.html). **Correction to a common belief:**
`scheme_for_appearance` is not a WezTerm API — it is the name used in their sample
config. `window:get_appearance()` fires `window-config-reloaded` on change
(https://wezterm.org/config/lua/window/get_appearance.html).

**Alacritty** — **refuted, deliberately.** One `[colors]` table, no light/dark pair
(https://alacritty.org/config-alacritty.html). Maintainers declined repeatedly:
*"There is no desire to add this"* (#5999), *"Not interested in handling this
inside of Alacritty"* (#7723), *"I have no interest in supporting this"* (#6311).
`decorations_theme_variant` affects window decorations only, not content. A
respected terminal shipping zero auto-switching is a reasonable precedent for
deferring it.

**Apple Terminal.app** — the official guide documents per-profile colours and
never mentions appearance switching
(https://support.apple.com/guide/terminal/change-profiles-text-settings-trmltxt/mac).
The claim that the stock Basic profile tracks appearance via dynamic system
colours until customised is **community-sourced only** (e.g.
https://apple.stackexchange.com/questions/408664/, and the existence of
https://github.com/patrik-csak/auto-terminal-profile). Flagged unconfirmed.

**Where this lands Umber:** deriving chrome from background luminance = Ghostty's
`window-theme = auto`, already shipped. Shipping a light preset = table stakes;
every product above has one except Ghostty. Auto-switching = opt-in everywhere it
exists (VS Code default-false, iTerm2 checkbox, WezTerm user Lua) and absent in
two of six. Deferring it to PR 2 puts Umber in the majority, not behind.

---

## Corrections to the brief

**1. The ANSI caveat is WRONG as stated, and it matters.** The brief says
*"installing ANY theme regenerates ANSI 16–255 by interpolating bg/fg (SwiftTerm's
`ansi256PaletteStrategy`, LAB interpolation)… A light theme inherits this
trade-off."* It does not, because Umber turns that off. `TerminalPane.swift:165`:

```swift
view.getTerminal().ansi256PaletteStrategy = .xterm
```

executed in `apply(config:)` **before** any colour is installed, with a nine-line
comment (`:156-164`) explaining that SwiftTerm defaults to `.base16Lab` and this
restores the standard cube. The mechanism confirms it: `Terminal.swift:523,538`
guard the rebuild with `if options.ansi256PaletteStrategy != .xterm`, and
`setupDefaultAnsiColors` (`Colors.swift:148`) routes `.xterm` to
`generateXtermPalette`, the fixed 6×6×6 cube plus greyscale ramp
(`Colors.swift:169-190`). `git blame` dates the line to commit `01803c8d`,
2026-07-26 — it has been there since before the rename.

Consequences: (a) the light preset does **not** inherit the interpolation
trade-off; (b) **the repo's own prose is stale in five places** and this PR should
fix the two it touches — `Config.swift:58-62`, `README.md:320`, `AFK.md:141`,
`StarterConfig.swift:46`, `GitStatus+Presentation.swift:38-42` all still describe
the pre-`.xterm` behaviour; (c) `GhosttyPane+Appearance.swift:70-73` has it right,
and is the only place that does; (d) the *real* light-background ANSI problem is
the opposite one — the cube is now fixed and dark-tuned, so 144 of 240 extended
colours fall below CR 3.0 on white (§4). Right conclusion ("say so"), wrong reason,
and the honest note is a different sentence.

**2. "`preset(named:)` resolves them, and `classic` deliberately maps to nil" — precise, but the nil is not in that function.** `Theme.preset(named:)` (`:143-149`)
has no `classic` case; it returns nil via `default`, the same as a typo. The
*deliberate* handling is in `Config.swift:215-226`, which tests
`t.preset?.lowercased() == "classic"` and distinguishes it from an unrecognised
name (which warns and promotes to `afk-dark`). This matters for the design: it is
why `ThemeCatalog.named(_:)` must keep returning nil for `classic` **and** why the
gate asserts that explicitly — merging the two nils in a "tidy-up" would turn a
typo into a silent no-theme.

**3. Minor: `GitStatus+Presentation.swift:36` is a fragment of a longer clause.**
The "would look wrong in light mode" phrase belongs to a sentence about *VS Code's
hex values*, not about this file's own approach. The conclusion the brief suspected
is right (zero changes needed); the line is evidence *for* the file, not a caveat
against it.

**Everything else in the brief verified as stated:** two dark presets at
`Theme.swift:108-148` (`#0D1117`, `#1A1B26`); `effectiveBackground` at `:118`;
`appearance` at `:140` with `lightChromeCutoff = 0.179` at `:149`; the pin at
`SpaceWindowController.swift:164-166` and `AppDelegate.swift:198`; no system-appearance
observer anywhere; `README.md:320-331` and `StarterConfig.swift:48-50`; and every
LOC figure (`Config.swift` 334, `TerminalPane.swift` 346, `Theme.swift` 150,
`SpaceWindowController.swift` 309, `GhosttyPane+Appearance.swift` 182,
`GitStatus+Presentation.swift` 76, `StarterConfig.swift` 56). `verify-vendor.sh`,
`check-renderer-config.sh` and `check-file-size.sh` all exit 0 in this worktree.

---

## Risks and unverified claims

1. **The 256-colour cube on a light background is unfixable in this PR and is a
   genuine quality regression relative to the dark experience.** 144 of 240
   extended colours below CR 3.0 on `#FFFFFF`, including greyscale 246–255. It
   must be documented, not hidden. Mitigation is documentation only; a real fix
   means `.base16LabHarmonious`, refused in §7.
2. **No pixel is verified.** The gate is arithmetic on hex. That the sidebar
   material, tab-strip rail blend, source-list selection pill and scroller knob
   actually look right in `.aqua` against `#FFFFFF` is **unverified and cannot be
   verified by any check in this repo** — same accepted-unverified category as the
   git sidebar's rendering (`AFK.md:162`). Requires one hand-check with
   `UMBER_DIAG=1` before merge. This is the largest residual risk.
3. **`DocumentTabStrip+Drawing.contentIsDark` uses HSB `brightnessComponent < 0.5`
   (`:31`), a different metric from `relativeLuminance`.** For `#FFFFFF` both agree
   (brightness 1.000 → not dark; luminance 1.0 → light) so this PR is safe, and I
   computed the same agreement for all four candidate backgrounds. But the two can
   disagree in the mid-range — saturated blue `#0000FF` is brightness 1.0 ("light")
   and luminance 0.0722 ("dark") — so a future preset could split them. Not worth
   unifying now; worth a note.
4. **`TerminalPane.apply(config:)` does more than recolour** — it also calls
   `changeScrollback` and `applyRenderer` (`:177-178`). Harmless in PR 1 (nothing
   new calls it), a real hazard in PR 2 if an appearance observer re-applies the
   whole config on every flip.
5. **My LOC figures for the new files are measured for `ThemeCatalog.swift` (149,
   compiled) and the harness (97, compiled and run), but the ~215-line shell
   wrapper is an estimate** scaled from `check-renderer-config.sh` (142 lines with
   a 61-line harness). It could land 10–20 lines either way; it is a script, and
   `check-file-size.sh` covers `Scripts/` too, so keep an eye on it.
6. **Ghostty's `light:/dark:` syntax version attribution is inferred**, not
   labelled — PR merge date vs release date. The syntax itself is confirmed
   verbatim.
7. **Apple Terminal.app's "no auto-switching" is community-sourced.** No official
   Apple page confirms or denies it.
8. **Catppuccin Latte's six computed "bright" values** came via a theme aggregator
   because the upstream raw file would not fetch. Since Latte is rejected, this
   only weakens the rejection evidence, not the recommendation — and the ten
   first-party-confirmed slots already include three below CR 3.0.
9. **GitHub Light Default's foreground has one conflicting citation** (`#0E1116` in
   alacritty-theme's port vs `#1F2328` in the Ghostty port and primer). I used
   `#1F2328`, which is CR 15.80 on white; the alternative is darker still, so the
   choice is not load-bearing for legibility.
10. **Not checked:** whether libghostty honours all sixteen `palette` entries at
    runtime for a light theme (the code path at `GhosttyPane+Appearance.swift:74-76`
    is engine-side and untestable here — the `ghostty` engine is opt-in and
    ungated); actual macOS rendering of `.aqua` chrome against `#FFFFFF`; whether
    any user has a `config.json` with a light background today.
