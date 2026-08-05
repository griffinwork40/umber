#!/bin/bash
#
# Verify the vendored SwiftTerm copy is the revision this app was built against,
# WITH its four local patches applied.
#
# Why this exists: vendor/ is gitignored (.gitignore:13), vendor/SwiftTerm is not a
# git repo, app/Package.swift:20 is an unpinned `.package(path:)`, and
# Package.resolved is ignored too. So nothing in git recorded either the upstream
# revision or the local patches. That made the two failure modes asymmetric:
#
#   * missing vendor/            -> loud (SwiftPM cannot resolve the path dependency)
#   * re-vendored, UNPATCHED     -> depends which patch is missing, and only one of the
#                                   two is loud:
#       - 0001 missing  -> LOUD. Upstream's `.process` on Shaders.metal needs the offline
#                          Metal toolchain, so the build dies at `unable to spawn process
#                          'metal'`. (This was silent until 2026-07-31, when 0001 stopped
#                          being an `exclude:` and became a `.copy` resource.)
#       - 0002/3/4 missing -> SILENT. Compiles, runs, and corrupts the buffer or ships a
#                          release-build abort(). This is the case that matters.
#
# Following app/README.md's recreation steps but forgetting a patch therefore
# produced a green build against a different dependency than the tested one. This
# script makes that case loud. It is called first by make-app-bundle.sh.
#
# The Buffer.swift patches raised the stakes, which is why the Buffer.swift check
# below is a HARD FAILURE and not the warning it was until 2026-07-29. A tree missing
# them compiles, runs, passes every other check, and silently CORRUPTS THE BUFFER:
# without 0002 (#494) reflow mangles SCROLLBACK on every window narrowing; without 0003
# the ALT buffer resurrects stale cells on every widening, which under tmux is content
# bleeding across pane and window boundaries. Same silent-failure asymmetry this script
# was written to kill, in its worst form yet. Warn-only would have meant the one check
# that can catch it printing to stderr and exiting 0.
# All THREE Buffer.swift patches (0002, 0003, 0004) touch the SAME file, so the pin carries
# ONE combined hash: a tree with only some of them matches neither the patched nor the
# upstream hash and lands in the exit-3 "unknown" branch, which is the intended outcome —
# half-patched is not a state this project supports. That is also why 0004 needs no check of
# its own: unlike 0002 and 0003 its absence corrupts nothing (it only restores a per-resize
# scrollback walk and a release-build `abort()`), but it still cannot pass, because the
# combined hash will not match. See the pin's own note on 0004.
#
# Usage:
#   ./Scripts/verify-vendor.sh            # verify, print one OK line
#   ./Scripts/verify-vendor.sh --quiet    # verify, print nothing on success
#
# Exit codes:
#   0  vendored tree matches the pin
#   1  vendor/ missing, or pin/patch files missing
#   2  present but UNPATCHED (the silent case this script exists to catch) —
#      either Package.swift is missing patch 0001, or Buffer.swift is missing 0002/0003/0004
#   3  present but a hash matches neither patched nor upstream (unknown revision)
#
set -euo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

# Scripts/ lives in app/; the vendored copy and its patches are at the repo root.
cd "$(dirname "$0")/.."
APP_ROOT="$(pwd)"
REPO_ROOT="$(cd .. && pwd)"

VENDOR="$REPO_ROOT/vendor/SwiftTerm"
PIN="$REPO_ROOT/patches/swiftterm/SwiftTerm.pin"
PATCH="$REPO_ROOT/patches/swiftterm/0001-ship-metal-shader-as-copy-resource.patch"
PATCH_REFLOW="$REPO_ROOT/patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch"
PATCH_ALTSIZE="$REPO_ROOT/patches/swiftterm/0003-trim-lines-on-narrowing-for-all-buffers.patch"
PATCH_DEBUGGATE="$REPO_ROOT/patches/swiftterm/0004-gate-resize-post-condition-behind-debug.patch"

say() { [[ "$QUIET" == "1" ]] || echo "$@"; }
err() { echo "$@" >&2; }

# `key = value` out of the pin, tolerating surrounding whitespace. Comments start
# with # and are skipped by the anchored key match.
pin_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$PIN" | head -1 | tr -d '[:space:]'
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# --- the pin and patch themselves must be present ------------------------------
for required in "$PIN" "$PATCH" "$PATCH_REFLOW" "$PATCH_ALTSIZE" "$PATCH_DEBUGGATE"; do
  if [[ ! -f "$required" ]]; then
    err "error: missing ${required#$REPO_ROOT/}"
    err "       The vendor pin is part of the build contract; do not delete it."
    exit 1
  fi
done

UPSTREAM_REPO="$(pin_value upstream_repo)"
UPSTREAM_TAG="$(pin_value upstream_tag)"
UPSTREAM_COMMIT="$(pin_value upstream_commit)"
WANT_PATCHED="$(pin_value patched_package_swift)"
WANT_UPSTREAM="$(pin_value upstream_package_swift)"
WANT_BUFFER="$(pin_value patched_buffer_swift)"
WANT_BUFFER_UPSTREAM="$(pin_value upstream_buffer_swift)"

