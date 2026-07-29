//
//  SpaceDocument.swift
//  What is allowed to live in a Space's document strip.
//

import AppKit

/// What a document wants the user to know, when the user is not looking at it.
///
/// Umber exists to host a long-running agent REPL, and the failure mode that matters
/// is three documents open where one is blocked on input, one finished four minutes
/// ago and one failed — with the strip rendering all three identically. This is the
/// model behind fixing that.
///
/// **Deliberately larger than what is wired today.** Only `.idle` and `.attention`
/// can be reached on the current foundation; `.running`, `.succeeded` and `.failed`
/// are modelled but unreachable, each noted below with the libghostty delegate that
/// will populate it. That is not speculative design — the replacement of SwiftTerm by
/// libghostty is already decided (probe plan §6.2, verdict "proceed with D"), and the
/// telemetry those cases need arrives with it as `TerminalSurfaceCommandFinishedDelegate`
/// (`exitCode` + `durationNanos`) and `TerminalSurfaceBellDelegate`. Building OSC 133
/// parsing on SwiftTerm to reach them now would be ~3 days of work written twice, so
/// the presentation is built and the signals are wired only where they are cheap.
///
/// Ordered by how loudly each one deserves to interrupt, so the strip can compare.
enum DocumentStatus: Int, Comparable {
    /// Nothing to say. Every document's resting state.
    case idle = 0

    /// Work in progress. **Not wired** — needs a command-start boundary, i.e. OSC 133
    /// `A`/`C`, which arrives free as libghostty's
    /// `TerminalSurfaceCommandFinishedDelegate` (§6.2) rather than being parsed here.
    case running = 1

    /// Finished cleanly. **Not wired** — same delegate, `exitCode == 0`. Worth having
    /// separately from `.idle` because "your build is done" is information and
    /// "nothing is happening" is not.
    case succeeded = 2

    /// Finished badly. **Not wired** — same delegate, `exitCode != 0`.
    case failed = 3

    /// The document is asking for you. Wired today, from the terminal bell: an agent
    /// REPL blocked on a prompt beeps, and `\a` is the one attention signal that
    /// crosses a pty without shell integration. Ranked highest because it is the only
    /// state where the program is *waiting* rather than reporting.
    case attention = 4

    static func < (lhs: DocumentStatus, rhs: DocumentStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Spoken by VoiceOver as part of the tab's label. Nil for `.idle` — appending
    /// "idle" to every tab is noise, and the absence is the information.
    var accessibilityDescription: String? {
        switch self {
        case .idle: return nil
        case .running: return "running"
        case .succeeded: return "finished"
        case .failed: return "failed"
        case .attention: return "needs attention"
        }
    }
}

/// One document inside a Space — what a tab in the in-window strip points at.
///
/// This protocol is the entire point of the (C) restructure (plan §12.3). Terax's
/// tab strip is a flat *heterogeneous* union of eight kinds — terminal, editor,
/// preview, markdown, and four diff/history kinds — all in ONE strip
/// (`terax-ai/src/modules/tabs/lib/useTabs.ts:114-122`). Native macOS window tabs
/// cannot express that, because a window tab **is** an `NSWindow`: an editor tab
/// beside a terminal tab would be a second window with its own `contentView`,
/// hence no shared sidebar and no project-level grouping (plan §12.2). So
/// documents get a custom strip, and this protocol is the seam they plug into.
///
/// `TerminalPane` was the only conformer until `FileViewerPane` landed, and that
/// mattered more than it looked: a protocol with one implementor is a *description*
/// of that implementor, not a proven seam. Extracting the second one found three
/// places where the container had quietly stayed terminal-shaped —
/// `SpaceViewController.apply(config:)` fanned out over `terminalPanes` only, the
/// file-tree handler reached for `activeTerminalPane`, and `AppDelegate`'s zoom
/// anchored on `[TerminalPane]`. All three would have compiled and rendered fine
/// with a second document kind installed, and silently done nothing to it.
///
/// Hence the appearance and zoom members below are **hard requirements with no
/// default implementations**, deliberately. A default no-op would restore exactly
/// the failure mode just removed: a future editor/diff/Ghostty conformer that
/// forgets font zoom would compile, render, and ignore ⌘+ forever. Requiring them
/// turns that into a build error at the moment the conformer is written.
@MainActor
protocol SpaceDocument: AnyObject {
    /// Deliberately *not* named `view`. `TerminalPane.view` is an
    /// `UmberTerminalView`, and Swift does not permit a subclass type to witness a
    /// get-only property requirement declared as the supertype — so naming this
    /// `view` would force a pointless type-erasing shim on every conformer.
    var documentView: NSView { get }

