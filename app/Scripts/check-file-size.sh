#!/usr/bin/env bash
#
# check-file-size.sh — the 350-LOC ceiling, mechanically.
#
# The rule (set 2026-07-28): no source file exceeds 350 lines. The reason is not
# aesthetic. This repo has no test target and no CI (see ../README.md, "Checks"),
# so the only things that keep it correct are a human reading a diff and an AI
# agent reading a whole file into context before editing it. A 550-line AppKit
# file costs an agent most of a working context just to establish what it may
# safely touch, and the failure mode is silent: the agent edits from a partial
# read. Small single-purpose files are the affordance that makes the codebase
# maintainable by an agent at all — so the ceiling is a build gate, not a habit.
#
# 350 is deliberately generous. It is above every natural AppKit unit in this
# app (a view controller, a delegate conformance, a drawing routine) and below
# the size at which a file starts owning two unrelated concerns. If a file is
# pushing the limit, that is the signal to find its seam — not to raise the
# limit.
#
# WARN_AT gives early warning at 90% so drift surfaces on the commit that starts
# it rather than the one that breaks the build.
#
# Scope note: source only — Swift, shell, Python. Prose is deliberately exempt.
# ../../.afk/plans/*.md run 500-600 lines each and are single arguments meant to
# be read start to finish; splitting a plan to satisfy a code rule would destroy
# the thing that makes it useful. The ceiling is about context cost per edit,
# and nobody edits a plan doc under compile pressure.
#
# Usage:
#   ./Scripts/check-file-size.sh            # 350-line ceiling, from app/
#   LIMIT=400 ./Scripts/check-file-size.sh  # override for a one-off audit
#
# Exit codes: 0 = every file within the ceiling, 1 = at least one over.

set -euo pipefail

# Run from app/ regardless of where the caller invoked us, so the paths printed
# below are stable and copy-pasteable.
cd "$(dirname "$0")/.."

LIMIT="${LIMIT:-350}"
WARN_AT=$(( LIMIT * 90 / 100 ))

# Sources/ and Scripts/ only. vendor/ is upstream SwiftTerm — thousands of lines
# we do not own and must not reformat (see README.md, "Dependency note"), and it
# lives outside app/ anyway. Resources/ holds generated binary assets whose line
# counts are meaningless.
files=$(find Sources Scripts -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.py' \) | sort)

violations=0
warnings=0

printf '%6s  %s\n' "LOC" "FILE"
printf '%6s  %s\n' "-----" "----"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  n=$(wc -l < "$file" | tr -d ' ')

  if [ "$n" -gt "$LIMIT" ]; then
    printf '%6d  %s  ✗ over by %d\n' "$n" "$file" "$(( n - LIMIT ))"
    violations=$(( violations + 1 ))
  elif [ "$n" -ge "$WARN_AT" ]; then
    printf '%6d  %s  ⚠ within %d of the ceiling\n' "$n" "$file" "$(( LIMIT - n ))"
    warnings=$(( warnings + 1 ))
  else
    printf '%6d  %s\n' "$n" "$file"
  fi
done <<< "$files"

echo
total=$(echo "$files" | grep -c . || true)

if [ "$violations" -gt 0 ]; then
  echo "FAIL: $violations of $total source files exceed the ${LIMIT}-line ceiling."
  echo
  echo "Fix by finding the file's seam, not by raising LIMIT: pull one whole"
  echo "concern into a new file (a delegate conformance, a model type, a drawing"
  echo "routine, a UserDefaults store) and give it a header comment saying what"
  echo "it owns. Then update the file table in ../AFK.md so the map stays true."
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  echo "OK: all $total source files within the ${LIMIT}-line ceiling ($warnings approaching it)."
else
  echo "OK: all $total source files within the ${LIMIT}-line ceiling."
fi
