#!/bin/bash
#
# Assert the Space-restore persistence layer keeps its promises.
#
# Same technique as check-keybindings.sh, and for the same reason: this app has no
# test target, and `OpenSpaceRoots` is a near-pure function of (stored strings,
# what exists on disk) — so instead of standing up XCTest, compile the SHIPPED
# Sources/Umber/Defaults.swift together with a throwaway harness and run a truth
# table. Nothing is stubbed or restated: a change to the real store shows up here.
#
# The compiled unit was Sources/Umber/Config.swift until 2026-07-28, when the
# 350-LOC ceiling split the UserDefaults stores out into Defaults.swift. Only the
# file name moved; `OpenSpaceRoots` itself is unchanged, which is why all 12 cases
# below are untouched.
#
# Why this script exists at all: restore is the one feature whose payoff is only
# observable ACROSS a quit/relaunch boundary, which no headless check can drive.
# The window/tab half genuinely cannot be verified here (see the PR body) — but the
# half that decides *what* comes back is ordinary logic, and leaving it unverified
# because its sibling is untestable would be the worse trade. In particular the
# fail-soft cases below are the ones that would otherwise only be discovered by a
# user whose app opened to nothing.
#
# Runs against a temp directory and its own defaults domain, NOT
# com.griffinlong.umber: a check that trashed your real remembered Spaces would be
# a bad check. The last assertion proves that isolation held.
#
# Usage: ./Scripts/check-space-restore.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# No SwiftTerm prebuild any more. Config.swift imported it for `CursorStyle` and
# the `Color` conversion, so compiling that file dragged in the whole module and
# its object file; Defaults.swift imports only AppKit, because a UserDefaults store
# has no business knowing about the emulator. That is a property worth keeping — it
# is what lets this check run without building SwiftTerm at all. If a future edit
# makes this script need `-I .build/out/Products/Debug` again, the store has grown
# a dependency it should not have.

cat > "$TMP/main.swift" <<'SWIFT'
import AppKit

var failures = 0

func check(_ label: String, _ got: [String], _ expect: [String]) {
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(label)")
    if !ok {
        print("    expected \(expect)")
        print("    got      \(got)")
    }
}

let fm = FileManager.default
let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("umber-restore-check-\(getpid())")

func dir(_ name: String) -> URL {
    let url = sandbox.appendingPathComponent(name)
    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let alpha = dir("alpha"), beta = dir("beta"), gamma = dir("gamma")
/// Never created — stands in for a project deleted between launches.
let deleted = sandbox.appendingPathComponent("deleted-project")

func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

// The base case: tab order is the point. Restoring the right roots in the wrong
// order rearranges the user's tab bar on every launch.
OpenSpaceRoots.urls = [alpha, beta, gamma]
check("round-trips in tab order", names(OpenSpaceRoots.urls), ["alpha", "beta", "gamma"])

// Checked, not trusted — the LastSpaceRoot rule applied per element. A root that
// is gone would otherwise open a Space onto an empty tree with no explanation.
OpenSpaceRoots.urls = [alpha, beta, deleted, gamma]
check("drops a deleted root, keeps the rest", names(OpenSpaceRoots.urls), ["alpha", "beta", "gamma"])

// isDirectory is not incidental: a project directory replaced by a file of the
// same name passes fileExists() alone.
let asFile = sandbox.appendingPathComponent("was-a-directory")
try? "not a directory".write(to: asFile, atomically: true, encoding: .utf8)
OpenSpaceRoots.urls = [alpha, asFile]
check("rejects a file where a directory was", names(OpenSpaceRoots.urls), ["alpha"])

// Two Spaces on one root rebuild the indistinguishable pair openFolder's dedupe
// explicitly refuses to create.
OpenSpaceRoots.urls = [alpha, beta, alpha, beta, gamma]
check("collapses duplicate roots", names(OpenSpaceRoots.urls), ["alpha", "beta", "gamma"])

// /tmp vs /private/tmp, or any symlinked checkout, must not read as two roots.
let link = sandbox.appendingPathComponent("alpha-symlink")
try? fm.createSymbolicLink(at: link, withDestinationURL: alpha)
OpenSpaceRoots.urls = [alpha, link, beta]
check("a symlink to a root is not a second root", names(OpenSpaceRoots.urls), ["alpha", "beta"])

// Overflow must drop the LEFTMOST tabs and keep order — each Space costs a login
// shell, and scrambling the survivors would be worse than capping.
let many = (1...20).map { dir("p\($0)") }
OpenSpaceRoots.urls = many
let capped = OpenSpaceRoots.urls
check(
    "caps at limit, keeping the most recent in order",
    [String(capped.count), capped.first?.lastPathComponent ?? "-", capped.last?.lastPathComponent ?? "-"],
    [String(OpenSpaceRoots.limit), "p\(20 - OpenSpaceRoots.limit + 1)", "p20"])

// Closing your last Space is you saying you are done; the next launch should be
// one fresh Space, not a resurrection.
OpenSpaceRoots.urls = []
check("an empty list stays empty", OpenSpaceRoots.urls.map(\.path), [])

// The both-empty-cases path AppDelegate.restoreSpaces() depends on: a list whose
// every entry is gone has to read as "nothing to restore", not as N dead Spaces.
OpenSpaceRoots.urls = [deleted]
check("every-root-deleted reads as empty", OpenSpaceRoots.urls.map(\.path), [])

// Fail-soft, the AppConfig.load() contract applied to persistence. A key someone
// hand-edited (or a future version wrote differently) must degrade to a working
// app, not trap on launch — stringArray(forKey:) returns nil for a non-array.
let key = "Umber.openSpaceRoots"
UserDefaults.standard.set("a-bare-string", forKey: key)
check("a string where an array belongs degrades to empty", OpenSpaceRoots.urls.map(\.path), [])
UserDefaults.standard.set(42, forKey: key)
check("a number where an array belongs degrades to empty", OpenSpaceRoots.urls.map(\.path), [])
UserDefaults.standard.set([1, 2, 3], forKey: key)
check("an array of non-strings degrades to empty", OpenSpaceRoots.urls.map(\.path), [])

UserDefaults.standard.removeObject(forKey: key)

// The check must not have touched the real app's remembered Spaces. A bundle-less
// binary gets its own defaults domain, so this asserts that assumption rather
// than trusting it.
let realDomain = UserDefaults(suiteName: "com.griffinlong.umber")
check(
    "the real com.griffinlong.umber domain was not written",
    [realDomain?.stringArray(forKey: key) == nil ? "clean" : "POLLUTED"],
    ["clean"])

try? fm.removeItem(at: sandbox)

print("")
print(failures == 0 ? "all checks passed" : "\(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -o "$TMP/harness" \
  Sources/Umber/Defaults.swift "$TMP/main.swift" \
  -framework AppKit

"$TMP/harness"