    var documentTitle: String { get }

    /// SF Symbol drawn in the tab, so terminal / editor / diff tabs are
    /// distinguishable at a glance once the strip is genuinely mixed.
    var documentSymbolName: String { get }

    /// Called when this document becomes the visible one — the moment to take
    /// first responder, so typing lands in the terminal without a stray click.
    func documentDidBecomeActive()

    /// ⌘R reloaded `~/.config/umber/config.json`, or the Space handed over a new
    /// one. Every document paints, so every document owns re-reading its theme.
    func apply(config: AppConfig)

    /// The size this document is currently rendering at, so a zoom applied in one
    /// tab can be mirrored into the others (`AppDelegate.zoomAllDocuments`).
    var currentFontSize: CGFloat { get }

    /// `persist: false` is for applying someone else's already-stored zoom (a
    /// reload, or a newly-opened tab) — only a real user gesture should write.
    func setFontSize(_ size: CGFloat, persist: Bool)

    /// ⌘0 — back to the configured size, dropping the stored zoom.
    func resetFontSize()

    /// The Space's window became key. Default no-op: this exists because the thing
    /// mutating these files is an agent running in the terminal beside them, so
    /// "you came back to this window" is almost exactly the moment a document's
    /// content is stale — the same reasoning as `FileTreeViewController.refresh()`.
    /// A terminal is fed by its pty and needs nothing; a file viewer needs to
    /// re-read or it quietly shows you a file that no longer exists on disk.
    func documentWindowDidBecomeKey()

    /// Unsaved changes, drawn as a dot in the tab strip.
    var documentIsEdited: Bool { get }

    /// What this document currently wants the user to know, drawn in the tab strip.
    ///
    /// On the protocol rather than on `TerminalPane` because it is not a terminal
    /// concept: a file viewer whose file was rewritten under it is in exactly the same
    /// position — something happened in a tab you are not looking at. Engine-agnostic
    /// for the same reason the zoom members are (see the note above): the foundation
    /// under `TerminalPane` is already scheduled for replacement by libghostty
    /// (`.afk/plans/emulator-foundation-probe-and-vendor-integrity.md` §6.2), and a
    /// status enum shaped around SwiftTerm's callbacks would be rewritten with it.
    var documentStatus: DocumentStatus { get }

    /// Return false to veto a close (⌘W, the tab's ×, closing the Space, quitting).
    /// Implementors that can hold unsaved work MUST prompt here — every close path
    /// in the app funnels through it, so this is the single choke point between a
    /// dirty buffer and silent data loss.
    func documentShouldClose() -> Bool

    /// ⌘S. Returns false if the save failed or the user cancelled.
    func saveDocument() -> Bool
}

/// What a document tells its Space when something happened to it that the container
/// has to react to.
///
/// Declared here, beside `SpaceDocument`, because these are document-level events, not
/// terminal-level ones — the container's reaction to each is already kind-agnostic
/// (`syncDocumentChrome()`, `closeDocument(at:)`). This was `TerminalPaneDelegate` in
/// `TerminalPane.swift` and typed all three callbacks to the concrete class, which gave
/// a second engine-backed conformer *no route to the container at all* for shell-exit
/// and title-change — and title changes drive both the strip and the window subtitle
/// (`emulator-foundation-probe-and-vendor-integrity.md` §8.2, "The delegate cannot
/// carry it"). Widening it and moving it here is site 1 of
/// `libghostty-swap-sequencing-2026-07-28.md` §2.
///
/// The parameter type is `SpaceDocument` rather than `ShellHosting` even though only a
/// shell-backed pane emits these today: "my title changed" and "I am finished" are not
/// shell concepts. A file viewer that grew a background reload would report through
/// exactly these callbacks, and narrowing the parameter now would be a second migration
/// later for no gain — the reverse of the `focusedShellHost` decision below, where the
/// *action* genuinely requires a shell.
///
/// Deliberately unrelated to `FileViewerPaneDelegate`, which is repaint-only and stays
/// where it is: merging them would make every conformer answer callbacks for a concern
/// it does not have. Two narrow inbound protocols is the correct shape while their
/// event sets are disjoint.
@MainActor
protocol SpaceDocumentDelegate: AnyObject {
    /// The document's work is over and it should be closed — a shell exited. Named for
    /// the document rather than the pane because the container closes *a tab*, and it
    /// looks the document up by identity rather than trusting an index
    /// (`SpaceViewController+Delegates.swift`).
    func documentDidTerminate(_ document: SpaceDocument)

