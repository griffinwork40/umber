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
    /// **NOT YET OBSERVED IN THIS APP, and that correction matters.** The spike saw OSC 7 by
    /// transcript (§6.2 Q1) and this callback is wired for it, but `check-ghostty-pane.sh`'s
    /// kill-criterion run reports `pwd=-`: within 12 seconds the shell sent a TITLE carrying
    /// the path and no OSC 7. So what is proven today is that the surface spawns a shell that
    /// talks; that ghostty's shell integration injects OSC 7 under Umber specifically is still
    /// inherited from the spike rather than re-confirmed here. Phase 4 must verify it before
    /// the 750ms kernel poller is retired for this engine — retiring a working mechanism on an
    /// unconfirmed replacement is how the sidebar silently stops following.
    ///
    /// Deliberately only RECORDS it rather than driving the file tree. Moving the tree is
    /// `followDirectory(_:)`'s job and it has exactly one caller by design ("the only place in
    /// the app that moves the tree"); adding a second entry point from here, while the poller
    /// is still live for `TerminalPane`, would give the tree two masters that disagree. Wiring
    /// this through properly is Phase 4, and it is the point at which the poller can become
    /// per-engine rather than always-on.
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
