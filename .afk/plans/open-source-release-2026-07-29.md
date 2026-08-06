# Going open-source, and shipping a build people can download

**Date:** 2026-07-29 · **Status:** plan, nothing executed · **Repo:** `griffinwork40/umber`, PRIVATE, `main` @ `cb7a49a`

This answers two questions that turn out to have almost nothing to do with each other:

1. **What must be true before `gh repo edit --visibility public`?** — mostly a licence, a scrub, and a repo that can actually be built by someone who is not you.
2. **How do people download and run it?** — a codesigning question with a $99/yr fork in the road, and one Info.plist bug that will bite real users regardless of which branch you take.

Every claim below is either a file:line read or a command that was actually run. Where something was *not* verified it says so.

---

## 0. The finding that reorders everything

**`main` does not contain the #494 reflow fix, but `main`'s plan docs already claim it does.**

- `cb7a49a` (HEAD of `main`) is titled *"re-price it now that #494 is fixed"* and its body says the defect *"is patched and gated as of today (PR #13)"*.
- `git merge-base --is-ancestor 9e23405 main` → **NO**. The fix commit lives only on `afk/reflow-patch`.
- `gh pr list` → **PR #13 is OPEN** (mergeable). PR #14 (`afk/phase1-shellhosting`) is open too.
- So the tracked tree on `main` has no `patches/swiftterm/0002-index-iswrapped-buffer-absolute.patch`, no `app/Scripts/check-reflow.sh`, and a `verify-vendor.sh` whose `Buffer.swift` check is still **warn-only**.
- Meanwhile the *working* `vendor/SwiftTerm` on this laptop **does** have the fix: live `Buffer.swift` hashes `926fd29…`, the pin on `main` wants `7b65f2b…`. Running `verify-vendor.sh` today prints `warning: … changed from the pin` and exits 0.

Three consequences, in descending order of how bad they are:

1. The working state of the project is **more correct than the repository**, and the difference lives in a gitignored directory on one machine. `rm -rf vendor/` loses a verified correctness fix. This is the exact failure mode `SwiftTerm.pin` was created to prevent (`patches/swiftterm/SwiftTerm.pin:5-20`), recurring one level up: the mechanism was built, then the fix that needed it was left on a branch.
2. Publishing `main` today publishes a repo that **asserts a scrollback-correctness fix it does not ship**, in a doc a stranger will read as the record.
3. AFK.md and hot memory both say "#494 is fixed." Upstream `#494` is **still `state=open`**, and the latest SwiftTerm tag is `v1.15.0` (2026-07-19) — the fix is *yours*, local, unmerged, and not in any release. Any SwiftTerm upgrade silently reintroduces it.

**Action: merge PR #13 before anything else on this list.** Nothing downstream is worth doing on a tree whose correctness story is a branch.

---

## 1. A stranger cannot build this repo. The reason is stale.

Empirically confirmed on a cold `gh repo clone` into `/tmp/umber-cold-clone`:

- `cd app && ./Scripts/make-app-bundle.sh release` → **fails in ~1s** at the `verify-vendor.sh` gate (`make-app-bundle.sh:29`), before `swift build` ever runs.
- bare `swift build` → fails on SwiftPM path resolution: `Package.swift:20` is `.package(path: "../vendor/SwiftTerm")` and `vendor/` is gitignored (`.gitignore:11-19`).
- The recreation recipe exists only in `app/README.md:180-190` — not in the root README, which is the file a newcomer reads. It is 3 manual steps.
- Bonus correction: the recipe's `chmod -R u+w vendor/SwiftTerm  # patch fails otherwise` is **wrong on a fresh `git clone`** — the patch applies fine without it. The `chmod` is only needed against a read-only *SPM checkout*, which is not what the recipe tells you to create.

Now the part that changes the fix. **Patch 0001 (exclude the Metal shader) is a workaround for a local toolchain selection, not an upstream defect:**

