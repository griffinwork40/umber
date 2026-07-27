# Naming decision brief — what to call this app

**Date:** 2026-07-27 · **Status:** RESOLVED AND EXECUTED — renamed to **Umber** in `faf1291`, repo is now `griffinwork40/umber` (the "research only, nothing renamed" state below describes this brief as written, before the rename landed) · **Repo state at time of research:** `main` @ `a37c312`, 2 unpushed commits, 6 dirty files (keybindings WIP)

Research method: two parallel sub-agents (external naming landscape + local rename-cost inventory), followed by
first-party verification of every load-bearing claim via registry/API calls and direct file reads. Availability
claims below name the URL or command that produced them.

---

## 1. The finding that forces a rename regardless of which name wins

`MacTerminal` is not merely a placeholder — it is **actively colliding with its own dependency**:

```
vendor/SwiftTerm/TerminalApp/MacTerminal.xcodeproj/
vendor/SwiftTerm/TerminalApp/MacTerminal/
```
*(verified: `ls -d vendor/SwiftTerm/TerminalApp/*/`)*

SwiftTerm's bundled demo app is also called MacTerminal. This project vendors SwiftTerm v1.15.0 directly, so the
build tree contains two different things with the same product name.

Second, independent reason: Apple's trademark guidance restricts "Mac" in third-party product names to products
that are **not** "a computer, computer system, or operating system software"
(<https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html>). A terminal emulator is
arguably system software, so `MacTerminal` / `mac-terminal` is legally disfavored for a public release.

**Conclusion:** the name must change before publishing. This is not a taste question.

## 2. Now is the cheapest possible moment — and the cost is rising

| Signal | Value | Source |
|---|---|---|
| git tags | **0** | `git tag -l \| wc -l` |
| releases / Homebrew casks / notarization | none (ad-hoc signature only) | `make-app-bundle.sh:83-87` |
| tracked files referencing the name | **8** | `git grep -ln 'MacTerminal\|macterminal'` |
| MUST-change edit sites | ~11 | inventory below |
| SHOULD-change (cosmetic/docs) | ~12 | inventory below |

