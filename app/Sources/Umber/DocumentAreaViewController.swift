//
//  DocumentAreaViewController.swift
//  The right-hand region of a Space: document tab strip on top, active document below.
//
//  Its own file because this is a second view controller, not a helper — it owns a
//  view hierarchy, a manual layout pass, and the strip's visibility rule, none of
//  which is about managing a document list. It was nested and `private` inside
//  `SpaceViewController.swift` only because it had nowhere else to live; the 350-LOC
//  ceiling supplied the reason to give it one (AFK.md, "Conventions"). The dependency
//  runs one way — the container drives this, this knows nothing about
//  `SpaceViewController` or `SpaceDocument` — so adding a document kind still never
//  reaches here.
//

import AppKit

// MARK: - Document area

/// The right-hand region: tab strip on top, active document filling the rest.
///
/// Laid out manually in `viewDidLayout` rather than with Auto Layout. The document
/// view is a SwiftTerm view that already ships with `autoresizingMask =
/// [.width, .height]` (`TerminalPane.swift:49`) and is sized by frame everywhere
/// else in this app; mixing a constraint-based parent into that is how a terminal
/// ends up one row short.
@MainActor
// Internal rather than `private`: it was `private` as a nested type, and moving it
// to its own file makes that unrepresentable — `SpaceViewController` holds one as a
// stored property, and a file-scoped `private` type cannot be named from another
// file. Internal is the narrowest level that compiles. Nothing outside
// `SpaceViewController` constructs one, and it is not `public`.
final class DocumentAreaViewController: NSViewController {
    let strip = DocumentTabStrip(frame: .zero)
    // SplitContainerView rather than a plain NSView: it holds 1 or 2 child views
    // with a draggable divider, using the same manual frame-based layout this file
    // already uses — no Auto Layout, no NSSplitView (see the header comment above).
    let container = SplitContainerView()

    private var isStripVisible = false

    override func loadView() {
        let root = NSView()
        root.addSubview(container)
        view = root
    }

    /// Hidden at a single document, matching Ghostty and Terminal.app: with one
    /// terminal open this app should still just look like a terminal, and the strip
    /// costs 30pt of rows that the primary surface would rather have. ⌘T brings it
    /// back the moment there is anything to switch between.
    func setStripVisible(_ visible: Bool) {
        guard visible != isStripVisible else { return }
        isStripVisible = visible
        if visible {
            view.addSubview(strip)
        } else {
            strip.removeFromSuperview()
        }
        view.needsLayout = true
        viewDidLayout()
    }

    /// Present a single document view, with no split. Delegates to the container's
    /// split-aware API so it stays the single authority on what is displayed.
    func present(documentView: NSView) {
        if container.isSplit { container.removeSplit() }
        container.setPrimary(documentView)
    }

    /// Present a two-pane split: primary on the left (or bottom for vertical).
    ///
    /// Called from SpaceViewController.selectDocument(at:) when the selected tab has
    /// a split peer. Clears any existing split first so switching between two split
    /// tabs does not leave a stale peer in the container.
    func presentSplit(
        primaryView: NSView, splitView: NSView,
        direction: SplitContainerView.Direction
    ) {
        if container.isSplit { container.removeSplit() }
        container.setPrimary(primaryView)
        container.addSplit(splitView, direction: direction)
    }

    /// Collapse the split, returning to single-pane display.
    ///
    /// Called from closeSplitPane(), teardownSplit(for:), and terminateSplitPeer(_:)
    /// in +Splits.swift. The container's removeSplit() removes the peer view from the
    /// hierarchy — that is the single owner of the removeFromSuperview call.
    func dismissSplit() {
        container.removeSplit()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        let stripHeight = isStripVisible ? DocumentTabStrip.height : 0
        // Non-flipped coordinates: the strip is at the TOP, so it takes the high y.
        strip.frame = NSRect(
            x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight)
        container.frame = NSRect(
            x: 0, y: 0, width: bounds.width, height: bounds.height - stripHeight)
        // Children are distributed by SplitContainerView.layout(). Call it
        // immediately rather than deferring via needsLayout so terminal rows/cols
        // are correct on the same pass that resized the container — deferred layout
        // would leave the terminal with a stale frame until the next run loop tick.
        container.layout()
    }
}
