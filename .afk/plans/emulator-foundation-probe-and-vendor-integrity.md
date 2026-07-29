# Emulator foundation: pin the vendor, correct the record, probe libghostty

**Status (2026-07-27):** Step 0 **DONE** (`114e9f8`, `f1e59a8`, `4053a7a`) · Step 1 probe **RUN, D
chosen** — see §6.1 (flip-condition check) and §6.2 (spike results, branch `afk/libghostty-spike`
@ `123919f`) · **next is §8.4**, which supersedes §6.2's "Next, in order": the container must be
regenericized *before* `GhosttyPane` is added, because two `as?` casts would otherwise leave it
silently inert (§8.2) · supersedes nothing; **amends** `native-swift-terminal-afk-host.md` §9 risk 1,
§11 G2, and §12's Step 3/4 ordering, and corrects its own §7 risk 2 (there is no version pin, §8.1).

Companion to the plan of record. Read `native-swift-terminal-afk-host.md` first — this document
does not restate it, it corrects two of its findings and inserts a decision procedure ahead of its
Step 3.

---

## 1. Why this document exists

The operator asked how to "compete with terax-ai (minus the AI for now)" and be "actually the best
terminal." Researching that question produced three findings that invalidate parts of the plan of
record, and one that dissolves the question as posed.

Method: `/research` (2 parallel agents) → `/shadow-verify` (4 independent verifiers, claims stripped
of their original citations) → `/devils-advocate` (3 critics). All three critics returned
`strength: strong`, i.e. `dissent = true`, so no synthesised recommendation was accepted; the
matrix is reproduced in §6 and the decision was converted into an experiment instead (§5).

---

## 2. Finding 1 — the G2 reflow gate was a blind test (corrects §11)

