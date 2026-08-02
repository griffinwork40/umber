# Git in the sidebar, like VS Code — decision brief

**Date:** 2026-07-31 · **Branch:** `afk/add-git-sidebar` · **Status:** **Phases 0, 1 and 2 SHIPPED** (`66eab87`, 2026-07-31). Phase 1 was completed on 2026-08-01 — `isStaged` and `originalPath` had been parsed since day one but reached no user; they now surface as a staged chip plus a row tooltip, and the header distinguishes "no upstream" from "in sync". Phases 3 and 4 remain unbuilt and remain **optional**. The §7 falsifier below has NOT yet run its week.
**Question asked:** *"i want to add git to the sidebar like vs code / research the best way to do this"*

**Answer: build the read-only half and refuse the other half. Decorate the file tree that already
exists (letter badge + colour, per file) from a `git status --porcelain=v2 -z` shell-out behind a pure,
headlessly-gated parser — and do NOT build VS Code's Source Control panel, its staging checkboxes, or
its commit box.**

The recommendation is not a compromise reached for lack of time. Three independent lines of evidence,
gathered by separate research passes that did not see each other's work, converge on the same boundary:

1. **Value.** VS Code's Source Control view ranks **last but one** of seven features on
   value-per-complexity for a terminal, because its entire reason to exist is giving a GUI-only user a
   path around `git add`/`git commit` — not a problem this user has
   (`git-sidebar-external-surface-2026-07-31.md` §2).
2. **The plan of record already refused it, in writing, before this question was asked.**
   `emulator-foundation-probe-and-vendor-integrity.md:208-215` lists things to *"Refuse regardless"*
   and names **"destructive git operations in a GUI"** among them. A read-only status decoration does
   not cross that line; a stage/commit/discard button does
   (`git-sidebar-local-verification-2026-07-31.md` §4).
3. **The ceiling.** `SpaceViewController.swift` is at **345/350 LOC** — five lines from a hard
   `check-file-size.sh` failure. Decorations need zero lines there. A new panel needs container
   surgery first (`git-sidebar-local-layout-2026-07-31.md` §1).

Value, the written project boundary, and the mechanical constraint all point the same direction. That
is the strongest form this recommendation could take, and it is why the brief is decisive.

---

## Evidence base

Five research documents written 2026-07-31, 1,860 lines total, every claim carrying a URL, a
`file:line`, or pasted command output:

| Doc | Lines | Covers |
|---|---|---|
| `git-sidebar-external-surface-2026-07-31.md` | 210 | VS Code's git surface decomposed into 4 subsystems; 6 competitor tools; 8-category UX-trap list |
| `git-sidebar-external-mechanism-2026-07-31.md` | 524 | porcelain v2 grammar (measured); SwiftGit2/libgit2 survey; FSEvents vs. polling |
| `git-sidebar-local-layout-2026-07-31.md` | 285 | Sidebar construction; 4 layouts priced against the ceiling; the file-tree cell seam |
| `git-sidebar-local-precedent-2026-07-31.md` | 388 | `ShellDirectory`+`DirectoryFollow` as template; `SpaceDocument` pricing; config/theme plumbing |
| `git-sidebar-local-verification-2026-07-31.md` | 453 | Check-script anatomy + exit-code contract; the falsification plan; libghostty sequencing |

**Provenance note, stated because it affects how much weight to put where:** the mechanism research
hit its tool-budget ceiling mid-write. Its Option A findings (the winning path) are complete and
measured; its Option B/C prose is thinner than its conclusions. The Option B verdict is nonetheless
well-sourced — it rests on checkable repository metadata (last release dates, API surface), not on
argument. Two earlier orchestration attempts to synthesise these docs failed on budget; this brief
was written directly against the sources instead, so the citations below were read, not relayed.

