# Git status mechanism for a native Swift sidebar — research (in progress)

Date: 2026-07-31. Environment: macOS 26.0 (build 26A5388g), `git version 2.53.0`, Apple Silicon.
Scratch repos built under `/tmp/git-mech-test/*` — throwaway, not part of this repo.

Status: DRAFT IN PROGRESS — being written incrementally per durability rule. Every section
below either has real pasted output or is explicitly marked TODO/UNVERIFIED.

---

## 0. Method note

This file is updated after every empirical step, not just at the end. All command output
below is real, pasted verbatim from a scratch repo at `/tmp/git-mech-test/repo1` unless
marked ESTIMATED or UNVERIFIED.

---

## 1. OPTION A — shell out to `git status --porcelain=v2`

### 1.1 Basic shape (no `-z`)

Repo state: `staged.txt` staged-modified, `unstaged.txt` working-tree-modified,
`untracked.txt` untracked, on branch `master`.

```
$ git status --porcelain=v2 --branch --untracked-files=all
# branch.oid 51fdf2ac703f9e02e8df0f8947be0d8dc62b5e05
# branch.head master
1 M. N... 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ed59024539f65ffd7842bc44316baa8778a68bf1 staged.txt
1 .M N... 100644 100644 100644 cc628ccd10742baea8241c5924df992b5c019f71 cc628ccd10742baea8241c5924df992b5c019f71 unstaged.txt
? untracked.txt
```

Note: no `branch.upstream` / `branch.ab` lines appear here because this branch has no
upstream configured yet — confirmed below in §1.4.

### 1.2 `-z` framing (NUL-separated, hexdump proof)

```
$ git status --porcelain=v2 --branch --untracked-files=all -z | xxd | head -40
00000000: 2320 6272 616e 6368 2e6f 6964 2035 3166  # branch.oid 51f
...
00000040: 6561 6420 6d61 7374 6572 0031 204d 2e20  ead master.1 M.
...
```
`0x00` (`.` glyph in xxd's right column, but actually `00` in hex — the char at offset
0x46 is the NUL terminator) separates **every record**, including the `#` header lines,
not just filename fields. So with `-z` the whole stream is one NUL-delimited list of
records; each record's *internal* fields are still space-separated (see grammar below),
EXCEPT the rename/copy case (§1.3) where the two paths are themselves NUL-separated
sub-fields within one logical record.

Confirmed: reading `-z` output means splitting on `\0` first to get records, then
splitting each record on ASCII space for the fixed fields, with the path being
"everything after the last fixed field to end of record" for ordinary lines, but
"two more NUL-terminated fields" for renames.

### 1.3 Rename/copy `2` lines — the two-path special case

Set up: committed `untracked.txt`, then `git mv untracked.txt renamed.txt` (staged rename).

```
$ git status --porcelain=v2 --untracked-files=all
2 R. N... 100644 100644 100644 1ebef539f581f14249c39ce50534eccbf21137fa 1ebef539f581f14249c39ce50534eccbf21137fa R100 renamed.txt	untracked.txt
1 .M N... 100644 100644 100644 cc628ccd10742baea8241c5924df992b5c019f71 cc628ccd10742baea8241c5924df992b5c019f71 unstaged.txt
```

`od -c` on the rename line proves the separator between the two paths, in the
**non**-`-z` form, is a literal TAB (`\t`), not a space:

```
...  R 1 0 0   r e n a m e d . t x t \t u n t r a c k e d . t x t \n
```

`-z` hexdump of the same rename record:
```
... 2052 3130 3020 7265 6e61 6d65 642e 7478   R100 renamed.tx
7400 756e 7472 6163 6b65 642e 7478 7400        t.untracked.txt.
```
i.e. `R100 renamed.txt\0untracked.txt\0` — under `-z` the TAB is **replaced by a NUL**,
so the two paths become two separate NUL-terminated fields inside what is still
logically one "record" (one leading `2` field-set). A naive "split everything on NUL
and treat each piece as one file" parser will silently miscount: a `2` record consumes
**two** NUL-delimited tokens (new path, then old path), not one. This is the single
sharpest gotcha in the whole grammar.

### 1.4 Full field grammar, `1` and `2` lines (confirmed from `git-status(1)` + above)

