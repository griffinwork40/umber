# Verification-surface research: git-status sidebar feature

Scope: read-only research into Umber's check-script pattern, the "pure file" rule,
falsification-as-bar, and strategic sequencing vs. the libghostty probe, ahead of
designing a git-status sidebar decoration feature. All check scripts were run
read-only for real observed output; none were modified. Repo: worktree
`afk/add-git-sidebar` @ `0ebd717`, clean.

---

## 1. THE CHECK-SCRIPT PATTERN, precisely

### Shared anatomy (from full reads of check-keybindings.sh, check-cwd-follow.sh; skims of check-space-restore.sh, check-reflow.sh, check-altbuffer-resize.sh)

1. **One `swiftc` invocation compiles exactly one shipped source file plus a
   throwaway harness, in the same command.** Never `@testable import`, never
   XCTest.
   - `Scripts/check-keybindings.sh:82`:
     `swiftc -o "$TMP/keycheck" Sources/Umber/KeyBindings.swift "$TMP/main.swift"`
   - `Scripts/check-cwd-follow.sh:211`:
     `swiftc -O "$SRC" "$WORK/main.swift" -o "$WORK/run"` where
     `SRC="Sources/Umber/ShellDirectory.swift"` (line 31)
   - `Scripts/check-space-restore.sh:168-170`:
     `swiftc -o "$TMP/harness" Sources/Umber/Defaults.swift "$TMP/main.swift" -framework AppKit`
   - `Scripts/check-reflow.sh:322-324` / `Scripts/check-altbuffer-resize.sh:248-250` are
     the one structural exception: they link `.build/out/Products/Debug/SwiftTerm.o`
     instead of a `Sources/Umber` file, because their unit under test is **the vendored
     emulator itself** (check-reflow.sh:11-13: *"the unit under test is the vendored
     emulator itself, not a file from `Sources/Umber`"*).

2. **Harness injection is a bash heredoc**, `cat > "$TMP/main.swift" <<'SWIFT' ... SWIFT`,
   written into a `mktemp -d` cleaned by `trap 'rm -rf "$TMP"' EXIT`. Every script uses
   this. check-cwd-follow.sh states explicitly *why* the file must be named `main.swift`:
   "Swift only allows top-level statements in a file with that name, and this needs
   top-level code to drive a spawned child" (check-cwd-follow.sh:39-40).

3. **Truth-table shape varies by need, not by convention**: check-keybindings.sh uses one
   parametrized `check(label, keyCode, modifiers, expect)` called ~17 times
   (lines 56-76); check-cwd-follow.sh and check-space-restore.sh use a looser
   `check(name, ok, detail)` grouped under `print()` section headers; check-reflow.sh /
   check-altbuffer-resize.sh use a `Case` struct + `run(_:)` function, because each case
   carries ~8 geometry parameters. The common thread is not a shared harness library —
   there is none — but the same three moves: state expectation, compute actual, compare,
   accumulate a `failures` counter, print ✓/✗.

4. **EXIT CODE CONTRACT — verified per script, and it is NOT uniform. This is itself a finding.**

   | Script | 0 | 1 | 2 | Pre-compile env guards? |
   |---|---|---|---|---|
   | `check-keybindings.sh` | all pass (`:79`) | `failures>0` (`:79`) | **none exist** | **No** — no `command -v swiftc`, no `[ -f ... ]` |
   | `check-cwd-follow.sh` | `:205` | `:208` | `:33,34,59,70,73,92,214` | **Yes**, explicit, before the heredoc even starts |
   | `check-space-restore.sh` | `:165` | `:165` | **none exist** | **No** — same gap as check-keybindings.sh |
   | `check-reflow.sh` | `:316-319` | same line, `failures>0` | `:84-115` (vendor missing, no swiftc, `swift build` fails, harness won't compile), `:312-315` (precondition failures) | **Yes** |
   | `check-altbuffer-resize.sh` | `:242-245` | same line | `:75-101` (mirrors check-reflow.sh), `:238-241` (terminal-construction env failures) | **Yes** |
   | `verify-vendor.sh` | `:—` (implicit, tree matches) | `1` missing vendor/pin (`:75,102,107,147`) | `2` present-but-unpatched (`:123,168`) | `3` unknown revision (`:136,186`) |

   **check-keybindings.sh and check-space-restore.sh have NO explicit exit-2 path.**
   I confirmed by exhaustive `grep -n exit` on both files (only one `exit(failures==0?0:1)`
   call exists in each). I then verified empirically what happens on a compile failure:
   `swiftc` on a missing file exits `1` (`error opening input file ... No such file or
   directory` — reproduced live against a scratch `/tmp` file, not a repo file); `swiftc`
   on a syntax error also exits `1`. Because both scripts run under `set -euo pipefail`
   (`check-keybindings.sh:18`, `check-space-restore.sh:30`) with **no `if ! swiftc...`
   wrapper**, a compile failure in either script propagates swiftc's own exit code (`1`)
   straight through as the script's exit code — **indistinguishable from "a real
   assertion failed."** This is the exact ambiguity check-cwd-follow.sh's header calls
   load-bearing (*"a broken environment must never read as a green gate"*,
   check-cwd-follow.sh:21) — but the inverse failure (environment misread as *red*, i.e.
   a real bug) is present here too, unflagged. check-cwd-follow.sh and check-reflow.sh
   avoid this by wrapping the compile step in an explicit `if ! swiftc ...; then ...;
   exit 2; fi` (`check-cwd-follow.sh:211-215`, `check-reflow.sh:322-329`) — a pattern
   check-keybindings.sh and check-space-restore.sh do not use. **Design consequence for
   the new git-status gate: copy the check-cwd-follow.sh/check-reflow.sh explicit-guard
   form, not the keybindings/space-restore form.**

5. **Real-run confirmation (executed this session, read-only):**
   `check-keybindings.sh` → 17/17 ✓, exit 0. `check-cwd-follow.sh` → all checks passed
   including the adversarial-path case (`deep dir's $weird\`one`), exit 0, with the
   tcgetpgrp-branch case correctly **SKIPped** ("stdin is not a tty") because this
   session's shell isn't a tty — confirms the honesty mechanism fires in practice, not
   just in comments. `check-space-restore.sh` → 12/12 ✓, exit 0. `check-file-size.sh` →
   41 files, 0 violations, 3 within the warn band (`SpaceViewController.swift` 345/350,
   `TerminalPane.swift` 336/350, `FileTreeViewController+OutlineView.swift` — no,
   corrected: 159, not warned). **`check-reflow.sh` and `check-altbuffer-resize.sh` both
   exited `2`** in this worktree — *"error: vendor/SwiftTerm is missing — nothing to
   check"* — because `vendor/` is gitignored (confirmed: `.afk-worktrees/*` checkouts
   never materialize it; the sibling main checkout at
   `/Users/griffinlong/Projects/open_source/mac-terminal/vendor/SwiftTerm` does have it).
   **This is itself a live, unplanned confirmation of the exit-code contract working
   correctly**: a genuinely environment-broken run (no vendor present) produced exit `2`
   with a named cause, not a false pass and not a false "assertion failed."

### What check-cwd-follow.sh spawns and reads back (full detail, lines 41-219)

Opens a real BSD pty (`openpty(&primary, &secondary, nil, nil, nil)`, line 69),
`posix_spawn`s `/bin/zsh -c "sleep 12"` (line 89-93) with `POSIX_SPAWN_SETSID` (line 78)
and `posix_spawn_file_actions_addchdir_np` pointed at
`"deep dir's $weird\`one"` (line 56) — a name chosen to defeat naive quoting. It reads the
child's cwd back via `ShellDirectory.current(foregroundOf: primary, fallbackPid: pid)`
(line 112) — the exact production code path. Separately (lines 159-171) it executes a
**second** real `/bin/zsh -c` running the constructed `cd` command + `pwd`, and compares
the shell's own reported `pwd` to the target — proving the quoting survives real
execution, not merely string-equality with an expected literal.

### What each script explicitly documents it CANNOT test, and why the honesty matters

- **check-cwd-follow.sh**: (a) the real `tcgetpgrp` foreground-process-group branch
  cannot be exercised against the *spawned child*, because "Darwin needs an explicit
  ioctl(TIOCSCTTY) that a posix_spawn'd child cannot issue and Swift marks fork()
  unavailable" (lines 97-107) — so that case is retitled to test the **fallback pid**
  path and says so in its own assertion label (`"foreground-group probe behaved as
  documented on this OS"`, line 115); the tcgetpgrp branch is tested for real only
  against the *script's own* controlling terminal (lines 178-192), skipped when stdin
  isn't a tty. (b) `setRoot(_:)` cannot be reached at all — it's AppKit, and the whole
  point of this harness is to compile without AppKit.
- **check-reflow.sh / check-altbuffer-resize.sh**: both name their blind spot as a
  structural fact about the harness's own code path (`getLine(row:)` vs
  `getBufferAsData`, normal vs alt buffer) rather than hiding it.
