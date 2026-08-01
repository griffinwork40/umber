//
//  GhosttyPane+Document.swift
//  How a libghostty pane presents itself to the container, and what it reports back.
//
//  Split from `GhosttyPane.swift` from the first commit rather than when the ceiling was hit,
//  which is what `libghostty-swap-sequencing-2026-07-28.md` §4 asks for: "Plan for two files
//  from the start… rather than writing 340 lines and splitting under ceiling pressure later."
//  The seam is the same one `FileViewerPane+Document.swift` uses — the pane owns the engine,
//  this file owns the protocol conformances — and it is the reason adding a document kind
//  never touches the container.
//
//  ALL FIVE INBOUND DELEGATES ARE HERE, and that is a change in kind from the SwiftTerm pane
//  rather than a change in degree. libghostty routes every surface event through ONE
//  `delegate` property whose protocols are matched by runtime `as?` cast
//  (`AppTerminalView.swift:23-26`, `TerminalSurfaceViewDelegate.swift`), so a pane simply
//  adopts the ones it wants. `TerminalPane` needed a `processDelegate`, a separate
//  `bellDelegate` slot, and a `bell(source:)` subclass override to reach the same set — and
//  still could not reach OSC 7 or OSC 133 at all.
//

import AppKit
import GhosttyTerminal

// MARK: - SpaceDocument

extension GhosttyPane: SpaceDocumentReporting {}

extension GhosttyPane: SpaceDocument {
    var documentView: NSView { view }

    /// Falls back rather than rendering an empty tab, same as `TerminalPane`: `currentTitle`
    /// stays empty until the shell emits OSC 0/2, which does not happen until the first prompt
    /// paints.
    ///
    /// "Terminal" and not "Ghostty" deliberately. The tab is a terminal from the user's point
    /// of view; which engine draws it is an implementation detail that must not leak into the
    /// UI, or Step 2's "delete the loser" would visibly rename every tab.
    var documentTitle: String { currentTitle.isEmpty ? "Terminal" : currentTitle }

    var documentSymbolName: String { "terminal" }

    var documentStatus: DocumentStatus { status }

    func documentDidBecomeActive() {
        // The pane's own view, not the container: libghostty reads key events on the terminal
        // view itself, and a container in the responder chain would swallow the first
        // keystroke. Same reasoning as `TerminalPane`.
        view.window?.makeFirstResponder(view)
        clearAttention()
    }

    /// Free the surface, which also kills the shell it spawned.
    ///
    /// Nilling `controller` is the whole mechanism, and it is the only route the module's
    /// access control leaves open: `AppTerminalView.controller` forwards to the coordinator
    /// (`Platform/AppKit/AppTerminalView.swift:28-31`), whose `didSet` calls
    /// `rebuildIfReady(removingBridgeFrom: oldValue)`
    /// (`Surface/TerminalSurfaceCoordinator.swift:23-28`), which calls `tearDownSurface`
    /// **first** and then bails on the `guard let controller` (`:98-101`) — so a nil
    /// assignment is a pure teardown with no rebuild. `tearDownSurface` is what does the
    /// work: `surface?.setFocus(false)`, `surface?.free()`, `surface = nil`, and it drops the
    /// callback bridge (`:311-325`). `freeSurface()` (`:294-297`) would say this more
    /// directly but is module-internal and unreachable from here.
    ///
    /// Idempotent for free: the second assignment hits `guard controller !== oldValue`
    /// (`:25`) with both sides nil and returns without touching anything.
    ///
    /// **On why this is needed at all — the risk register overstated the bug, and the real
    /// reason is better.** `AFK.md` and this pane's own header said "nothing frees the
    /// surface", reasoning from libghostty having removed `TerminalSurface`'s deinit safety
    /// net (`Surface/TerminalSurface.swift:405-410`). That is true of `TerminalSurface` and
    /// false of the layer above it: `TerminalSurfaceCoordinator` has a `deinit` that calls
    /// the same `tearDownSurface` (`:299-309`), and the delegate back-reference is `weak` at
    /// both levels (`AppTerminalView.swift:23`, `TerminalSurfaceCoordinator.swift:19`), so
    /// there is no retain cycle and a released pane *would* eventually free its surface.
    /// Explicit teardown still earns its place, for two reasons that survive that correction:
    ///
    /// 1. **Determinism.** "Eventually" is doing a lot of work in a sentence about a live
    ///    shell. The pane is referenced by the `documents` array, by the view hierarchy, and
    ///    transiently by whatever is mid-callback; releasing at *close* means the child
    ///    process dies when the user closes the tab, not whenever the last reference happens
    ///    to drop. A closed tab still running a build is a bug the user would find first.
    /// 2. **That deinit is the riskier path.** It reaches main-actor state from a nonisolated
    ///    `deinit` via `MainActor.assumeIsolated`, which *traps* rather than degrades if the
    ///    final release ever lands off the main actor. Tearing down here, on the main actor,
    ///    at a known moment, means the deinit later finds `surface == nil` and does nothing —
    ///    so the fragile path stops being load-bearing instead of being relied upon.
    func documentWillClose() {
        diag("document closing — freeing surface and its shell")
        view.controller = nil
    }
}

