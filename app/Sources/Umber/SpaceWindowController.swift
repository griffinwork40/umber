//
//  SpaceWindowController.swift
//  One window == one Space == one project root. Documents live inside it.
//
//  Native macOS window tabbing (tabbingIdentifier + addTabbedWindow) is KEPT and
//  re-pointed: a system tab is now a *Space*, not a shell. That is the whole
//  argument for branch (C) (plan §12.3) — ⌘⇧[ / ⌘⇧] cycling, the tab overview,
//  drag-to-reorder, drag-out-to-detach, Merge All Windows, full-screen behaviour
//  and VoiceOver all stay free, and they land at the level where detaching and
//  merging actually mean something: a project.
//
//  What a system tab could NOT do is documents. A window tab *is* an NSWindow, so
//  a mixed terminal/editor strip would give every document its own contentView and
//  there could be no shared, full-height sidebar (plan §12.2). Documents therefore
//  live in `SpaceViewController`'s hand-rolled strip. Two tab levels, each using
//  the mechanism that fits it.
//

import AppKit

@MainActor
final class SpaceWindowController: NSWindowController, NSWindowDelegate,
    SpaceViewControllerDelegate
{
    /// Shared identifier is what makes separate windows join one tab group.
    private static let tabbingIdentifier = "com.griffinlong.umber.space"

    /// Every open Space, so the app can attach a new tab to one, fan a config
    /// reload across all of them, and know when the last one is gone.
    private(set) static var open: [SpaceWindowController] = []

    let space: SpaceViewController

    /// This Space's project root. Stored, not just handed to `SpaceViewController`,
    /// so `AppDelegate.openFolder` can focus an already-open Space for a folder
    /// instead of opening a second Space onto the same directory.
    let root: URL

    init(config: AppConfig, root: URL) {
        self.root = root
        let frame = NSRect(x: 0, y: 0, width: 1100, height: 680)
        self.space = SpaceViewController(config: config, root: root)

        // NOT .fullSizeContentView. That flag makes the content view span the
        // whole window frame, including the 28pt the titlebar occupies — and
        // since the titlebar here is opaque, it hid the terminal's top ~1.7
        // rows. Row 0 is where a fresh prompt, the caret, and typed echo all
        // live, so the pane looked empty and dead while working perfectly:
        // measured contentView 600pt vs contentLayoutRect 572pt at 37 rows.
        // A sidebar item is the textbook reason to reach for the flag, and it is
        // still declined: AppKit would probably propagate the safe area correctly
        // now that the terminal sits two levels deeper, but "probably" is not worth
        // re-opening a bug that cost real debugging (plan §12.4 item 6).
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .preferred
        // The system tab bar shows window titles, and a system tab is a Space — so
        // the title names the project and the *subtitle* carries the active
        // document. Titling the window after the shell would make every project's
        // tab read "zsh" (plan §12.4 item 1).
        window.title = root.lastPathComponent
        // Match the terminal's own background so the titlebar area does not flash
        // a mismatched colour on open or during a live resize. A nil theme leaves
        // SwiftTerm on its own defaults, whose background is black
        // (`Colors.swift:37` defaultBackground) — so match that, not the system
        // window colour, or the chrome and the terminal disagree.
        window.backgroundColor = config.effectiveBackground
        // Set on the window so it cascades to every system-drawn surface at once —
        // the sidebar's vibrant material, the source-list selection pill, the label
        // colours, the scroller knob and the titlebar. Without it they all follow
        // System Settings instead of the theme, which is what put a Light-Mode grey
        // file tree against a black terminal. See `AppConfig.appearance`.
        window.appearance = config.appearance
        window.titlebarAppearsTransparent = false
        window.contentViewController = space
        // Wider floor than the old terminal-only window: below this the sidebar's
        // 150pt minimum plus the document area's 240pt cannot both be honoured and
        // the split view starts fighting itself.
        window.minSize = NSSize(width: 480, height: 240)

        super.init(window: window)

        window.delegate = self
        space.spaceDelegate = self
        // Restore position/size per identifier across launches.
        window.setFrameAutosaveName("UmberWindow")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — windows are created programmatically")
    }

    // MARK: - Lifecycle

    func present() {
        Self.open.append(self)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        openFirstDocument()
    }

    /// Open as a system tab on the frontmost existing Space, falling back to a
    /// plain window when there is nothing to attach to.
    func presentAsTab(relativeTo host: NSWindow?) {
        Self.open.append(self)
        if let host, let window {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
        openFirstDocument()
    }

    /// Deferred until the window is on screen, and forced through a layout pass
    /// first. `TerminalPane` sizes its SwiftTerm view from the frame it is handed,
    /// and the document container's bounds are zero until the split view has laid
    /// out — starting the shell before that would hand it a 0×0 pty and a bogus
    /// initial `SIGWINCH`.
    private func openFirstDocument() {
        space.view.layoutSubtreeIfNeeded()
        space.addTerminalDocument()
    }

    // MARK: - SpaceViewControllerDelegate

    func spaceViewController(_ controller: SpaceViewController, didChangeDocumentTitle title: String) {
        window?.subtitle = title
    }

    func spaceViewControllerDidCloseLastDocument(_ controller: SpaceViewController) {
        // A Space with no documents has nothing to show; closing matches every
        // other terminal's behaviour when the last shell in a tab exits.
        close()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // The agent running in the terminal beside the tree is what mutates these
        // files, so "you came back to this window" is very close to the moment the
        // tree went stale. See `FileTreeViewController.refresh()`.
        space.refreshFileTree()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
