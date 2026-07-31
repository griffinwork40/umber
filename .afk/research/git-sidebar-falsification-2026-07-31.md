# The git-status gate, falsified

**Date:** 2026-07-31 · **Gate:** `app/Scripts/check-git-status.sh` (+ its extracted harness)

Why this file exists: a gate that has only ever been green is not evidence. The reflow
gates falsify by reverting a vendor patch (`check-reflow.sh` fails 6/8 without `0002`,
`check-altbuffer-resize.sh` 2/4 without `0003`), but `GitStatus.swift` is new first-party
code with no upstream bug to revert, so the counterexample had to be manufactured —
`.afk/research/git-sidebar-local-verification-2026-07-31.md` §3 specifies the procedure and
this file is its result.

## The strawman

Three deliberate defects installed in `GitStatus.parse`, each the naive-but-plausible
reading of the format, and each one the research named in advance:

1. **The rename record's second NUL token is not consumed** — `2` records treated as one
   token like every other record.
2. **The unmerged `u` record is parsed with the ordinary `1` record's field offsets** —
   path read at token 8 instead of token 10.
3. **Fixed fields whitespace-split with no `maxSplits`** — so a path containing a space is
   truncated at its first one.

The gate script itself was **not modified** between the two runs below.

## Red — the naive parser

```
CONTROL — a boring repo any parser should manage          (6/6 green)
RENAME — the two-token record
  ✗ original path is recorded on the entry   [nil]
PATHS — spaces, quotes, and non-ASCII bytes
  ✗ space + ' + $ + backtick survives verbatim   [keys=[]]
ROLLUP — ancestors of a change                            (5/5 green)
BRANCH — head, and ahead/behind that may not exist         (4/4 green)
CONFLICT — the u record
  ✗ conflicted file is present   [keys=["351be5bf6e17c59ea560546d69654115ecb2fd8d e45c9c2666d44e0327c1f9c239a74c508336053e c.txt"]]
  ✗ conflicted file is .conflicted   [nil]
DISCOVERY — including the worktree landmine                (7/7 green)
RELATIVE PATHS                                            (4/4 green)
DEGENERATE INPUT — must not trap                          (4/4 green)
4 check(s) failed
exit 1
```

## Green — the shipped parser

```
all checks passed
exit 0
```

## Why this is the *right* red, not just red

- **The control case stayed fully green.** That is the load-bearing observation, and it is
  the check the retired `ReflowGateTests` never had. A harness bug would have shown up as
  "control + edge cases both red", and its verdict would have to be discarded. Control
  green + edge cases red localises the fault to the subject.
- **Each red case names its own defect.** The conflict key
  `"351be5bf… e45c9c26… c.txt"` is the field-offset bug made visible: the path field
  absorbed two stage SHAs because a `u` record has three modes and three hashes where a
  `1` record has three and two. No token count or "is it non-empty" assertion would have
  caught that — the entry exists, it is simply keyed by garbage, and it would have
  silently failed to match any `FileNode` in the tree.
- **The emoji case passed under the strawman, and that is correct.** `café-😀.txt` has no
  space, so whitespace-splitting does not damage it; only the `-z` flag matters there, and
  the strawman kept `-z`. A gate where *every* case flips on *every* defect is not
  discriminating between defects.
- **Exit was 1, not 2.** A real assertion failure, correctly distinguished from an
  environmental one — the distinction `check-keybindings.sh` and `check-space-restore.sh`
  cannot make at all.