# --- vendor/ present? ----------------------------------------------------------
if [[ ! -d "$VENDOR" ]]; then
  err "error: vendor/SwiftTerm is missing."
  err ""
  err "Recreate it:"
  err "  ./Scripts/bootstrap-vendor.sh"
  err ""
  err "That clones $UPSTREAM_TAG, applies all four patches in order, and re-runs this"
  err "check for the verdict. app/README.md documents the manual equivalent if you"
  err "would rather see the steps than trust a script."
  err ""
  err "ALL FOUR patches are required. 0002 fixes SwiftTerm #494 (scrollback corruption on"
  err "narrowing), 0003 fixes the alt-buffer resize defect (stale cells bleeding across tmux"
  err "panes on widening), and 0004 stops an upstream debug assertion from walking the whole"
  err "scrollback and calling abort() in RELEASE builds on every resize; check-reflow.sh and"
  err "check-altbuffer-resize.sh are what prove 0002 and 0003 applied."
  exit 1
fi

if [[ ! -f "$VENDOR/Package.swift" ]]; then
  err "error: vendor/SwiftTerm exists but has no Package.swift — incomplete checkout."
  exit 1
fi

# --- the load-bearing check: is the patch applied? -----------------------------
GOT_PACKAGE="$(sha256_of "$VENDOR/Package.swift")"

if [[ "$GOT_PACKAGE" == "$WANT_UPSTREAM" ]]; then
  err "error: vendor/SwiftTerm is UNPATCHED upstream $UPSTREAM_TAG."
  err ""
  err "Upstream declares Shaders.metal as \`.process\`, which invokes the offline Metal"
  err "compiler. Xcode 26.6 moved that toolchain to a downloadable component"
  err "(\`xcodebuild -downloadComponent MetalToolchain\`), so on a Command Line Tools"
  err "machine the build dies at \`unable to spawn process 'metal'\`. 0001 makes it a"
  err "\`.copy\` instead: the shader ships as source and MetalTerminalRenderer compiles"
  err "it at runtime, which needs no toolchain. Without 0001 you get no build at all;"
  err "with the OLD exclude-based 0001 you got a build with no reachable GPU renderer."
  err ""
  err "Apply the patch:"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0001-ship-metal-shader-as-copy-resource.patch"
  exit 2
fi

if [[ "$GOT_PACKAGE" != "$WANT_PATCHED" ]]; then
  err "error: vendor/SwiftTerm/Package.swift matches neither the pinned patched hash"
  err "       nor upstream $UPSTREAM_TAG. The vendored copy is an unknown revision."
  err ""
  err "  expected (patched): $WANT_PATCHED"
  err "  found:              $GOT_PACKAGE"
  err ""
  err "If you deliberately re-vendored or edited the patch, regenerate the pin:"
  err "  shasum -a 256 vendor/SwiftTerm/Package.swift"
  err "  # then update patched_package_swift in patches/swiftterm/SwiftTerm.pin"
  exit 3
fi

# --- the second load-bearing check: is the reflow patch applied? ----------------
# Same logic as Package.swift above, deliberately mirrored. Buffer.swift carries a
# REQUIRED patch (0002) that fixes the #494 _yBase defect at lines 1171/1211, so
# "changed from the pin" is no longer a curiosity to warn about — an unpatched
# Buffer.swift is a broken build that looks healthy.
BUFFER="$VENDOR/Sources/SwiftTerm/Buffer.swift"
if [[ ! -f "$BUFFER" ]]; then
  err "error: vendor/SwiftTerm has no Sources/SwiftTerm/Buffer.swift — incomplete checkout."
  exit 1
fi

GOT_BUFFER="$(sha256_of "$BUFFER")"

if [[ "$GOT_BUFFER" == "$WANT_BUFFER_UPSTREAM" ]]; then
  err "error: vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift is UNPATCHED upstream $UPSTREAM_TAG."
  err ""
  err "This tree will COMPILE, RUN, and SILENTLY CORRUPT SCROLLBACK. SwiftTerm #494:"
  err "lines 1171/1211 set \`_lines[_y].isWrapped\` with a SCREEN-relative index while"
  err "the adjacent content writes at 1176/1224 use the BUFFER-absolute"
  err "\`_lines[_y + _yBase]\`, so with non-empty scrollback the wrapped-line flag lands"
  err "on the wrong row and reflow joins/splits unrelated history on every narrowing."
  err ""
  err "Apply the patch:"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0003-trim-lines-on-narrowing-for-all-buffers.patch"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0004-gate-resize-post-condition-behind-debug.patch"
  err ""
  err "Then prove they took (each gate was validated by falsification):"
  err "  cd app && ./Scripts/check-reflow.sh            # 6 of 8 fail without 0002"
  err "  cd app && ./Scripts/check-altbuffer-resize.sh  # 2 of 4 fail without 0003"
  exit 2
fi

if [[ "$GOT_BUFFER" != "$WANT_BUFFER" ]]; then
  err "error: vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift matches neither the pinned"
  err "       patched hash nor upstream $UPSTREAM_TAG. The vendored copy is unknown."
  err ""
  err "  expected (patched): $WANT_BUFFER"
  err "  found:              $GOT_BUFFER"
  err ""
  err "If you deliberately re-vendored or upgraded SwiftTerm: re-check whether the #494"
  err "_yBase defect still exists at lines 1171/1211, whether the line-trim loop is still"
  err "inside 'if isReflowEnabled' near line 522, and whether the '// DEBUG: Post-condition'"
  err "loop after it is still ungated, re-apply or retire 0002/0003/0004, run BOTH gates"
  err "  cd app && ./Scripts/check-reflow.sh && ./Scripts/check-altbuffer-resize.sh"
  err "and only then regenerate the pin:"
  err "  shasum -a 256 vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift"
  err "  # then update patched_buffer_swift in patches/swiftterm/SwiftTerm.pin"
  exit 3
fi

say "==> vendor OK: SwiftTerm $UPSTREAM_TAG (${UPSTREAM_COMMIT:0:7}) + 4 local patches"
