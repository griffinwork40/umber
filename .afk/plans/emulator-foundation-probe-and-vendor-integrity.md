# Emulator foundation: pin the vendor, correct the record, probe libghostty

**Status (2026-07-27):** Step 0 in progress · Step 1 (probe) not started · supersedes nothing;
**amends** `native-swift-terminal-afk-host.md` §9 risk 1, §11 G2, and §12's Step 3/4 ordering.

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

## 7. Risks this plan accepts

1. **The probe may cost two days and return nothing.** Bounded by the kill criterion.
2. **libghostty's ABI is pre-stable and its embedding API is undocumented outside Zig source.**
   Mitigated by the version pin; upgrades become deliberate.
3. **An XCFramework is not auditable text.** A real convention loss with no mitigation; if adopted,
   the convention in `AFK.md` must be amended honestly rather than quietly.
4. **#494 remains unfixed if SwiftTerm wins the probe.** Step 0 item 2 at least stops the plan from
   claiming otherwise; option B is the cheap escape.
5. **G6 (the multi-hour soak) is untouched by any of this** and still retires only through real use.
6. `.afk/plans/native-swift-terminal-afk-host.md` still carries three absolute `/Users/griffinlong`
   paths (one naming an unrelated fork). Unchanged here, still blocking on any
   `gh repo edit --visibility public`.
