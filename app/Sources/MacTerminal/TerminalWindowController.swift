//
//  TerminalWindowController.swift
//  One window == one tab. Tabs are real macOS window tabs.
//
//  Using the system's native window tabbing (tabbingIdentifier +
//  addTabbedWindow) rather than a hand-rolled tab bar buys, for free: correct
//  ⌘⇧[ / ⌘⇧] cycling, the tab overview, drag-to-reorder, drag-out-to-detach,
//  merge-all-windows, full-screen behaviour, and VoiceOver support. A custom tab
//  strip would have to reimplement all of it and would still look subtly wrong.
//

import AppKit

@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate, TerminalPaneDelegate {
    /// Shared identifier is what makes separate windows join one tab group.
    private static let tabbingIdentifier = "com.macterminal.terminal"

    /// Every open controller, so the app can find one to attach a new tab to and
    /// knows when the last window is gone.
    private(set) static var open: [TerminalWindowController] = []

    let pane: TerminalPane

    init(config: AppConfig) {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 600)
        self.pane = TerminalPane(config: config, frame: frame)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .preferred
        window.title = "Terminal"
        // Match the terminal's own background so the titlebar area does not flash
        // a mismatched colour on open or during a live resize.
        window.backgroundColor = config.theme.background
        window.titlebarAppearsTransparent = false
        window.contentView = pane.view
        window.minSize = NSSize(width: 320, height: 200)

        super.init(window: window)

        window.delegate = self
        pane.delegate = self
        // Restore position/size per identifier across launches.
        window.setFrameAutosaveName("MacTerminalWindow")
        window.makeFirstResponder(pane.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — windows are created programmatically")
    }

    // MARK: - Lifecycle

    func present() {
        Self.open.append(self)
        pane.start()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Open as a tab on the frontmost existing window, falling back to a plain
    /// window when there is nothing to attach to.
    func presentAsTab(relativeTo host: NSWindow?) {
        Self.open.append(self)
        pane.start()
        if let host, let window {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - TerminalPaneDelegate

    func paneDidTerminate(_ pane: TerminalPane) {
        // The shell exited (user typed `exit`, or it crashed) — close the tab,
        // matching every other terminal's behaviour.
        close()
    }

    func pane(_ pane: TerminalPane, didChangeTitle title: String) {
        window?.title = title.isEmpty ? "Terminal" : title
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