`native-swift-terminal-afk-host.md` §11 and `app/README.md` record that three deterministic reflow
tests could not reproduce SwiftTerm [#494](https://github.com/migueldeicaza/SwiftTerm/issues/494),
and conclude the risk is *"reduced, not closed."*

That conclusion does not follow. The defect only manifests when the scrollback offset is non-zero,
and the harness never established one:

```
git show 1e84dd0~1:spike/Tests/SpikeGatesTests/ReflowGateTests.swift | grep -c yBase
→ 0
```

Two of the three cases ran at `_yBase == 0`, where the defect is *structurally inexpressible*; the
third had `_yBase > 0` but asserted only duplicate-token counts, never missing tokens — so the
orphaning half went unchecked. **This is absence of evidence recorded as risk reduction.** The
correct status is *untested*.

The defect itself is real, confirmed by direct read of the vendored tree:

| Site | Code | Index space |
|------|------|-------------|
| `Buffer.swift:1171` | `_lines[_y].isWrapped = true` | screen-relative ✗ |
| `Buffer.swift:1176` | `let row = _lines[_y + _yBase]` | buffer-absolute ✓ |
| `Buffer.swift:1211` | `_lines [_y].isWrapped = true` | screen-relative ✗ |
| `Buffer.swift:1224` | `let bufferRow = _lines[_y+_yBase]` | buffer-absolute ✓ |

Same functions, same `_y`, two different address spaces five and thirteen lines apart. `_y` is
screen-relative per `Buffer.swift:22,42-43`. Consequence when scrollback is non-empty: the
`isWrapped` flag — the only flag reflow consumes to find logical-line boundaries — lands `yBase`
rows off target, so a falsely-wrapped scrollback line is **joined** to an unrelated neighbour and a
genuinely-wrapped line is **split**. That is silent mangling of history, not a visual glitch.

Upstream state (live GitHub REST, 2026-07-27): #494 `state: open`, `closed_at: null`, 9 comments,
last activity `2026-03-29`. The maintainer's partial fix (`protectedLines`) exists only on unmerged
branch `reflow` @ `0619254f`. Releases v1.12.0→v1.15.0 mention no reflow fix, so **the vendored
v1.15.0 lacks even the partial fix.**

Caveat retained: reflow-on-narrow is genuinely hard across emulators (xterm.js gates
`reflowCursorLine` off by default; there is no escape sequence for "I relaid out N lines"). But the
reporter reproduced orphans with the shell fully silenced (`trap '' WINCH`), so the buffer-level
component is a real implementation bug independent of the protocol limit. The claim that
Terminal.app "exhibits similar artifacts" is one unverified sentence from the issue reporter and
should not be relied on.

## 3. Finding 2 — the vendor patch exists nowhere in git (new risk, live today)

```
git ls-files vendor/            → 0
git log --all -- vendor/        → 0
.gitignore:13                   → vendor/
.gitignore:6                    → Package.resolved
app/Package.swift:20            → .package(path: "../vendor/SwiftTerm")
```

`vendor/SwiftTerm` is not a git repo either (`git rev-parse HEAD` inside it walks up to the parent
repo). So: the local patch has never existed on any ref, there is no lockfile, nothing pins
v1.15.0, and `app/README.md`'s recovery instructions say the change "is annotated in place" —
inside the ignored file.

**The failure is asymmetric.** A missing `vendor/` fails loudly: the build breaks. A re-vendor that
follows the README faithfully produces upstream v1.15.0 *without* the patch and **builds green** —
so the reverted patch fails silently. Any future buffer fix would inherit the same hole, only with
correctness rather than a build flag at stake.

This is a defect in the build, independent of every strategic question below, and it is the one
item here that is strictly worse in Umber today than in the dependency being considered as a
replacement (§4: `libghostty-spm` pins its upstream in a reviewed `Ghostty.ref` and states that a
package release cannot silently switch commits).

## 4. Finding 3 — the competitive frame is aimed at the wrong target

terax-ai is not the competition. `Uzaaft/awesome-libghostty` (branch `master`) lists **~27 projects
in its "AI Tools & Agent Orchestration" section alone**, nearly all macOS-native, nearly all on
libghostty. Representative, verbatim:

- **Mux0** — "native macOS terminal built on libghostty, with workspaces, tabs, and split panes plus
  live status for Claude Code, OpenCode, and Codex sessions"
- **agterm** — "native macOS terminal for AI coding agents that groups sessions into named
  workspaces, with live agent status"
- **in0** — "native macOS terminal multiplexer with live AI agent status, built on libghostty +
  SwiftUI/AppKit"
- plus Zentty, moss, AiyuTerm, limpid, Supacode, TheCommander, Factory Floor, YEN
  ("Terminal-first IDE"), and — in the adjacent section — Enso, Mori, fantastty, conterm, macterm,
  Muxy, OpenOwl, and Ghostree (a Ghostty fork with git-worktree + agent support).

Mux0's description is close to Umber's own spec. The category Umber was heading for is the most
crowded new category in developer tooling, entered ~6 months late, on a slower core.

Two consequences:

1. **"Best terminal" on generic craft is not winnable and not measurable.** Ghostty shipped 1.0
   after ~2 years of private beta with ~2000 testers, and deliberately published no headline
   performance number. The canonical terminal-latency dataset is danluu's, taken on a 2014 MacBook
   Pro running macOS 10.12; no modern public Apple-Silicon study surfaced. Both "fastest" and "not
   fastest" are currently unfalsifiable.
2. **The one position not available to those ~27 is vertical integration across the PTY.** They
   integrate *other people's* agents (Claude Code, Codex, OpenCode) and must infer state by
   scraping stdout. Umber's author ships `agent-afk`, so he can obtain structured session state *by
   contract*. That is §6 Step 1's session-status contract feeding Step 3's Observer panel — and it
   is foundation-independent, so it survives either outcome of §5.

### 4.1 What the replacement candidate actually offers

`Lakr233/libghostty-spm` — MIT, macOS 13+, 86★/55 forks, pushed 2026-07-27 (same day as this
document). Ships a **prebuilt `GhosttyKit.xcframework`**, so no Zig toolchain for consumers.

- `GhosttyTerminal` product exposes `TerminalView`, a typealias resolving to **`AppTerminalView` on
  macOS** — a real AppKit view with delegate callbacks. There is an AppKit demo at
  `Example/GhosttyTerminalApp/`.
- Retained from upstream: Metal renderer, CoreText font rasterisation **and shaping** (→ ligatures),
  full key/mouse/IME pipeline, text selection and clipboard, the whole config system.
- Removed in the trimmed build: custom GLSL shaders, ImGui inspector, Sentry, the Cocoa app
  runtime, the standalone executable.
- Bonus already implemented: `jumpToPrompt(by:)` / `scrollToRow(_:)` on OSC 133 shell integration —
  which was a Tier-2 item in the discarded ordering. Plus 485 bundled iTerm2 themes.
- Pinning: upstream commit recorded in `Ghostty.ref`; "a package release cannot silently switch to a
  different upstream tag or commit."

Counterweight, verbatim from `ghostty-org/ghostty` `include/ghostty.h:1-7`: *"This isn't meant to be
a general purpose embedding API (yet) so there hasn't been documentation or example work beyond
that. The only consumer of this API is the macOS app."* And: types in the header *"must be kept in
sync with their Zig counterparts."* ~100 projects consume it regardless. Because the version is
pinned, ABI instability is a controlled upgrade decision rather than a live hazard.

Cost if adopted: an opaque binary XCFramework replaces auditable vendored text, which breaks this
repo's "all-text, diffable, scriptable" convention and the comment rule requiring citations to
vendor source lines.

---

## 5. Chosen approach: don't decide, probe — the seam makes the bet reversible

The apparent fork ("patch SwiftTerm" vs "swap to libghostty") is not a fork. `SpaceDocument`
(`app/Sources/Umber/SpaceDocument.swift:22-38`) is a four-method protocol, and a second *emulator*
is simply another document kind. Umber can host both at once, in one window, and let real use
decide.

This is exactly what plan §12.3 claimed the restructure bought — "adding a new document kind means
writing a conformer, not touching the container." §5 spends that credit.

### Step 0 — strategy-independent (true under every option in §6)

1. **Close the vendoring hole.** Commit a real patch artifact + a content-based pin + a verifier,
   and call the verifier first from `make-app-bundle.sh` so a missing patch fails **loudly**.
   Content-based because `vendor/SwiftTerm` is not a git repo, so there is no SHA to pin.
2. **Correct the record.** Downgrade the #494 claim in `AFK.md` and `app/README.md` from "reduced,
   not closed" to *untested*, stating why the harness could not see it, and enter
   `Buffer.swift:1171`/`:1211` as a defect of record.
3. **⌘F scrollback search.** SwiftTerm already ships it: `performFindPanelAction` is `@objc open`
   (`Mac/MacTerminalView.swift:2169`), `findNext`/`findPrevious`/`searchMatchSummary`/`clearSearch`
   are `public` on `extension TerminalView` (`TerminalViewSearch.swift:19,40,58,71`), and
   `validateUserInterfaceItem` already validates the find selectors. `UmberTerminalView`
   inherits all of it. So this is menu plumbing — **plus a real collision to fix**:
   `AppDelegate.swift:203` currently binds `keyEquivalent: "f"` to Enter Full Screen.
4. **Open-folder-as-Space.** `root:` is already a threaded init parameter
   (`AppDelegate.swift` → `SpaceWindowController` → `SpaceViewController` → `FileTreeViewController`);
   `defaultSpaceRoot` is `$HOME` with a comment calling itself a placeholder. So this is an
   `NSOpenPanel` and passing the URL through.

### Step 1 — the probe that decides the foundation (timebox: 2 days)

Add `libghostty-spm`; write `GhosttyPane: SpaceDocument` alongside — **not instead of** —
`TerminalPane`; add a config field selecting the default document kind. Then run both side by side
on real `agent-afk` work and answer with hands rather than theory:

- Does narrowing with scrollback corrupt history? (SwiftTerm: expected eventually. Ghostty: expected no.)
- Does burst agent output feel better?
- Do ligatures, IME, and selection behave?
- What did AppKit integration actually cost?

**Kill criterion:** no working shell rendering in `GhosttyPane` within 2 days ⇒ libghostty is
rejected on evidence, and the fallback is §6 option B+C on SwiftTerm.

### Step 2 — decide, then delete the loser

Remove whichever conformer loses. Keeping both permanently is the failure mode.

### Refuse regardless

Warp-style command blocks (terax's `terminal/block/`, 19 files, reimplements the shell's own line
editor and exists largely so an AI can address command regions — it fights the premise that
afk's REPL owns the prompt), renderer pools (a browser-WebGL-scarcity artifact; also the source of
terax's arbitrary `MAX_PANES_PER_TAB = 4`), a 55-field preferences window (~35 of terax's fields are
AI/model/STT config), theme editors, 1300 lines of file-icon tables (Finder icons are one line),
LSP, and destructive git operations in a GUI.

---

## 6. Alternatives considered

All three critics returned `strength: strong`, so this matrix is recorded rather than resolved; §5
sidesteps it by making the choice empirical.

| # | Option | Cost | Risk | Why not chosen outright |
|---|--------|------|------|-------------------------|
| A | Fork SwiftTerm now: apply the `_yBase` fix, port the unmerged `reflowV2`, build a harness | weeks | **high** | Core buffer surgery in a repo with zero tests and an untracked dependency. `reflowV2` *consumes* the very `isWrapped` metadata the confirmed bug corrupts, so porting it onto corrupt input amplifies mangling. Buys correctness that cannot be verified, on a core the field has left. Still viable *after* Step 0 makes the patch recoverable. |
| B | Refuse to reflow: clamp/pin columns on narrow | hours | low | #494 stops existing by construction. Genuinely un-beautiful for heavy resizers, which cuts against the stated bar — but it is the cheapest correct answer and remains the fallback. |
| C | Pin + canary, ship no buffer fix | ~1 day | lowest | Folded into Step 0 item 1. The canary half (a `UMBER_DIAG` buffer-diff across resize) is deferred until a reflow decision is actually needed. |
| D | Swap to libghostty | 1–2 weeks | medium | Erases #494, single-threaded IO, absent ligatures, Metal-off-by-default, the ~3,500-line `Buffer.resize` cliff, *and* the untracked-patch hole. Costs the auditable-vendor convention and accepts a pre-stable ABI. Not chosen blind — Step 1 tests it. |
| E | Delete the competitive frame; optimise for daily-driver joy | zero | zero | Partially adopted: §4 discards "compete with terax-ai" and "best terminal" as goals. Rejected as a *complete* answer only because the vertical-integration position in §4.2 is real and worth pursuing. |

Also rejected: replacing the Spaces-as-native-window-tabs level with custom chrome. Verified as a
genuine differentiator — nearly every competitor hand-rolls SwiftUI chrome and forfeits
drag-out-to-detach, Merge All Windows, the tab overview, and the accessibility that comes free with
real `NSWindow` tabs.

## 6.1 Flip-condition check on D — run 2026-07-27, after choosing D

§6 named two capabilities that, if libghostty could not deliver them, would reopen the A/D
trade: **scrollback search** (just shipped on SwiftTerm in under 3 hours, `114e9f8`) and the
**image protocols** (SwiftTerm verifiably ships sixel + kitty graphics + iTerm2 inline).
Checked both. Result: **D survives, but search stops being free.**

**Search — engine yes, UI no, wrapper no.** `include/ghostty.h` exposes 90 `GHOSTTY_API`
functions and **not one of them initiates or drives a search.** What exists is the opposite
direction — outbound *actions* libghostty emits to the host:

```c
// apprt.action.StartSearch.C
typedef struct { const char* needle; }  ghostty_action_start_search_s;
typedef struct { ssize_t total; }       ghostty_action_search_total_s;
typedef struct { ssize_t selected; }    ghostty_action_search_selected_s;
```
plus `GHOSTTY_ACTION_START_SEARCH` / `_END_SEARCH` / `_SEARCH_TOTAL` / `_SEARCH_SELECTED`.

Contrast selection, which *does* have callable entry points (`ghostty_surface_has_selection`,
`ghostty_surface_read_selection`, `ghostty_surface_read_text`). So the matching engine lives
inside libghostty and is driven by its own keybinding layer; the embedder is told the match
total and selected index so it can render its own find bar. The escape hatch for triggering
it is `performBindingAction(_:)` (GhosttyKit README). Net: search is **reachable but
unbuilt** — a day or two of find-bar UI consuming the action stream, not 3 hours of menu
plumbing, and not "implement scrollback matching from scratch" either.

Worse in the short term: GhosttyKit's *documented* API surface
(`lakr233.github.io/libghostty-spm/api/terminal.html`) contains **no search of any kind** —
no method, no delegate — across `TerminalViewState`, `TerminalSurfaceView`, `TerminalView`,
`TerminalController`, `InMemoryTerminalSession`. So today the action stream would have to be
reached below the wrapper, or the wrapper extended upstream.

**Images: not checked, and lower risk.** Sixel/kitty graphics are renderer-internal rather
than API surface, so they plausibly "just render" without an embedder-visible entry point —
but that is an inference, not a verified fact. Flagged as open.

**The offsetting find, which is larger than the loss.** `TerminalViewState` already publishes:

```swift
@Published public internal(set) var workingDirectory: String? { get }
@Published public internal(set) var lastCommandExitCode: Int? { get }
@Published public internal(set) var lastCommandDurationNanos: UInt64? { get }
```

That is OSC 7 **and** OSC 133 command telemetry, already parsed and surfaced as observable
state. On SwiftTerm those were costed at ~1 day (OSC 7) + ~3 days (OSC 133) in the discarded
ordering, and `TerminalPane.hostCurrentDirectoryUpdate` is still an empty stub. It is also
precisely the substrate the Observer panel needs — i.e. the differentiator identified in §4.2
arrives closer to free on this foundation than on SwiftTerm.

**Revised trade:** give up a 3-hour ⌘F win and owe a day or two of find-bar UI; get ~4 days of
shell integration, command telemetry as first-class state, and the four SwiftTerm ceilings
(reflow, threading, ligatures, GPU) gone. Still clearly favourable. **Decision stands: D.**

**Consequence for Step 1.** The spike gains a task and an ordering change: before wrapping
anything as a `SpaceDocument`, confirm (a) a login shell renders, and (b) `performBindingAction`
can start a search and the action stream reports totals. If (b) fails, search must be rebuilt
on `ghostty_surface_read_text` with no incremental highlighting — which is the one outcome that
would make the trade genuinely close, and is worth knowing on day one rather than day two.

## 6.2 Step 1 spike results — 2026-07-27, branch `afk/libghostty-spike`

Spike target `GhosttySpike` (that branch only; Umber's sources untouched), commit `123919f`.
`libghostty-spm` resolved to **1.3.2**, a 51.8 MB prebuilt XCFramework, in 18 s, pulling two
unexpected transitive dependencies: `msdisplaylink` 2.1.0 and `swift-argument-parser` 1.8.2.

**Q3 — PTY cost: DISSOLVED, and my earlier claim was wrong.** `TerminalSessionBackend` has
exactly two cases, `.exec` and `.inMemory`, and **`.exec` is the default**: libghostty spawns
the child process itself and honours `workingDirectory` and `envVars`. The claim that Umber
would have to own `forkpty` came from the README's examples, which use `.inMemory` because the
sample app is sandboxed. Cost is zero, not a day.

**Q1 — does a login shell render in AppKit: PASS, first build.** No PTY code. And shell
integration is live with `configSource: .none` and no rc changes — actual transcript:

```
[spike] Q1: surface configured, backend=.exec (libghostty spawns the shell)
[spike] OSC 7 pwd -> /Users/griffinlong/…/.afk-worktrees/libghostty-spike/app
[spike] title -> griffinlong@Griffins-MacBook-Pro:~/Projects/…/app
[spike] title -> …/.afk-worktrees/libghostty-spike/app      <- libghostty abbreviates paths itself
```

**Q2 — can an embedder start a search: FAIL.** All eight candidate spellings rejected by
`performBindingAction`; two controls accepted:

```
control  scroll_to_top      -> true        search  toggle_search   -> false
control  jump_to_prompt:-1  -> true        search  search          -> false
control  copy_to_clipboard  -> false       search  open_search     -> false
                                           search  show_search     -> false
   (+ find, toggle_find, search_forward, start_search — all false)
```

Consistent with §6.1's ABI reading. **Caveat against overclaiming:** `false` can also mean
"known action declined" — `copy_to_clipboard` returned false with no selection — so this is
strong but not airtight proof that no search action exists under some unguessed name. Either
way it is not drivable from an embedder today, and Ghostty's search UI plausibly lives in its
own apprt (Swift app) layer rather than in libghostty.

**Q4 — prompt navigation: PASS.** `jumpToPrompt(by: -1)` and `scrollToRow(0)` both returned
true. So OSC 133 prompt navigation works even though search does not.

**Bonus finding — the delegate surface covers much of "Not Built Yet."**
`TerminalSurfacePwdDelegate` (OSC 7), `TerminalSurfaceCommandFinishedDelegate`
(`exitCode` + `durationNanos`, OSC 133), `TerminalSurfaceHoverLinkDelegate` and
`TerminalSurfaceOpenURLDelegate` (URL clicking), `TerminalSurfaceScrollbarDelegate`
(`total`/`offset` — which also retires the ~3,500-line scrollbar-thumb risk in §7),
`TerminalSurfaceProgressReportDelegate`, `TerminalSurfaceBellDelegate`,
`TerminalSurfaceDesktopNotificationDelegate`. Also `AppTerminalView` is `open` **and already
overrides `performKeyEquivalent`**, so `MacLineEditing`'s ⌘-chord table survives the swap by
subclassing exactly as `UmberTerminalView` does today.

### Verdict: proceed with D. The trade is now measured rather than estimated.

| | |
|---|---|
| **Gained, verified by running** | OSC 7 pwd · OSC 133 command boundaries + prompt jumping · title abbreviation · Metal · CoreText shaping (ligatures) · threaded IO · no #494 · hover-link / open-URL / scrollbar / progress / bell / notification delegates · 485 themes |
| **Lost, confirmed** | ⌘F scrollback search — must be rebuilt on `ghostty_surface_read_text`, without incremental highlighting. Estimate 2–4 days for a find bar with match navigation, versus the 1–3 hours SwiftTerm's ready-made bar cost in `114e9f8`. |
| **New costs** | 51.8 MB opaque binary + 2 unexpected transitive deps · pre-stable ABI (pinned) · the auditable-vendor convention dies |

This is precisely the outcome §6.1 called "the one outcome that makes the trade close," so it
deserves a plain statement rather than a shrug: **it is close on search alone, and not close
overall.** Rebuilding a find bar is bounded, self-contained work with no upstream dependency.
SwiftTerm's four ceilings are unbounded and require becoming a terminal-engine maintainer,
which contradicts plan §4.2's own founding principle.

### Next, in order

1. Wrap as `GhosttyPane: SpaceDocument` alongside `TerminalPane` (the seam's four methods).
2. Subclass `AppTerminalView` for `MacLineEditing`, mirroring `UmberTerminalView`.
3. Daily-drive both side by side; confirm narrowing-with-scrollback no longer corrupts.
4. Build the find bar on `read_text` — the one real debt this decision takes on.
5. Only then delete `TerminalPane`, `vendor/SwiftTerm`, the pin, and the patch.

## 7. Risks this plan accepts

1. **The probe may cost two days and return nothing.** Bounded by the kill criterion.
2. **libghostty's ABI is pre-stable and its embedding API is undocumented outside Zig source.**
   ~~Mitigated by the version pin; upgrades become deliberate.~~ **Corrected 2026-07-27 (§8.1) —
   there is no pin.** The spike manifest says `from: "1.2.0"`, which permits any `>=1.2.0 <2.0.0`,
   so a stray `swift package update` can move the pre-stable ABI silently. `Package.resolved`
   happens to record 1.3.2, but a resolved file is a lockfile, not a declared constraint, and it is
   the manifest that governs re-resolution. The mitigation becomes real only when production
   declares `.exact("1.3.2")`. Until then this risk is **unmitigated**, not mitigated.
3. **An XCFramework is not auditable text.** A real convention loss with no mitigation; if adopted,
   the convention in `AFK.md` must be amended honestly rather than quietly.
4. **#494 remains unfixed if SwiftTerm wins the probe.** Step 0 item 2 at least stops the plan from
   claiming otherwise; option B is the cheap escape.
5. **G6 (the multi-hour soak) is untouched by any of this** and still retires only through real use.
6. `.afk/plans/native-swift-terminal-afk-host.md` still carries three absolute `/Users/griffinlong`
   paths (one naming an unrelated fork). Unchanged here, still blocking on any
   `gh repo edit --visibility public`.

---

## 8. Step 1 plan — verified seam map, and three things §6.2 got wrong

Written 2026-07-27 after `/ground-state` + two research agents (seam map, spike API recovery) +
`/shadow-verify` with 4 independent verifiers, each given the bare claim with all citations
stripped. All four returned `CONFIRMED` on `evidence_base: independent-rederivation`. The
verifiers also found three things the first pass missed; those are §8.1–§8.3, and two of them
change the work.

### 8.1 There is no version pin — §7 risk 2 was unsupported

Corrected in place at §7. `app/Package.swift:24` (spike worktree) declares
`.package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.2.0")` — a floating
minimum admitting all of `>=1.2.0 <2.0.0`. `app/Package.resolved:9-10` records `1.3.2` @
`b146b73a8ba3ed2678a22a9de5feecfcbf298d48`. A lockfile is not a constraint. **Production must
declare `.exact("1.3.2")`** — on a pre-stable ABI consumed as an opaque 127 MB binary, floating
minor upgrades are the one thing the vendor-integrity work in `f1e59a8` existed to prevent, and it
would be incoherent to hash-pin SwiftTerm's source while letting its replacement float.

### 8.2 "The seam's four methods" understates Step 1 by about 4×

`SpaceDocument` is genuinely clean — 4 requirements (`documentView: NSView`, `documentTitle: String`,
`documentSymbolName: String`, `func documentDidBecomeActive()`, at `SpaceDocument.swift:97/99/103/107`),
declared in a file that imports only AppKit, with no SwiftTerm type anywhere in it. Conforming
`GhosttyPane` really is trivial.

**But conforming is not integrating.** Every app-wide behaviour is routed through *concrete*
`TerminalPane` types, and two `as?` casts are the whole reason a second conformer would be
silently inert rather than loudly broken:

| Path | Filter that excludes a second conformer | Verified consequence |
|---|---|---|
| Font zoom / ⌘0 reset | ~~`SpaceViewController.swift:95`~~ — **resolved before this table was acted on**: the zoom fan-out iterates `[SpaceDocument]` at `AppDelegate.swift:236-238`, per `libghostty-swap-sequencing-2026-07-28.md` §2 | ⌘+/⌘−/⌘0 silently no-op on a `GhosttyPane` |
| Live config reload (⌘R) | ~~same cast at `:95`~~ — **also resolved**: `SpaceViewController.apply(config:)` (`:296-301`) iterates `documents`, i.e. `[SpaceDocument]` | theme/font/scrollback changes never reach it |
| File-tree activate → inject text | ~~`SpaceViewController.swift:98` `activeTerminalPane`, then `:211-214`~~ — **resolved 2026-07-29 (Phase 1)**: the cast is now `ShellHosting`-typed (`ShellHosting.swift:114`) and the call site goes through `send(text:)`, not SwiftTerm's `view.send(txt:)` (`SpaceViewController+Delegates.swift:98,109`) | clicking a file in the sidebar does nothing |

Two further sites the spike write-up missed entirely:

- **No polymorphic factory.** ~~`SpaceViewController.addTerminalDocument()` (`:102-109`)~~
  **Resolved 2026-07-29 (Phase 1).** `addTerminalDocument` (`SpaceViewController.swift:129`) still
  hardcodes `TerminalPane(config:frame:workingDirectory:)` and returns the concrete type — it is the
  ⌘T path, and "a terminal rooted at this Space" is a policy worth keeping — but it now calls through
  a polymorphic `add(document:beforeActivating:)` (`:173`) that takes any `SpaceDocument`. A second
  kind is handed in, not wired in.
- **The delegate cannot carry it.** ~~`TerminalPaneDelegate` (`TerminalPane.swift:10-15`)~~
  **Resolved 2026-07-29 (Phase 1).** Widened to `SpaceDocumentDelegate` and moved beside the document
  protocol (`SpaceDocument.swift:181-194`); all three callbacks now take `SpaceDocument`, implemented
  at `SpaceViewController+Delegates.swift:50-72`. The delegate is wired on any
  `SpaceDocumentReporting` conformer (`SpaceDocument.swift:214-220`) rather than by a concrete cast,
  so a `GhosttyPane` is routed by the same line that routes `TerminalPane`. This was load-bearing:
  title changes drive the document strip and the window subtitle.

**Consequence for ordering:** the honest Step 1 is *regenericize the container first, then add the
conformer* — otherwise `GhosttyPane` renders in a strip that never retitles it, ignores ⌘R, and
ignores zoom, which is indistinguishable from "libghostty is broken" during the side-by-side
daily-drive that Step 3 depends on for signal.

### 8.3 The keymap survives — but a new collision surface arrives with it

Confirmed structurally: `AppTerminalView` is `open class AppTerminalView: NSView`
(`.build/checkouts/libghostty-spm/Sources/GhosttyTerminal/Platform/AppKit/AppTerminalView.swift:13`)
and already overrides `performKeyEquivalent` (`AppTerminalView+Input.swift:17`). So the
`UmberTerminalView` pattern ports directly, and the reason it existed under SwiftTerm — `keyDown`
being `public` not `open` — does not even apply here.

The part §6.2 did not know: **that parent override never calls `super`**, and it consumes any event
libghostty's own binding table claims —

```swift
if keyIsBinding(event, on: surface) { keyDown(with: event); return true }   // +Input.swift:22-25
```

where `keyIsBinding` bottoms out in `ghostty_surface_key_is_binding` (`:291`), a C call into the
Zig core. **The contents of that binding table are not visible from Swift source**, so whether any
of Umber's ⌘-chords collide with a libghostty default is *not statically knowable* — it is a
runtime question. Two consequences:

1. `GhosttyTerminalView` must check `MacLineEditing.controlBytes` **first** and call
   `super.performKeyEquivalent` only as fallback — exactly the ordering `UmberTerminalView.swift:32-53`
   already uses. Overriding without `super` would silently delete libghostty's entire binding
   pipeline (⌃-Return, ⌃-/, the two-pass command-key translation at `+Input.swift:43-84`).
2. Add a **chord-collision check** to Step 1's exit criteria: run the 17 cases from
   `check-keybindings.sh` against a live `GhosttyPane` and confirm the bytes that reach the pty are
   identical. `check-keybindings.sh` itself stays valid — it compiles `KeyBindings.swift` headlessly
   and that file is engine-free — but it proves the *table*, not the *delivery*, and delivery is
   precisely what changed.

### 8.4 Revised Step 1, in order

Ordering differs from §6.2 in one way that matters: 0 comes before 1.

0. **Regenericize the container** — **DONE 2026-07-29**, as Phase 1 of
   `libghostty-swap-sequencing-2026-07-28.md` §2 (no libghostty yet, `TerminalPane` still the only
   conformer, so this was provably behaviour-preserving and verifiable by `check-keybindings.sh` +
   `check-file-size.sh` + `make-app-bundle.sh` alone): widened `TerminalPaneDelegate` to a
   `SpaceDocument`-typed `SpaceDocumentDelegate` and moved it to `SpaceDocument.swift:181`; added a
   polymorphic `add(document:beforeActivating:)` beside `addTerminalDocument()`
   (`SpaceViewController.swift:173`). One correction to the prescription above: the font-sizing and
   `apply(config:)` fan-outs needed **nothing** — they were already `[SpaceDocument]` (see the §8.2
   table). And send-text was added to a **sibling protocol, not `SpaceDocument`** — `ShellHosting`,
   one member, `send(text:)` (`ShellHosting.swift:53`). Putting it on `SpaceDocument` would have been
   wrong, not merely broad: `FileViewerPane` conforms to `SpaceDocument`, so it would have let the
   file tree inject a path into an editor buffer. Hence "replace the two `as?` casts" was also only
   half right — the zoom/config cast was already gone, and the `focusedTerminalPane` cast was
   **narrowed** to `ShellHosting`, never widened.
1. Add the dependency at `.exact("1.3.2")` (§8.1) and amend the auditable-vendor convention in
   `AFK.md` honestly, per §7 risk 3 — the convention dies here, and it should die in writing.
2. `GhosttyPane: SpaceDocument` + `GhosttyTerminalView: AppTerminalView`, `super`-fallback ordering
   per §8.3. Config surface known-unexercised by the spike: font size, theme, scrollback limit,
   `envVars`, selection/copy-paste, resize beyond initial `fitToSize()`.
3. Wire the delegates the spike proved live: `TerminalSurfacePwdDelegate` (OSC 7),
   `TerminalSurfaceCommandFinishedDelegate` (OSC 133 `exitCode` + `durationNanos`),
   `TerminalSurfaceTitleDelegate`, `TerminalSurfaceCloseDelegate` → the new document delegate.
4. Gate on: 17-case chord parity (§8.3), ⌘R/zoom/file-tree reaching a `GhosttyPane`, and the
   narrowing-with-scrollback test that SwiftTerm fails (`Buffer.swift:1171`/`:1211`) passing.
5. Then §6.2's steps 3–5 unchanged: daily-drive both, build the find bar on
   `ghostty_surface_read_text`, and only then delete `TerminalPane`, `vendor/SwiftTerm`, the pin,
   and the patch.

**Do not copy from the spike:** the `asyncAfter(deadline: .now() + 2.5)` shell-readiness guess
(`main.swift:78-81`), stderr-only logging (`:35-41`), and the 8-string blind search probe (`:90-93`).