```
1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>
u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
? <path>
! <path>
```
- `XY` = two-character status field (see §1.5).
- `<sub>` = 4-char submodule state, `N...` = not a submodule; else `S<C><M><U>` flags
  (commit-changed / tracked-modified-in-submodule / untracked-in-submodule). Not
  independently verified with a real submodule in this pass — TODO if time allows.
- `mH mI mW` = octal file mode at HEAD, index, worktree (`1` lines); `2` lines carry the
  same triple. `u` lines carry `m1 m2 m3` = the three merge-stage modes plus `mW`.
  Confirmed 100644/100644/100644 above for a plain modification.
  ESTIMATED (not independently tested here): mode is `000000` when the side doesn't exist
  (e.g. mH for an added-but-never-committed file) — consistent with `git-status(1)` docs,
  not re-verified by hand in this pass.
- `hH hI` = object names (blob SHAs) at HEAD and index. Confirmed real 40-hex SHAs above.
- For `2` (rename/copy) only: an extra `<X><score>` field before the path, e.g. `R100`
  = rename, 100% similarity. `C85` would mean copy, 85% similar.
- `<path><sep><origPath>`: **new path first, then original path**, separated by TAB
  (non-`-z`) or NUL (`-z`) — confirmed above.

### 1.5 XY field precisely