    /// The document reported a new title (OSC 0/2 for a shell). Drives the tab strip
    /// and, when this is the active document, the window subtitle.
    func document(_ document: SpaceDocument, didChangeTitle title: String)

    /// `documentStatus` changed — the tab strip needs to repaint.
    func documentDidChangeStatus(_ document: SpaceDocument)
}

/// A document that reports the events above, exposing the slot its Space writes itself
/// into.
///
/// Exists so `SpaceViewController.add(document:)` can wire the delegate on any reporting
/// conformer without naming one: the alternative it replaced was
/// `(document as? TerminalPane)?.delegate = self`, which compiles and then silently
/// leaves a second engine-backed pane's delegate nil — a tab that renders and never
/// retitles, which is precisely the "silently inert rather than loudly broken" class
/// `emulator-foundation-probe-and-vendor-integrity.md` §8.2 catalogues. A future
/// `GhosttyPane` conforms and is wired by the same line.
///
/// Separate from `SpaceDocument` rather than a member of it because it is genuinely
/// optional: `FileViewerPane` reports edited-state through its own repaint-only
/// `FileViewerPaneDelegate` and has no use for these three callbacks, and a required
/// slot it left nil would be a member that lies. This is the same reasoning the zoom
/// members get in reverse — they are required because a conformer that skips them is
/// *broken*, while a conformer that skips this one is merely quiet.
@MainActor
protocol SpaceDocumentReporting: SpaceDocument {
    /// Named `documentDelegate`, not `delegate`, because conformers are AppKit-adjacent
    /// types that may already own a `delegate` meaning something else entirely — and a
    /// protocol requirement silently witnessed by an unrelated inherited property is a
    /// bug with no compiler error attached.
    var documentDelegate: SpaceDocumentDelegate? { get set }
}

extension SpaceDocument {
    /// The four defaults below are all *correct* for a live document rather than
    /// merely convenient, which is what separates them from the zoom members above:
    /// a terminal has nothing to re-read, no buffer to lose, and nothing to write.
    /// A conformer that ignores them is right by default, not broken by default.
    func documentWindowDidBecomeKey() {}
    var documentIsEdited: Bool { false }
    func documentShouldClose() -> Bool { true }
    func saveDocument() -> Bool { true }

    /// `.idle` is the honest answer for a document that cannot produce a status, which
    /// is why this one gets a default while the zoom members do not: a conformer that
    /// never has anything urgent to say is correctly silent, not silently broken.
    var documentStatus: DocumentStatus { .idle }
}

/// The stored `documentDelegate` property on `TerminalPane` is the whole witness, so this
/// is a declaration of intent rather than code: it is what makes
/// `SpaceViewController.add(document:)`'s conditional wire-up reach this pane.
extension TerminalPane: SpaceDocumentReporting {}

extension TerminalPane: SpaceDocument {
    var documentView: NSView { view }

    /// Falls back rather than rendering an empty tab: `currentTitle` stays empty
    /// until the shell emits OSC 0/2, which does not happen until the first prompt
    /// paints — so a brand-new tab would otherwise be a blank sliver.
    var documentTitle: String { currentTitle.isEmpty ? "Terminal" : currentTitle }

    var documentSymbolName: String { "terminal" }

    var documentStatus: DocumentStatus { status }

    func documentDidBecomeActive() {
        // The pane's own view, not the container: SwiftTerm reads key events on
        // the terminal view itself, and a container in the responder chain would
        // swallow the first keystroke.
        view.window?.makeFirstResponder(view)
        // You are now looking at it, so whatever it was trying to tell you has landed.
        // Here rather than in a focus notification because this is the one call that
        // means "this document is the visible one" — see `clearAttention()`.
        clearAttention()
    }
}