// MARK: - Attention state

extension GhosttyPane {
    /// The user is looking at this pane, so whatever it wanted to tell them has landed.
    func clearAttention() {
        // Via the pane's own mutator for the same file-scope reason the delegates use theirs.
        resetStatus()
    }

    /// Is this the document currently on screen in its Space?
    ///
    /// Derived from the view hierarchy rather than tracked with a flag, for the reason
    /// `TerminalPane.isActiveDocument` documents in full: `DocumentAreaViewController.present`
    /// maintains exactly this invariant already, and a cached flag would be a second copy of
    /// that fact with no "did become inactive" callback to keep it honest.
    fileprivate var isActiveDocument: Bool { view.superview != nil }
}

// MARK: - ShellHosting

/// The seam that lets a shell-directed action — the file tree's "insert path", `cd Here` —
/// find a *shell* without naming a concrete pane. `FileViewerPane` must never conform; a
/// second terminal engine must.
extension GhosttyPane: ShellHosting {
    func send(text: String) {
        // `sendText` is the public wrapper (`AppTerminalView+PublicInput.swift:17-19`); the
        // underlying `TerminalSurface` is internal to the module and unreachable from here.
        view.sendText(text)
    }

    /// The shell's current directory — and here it is simply *known*.
    ///
    /// This is the single clearest demonstration of what the engine buys. The SwiftTerm pane
    /// answers the same question by asking the KERNEL: `tcgetpgrp` for the foreground process
    /// group, then `proc_pidinfo(PROC_PIDVNODEPATHINFO)` for its cwd (`ShellDirectory.swift`,
    /// ~162 lines whose header argues at length why OSC 7 was unavailable — macOS only emits
    /// it when `TERM_PROGRAM == Apple_Terminal`, and SwiftTerm sets no `TERM_PROGRAM`).
    /// libghostty ships its own shell integration and pushes OSC 7 with no rc-file
    /// cooperation, which the spike confirmed by transcript (§6.2 Q1).
    ///
    /// Falls back to the pane's launch directory before the first report, so a brand-new tab
    /// answers with the truth rather than nil.
    var currentDirectory: URL? {
        if let reported = reportedDirectory { return URL(fileURLWithPath: reported) }
        return launchDirectory
    }
}

// MARK: - libghostty surface delegates

extension GhosttyPane:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceCommandFinishedDelegate
{
    /// OSC 0/2. Drives the tab strip and, when this is the active document, the window
    /// subtitle — via the widened document delegate, so the container never names this class.
    func terminalDidChangeTitle(_ title: String) {
        recordTitle(title)
    }

