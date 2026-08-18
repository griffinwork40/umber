//
//  SpaceViewController+DocumentConstruction.swift
//  How a Space builds a terminal document.
//
//  Its own file for two reasons, one structural and one arithmetic.
//
//  Structural: `add(document:beforeActivating:)` in `SpaceViewController.swift` is deliberately
//  polymorphic — it installs any `SpaceDocument` and knows nothing about kinds. Deciding WHICH
//  kind to build is a different concern, and it is the concern that has to name `TerminalPane`
//  concretely. Keeping it here means the container proper still contains no pane knowledge at
//  all.
//
//  Arithmetic: `SpaceViewController.swift` was at 346 lines against a hard 350-line ceiling
//  (`Scripts/check-file-size.sh`). The convention when a file reaches the ceiling is to find
//  its seam and move one whole concern out rather than shave comments — this is that seam, and
//  moving `addTerminalDocument` here also bought the room for `closeDocument`'s teardown call.
//

import AppKit

extension SpaceViewController {
    /// Add a terminal document rooted at `workingDirectory`, defaulting to the Space's own
    /// `root`.
    ///
    /// The root default is the point. A Space *is* a project root (plan §12.4 item 1) and every
    /// terminal in it inherited `$HOME` instead, because this function created the pane without
    /// ever mentioning `root` — so ⌘T in a Space opened on a project landed outside that project
    /// and the first thing you typed was a `cd`. The root was already right here, one property
    /// away, which is exactly why it went unnoticed.
    ///
    /// `workingDirectory` is an override rather than a replacement so the tree's "New Terminal
    /// Here" can pass a subdirectory (`fileTree(_:didRequestNewTerminalAt:)`) without every other
    /// caller — first launch, ⌘T, the strip's `+` — having to restate the root it already implies.
    @discardableResult
    func addTerminalDocument(start: Bool = true, workingDirectory: URL? = nil) -> SpaceDocument {
        let directory = workingDirectory ?? root

        let pane = TerminalPane(
            config: config, frame: documentArea.container.bounds, workingDirectory: directory)

        // `beforeActivating`, not after, and this ordering is load-bearing rather than stylistic.
        // `start()` hands the pty its initial `winsize` from the view's *current* geometry
        // (SwiftTerm: `MacLocalTerminalView.swift:204-209` builds it from `terminal.rows`/`cols`),
        // while activation is what makes the tab strip appear at the second document — costing the
        // container ~30pt, i.e. about two rows (`DocumentAreaViewController.viewDidLayout`).
        // Starting after activation would therefore hand a *different* initial row count to every
        // terminal but the first and add a SIGWINCH before the first prompt. Both are reflow
        // inputs, and reflow is the one area of this app with a known upstream defect
        // (SwiftTerm #494, patched locally as `0002`), so the original sequence — append, start,
        // select — is reproduced exactly.
        add(document: pane, beforeActivating: { if start { pane.start() } })
        return pane
    }
}