Nothing has shipped to anyone, so a rename strands exactly one config file (the author's own).

**The cost is growing as work-in-progress lands.** Uncommitted files already add new name-derived identifiers —
`MTTerminalView.swift` and the `MT_DIAG` env var (`TerminalPane.swift:99`) bake the initials in. Every week of
WIP widens the rename surface.

**Documentation bug found:** `README.md:11-12` claims the placeholder is referenced only in
`make-app-bundle.sh` and its generated `Info.plist`. That is **false** — 8 tracked files reference it, including
3 Swift sources, `Package.swift`, and the source directory name itself. Treat that README line as unreliable.

### Rename-cost inventory

**MUST change (~11 sites)**
- `app/Scripts/make-app-bundle.sh:18` `APP_NAME="MacTerminal"`, `:19` `BUNDLE_ID="com.macterminal.app"` — drives `CFBundleExecutable`/`Identifier`/`Name`/`DisplayName` (`:56-62`) and the `.app` path (`:35`)
- `app/Package.swift:9` package name, `:23` executable target, `:25` `path: "Sources/MacTerminal"`
- `app/Sources/MacTerminal/` — directory rename (pinned by `Package.swift:25`)
- `app/Sources/MacTerminal/AppDelegate.swift:93` `let appName = "MacTerminal"` → About/Hide/Quit menu items (`:99,104,105`); the only user-visible name strings
- `app/Sources/MacTerminal/Config.swift:193` `.config/macterminal/config.json`

**SHOULD change (~12 sites)** — `README.md:1,11,42,45,50`; `app/README.md:1,6,16,22,54`;
`TerminalWindowController.swift:17` (`com.macterminal.terminal`), `:63` (`setFrameAutosaveName`);
`Config.swift:143` (`"MacTerminal.fontSizeOverride"`); the `mac-terminal` GitHub repo slug.
Renaming the autosave/override keys silently resets window position and zoom — harmless for one user.

**Bundle-id recommendation:** current `com.macterminal.app` is *product-derived*, so any rename forces a new
bundle id. Move to a stable **personal/org prefix** (`com.griffinlong.<name>`) so the next rename — or a second
app — never breaks identifier continuity again.

## 3. What the name has to do (derived from the code, not taste)

**Hard constraints**
- **Single word, valid Swift identifier.** The name is simultaneously the SwiftPM package name, executable target, module name, and `CFBundleExecutable` (`Package.swift:9,23`; `make-app-bundle.sh:29,39`). No spaces or hyphens. A spaced *display* name is possible only by decoupling `CFBundleDisplayName` from `$APP_NAME`, which currently share one variable (`:56-62`).
- **Not `MacTerminal`**, and no `Mac`/`Apple`/`i`-prefix (§1).
- **Homebrew cask name must be free** — that is the intended distribution channel, so it outranks npm as an availability signal. (npm barely matters: this is a Swift app, not a Node CLI.)

**Positioning constraints**
- "No AI" is the product boundary, not a gap: zero model calls, no chat UI (`plan:21-22`, `plan:370-374`). The name must not read as an AI terminal.
- The app is a **host**: a beautiful native window an agent lives inside, not an IDE (`README.md:3-4`, `plan:1`).
- The bar is *"beautiful, and user-friendly as hell"*, built for the author (`plan:15-16`, `plan:23`).
- Aesthetic already chosen: dark, restrained, native-conventional, with warm-orange accent `#E67E4C` described in-code as *"the AFK warm-orange accent… matching afk's brand tone"* (`Config.swift:60-78`). SF Mono 14pt. **No app icon exists** — visual identity is unclaimed (`plan:292`).

## 4. Eliminated, with evidence

| Rejected | Why | Evidence |
|---|---|---|
| `Warp`, `Wave`, `Zenith`, `Ember` | taken **and** semantically coded "AI terminal" | warp.dev; waveterm; Gkyohd/zenith; emberterm.com |
| anything `*term` / `*terminal` | saturated to absurdity; signals "couldn't get the real name" | WezTerm, cterm, Termy, qwertty-term, Extraterm, mlterm, xterm, st |
| anything with AI/LLM/Agent/GPT | that is the crowd, and the wrong flag | Awal, infinitty, Zenith |
| **`Plinth`** | **423★ `jabrena/plinth` = "AI-native engineering toolkit"** — collides on name *and* on the exact positioning this app rejects | GitHub search API, exact-name match |
| `Kiln` | 4,969★ `Kiln-AI/Kiln` AI workbench *with a macOS app*; kiln.digital active | web research |
| `Cairn` | two 2026 agent-CLI repos; cairn.com live | web research |
| `Loupe`, `Etch`, `Glaze` | high-traffic npm (chai/vitest dep; Atom) or an existing **homebrew/core formula** | registry fetches |
| `Alcove`, `Adze`, `Vellum` | **existing Homebrew casks** (HTTP 200) — kills the distribution channel | `formulae.brew.sh/api/cask/<n>.json` |
| `Jig` | 315★/229★ exact repos + 108★ "pre-execution **Agent** Firewall"; App Store "Jigsaw*" leads | GitHub + iTunes search API |
| `Skiff` | Skiff Mail → Notion trademark | web research |
| `Blackbird`-adjacent | `conjfrnk/blackbird` already claims the literal "minimal, feels like Apple shipped it" pitch | blackbird-terminal.com |

**Domains are not a tiebreaker.** Every single-word `.app` and `.com` I probed is registered (RDAP HTTP 200 for
sconce/sash/plinth/kerf/jig/taper). That is precisely why this whole cohort ships compound domains —
`blackbird-terminal.com`, `emberterm.com`, `termy.sh`, `infinitty.ai`. Plan on `<name>.sh`, `get<name>.app`, or a
compound; do not let domain availability drive the name.

## 5. Finalists — all verified free where it counts

| Candidate | brew cask | brew formula | npm | GitHub exact-name prior art | Mac App Store | Risk |
|---|---|---|---|---|---|---|
| **Sconce** | 404 free | 404 free | **404 free** | 11 matches, max **45★** (obscure AutoML compression pkg) | 0 results | **low** |
| **Sash** | 404 free | 404 free | 200 taken | 8 matches, max **76★** (all obscure/unrelated) | 0 leading matches | low |
| **Transom** | 404 free | 404 free | 200 taken | 19 matches, max **1★** — effectively zero prior art | 0 leading matches | low |
| **Kerf** | 404 free | 404 free | **404 free** | 2 matches, max 38★ (columnar tick DB) | 0 leading matches | low-med |

*Commands: `formulae.brew.sh/api/{cask,formula}/<n>.json`, `registry.npmjs.org/<n>`,
`api.github.com/search/repositories?q=<n>+in:name&sort=stars` (top-40 scanned, exact-name filtered),
`itunes.apple.com/search?entity=macSoftware`.*

## 6. Recommendation — ranked

**1. `Sconce`** — the pick. The only finalist free on **all three** registries (cask, formula, npm) with no
credible dev-tool namesake. A sconce is the wall fixture that *holds a light* — which is literally what this app
is: the beautiful native fixture that holds agent-afk's glow. It ties directly to evidence already in the code:
the accent is warm lamplight, `#E67E4C`, self-described as matching afk's brand tone (`Config.swift:60-78`). And
the story closes on the parent product's own name — **AFK is away-from-keyboard; a sconce is the light you leave
on.** One word, valid Swift identifier, `com.griffinlong.sconce`, brew cask `sconce` free today.
*Weakness:* lower word-recognition; some people will need to be told what it means once. Ghostty/Tot/Bear
precedent says that is survivable, and a distinctive name is easier to own than a generic one.

**2. `Sash`** — best pure ergonomics: four letters, one syllable, trivial to type and say, impossible to
misspell. A sash is the movable glazed part of a window, which maps onto the actual differentiator (real native
macOS window tabs). *Weakness:* npm taken (low impact for a Swift app); "sash" also means a ribbon, so the
window sense is inside-baseball.

**3. `Transom`** — the strongest "nobody else has this" claim in the set: 19 exact-name repos with a maximum of
**one** star. A transom is the small window above a door — a window you see through into another room, which is
what a terminal is. *Weakness:* seven letters and a beat of spelling friction.

**4. `Kerf`** — clean and craft-honest (the slot a saw blade cuts), free on cask/formula/npm, but semantically
silent about what the app *does*, and a 38★ database shares the name.

### The one question the code cannot answer

Should this name signal **kinship with agent-afk** or stand **independent**? The shared `#E67E4C` accent implies
a family. If family is the intent, the lamplight field (**Sconce**, Taper, Wick) is the coherent choice because
AFK's own accent *is* lamplight. If independence is the intent, **Sash** or **Transom** — native-window
vocabulary with no parent-product tell — is the better read. This is the operator's taste call; everything above
is evidence.

## 6b. Adversarial critique round (`/devils-advocate`) — Sconce survived, with two corrections

Operator constraint added after the first draft: **"independent of agent-afk, but I wouldn't mind if it were a
nod."** The name must stand alone; an allusion is welcome but must not be the justification. This demoted §6's
AFK story from *argument* to *bonus*, so the recommendation was re-tested by three independent critics
(pragmatist / paranoid / architect), each required to verify availability first-hand and to invent an alternative.

**Outcome: no critic rated its alternative `strong`** (weak / medium / medium), so `dissent = false` and no
convergence — three different alternatives, no shared pick. Per the critique contract, recommendation = original:
**Sconce stands.** Two substantive corrections came out of it, plus one action redirect.

### Correction 1 — SEO contest is real and 3-layer (closes a gap §7 had left open)

My first draft listed PyPI as unchecked. It is not free:

| Layer | Observed |
|---|---|
| PyPI `sconce` | **HTTP 200** — v0.99.1, *"Model Compresion Made Easy"* |
| `sconce.readthedocs.io` | **HTTP 200** — live docs site |
| GitHub `satabios/sconce` | 45★ AutoML model-compression |
| crates.io `sconce` | 404 free |

So `sconce github` and `sconce docs` resolve to an unrelated ML package, and will keep doing so. **Accept this
consciously:** it is a discoverability tax, not a blocker, and it is a tax this app does not need to pay — a
for-himself tool distributed by Homebrew cask + README + word of mouth does not compete with a Python package for
query intent. `sconce mac terminal` and `sconce.sh` remain winnable. Do not pick a name *for* SEO here.

### Correction 2 — trademark risk is UNRESOLVED, not "fallen" (a critic claim, refuted)

The paranoid critic argued Sconce's trademark risk *dropped* because the one software-class holder vacated:
"sconce.com expired 2025-06-24." **That is false.** RDAP on `sconce.com`:

- registration 2001-06-24, **expiration 2027-06-24** — renewed, not expired
- last changed **2026-06-29** (one month ago)
- status: `client delete/renew/transfer/update prohibited` — registrar locks typical of a defended corporate asset
- HTTP 200, redirecting to `pdsvision.com/sconce`, title *"Sconce becomes PDSVISION"*

The **rebrand is real** — Sconce Solutions Inc (PLM software) is now PDSVISION — but they are *defending* the
name, not abandoning it. A retired-but-defended mark in the software class is modest exposure, not zero.
Probability a free Mac terminal draws a complaint: low. Severity if it lands post-notarization: high (forced
rename). **This is the one genuinely unresolved risk, and it is cheaply answerable — see the gate in §6c.**

### Action redirect — the architect's frame attack partly lands

The strongest argument in the wave was structural, not lexical: the craft/light/architecture semantic field is
*the most-mined seam in indie Mac naming*, and the 20-name elimination list in §4 is the evidence, not bad luck.
A dictionary word can never be fully owned in search or in mark. Two rebuttals hold, though:

- **"A concrete noun mortgages the icon" is backwards here.** No icon exists and the author must draw it himself.
  "Draw a sconce" is an asset for a solo dev; a coinage forces the icon to invent meaning from nothing.
- **The field's converged alternative is `-tty` (Alacritty, Ghostty).** Taking it makes this the *third* such
  terminal — importing the crowd's morpheme, for an app whose whole positioning is not-the-crowd. Same objection
  that already eliminated `*term` in §4, one layer over.

**What does land:** the app icon is genuinely unclaimed and does more identity work than the name. After the name
is settled, spend the next identity cycle there, not on more name search.

### Alternatives generated, and why each lost

| Alternative | Lens | Verified | Why it lost |
|---|---|---|---|
| **Velvetty** (velvet+tty) | architect, `medium` | cask 404 · formula 404 · npm 404 · PyPI 404 · crates 404 · GitHub `total_count: 0` · iTunes 0 — **cleanest name found, verified first-hand** | `velvety` is a real English word one letter away = permanent typo tax on cask + slug; third `-tty` terminal reads as follower |
| **Ambril** (coined, amber-ish) | paranoid, `medium` | cask/formula/npm/PyPI all 404; 0 exact GitHub; 0 iTunes | Meaning is invisible without being told; reads as generic-SaaS/pharma, failing the handmade-craft test Sconce passes |
| **Taper** | pragmatist, `weak` | cask 404 · formula 404 · **npm 200** · **PyPI 200** · GitHub 71★ `dsppman/Taper` | Strictly worse registries than Sconce, and *"taper off"* = diminish is a bad connotation for a tool |

The pragmatist attacked Sconce's spelling tax and concluded it does not hold up (`s-c-o-n-c-e` is phonetically
regular; the "scone" joke is a one-time ~5-second cost), and made the sharpest point in the wave: **the naming
search now costs more than Sconce's entire lifetime explaining tax.** Stop searching.

