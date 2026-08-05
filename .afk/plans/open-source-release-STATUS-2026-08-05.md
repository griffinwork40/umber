# Open-source release: what is actually left (status pass, 2026-08-05)

**Re-verifies** `.afk/plans/open-source-release-2026-07-29.md` (written a week ago, before PRs
#17–#25 landed) against the current tree. Every line below is a command I ran or a file:line I
read today. Where the plan's item changed shape rather than closing, it says so.

**Repo today:** `griffinwork40/umber`, still `PRIVATE`, `main` @ `832d2d5`, **0 tags, 0 releases,
no `.github/`**, 1 star. Working tree dirty (`Theme.swift`, `ThemeValues.swift`) with 3 open PRs
(#26 editor syntax, #32 classic-repaired theme, #33 sidebar toggle) and 15 worktrees.
**Note: the release plan itself is UNTRACKED** — `git status` shows `?? .afk/plans/open-source-release-2026-07-29.md`.

---

## Closed since the plan was written

| Plan item | Evidence |
|---|---|
| §0 Phase 0.1 — merge PR #13 (the #494 reflow fix that `main` claimed but did not ship) | `gh pr view 13` → **MERGED**; `patches/swiftterm/0002-*.patch` + `app/Scripts/check-reflow.sh` are on `main`. PR #14 also MERGED. |
| §6 "not verified: do the check scripts pass on a cold clone" | Answered by inspection: of 19 scripts, **12 are cold-clone-safe** (single-file `swiftc` harnesses) and **7 are not** — `verify-vendor.sh`, `check-reflow.sh`, `check-altbuffer-resize.sh` (explicit `vendor/` preconditions), `check-ghostty-pane.sh`, `check-metal-renderer.sh`, `check-pane-teardown.sh` (run `swift build`), `check-keys-e2e.sh:38-40` (needs a built bundle). |
| §5 bundle-size worry (implicit) | `du -sh app/build/Umber.app` → **16M** debug / 11M release. GhosttyKit statically links and dead-strips; no xcframework inside the bundle. The 51.8 MB is a build-time cost only. |

---

## Still open — Phase 0 (tree must be buildable and correct)

1. **A stranger still cannot build this repo, and it got worse.** `.gitignore:20` still ignores
   `vendor/`; `app/Package.swift:24` is still `.package(path: "../vendor/SwiftTerm")`. No
   `bootstrap-vendor.sh` exists (Option B) and `griffinwork40/SwiftTerm` 404s (Option A). The
   manual recipe in `app/README.md` is now **6 steps, not 3** — patches 0003 and 0004 landed with
   no follow-through on either option. This is the single largest blocker to publishing.
2. **The three TCC folder keys are still missing — the live bug is still live.** `make-app-bundle.sh:74-101`
   has `NSMicrophoneUsageDescription` and `NSAppleEventsUsageDescription` (added by `8fabf33`/PR #23)
   and **no** `NSDesktopFolderUsageDescription` / `NSDocumentsFolderUsageDescription` /
   `NSDownloadsFolderUsageDescription`. PR #23's title reads like it closed this; it closed a
   *different* TCC surface (mic/AppleEvents SIGABRT). A shell inside Umber that `cd ~/Documents`
   is still silently denied, with no Privacy & Security entry for the user to grant.
3. **Patch 0001 / `DEVELOPER_DIR` — the plan's ask is now moot, but not done.** 0001 was rewritten
   (not dropped) on 2026-07-31 to ship the shader as a `.copy` resource, which sidesteps the offline
   `metal` compiler; `swift build` succeeds today under CLT-only. No script resolves `DEVELOPER_DIR`
   (`grep DEVELOPER_DIR app/Scripts/*.sh` → 0 hits), so an *unpatched* upstream checkout still dies
   at `unable to spawn process 'metal'`. Only matters if Option A/B changes where the source lives.

## Still open — Phase 1 (make it publishable)

4. **No LICENSE. Still the only hard legal blocker.** No `LICENSE`, `THIRD-PARTY-LICENSES.md`,
   `NOTICE`, `CONTRIBUTING`, or `CODE_OF_CONDUCT` anywhere; `gh repo view --json licenseInfo` → `null`;
   no `NSHumanReadableCopyright` in the plist; `AppMenu.swift:42` is still a bare
   `orderFrontStandardAboutPanel` with no Acknowledgements item.
5. **The third-party list is bigger than the plan's, and one entry is not MIT.**
   - SwiftTerm v1.15.0 + 4 patches — MIT, **four stacked copyright lines** must travel together.
   - libghostty-spm `1.3.2` (`app/Package.resolved:9-10`) — MIT (Lakr233), wrapping Ghostty (MIT).
   - MSDisplayLink `2.1.0` — MIT, transitive via libghostty-spm.
   - **swift-argument-parser `1.8.2` — Apache-2.0**, pulled by the *vendored SwiftTerm*
     (`vendor/SwiftTerm/Package.swift:151`). The only non-MIT license in the graph; it has its own
     NOTICE-shaped obligation the plan does not mention.
6. **Theme attribution is now a stronger case than "courtesy credit."** `ThemeValues.swift:105-164`
   self-documents `afk-light` as a **verbatim** GitHub Light Default port (Primer, MIT), `afk-dark`
   as GitHub-Dark-derived, and `tokyo-night` as transcribed verbatim (enkia, MIT). Zero credit lines
   exist in any user-facing file. `umber` is in-house and needs none.
7. **The scrub list is untouched: 6 of 6 still open.** `git grep "/Users/<user>"` → 3 hits in
   `native-swift-terminal-afk-host.md:9,43,250` (one names the unrelated `terax-ai` fork), 1 in
   `emulator-foundation-probe-and-vendor-integrity.md:315`, plus 2 in `.afk/research/git-sidebar-*`
   the plan never caught. Hostname leak `<user>@<host>` still at
   `…integrity.md:316`. `AFK.md:5` still says "private repo". The dangling "3 absolute paths"
   meta-sentences (`AFK.md:182`, `…integrity.md:387`) are still there and become literally false
   after the scrub. ~9 bare private-tooling references (`/research`, `/shadow-verify`,
   `/devils-advocate`, `/ground-state`) across 6 docs.
8. **`.afk/` is tracked: 40 files, 10,178 lines** that publish as-is. Decide whether that is the
   project's transparency story (it reads that way, and the commit style supports it) or noise —
   but decide deliberately, not by default.
9. **Commit identity:** 91 commits as `Griffin Long <griffinwork40@gmail.com>`, 2 as
   `griffinwork40 <griffin@local>`. Rewriting after publish means rewriting every SHA.
10. **The root README is not two features behind — it is wrong in five places.** `README.md:31-36`
    says "**no palette installed by default**" (false since 2026-08-03: `umber` IS the default,
    `Config.swift:73`) and never mentions `umber` at all; `:38-39` still lists **app icon** and
    **search** as not built (both shipped in `243fcfb`) and omits the git sidebar, light mode, the
    second engine and OSC 133; `:41-42` says "No test target… a deleted Step 0 gate harness" when
    there are 18 `check-*.sh` + `verify-vendor.sh`; `:63` says "five source files" (actual **52**);
    `:64` says "one local patch" (actual **four**); `:72-78` still tells the pre-2026-07-27 #494
    story ("three deterministic reflow tests could not reproduce it… reduced, not closed") that
    `AFK.md` corrected as *wrong*. No screenshot exists (only `icon-1024.png`). No Gatekeeper /
    `xattr` instructions.
11. **No CI.** No `.github/` at all. The 350-LOC gate and the 12 cold-clone-safe check scripts are
    exactly what a public repo should run on PRs, and they cost nothing to wire.

## Still open — Phase 2 (a download that works)

12. **Signing is hardcoded ad-hoc.** `make-app-bundle.sh:108` is a literal `codesign --force --sign -`.
    The plan's advice — put the identity in a variable from day one — is not done. No dmg/zip
    packaging, no notarytool, no stapler, no Sparkle, no tag, no release.
13. **The $99 fork in the road is still unmade.** Ad-hoc = a ~6-step Settings dance per version for
    every downloader, and permanently brew-ineligible (Homebrew 5.0.0 removes non-notarized casks
    2026-09-01, and a self-submitted cask needs 225★).

## New since the plan — decisions that gate a release, not chores

14. **Which engine ships?** Both SwiftTerm and libghostty are linked on purpose for the probe
    (`Package.swift:56-66`); `engine` defaults to `swiftterm` and libghostty Phase 5/6 (reflow gate,
    kitty-keyboard guard, the soak) are unwritten. Publishing with both linked is defensible — it is
    the probe's whole point — but it doubles the surface a stranger sees and the licences you owe.
15. **Uncommitted / in-flight work.** `Theme.swift` and `ThemeValues.swift` are dirty; PRs #26, #32,
    #33 are open. A v0.1 tag should land on a clean tree, and #32 (classic repaired) touches the
    same files as the uncommitted diff.

---

## The shortest honest path to "public + downloadable"

Free path, in order: **(a)** Option A or B so `git clone && ./Scripts/make-app-bundle.sh release`
works → **(b)** the three folder keys → **(c)** `LICENSE` + `THIRD-PARTY-LICENSES.md` (incl. the
Apache-2.0 entry) + theme credits + `NSHumanReadableCopyright` → **(d)** the 6-item scrub + AFK.md:5
→ **(e)** rewrite the root README against reality and add one screenshot → **(f)**
`gh repo edit --visibility public` → **(g)** tag `v0.1.0`, attach the ad-hoc zip, document
`xattr -dr com.apple.quarantine`. CI (11) is optional but nearly free. The $99 tier (13) waits for
the first person who is not you asking for a build.

**Not checked today:** embedded metadata in `Umber.icns`/`icon-1024.png` (still unverified, as in
the original plan); whether a built `.app` has ever left this machine; notarization limits;
Ghostty's upstream LICENSE text was read only at the SPM-wrapper layer.
