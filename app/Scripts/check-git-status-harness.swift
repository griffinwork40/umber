//
//  check-git-status-harness.swift
//  The assertion half of Scripts/check-git-status.sh.
//
//  Not part of the app: `Package.swift` globs `Sources/Umber` only, so nothing here is
//  ever linked into Umber. `check-git-status.sh` copies this file to `main.swift` in its
//  temp dir and compiles it against the two shipped sources under test.
//
//  WHY IT IS NOT A HEREDOC, unlike every other check script's harness. The shell half
//  plus this Swift came to 358 lines in one file, over `check-file-size.sh`'s 350-line
//  ceiling, and AFK.md's rule for that is explicit: find the seam and pull one whole
//  concern out — never shave comments, never raise LIMIT. The seam was already here and
//  is a clean one: the shell builds real repositories with real git, and this file makes
//  assertions about what the parser saw in them. Splitting on it also buys something a
//  heredoc cannot — this is real Swift that a formatter and an editor can both read,
//  where `<<'SWIFT'` swallows every syntax error silently until swiftc finally runs.
//
//  It must be COPIED to `main.swift` rather than compiled under its own name: Swift
//  allows top-level statements only in a file literally called main.swift, and this
//  harness is top-level code driving real subprocesses.
//
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ✓ " : "  ✗ ") + name + (detail.isEmpty ? "" : "   [\(detail)]"))
    if !ok { failures += 1 }
}

let work = ProcessInfo.processInfo.environment["GIT_GATE_WORK"] ?? ""
guard !work.isEmpty else { print("ENV: GIT_GATE_WORK unset"); exit(2) }
func fixture(_ name: String) -> URL { URL(fileURLWithPath: work + "/" + name) }

func snapshot(_ name: String) -> (GitRepository, GitStatusSnapshot)? {
    guard let repo = GitStatusReader.discoverRepository(at: fixture(name)),
          let snap = GitStatusReader.snapshot(of: repo) else { return nil }
    return (repo, snap)
}

guard let (plainRepo, plain) = snapshot("plain") else {
    print("ENV: could not read the plain fixture at all"); exit(2)
}

let weird = "sp ace's $weird`one.txt"
let emoji = "café-😀.txt"

// CONTROL. Boring ASCII add/modify/delete/untracked, no renames, no conflicts, no
// non-ASCII. Its job is the same as check-altbuffer-resize.sh's control case (:192-195):
// it must pass under a DELIBERATELY NAIVE parser too. If the control ever goes red
// alongside the edge cases, the rig is measuring the wrong thing and the whole run's
// verdict must be discarded rather than read as a real defect.
print("CONTROL — a boring repo any parser should manage")
check("modified file is .modified", plain.entries["control-mod.txt"]?.status == .modified,
      String(describing: plain.entries["control-mod.txt"]?.status))
check("deleted file is .deleted", plain.entries["control-del.txt"]?.status == .deleted)
check("untracked file is .untracked", plain.entries["control-new.txt"]?.status == .untracked)
check("staged add is .added and isStaged", plain.entries["staged-add.txt"]?.status == .added
      && plain.entries["staged-add.txt"]?.isStaged == true)
check("unmodified file gets no entry", plain.entries["control-keep.txt"] == nil)
check("worktree-only edit is not staged", plain.entries["control-mod.txt"]?.isStaged == false)

// THE RENAME RECORD — the single sharpest edge in the grammar. Under -z the TAB between
// the new and original path becomes a NUL, so one logical record spans TWO tokens. A
// parser that splits the blob on NUL and treats each piece as a record reads
// `rename-src.txt` as a record of its own; because every record is self-describing it
// does not cascade loudly, it just invents one path and drops another.
print("RENAME — the two-token record")
check("new path is present and .renamed", plain.entries["rename-dst.txt"]?.status == .renamed,
      String(describing: plain.entries["rename-dst.txt"]?.status))