## 6c. Decision: Sconce, gated

**Ship `Sconce`, contingent on one cheap check.** The only unresolved risk is trademark, and it is answerable in
minutes rather than avoidable by switching names:

1. **Run a USPTO/TESS search** for `sconce` in the software/Class 9 + Class 42 classes before claiming the
   Homebrew cask or renaming the repo. (`tmsearch.uspto.gov` is a JS-only SPA — no scriptable endpoint; do this
   by hand.)
2. **If TESS is clean →** proceed: `Sconce`, bundle id `com.griffinlong.sconce`, cask `sconce`, and accept the SEO
   tax knowingly.
3. **If TESS shows a live software-class mark →** fall back to **`Velvetty`**, the verified-cleanest name in this
   whole exercise (six registries free, zero GitHub matches), accepting the `velvety` typo tax.
4. Either way, **the next identity cycle goes to the app icon**, not to more name search.

Ranked against the operator's weighted criteria — (a) independence, (b) registry+trademark defensibility,
(c) ergonomics, (d) craft-aesthetic fit, (e) headroom:

| | (a) indep | (b) defensible | (c) ergonomics | (d) aesthetic | (e) headroom | verdict |
|---|---|---|---|---|---|---|
| **Sconce** | pass — stands alone, nod is latent not load-bearing | good registries / **trademark open** | **best** | **best** | good | **1st** |
| Velvetty | pass | **best** | weak (`velvety` trap) | good | good | 2nd (fallback) |
| Ambril | pass | very good | fair | weak | good | 3rd |
| Taper | pass | weak | good | good | fair | 4th |