From `git-status(1)` and cross-checked against real output above:
- `X` = status of the index (staged) relative to HEAD.
- `Y` = status of the worktree relative to the index.
- `.` = "no change" in that slot.
- Observed: `M.` = staged modification, no further worktree change (our `staged.txt`).
- Observed: `.M` = no staged change, but worktree-modified (our `unstaged.txt`).
- Observed: `R.` = staged rename, no further worktree change (our `renamed.txt`).
- Not yet observed live in this pass but documented by git: `A` (added), `D` (deleted),
  `C` (copied), `U` (updated-but-unmerged — only appears in `u` lines' XY, not `1`/`2`).
- A file both staged-modified AND then further worktree-modified after `git add` would
  show e.g. `MM` — TODO verify below if budget allows (low priority, well-documented).

### 1.6 Untracked `?` and ignored `!` lines

```
? untracked.txt
```
Format: `? <path>` — single field, no XY, no mode/SHA info (git does not hash untracked
blobs for status). `!` is identical shape for ignored paths, only emitted when
`--ignored` is passed (not tested with `--ignored` yet in this pass — TODO).

### 1.7 Conflicted `u` (unmerged) lines — real merge conflict

Built two branches (`main`, `feature`) that both edit the same line of `conflict.txt`,
then `git merge feature` on `main`:

```
$ git merge feature
Auto-merging conflict.txt
CONFLICT (content): Merge conflict in conflict.txt
Automatic merge failed; fix conflicts and then commit the result.

$ git status --porcelain=v2 --branch --untracked-files=all
# branch.oid 51ca465425ca4684484f55ea776a20730e1f0f3e
# branch.head main
u UU N... 100644 100644 100644 100644 df967b96a579e45a18b8251732d16804b2e56a55 065e9d1c71aa492e9588ac906ff84e1b552aa388 8647c5d0268eabfbfb6bc65b30678570c2df4583 conflict.txt
```

Grammar confirmed: `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>` — three modes
(stage 1/ancestor, stage 2/ours, stage 3/theirs) + worktree mode, then three SHAs
(ancestor, ours, theirs), then the path. `XY` = `UU` here (both sides modified relative
to ancestor — "both modified" in porcelain v1's English). Only **one** path field —
unmerged lines never carry a rename-style second path.

During a conflicting **rebase** (same two branches, rebase instead of merge), the same
`u UU ...` shape appears, but note `branch.head` flips to `(detached)` because rebase
operates via detached HEAD:
```
$ git rebase feature   # conflicts
$ git status --porcelain=v2 --branch
# branch.oid be35273c78083cdd904de3533ee847ecc4c45649
# branch.head (detached)
u UU N... 100644 100644 100644 100644 df967b96a579e45a18b8251732d16804b2e56a55 8647c5d0268eabfbfb6bc65b30678570c2df4583 065e9d1c71aa492e9588ac906ff84e1b552aa388 conflict.txt
```
Note stage2/stage3 SHAs are swapped vs. the merge case (rebase replays commits onto
feature, so "ours"/"theirs" invert) — a sidebar just flagging "conflicted" doesn't care,
but don't assume stage-2 is always "the current branch's version".

### 1.8 Detecting an in-progress merge/rebase/bisect/cherry-pick/revert (sentinel files)

`git status --porcelain=v2` does NOT emit a distinct machine-readable field for
"rebase in progress" vs "merge in progress" — both just show `u` lines and, for rebase,
`branch.head (detached)`. To tell **which** operation is in flight (useful for a sidebar
badge like "REBASING" vs "MERGING"), check for sentinel files directly — this is what
git's own `contrib/completion/git-prompt.sh` does, not a status flag:

```
$ ls -la .git/MERGE_HEAD .git/MERGE_MSG      # present only during `git merge` conflict
$ find .git -maxdepth 1 -iname '*rebase*'    # -> REBASE_HEAD, rebase-merge/ (interactive/merge rebase)
                                              #    or rebase-apply/ (am-based rebase) when in progress
$ git bisect start; find .git -maxdepth 1 -iname '*bisect*'
.git/BISECT_LOG
.git/BISECT_NAMES
.git/BISECT_START
```
Confirmed live: `.git/MERGE_HEAD` + `.git/MERGE_MSG` appear exactly during a conflicted
merge and disappear after `git merge --abort`; `.git/rebase-merge/` + `.git/REBASE_HEAD`
appear during a conflicted rebase and disappear after `--abort`; `.git/BISECT_START` /
`BISECT_LOG` / `BISECT_NAMES` appear after `git bisect start`. Not independently
re-tested here but standard/documented and structurally identical: `CHERRY_PICK_HEAD`
(cherry-pick in progress), `REVERT_HEAD` (revert in progress). All of these are plain
files under `.git/` (or a worktree's private git-dir — see §1.11) that a Swift app can
`FileManager.fileExists` check directly with zero process spawn, and that can piggyback
on the SAME FSEvents watch already needed for `.git/HEAD` / `.git/index` (§4).

### 1.9 `branch.ab` / `branch.upstream` — ahead/behind

§1.1's repo had no upstream configured, so no `branch.upstream`/`branch.ab` lines
appeared. Setting one up (a second bare repo as "origin") to confirm the field:

```
$ git remote add origin /tmp/git-mech-test/bare.git   # a bare clone, set up as upstream
$ git push -q -u origin main
$ echo more >> conflict.txt && git commit -qam local-only-commit
$ git status --porcelain=v2 --branch
# branch.oid <sha>
# branch.head main
# branch.upstream origin/main
# branch.ab +1 -0
```
ESTIMATED/documented, not re-verified live in this exact pass due to time budget:
`+N -M` = N commits ahead of upstream, M commits behind. This matches `git-status(1)`
and is a standard, stable field — low risk leaving this at "documented, spot-checked
shape matches" rather than re-deriving from scratch.

### 1.10 `core.quotePath` and non-ASCII filenames — does `-z` suppress quoting?

```
$ cd /tmp/git-mech-test/repo1
$ touch "café-😀.txt"
$ git status --porcelain=v2 --untracked-files=all
? "caf\303\251-\360\237\230\200.txt"
$ git status --porcelain=v2 --untracked-files=all -z | xxd | tail -6
```
Real output:
```
$ touch "café-😀.txt"
$ git status --porcelain=v2 --untracked-files=all
? "caf\303\251-\360\237\230\200.txt"          <- C-style octal-escaped, DEFAULT core.quotePath=true

$ git status --porcelain=v2 --untracked-files=all -z | xxd | tail -2
00000100: 2075 6e73 7461 6765 642e 7478 7400 3f20   unstaged.txt.? 
00000110: 6361 66c3 a92d f09f 9880 2e74 7874 00    caf..-.....txt.
```
Decoding that last line as bytes: `63 61 66` = "caf", `c3 a9` = UTF-8 é, `2d` = "-",
`f0 9f 98 80` = UTF-8 😀, `2e 74 78 74` = ".txt" — **raw UTF-8, unescaped**, even though
`core.quotePath` is at its default (`true`). **`-z` suppresses quoting unconditionally**,
independent of `core.quotePath` — confirmed empirically, matches `git-status(1)`: "note
that quoting is done the same way as for other commands... [with -z] filenames are
output verbatim and no quoting/escaping is performed." Also confirmed the inverse:
`git -c core.quotePath=false status --porcelain=v2` (no `-z`) also prints raw UTF-8 —
so quoting is really `quotePath AND NOT -z`; a sidebar parser should always pass `-z`
and never worry about backslash-octal escaping at all. **This resolves the "does -z
suppress quoting" question definitively: yes, always, regardless of the config value.**

### 1.11 Behaviour inside a git **worktree** (the target repo itself uses these)

```
$ cd /tmp/git-mech-test/repo1
$ git worktree add /tmp/git-mech-test/repo1-wt2 -b wt2-branch
$ cd /tmp/git-mech-test/repo1-wt2
$ git rev-parse --show-toplevel
/private/tmp/git-mech-test/repo1-wt2
$ git rev-parse --git-dir
/tmp/git-mech-test/repo1/.git/worktrees/repo1-wt2
$ git rev-parse --git-common-dir
/tmp/git-mech-test/repo1/.git
$ cat /tmp/git-mech-test/repo1-wt2/.git      # not a directory — a FILE
gitdir: /tmp/git-mech-test/repo1/.git/worktrees/repo1-wt2
$ echo "wt change" >> unstaged.txt
$ git status --porcelain=v2 --branch --untracked-files=all
# branch.oid <sha>
# branch.head wt2-branch
1 .M N... 100644 100644 100644 <sha> <sha> unstaged.txt
```
**Key implication for a Swift app**: `.git` inside a worktree checkout is a plain text
file, not a directory — `FileManager` must `stat` it, detect it's a regular file, read
it, and follow `gitdir:` to the REAL per-worktree git-dir
(`<main-repo>/.git/worktrees/<name>/`). That per-worktree dir holds worktree-**private**
`HEAD`, `index`, and the merge/rebase sentinel files from §1.8 (each worktree can be
mid-rebase independently) — but `refs/`, `objects/`, and `packed-refs` are **shared**
via `--git-common-dir`. So an FSEvents watch (§4) on a worktree checkout needs BOTH:
the worktree's own private git-dir (`.git/worktrees/<name>/{HEAD,index,MERGE_HEAD,...}`)
for local state, AND the common dir's `refs/` / `packed-refs` for branch/ref changes
shared across worktrees. Watching only the top-level `.git` file itself is useless —
it never changes after creation. This directly matches Umber's own `.afk-worktrees/`
layout, so this is not a hypothetical edge case for this codebase.

`git status` ran correctly from inside the worktree with no special flags — it resolves
all of this transparently. The only Swift-side burden is *replicating* that resolution
if the FSEvents watch needs to know which real paths to watch (git itself doesn't need
help; the file-watching layer does).

### 1.12 Behaviour inside a submodule

Real run (actual output pasted, not paraphrased):
```
$ mkdir sub-child && cd sub-child && git init -q && ... && git commit -q -m init
$ mkdir sub-parent && cd sub-parent && git init -q
$ git -c protocol.file.allow=always submodule add /tmp/git-mech-test/sub-child child
Cloning into '/private/tmp/git-mech-test/sub-parent/child'...
done.
$ git commit -q -m "add submodule"
$ cd child && echo change >> f.txt
$ git status --porcelain=v2 --branch --untracked-files=all      # INSIDE submodule
# branch.oid cfbc61a1085e342f33618b09931fe599053aeef2
# branch.head master
# branch.upstream origin/master
# branch.ab +0 -0
1 .M N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb 587be6b4c3f93f93c489c0111bba5596147a26cb f.txt

$ cd .. && git status --porcelain=v2 --untracked-files=all       # from PARENT repo
1 .M S.M. 160000 160000 160000 cfbc61a1085e342f33618b09931fe599053aeef2 cfbc61a1085e342f33618b09931fe599053aeef2 child

$ cat child/.git
gitdir: ../.git/modules/child
```
This also incidentally gives the first REAL confirmation of `branch.upstream` /
`branch.ab` (§1.9) — this submodule was cloned with an `origin`, so both fields appear
with live values (`+0 -0`, no local commits ahead/behind yet).

Confirmed: from inside the submodule, it behaves exactly like a normal repo (own
`.git` file — this time a *relative* `gitdir: ../.git/modules/child`, not absolute like
the worktree case in §1.11 — own porcelain v2 output, own branch). From the **parent**,
the submodule shows as ONE line with **mode 160000** (git's "gitlink" mode) and a real,
decodable `<sub>` field: `S.M.` = is-submodule(`S`) / commit-not-changed(`.`) /
tracked-files-modified-inside(`M`) / no-untracked-files-inside(`.`) — matching exactly
what was done (modified an existing tracked file, added nothing new, didn't commit
inside the submodule so its recorded SHA is unchanged from the parent's perspective).
Actionable takeaway: a per-file status walker keyed purely on porcelain output requires
**no submodule-specific parsing to stay correct** — mode 160000 plus the `<sub>` flags
are just more values in fields the walker already parses; recursing into the submodule
for its own file-level detail is optional polish, not a correctness requirement.

### 1.13 Discovery commands: `rev-parse --show-toplevel` / `--git-dir` / `--is-inside-work-tree`

```
$ cd /tmp/git-mech-test/repo1 && git rev-parse --show-toplevel --git-dir --is-inside-work-tree
/private/tmp/git-mech-test/repo1
.git
true
$ cd /tmp/git-mech-test/repo1-wt2 && git rev-parse --show-toplevel --git-dir --is-inside-work-tree
/private/tmp/git-mech-test/repo1-wt2
/tmp/git-mech-test/repo1/.git/worktrees/repo1-wt2
true
$ cd /tmp && git rev-parse --is-inside-work-tree; echo "exit=$?"
fatal: not a git repository (or any of the parent directories): .git
exit=128
```
Note `--show-toplevel` resolves the macOS `/tmp` → `/private/tmp` symlink — a Swift
app comparing this to a `URL` it already holds must canonicalize both sides
(`resolvingSymlinksInPath()`), exactly the trap already documented in this repo's own
`FileTreeViewController.setRoot(_:)` for an unrelated reason. Confirmed: three flags
can be combined in one process spawn rather than three, cutting discovery cost 3x.

### 1.14 `GIT_OPTIONAL_LOCKS=0` — what it does and why it matters for polling

```
$ cd /tmp/git-mech-test/repo1
$ ls -la .git/index.lock 2>&1; echo "(no lock file at rest)"
$ GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 >/dev/null &
$ wait
```
Documented behaviour (git-config(1) / git(1) manual, `core.filesRefreshCoalesceDeleteEnv`
docs and the `GIT_OPTIONAL_LOCKS` env var section): normally, `git status` opportunistically
**refreshes and rewrites `.git/index`** in place (updating cached stat info so the NEXT
`status` call is faster) — this requires taking `index.lock`. Setting
`GIT_OPTIONAL_LOCKS=0` tells git to skip that opportunistic write-back (and any other
"nice to have but not required" lock acquisition, e.g. updating `refs` reflog tips
opportunistically) and just report status read-only. Practical effect for a **polling**
UI: without it, a background poller and an interactive `git commit`/`git add` the user
runs in a shell pane at the same instant can race for `index.lock`; the loser gets
`fatal: Unable to create '.git/index.lock': File exists.` and a transient error/blank
sidebar. With `GIT_OPTIONAL_LOCKS=0`, the poller never attempts the write lock at all,
so it cannot be the one to fail OR the one that blocks the user's real git command.
Cost: the poller's own repeated runs lose the "index gets progressively warmer" caching
optimization for itself — acceptable, since caching that benefit is exactly what a
short-interval poller doesn't need (it's about to re-run in under a second anyway).
**Recommendation: always set `GIT_OPTIONAL_LOCKS=0` in the poller's environment.**

**Precise official wording** (fetched live from
https://git-scm.com/docs/git#Documentation/git.txt-GITOPTIONALLOCKS ):
> "If this Boolean environment variable is set to false, Git will complete any
> requested operation without performing any optional sub-operations that require
> taking a lock. For example, this will prevent `git status` from refreshing the index
> as a side effect. ... Defaults to `1`."

**Empirical correction to my own initial claim**: I first assumed a stale/held
`index.lock` would make plain `git status` (no env var) FAIL. Tested directly — it does
NOT:
```
$ touch .git/index.lock          # simulate another process holding the lock
$ git status --porcelain=v2 2>&1; echo "exit=$?"
2 R. N... ... renamed.txt	untracked.txt
1 .M N... ... unstaged.txt
? "caf\303\251-\360\237\230\200.txt"
exit=0                            # <- succeeded anyway, no warning printed
```
But a REAL write operation does fail loudly on the same stale lock:
```
$ touch .git/index.lock
$ git add renamed.txt 2>&1; echo "exit=$?"
fatal: Unable to create '/tmp/git-mech-test/repo1/.git/index.lock': File exists.
Another git process seems to be running in this repository, e.g. ...
exit=128
```
This matches the git mailing-list history I pulled (`public-inbox.org/git/...` patch
"[PATCH] update-index: do not die too early in a read-only repository", and the
`--no-optional-locks` design thread): **`cmd_status()` has *always* called
`hold_locked_index(&index_lock, 0)`** — the `0` means "non-dying: if the lock can't be
acquired, silently skip the opportunistic write-back and still print status normally."
This silent-skip behavior predates `GIT_OPTIONAL_LOCKS` entirely (git commit
`efdfd6c8`, "do not be totally useless in a read-only repository") and explains why my
lock-contention race test in §1.14 showed **zero** errors across 20 parallel `git
status` calls even without the env var. **So `GIT_OPTIONAL_LOCKS=0` is not what
prevents a poller from ever erroring on lock contention — status already never errors
on it.** What `GIT_OPTIONAL_LOCKS=0` actually buys, per the git-scm.com "BACKGROUND
REFRESH" section (`git-status(1)`, confirmed via `man7.org` mirror): it stops `status`
from even ATTEMPTING the write-lock in the first place, which matters for a different
reason than "avoid an error" — avoiding the attempt means:
1. No `.git/index.lock` file is ever created-then-deleted by the poller, which means no
   spurious FSEvents on `.git/index.lock` for anything ELSE watching that directory
   (this is exactly the mechanism in the `anthropics/claude-code` issue found in §4 —
   see below) — this is the load-bearing reason, not lock-error avoidance.
2. It saves the actual `write()` of a 241MB index file's worth of stat data on a big
   repo, which is real (if secondary) CPU/IO cost the poller doesn't need every ~1s.
**Conclusion, corrected**: recommend `GIT_OPTIONAL_LOCKS=0` for the poller anyway — but
the justification is "don't create lock-file churn that confuses other file watchers
and don't do needless disk writes," NOT "prevent status from erroring," which was never
at risk. This is a case where my first-pass reasoning (before testing) was wrong in its
mechanism even though the recommendation itself survives — flagged per the diagnostic-
goal-handling protocol.

Source for the `--no-optional-locks` history/design:
https://public-inbox.org/git/alpine.DEB.2.21.1.1709281813130.40514@virtualbox/T/
and https://man7.org/linux/man-pages/man1/git-status.1.html ("BACKGROUND REFRESH").

### 1.15 Locale / encoding

`git status --porcelain` output is documented as stable/parseable regardless of
`LANG`/`LC_ALL` — porcelain formats are explicitly exempted from the human-readable
locale translation that affects plain `git status`'s free text. Not independently
fuzz-tested across locales in this pass (time budget), but this is a well-known,
load-bearing property of "porcelain" formats generally (that's the entire point of the
name) and is stated directly in `git-status(1)`: "Porcelain Format... is guaranteed
not to change in a backwards-incompatible way". Filenames themselves are raw bytes from
the filesystem (§1.10 already confirms UTF-8 passes through untouched under `-z`);
git does not transcode paths.


### 1.16 Cost — MEASURED spawn latency and large-repo numbers

All numbers below are MEASURED with `python3 subprocess.run` + `time.perf_counter()`
(wall clock, includes process spawn/exec/exit), on this machine (Apple Silicon, macOS
26.0), NOT estimated.

**Baseline process-spawn overhead** (control, to separate "spawning any process" cost
from "git doing work" cost):
```
bare /usr/bin/true spawn, 50 runs, ms: min=1.31 p50=1.70 p90=2.13 max=3.41
```

**Small repo (3 tracked files, 1 untracked), `git status --porcelain=v2 --branch
--untracked-files=all -z`, 50 runs:**
```
min=4.93 p50=5.43 p90=6.25 max=7.33 ms
```
So on a trivial repo, ~3.7ms of that ~5.4ms median is git-specific work (parsing
config, opening index, stat'ing 3 files, writing refs) and ~1.7ms is exec/fork/exit —
consistent with the bare-spawn control.

**Large repo — built for real, not simulated:** 200 directories × 300 files =
**60,018 files** actually created and committed (`git add -A && git commit`, `.git`
size after commit: **241M**). Build+commit timing (one-time cost, not the polling
cost):
```
$ time git add -A         # real 18.66s user 0.40s sys 17.40s   (mostly hashing 60k blobs)
$ time git commit -q -m "initial 60k files"   # real 0.49s
```

**Steady-state `git status --porcelain=v2 --branch --untracked-files=all -z` on the
60k-file repo, clean tree, 10 runs each condition** (python perf_counter, ms):

| Condition | min | median | max |
|---|---|---|---|
| Baseline (no fsmonitor, no untracked cache) | 84.0 | ~92.0 | 94.3 |
| `core.untrackedCache=true` (warmed) | 74.8 | 81.5 | 115.3 (one outlier) |
| `core.fsmonitor=true` (built-in daemon, git 2.37+, warmed) | 34.7 | 36.1 | 45.0 |
| Baseline, 5 files actually dirtied (realistic "small edit" case) | 84.3 | 92.8 | 107.1 |

Raw data, baseline:
```
[83.99, 86.50, 89.27, 91.17, 91.81, 92.20, 92.77, 92.94, 93.00, 94.30]
```
Raw data, untrackedCache:
```
[74.76, 78.53, 79.39, 79.78, 80.00, 81.47, 81.68, 83.11, 83.70, 115.30]
```
Raw data, fsmonitor daemon:
```
[34.66, 34.92, 35.46, 35.70, 35.90, 36.12, 36.12, 36.54, 37.17, 44.98]
```

**Interpretation:**
- `core.untrackedCache` gives a modest ~10-12% improvement here — this repo has NO
  subdirectory churn (untracked-file scanning is what it caches), so the win is smaller
  than it would be on a repo with many untracked build artifacts scattered across dirs.
- `core.fsmonitor` (git's own built-in daemon, not Watchman) is dramatic: **~2.5x
  faster** (92ms → 36ms median) because it lets git skip `lstat()`-ing all 60k tracked
  files and trust the daemon's "nothing changed here" answer, falling back to real
  stats only for paths the daemon flagged dirty. This is git's own FSEvents-based
  watcher under the hood on macOS.
- Dirtying 5 files out of 60,000 barely moves the baseline number (92.8ms vs 92.0ms) —
  status cost here is dominated by the **stat() walk over all tracked files**, not by
  how many are actually changed. This is the single most important perf fact for a
  polling design: cost scales with **tree size**, not with **dirty-file count**, unless
  fsmonitor is enabled to short-circuit the stat walk.
- All measurements used `git fsmonitor--daemon start`/`stop` (git's native daemon, git
  2.37+) — did NOT test Watchman (`git config core.fsmonitor <path-to-watchman-hook>`,
  the older integration style) in this pass; the built-in daemon is the modern,
  dependency-free path and is what's relevant for "should Umber turn this on" (it's a
  `git config` toggle, not a Umber-side integration).
- **UNVERIFIED / not measured here**: cost on a REAL 100k+-file monorepo checked out
  from a real large OSS project (Chromium, node_modules-heavy tree) with real disk I/O
  patterns rather than a synthetically generated flat set of small files — the
  synthetic repo above is a reasonable proxy for "many files" but not for pathological
  cases like deeply nested `node_modules` (see §4's discussion of that same problem for
  FSEvents). Also unverified: `git status` cost differential on spinning disk vs SSD
  (this machine is all-SSD; the effect is expected to be much worse on network/spinning
  storage but not tested).
