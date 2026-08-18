//
//  SpaceViewController+Splits.swift
//  The model half of split panes: creating and closing a split, tracking per-tab
//  split peer documents, and wiring the container to show/hide the split view.
//
//  Its own file because this is one whole concern ("a tab can have a split peer")
//  separable from the document-list operations in SpaceViewController.swift and from
//  the display plumbing in DocumentAreaViewController.swift. The stored property
//  (splitPeers) lives in SpaceViewController.swift — Swift extensions cannot add
//  stored properties, and the setter on `documents` is private to that file — while
//  all the methods that read and manipulate it live here.
//
//  v1 scope: exactly ONE split per tab (2 panes). ⌘⇧D splits right (horizontal).
//  The split peer is NOT in documents[] — it does not appear as a tab. The tab strip
//  stays 1:1 with documents[]. ⌘W when split collapses the split (closes the peer),
//  keeping the primary tab; ⌘W when unsplit closes the tab as before.
//

import AppKit

extension SpaceViewController {

    // MARK: - Split creation

    /// ⌘⇧D — split the active terminal horizontally, opening a new pane to the right.
    ///
    /// Wired from AppMenu.swift. Uses the same construction path as addTerminalDocument
    /// (SpaceViewController+DocumentConstruction.swift) so both engines are handled,
    /// but deliberately does NOT call add(document:) — the peer must not appear as a tab.
    @objc func splitHorizontal(_ sender: Any?) {
        makeSplit(direction: .horizontal)
    }

    /// Vertical split — @objc stub for v1. The stub lets a future caller wire ⌘⇧E
    /// through the responder chain without touching AppMenu.swift. Implement by
    /// calling makeSplit(direction: .vertical) when vertical is enabled.
    @objc func splitVertical(_ sender: Any?) {}

    /// Create a split peer for the active document in the given direction.
    ///
    /// Does nothing when: no active document, the active document is not a terminal
    /// (FileViewerPane has no shell whose cwd to inherit), or this tab already has a
    /// split peer (v1 allows exactly one split per tab).
    private func makeSplit(direction: SplitContainerView.Direction) {
        guard let primary = activeDocument else { return }
        // Only allow splitting terminal documents. A file viewer has no shell.
        guard primary is ShellHosting else { return }
        // v1: one split per tab maximum.
        guard !hasSplit(for: primary) else { return }

        // Inherit the focused pane's working directory so the new pane opens in the
        // same location the user is already in. Falls back to the Space root before
        // the first OSC 7 fires (new tab, pre-first-prompt).
        let peerDirectory = (primary as? ShellHosting)?.currentDirectory ?? root

        // Build the peer via the same engine switch as addTerminalDocument
        // (SpaceViewController+DocumentConstruction.swift:53-61). The frame uses
        // the current container bounds so the initial size is sane before the split
        // layout runs for the first time.
        let frame = documentArea.container.bounds
        let peer: SpaceDocument
        switch config.engine {
        case .swiftTerm:
            peer = TerminalPane(config: config, frame: frame, workingDirectory: peerDirectory)
        case .ghostty:
            peer = GhosttyPane(config: config, frame: frame, workingDirectory: peerDirectory)
        }

        // Wire the delegate so the peer can report title changes and exit.
        (peer as? any SpaceDocumentReporting)?.documentDelegate = self

        // Register in splitPeers BEFORE starting the shell, so if the shell exits
        // immediately the teardown path (documentDidTerminate via the delegate above)
        // can find it and clean up correctly.
        splitPeers[ObjectIdentifier(primary)] = peer

        // Start the shell. The beforeActivating ordering from addTerminalDocument is
        // not needed here — the peer lives beside the primary, not replacing it, so
        // the tab strip geometry is already settled.
        (peer as? any ShellStarting)?.start()

        // Hand the peer's view to the container so it appears in the split layout.
        documentArea.presentSplit(
            primaryView: primary.documentView,
            splitView: peer.documentView,
            direction: direction)
    }

    // MARK: - Split closing

    /// Collapse the split for the active document, tearing down the peer.
    ///
    /// v1 behavior: always closes the PEER (the right-hand pane), keeping the primary
    /// tab. This is intentionally simpler than a focus-sensitive swap — the split peer
    /// is an auxiliary view, and "close the split" means "remove the auxiliary". Called
    /// from AppDelegate.closeDocument(_:) when the active tab has a split; the ⌘W
    /// routing lives in AppDelegate+EditorActions.swift.
    func closeSplitPane() {
        guard let primary = activeDocument,
              let peer = splitPeers.removeValue(forKey: ObjectIdentifier(primary)) else { return }
        peer.documentWillClose()
        peer.documentView.removeFromSuperview()
        documentArea.dismissSplit()
        // Restore focus to the primary pane.
        primary.documentDidBecomeActive()
    }

    // MARK: - Queries

    func splitPeer(for document: SpaceDocument) -> SpaceDocument? {
        splitPeers[ObjectIdentifier(document)]
    }

    func hasSplit(for document: SpaceDocument) -> Bool {
        splitPeers[ObjectIdentifier(document)] != nil
    }

    // MARK: - Peer-initiated termination

    /// Called from SpaceViewController+Delegates when a split peer's shell exits.
    ///
    /// A peer document is NOT in documents[], so documentDidTerminate's normal path
    /// (firstIndex lookup → closeDocument) finds nothing. This handles the peer case:
    /// find the primary, remove the entry from splitPeers, and collapse the split.
    func terminateSplitPeer(_ document: SpaceDocument) {
        for primary in documents where splitPeers[ObjectIdentifier(primary)] === document {
            splitPeers.removeValue(forKey: ObjectIdentifier(primary))
            document.documentWillClose()
            document.documentView.removeFromSuperview()
            documentArea.dismissSplit()
            primary.documentDidBecomeActive()
            return
        }
    }

    // MARK: - Teardown (called when a tab closes, so its peer closes too)

    /// Tear down the split peer for a document that is itself about to close.
    ///
    /// Called from SpaceViewController.closeDocument(at:) BEFORE the primary is
    /// removed from the document list, so the peer can be cleaned up while the
    /// primary's identity is still available as the dictionary key. Also called from
    /// tearDownAllDocuments() in SpaceViewController+Closing.swift.
    func teardownSplit(for document: SpaceDocument) {
        guard let peer = splitPeers.removeValue(forKey: ObjectIdentifier(document)) else { return }
        peer.documentWillClose()
        peer.documentView.removeFromSuperview()
        documentArea.dismissSplit()
    }
}
