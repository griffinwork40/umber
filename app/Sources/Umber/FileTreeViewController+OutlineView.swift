//
//  FileTreeViewController+OutlineView.swift
//  Everything AppKit asks the tree: the two `NSOutlineView` conformances and the
//  row view behind them.
//
//  Its own file because this is one concern with one reason to change — how a row
//  is answered for and drawn. It holds the data source's four callbacks, the
//  delegate's `viewFor`, and the cell machinery nothing else uses: `FileCellView`,
//  the SF Symbol table, the glyph cache, and the row's Auto Layout. It reaches
//  back into the controller for exactly one thing, `root`. What stays in
//  `FileTreeViewController.swift` is the controller's own job — building the
//  outline and scroll view, the identity-preserving `refresh()`, double-click
//  routing, and the row context menu. `NSMenuDelegate` stays there too: its single
//  member forwards to the context-menu code, so it belongs to that concern, not
//  this one.
//

import AppKit

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

/// A source-list row whose glyph tracks the row's own state.
///
/// The tint has to be re-derived from `backgroundStyle` rather than assigned once
/// at build time: AppKit flips a selected row to `.emphasized` and expects the cell
/// to answer, and a fixed `contentTintColor` would leave a dim grey glyph stranded
/// inside the blue selection pill. `secondaryLabelColor` deliberately sits the icon
/// *below* the filename in the visual hierarchy — the name is what you read, the
/// glyph is what you skim.
@MainActor
private final class FileCellView: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyTint() }
    }

    func applyTint() {
        imageView?.contentTintColor =
            backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
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
        cell.imageView?.image = Self.symbol(named: Self.symbolName(for: node))
        return cell
    }

    /// SF Symbols rather than `NSWorkspace.icon(forFile:)`.
    ///
    /// Finder's icons are full-colour raster art. Measured against the now-dark
    /// tree they were 5.4% of the sidebar's pixels in saturated blue, competing
    /// for attention with the filenames they exist to label — and they are the one
    /// thing in the sidebar that cannot follow the window's appearance, because a
    /// baked bitmap has no template to tint. Xcode's navigator, VS Code and Zed all
    /// draw monochrome glyphs here for the same reason.
    ///
    /// Deliberately coarse: enough shape variety to scan a directory by, not a
    /// per-language icon set to maintain. Dotfiles get their own glyph because this
    /// tree shows them on purpose (see `FileNode.isVisible`), so they are a category
    /// a developer actually looks for rather than noise to hide.
    private static func symbolName(for node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        switch node.url.pathExtension.lowercased() {
        case "swift", "c", "h", "m", "mm", "cpp", "py", "js", "ts", "tsx", "jsx", "rs", "go",
            "rb", "java", "kt", "lua", "pl", "php", "cs":
            return "curlybraces"
        case "json", "yml", "yaml", "toml", "plist", "xml", "lock", "cfg", "conf", "ini", "env":
            return "list.bullet.rectangle"
        case "md", "markdown", "txt", "rst", "adoc", "log":
            return "doc.text"
        case "sh", "bash", "zsh", "fish", "command":
            return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "icns", "webp", "heic", "pdf":
            return "photo"
        default:
            return node.name.hasPrefix(".") ? "gearshape" : "doc"
        }
    }

    /// Cached because `viewFor` runs on every row recycle during a scroll, and the
    /// call this replaced (`NSWorkspace.icon(forFile:)`) hit icon services on each
    /// one. There are a dozen distinct glyphs for any tree, so the cache is bounded
    /// by the table above, not by the number of files.
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbol(named name: String) -> NSImage? {
        if let cached = symbolCache[name] { return cached }
        guard
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        else { return nil }
        // Template is what lets `contentTintColor` apply at all — see `FileCellView`.
        image.isTemplate = true
        symbolCache[name] = image
        return image
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = FileCellView()
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
        // Seed the tint: `backgroundStyle` only fires its observer on a *change*,
        // so an unselected row built fresh would otherwise draw an untinted glyph.
        cell.applyTint()
        return cell
    }
}
