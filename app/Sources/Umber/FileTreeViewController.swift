//
//  FileTreeViewController.swift
//  The sidebar file tree, rooted at the Space's project directory.
//

import AppKit

@MainActor
protocol FileTreeViewControllerDelegate: AnyObject {
    /// A file (not a directory) was activated. There is no editor yet, so the
    /// Space answers this by typing the path into the focused terminal — see
    /// `SpaceViewController.fileTree(_:didActivate:)`.
    func fileTree(_ controller: FileTreeViewController, didActivate url: URL)
}

/// A lazily-populated directory node.
///
/// Children are loaded on first disclosure, not up front: rooting a Space at
/// `$HOME` and eagerly walking it would stat tens of thousands of files before the
/// first frame.
@MainActor
final class FileNode {
    let url: URL
    let isDirectory: Bool
    private(set) var children: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var name: String { url.lastPathComponent }

    /// Read the directory, **reusing existing child nodes by URL**. Identity has to
    /// survive a refresh or `NSOutlineView` loses every expanded row: it tracks
    /// disclosure state by item identity, so handing it fresh objects for unchanged
    /// paths collapses the whole tree on each reload.
    func reloadChildren() {
        guard isDirectory else { return }
        let existing = Dictionary(
            (children ?? []).map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })

        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [])) ?? []

        children =
            contents
            .filter { Self.isVisible($0) }
            .map { child -> FileNode in
                let isDir =
                    (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if let reused = existing[child], reused.isDirectory == isDir { return reused }
                return FileNode(url: child, isDirectory: isDir)
            }
            .sorted { lhs, rhs in
                // Directories first, then case-insensitive name — Finder's order,
                // and the one every file tree a developer already uses follows.
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        // Recurse only into what the user already opened, so a refresh costs the
        // same as the disclosure state and not the size of the tree.
        for child in children ?? [] where child.children != nil {
            child.reloadChildren()
        }
    }

    /// Dotfiles are deliberately **shown**: this is a developer tool, and hiding
    /// `.github`, `.env` or this project's own `.afk/` in a terminal-first IDE
    /// would be actively obstructive. Only the two entries nobody ever wants to
    /// browse are dropped. A config field can generalise this later.
    private static func isVisible(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name != ".git" && name != ".DS_Store"
    }
}

@MainActor
final class FileTreeViewController: NSViewController {
    weak var delegate: FileTreeViewControllerDelegate?

    private let root: FileNode
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()

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
        } else {
            delegate?.fileTree(self, didActivate: node.url)
        }
    }
}

extension FileTreeViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(for: item).children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(for: item).children?[index] ?? root
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    /// Populate on demand. `numberOfChildrenOfItem` is asked about collapsed
    /// directories too, so loading there instead would walk the entire tree.
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        if let node = item as? FileNode, node.children == nil { node.reloadChildren() }
        return true
    }

    private func node(for item: Any?) -> FileNode { (item as? FileNode) ?? root }
}

extension FileTreeViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
        -> NSView?
    {
        guard let node = item as? FileNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell =
            outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)

        cell.textField?.stringValue = node.name
        // Finder's own icon for the file type — free, correct for every extension,
        // and it keeps the tree recognisable without shipping an icon set.
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        return cell
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 12)
        textField.lineBreakMode = .byTruncatingMiddle

        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
