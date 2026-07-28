//
//  SpaceDocument.swift
//  What is allowed to live in a Space's document strip.
//

import AppKit

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

    /// Return false to veto a close (⌘W, the tab's ×, closing the Space, quitting).
    /// Implementors that can hold unsaved work MUST prompt here — every close path
    /// in the app funnels through it, so this is the single choke point between a
    /// dirty buffer and silent data loss.
    func documentShouldClose() -> Bool

    /// ⌘S. Returns false if the save failed or the user cancelled.
    func saveDocument() -> Bool
}

extension SpaceDocument {
    /// The three defaults below are all *correct* for a live document rather than
    /// merely convenient, which is what separates them from the zoom members above:
    /// a terminal has nothing to re-read, no buffer to lose, and nothing to write.
    /// A conformer that ignores them is right by default, not broken by default.
    func documentWindowDidBecomeKey() {}
    var documentIsEdited: Bool { false }
    func documentShouldClose() -> Bool { true }
    func saveDocument() -> Bool { true }
}

extension TerminalPane: SpaceDocument {
    var documentView: NSView { view }

    /// Falls back rather than rendering an empty tab: `currentTitle` stays empty
    /// until the shell emits OSC 0/2, which does not happen until the first prompt
    /// paints — so a brand-new tab would otherwise be a blank sliver.
    var documentTitle: String { currentTitle.isEmpty ? "Terminal" : currentTitle }

    var documentSymbolName: String { "terminal" }

    func documentDidBecomeActive() {
        // The pane's own view, not the container: SwiftTerm reads key events on
        // the terminal view itself, and a container in the responder chain would
        // swallow the first keystroke.
        view.window?.makeFirstResponder(view)
    }
}