- **Why this matters**: a gate silent about its blind spots invites "all green" to be
  read as "fully verified" — precisely the failure this repo's whole apparatus exists to
  prevent (AFK.md's repeated "must never read as a green gate" framing, echoed in every
  script's own header). Naming the blind spot is what lets a reader trust the green that
  remains.

---

## 2. THE 'PURE FILE' REQUIREMENT

**Verified directly**: `ShellDirectory.swift:33-34` — exactly two imports,
`import Darwin` then `import Foundation`. No AppKit, no SwiftTerm. The file's own header
states the reason explicitly: *"Pure and view-free on purpose — `Foundation` and `Darwin`
only, no AppKit and no SwiftTerm. That is not tidiness: it is what lets
`Scripts/check-cwd-follow.sh` compile this one file directly with `swiftc` and run a
truth table over it, the same trick `KeyBindings.swift` plays for
`check-keybindings.sh`. In a repo with no test target and no CI..., a concern that
cannot be compiled alone cannot be gated alone, so the dependency-free boundary IS the
testability"* (ShellDirectory.swift:36-41). `FileNode.swift:16` — `import Foundation`
only, for the identical reason stated in its own header (lines 5-7: *"no NSOutlineView
and no AppKit control anywhere in it (hence Foundation, not AppKit)"*).
`KeyBindings.swift` (per AFK.md's file table) and `Defaults.swift`
(`check-space-restore.sh:36-42`: *"Defaults.swift imports only AppKit, because a
UserDefaults store has no business knowing about the emulator... If a future edit makes
this script need `-I .build/out/Products/Debug` again, the store has grown a dependency
it should not have"*) are the other two proven instances — note Defaults.swift's bar is
"AppKit-only, no SwiftTerm," one step looser than ShellDirectory/FileNode/KeyBindings'
"Foundation/Darwin-only, no AppKit either," because `UserDefaults` itself is AppKit-tier
Foundation and the file has no view code to keep out.

### Design rule for a git-status parser

- **May import**: `Foundation` only (and `Darwin` if a raw syscall is ever needed, which
  git-status parsing should not require — it consumes `git`'s own stdout, not a kernel
  struct). No `AppKit`, no `SwiftTerm`.
- **Must NOT touch**: `NSOutlineView`, `NSView`, any `SpaceDocument`/`SpaceViewController`
  type, `Process`/`posix_spawn` invocation of the `git` binary itself. The parser's job
  is `(Data or String) -> [GitFileEntry]` — a pure function over bytes already captured,
  exactly as `ShellDirectory.workingDirectoryPath(of:)` is a pure function over a `pid_t`
  someone else obtained, and `ShellDirectory.cdCommand(to:)` is a pure function that
  *builds* a string without executing anything.
- **Where process-spawning code lives vs. pure parsing code — concrete split, following
  the cwd-follow precedent exactly**:
  - `Sources/Umber/GitStatusParser.swift` (new, pure): `Foundation`-only. One function
    `parse(porcelain: Data) -> GitStatusSnapshot` (or similar), decoding
    `git status --porcelain=v2 -z --branch` output into a structured model (per-file
    status codes, rename pairs, branch ahead/behind). Compiled alone by a new
    `check-git-status.sh`, mirroring `check-cwd-follow.sh`'s
    `swiftc -O "$SRC" "$WORK/main.swift" -o "$WORK/run"`.
  - A **new impure file**, analogous to `SpaceViewController+DirectoryFollow.swift`
    (the existing precedent for "poll a live external fact into the sidebar" — it owns
    the 750ms poller, `DirectoryFollow`, its key/resign lifecycle, per AFK.md's file
    table), e.g. `SpaceViewController+GitStatus.swift` or a standalone
    `GitStatusService.swift`: owns the `Process` (or `posix_spawn`) invocation of
    `/usr/bin/git status --porcelain=v2 -z --branch` inside the Space's root, a poll
    timer or FS-event trigger, and feeds the resulting `Data` into
    `GitStatusParser.parse(porcelain:)`. This file imports `AppKit`/`Foundation` freely
    and is NOT gated by a headless compile — it is glue, verified (if at all) only by
    `UMBER_DIAG` dumps and manual daily-drive, exactly as `DirectoryFollow`'s poller half
    is documented as "genuinely not verifiable headlessly" while its *decision logic*
    (what to do with the answer) is what gets gated (`app/README.md:71-79`'s framing of
    `check-space-restore.sh` applies near-verbatim here: the half that decides *what*
    comes back is ordinary logic and gatable; the half that only pays off across a
    live-process boundary is not).
  - `FileNode.swift` or `FileTreeViewController+OutlineView.swift` gets a small,
    additive hook to *render* a status glyph next to a row — this is view code, stays
    ungated in the same way icon selection (`FileTreeViewController+OutlineView.swift`'s
    `symbolName(for:)`) is ungated today: a real behavioral decision (which glyph) with
    no headless test, verified by eyeballing, which is an accepted, precedented gap in
    this codebase, not a new one.
- **Consequence**: the parser is the ONLY part of this feature a check script can gate.
  Everything downstream (the poller cadence, the glyph choice, the sidebar wiring) is
  UI glue in the same category as file icons and drag-to-reorder — accepted, unverified,
  daily-drive-only territory, exactly as it is for every other AppKit concern in this repo.

---

## 3. FALSIFICATION AS THE BAR — the highest-value section

### Verifying the two claims

**check-reflow.sh, read directly**: its header states the old, deleted gate
(`spike/Tests/SpikeGatesTests/ReflowGateTests.swift`) "still passes UNPATCHED" (line 27)
and that the new gate was checked the other direction — *"Verified by reverting 0002 and
re-running with no manual build: 6 of 8 cases fail, as they must"* (lines 104-105,
inside the "ALWAYS build" comment explaining why the `.build` cache must never be
skipped). `app/README.md:359-364` restates this with the actual mechanism: *"against the
unpatched vendored tree it fails 6 of 8 cases (exit 1)... against the patched tree all 8
pass (exit 0). Reverting the patch reproduces the failures. A gate that had passed both
ways would have been worth nothing, which is exactly what happened the first time"* —
i.e., the retired `ReflowGateTests` is the documented case of a gate that passed both
ways and was therefore worthless. **I did not personally reproduce the revert-and-fail
experiment this session** (marked INFERRED/relying on the repo's own documentation) —
doing so would require unpinning `vendor/SwiftTerm`, which is out of scope for read-only
research and, in this worktree specifically, `vendor/` does not even exist (confirmed:
both reflow-family scripts exited `2` here for that reason, itself an accidental live
demo of the exit-2 contract firing correctly on a real, present-tense environmental gap).

**check-altbuffer-resize.sh, read directly**: case 3 is explicitly labeled `CONTROL`
(line 192) and its own comment states the property precisely: *"It runs the identical
sequence on the NORMAL buffer, where reflow IS enabled and the trim therefore runs...
what must not happen is a row wider than cols. If this fails too, the harness is
suspect, not the code"* (lines 193-195), and in code: *"the harness is measuring the
wrong thing — do not trust 1 and 2"* (line 213, printed on control failure). The header
confirms falsification: *"Validated by falsification, like check-reflow.sh: reverting
0003 fails cases 1 and 2 and still passes 3 and 4, which is the only reason to believe 4
passes mean anything"* (lines 47-48). Same caveat: not independently reproduced this
session; vendor/ absent in this worktree.

### The design question: what is the equivalent falsification test for a git-status parser gate?

**The disanalogy that must be resolved first.** check-reflow.sh / check-altbuffer-resize.sh
falsify against a *known upstream defect in an existing dependency* — there is a real
"before" (buggy) and "after" (patched) state to diff and re-run against. A git-status
parser is **new first-party code**, not a patched vendor dependency: there is no
upstream bug to revert. The falsification move must therefore be manufactured
deliberately, not discovered. The mechanism that preserves the same evidentiary value —
*a gate proven capable of turning red for a reason that maps to the real defect class*
— is: **write a plausible, specifically-wrong reference implementation first, run the
finished gate against it, observe it fail on exactly the cases that implementation gets
wrong (and nowhere else), then swap in the correct implementation and watch the same
script go green.** The artifact proving this (the wrong implementation's diff, or a
throwaway git stash/branch) belongs in the commit message or PR body the same way
check-reflow.sh's header narrates the retired `ReflowGateTests`' three blindnesses as
its own evidence trail — the failure story IS part of the deliverable, not a discarded
scratch step.

**Concretely, two candidate "naive-parser" bugs, chosen because they are this domain's
version of the exact defect *shapes* already proven to burn this codebase:**

1. **Whitespace-split instead of fixed-field/NUL-delimited parsing** — the git-porcelain
   analogue of the ShellDirectory adversarial-path case. `git status --porcelain=v1`
   quotes and space-delimits in ways a naive `line.split(separator: " ")` gets right for
   `M file.txt` but wrong for a renamed pair (`R  old name.txt -> new name.txt`) or any
   filename containing a space, tab, or the literal `->` substring. The correct
   implementation uses `--porcelain=v2 -z` (NUL-terminated records, no quoting, a fixed
   leading-field grammar, and rename records carrying `ORIG_PATH` as a second
   NUL-terminated segment rather than embedding it in a human-readable arrow). A
   whitespace-split naive parser either drops the renamed-from path silently or
   concatenates the two paths into one bogus string that resolves to no real
   `FileNode` — a UI-invisible failure, precisely the class of bug
   `app/README.md:32-36` says a unit test of pure logic would catch and a human staring
   at the sidebar would not ("the font that silently fell back to Menlo... none of which
   a unit test of pure logic would have caught" — here inverted: this IS the unit-test
   case that catches what eyeballing the sidebar would miss, because a missing
   decoration on one file among hundreds is not something a user notices).
2. **Ignoring the conflicted/unmerged three-mode record shape** — porcelain v2's `u`
   line carries three mode fields (stage 1/2/3) and two object-id fields, structurally
   different from the ordinary `1 xy ...` changed-entry line. A naive parser built only
   against `git add`/`git rm` fixtures (the "boring" case) will silently misparse or
   drop conflicted entries during a merge — arguably the single moment a git sidebar's
   correctness matters most to the user, and the moment least likely to be manually
   re-tested before every commit in a repo with no CI.

**The control case, mapped onto this domain (the direct analogue of check-altbuffer-resize.sh's
case 3):** run the identical assertion table against a **deliberately boring fixture** —
a real, freshly-`git init`'d repo with only plain ASCII-named added/modified/deleted
files, no renames, no conflicts — asserted to pass under **both** the naive and the
correct parser. If the boring fixture ever fails under the *correct* parser, the harness
itself is broken (wrong git invocation, wrong temp-repo setup, wrong assertion), not the
parser, exactly as check-altbuffer-resize.sh's case 3 failing means *"do not trust 1 and
2."* This is the load-bearing shape to copy: **the control's job is to fail only when
the test rig is wrong, and the edge-case assertions' job is to fail only when the
subject is wrong** — a harness bug that broke everything must be visible as "control +
edge cases both red," and a real, localized parser bug must be visible as "control green,
edge cases red." Neither check-reflow.sh nor check-altbuffer-resize.sh achieves this by
counting tokens or by asserting on hand-typed fixture strings; both insist on driving
the *real* subsystem (a real `Terminal`/`Buffer`, a real spawned shell) and reading its
*real* output back — the git-status gate must equally insist on a **real spawned `git`
binary** operating on a **real temporary repository** (`git init`, real file writes,
real `git add`/`git commit`/`git mv` to create renames, a real merge conflict via two
diverging real commits) rather than a hand-authored string claiming to look like
porcelain output — a hand-typed fixture only ever encodes the author's *assumptions*
about the format, which is exactly what a "looks-right-is-wrong" bug hides inside.
This mirrors check-cwd-follow.sh's own methodological insistence, stated of its own `cd`
line assertion: *"Executed, not string-matched: the only question that matters is
whether a real zsh lands in the intended directory, and asserting on the quoting's
shape would pass for any self-consistent wrong answer"* (check-cwd-follow.sh:156-158) —
substitute "a real zsh" for "a real git binary" and the same sentence is the design spec.

**Exit-code contract for the new gate, following the stronger (check-cwd-follow.sh /
check-reflow.sh) form, not the weaker (check-keybindings.sh / check-space-restore.sh)
form identified in §1**: `0` = every case passed; `1` = a real parser assertion failed
(wrap the `swiftc` compile step in an explicit `if ! swiftc ...; then exit 2; fi`, do
not let `set -e` propagate swiftc's native exit code); `2` = environment — no `git`
binary, git version too old for `--porcelain=v2` (a real, checkable possibility, unlike
anything in the existing scripts — worth a `git --version` guard analogous to the
`command -v swiftc` guards already used), `git init` in the temp dir failing, or the
harness failing to compile.

**Summary of the falsification plan, in the order it should actually be executed:**
1. Write the naive (whitespace-split, non-`-z`) parser as a deliberate strawman.
2. Write the full gate script (real `git init` fixtures: boring case + rename case +
   conflict case + special-character-filename case) against that strawman.
3. Observe: boring case green, rename/conflict/special-character cases red — confirms
   the gate can fail, and fails for the *right, specific* reason (not "everything is
   red," which would suggest a harness bug instead).
4. Swap in the correct `-z`/porcelain-v2 fixed-field parser, same unmodified script.
5. Observe: all cases green.
6. Ship the correct parser; keep the red→green transition (steps 3→5) as the commit's
   or PR's evidentiary trail, in the same spirit as check-reflow.sh's header preserving
   the retired ReflowGateTests' specific blindnesses as permanent documentation rather
   than deleting the history of being wrong.

---

## 4. THE STRATEGIC CONFLICT

### What the plans actually say about git/SCM as a feature (quoted, not paraphrased)

Exhaustive search (`grep -in` across all four `.afk/plans/*.md` plus `AFK.md` for
"git status", "git sidebar", "SCM", "source control", "git diff", "git blame", "version
control") returns exactly **one hit that is not a commit-reference or code citation**:

> "Sidebar | Persistent, collapsible to 0, **px-capped** (`SIDEBAR_MAX_WIDTH` 480); holds
> Explorer **or** Source Control, mutually exclusive | `App.tsx:1111-1163`"
> — `native-swift-terminal-afk-host.md:510`

and its neighbor:

> "Tabs | **ONE flat heterogeneous strip**, 8-kind union: Terminal · Editor · Preview ·
> Markdown · AiDiff · GitDiff · GitHistory · GitCommitFileDiff |
> `src/modules/tabs/lib/useTabs.ts:114-122`"
> — `native-swift-terminal-afk-host.md:512`

**Both are descriptive of the competitor `terax-ai`, in a table cataloguing terax's
architecture (§12.1) — neither is a recommendation, endorsement, or roadmap item for
Umber.** The surrounding prose (§12.1-12.4) uses this table to settle a *different*
question (native window tabs vs. a custom document strip) and never revisits the
Explorer/SCM toggle or the Git* tab kinds as something Umber should build. AFK.md's own
"Not Built Yet" section — *"Splits · preferences UI ... shell integration (OSC 7/133) ...
URL clicking · profiles · editor"* — **does not mention git or source control at all**,
confirmed by direct re-read. `next-sequencing-2026-07-28.md`'s proposed sequence
(§3: Tier-0 wave, land research, housekeeping, pick one probe, patch decision) also
**does not mention git as a feature anywhere.**

**The one normative statement that does exist is a boundary, not an endorsement**, and
it cuts the other way from what a sidebar feature needs to worry about:

> "Refuse regardless: Warp-style command blocks..., renderer pools..., a 55-field
> preferences window..., theme editors, 1300 lines of file-icon tables..., LSP, **and
> destructive git operations in a GUI**."
> — `emulator-foundation-probe-and-vendor-integrity.md:208-215`

This refuses *destructive* git operations (commit/push/merge/rebase buttons) inside a
GUI — it does not refuse read-only status display. **Design boundary for this feature**:
a git-status sidebar (colored decorations reflecting `git status`) is squarely inside
what is allowed; the moment the feature grows stage/unstage buttons, a commit box, or
any git-mutating action triggered from the sidebar, it crosses into territory the plan
of record has already, explicitly refused. Scope the feature as read-only.

**Verdict: no plan sequences a git feature anywhere, positively or negatively, beyond
that one boundary.** The honest framing is "unaddressed terrain bounded by one refusal,"
not "the plans want this next" and not "the plans forbid this."

### Blast radius against the libghostty probe — named file sets, not vague claims

The plan of record's next commitment (`.afk/plans/emulator-foundation-probe-and-vendor-integrity.md`
§5 Step 1, refined by `.afk/plans/libghostty-swap-sequencing-2026-07-28.md` Phases 1-6)
is timeboxed at *"Add libghostty-spm; write GhosttyPane: SpaceDocument alongside — not
instead of — TerminalPane"* (`emulator-foundation-probe-and-vendor-integrity.md:190-191`),
gated behind an operator go/no-go (`libghostty-swap-sequencing-2026-07-28.md:39-49`,
*"Question: does losing ⌘F on the primary daily driver for an estimated 2-4 days clear
the bar? This is not an agent decision"*) that has **not yet been answered** (doc status
line: *"Phase 0 open (operator decision)"*).

Files the libghostty plan names, gathered by exhaustive `grep` across
`emulator-foundation-probe-and-vendor-integrity.md` and cross-checked against
`libghostty-swap-sequencing-2026-07-28.md`: `Buffer.swift` (vendor), `TerminalViewSearch.swift`
(vendor), `AppDelegate.swift`, `SpaceDocument.swift`, `SpaceViewController.swift`,
`SpaceViewController+Delegates.swift`, `ShellHosting.swift`, `TerminalPane.swift`,
`UmberTerminalView.swift`, `KeyBindings.swift` (chord-collision re-verification only,
read-only), plus new files `GhosttyPane.swift` + `GhosttyPane+Document.swift`
(`libghostty-swap-sequencing-2026-07-28.md:129-131`, explicitly planned as *new* files
"following the FileViewerPane precedent," not edits to an existing file), and
`Package.swift`.

A git-status sidebar's most likely touch set (§2 above, marked INFERRED since the
feature doesn't exist yet): a new `GitStatusParser.swift`, a new
`check-git-status.sh`, a new poller file (`SpaceViewController+GitStatus.swift` or
standalone `GitStatusService.swift`), small additive hooks in `FileNode.swift` (carry a
status enum) and `FileTreeViewController+OutlineView.swift` (render a decoration glyph),
and — only if the sidebar needs a second, mutually-exclusive pane a la terax's
Explorer/SCM toggle — a small change to `SpaceViewController.swift`'s
`NSSplitViewItem` wiring (the region at `SpaceViewController.swift:60-105`, which
constructs `fileTree` and the `sidebarItem`).

**The one file named on both lists is `SpaceViewController.swift`** — but the concerns
are disjoint *regions* of that file, verified by direct inspection: libghostty's Phase 1
(already landed — confirmed via `git log`: commit `4cdbbea`,
*"refactor(app): widen the document delegate and give shell-directed actions their own
protocol — the container stops naming a concrete pane (#14)"*) touched the
**document/pane plumbing** (`addTerminalDocument`, `add(document:)`,
`focusedTerminalPane`/`ShellHosting`, per
`libghostty-swap-sequencing-2026-07-28.md:53-84`'s own site table) — none of which
overlaps the **sidebar-construction** region (`SpaceViewController.swift:60-105`, the
`fileTree`/`NSSplitViewItem` init code a git-sidebar would touch). Confirmed live: Phase 1
is **done** (its own gate section says *"remains the only conformer... fully verifiable
by check-keybindings.sh + check-file-size.sh + make-app-bundle.sh"*, already satisfied),
and the **remaining, still-gated** libghostty phases (2 through 6) are explicitly scoped
to *new* files: *"Plan for two files from the start... TerminalPane.swift carries this
surface at 339/350 lines. GhosttyPane will land in the same territory, so split it on
arrival"* (`libghostty-swap-sequencing-2026-07-28.md:129-131`), and separately,
`emulator-foundation-probe-and-vendor-integrity.md:105-106`: *"`TerminalPane.swift` split
(339/350). Does NOT gate libghostty — GhosttyPane is a new file. It gates only edits to
TerminalPane itself."* **No remaining libghostty phase is documented as touching
`SpaceViewController.swift` again.**

**The real, non-architectural friction is the 350-line ceiling, not the libghostty
probe.** `check-file-size.sh`, run live this session, reports
`SpaceViewController.swift` at **345/350** — 5 lines of slack, in the WARN band — a fact
already flagged in this repo's own file table (*"⚠ 5 lines from the ceiling — the next
concern to arrive here gets its own file, like `+DirectoryFollow` did"*). If a
git-sidebar toggle needs even a handful of lines in `SpaceViewController.swift`, it will
almost certainly need to pull a concern out first (the established, precedented move —
`+DirectoryFollow` did exactly this for cwd-follow) — but this constraint exists
**independent of libghostty entirely**; it would bind identically whether or not the
probe existed, and it does not bind the *parser*, the *poller*, or the *check script*,
which are all clean new files.

### Verdict

**Orthogonal, with one shared-but-disjoint-region file and a pre-existing, unrelated
ceiling constraint — not a conflict.** Non-overlapping file sets: the entire
parser/poller/gate-script surface (`GitStatusParser.swift`, `check-git-status.sh`, the
poller file, `FileNode.swift`, `FileTreeViewController+OutlineView.swift`) shares zero
files with anything the libghostty plan names or has touched. The one nominal overlap
(`SpaceViewController.swift`) is a different region of the same file, already resolved
for libghostty's Phase 1 (done, merged) and explicitly not scoped for its remaining
phases (new files only). The plans express no opinion endorsing or sequencing a git
feature, and exactly one boundary (no destructive git GUI actions) that a read-only
status sidebar does not cross. Building this now does not block, invalidate, or get
complicated by the pending 2-day libghostty probe; the only design tax is the
already-standing, feature-independent 350-line ceiling on `SpaceViewController.swift`,
which the design in §2 avoids by construction (new files for every gated concern).