check("original path is recorded on the entry",
      plain.entries["rename-dst.txt"]?.originalPath == "rename-src.txt",
      plain.entries["rename-dst.txt"]?.originalPath ?? "nil")
check("original path did NOT leak in as its own entry",
      plain.entries["rename-src.txt"] == nil,
      String(describing: plain.entries["rename-src.txt"]))
check("rename is staged (git mv writes the index)",
      plain.entries["rename-dst.txt"]?.isStaged == true)

// ADVERSARIAL PATHS — what -z buys. Without it these arrive C-octal-quoted (or not,
// depending on core.quotePath), and a parser that splits fixed fields on whitespace
// truncates the first one at its first space.
print("PATHS — spaces, quotes, and non-ASCII bytes")
check("space + ' + $ + backtick survives verbatim", plain.entries[weird]?.status == .modified,
      "keys=\(plain.entries.keys.filter { $0.contains("weird") })")
check("emoji filename survives verbatim", plain.entries[emoji]?.status == .modified,
      "keys=\(plain.entries.keys.filter { $0.contains("caf") })")
check("no key arrived octal-escaped",
      !plain.entries.keys.contains { $0.contains("\\3") || $0.hasPrefix("\"") })

// DIRECTORY ROLLUP — the outline view cannot walk children to answer a parent's
// decoration, because FileNode.children is nil for an unexpanded directory
// (FileNode.swift:97). So the snapshot must roll up eagerly.
print("ROLLUP — ancestors of a change")
check("immediate parent inherits", plain.directories["nested/deep"] == .modified,
      String(describing: plain.directories["nested/deep"]))
check("grandparent inherits too", plain.directories["nested"] == .modified)
check("a clean sibling directory gets nothing", plain.directories["not-a-dir"] == nil)
check("deleted does NOT roll up to its parent", plain.directories["doomed"] == nil,
      String(describing: plain.directories["doomed"]))
check("status(forRelativePath:) answers files and dirs through one call",
      plain.status(forRelativePath: "nested") == .modified
      && plain.status(forRelativePath: "control-mod.txt") == .modified
      && plain.status(forRelativePath: "control-keep.txt") == nil)

// BRANCH HEADERS. The absent-not-zero case is the one that breaks on exactly the
// freshly-created local branches an agent workflow produces constantly.
print("BRANCH — head, and ahead/behind that may not exist")
check("branch.head is parsed", plain.branch != nil && plain.isDetached == false,
      plain.branch ?? "nil")
check("no upstream -> ahead/behind are nil, NOT zero",
      plain.ahead == nil && plain.behind == nil,
      "ahead=\(String(describing: plain.ahead)) behind=\(String(describing: plain.behind))")
if let (_, upstream) = snapshot("upstream") {
    check("with an upstream, ahead/behind are parsed",
          upstream.ahead == 2 && upstream.behind == 0,
          "ahead=\(String(describing: upstream.ahead)) behind=\(String(describing: upstream.behind))")
} else {
    print("  ✗ upstream fixture unreadable"); failures += 1
}
if let (_, detached) = snapshot("detached") {
    check("detached HEAD -> isDetached, branch nil",
          detached.isDetached && detached.branch == nil, detached.branch ?? "nil")
} else {
    print("  ✗ detached fixture unreadable"); failures += 1
}

// UNMERGED RECORDS have a different field count than ordinary ones (three stage modes
// and three stage hashes, so the path is token 10 not 8). A parser reusing the ordinary
// layout silently drops every conflicted file — at the single moment a git sidebar's
// correctness matters most, and the moment least likely to be manually re-checked.
print("CONFLICT — the u record")
if let (_, conflicted) = snapshot("conflicted") {
    check("conflicted file is present", conflicted.entries["c.txt"] != nil,
          "keys=\(Array(conflicted.entries.keys))")
    check("conflicted file is .conflicted", conflicted.entries["c.txt"]?.status == .conflicted,
          String(describing: conflicted.entries["c.txt"]?.status))
    check("conflict outranks everything in a rollup",
          GitFileStatus.conflicted.rollupPrecedence < GitFileStatus.modified.rollupPrecedence)
} else {
    print("  ✗ conflicted fixture unreadable"); failures += 1
}

