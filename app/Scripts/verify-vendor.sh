#!/bin/bash
#
# Verify the vendored SwiftTerm copy is the revision this app was built against,
# WITH its two local patches applied.
#
# Why this exists: vendor/ is gitignored (.gitignore:13), vendor/SwiftTerm is not a
# git repo, app/Package.swift:20 is an unpinned `.package(path:)`, and
# Package.resolved is ignored too. So nothing in git recorded either the upstream
# revision or the local patches. That made the two failure modes asymmetric:
#
#   * missing vendor/            -> loud (SwiftPM cannot resolve the path dependency)
#   * re-vendored, UNPATCHED     -> SILENT (compiles and runs; patch 0001 only drops
#                                   a build-time resource, so nothing complains)
#
# Following app/README.md's recreation steps but forgetting a patch therefore
# produced a green build against a different dependency than the tested one. This
# script makes that case loud. It is called first by make-app-bundle.sh.
#
# Patch 0002 (Buffer.swift, the #494 reflow fix) raised the stakes, which is why the
# Buffer.swift check below is a HARD FAILURE and not the warning it was until
# 2026-07-29. A tree missing 0002 compiles, runs, passes every other check, and
# silently CORRUPTS SCROLLBACK on every window narrowing — the same silent-failure
# asymmetry this script was written to kill, in its worst form yet. Warn-only would
# have meant the one check that can catch it printing to stderr and exiting 0.
#
# Usage:
#   ./Scripts/verify-vendor.sh            # verify, print one OK line
#   ./Scripts/verify-vendor.sh --quiet    # verify, print nothing on success
#
# Exit codes:
#   0  vendored tree matches the pin
#   1  vendor/ missing, or pin/patch files missing
#   2  present but UNPATCHED (the silent case this script exists to catch) —
#      either Package.swift is missing patch 0001, or Buffer.swift is missing 0002
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
PATCH="$REPO_ROOT/patches/swiftterm/0001-exclude-metal-shader-from-target.patch"
PATCH_REFLOW="$REPO_ROOT/patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch"

say() { [[ "$QUIET" == "1" ]] || echo "$@"; }
err() { echo "$@" >&2; }

# `key = value` out of the pin, tolerating surrounding whitespace. Comments start
# with # and are skipped by the anchored key match.
pin_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$PIN" | head -1 | tr -d '[:space:]'
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# --- the pin and patch themselves must be present ------------------------------
for required in "$PIN" "$PATCH" "$PATCH_REFLOW"; do
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
  err "Recreate it (SPM checkouts are read-only, hence the chmod):"
  err "  git clone --depth 1 --branch $UPSTREAM_TAG $UPSTREAM_REPO vendor/SwiftTerm"
  err "  chmod -R u+w vendor/SwiftTerm"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0001-exclude-metal-shader-from-target.patch"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch"
  err ""
  err "BOTH patches are required. 0002 fixes SwiftTerm #494 (scrollback corruption on"
  err "narrowing); app/Scripts/check-reflow.sh is what proves it applied."
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
  err "This is the silent-failure case verify-vendor.sh exists to catch: the tree"
  err "compiles and runs, but the Metal shader is compiled as a resource, which"
  err "fails on machines without the Metal toolchain component (Xcode 26.6 moved it"
  err "to \`xcodebuild -downloadComponent MetalToolchain\`)."
  err ""
  err "Apply the patch:"
  err "  patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0001-exclude-metal-shader-from-target.patch"
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
  err ""
  err "Then prove it took (fails 6 of 8 cases unpatched, passes all 8 patched):"
  err "  cd app && ./Scripts/check-reflow.sh"
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
  err "_yBase defect still exists at lines 1171/1211, re-apply or retire patch 0002, run"
  err "  cd app && ./Scripts/check-reflow.sh"
  err "and only then regenerate the pin:"
  err "  shasum -a 256 vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift"
  err "  # then update patched_buffer_swift in patches/swiftterm/SwiftTerm.pin"
  exit 3
fi

say "==> vendor OK: SwiftTerm $UPSTREAM_TAG (${UPSTREAM_COMMIT:0:7}) + 2 local patches"