**Adversarially shadow-verified.** The mechanism decision's load-bearing external claims (SwiftGit2's
staleness, the absent worktree API, the health of alternatives) were re-derived from primary sources by
an independent verifier instructed to *refute* them. Verdict: **recommendation stands**, with two
corrections and one newly-found candidate now recorded inline in §4.

**Independently re-verified by the orchestrator** (not taken on a sub-agent's word):

```
$ git rev-parse --show-toplevel        → .../.afk-worktrees/afk-add-git-sidebar   # worktree root, correct
$ git rev-parse --git-dir              → .../mac-terminal/.git/worktrees/afk-add-git-sidebar
$ git rev-parse --git-common-dir       → .../mac-terminal/.git                    # DIFFERENT — see Risk 1
$ file .git                            → ASCII text
$ test -d .git                         → false                                    # the landmine
$ time (5× git status --porcelain=v2)  → 0.033s total, ~6.6ms/run
```

---

## 1. What to build, and what not to

"Git in the sidebar like VS Code" is not one feature. It is **four architecturally unrelated
subsystems** that ship together in VS Code and get conflated when scoped
(`external-surface` §1). Separating them is most of the work of answering this question:

| VS Code subsystem | Where it actually lives in VS Code | Verdict for Umber |
|---|---|---|
| Letter badge + colour on each file | Explorer tree — a passive decoration overlay | **BUILD.** This is the ask. |
| Branch + ahead/behind | Status bar — *not* the sidebar | **BUILD** (cheap; rides the same data) |
| Resource groups, staging checkboxes, commit box | Source Control view — a *separate panel* | **REFUSE.** Plan already refuses it. |
| Gutter dirty-diff, inline blame | The editor | **DEFER.** Needs a real editor first. |

The structural fact that settles the shape: **VS Code never puts staging controls in the file tree.**
The tree gets passive decorations only; staging is a separate view with its own model
(`external-surface` §1a). So "add git to the sidebar like VS Code" — read literally, against what VS
Code actually does in the sidebar's tree — *is* the decoration feature. The commit UI is a different
panel that the user did not ask for and the plan of record has already declined.

Worth stating plainly, because it is the most surprising external finding: **essentially nobody ships
git-status decorations in a terminal.** Ghostty has zero, and it is an open, unimplemented ask.
Warp — funded, actively developed, with a dedicated diff-review panel and a merged branch chip — has
**no** tree decorations, across three open issues whose own maintainer triage cites
`microsoft/vscode`'s `decorationProvider.ts` as the file to copy (`external-surface` §3).

Is that an opportunity or a warning? The evidence supports a split answer, and the split maps exactly
onto the phases below. **Decorating a tree that already exists** is the opportunity: wanted, cheap,
additive, and deprioritized-not-abandoned everywhere it is missing. **Building a new changed-files
panel** is the thing teams closer to the problem keep deciding against on purpose — GitHub Desktop
refused a file tree for 8+ years in explicit maintainer statements ("not in the scope of GitHub
Desktop"), and Sublime Merge's changed-files-tree request has been open since 2019 in a paid,
git-specialist tool (`external-surface` §3). Decorations are underbuilt; a second panel is
*declined*. Build the first; treat the second as optional.

---

## 2. The phased plan

Every phase is independently shippable and independently gated. LOC budgets keep every file under 350.

### Phase 0 — the parser and its gate (no user-visible change)

The gate is the deliverable, which is how this repo works: *"a concern that cannot be compiled alone
cannot be gated alone, so the dependency-free boundary IS the testability"*
(`ShellDirectory.swift:36-41`).

| File | New/changed | Budget | Owns |
|---|---|---|---|
| `Sources/Umber/GitStatus.swift` | new, **pure** (`Foundation` only, not `@MainActor`) | ~140-170 | Repo discovery, spawn `git status --porcelain=v2 -z`, parse to a value type |
| `Scripts/check-git-status.sh` | new | ~200 | Truth table over `GitStatus.swift` compiled standalone |

**Gate:** `swiftc` compiles `GitStatus.swift` + a heredoc `main.swift` alone, exactly as
`check-cwd-follow.sh:211` does. Exit contract must copy the **strong** form — wrap the compile in
`if ! swiftc ...; then exit 2; fi`. Do *not* copy `check-keybindings.sh`/`check-space-restore.sh`,
which have **no exit-2 path at all**, so a compile failure there is indistinguishable from a real
assertion failure (`local-verification` §1, verified by exhaustive `grep -n exit`). Add a
`git --version` guard: "git too old for `--porcelain=v2`" is a real environmental case, unlike
anything the existing scripts face.

**Fixtures must be real.** Not hand-typed strings claiming to look like porcelain — a real `git init`
in a temp dir, real `git add`/`git commit`/`git mv`, a real merge conflict from two diverging commits.
`check-cwd-follow.sh:156-158` states the principle: *"Executed, not string-matched... asserting on the
quoting's shape would pass for any self-consistent wrong answer."* A hand-typed fixture encodes only
the author's assumptions about the format, which is precisely where a looks-right-is-wrong bug hides.

**Falsification — how we prove the gate can fail.** The reflow gates falsify by reverting a vendor
patch; there is no upstream bug to revert for new first-party code, so the counterexample must be
manufactured (`local-verification` §3):

1. Write a deliberately naive parser first: whitespace-split, `--porcelain=v1`, no `-z`.
2. Write the finished gate against it.
3. **Observe: the boring case passes; rename, conflict, and special-character cases fail.** Fails for
   the *right specific reason* — not "everything red," which would indicate a harness bug.
4. Swap in the correct `-z`/v2 parser. Same unmodified script.
5. Observe all green. Keep the red→green transition in the PR body as the evidentiary trail.

**Control case** (the analogue of `check-altbuffer-resize.sh`'s case 3): a boring ASCII-only
add/modify/delete fixture asserted to pass under *both* parsers. If the control ever fails under the
correct parser, the rig is broken, not the parser — so a harness bug reads as "control + edge cases
both red" and a real parser bug reads as "control green, edge cases red."

The two naive-parser bugs to falsify against are chosen because they are this domain's version of
defect shapes that have already burned this codebase: **(a)** whitespace-splitting a rename record
(`R old name.txt -> new name.txt`) — the porcelain analogue of the adversarial-path case
`check-cwd-follow.sh` already defends; **(b)** ignoring the `u` unmerged record's three-mode shape,
which silently drops conflicted files during a merge — the single moment a git sidebar's correctness
matters most, and the least likely to be manually re-checked in a repo with no CI.

### Phase 1 — decorations in the tree (the ask)

**User sees:** filenames tinted by status, with an optional letter badge; dirty state propagating up
to parent folders.

| File | Change | Headroom |
|---|---|---|
| `FileNode.swift` | add one mutable `gitStatus` property | 110/350 → **240 free** |
| `FileTreeViewController+OutlineView.swift` | tint + badge in `viewFor` (:64-77) / `makeCell` (:129-158) | 159/350 → **191 free** |
| `FileTreeViewController.swift` | one trigger call in `refresh()` (:123) | 300/350 → 50 free |
| `GitStatus+Presentation.swift` | new — status → `NSColor`, mirroring `DocumentStatus+Presentation.swift` | new file |
| `SpaceViewController.swift` | **untouched** | 345/350 → 5 free |

The mutable `gitStatus` on `FileNode` rides the **already-proven** identity-preserving reuse in
`reloadChildren()` (`FileNode.swift:50-53, 73-78`) exactly as `isDirectory`/`isHidden` already do, so
`NSOutlineView`'s expansion and selection state survives a status refresh for free. Getting this wrong
— replacing nodes instead of mutating them — silently destroys the user's expanded tree, the same bug
class `refresh()` already guards against.

**Colours:** no new theme fields. Use AppKit semantic system colours following
`DocumentStatus+Presentation.swift` verbatim, whose own doc comment gives the rule: *"System colours,
not hex literals: they are the only ones that adapt to Increase Contrast and to the window's effective
appearance."* An ANSI-palette colour would be actively wrong — under the default `theme == nil` Umber
installs no palette at all, and the moment any theme is set SwiftTerm **regenerates** ANSI 16-255 by
interpolating from bg/fg, so "ANSI green" silently becomes a different RGB
(`local-precedent` §4b).

**Gate:** Phase 0's parser gate still covers correctness of the data. The rendering itself is
ungated — and that must be said out loud rather than implied. Glyph choice and poller cadence are UI
glue in the same accepted-unverified category as file icons today (`local-verification` §2). The
parser is the only part a check script can reach; `check-file-size.sh` covers the ceiling.

### Phase 2 — ambient branch + ahead/behind

**User sees:** current branch and ahead/behind counts, without typing `git status`. Ranked #1 on
value-per-complexity by the external research (`external-surface` §2) because glance-frequency is
high and cost is near-zero once Phase 0 exists — the data is already in the same snapshot.

**Where it goes is a genuine judgment call — see §6.** Files: the poller from Phase 0/1 plus either a
live `window.title` update on `SpaceWindowController` or a small sidebar header view.

### Phase 3 — changed-files list *(optional)*

Layout (d), a segmented Files/Source-Control switch, mirroring
`DocumentAreaViewController.setStripVisible` (:48-58) rather than a nested split. **This is the phase
that costs container surgery**: it must edit `SpaceViewController.swift`'s construction site
(:92-102) against 5 lines of headroom, so it requires pulling a concern out into a new file *first* —
the established `+DirectoryFollow` move. Genuinely optional; see §1 on why everyone declines to build
this panel.

### Phase 4 — diff view *(optional)*

A `GitDiffPane: SpaceDocument` — a tab in the document area, **not** sidebar UI. The protocol's own doc
comments already name diff tabs twice (`SpaceDocument.swift:101-103`), AFK.md names diff as the
anticipated next conformer, and a read-only monospace view takes 4 of 5 defaulted members correctly for
free (`local-precedent` §2). Adding it must not touch the container — that is the seam's whole payoff.

---

## 3. Verdict table

| Decision | Chosen | Rejected | One-line reason |
|---|---|---|---|
| **Sidebar layout** | (a) decorations only | (b) nested `NSSplitView` | Needs the construction site at :92-102; 5 lines of headroom |
| | | (c) synthetic outline group | Breaks `FileNode`'s contract as pure filesystem data (:5-7) |
| | | (d) segmented switcher | Right shape for Phase 3, wrong opening move — same 5-line problem |
| **Git access** | shell out, `--porcelain=v2 -z` | libgit2 / SwiftGit2 | No release since 2019; **no worktree API**; second vendored C dep |
| | | parse `.git` yourself | Index v2/3/4 + extension variance for no gain (fine for `HEAD` alone) |
| **Refresh** | FSEvents + slow-poll backstop | polling only | 92ms at 60k files makes a live-feeling interval too costly |
| | | FSEvents only | Coalesces/drops under load; misses network volumes |
| | | watch `.git/index`+`HEAD` only | **Cannot see untracked or modified worktree files at all** |
| **Scope** | read-only status | staging / commit / discard | Plan refuses *"destructive git operations in a GUI"* (:208-215) |
| **Colours** | AppKit semantic system colours | new `theme.json` hex fields | System colours adapt to appearance + Increase Contrast for free |
| | | ANSI palette colours | No palette exists at `theme == nil`; regenerated when theming is on |

---

## 4. Rejected alternatives, steelmanned

**libgit2 via Swift bindings.** *Strongest case:* a real typed API instead of parsing text; no fork/exec
per refresh; structured access to refs, blobs and diffs that a status shell-out cannot give — and Phase
4's diff view will eventually want exactly that. *Why it loses:* **no binding clears the worktree bar,
which is disqualifying on its own** — Umber's own development happens in worktrees and this very
checkout is one. `SwiftGit2`'s latest tag is **0.6.0, 2019-04-15** (7+ years stale; a Nov 2025 push
never cut a release), and no fork adds worktrees — `light-tech` is an SPM/iOS build fix, `mbernson`
mirrors upstream tags with no divergence, `SwiftGit3` adds push/pull/SSH/M1 only. Beyond worktrees, the
structural objections are independent and each sufficient: it would be a **second** vendored C
dependency in a repo whose one vendored dependency already carries three local patches that a re-vendor
silently drops, and — decisively — a C-library binding **cannot be gated by a single-file `swiftc`
harness**, so it forfeits the only verification surface this repo has. `git` ships with the OS at zero
vendoring cost, measured ~6.6ms here / ~92ms on a 60k-file repo (~36ms with `core.fsmonitor`).

> **Shadow-verified 2026-07-31, with two corrections to the first research pass.** An independent
> adversarial verifier re-derived these claims from primary sources and returned *"recommendation
> STANDS"* — but two specifics were wrong and are corrected here rather than quietly kept:
> **(1) `SwiftGitX` is healthier than "unproven" implied** — 0.4.0 released, Swift 6 support merged
> (PR #10), zero data-race-safety errors, a PR merged ~1 week before a 2026-07-24 index snapshot. It is
> disqualified purely on **no worktree API surface** (absent from README, docs and forum announcement;
> independently corroborated by a third-party dependency evaluation finding no worktree files in the
> source tree) — a cleaner reason than the one first given.
> **(2) The first pass missed a candidate entirely: `swift-developer-tools/swift-libgit2`** — real and
> current, bundling libgit2 **v1.9.1**, Swift 6.1 minimum, tag 1.0.1, 1,186 commits, claiming coverage
> of "every libgit2 API except opaque objects and init macros." It loses anyway, on grounds that do not
> depend on the unresolved question below: it is explicitly a **raw C-interop shim, not an idiomatic
> wrapper** (its own README: "same signatures… camelCase instead of snake_case," "no namespaces,"
> manual memory management), so it is still "link and vendor a C library" — the exact cost the
> recommendation exists to avoid, and still ungatable by the single-file harness.
> **UNVERIFIABLE:** whether `swift-libgit2` exposes `git_worktree_*`. Direct source fetches failed
> repeatedly; a third-party code index returned zero `gitWorktree*` symbols but its coverage of a
> 3-star repo is unconfirmed. This is a **gap, not a refutation** — and it does not change the verdict,
> because the shim/vendoring/gating objections are each independently sufficient. Anyone revisiting the
> mechanism decision should close this gap first.

**The full Source Control panel with staging.** *Strongest case:* it is literally what "like VS Code"
names; it is the largest visual chunk of VS Code's git by screen area; and mouse-driven hunk staging is
genuinely faster than `git add -p` for some people. *Why it loses:* the plan of record already refused
destructive git operations in a GUI, in writing, before this question was asked. It is the single most
expensive item on the ranked list, its whole purpose is serving users who *cannot* type `git add`, and
the target user chose a terminal-first tool precisely because typing commands is not the friction. It
also needs container surgery against 5 lines of headroom. Every axis agrees.

**The synthetic "Source Control" outline group.** *Strongest case:* genuinely clever — zero container
change, reuses the existing `NSOutlineView`, and a changed-files list falls out nearly free. *Why it
loses:* it forces `FileNode` and the data source to represent two fundamentally different row kinds
under one root, breaking `FileNode`'s stated contract — *"a URL, two flags and a directory read"*
(:5-7) — at the **model** layer, not just the view layer. Every synthetic row violates the
`node.url` / `isDirectory` / `reloadChildren()` assumptions the identity-preservation mechanism depends
on. A bigger structural break than the layout it avoids, and VS Code itself uses a separate panel.

**FSEvents only, no polling.** *Strongest case:* strictly event-driven is more correct *and* cheaper
than waking up on a timer to usually find nothing; polling is the crude option. *Why it loses:*
FSEvents coalesces aggressively and can drop events under load, does not cover network volumes, and —
decisively — watching only `.git` **cannot see untracked or modified working-tree files at all**, since
those never touch `.git` until staged. Watching the whole worktree instead reintroduces the
`node_modules` churn problem that produced real reported VS Code freezes. FSEvents as primary signal
with a slow poll as backstop is what VS Code itself does (`DotGitWatcher` plus a `**` workspace
watcher).

**Branch in the window title, no sidebar UI at all.** *Strongest case:* the cheapest thing that could
work; `window.title` is already scoped to the Space's root (`SpaceWindowController.swift:154`), which
exactly matches "one repo per Space"; zero new views; zero tree changes. *Why it loses as the whole
answer:* it does not answer the question asked — per-file status in the tree is the ask, and a branch
name is orthogonal to it. `window.title` is also written once at init and never mutated, so making it
live is new code, not reuse. It survives as a real *option for Phase 2* (see §6), not as a substitute
for Phase 1.

---

## 5. Risks and open questions

**Risk 1 — the worktree detection landmine. Highest severity; independently confirmed.** In a
worktree checkout `.git` is an **ASCII text file** containing `gitdir: …`, not a directory. Verified in
this very checkout: `test -d .git` → **false**. Any repo detection written as
`isDirectory(root + "/.git")` therefore concludes "not a repo" for **Umber's own development tree and
every `.afk-worktrees/*` checkout** — while passing every manual test from an ordinary clone.
*Mitigation:* never hand-roll detection; shell out to `git rev-parse --show-toplevel`, verified above
to return the worktree root correctly. Note also that `--git-dir` and `--git-common-dir` **differ** in
a worktree (per-worktree `HEAD`/`index` vs. shared `refs/`), so a watcher must cover **both** paths —
watching only one misses either branch switches or index changes.

**Risk 2 — staleness is the dominant bug class, not rendering.** Across VS Code's history the external
research found **five separately-filed, separately-root-caused** stale-decoration bugs, including a
decoration-event cap that silently degrades correctness inside collapsed folders, two competing
providers racing so `undefined` overwrites a real status, and a "repository too huge" latch with no
recovery but an app restart. Every one came from a *clever incremental* update scheme.
*Mitigation:* rebuild the whole status map from `git status` on every trigger. Never diff/patch it
incrementally. Accept the redundant work; it is measured in single-digit milliseconds here.

**Risk 3 — cost scales with tree size, not dirty-file count.** Measured: ~92ms on a real 60k-file repo
(~36ms with `core.fsmonitor`); dirtying 5 of 60k files barely moves it. *Mitigation:* debounce ~200-300ms
after an FSEvent; slow backstop poll ~2s, slower than cwd-follow's 750ms; and stop entirely on
resign-key, reusing `DirectoryFollow`'s existing rule that *"a background Space cannot be looked at, so
following it is pure cost."*

**Risk 4 — the N-repos-open case.** VS Code's #318279: a ~50-repo workspace fired ~400 concurrent git
subprocesses and killed its own extension host in a restart loop; the fix was a hard `Limiter(5)`.
Umber is one repo per Space, but a user with many Spaces open reproduces the shape.
*Mitigation:* one poller per Space, stopped on resign; consider a process limiter before Phase 3.

**Risk 5 — most of this feature is not gatable, and the brief should not pretend otherwise.** The
parser is the only part a check script can reach. Poller cadence, glyph choice, colour legibility and
sidebar wiring are verified only by daily use — precedented (file icons are in the same category) but
real. Phase 0's gate buys correctness of the *data*, not of the *display*.

**Carried UNVERIFIED, not upgraded to fact:** whether `swift-developer-tools/swift-libgit2` exposes
`git_worktree_*` (see §4 — a gap, not a refutation; close it first if the mechanism decision is ever
reopened); default hex values for `gitDecoration.*` (only
inconsistent third-party gists; the real source is `extensions/git/package.json`, never pulled);
VS Code's status-bar branch indicator (thin citation); whether current Xcode fixed its 2017 worktree
breakage; Nova's file-tree colour coding (third-party review only); Fork/Sublime Merge worktree support
(absence of evidence); 100k-file monorepo churn and FSEvents cost at that scale (only a synthetic flat
tree was measured); `core.fsmonitor`'s Watchman-hook variant. Also **corrected on the record** by the
mechanism research against its own first pass: `GIT_OPTIONAL_LOCKS=0` does *not* prevent lock errors —
a stale `index.lock` never fails plain `git status`. Its real value is avoiding lock-file churn,
FSEvents noise, and a needless index write. Use it anyway, for those reasons.

**One parser edge case found during verification and worth writing into the gate:** `# branch.ab` is
**absent entirely** when the branch has no upstream — as on this very branch. Ahead/behind must be an
optional, and a parser that assumes the header is always present will break on exactly the
freshly-created local branches an agent workflow produces constantly.

**libghostty sequencing — orthogonal, not a conflict.** The parser, poller, gate script, `FileNode` and
`+OutlineView` share **zero** files with anything the libghostty plan names or has touched. The one
nominal overlap, `SpaceViewController.swift`, is a disjoint *region*: libghostty's Phase 1 touched
document/pane plumbing and is already merged (`4cdbbea`), and no remaining libghostty phase is
documented as touching that file again — its remaining work is explicitly scoped to new files
(`GhosttyPane.swift`, `GhosttyPane+Document.swift`). The plans express **no opinion** sequencing a git
feature either way, beyond the one refusal in §1. The only tax is the 350-line ceiling, which binds
identically with or without the probe (`local-verification` §4).

---

## 6. The judgment calls that are the operator's, not the agent's

1. **Where does the branch indicator go (Phase 2)?** `window.title` matches the scope exactly (one repo
   per Space) but is currently write-once at init, so making it live is new code; a sidebar header is a
   new view but keeps git information in one place. `DocumentStatus` precedent routes "things worth
   flagging" through per-item chrome rather than window strings, which mildly favours the sidebar. This
   is taste, not correctness.
2. **Letter badges on or off by default?** Zed ships colour tint **on** and letter badges **off**;
   VS Code ships both on. For a terminal's sidebar — narrower than an IDE's, and next to a
   deliberately quiet UI — the Zed default may be the better fit. A visual-noise call the operator
   should make by looking at it.
3. **Does Phase 3 happen at all?** It is the only phase that costs container surgery and a preparatory
   refactor, and §1 argues the industry keeps declining to build exactly that panel.

---

## 7. What it looks like if this is wrong

The recommendation rests on one premise: **ambient read-only status is worth more to this user than
workflow replacement.** The leading indicator that it is wrong is behavioural, and cheap to watch for:

**If, a week after Phase 1 ships, the operator still types `git status` in the terminal instead of
glancing at the sidebar, the premise is false** — and the correct response is to *cut* the feature, not
to extend it toward the staging UI. Extending would be the trap: it would read as "decorations weren't
enough, so build the rest of VS Code," when the actual finding would be that a terminal user's git
workflow is already fast enough in the terminal.

Two secondary indicators: decorations that read as noise rather than information (mitigation is
judgment call #2, not more features), and the poller showing up in Activity Monitor or battery use
(mitigation is Risk 3's debounce, or dropping to refresh-on-focus only).

The honest prior: nobody has shipped this in a terminal. Warp's three open issues suggest it is wanted
and deprioritized rather than tried and abandoned — but that is weak evidence, and Phase 0's gate plus
Phase 1's small blast radius are what make the bet cheap to unwind. Nothing in Phases 0-2 is
load-bearing for anything else; deleting them removes decorations and a branch string, and no other
feature notices.
