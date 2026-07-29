//
//  FileTreeViewController.swift
//  The sidebar file tree, rooted at the Space's project directory.
//
//  Two concerns live in files of their own: the tree's model in `FileNode.swift`,
//  and the `NSOutlineView` data source and delegate, plus the cell machinery they
//  build, in `FileTreeViewController+OutlineView.swift`. What stays here is the
//  controller itself — the outline and scroll view it assembles, the
//  identity-preserving `refresh()`, `setRoot(_:)` (repoint the tree at a new
//  directory — cwd-follow), double-click routing, and the row context menu.
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

    /// "cd Here". The user asked to make `url` — always a **directory**, resolved
    /// from a clicked file to its parent exactly like `didRequestNewTerminalAt`
    /// above — the focused shell's working directory. Unlike the other three
    /// members this does not touch the tree itself; it is the other half of
    /// cwd-follow, the shell-to-tree direction being `setRoot(_:)`
    /// (`SpaceViewController.fileTree(_:didRequestChangeDirectory:)`).
    func fileTree(_ controller: FileTreeViewController, didRequestChangeDirectory url: URL)
}

@MainActor
final class FileTreeViewController: NSViewController {
    weak var delegate: FileTreeViewControllerDelegate?

    /// Internal, not `private`: the `NSOutlineViewDataSource` conformance moved to
    /// `FileTreeViewController+OutlineView.swift` and its `node(for:)` substitutes
    /// this for a nil item, which is how the root row is answered for. That
    /// extension only ever reads it, so `private(set)` — not plain `private` —
    /// keeps the getter at this same internal level while confining the *setter*
    /// to this file, where `setRoot(_:)` lives.
    ///
    /// `var`, not `let`: this used to be immutable on purpose, with a comment
    /// arguing the tree could never be repointed. That argument is retired, not
    /// the protection it existed for — cwd-follow needs the tree to move when the
    /// shell's cwd moves, and `setRoot(_:)` below is the one path allowed to do
    /// it, still gated to this file by `private(set)`.
    ///
    /// This is only the tree's **displayed** root. A Space's *identity* root —
    /// `SpaceWindowController.root`, the `UmberSpace:<path>` frame-autosave key,
    /// `OpenSpaceRoots`, `LastSpaceRoot` — is a separate, still-immutable concept:
    /// a Space stays "the project opened with ⌘O" no matter where its shell's cwd
    /// wanders, so a `cd` moving the sidebar must never rename the Space, relabel
    /// its window tab, or rewrite its remembered frame/restore entry.
    private(set) var root: FileNode
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

    /// Repoint the tree at a different directory — cwd-follow, the shell-to-tree
    /// half of it (the tree-to-shell half is "cd Here" below).
    ///
    /// Deliberately does **not** preserve expansion/selection the way `refresh()`
    /// does. `refresh()` re-reads the *same* directory, so an expanded row is still
    /// the same path with possibly-changed contents — carrying its state forward is
    /// exactly right. `setRoot(_:)` points at a *different* directory: a row
    /// expanded under the old root is an unrelated path under the new one (same
    /// relative position, different file), so "restoring" it would show disclosure
    /// state that has nothing to do with what's on disk at the new root. A full
    /// `reloadData()` against a fresh `FileNode` is the correct amount of state to
    /// carry across a root change: none.
    ///
    /// The early return on an unchanged root is **load-bearing, not an
    /// optimisation**: this is meant to be driven by a shell's reported cwd
    /// (`TerminalPane.hostCurrentDirectoryUpdate`, currently a wired-but-empty OSC 7
    /// stub) and the tree's own "cd Here" pushes the opposite direction, into the
    /// shell — together that is a UI <-> shell feedback loop, and a shell that
    /// echoes its cwd on every prompt would otherwise rebuild `root` and blow away
    /// the user's expansion/selection on every keystroke even when the directory
    /// never changed. The guard is what makes "did anything actually change?" the
    /// question, not "did an update arrive?". `resolvingSymlinksInPath()` matches
    /// the normalisation `AppDelegate.openFolder` and `SpaceRestore` already use so
    /// `/tmp` vs `/private/tmp` cannot defeat it.
    /// Compared as **paths, not as `URL`s**, and that is not a style preference — it is a
    /// bug that was caught by `check-cwd-follow.sh` before it shipped. `URL` equality
    /// includes the directory marker (a trailing slash), and `resolvingSymlinksInPath()`
    /// drops that marker when the last component is itself a symlink: measured,
    /// `URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath()` is `file:///tmp/`
    /// while `URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()` is `file:///tmp` —
    /// same `.path`, and `==` is **false**. With a `URL` comparison this guard would have
    /// answered "changed" every time for such a directory, so a 750ms poller would have
    /// rebuilt the tree and discarded the user's expansion and selection twice a second:
    /// precisely the damage the guard exists to prevent, in the shape of a passing test.
    func setRoot(_ url: URL) {
        guard url.resolvingSymlinksInPath().path != root.url.resolvingSymlinksInPath().path
        else { return }
        root = FileNode(url: url, isDirectory: true)
        root.reloadChildren()
        outlineView.reloadData()
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
        // Right beside "New Terminal Here": both answer "here", one by starting a
        // fresh shell at this path, the other by redirecting the shell you already
        // have. Same file-to-parent resolution as that item, for the same reason —
        // see `menuChangeDirectory`.
        menu.addItem(
            withTitle: "cd Here", action: #selector(menuChangeDirectory(_:)),
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

    /// Same file-to-parent resolution as `menuNewTerminal`, and for the same
    /// reason: the row under a right-click here is usually the file you are about
    /// to work on, not its enclosing folder, so `cd`-ing to a *file* would fail —
    /// this makes it just work instead of asking the container to handle that.
    @objc private func menuChangeDirectory(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        let directory = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        delegate?.fileTree(self, didRequestChangeDirectory: directory)
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
