#!/bin/bash
#
# Verify the vendored SwiftTerm copy is the revision this app was built against,
# WITH its local patch applied.
#
# Why this exists: vendor/ is gitignored (.gitignore:13), vendor/SwiftTerm is not a
# git repo, app/Package.swift:20 is an unpinned `.package(path:)`, and
# Package.resolved is ignored too. So nothing in git recorded either the upstream
# revision or the local patch. That made the two failure modes asymmetric:
#
#   * missing vendor/            -> loud (SwiftPM cannot resolve the path dependency)
#   * re-vendored, UNPATCHED     -> SILENT (compiles and runs; the patch only drops
#                                   a build-time resource, so nothing complains)
#
# Following app/README.md's recreation steps but forgetting the patch therefore
# produced a green build against a different dependency than the tested one. This
# script makes that case loud. It is called first by make-app-bundle.sh.
#
# Usage:
#   ./Scripts/verify-vendor.sh            # verify, print one OK line
#   ./Scripts/verify-vendor.sh --quiet    # verify, print nothing on success
#
# Exit codes:
#   0  vendored tree matches the pin
#   1  vendor/ missing, or pin/patch files missing
#   2  present but UNPATCHED (the silent case this script exists to catch)
#   3  present but hash matches neither patched nor upstream (unknown revision)
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

say() { [[ "$QUIET" == "1" ]] || echo "$@"; }
err() { echo "$@" >&2; }

# `key = value` out of the pin, tolerating surrounding whitespace. Comments start
# with # and are skipped by the anchored key match.
pin_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$PIN" | head -1 | tr -d '[:space:]'
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# --- the pin and patch themselves must be present ------------------------------
for required in "$PIN" "$PATCH"; do
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
WANT_BUFFER="$(pin_value buffer_swift)"

# --- vendor/ present? ----------------------------------------------------------
if [[ ! -d "$VENDOR" ]]; then
  err "error: vendor/SwiftTerm is missing."
  err ""
  err "Recreate it (SPM checkouts are read-only, hence the chmod):"
  err "  git clone --depth 1 --branch $UPSTREAM_TAG $UPSTREAM_REPO vendor/SwiftTerm"
  err "  chmod -R u+w vendor/SwiftTerm"
  err "  git -C vendor/SwiftTerm apply --directory=. \\"
  err "      ../../patches/swiftterm/0001-exclude-metal-shader-from-target.patch"
  err ""
  err "Or without git: patch -p1 -d vendor/SwiftTerm < patches/swiftterm/0001-*.patch"
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

# --- version tripwire ----------------------------------------------------------
# Buffer.swift is unmodified upstream and must stay that way while the reflow fork
# (plan option A) is unchosen. It carries the confirmed #494 defect of record at
# lines 1171/1211, so a change here invalidates what the plan and AFK.md claim
# about that bug. Warn rather than fail: a deliberate SwiftTerm upgrade should not
# be blocked by this script, only noticed.
BUFFER="$VENDOR/Sources/SwiftTerm/Buffer.swift"
if [[ -f "$BUFFER" ]]; then
  GOT_BUFFER="$(sha256_of "$BUFFER")"
  if [[ "$GOT_BUFFER" != "$WANT_BUFFER" ]]; then
    err "warning: vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift changed from the pin."
    err "         Re-check whether the #494 _yBase defect still exists at lines"
    err "         1171/1211 before trusting AFK.md or the plan on reflow, then update"
    err "         buffer_swift in patches/swiftterm/SwiftTerm.pin."
  fi
fi

say "==> vendor OK: SwiftTerm $UPSTREAM_TAG (${UPSTREAM_COMMIT:0:7}) + 1 local patch"
