//
//  AppMenu.swift
//  The whole NSMenu tree — every key equivalent the app offers, in one place.
//

import AppKit

/// `AppDelegate`'s menu bar: the `buildMenu()` tree and nothing else.
///
/// Its own file because menu construction is a closed concern with a different
/// reason to change than the lifecycle and actions it points at — the actions are
/// *what the app does*, this is *how it is offered* — and it was two thirds of
/// `AppDelegate.swift`, which is the shape the 350-LOC ceiling exists to catch
/// (AFK.md, "Conventions"). An extension rather than a new type: these are still
/// the delegate's members, `NSApp.mainMenu` still wants one target for every
/// `#selector` below, and splitting the target out would mean promoting fourteen
/// `@objc` actions to reach it.
///
/// `validateMenuItem` is deliberately NOT here. It is the enablement half of the
/// Save *action* — its comment reads "the action above" and refers to
/// `saveDocument` — so it stays next to that action in `AppDelegate.swift` rather
/// than being filed under menu construction.
///
/// Nothing here is a Umber implementation of anything. Every item is either a
/// standard AppKit selector resolved through the responder chain (Copy, Paste,
/// Select All, full screen, Toggle Sidebar, scrollback search — see the Edit-menu
/// note on why search is SwiftTerm's) or one of the `@objc` actions in
/// `AppDelegate.swift`. Menu items carry no logic; they carry key equivalents,
/// `tag`s, and targets.
@MainActor
extension AppDelegate {
    /// Internal, not `private`: called from `applicationDidFinishLaunching` in
    /// `AppDelegate.swift`, and `private` is file-scoped in Swift. Nothing outside
    /// the module can see it either way — the target is an executable.
    func buildMenu() {
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
        fileMenu.addItem(.separator())
        // Grouped with the document verbs but fenced off from them: Save is the only
        // item in this menu that writes to the user's files.
        fileMenu.addItem(
            withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(.separator())
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
}
