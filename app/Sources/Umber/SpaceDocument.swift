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
/// `TerminalPane` is the only conformer today. Adding an editor later should mean
/// writing a conformer — not touching the container.
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
