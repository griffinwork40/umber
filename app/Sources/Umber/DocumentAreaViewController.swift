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
    let container = NSView()

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

    func present(documentView: NSView) {
        for subview in container.subviews where subview !== documentView {
            subview.removeFromSuperview()
        }
        if documentView.superview !== container {
            documentView.frame = container.bounds
            container.addSubview(documentView)
        }
        documentView.frame = container.bounds
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
        for subview in container.subviews { subview.frame = container.bounds }
    }
}