**Strongest argument against this recommendation:** the architect is right that a coinage is strictly more ownable
in both search and trademark, and Sconce's SEO slot is *permanently* contested by three live properties. If this
app ever stops being a for-himself tool and needs organic discovery, `Velvetty` would have been the better choice
and switching later costs far more than switching now. I am accepting that risk because discoverability is not
this project's constraint and the name's day-one legibility and aesthetic fit are.

## 6d. Operator veto → re-run with SOUND as the first filter → **Umber**

**Operator:** *"but that name isnt catchy and easy to say."* Correct, and it overrides §6c. `Sconce` has an awkward
`-nce` cluster, a "scone" homophone, and needs a one-time explanation. I had scored "catchy / easy to say" as a
footnote under ergonomics (typing + spelling) while weighting semantic aptness and registry cleanliness heavily.
For a tool the author lives in daily, phonetic appeal is a **primary** criterion. **Sconce is retired.**

The convention in this space is phonetic, not semantic — `Ghostty`, `kitty`, `Tabby`, `Rio`, `Warp`, `Blink`,
`Bear`, `Tot`: one or two syllables, trochaic stress, no pronunciation ambiguity. Ghostty means nothing; it just
feels good to say. So the search was re-run generating for *sound* and filtering by availability, instead of the
reverse — ~45 candidates swept across brew cask, brew formula, npm, PyPI, GitHub exact-name, and Mac App Store.