// DISCOVERY. The bug this replaces would have passed every manual test from an ordinary
// clone and failed on every worktree, including Umber's own development checkout.
print("DISCOVERY — including the worktree landmine")
check("plain repo root is found", plainRepo.root.lastPathComponent == "plain",
      plainRepo.root.path)
check("in an ordinary clone, git-dir == common-dir",
      plainRepo.gitDirectory == plainRepo.commonDirectory,
      "\(plainRepo.gitDirectory.path) vs \(plainRepo.commonDirectory.path)")
if let subRepo = GitStatusReader.discoverRepository(at: fixture("plain/nested/deep")) {
    check("discovery from a subdirectory finds the same root", subRepo.root == plainRepo.root,
          subRepo.root.path)
} else {
    print("  ✗ discovery from a subdirectory returned nil"); failures += 1
}
if let linked = GitStatusReader.discoverRepository(at: fixture("linked")) {
    // `.git` here is an ASCII file containing `gitdir:`, which is why `test -d .git` is
    // the wrong question. Asserted, not assumed — if git ever changes this, the fixture
    // builder refuses first.
    check("a linked worktree IS recognised as a repo", linked.root.lastPathComponent == "linked",
          linked.root.path)
    check("in a worktree, git-dir != common-dir (a watcher needs BOTH)",
          linked.gitDirectory != linked.commonDirectory,
          "\(linked.gitDirectory.path) vs \(linked.commonDirectory.path)")
    check("the worktree's common-dir is the main repo's git dir",
          linked.commonDirectory == plainRepo.commonDirectory,
          linked.commonDirectory.path)
} else {
    print("  ✗ a linked worktree was not recognised as a repository"); failures += 1
}
check("a plain directory is not a repo",
      GitStatusReader.discoverRepository(at: fixture("notrepo")) == nil)
check("a subdirectory of a plain directory is not a repo either",
      GitStatusReader.discoverRepository(at: fixture("notrepo/sub")) == nil)

print("RELATIVE PATHS — how a tree node finds its decoration")
check("a file inside the repo resolves",
      plainRepo.relativePath(for: fixture("plain/nested/deep/buried.txt"))
          == "nested/deep/buried.txt",
      plainRepo.relativePath(for: fixture("plain/nested/deep/buried.txt")) ?? "nil")
check("the root itself resolves to the empty string",
      plainRepo.relativePath(for: fixture("plain")) == "")
check("a path outside the repo resolves to nil",
      plainRepo.relativePath(for: fixture("notrepo")) == nil)
check("a sibling with the root as a string prefix is NOT inside it",
      plainRepo.relativePath(for: URL(fileURLWithPath: work + "/plainer/x.txt")) == nil,
      "guards against dropFirst on a bare hasPrefix")

print("DEGENERATE INPUT — must not trap")
check("empty bytes -> empty snapshot", GitStatus.parse(porcelain: [UInt8]()) == .empty)
check("garbage -> empty entries, no crash",
      GitStatus.parse(porcelain: Array("not porcelain at all".utf8)).entries.isEmpty)
check("a truncated record is skipped, not fatal",
      GitStatus.parse(porcelain: Array("1 .M N... 100644\u{0}".utf8)).entries.isEmpty)
check("a rename record with no second token does not read past the end",
      GitStatus.parse(porcelain: Array(
          "2 R. N... 100644 100644 100644 aaa bbb R100 only.txt\u{0}".utf8))
          .entries["only.txt"]?.status == .renamed)

print("")
if failures == 0 {
    print("all checks passed")
    exit(0)
}
print("\(failures) check(s) failed")
exit(1)
