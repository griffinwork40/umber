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
        newWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Actions

    @objc func newWindow(_ sender: Any?) {
        TerminalWindowController(config: config).present()
    }

    @objc func newTab(_ sender: Any?) {
        let host = NSApp.keyWindow ?? TerminalWindowController.open.last?.window
        TerminalWindowController(config: config).presentAsTab(relativeTo: host)
    }

    /// Re-read the config file and apply it to every open pane, so tuning the
    /// theme does not require restarting the app.
    @objc func reloadConfig(_ sender: Any?) {
        config = AppConfig.load()
        for warning in config.warnings {
            FileHandle.standardError.write("config: \(warning)\n".data(using: .utf8)!)
        }
        for controller in TerminalWindowController.open {
            controller.pane.apply(config: config)
            controller.window?.backgroundColor = config.theme.background
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

    private var focusedPane: TerminalPane? {
        TerminalWindowController.open.first { $0.window === NSApp.keyWindow }?.pane
            ?? TerminalWindowController.open.last?.pane
    }

    @objc func biggerFont(_ sender: Any?) { focusedPane?.adjustFontSize(by: 1) }
    @objc func smallerFont(_ sender: Any?) { focusedPane?.adjustFontSize(by: -1) }
    @objc func resetFont(_ sender: Any?) { focusedPane?.resetFontSize() }

    // MARK: - Menu

    private func buildMenu() {
        let appName = "MacTerminal"
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

        // Shell menu
        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        shellItem.submenu = shellMenu
        mainMenu.addItem(shellItem)

        // Edit menu — the standard selectors; TerminalView implements them.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Bigger Font", action: #selector(biggerFont(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Smaller Font", action: #selector(smallerFont(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetFont(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Window menu — giving it the standard role is what makes the native tab
        // commands (Show All Tabs, Move Tab to New Window, …) appear.
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private static let starterConfig = """
    {
      "// font": "any installed monospaced family; omit family for SF Mono (the system monospaced face, and the default)",
      "font": { "family": "SF Mono", "size": 13 },

      "// cursor": "block | steady-block | bar | steady-bar | underline | steady-underline",
      "cursor": "block",

      "// scrollback": "lines to retain; 0 disables scrollback entirely",
      "scrollback": 10000,

      "// shell": "defaults to $SHELL; launched with -l so your PATH loads",
      "// optionAsMeta": "true lets Option act as Meta instead of typing accents",
      "optionAsMeta": true,

      "// theme": "ansi must contain exactly 16 colours: 8 normal then 8 bright",
      "theme": {
        "background": "#1a1b26",
        "foreground": "#c0caf5",
        "cursor": "#c0caf5",
        "ansi": [
          "#15161e", "#f7768e", "#9ece6a", "#e0af68",
          "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
          "#414868", "#f7768e", "#9ece6a", "#e0af68",
          "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"
        ]
      }
    }

    """
}