### Methodology correction (this one changed the answer twice)

Two silent failures were caught and fixed mid-sweep. Both are worth recording because each produced a
confidently-wrong clean bill of health:

1. **Unauthenticated GitHub search rate-limits return no `items` key**, which my filter counted as "0 exact
   matches." Sixteen names got a false clean verdict; re-running through `gh api` exposed `magpie` 14,247★,
   `wren` 8,084★, `lark` 5,940★, `opal` 5,488★, `willow` 3,081★, `marten` 3,435★.
2. **`in:name` + top-40-by-stars misses exact matches for any name that is a substring of a common word.**
   `cove` ⊂ *cover/coverage/discover/recover*, so the sample was saturated and the real exact matches never
   surfaced. Fix: 200-result sample across two pages, then filter. This **refuted my own intermediate favorite** —
   `cove` looked like it had zero collisions, and actually has `salesforce/cove` 471★ and `emanuele-em/cove` 181★
   *"multi-database GUI client for macOS"* — a same-platform, same-audience dev tool.

### Verified results, sound-first set (200-result GitHub sample)

| Candidate | cask | formula | npm | PyPI | GitHub exact (max★) | MAS | Verdict |
|---|---|---|---|---|---|---|---|
| **Umber** | **404** | **404** | **404** | **404** | 33 matches, **max 8★** (course-mgmt app) | 0 | **winner — cleanest name in the whole exercise** |
| Lull | 404 | 404 | 200 | 200 | 53, max 13★ | 0 | clean, but *lull* = sleepiness; mushy double-l |
| Tarn | 404 | 404 | 200 | 200 | 45, max 20★ | 0 | clean; obscure and flat-sounding |
| Roost | 404 | 404 | 200 | **404** | 49, max 61★ | 0 | good runner-up if 1 syllable is wanted |
| Sash | 404 | 404 | 200 | — | 24, max 76★ | 0 | prior §6 runner-up; soft, evokes ribbon |
| ~~Cove~~ | 404 | 404 | 200 | 200 | 3, **max 471★** + 181★ macOS dev tool | 2 | **out** — same-platform collision |
| ~~Perch~~ | 404 | 404 | 200 | 200 | 47, max 375★ + **87★ terminal client** | 1 | **out** — terminal adjacency |
| ~~Hearth~~ | 404 | 404 | 200 | 200 | 16, max 332★ | 0 | out — contested; *hearth* → "harth" trap |
| ~~Nook / Hush / Mellow / Tuck~~ | **200** | — | — | — | — | — | out — **existing Homebrew casks** |
| ~~Glow / Amber / Loft / Den / Dusk / Snug~~ | mixed | mixed | — | — | 26,541★ / 5,161★ / 847★ / 520★ / 1,943★ / 202★ | — | out — prior art |
| ~~Glim / Lumo / Tallow / Saffron / Glint~~ | 404 | 404 | 200 | mixed | 1,702★ / **1,873★ ClojureScript REPL** / 563★ / **249★ Cloudflare** / 488★ | — | out — prior art |