    /// OSC 7. **This is the callback `TerminalPane` has never been able to fill.**
    /// `TerminalPane.hostCurrentDirectoryUpdate` is a wired-but-empty body and provably must
    /// be — see `ShellHosting.swift:97` — so the sidebar follows the shell by polling the
    /// kernel every 750ms instead (`SpaceViewController+DirectoryFollow.swift`). Under this
    /// engine the shell just says so, and the poller would be redundant for this pane.
    ///
    /// **OBSERVED, 3/3 runs.** This comment previously said "NOT YET OBSERVED IN THIS APP"
    /// and cited `check-ghostty-pane.sh` reporting `pwd=-`; both the claim and the citation
    /// were wrong, and how they were wrong is worth keeping. That gate waited
    /// `until title || OSC 7`, and its `pump` returns the moment its condition holds — a zsh
    /// sends the title first, so the wait ended a beat before the OSC 7 sequence landed and
    /// the harness printed `pwd=-` on every run. A disjunction in a *wait* silently truncates
    /// the slower signal. Split into cases 5a/5b with the reported path asserted against this
    /// pane's own root, OSC 7 arrives every run. The lesson generalised: a gate that cannot
    /// notice good news cannot notice the bad news sharing its channel.
    ///
    /// Deliberately only RECORDS it rather than driving the file tree — and after Phase 4 that
    /// is a *sufficient* implementation rather than a placeholder. `currentDirectory` below
    /// answers from `reportedDirectory`, and the 750ms poller reads exactly that property
    /// through `focusedShellHost` (`ShellHosting.swift:166-168`, a protocol lookup that never
    /// names a concrete pane). So the sidebar already follows this engine, driven by OSC 7,
    /// with `followDirectory(_:)` keeping the single caller its own header insists on ("the
    /// only place in the app that moves the tree").
    ///
    /// Calling `followDirectory` from here would therefore buy ≤750ms of latency and cost the
    /// invariant — two writers moving the tree, one per engine. If that latency ever grates,
    /// the fix that keeps one writer is to nudge the existing poller
    /// (`directoryFollowPollNow()`), so the *trigger* moves and the writer does not.
    func terminalDidChangeWorkingDirectory(_ path: String) {
        recordDirectory(path)
        diag("OSC 7 pwd -> \(path)")
    }

    /// BEL. A first-class delegate here, where SwiftTerm needed a subclass override of
    /// `bell(source:)` plus a bespoke `bellDelegate` slot to reach the same byte.
    func terminalDidRingBell() {
        // Not raised on the pane the user is already reading — the marker exists to label a
        // tab you are *not* looking at, and lighting up the front tab trains the eye to ignore
        // it. Same guard as `TerminalPane.terminalViewDidRingBell`.
        guard !isActiveDocument else { return }
        // Reproduces the audible half too. `TerminalPane` gets `NSSound.beep()` by inheriting
        // SwiftTerm's default; libghostty's delegate REPLACES its default rather than
        // supplementing it, so a pane that only set the marker would silently make the bell
        // quieter than the other engine's. Two panes that disagree about whether the bell
        // makes a sound is exactly the divergence this probe must not introduce.
        NSSound.beep()
        raiseAttention()
    }

    /// The shell exited and the surface is done, so the tab should close.
    ///
    /// Deliberately does NOT set `.failed`, for the reason `TerminalPane.processTerminated`
    /// spells out: this fires when the *shell itself* exits, at which point the pane is
    /// closing, and a status on a tab about to vanish is a status nobody reads.
    func terminalDidClose(processAlive: Bool) {
        diag("surface closed (processAlive=\(processAlive)) — closing the tab")
        documentDelegate?.documentDidTerminate(self)
    }

    /// OSC 133 — a command inside the live shell finished, with its exit code and duration.
    ///
    /// **This is the signal `DocumentStatus` was designed around and has never been able to
    /// receive.** That enum models `.running`, `.succeeded` and `.failed` and marks all three
    /// "Not wired", each annotated with the libghostty delegate that would populate it — this
    /// one. Building OSC 133 parsing on SwiftTerm to reach them was costed at ~3 days of work
    /// that would be written twice, so the presentation was built and the signal was left for
    /// the engine that already emits it.
    ///
    /// Still not wired here, and that is a scope decision rather than an oversight. Setting
    /// `.succeeded`/`.failed` correctly needs a policy this probe has not settled: how long a
    /// finished command's status should persist, whether a fast command should register at
    /// all, and what happens when the user is already looking at the tab. Guessing now would
    /// put a half-considered behaviour in front of the operator during the exact stretch of
    /// daily use that is supposed to be evaluating the engine. Phase 4 wires it deliberately;
    /// today it proves the signal ARRIVES, which is what the probe needs to know.
    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        diag("""
            OSC 133 command finished: exit=\(exitCode.map(String.init) ?? "nil") \
            in \(String(format: "%.1f", Double(durationNanos) / 1_000_000))ms \
            — signal ARRIVES; status mapping is Phase 4
            """)
    }
}
