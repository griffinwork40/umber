//
//  AppDelegate.swift
//  App lifecycle and menus.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Surface config problems where the user will actually see them, instead
        // of silently substituting defaults and leaving them wondering why their
        // theme did nothing.
        for warning in config.warnings {
            FileHandle.standardError.write("config: \(warning)\n".data(using: .utf8)!)
        }
        buildMenu()
        newSpaceInWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Actions

    /// The root a Space gets when the user did not name one (⌘N, ⌘⇧N, first launch).
    ///
    /// The last root opened with ⌘O, falling back to `$HOME` — which is still the
    /// right *first* answer, because a login shell starts there anyway, but a poor
    /// steady-state one: you almost always want the project you were last in, not a
    /// home directory whose first screen is tool caches. See `LastSpaceRoot`.
    private var defaultSpaceRoot: URL {
        LastSpaceRoot.url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// ⌘N — a new Space, joining the existing tab group. A system tab *is* a Space
    /// under this design, and `tabbingMode = .preferred` already says macOS wants
    /// these tabbed; ⌘⇧N exists for when a genuinely separate window is wanted.
    @objc func newSpace(_ sender: Any?) {
        let host = NSApp.keyWindow ?? SpaceWindowController.open.last?.window
        SpaceWindowController(config: config, root: defaultSpaceRoot)
            .presentAsTab(relativeTo: host)
    }

    @objc func newSpaceInWindow(_ sender: Any?) {
        SpaceWindowController(config: config, root: defaultSpaceRoot).present()
    }

    /// ⌘O — choose a project folder and open it as a Space.
    ///
    /// This is what makes the sidebar file tree worth having: until now every Space
    /// rooted at `$HOME`, so the tree showed the home directory and nothing else was
    /// reachable. The root was already a threaded init parameter
    /// (`SpaceWindowController.init(config:root:)` → `SpaceViewController` →
    /// `FileTreeViewController`), so this action only has to supply a URL.
    ///
    /// Re-opening a folder that already has a Space focuses it instead of making a
    /// duplicate — two Spaces onto one root would give the same project two file
    /// trees and two titles with no way to tell them apart.
    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder to open as a Space."
        panel.prompt = "Open as Space"
        // Start where the focused Space already is, so opening a sibling project is
        // one level up rather than a walk from $HOME.
        panel.directoryURL = focusedSpaceWindow?.root ?? defaultSpaceRoot

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Recorded before the dedupe, not after: re-opening a folder that already
        // has a Space is still you saying "this is where I am working", and the
        // next ⌘N should land there even though this call goes on to just focus
        // the existing window.
        LastSpaceRoot.url = url

        // resolvingSymlinksInPath so /tmp and /private/tmp — or any symlinked
        // checkout — do not read as two different roots and defeat the dedupe.
        let target = url.resolvingSymlinksInPath()
        if let existing = SpaceWindowController.open.first(
            where: { $0.root.resolvingSymlinksInPath() == target })
        {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSApp.keyWindow ?? SpaceWindowController.open.last?.window
        SpaceWindowController(config: config, root: url).presentAsTab(relativeTo: host)
    }

    /// ⌘T — a new document inside the focused Space. This is the semantic change at
    /// the heart of the restructure: it used to spawn a whole NSWindow.
    @objc func newDocument(_ sender: Any?) {
        guard let space = focusedSpace else { return newSpace(sender) }
        space.addTerminalDocument()
    }

    /// ⌘W — close the *document*, falling through to the window only when it was the
    /// last one (`SpaceViewController` reports that back via its delegate). Wiring ⌘W
    /// straight to the window would throw away every other terminal in the project.
    @objc func closeDocument(_ sender: Any?) {
        guard let space = focusedSpace else { return NSApp.keyWindow?.performClose(sender) ?? () }
        space.closeActiveDocument()
    }

    @objc func nextDocument(_ sender: Any?) { focusedSpace?.cycleDocument(by: 1) }
    @objc func previousDocument(_ sender: Any?) { focusedSpace?.cycleDocument(by: -1) }

    /// ⌘1…⌘9. The index rides in the menu item's `tag` so nine items share one action.
    @objc func selectDocumentByIndex(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        focusedSpace?.selectDocument(at: item.tag - 1)
    }

    /// Re-read the config file and apply it to every open pane, so tuning the
    /// theme does not require restarting the app.
    @objc func reloadConfig(_ sender: Any?) {
        config = AppConfig.load()
        for warning in config.warnings {
            FileHandle.standardError.write("config: \(warning)\n".data(using: .utf8)!)
        }
        for controller in SpaceWindowController.open {
            controller.space.apply(config: config)
            controller.window?.backgroundColor = config.effectiveBackground
            // Re-derived on every reload, not just at init: editing the theme from
            // a dark background to a light one (or back) has to move the sidebar
            // and titlebar with it, or ⌘R leaves the chrome showing the old theme.
            controller.window?.appearance = config.appearance
        }
    }

    @objc func openConfigFile(_ sender: Any?) {
        let url = AppConfig.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // Write a commented starter file rather than opening nothing — a
            // config you can see is far easier to edit than one you must invent.
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.starterConfig.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    /// The Space whose window has focus, falling back to the most recently opened.
    /// Same resolution order as `focusedSpace`; this one keeps the window controller
    /// because `openFolder` needs its `root`, which `SpaceViewController` does not
    /// expose.
    private var focusedSpaceWindow: SpaceWindowController? {
        SpaceWindowController.open.first { $0.window === NSApp.keyWindow }
            ?? SpaceWindowController.open.last
    }

    private var focusedSpace: SpaceViewController? {
        focusedSpaceWindow?.space
    }

    /// Every terminal in every Space. Zoom and config reload are app-wide, so they
    /// need the flattened list rather than one pane per window as before.
    private var allPanes: [TerminalPane] {
        SpaceWindowController.open.flatMap { $0.space.terminalPanes }
    }

    private var focusedPane: TerminalPane? {
        focusedSpace?.activeTerminalPane ?? allPanes.last
    }

    /// Zoom every pane, not just the focused one. Per-pane sizing reads as a bug
    /// in a tabbed terminal: you zoom because the text is too small for your eyes
    /// and this screen, which is not a property of one tab — and now, not a
    /// property of one Space either (plan §12.4 item 7).
    private func zoomAllPanes(by delta: CGFloat) {
        guard let anchor = focusedPane else { return }
        let target = anchor.currentFontSize + delta
        anchor.setFontSize(target)
        // Mirror the anchor's post-clamp size so every pane agrees even at a bound.
        let settled = anchor.currentFontSize
        for pane in allPanes where pane !== anchor {
            pane.setFontSize(settled, persist: false)
        }
    }

    @objc func biggerFont(_ sender: Any?) { zoomAllPanes(by: 1) }
    @objc func smallerFont(_ sender: Any?) { zoomAllPanes(by: -1) }

    @objc func resetFont(_ sender: Any?) {
        for pane in allPanes { pane.resetFontSize() }
    }

    // MARK: - Menu

    private func buildMenu() {
        let appName = "Umber"
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openConfigFile(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig(_:)), keyEquivalent: "r")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu — was "Shell". Renamed because its nouns are now Spaces and
        // documents, and a document is not necessarily a shell any more.
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Space", action: #selector(newSpace(_:)), keyEquivalent: "n")
        let newWindowItem = NSMenuItem(
            title: "New Space in New Window", action: #selector(newSpaceInWindow(_:)),
            keyEquivalent: "n")
        newWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(newWindowItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Open Folder…", action: #selector(openFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newDocument(_:)), keyEquivalent: "t")
        // ⌘W closes the document. Closing the whole Space out from under the other
        // terminals in it is ⌘⇧W, which is the ordering every tabbed app uses.
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeDocument(_:)), keyEquivalent: "w")
        let closeSpaceItem = NSMenuItem(
            title: "Close Space", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeSpaceItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeSpaceItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu — the standard selectors; TerminalView implements them.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        // Scrollback search. Nothing here implements searching — SwiftTerm already
        // ships the engine, the find bar, and the validation:
        // `performFindPanelAction` is `@objc open`
        // (`Mac/MacTerminalView.swift:2169`), it dispatches on `NSFindPanelAction`
        // raw values to `showFindBar` / `performFind(next:)`, and
        // `validateUserInterfaceItem` (`:2119`) already returns true for
        // showFindPanel/next/previous and gates setFindString on an active
        // selection. `UmberTerminalView` inherits all of it, so this menu is the
        // only missing piece.
        //
        // Two details that are load-bearing:
        //   * target stays nil so AppKit walks the responder chain to the focused
        //     terminal view. A hardcoded target would break the moment splits exist.
        //   * `performFindPanelAction` early-returns unless the sender IS an
        //     NSMenuItem and reads `menuItem.tag`, so every item below must carry a
        //     tag or it silently does nothing.
        let findItems: [(String, String, NSEvent.ModifierFlags, NSFindPanelAction)] = [
            ("Find…", "f", [.command], .showFindPanel),
            ("Find Next", "g", [.command], .next),
            ("Find Previous", "g", [.command, .shift], .previous),
            ("Use Selection for Find", "e", [.command], .setFindString),
        ]
        for (title, key, mask, action) in findItems {
            let item = NSMenuItem(
                title: title,
                action: #selector(NSTextView.performFindPanelAction(_:)),
                keyEquivalent: key)
            item.keyEquivalentModifierMask = mask
            item.tag = Int(action.rawValue)
            editMenu.addItem(item)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        // Shown as ⌘+ because that is what people read, but a key equivalent of
        // "+" only matches the literal plus glyph — i.e. ⌘⇧=. Pressing ⌘= (what
        // everyone actually does, and what every other app honours) matched
        // nothing in v0.1, so zoom appeared not to work at all. Verified with a
        // performKeyEquivalent harness: a HIDDEN item still matches its key
        // equivalent, which is the standard way to register the ⌘= alias without
        // showing a duplicate row in the menu.
        viewMenu.addItem(withTitle: "Bigger Font", action: #selector(biggerFont(_:)), keyEquivalent: "+")
        let plusAlias = NSMenuItem(
            title: "Bigger Font", action: #selector(biggerFont(_:)), keyEquivalent: "=")
        plusAlias.isHidden = true
        viewMenu.addItem(plusAlias)
        viewMenu.addItem(withTitle: "Smaller Font", action: #selector(smallerFont(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetFont(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        // ⌃⌘F, not ⌘F. ⌘F belonged to full screen until scrollback search existed,
        // and ⌘F is search's key everywhere on this platform — so full screen moves
        // rather than search taking a non-standard chord. ⌃⌘F is also what macOS
        // itself uses (System Settings › Keyboard › Shortcuts), so this is a
        // correction to the platform default, not a compromise.
        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(fullScreenItem)
        viewMenu.addItem(.separator())
        // No custom action and no target: the responder chain reaches
        // SpaceViewController, which is the window's contentViewController and
        // inherits toggleSidebar(_:) from NSSplitViewController. Using the system
        // selector also gets the correct menu-item state and the collapse animation.
        viewMenu.addItem(
            withTitle: "Toggle Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "b")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Navigate menu — document-level movement, deliberately NOT folded into the
        // Window menu. That menu carries the standard role, and its native tab
        // commands (Show All Tabs, Move Tab to New Window) act on *Spaces*; putting
        // document navigation beside them would present two different tab levels as
        // one list.
        let navigateItem = NSMenuItem()
        let navigateMenu = NSMenu(title: "Navigate")
        let nextTabItem = NSMenuItem(
            title: "Next Tab", action: #selector(nextDocument(_:)),
            keyEquivalent: Self.functionKeyEquivalent(NSRightArrowFunctionKey))
        nextTabItem.keyEquivalentModifierMask = [.command, .option]
        navigateMenu.addItem(nextTabItem)
        let previousTabItem = NSMenuItem(
            title: "Previous Tab", action: #selector(previousDocument(_:)),
            keyEquivalent: Self.functionKeyEquivalent(NSLeftArrowFunctionKey))
        previousTabItem.keyEquivalentModifierMask = [.command, .option]
        navigateMenu.addItem(previousTabItem)
        navigateMenu.addItem(.separator())
        // ⌘1…⌘9 only — ⌘0 is Actual Size and predates this menu.
        for index in 1...9 {
            let item = NSMenuItem(
                title: "Tab \(index)", action: #selector(selectDocumentByIndex(_:)),
                keyEquivalent: String(index))
            item.tag = index
            navigateMenu.addItem(item)
        }
        navigateItem.submenu = navigateMenu
        mainMenu.addItem(navigateItem)

        // Window menu — giving it the standard role is what makes the native tab
        // commands (Show All Tabs, Move Tab to New Window, …) appear.
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// Arrow keys as a menu key equivalent: AppKit expresses them as function-key
    /// code points, not ASCII, so `"→"` or `"\u{2192}"` would silently never match.
    ///
    /// ⌘⌥← / ⌘⌥→ are verified safe against `KeyBindings.swift`: its guard is
    /// `intent == [.command]`, *exact* equality on the masked modifier set, so
    /// adding Option cannot collide with the ⌘←/⌘→ line-editing bytes (^A/^E) —
    /// the event falls through instead (plan §12.4 item 4).
    private static func functionKeyEquivalent(_ functionKey: Int) -> String {
        String(utf16CodeUnits: [unichar(functionKey)], count: 1)
    }

    private static let starterConfig = """
    {
      "// font": "any installed monospaced family; omit family for SF Mono (the system monospaced face, and the default)",
      "// font.size": "points, 6-48. Default 14. Cmd+ / Cmd- zoom live on top of this and persist; Cmd0 clears the zoom and hands control back to this value.",
      "font": { "family": "SF Mono", "size": 14 },

      "// cursor": "block | steady-block | bar | steady-bar | underline | steady-underline",
      "cursor": "block",

      "// scrollback": "lines to retain; 0 disables scrollback entirely",
      "// scrollback-note": "past ~3500 the scrollbar thumb hits its 1% floor and stops tracking position, and every window resize walks the whole buffer",
      "scrollback": 1000,

      "// shell": "defaults to $SHELL; launched with -l so your PATH loads",
      "// optionAsMeta": "true lets Option act as Meta instead of typing accents",
      "optionAsMeta": true,

      "// theme": "OMITTED ON PURPOSE. With no theme, SwiftTerm's own colours stand and ANSI 16-255 keep the standard xterm values. Setting a background or foreground makes SwiftTerm regenerate indices 16-255 by interpolating them out of your bg/fg, so 256-colour programs render against synthesised approximations. Uncomment below only if you want that trade.",
      "// theme-example": {
        "preset": "afk-dark",
        "// preset-values": "afk-dark | tokyo-night | classic",
        "// overrides": "background/foreground/cursor/ansi may be set on top of a preset; ansi must be exactly 16 colours, 8 normal then 8 bright",
        "cursor": "#E67E4C"
      }
    }

    """
}