### Why `Umber` wins

- **Easy to say, zero ambiguity:** UM-ber. Two syllables, trochaic — the same stress pattern as Ghostty/kitty/Tabby. Phonetically regular spelling, `u-m-b-e-r`. Strictly better than Sconce on both saying *and* spelling.
- **Cleanest availability found:** the only candidate free on **all four** registries (cask, formula, npm, PyPI) *and* with no notable GitHub namesake — 33 repos share the string and the largest has **8 stars**. Nothing to out-rank, nothing to be confused with, no dev-tool incumbent.
- **The color story is self-contained and independent of agent-afk.** Umber is a warm earth pigment — burnt umber is orange-brown. The app's accent is already `#E67E4C` (`Config.swift:60-78`). The name *names the app's own color*, with no reference to anything external. A nod is available if wanted, never required.
- **It hands you the icon for free** — which answers the architect's strongest point (§6b: the icon is the genuinely unclaimed asset). A warm pigment swatch / earth-tone mark is an obvious, ownable, color-first direction that needs no metaphor decoding.
- **Trademark surface is far thinner than Sconce's** — no software-class incumbent, no defended corporate domain, no rebrand history to inherit. The §6c USPTO gate still applies, but it is now a formality rather than the load-bearing risk.

**Honest downsides:** "Umber" can be misheard as "Amber" when spoken — mild, and both are warm colors so the
confusion is on-brand rather than damaging. Some people won't know the word means a pigment (most will recognize
it from "burnt umber" on a paint tube or crayon). And it is a shared string — 33 tiny repos — so it is not
globally unique, just uncontested.

### Revised decision

**Ship `Umber`.** Bundle id `com.griffinlong.umber`, cask `umber`, module `Umber`, config
`~/.config/umber/config.json`. Runner-up if one syllable is preferred: **`Roost`** (max 61★, PyPI also free).
Retired: `Sconce` (fails the operator's phonetic criterion), `Velvetty` (the `velvety` typo trap — the same class
of failure), `Cove`, `Perch`.

Still run the USPTO/TESS check for `umber` in classes 9 + 42 before claiming the cask — cheap, and the only
remaining unresolved dimension.

## 7. Coverage and gaps

- **High confidence:** rename-cost inventory and repo state (direct file reads + git commands, re-derived first-party, not taken from sub-agent claims). The SwiftTerm collision, bundle id, 8 referencing files, and zero tags were each independently verified.
- **Medium-high confidence:** registry availability — every cask/formula/npm/GitHub/App Store claim above is an observed HTTP status from a named endpoint.
- **Gaps:** (1) **No USPTO/trademark search** — trademark risk is inferred from brand recognition only; run a TESS search before any public launch. (2) `.sh` TLD availability is **unverified** (whois for `.app`/`.dev` resolved to IANA rather than the registry; the `.sh` registry did not answer reliably). (3) GitHub exact-name matching scanned the top 40 by stars, not the full result set. (4) The 2026 competitor cohort (Blackbird, infinitty, Awal, Zenith, Termy) is reported from search-index cards, not per-repo API reads. (5) PyPI and crates.io unchecked.
- **Time-sensitive:** registry and domain availability, and this fast-moving 2026 terminal cohort, can shift within weeks. **Re-verify the chosen name immediately before claiming the cask and the repo slug.**
