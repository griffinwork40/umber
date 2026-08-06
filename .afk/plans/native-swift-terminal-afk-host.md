# Native Swift macOS terminal that hosts agent-afk

**Status (2026-07-27):** approved · Step 0 GREEN (§11, G6 carried as a standing risk) · Step 1 items 1–3
done (item 3 in review, PR #718) · Step 2 v0.1 DONE and daily-driveable · **Step 3 is the next
substantive commitment and is the least-specified section in this document** · Step 4 still optional.
The app was renamed **MacTerminal → Umber** on 2026-07-27 (`faf1291`); repo is now `griffinwork40/umber`.
**Created:** 2026-07-26
**Owner:** Griffin Long
**Repo:** this one (then named `mac-terminal`; new, empty at plan time)

---

## 1. Goal (operator's own words)

> "i think terax is a cool idea but tbh i think native swift would be even cooler (macos) and without
> all the ai stuff (just editor/terminal/ide-esque vibes) with git?"
>
> "ya i'd be building for myself. its gotta be beautiful, and user-friendly as hell. i'd be running
> agent-afk in it and maybe at somepoint making it a native feature who knows"

Constraints extracted:

- **Native Swift / macOS.** Not Electron, not Tauri, not a webview.
- **No AI features in the app.** The app makes zero model calls and has no chat UI of its own. It is a
  *host* for an agent, and a *window onto* one. That boundary is the product.
- **For himself.** Not a product; no stars to chase. But the bar is "beautiful, user-friendly as hell."
- **Must host `agent-afk`'s interactive REPL correctly.** ~~This is the load-bearing requirement and the
  reason the project is technically non-trivial.~~ **CORRECTED 2026-07-27 — see §12.** This is the
  load-bearing *technical* requirement, but it is **not the product goal**, and this document treated it
  as both. Read the first quote again: *editor / git lead the sentence.* "i'd be running agent-afk in it"
  is the second quote and is a *usage* statement. §3 inverted them — promoting "host afk" to the thesis
  and demoting editor/git to Step 4 "explicitly optional."
- **Terminal-first IDE is the product shape** (operator, 2026-07-27: *"the goal was to make a better
  terax lol like ide/esque terminal-first"*). Not a terminal that happens to host an agent. "Better
  terax" minus the AI layer — terminal as the primary object, with editor / file tree / git attached.
- **Optional, later:** make agent-afk a *native* feature rather than a CLI in a pane.

## 2. Prior art / what this is reacting to

`crynta/terax-ai` — 8,669 stars, 931 forks, 364 open issues, created 2026-04-21, last push 2026-07-25.
"Lightweight (7MB) Terminal-first AI-native dev workspace." Tauri 2 + Rust (`portable-pty`) + React 19 +
xterm.js (WebGL) + CodeMirror 6 + Vercel AI SDK v6. Apache-2.0. Site terax.app.
Operator has a local fork of it (`upstream=crynta/terax-ai`).

Two observations that shaped this plan:

1. Terax's identity is "7MB lightweight" and it is *still* a webview app shipping React + xterm.js. A
   native AppKit app with a real text renderer beats it on size and latency without trying. The
   "native would be cooler" instinct is technically sound, not just aesthetic.
2. Terax's 364 open issues and its forks cluster around the **AI layer** (localization, BYOK proxying,
   model plumbing). Deleting AI from the app doesn't just simplify the product, it deletes the surface
   that generates most of the maintenance load.

Counterpoint held honestly: 8.7k stars in 3 months is *the AI layer acting as distribution*. A no-AI
native Mac editor/terminal/git app competes with Nova, Zed, CodeEdit and Xcode on craft alone with no
novelty hook. Fine to build for yourself; hard to build for an audience. Operator confirmed: for himself.

## 3. The reframe that drives the plan

Editor + terminal + git in native Swift is **already solved and MIT-licensed**:
[CodeEdit](https://github.com/CodeEditApp/CodeEdit) (~23k stars, Swift/AppKit) is literally
SwiftTerm + CodeEditSourceEditor + tree-sitter + git. Building those three from scratch is not where
the value is.

What does *not* exist is a **native Mac app whose primary object is an agent-afk session**. afk already
runs sessions across CLI / daemon / Telegram that outlive any one terminal window, and already writes a
machine-readable substrate to disk. Nobody has built native UI on that.

> **PARTIALLY RETRACTED 2026-07-27 (§12).** The reframe above rests on a *novelty* premise — "building
> the solved three isn't where the value is; nobody has built the afk-native thing." Novelty only counts
> if differentiation counts, and §2 already recorded **"Operator confirmed: for himself."** For an
> audience of one, "nobody has built it" is not a reason to build it, and "CodeEdit already solved it"
> is not a reason to skip it — CodeEdit was *rejected as a base* (§4.3), so its existence removes
> nothing. The afk-observer thesis stays a good idea; it was never the operator's stated goal, and
> promoting it over editor/git was unforced. Step 3 vs Step 4 ordering is **reopened** — see §12.

**However** — see §7 Wave 3.5 — that substrate is not currently fit to build on, and fixing it is a
change to *afk*, which the operator owns. That discovery is the single most important output of the
planning session and it reordered the whole plan.

## 4. Verified technical evidence

All of the following was re-derived during planning, not assumed. Citations are to real files/issues.

### 4.1 What afk's REPL demands of a terminal

afk's REPL is a **custom raw-ANSI compositor** — not Ink, not blessed, not readline.
`src/cli/terminal-compositor.ts` + `src/cli/cup-frame-renderer.ts`, which self-describes:
"positions every line with absolute CUP escapes... no `\n` is ever emitted"
(`cup-frame-renderer.ts:6-8`).

| Feature | Status | Evidence |
|---|---|---|
| DECSTBM scroll regions | **REQUIRED** (core scrollback mechanism) | `status-line.ts:275-298`, `docs/scrollback.md:22-69` |
| Cursor save/restore | REQUIRED | `status-line.ts:112,114,168,262,310` |
| Raw mode | REQUIRED | `terminal-compositor.lifecycle.ts:158`, `input/raw-mode.ts:40` |
| Shift+Tab → permission-mode ring | REQUIRED, plain xterm (CSI Z) | `terminal-compositor.input-dispatch.ts:1109` → `permission-mode-cycle.ts:41` |
| Ctrl+B → background turn | REQUIRED, plain ctrl-byte | `input-dispatch.ts:1074` |
| Bracketed paste | REQUIRED (enables `?2004h`, parses `200~`/`201~`) | `input/raw-mode.ts:17`, `input-dispatch.ts:258,268` |
| SIGWINCH / resize | REQUIRED | `terminal-size.ts:14,20,81` |
| Unicode width + grapheme clustering | REQUIRED (`string-width` + `Intl.Segmenter`) | `display.ts:21` |
| Cursor show/hide | REQUIRED | `cup-frame-renderer.ts:59-60` |
| Alternate screen buffer | **NOT USED** | zero hits in `src/cli` |
| Mouse / SGR tracking | **NOT USED** | zero hits for `1000h/1002h/1006h` |
| Inline images | **NOT USED** — actively stripped as a security boundary | `utils/terminal-sanitize.ts:33` |
| kitty keyboard protocol | OPTIONAL, never enabled | no `CSI>1u` enable sequence anywhere |
| Truecolor, OSC 8, OSC 52, OSC 2/9, sync output 2026 | OPTIONAL, degrade gracefully | `mascot.ts:10-14`, `hyperlink.ts:48-94`, `clipboard.ts:116-130` |

The REPL itself is plain stdio (`node-pty` is test-only). The *terminal* still allocates a PTY for the
shell; afk just runs inside it.

**Minimum viable VT surface:** raw-mode byte delivery; plain xterm key sequences; bracketed paste;
DECSTBM with correct LF-at-margin scroll semantics (**the hardest piece**); CUP + save/restore +
show/hide; SIGWINCH; and `string-width`-compatible Unicode width.

### 4.2 SwiftTerm assessment

MIT, v1.15.0 released 2026-07-19, pushed 2026-07-26, ~1.6k stars, used in CodeEdit / La Terminal /
Secure Shellfish. Library product `SwiftTerm` (`Package.swift:28-29`).

Confirmed present by direct source read:

- **DECSTBM implemented deeply** — `Terminal.swift:1022` (`case "r"`), `:1631`, `:2495-2540`
  (scroll-region refresh with blitting), margin mode.
- **Synchronized output (mode 2026)** — `Terminal.swift:4460`, with a 1s timeout guard at `:343`.
- **Bracketed paste genuinely works at the view layer** — `Mac/MacTerminalView.swift:1543-1592`
  wraps pasted text in `EscapeSequences.bracketedPasteStart/End` when the app enables mode 2004.
  NOTE: the `// TODO: must implement bracketed paste mode` at `Terminal.swift:4458` is **stale and
  misleading** — it sits at the core's mode-set site only. Verifying this retired a risk rather than
  confirming one.
- Blessed embedding API (per official `Documentation.docc/GettingStarted.md`):
  `LocalProcessTerminalView(frame:)` + `.processDelegate` + `.startProcess(executable:args:environment:)`,
  delegate `LocalProcessTerminalViewDelegate` (`sizeChanged`, `setTerminalTitle`,
  `hostCurrentDirectoryUpdate`, `processTerminated`). Defaults to `/bin/bash`.
  Core is `LocalProcess` with `startProcess(...)` at `LocalProcess.swift:383`.
- Optional Metal renderer exists — `Apple/Metal/MetalTerminalRenderer.swift`.
- Headless usage is documented — `Documentation.docc/HeadlessUsage.md`.

**Open risks:**

- **Issue #494 "Buffer reflow produces duplicate/orphan lines when narrowing terminal" — OPEN.**
  Created 2026-03-20, 9 comments, untouched since 2026-03-29. Hits exactly the code path afk exercises
  (compositor + resize). This is the single biggest technical threat to the project.
- ~~**Shift+Tab is routed through `sendKittyFunctionalKey(.tab, modifiers: [.shift])`**
  (`Mac/MacTerminalView.swift:1439-1442`). afk never enables the kitty keyboard protocol, and no
  `\x1b[Z` fallback was located. The permission-mode ring may silently do nothing.~~
  **REFUTED 2026-07-26 during Step 0 — see §11.** There IS a plain-xterm fallback. The original
  grep missed it because AppKit routes Shift+Tab to `insertBacktab(_:)` (lowercase `t`), not
  `insertTab` + shift modifier.
- **Bus factor:** single primary maintainer; was unreachable mid-thread on an open scrolling-corruption
  bug ("traveling and on vacation").
- Issue #486 (scroll/content desync under async feeds) was claimed open by a critic but is
  **CLOSED / completed**, updated 2026-07-10. Claim refuted.

### 4.3 Editor / git / prior art

| Component | Verdict |
|---|---|
| CodeEditTextView + CodeEditSourceEditor (MIT) | Take off the shelf if/when an editor is built. But CodeEditSourceEditor's own README says "not ready for production use." |
| STTextView | Stronger engine, but **GPLv3-or-paid-commercial**. Fine personally, a license trap on any future distribution. Rejected. |
| Runestone | **iOS-only** as shipped. Out. |
| SwiftTreeSitter | Active, now under the official `tree-sitter` org. Fine. |
| SwiftGit2 | **Stale** (last push 2025-11-24), fragmented into ≥3 partial forks. libgit2 disclaims maintaining bindings. **Shell out to `git` via `Process` instead.** |
| CodeEdit as a fork base | **Rejected.** PR #2182 "Add native GitHub Copilot inline completions" is open (draft, 2026-06-30) with 7 open AI/Copilot PRs; README.md:31 still says "not yet recommended for production use" after 4+ years; spans 6 loosely-coordinated repos. Forking a deliberately no-AI app off a codebase drifting into AI means rejecting upstream's roadmap forever. **Read it, don't fork it.** Also note it pins a *stale* SwiftTerm fork (`thecoolwinter/SwiftTerm`, last push 2025-07-17) — use upstream. |
| Nova (Panic) | Native AppKit/Swift, custom text engine, tree-sitter, SourceKit-LSP. Proves a small team can ship this beautifully — and that custom text engines still choke on pathological files. |
| Zed | Rust + GPUI, not Swift. The non-native alternative. |
| Ghostty / libghostty | **Rejected for embedding.** Official docs: the surface/render API is "not yet general-purpose... only consumer is the macOS app... expect breaking changes." Only the `libghostty-vt` parser slice is usable and signatures are in flux; you'd write the renderer yourself. |
| Rust `alacritty_terminal` via FFI | Rejected — no payoff over SwiftTerm, adds an FFI boundary. |
| Hand-rolled VT engine | Rejected — reflow-on-resize has no formal spec, `wcwidth` is broken for modern grapheme clusters, DEC-mode support is unqueryable in practice. Multi-year trap, and afk leans on precisely the hardest parts. |

### 4.4 agent-afk integration surfaces

| Surface | Exposes | Swift-usable | Evidence |
|---|---|---|---|
| `afk chat --format stream-json` | NDJSON `OutputEvent` stream | **Easy** | `chat.ts:792-830`, `docs/headless.md`, schema `agent/types/session-types.ts:90-136` |
| Session ledger JSONL | Tailable cross-process event feed | Easy (with caveats, §7) | `agent/session-ledger.ts:1-90` |
| Presence files | Live pid / cwd / model / AFK-mode | Easy (with caveats, §7) | `agent/awareness/presence.ts:34-60` |
| `--format json` (status/config/doctor/...) | One-shot JSON | Easy | `status.ts:44` |
| Library import (`AgentSession`, `query`) | Full agent loop | **Medium** — Node object graph, needs an embedded/sidecar Node runtime, not FFI | `src/index.ts:7-109`, `docs/architecture.md:162-201` |
| Daemon HTTP `127.0.0.1:7777` | Cron-task CRUD **only** | Medium (narrow) | `agent/daemon.ts:129,213-313` |
| MCP | **Client only** — no server mode | Hard (would have to be built) | `agent/mcp/client.ts:38` |
| `interactive` REPL | ANSI TUI, raw-mode TTY, **no JSON** | Hard | `interactive.ts:184-234` |

Runtime: Node ≥22, `better-sqlite3` is a real native production dep. Headless-capable outside
`interactive`.

**Biggest blocker to true native embedding:** the rich interactive experience is welded to
Commander + `process.argv` + raw-mode TTY with no JSON or library equivalent, and `AgentSession` is a
Node object graph, not a Swift-callable library. So "native afk" realistically means
**subprocess + NDJSON**, not linking a library. The REPL keeps living in the terminal pane — which is
exactly why the terminal must be correct.

## 5. Chosen approach

Assemble, don't build. Native Swift shell around mature components:

- **Terminal:** SwiftTerm **upstream** (not CodeEdit's stale fork).
- **Editor (later, optional):** CodeEditTextView + CodeEditSourceEditor + SwiftTreeSitter.
- **Git:** shell out to the `git` binary via `Process`.
- **afk:** subprocess + NDJSON, plus reading on-disk state — *after* §6 Step 1 makes that state safe.

## 6. Steps

### Step 0 — Spike (half a day, throwaway) ← THE GATE

`git init` the repo; disposable `spike/` SwiftPM package, kept separate so it's cheap to delete.

- `Package.swift`: `.macOS(.v14)`, dep `https://github.com/migueldeicaza/SwiftTerm.git` from `1.15.0`.
- GUI executable: bootstrap `NSApplication` programmatically (`.setActivationPolicy(.regular)`),
  one `NSWindow`, `LocalProcessTerminalView`, `startProcess(executable: <login shell>, args: ["-l"])`.
  Fallback if a bare SPM executable fights AppKit: a minimal Xcode app target.
- Headless test target: automate the gates that don't need human eyes (see deviation note below).

**Gates — each recorded pass/fail:**

| Gate | Test | Why |
|---|---|---|
| G1 | afk REPL paints; status line intact; no tearing | zero newlines, pure absolute CUP |
| **G2** | **narrow window mid-session with scrollback → no duplicate/orphan lines** | **SwiftTerm #494, open, 4 months stale** |
| ~~**G3**~~ | **Shift+Tab cycles the permission-mode ring** | ~~kitty-only routing at `MacTerminalView.swift:1439-42`~~ **RESOLVED PASS, §11** |
| G4 | Ctrl+B backgrounds a turn | plain ctrl-byte |
| G5 | multi-line paste doesn't premature-submit | bracketed paste, `:1543-92` |
| G6 | multi-hour soak + forced resizes + scrollback overflow, differential vs Ghostty/Terminal.app | intermittent corruption won't show in a smoke test |

**Decision rule, fixed in advance:**

- All pass → Step 1.
- G3 fails → patch a fork to emit `\x1b[Z` on Shift+Tab when kitty mode is off (small, local); re-test.
- **G2 fails structurally → the native-terminal premise is dead.** Pivot to observer-only; Step 1
  becomes the whole project.

*Deviation from the originally-approved GUI-only spike:* G2/G5 are better tested **headlessly**
(repeatable, CI-able, no human eyeballs) using SwiftTerm's documented headless mode, and G3 is best
resolved by **static source analysis** of the key-encoding fallback path. The GUI executable is still
built, for the human-judgment gates G1/G4/G6.

### Step 1 — agent-afk session-status contract (1-2 days TS, PUBLIC repo)

> **STATUS 2026-07-27 (rev 2): items 1, 2 and 3 all DONE — items 1–2 MERGED, item 3 IN REVIEW.**
> **Item 3 (blocked-on-human signal): PR https://github.com/griffinwork40/agent-afk/pull/718**,
> "feat(presence): emit a blocked-on-human marker while an elicitation waits", +558/-11 on
> `afk/blocked-on-human-signal` — `OPEN`, not draft, `mergeStateStatus: CLEAN`, but **no reviewer has
> looked yet** (`reviewDecision` empty). This was the gate on Step 3; merging it unblocks the panel.
> **PR: https://github.com/griffinwork40/agent-afk/pull/716** — **MERGED 2026-07-26T23:02Z**
> (was `MERGEABLE / CLEAN` when this entry was first written),
> +494/-4 across 4 files, 2 commits (`91bb3c3`, `e3727ff`), all CI green
> (macOS + Ubuntu suites, lint/build, real-PTY scrollback, docs).
> Branch `afk/session-status-contract` off `main` in
> the `agent-afk` checkout, pushed to `origin`
> (= public `griffinwork40/agent-afk`).
>
> **CI incident worth remembering:** the first run failed on macOS in an unrelated test —
> `bash.test.ts > [process-group kill] reaps descendant processes`, `expected +0 to be 1`. A re-run
> with zero code changes passed, so: transient pid-reuse flake, not a regression. But the first
> commit's test helper spawned and reaped three Node processes purely to obtain a known-dead pid,
> which churns pids in a suite containing a test that fails when a specific pid is recycled — so it
> raised that flake's odds, and exposed this file's own assertions to the mirror-image race.
> `e3727ff` replaced it with `unusedPid()`, which probes for an `ESRCH` pid and creates no process.
> The flaky assertion itself was left alone (out of scope) and documented in a PR comment: its
> comment claims the inverse false-positive "cannot occur because kill -0 is non-destructive," which
> is wrong — pid reuse is symmetric.
> New file `src/agent/process-liveness.ts`; edits to `src/agent/awareness/{presence.ts,index.ts}`
> plus 13 new tests in `presence.test.ts`. Verified: `npm run lint` clean, full suite
> 704 files / 13215 tests pass.
>
> Two design decisions worth carrying forward:
> - `schemaVersion`/`heartbeatAt` are stamped **inside `writePresenceFile`**, not at call sites —
>   two providers write presence today (anthropic-direct, openai-compatible) and a per-caller stamp
>   would silently miss a future third surface.
> - `readPresenceFiles()` **annotates** liveness but does **not filter**. The worktree sweep decides
>   whether a worktree is in use from these records, so a false `'dead'` would let it delete a
>   worktree out from under a running session. Filtering is opt-in via `readLivePresenceFiles()`,
>   which retains `'unknown'` and heartbeat-less records for the same reason. A test pins the
>   non-filtering invariant.
>
> Known partial: `touchPresenceHeartbeat()` exists and is tested but is **not yet wired to turn
> boundaries**, so `heartbeatAt` is currently only stamped at session start. The primary ghost-session
> fix (pid liveness) is fully effective regardless; the heartbeat is the secondary guard against pid
> recycling and needs a caller before it earns its keep.
>
> `worktree-sweep.ts` keeps its own private `kill(pid,0)` copy — it has unmerged work in flight on
> `afk/cleanup-agent-worktree`, so consolidating would conflict for no functional gain.

Worth doing whether or not any Swift ships: it fixes a real latent bug (ghost sessions look live
forever). Additive and backward-compatible.

1. **Liveness** — `src/agent/awareness/presence.ts`: `PresenceFileInfo` (:41-59) gains a heartbeat
   timestamp; `readPresenceFiles()` (:207-220) reconciles against `kill(pid, 0)`.
   `presence-lifecycle.ts:35-68` writes the heartbeat at turn boundaries — current cleanup at
   `:60-63` is best-effort `process.once('exit'|'SIGINT'|'SIGTERM')` and cannot survive SIGKILL/OOM.
2. **Versioned contract** — `src/agent/session-ledger.ts`: promote `v` (:38, :287-299) from an internal
   malformed-line discard guard to a declared, documented schema version so external readers fail soft.
3. **Blocked-on-human signal** — emit on *every* blocking elicitation, not only when `/afk on` and
   ≥1 turn has completed (today gated at `src/cli/afk-mode-toggle.ts:70-116`). This is the one event
   worth a native notification and it currently has no on-disk trace in the common case.
4. Tests mirroring `src/telegram/presence-surface.test.ts:1-23` — that test exists *because this exact
   format silently broke `/watch`.*

Lands in **public `agent-afk`** (clean open-source core, per repo topology).

### Step 2 — Thin terminal app

> **STATUS 2026-07-26: v0.1 DONE.** Commit `988089e` in this repo. Lives in `app/` — see
> `app/README.md`. Built and verified: `swift build` clean, `app/build/MacTerminal.app` launches as a
> real bundle, spawns a login `zsh`, and config fail-soft was verified against six deliberately-bad
> fields (six warnings, still a working terminal).
>
> Shipped: real `.app` bundle via `Scripts/make-app-bundle.sh` (no `.xcodeproj` — the project stays
> all text), login shell, **native macOS window tabs** (shared `tabbingIdentifier` +
> `addTabbedWindow`, which buys cycling/overview/reorder/detach/merge/full-screen/VoiceOver for free),
> live-reloadable JSON config with per-field soft failure, font sizing, Tokyo Night default.
>
> NOT shipped: splits, app icon, preferences UI, shell integration (OSC 7/133), search, URL clicking,
> profiles. The name `MacTerminal` is a placeholder.
>
> **Resolved 2026-07-27:** named **Umber**, bundle id `com.griffinlong.umber`. Rationale and
> availability checks in `.afk/research/naming-decision-2026-07-27.md`.
>
> Three API assumptions from the planning phase were WRONG and corrected by compiling:
> `LocalProcessTerminalView` exposes only `init(frame:)` (the font-taking init belongs to
> `TerminalView` and is not inherited); cursor style has no public initialiser either, so it is driven
> by DECSCUSR; and the SwiftTerm delegate conformance needs `@preconcurrency` because SwiftTerm
> predates Swift concurrency annotations and Swift 6 rejects a `@MainActor` conformer outright.
> Worth remembering the shape of that: "assemble off-the-shelf components" was not friction-free.

Original scope, for reference: only after G1-G6. Tabs, splits, config, theme, font. Nothing else. It
either replaces the daily terminal or gets abandoned honestly and cheaply.

### Step 3 — Observer panel

Native session UI built on the Step-1 contract.

### Step 4 — Editor + git (explicitly optional)

Bundling three products into one binary is inherited IDE shape, not derived from this workflow. Three
good separate tools is a legitimate end state.

## 7. Wave 3.5 boundary finding (why Step 1 exists)

A composition-boundary verifier returned **OVERRIDE** on the idea of building a read-only JSONL
observer directly on afk's current on-disk state. It breaks in three places — and it broke the original
plan's Phase 2 in exactly the same way:

- **No stability contract.** `PresenceFileInfo` grew `actor?`/`afk?` on 2026-06-18 with comments saying
  "absent on presence files written before this field existed"; 3 new ledger `kind`s landed the same
  day; `meta.traceLabel?` landed 2026-07-10. `LedgerRecord.v` is an internal discard guard, not version
  negotiation. `paths.ts:431-446` holds *permanent* migration shims from when
  `~/.afk/{sessions,todos,transcripts}` moved under `state/`.
- **Liveness unsolved.** No TTL, no heartbeat, no reaper. Only `kill(pid,0)` in
  `worktree-sweep.ts:181-186`, scoped to that module. **A crashed session looks live forever.**
- **The best notification can't be built.** `elicitation` records require a CLI session with ≥1
  completed turn *and* `/afk on` (`afk-mode-toggle.ts:70-116`). Daemon strips `ask_question`
  (`daemon.ts:269`); Telegram routes natively (`bot.ts:380`). A plain CLI session blocked on stdin has
  **no on-disk signal**.
- Precedent: `telegram/presence-surface.test.ts` exists only because presence `surface` defaulted to
  `'cli'` and `/watch` mis-classified every Telegram session. A first-party consumer silently misread
  this format.
- Multi-writer ledger (REPL + Telegram daemon, both `flags:'a'`, `session-ledger.ts:223`) means a Swift
  parser must reimplement afk's hold-back-the-last-line tail buffering (`:372-381`) or read torn JSON.

Caveat: that verifier hit its iteration cap and returned a **PARTIAL** result. It did not check
`docs/`/`CHANGELOG.md` for a published schema promise, did not empirically test concurrent
multi-process ledger writes, and the repo is a shallow clone — so format churn is **undercounted**.

## 8. Alternatives considered and rejected

| Alternative | Source | Why rejected |
|---|---|---|
| Original ordering: terminal chrome first, afk panel at Phase 2 | my first plan | All 3 critics independently: back-loads the only uncertain hypothesis behind weeks of re-solving solved problems. **Conceded.** |
| Build nothing unifying; only a ~3d menu-bar JSONL observer | pragmatist critic (strength: **strong**) | Correct instinct, and largely adopted — but Wave 3.5 OVERRIDE guts its value on today's substrate (ghosts, no elicitation signal). Hence Step 1 first. |
| Same, 0.5-1d, run 2-4 weeks before deciding | paranoid critic (medium) | Same OVERRIDE. Its soak-testing insight was adopted as gate G6. |
| MenuBarExtra thin client + focus-owning-terminal + daemon HTTP for approvals | architect critic (medium) | Same OVERRIDE, **plus** the daemon strips `ask_question` entirely, so the approvals path does not exist. Its "bundling is inherited IDE shape" point was adopted as Step 4's optionality. |
| Fork CodeEdit and reskin | operator's own question | AI drift (PR #2182 + 7 AI PRs), "not production ready" after 4+ years, 6-repo sprawl, stale SwiftTerm pin. |
| libghostty / Rust FFI / hand-rolled VT / STTextView | §4.3 | Not embeddable / no payoff / multi-year trap / license trap. |

## 9. Risks carried forward

1. **SwiftTerm #494** — open reflow corruption, 4 months stale, single maintainer with a demonstrated
   availability gap. Mitigation: gate G2 as a hard pass/fail before any commitment; patch a fork if
   tractable; kill the terminal premise if not.
   **Status 2026-07-26: G2 PASSES at the engine level (§11), but #494 is still OPEN upstream and its
   reporter describes an INTERMITTENT defect. Deterministic tests can miss intermittent bugs, so this
   risk is REDUCED, NOT CLOSED. G6 (multi-hour differential soak) remains the real gate.**
2. **afk format churn** — Step 1 converts this from an external hazard into a contract the operator
   controls.
3. **Abandonment** — the honest failure mode is stalling at Step 2 and going back to Ghostty + Cursor.
   Mitigated by Step 1 being useful standalone in a repo he already maintains, and Step 2 being small.
4. **"Beautiful and user-friendly as hell" is the actual hard part** and no library provides it. The
   failure mode is scope-creeping into an IDE; the antidote is that every feature must earn its place
   against "does this make running afk better."
5. **Maintenance obligation** — a personal tool that becomes a second job crowds out the work it was
   built to serve.

## 10. Is "no AI" coherent?

Yes, and more sharply than first framed: the app makes zero model calls and has no chat UI of its own.
It is a host and a window. CodeEdit's Copilot drift (PR #2182) is the concrete thing that boundary
protects against.

---

## 11. Step 0 results — 2026-07-26

Environment: Swift 6.4 (swiftlang-6.4.0.27.1), macOS 27.0 (26A5388g), arm64, SwiftTerm **v1.15.0**.
Harness: `spike/` — 5 tests, 0 failures. **The harness was deleted once the gates were
answered** (it was disposable by design); all of its findings are retained verbatim below.

| Gate | Verdict | Method |
|---|---|---|
| G1 render / no tearing | **PASS** | operator-confirmed live, 2026-07-26 |
| **G2 narrowing reflow (#494)** | **PASS** | 3 headless tests, deterministic |
| **G3 Shift+Tab → permission ring** | **PASS** | static analysis, certain |
| G4 Ctrl+B backgrounds | **PASS** | operator-confirmed live, 2026-07-26 |
| **G5 bracketed paste mode** | **PASS** | headless test |
| G6 soak + differential | **PRELIMINARY PASS** | operator eyeballed it clean; NOT the full multi-hour differential soak |

**Verdict: Step 0 GREEN. No blocker found. The gates that could have killed the project did not.
Proceeding to Step 1.**

Recorded precisely, because inflating this would be the exact failure mode worth avoiding: the operator
launched the spike, ran afk in it, and reported "yep seems to be good." That is genuine confirmation of
G1 and G4. It is **not** the multi-hour differential-vs-Ghostty soak G6 was defined as, and #494 is an
*intermittent* defect. G6 therefore converts from a gate into a **standing risk retired only by real
daily use** — if duplicated or orphaned lines ever appear during a narrow-with-scrollback, that is
#494 and it invalidates the terminal premise. Revisit §9 risk 1 at that point.

### G2 — PASS

```
[G2-A before]             distinct tokens: 8,  duplicated: 0
[G2-A after]              distinct tokens: 7,  duplicated: 0   <- visible rows only
[G2-A after(full buffer)] distinct tokens: 8,  duplicated: 0   <- nothing orphaned
[G2-B before]             distinct tokens: 30, duplicated: 0
[G2-B after]              distinct tokens: 30, duplicated: 0
[G2-C before]             distinct tokens: 20, duplicated: 0
[G2-C after]              distinct tokens: 20, duplicated: 0
```

G2-C is the afk-shaped case: DECSTBM scroll region + absolute CUP + zero newlines, then narrow.

The 8→7 drop in G2-A's *visible* rows was investigated rather than waved off: rewrapping 8×100-char
lines from 16 to 24 rows overflows a 24-row screen once the cursor row is counted, so one line
legitimately scrolled into scrollback. The full-buffer assertion (added specifically to close this
ambiguity, since #494 is "duplicate/**orphan**" and the first version of the test only checked
duplicates) confirms all 8 tokens present, 0 duplicated.

**Not closed:** #494 remains OPEN upstream and describes an *intermittent* defect. Deterministic tests
can miss intermittent bugs. G6 is still required before daily-driver commitment.

### G3 — PASS, and the planning risk assessment was WRONG

Planning named G3 the top risk on the claim that no `\x1b[Z` fallback existed. That was a grep error.
`Mac/MacTerminalView.swift` has **two** selector switches:

1. Kitty-protocol switch, gated `if !terminal.keyboardEnhancementFlags.isEmpty` (:1417). afk never
   enables the protocol → block skipped entirely.
2. Plain-xterm fallback switch → `case #selector(insertBacktab(_:)): send(EscapeSequences.cmdBackTab)`.

`EscapeSequences.swift:112`: `cmdBackTab: [UInt8] = [ 0x1b, 0x5b, 0x5a ]` = `ESC [ Z` = **CSI Z** —
precisely what afk's keypress parser needs for `{name:'tab', shift:true}`.

Root cause of the error: AppKit routes Shift+Tab to `insertBacktab(_:)` (lowercase `t`), so a grep for
`insertTab`/`shift.*tab` missed the real handler. **Lesson: a negative grep result is not evidence of
absence — it is evidence about the grep.** This is the second planning claim corrected by direct
verification (the first was the stale bracketed-paste `// TODO`, §4.2).

### Environmental workarounds (not project decisions)

1. **Metal toolchain absent.** Xcode 26.6 moved it to a downloadable component
   (`xcodebuild -downloadComponent MetalToolchain`). Upstream SwiftTerm compiles
   `Apple/Metal/Shaders.metal` as a resource, so `swift build` fails with
   `unable to spawn process 'metal'`. Worked around with a one-line exclude in a vendored copy at
   `spike/vendor/SwiftTerm`, and now at `vendor/SwiftTerm` for the app (gitignored, recreation
   documented in `app/README.md`). Renderer-only;
   the gates test the engine. **For the real project, download the Metal toolchain instead.**
2. **XCTest absent from CommandLineTools.** `xcode-select -p` points at CLT.
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` fixes it for one invocation,
   avoiding a system-wide `sudo xcode-select -s`. `swift build`/`swift run` need no override.

### Next action

*(Superseded — G1 and G4 passed live; the spike harness is deleted. G6 now runs against the shipped
app.)* Build and launch `app/` (`./Scripts/make-app-bundle.sh && open build/Umber.app`) and
daily-drive it. G6 is the one that matters: leave a long session running, narrow the window repeatedly
with scrollback present, overflow the scrollback, and compare against Ghostty side by side. If that
stays clean, the terminal premise holds and the project is real.

---

## 12. Goal correction — 2026-07-27

Operator asked *"when should we add the editor / file explore tree like vs code?"* The first answer
given cited §6 Step 4's optionality and §9 risk 4's "scope-creeping into an IDE" to argue **against**
it. That answer was **wrong**, and wrong because it trusted §3's reframe over §1's verbatim quotes.
Operator's correction: *"the goal was to make a better terax lol like ide/esque terminal-first."*

**The editor and file tree are not scope creep. They are the product.** §1 and §3 are amended above.
Recorded because the plan's own thesis drift produced the error — a future reader would repeat it.

### 12.1 What "terminal-first IDE" concretely means

Terax's layout, read from the operator's fork at `~/Projects/open_source/terax-ai` and independently
re-verified (not taken on a subagent's word):

| Property | Terax | Evidence |
|---|---|---|
| Windows | **Exactly one** | `src-tauri/tauri.conf.json:14-26` (single `windows` entry) |
| Top-level layout | Two-region horizontal resizable split: sidebar + workspace | `src/app/App.tsx:1107-1204` |
| Sidebar | Persistent, collapsible to 0, **px-capped** (`SIDEBAR_MAX_WIDTH` 480); holds Explorer **or** Source Control, mutually exclusive | `App.tsx:1111-1163` |
| Workspace | `defaultSize="78%"`, `minSize="30%"`, **no maxSize** — absorbs all remaining flex | `App.tsx:1166` |
| Tabs | **ONE flat heterogeneous strip**, 8-kind union: Terminal · Editor · Preview · Markdown · AiDiff · GitDiff · GitHistory · GitCommitFileDiff | `src/modules/tabs/lib/useTabs.ts:114-122` |
| Terminal primacy | Boots as tab 1, `kind:"terminal"`, active | `useTabs.ts:244-261` |
| Terminal splits | Pane tree *inside* a tab, max 4 | `useTabs.ts:18`, `PaneTreeView.tsx:63-79` |
| Project root | **"Spaces"** — `SpaceMeta.root` is a dir; tabs partitioned by `spaceId` | `src/modules/spaces/lib/store.ts:5-14` |
| Docking | Fixed positions, resize-only. No drag-to-redock | `App.tsx:1079-1220` |

The load-bearing fact: **editor tabs and terminal tabs live in the same strip.** "Terminal-first" is not
"terminal plus an editor elsewhere" — it is one tab strip where the terminal happens to be tab 1 and win
the default space.

### 12.2 The collision this creates with Step 2's shipped architecture

`TerminalWindowController.swift:55` is `window.contentView = pane.view` — the `TerminalPane` **is** the
window's entire content, and every "tab" is a **separate `NSWindow`** joined by `addTabbedWindow`
(`:86`, `tabbingIdentifier` `:45`). Consequences, all structural:

1. A macOS window tab **is a window**, so an editor tab beside a terminal tab means an editor `NSWindow`
   with its own `contentView` — hence **no shared sidebar**, and the file tree duplicated per tab.
2. The system tab bar spans the full window width, so a **full-height sidebar is not expressible**;
   Terax's (and VS Code's) sidebar runs floor-to-ceiling beside the tab strip.
3. There is no container to hold "these N tabs belong to project X" — **no analogue of Spaces.**

So `app/README.md` + `AFK.md`'s convention *"Native window tabs are load-bearing… do not replace them
with a custom tab bar"* is **correct for a terminal and wrong for the stated product.** It was written
in Step 2 when the goal was still misread as "terminal that hosts afk."

**This, not time and not Step 3, is what gates the editor and file tree.** And it gets more expensive
per feature that accretes on the current shape.

### 12.3 RESOLVED 2026-07-27 — (C) hybrid

Operator picked **(C)**, and delegated the remaining calls ("c then whstever u think is best"). The
three branches as put to him:

- **(A) Keep native window tabs.** Cheapest; forfeits the Terax shape. Per-window sidebar at best,
  editor never lands cleanly.
- **(B) Replace with an in-window tab strip** (what Terax and every Electron IDE do). Unlocks the shape;
  you hand-roll and then own forever: ⌘⇧[/] cycling, tab overview, drag-reorder, drag-out-to-detach,
  Merge All Windows, full-screen behaviour, VoiceOver — all of which are currently **free**.
- **(C) Hybrid — recommended.** Native window tabs are promoted to **Spaces/projects** (one `NSWindow`
  per project root, keeping every free system affordance at the level where detach/merge actually mean
  something), and a hand-rolled in-window strip carries documents (terminal/editor/diff) inside each
  window. Sidebar becomes that window's content, full-height, beside the document strip. Pays the
  hand-roll cost only where unavoidable, and is arguably *more* Mac-native than Terax.

**Chosen: (C).** The next substantive commitment is therefore the **container hierarchy**. §6 Step 3
(Observer panel) is **not** displaced so much as *absorbed*: it becomes a sidebar rail view beside the
file tree, which is exactly Terax's Explorer-XOR-SourceControl pattern (§12.1). G6 still gates
everything — if SwiftTerm #494 kills the terminal premise, none of this matters.

### 12.4 Decision set for (C) — settled 2026-07-27 under delegated judgment

1. **A Space is a project-root directory.** `NSWindow` ⇢ Space ⇢ N documents. Window title is the
   root's `lastPathComponent`. **Default root is `$HOME`** — a deliberate placeholder: a login shell
   starts there anyway, and there is no folder-open action yet. `hostCurrentDirectoryUpdate`
   (OSC 7, `TerminalPane.swift:187`) is *not* used to derive it, because macOS zsh does not emit OSC 7
   without shell integration, which is still unbuilt.
2. **Native window tabs are kept and re-pointed at Spaces.** Same `tabbingIdentifier`, same
   `addTabbedWindow`. This is the whole point of (C): ⌘⇧[ / ⌘⇧] cycling, tab overview, drag-reorder,
   drag-out-to-detach and Merge All Windows keep working for free, at the level where detaching and
   merging actually mean something — a *project*, not a shell.
3. **Documents get a hand-rolled in-window strip**, over the document area only (VS Code's shape), not
   spanning the sidebar (Terax's shape). The strip is heterogeneous by construction — a `SpaceDocument`
   protocol — but `TerminalPane` is its only conformer today. Editor/diff/observer tabs slot in later
   with no further restructuring; that is the unlock this whole change buys.
4. **Keymap.** ⌘N new Space · ⌘T new document · ⌘W closes the *document*, falling through to closing the
   Space when it is the last one · ⌘⌥← / ⌘⌥→ cycle documents · ⌘1…⌘9 select by index · ⌘B toggles the
   sidebar. ⌘0 is untouched (Actual Size). **⌘⌥arrows are verified safe** against
   `KeyBindings.swift`: its guard is `intent == [.command]` — *exact* equality on the masked set — so
   adding Option falls through to SwiftTerm rather than colliding with the ⌘←/⌘→ line-editing bytes.
5. **Sidebar is `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)`**, not a
   hand-rolled split. That buys system sidebar vibrancy, collapse animation, and a free
   `toggleSidebar(_:)` responder. Width min 150 / max 480 (Terax's cap, §12.1) / default 220.
6. **Still no `fullSizeContentView`.** A sidebar item is the textbook reason to reach for it, and it is
   declined on purpose: `TerminalWindowController.swift:29-38` records that this exact flag once clipped
   the terminal's top ~1.7 rows — where the prompt, caret and echo live. AppKit would *probably* handle
   the safe area correctly now that the terminal is nested two levels deeper, but "probably" is not
   worth re-opening a bug that cost real debugging. Sidebar sits below an opaque titlebar.
7. **Font zoom fans out across Spaces × documents**, not windows × one pane. Same rationale as the
   original (`AppDelegate.swift:69-71`): zoom is a property of your eyes, not of one tab.

**Consequence for the docs:** `AFK.md` and `app/README.md` both assert "native window tabs are
load-bearing — do not replace them with a custom tab bar." Under (C) that is half-true and must be
restated: native tabs are load-bearing **for Spaces**; documents are a custom strip by design.
