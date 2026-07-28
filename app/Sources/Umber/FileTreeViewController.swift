//
//  FileTreeViewController.swift
//  The sidebar file tree, rooted at the Space's project directory.
//
//  Two concerns live in files of their own: the tree's model in `FileNode.swift`,
//  and the `NSOutlineView` data source and delegate, plus the cell machinery they
//  build, in `FileTreeViewController+OutlineView.swift`. What stays here is the
//  controller itself — the outline and scroll view it assembles, the
//  identity-preserving `refresh()`, double-click routing, and the row context menu.
//

import AppKit

@MainActor
protocol FileTreeViewControllerDelegate: AnyObject {
    /// A file (not a directory) was activated — double-click, or "Open" from the
    /// row's context menu. The Space opens it as a document tab
    /// (`SpaceViewController.fileTree(_:didActivate:)`).
    func fileTree(_ controller: FileTreeViewController, didActivate url: URL)

    /// ⌥-double-click, or "Insert Path in Terminal". Types the quoted path into the
    /// Space's focused terminal without opening anything — the terminal-first
    /// gesture, which used to be bound to plain double-click and confused everyone.
    func fileTree(_ controller: FileTreeViewController, didRequestPathInsert url: URL)

    /// "New Terminal Here". Opens a new terminal document rooted at `url`, which is
    /// always a **directory** — the menu resolves a clicked file to its parent before
    /// calling, so the Space never has to ask what kind of row was hit
    /// (`SpaceViewController.fileTree(_:didRequestNewTerminalAt:)`).
    func fileTree(_ controller: FileTreeViewController, didRequestNewTerminalAt url: URL)
}

@MainActor
final class FileTreeViewController: NSViewController {
    weak var delegate: FileTreeViewControllerDelegate?

    /// Internal, not `private`: the `NSOutlineViewDataSource` conformance moved to
    /// `FileTreeViewController+OutlineView.swift` and its `node(for:)` substitutes
    /// this for a nil item, which is how the root row is answered for. Still a
    /// `let` — the extension can read the root, never repoint the tree at another
    /// directory. This is the only member that file needs.
    let root: FileNode
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let rowMenu = NSMenu()

    init(root url: URL) {
        self.root = FileNode(url: url, isDirectory: true)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — views are created programmatically")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        // `.sourceList` is what makes the rows adopt the system sidebar's
        // selection pill and vibrancy-aware text colours, so this tree matches
        // Finder and Xcode instead of looking like a plain table in a grey box.
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 12
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(handleDoubleClick)
        outlineView.autoresizingMask = [.width, .height]

        // Right-click affordances. This is also where "insert path in terminal"
        // becomes findable: bound only to a modifier chord it was a feature nobody
        // could discover, which is most of why the tree felt like it did nothing.
        rowMenu.delegate = self
        outlineView.menu = rowMenu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // The sidebar item paints its own vibrant material; an opaque scroll view
        // on top of it would flatten that back to a solid rectangle.
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        root.reloadChildren()
        view = scrollView
    }

    /// Re-read the tree, preserving expansion and selection.
    ///
    /// Called when the Space's window becomes key rather than driven by FSEvents.
    /// That is a deliberate first cut, and it is well matched to this app's actual
    /// job: the thing mutating these files is an agent running in the terminal
    /// beside the tree, so "you came back to this window" is almost exactly the
    /// moment the tree is stale. FSEvents is the obvious upgrade if it ever feels
    /// behind.
    func refresh() {
        let expanded = (0..<outlineView.numberOfRows)
            .compactMap { outlineView.item(atRow: $0) as? FileNode }
            .filter { outlineView.isItemExpanded($0) }
        let selectedURL = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url

        root.reloadChildren()
        outlineView.reloadData()

        for node in expanded { outlineView.expandItem(node) }
        if let selectedURL {
            for row in 0..<outlineView.numberOfRows
            where (outlineView.item(atRow: row) as? FileNode)?.url == selectedURL {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)
                break
            }
        }
    }

    @objc private func handleDoubleClick() {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FileNode else { return }
        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            // ⌥ is the "give me the path, do not open it" modifier — the same key
            // Finder uses to turn Copy into Copy as Pathname.
            delegate?.fileTree(self, didRequestPathInsert: node.url)
        } else {
            delegate?.fileTree(self, didActivate: node.url)
        }
    }

    // MARK: - Context menu

    /// Built per right-click rather than once, so the item set can depend on what
    /// was actually clicked (a directory has nothing to "Open" in a viewer).
    ///
    /// Every action carries its `FileNode` in `representedObject` instead of
    /// re-reading `clickedRow` when it fires: the menu outlives the click, and a
    /// refresh landing in between would silently retarget the action at whatever
    /// row moved into that index.
    @objc private func menuNeedsUpdateImpl(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FileNode else { return }

        if !node.isDirectory {
            menu.addItem(withTitle: "Open", action: #selector(menuOpen(_:)), keyEquivalent: "")
            menu.addItem(
                withTitle: "Insert Path in Terminal", action: #selector(menuInsertPath(_:)),
                keyEquivalent: "")
        }
        // Offered for files as well as directories — it resolves a file to its parent
        // (`menuNewTerminal`), which is what "here" means when you right-click a file
        // you are about to run something against. Finder's own "New Terminal at
        // Folder" service is directory-only and that is a worse rule in a project
        // tree, where the row your eye is on is usually the file, not its folder.
        menu.addItem(
            withTitle: "New Terminal Here", action: #selector(menuNewTerminal(_:)),
            keyEquivalent: "")
        // The separator moved out of the `!isDirectory` block rather than being
        // duplicated: it was conditional only because a directory row had nothing
        // above it to separate, and now every row does. The in-app actions stay above
        // it, the two hand-offs to the rest of macOS stay below.
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Reveal in Finder", action: #selector(menuReveal(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Copy Path", action: #selector(menuCopyPath(_:)), keyEquivalent: "")

        for item in menu.items where item.action != nil {
            item.target = self
            item.representedObject = node
        }
    }

    private func node(from sender: Any?) -> FileNode? {
        (sender as? NSMenuItem)?.representedObject as? FileNode
    }

    @objc private func menuOpen(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        delegate?.fileTree(self, didActivate: node.url)
    }

    @objc private func menuInsertPath(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        delegate?.fileTree(self, didRequestPathInsert: node.url)
    }

    /// Resolve the clicked row to a directory here, in the one place that knows what
    /// was clicked, rather than passing the raw node and making the Space re-derive
    /// it: `deletingLastPathComponent()` on a directory URL would climb to its
    /// *parent*, so a receiver that guessed wrong would open every folder's terminal
    /// one level too high.
    @objc private func menuNewTerminal(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        let directory = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        delegate?.fileTree(self, didRequestNewTerminalAt: directory)
    }

    @objc private func menuReveal(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func menuCopyPath(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }
}

extension FileTreeViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { menuNeedsUpdateImpl(menu) }
}