| command | result |
|---|---|
| `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| `xcrun -f metal` | `error: unable to find utility "metal"` |
| `swift build` — scratch pkg, **unpatched** upstream SwiftTerm `1.15.0` | `error: unable to spawn process 'metal'` → **Build failed** |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun -f metal` | `/Applications/Xcode.app/…/usr/bin/metal` ✅ |
| `DEVELOPER_DIR=… swift build` — same **unpatched** upstream dep | **`Build complete! (10.68s)`** ✅ |

`/Applications/Xcode.app` is installed and already has a working `metal`. So the repo's stated premise — *"Xcode 26.6 moved the Metal toolchain to a downloadable component that is not installed here"* (`app/Package.swift:14-18`, `app/README.md:172-176`) — is **stale**. The real cause is that the active developer dir is CLT. One `DEVELOPER_DIR` export, or `sudo xcode-select -s /Applications/Xcode.app`, and patch 0001 has no reason to exist.

But you **cannot fully de-vendor**, because patch **0002** (the #494 fix) is a genuine source change upstream does not have. So the choice is about *where the patched source lives*:

**Option A — fork SwiftTerm publicly (recommended).** Push `griffinwork40/SwiftTerm` = `v1.15.0` + patch 0002, then `Package.swift` becomes `.package(url: "https://github.com/griffinwork40/SwiftTerm.git", revision: "<sha>")`.
- Cold clone becomes `git clone && cd app && ./Scripts/make-app-bundle.sh release`. Zero extra steps.
- Deletes `vendor/`, `patches/`, `verify-vendor.sh`, and the entire pin/hash apparatus — ~500 lines of machinery that exists solely to compensate for an unversioned directory.
- The patch becomes public, citable, and *upstreamable*: it is a two-line index fix for an open issue with a falsifiable 8-case gate. **Send it to `migueldeicaza/SwiftTerm#494` as a PR.** If it lands, the fork evaporates and you go back to `from: "1.15.0"`.
- Keeps `check-reflow.sh` meaningful — it now gates your fork rather than a local directory.

**Option B — keep vendoring, make it bootstrappable.** Add `Scripts/bootstrap-vendor.sh` that clones the pinned commit, applies both patches, runs `verify-vendor.sh`; call it from `make-app-bundle.sh` when `vendor/` is absent. Cold clone works in one command, all the pin machinery survives.
- Cheaper to write, but keeps ~500 lines of hash-pinning and leaves the project's correctness fix invisible to anyone reading GitHub.

Either way, drop patch 0001 and instead have `make-app-bundle.sh` resolve a usable toolchain: prefer `xcode-select -p` if it contains `metal`, else fall back to `/Applications/Xcode.app/Contents/Developer`, else fail loudly with the `xcodebuild -downloadComponent MetalToolchain` instruction. That is a portability win for every contributor, not a personal workaround.

---

## 2. There is no LICENSE. That is the only actual legal blocker.

`ls LICENSE*` → nothing. `gh repo view --json licenseInfo` → `null`.

- **SwiftTerm is MIT** (`vendor/SwiftTerm/LICENSE:1-23`, confirmed against upstream `main` and the GitHub licence API). Four stacked copyright lines — de Icaza 2019-2022, xterm.js 2017-2019, SourceLair 2014-2016, Christopher Jeffrey 2012-2013 — **all** must be preserved together.
- MIT's obligation attaches to what you **distribute**. Today `vendor/` is gitignored, so the repo carries none of SwiftTerm's source — but the shipped `.app` contains its object code, so the notice obligation attaches to the binary. Under Option A the licence travels with the fork automatically.
- **Ghostty / libghostty is MIT** (confirmed via licence API; `Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors`). GTK4 is a Linux-only runtime dep and irrelevant to a macOS Swift app. **The future engine swap has no licence constraint.**
- **Icon: safe.** `make-icon.py` is fully procedural — superellipse mask (`:62-73`), hand-computed gradients (`:76-119`), a bespoke mitred-polygon `>_` glyph (`:127-196`). No `NSImage`, no `systemSymbolName`, no font rendering. SF Symbols *are* used for in-UI glyphs (`FileTreeViewController+OutlineView.swift:120`, `DocumentTabStrip+Drawing.swift:99`, `:158`) which Apple's licence permits; the prohibition is on app icons, and the icon is not one of them.
- **Themes: courtesy credit.** `Theme.swift:90-113` — `tokyoNight` reuses enkia's name and near-identical hex values (MIT); `afkDark` is documented at `:85-89` as a GitHub-Dark-derived palette (Primer, MIT). Colour values are facts with a weak copyright claim, but same-name-same-values earns a credit line.
- **Gaps in the bundle:** `Info.plist` has no `NSHumanReadableCopyright` (`make-app-bundle.sh:69-100`) and the About panel (`AppMenu.swift:42`, `orderFrontStandardAboutPanel`) has no credits content.

**Add:** `LICENSE` (MIT, `Copyright (c) 2026 Griffin Long` — matching `com.griffinlong.umber`), `THIRD-PARTY-LICENSES.md` (SwiftTerm's full text + link, plus the two theme credits), `NSHumanReadableCopyright` in the plist, and bundle the third-party file into `Contents/Resources` with an "Acknowledgements" menu item.

---

## 3. Scrub list — 6 real leaks, and no history rewrite needed

| # | Location | What | Fix |
|---|---|---|---|
| 1 | `.afk/plans/native-swift-terminal-afk-host.md:9` | `<repo>` | relative path |
| 2 | `…host.md:43` | `<projects>/terax-ai` — **names an unrelated private fork** | drop path *and* consider dropping the repo slug |
| 3 | `…host.md:250` | `<projects>/agent-afk` | relative path or plain repo link |
| 4 | `.afk/plans/emulator-foundation-probe-and-vendor-integrity.md:315` | `/Users/<user>/…/.afk-worktrees/libghostty-spike/app` — ellipsis does not hide the home dir | redact |
| 5 | `…integrity.md:316` | `<user>@<host>:~/…` — **leaks the machine hostname**, invisible to a `/Users/` grep | redact |
| 6 | `AFK.md:5` | "Personal project, **private repo** `griffinwork40/umber`" | false on publish |

Plus, non-blocking but worth doing in the same pass:

- `AFK.md:120` and `…integrity.md:387-388` are meta-sentences *quoting* "3 absolute `/Users/<user>` paths" — they dangle once #1–3 are fixed.
- `…host.md:8` — `**Owner:** Griffin Long`. Real name in prose; your call (the bundle id already carries it).
- `.afk/plans/next-sequencing-2026-07-28.md:82` — "on a private solo repo with no CI", stale.
- **Undefined private tooling:** bare `/research`, `/shadow-verify`, `/devils-advocate` (`…integrity.md:22-23`), `/ground-state` (`next-sequencing…md:4`), `/devils-advocate` (`naming-decision…md:147`). These name your AFK skill system with zero explanation and will read as noise to a stranger. Either footnote them once or strip them.
- **Commit identity becomes public:** 86 commits as `Griffin Long <griffinwork40@gmail.com>`, plus 3 as `afk <afk@local>` and 2 as `griffinwork40 <griffin@local>`. The gmail address is the exposure; the two `@local` identities are just untidy. Decide before publishing — after publishing, rewriting authorship means rewriting every SHA.

**History: a scrub commit is sufficient. No rewrite.** 91 commits; `git log --all -S'/Users/<user>'` returns 5 commits, all touching the *same still-tracked lines* listed above (nothing deleted-and-forgotten). Zero hits for `api_key`, `ssh-rsa`, `BEGIN PRIVATE KEY`, `@gmail.com` in content, or `afk-workshop`. `MacTerminal` hits split cleanly at the rename `faf1291` and are harmless.

**Not checked:** embedded metadata inside `Umber.icns` / `icon-1024.png`.

---

## 4. The root README is out of date in a way that undersells the project

`README.md:36-37` — *"Not built: splits · **app icon** · preferences UI · shell integration · **search** · URL clicking · profiles."* Both the icon and search shipped (`243fcfb`). The README is showing a version of the project two features behind itself, on the page everyone lands on.

`README.md:39-40` — *"No test target. Verification so far is a deleted Step 0 gate harness … plus use."* There are now **five** `check-*.sh` scripts (six with `check-reflow.sh` from PR #13) plus `verify-vendor.sh` and `UMBER_DIAG`. That is a real verification story told as an absence.

Also needed for a public front page: a **screenshot or GIF** (there is none — the icon is the only image), the download link, the Gatekeeper instructions from §5, and a one-line "how to build" that actually works after §1.

---

## 5. How people download it — and the one bug that bites either way

### The Gatekeeper reality in 2026

macOS 15 removed the Control-click→Open bypass ([Apple, id=saqachfa](https://developer.apple.com/news/?id=saqachfa)). A user who downloads an unsigned or ad-hoc-signed `.app` today gets: double-click → *"cannot be opened"* with only **Done / Move to Trash** → System Settings → Privacy & Security → scroll → **Open Anyway** → password → reopen → confirm. **~6 steps across two apps**, once per version. `xattr -dr com.apple.quarantine Umber.app` still works through macOS 26/27 and is now the only fast path.

`make-app-bundle.sh:104` already ad-hoc signs (`codesign --force --sign -`). That is worth keeping regardless — it gives TCC a stable identity, which is what stops the repeated-permission-prompt bug other terminals hit — but it buys **nothing** with Gatekeeper.

### Fix this before shipping any build: TCC usage descriptions are missing

`Info.plist` (`make-app-bundle.sh:69-100`) has no `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, or `NSDownloadsFolderUsageDescription`. TCC attributes a child process's file access to the **launching bundle**, so when your login shell `cd ~/Documents && ls`, macOS checks *Umber's* plist. Without these keys, access is **silently denied** and the app never even appears in Privacy & Security for the user to grant. WezTerm ships exactly these three, worded *"An application launched via WezTerm would like to access…"*. This is a live bug on the current build, not a release chore.

Hardened-runtime entitlements, by contrast, are a non-issue: `forkpty`+`execve` of a login shell needs **no** opt-outs. Ghostty's and WezTerm's shipped entitlements contain zero hardened-runtime exceptions; `com.apple.security.inherit` is sandbox-only and Umber is unsandboxed.

### Three tiers

| | cost | Gatekeeper UX | brew-eligible |
|---|---|---|---|
| **(a)** unsigned | $0 | 6-step Settings dance | never |
| **(b)** ad-hoc signed — *where you are* | $0 | identical to (a) | never |
| **(c)** Developer ID + notarized + stapled | **$99/yr** | double-click, just opens | yes |

Tier (c) prerequisites: Apple Developer Program ($99/yr, no waiver for individuals), a **"Developer ID Application"** certificate, `--options runtime --timestamp` on `codesign`, `xcrun notarytool submit --wait`, `xcrun stapler staple`. Command Line Tools are enough for `notarytool`, but **`stapler` hard-requires full Xcode** — you have `/Applications/Xcode.app`, so this is fine locally and fine on CI runners. Store creds with `notarytool store-credentials` (app-specific password, or an App Store Connect **Team** API key — Individual keys are rejected).

### Artifact and CI

Ship a **`.dmg`**, not a `.zip`: you can notarize either, but you can only **staple** a `.dmg`/`.pkg`/`.app` — never a zip. Build universal (`swift build -c release --arch arm64 --arch x86_64`, or two builds + `lipo -create`, which is what WezTerm does because mixing `--arch` with `-Xswiftc` silently drops flags). Then `create-dmg` (or `hdiutil create -format UDZO`) → `notarytool submit --wait` → `stapler staple` both the dmg and the app.

For GitHub Actions: base64 the `.p12` into a secret, create a throwaway keychain, `security import -T /usr/bin/codesign`, then — the #1 gotcha — **`security set-key-partition-list -S apple-tool:,apple: -k "$PW"`**, without which signing hangs on an invisible prompt. `security delete-keychain` in `if: always()`.

### Homebrew: the door is closing

- **Homebrew 5.0.0 deprecates unsigned/non-notarized casks, removal by 2026-09-01.** Ad-hoc signing cannot get in, at any star count. Signing is now a hard gate.
- Notability floor: rejected below **75 stars / 30 forks / 30 watchers** — and for a **self-submitted** cask (you submitting your own app) the bar **triples to 225 / 90 / 90** (added Feb 2026).
- So `brew install umber` from the official cask means: pay the $99, notarize, *and* reach 225 stars. A **personal tap** (`brew tap griffinwork40/umber`) has neither bar and works today — it is the honest answer for `brew`-installability in the near term.

Sparkle 2.x is still the standard for auto-update (needs an EdDSA key + an HTTPS `appcast.xml`), but it lists Developer ID signing as a prerequisite, so it is strictly post-tier-(c). v0.2+.

---

## 6. Sequenced plan

**Phase 0 — unblock the tree** (nothing else is worth doing first)
1. Merge **PR #13**. Decide PR #14. Then the repo's correctness claims match the repo.
2. Pick Option A (public SwiftTerm fork) or B (`bootstrap-vendor.sh`). Make `git clone` → build work in one command; verify by actually cold-cloning.
3. Drop patch 0001; resolve `DEVELOPER_DIR` in `make-app-bundle.sh` instead.
4. Add the three `NS*FolderUsageDescription` keys — this is a live bug.

**Phase 1 — make it publishable**
5. `LICENSE` (MIT) + `THIRD-PARTY-LICENSES.md` + `NSHumanReadableCopyright` + Acknowledgements menu item.
6. Scrub the 6 leaks in §3; decide on the commit email *before* publishing.
7. Rewrite the root README status block (§4); add a screenshot.
8. `gh repo edit griffinwork40/umber --visibility public`. Optionally add a CI workflow running the six `check-*.sh` — you have no CI, and the 350-LOC gate and keybinding truth table are exactly what a public repo should enforce on PRs.

**Phase 2 — a download that works** (pick one)
- **Free path:** tag `v0.1.0`, attach an ad-hoc-signed `.zip`, and put the `xattr -dr com.apple.quarantine` line + the Settings walkthrough in the README. Honest, $0, ~6 steps of user friction. Fine for "a handful of people I tell about it."
- **$99 path:** Developer ID cert → hardened runtime → universal `.dmg` → notarize → staple → GitHub Release, with the signing pipeline in Actions. Double-click and it opens. This is the version you want if you expect strangers to install it, and it is the only version with a future in Homebrew.

**Phase 3 — later**
- Upstream patch 0002 to SwiftTerm `#494` (it is a two-line fix with an 8-case falsifiable gate — genuinely mergeable).
- Personal tap now; official cask only past 225 stars.
- Sparkle once signed.

**Recommendation:** Phase 0 + Phase 1 + the free Phase 1 release. Pay the $99 the first time someone who is not you asks for a build. The forcing function for tier (c) is an actual user, and you do not have one yet — but the Sept 2026 Homebrew deadline means "signed" is the long-run default, so do not architect the release script as if ad-hoc is permanent: put the identity in a variable from day one.

---

## Not verified

- Whether `check-*.sh` pass on a cold clone (the agent testing this was killed by a rate limit mid-run; the two build failures above were captured before it died).
- Notarization size/rate limits; whether macOS 27's amfid tightening affects plain `execve` shell spawning versus separately-signed helpers.
- Embedded metadata in `Umber.icns` / `icon-1024.png`.
- Whether a built `.app` has ever been handed to a third party (changes urgency of §2, not the obligation).
