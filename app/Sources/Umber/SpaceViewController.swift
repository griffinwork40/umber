//
//  SpaceViewController.swift
//  One Space: a project root, a sidebar, and N documents behind a tab strip.
//
//  This is the container the (C) restructure exists to create (plan §12.3). The
//  shape it implements, from Terax read directly (plan §12.1):
//
//      ┌──────────┬───────────────────────────────┐
//      │          │ ⟨ document tab strip ⟩         │
//      │ sidebar  ├───────────────────────────────┤
//      │ (tree)   │ active document               │
//      └──────────┴───────────────────────────────┘
//
//  Deliberate divergence from Terax: the strip spans the document area only, not
//  the full window width above the sidebar. That is VS Code's arrangement and it
//  reads better with a full-height sidebar — Terax puts its tab strip in a header
//  above everything (`terax-ai/src/app/App.tsx:1078-1220`).
//

import AppKit

@MainActor
protocol SpaceViewControllerDelegate: AnyObject {
    /// The active document's title changed — the window shows this as its subtitle.
    func spaceViewController(_ controller: SpaceViewController, didChangeDocumentTitle title: String)
    /// The last document closed; a Space with nothing in it should not linger.
    func spaceViewControllerDidCloseLastDocument(_ controller: SpaceViewController)
}

@MainActor
final class SpaceViewController: NSSplitViewController {
    /// The Space's project root. Native window tabs group Spaces, so this is what
    /// one macOS tab now means (plan §12.4 item 1).
    let root: URL

    weak var spaceDelegate: SpaceViewControllerDelegate?

    private var config: AppConfig
    private var documents: [SpaceDocument] = []
    private var activeIndex = 0

    private let fileTree: FileTreeViewController
    private let documentArea: DocumentAreaViewController

    /// Default sidebar width. Bounds are Terax's: it caps its own sidebar at
    /// `SIDEBAR_MAX_WIDTH` = 480 (`terax-ai/src/app/App.tsx:1120`).
    private static let defaultSidebarWidth: CGFloat = 220
    private static let minSidebarWidth: CGFloat = 150
    private static let maxSidebarWidth: CGFloat = 480

    init(config: AppConfig, root: URL) {
        self.config = config
        self.root = root
        self.fileTree = FileTreeViewController(root: root)
        self.documentArea = DocumentAreaViewController()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — controllers are created programmatically")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // `sidebarWithViewController:` rather than a hand-rolled NSSplitView: it is
        // what supplies the system sidebar material, the collapse animation, and a
        // free `toggleSidebar(_:)` responder for ⌘B — none of which is worth
        // reimplementing badly (plan §12.4 item 5).
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: fileTree)
        sidebarItem.minimumThickness = Self.minSidebarWidth
        sidebarItem.maximumThickness = Self.maxSidebarWidth
        sidebarItem.canCollapse = true
        // Low holding priority so a window resize grows the terminal, not the tree.
        sidebarItem.holdingPriority = .defaultLow

        let contentItem = NSSplitViewItem(viewController: documentArea)
        contentItem.minimumThickness = 240

        splitViewItems = [sidebarItem, contentItem]

        fileTree.delegate = self
        documentArea.strip.delegate = self
        documentArea.strip.apply(
            background: config.effectiveBackground, foreground: config.effectiveForeground)

        // Set the initial divider explicitly. `minimumThickness` alone leaves the
        // sidebar at whatever the split view computes, which is not 220.
        splitView.setPosition(Self.defaultSidebarWidth, ofDividerAt: 0)
    }

    // MARK: - Documents

    /// Every document, kind-agnostic. Anything app-wide — config reload, font zoom —
    /// must fan out over *this*, not `terminalPanes`: fanning over the concrete kind
    /// is how a second document kind ends up installed, rendered, and silently inert
    /// (see `SpaceDocument.swift`'s note on why the zoom members are hard requirements).
    var allDocuments: [SpaceDocument] { documents }

    var activeDocument: SpaceDocument? {
        documents.indices.contains(activeIndex) ? documents[activeIndex] : nil
    }

    var terminalPanes: [TerminalPane] { documents.compactMap { $0 as? TerminalPane } }

    /// The terminal a shell-directed action should land in.
    ///
    /// Falls back to the most recent terminal in this Space rather than returning
    /// nil when the active document is *not* a terminal. Without the fallback,
    /// "insert this path into the shell" would do nothing whenever a file viewer
    /// happened to be the front tab — the failure would be invisible, and the
    /// feature would look broken exactly when the file tree is most in use.
    var focusedTerminalPane: TerminalPane? {
        (activeDocument as? TerminalPane) ?? terminalPanes.last
    }

    /// Add a terminal document rooted at `workingDirectory`, defaulting to the Space's
    /// own `root`.
    ///
    /// The default is the point. A Space *is* a project root (plan §12.4 item 1) and
    /// every terminal in it inherited `$HOME` instead, because this function created
    /// the pane without ever mentioning `root` — so ⌘T in a Space opened on a project
    /// landed outside that project and the first thing you typed was a `cd`. The root
    /// was already right here, one property away, which is exactly why it went
    /// unnoticed.
    ///
    /// `workingDirectory` is an override rather than a replacement so the tree's
    /// "New Terminal Here" can pass a subdirectory
    /// (`fileTree(_:didRequestNewTerminalAt:)`) without every other caller — first
    /// launch, ⌘T, the strip's `+` — having to restate the root it already implies.
    @discardableResult
    func addTerminalDocument(start: Bool = true, workingDirectory: URL? = nil) -> TerminalPane {
        let pane = TerminalPane(
            config: config, frame: documentArea.container.bounds,
            workingDirectory: workingDirectory ?? root)
        pane.delegate = self
        documents.append(pane)
        if start { pane.start() }
        selectDocument(at: documents.count - 1)
        return pane
    }

    /// Open `url` as a read-only document, or surface the tab that already has it.
    ///
    /// Reuse is not an optimisation — it is the behaviour. A file tree where every
    /// double-click appends a tab turns eight glances at `Config.swift` into eight
    /// identical tabs, which is how every editor that skipped this feels broken.
    @discardableResult
    func openFile(url: URL) -> FileViewerPane {
        let target = url.resolvingSymlinksInPath()
        if let index = documents.firstIndex(where: {
            ($0 as? FileViewerPane)?.url.resolvingSymlinksInPath() == target
        }), let existing = documents[index] as? FileViewerPane {
            selectDocument(at: index)
            // Re-stat on re-activation: you clicked the file again, which usually
            // means you want to see what it says *now*.
            existing.documentWindowDidBecomeKey()
            return existing
        }

        let viewer = FileViewerPane(config: config, url: url, frame: documentArea.container.bounds)
        viewer.delegate = self
        documents.append(viewer)
        selectDocument(at: documents.count - 1)
        return viewer
    }

    func selectDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
        let document = documents[index]

        documentArea.present(documentView: document.documentView)
        syncStrip()
        spaceDelegate?.spaceViewController(self, didChangeDocumentTitle: document.documentTitle)
        document.documentDidBecomeActive()
    }

    /// ⌘⌥← / ⌘⌥→. Wraps, because a cycle that dead-ends at the edges is a worse
    /// version of ⌘1…⌘9.
    func cycleDocument(by delta: Int) {
        guard documents.count > 1 else { return }
        let next = (activeIndex + delta + documents.count) % documents.count
        selectDocument(at: next)
    }

    func closeDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        // Every close path in the app — ⌘W, the tab's ×, closing the Space, quitting —
        // reaches a document through here, which is what makes this the one place a
        // dirty buffer has to be able to say no.
        guard documents[index].documentShouldClose() else { return }
        let document = documents.remove(at: index)
        document.documentView.removeFromSuperview()

        guard !documents.isEmpty else {
            spaceDelegate?.spaceViewControllerDidCloseLastDocument(self)
            return
        }
        // Land on the neighbour to the left, which is where the eye already is.
        selectDocument(at: min(index, documents.count - 1))
    }

    func closeActiveDocument() { closeDocument(at: activeIndex) }

    private func syncStrip() {
        documentArea.setStripVisible(documents.count > 1)
        documentArea.strip.reload(
            items: documents.map {
                .init(
                    title: $0.documentTitle, symbolName: $0.documentSymbolName,
                    isEdited: $0.documentIsEdited)
            },
            activeIndex: activeIndex)
    }

    // MARK: - Config / lifecycle

    func apply(config: AppConfig) {
        self.config = config
        for document in documents { document.apply(config: config) }
        documentArea.strip.apply(
            background: config.effectiveBackground, foreground: config.effectiveForeground)
    }

    /// Called when the Space's window becomes key — see `FileTreeViewController.refresh()`
    /// for why that is the chosen trigger rather than FSEvents. The documents get the
    /// same signal for the same reason: an open file viewer is as stale as the tree is.
    func windowDidBecomeKey() {
        fileTree.refresh()
        for document in documents { document.documentWindowDidBecomeKey() }
        // A document may have picked up an external change; the strip does not show
        // that today, but the dot state is cheap to keep honest.
        syncStrip()
    }

    /// Can this whole Space go away? Asks each document in turn and stops at the
    /// first refusal, so closing a window with three dirty files prompts three times
    /// rather than discarding the other two behind one answer.
    func spaceShouldClose() -> Bool {
        for document in documents where !document.documentShouldClose() { return false }
        return true
    }

    var hasEditedDocuments: Bool { documents.contains { $0.documentIsEdited } }
}

// MARK: - FileViewerPaneDelegate

extension SpaceViewController: FileViewerPaneDelegate {
    func fileViewerDidChangeEditedState(_ pane: FileViewerPane) {
        // Repaint the strip so the unsaved dot appears/disappears as you type.
        syncStrip()
    }
}

// MARK: - DocumentTabStripDelegate

extension SpaceViewController: DocumentTabStripDelegate {
    func tabStrip(_ strip: DocumentTabStrip, didSelect index: Int) {
        selectDocument(at: index)
    }

    func tabStrip(_ strip: DocumentTabStrip, didRequestClose index: Int) {
        closeDocument(at: index)
    }

    func tabStripDidRequestNewDocument(_ strip: DocumentTabStrip) {
        addTerminalDocument()
    }
}

// MARK: - TerminalPaneDelegate

extension SpaceViewController: TerminalPaneDelegate {
    func paneDidTerminate(_ pane: TerminalPane) {
        // The shell exited — close that document specifically, not the active one:
        // a background tab's shell can exit while you are looking at another.
        guard let index = documents.firstIndex(where: { $0 === pane }) else { return }
        closeDocument(at: index)
    }

    func pane(_ pane: TerminalPane, didChangeTitle title: String) {
        syncStrip()
        guard documents.indices.contains(activeIndex), documents[activeIndex] === pane else { return }
        spaceDelegate?.spaceViewController(self, didChangeDocumentTitle: pane.documentTitle)
    }
}

// MARK: - FileTreeViewControllerDelegate

extension SpaceViewController: FileTreeViewControllerDelegate {
    /// Double-click opens the file in a document tab — what every Mac user already
    /// means by double-clicking a row in a file tree.
    ///
    /// This used to type the path into the terminal instead, because there was no
    /// document kind to open a file *into*. That was an honest placeholder and a
    /// bad feature: a picker whose only effect is inserting text reads as broken to
    /// anyone who did not write it. `FileViewerPane` gives the tree somewhere to go.
    func fileTree(_ controller: FileTreeViewController, didActivate url: URL) {
        openFile(url: url)
    }

    /// The old behaviour, kept and given a name.
    ///
    /// Inserting a quoted path is genuinely useful — it is what you want while
    /// composing `nvim <path>` or `git add <path>` — it was just bound to the one
    /// gesture that means "open". Now it is ⌥-double-click and a context-menu item,
    /// which also makes it discoverable, which it never was.
    func fileTree(_ controller: FileTreeViewController, didRequestPathInsert url: URL) {
        guard let pane = focusedTerminalPane else { return }
        // Single-quoted, with any embedded quote closed-escaped-reopened, so spaces,
        // `$`, and quotes in a filename survive the shell verbatim.
        let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        pane.view.send(txt: quoted + " ")
        // Bring the terminal forward if a viewer was in front, otherwise the text
        // lands in a tab the user cannot see.
        if let index = documents.firstIndex(where: { $0 === pane }), index != activeIndex {
            selectDocument(at: index)
        } else {
            pane.documentDidBecomeActive()
        }
    }
}

// MARK: - Document area

/// The right-hand region: tab strip on top, active document filling the rest.
///
/// Laid out manually in `viewDidLayout` rather than with Auto Layout. The document
/// view is a SwiftTerm view that already ships with `autoresizingMask =
/// [.width, .height]` (`TerminalPane.swift:49`) and is sized by frame everywhere
/// else in this app; mixing a constraint-based parent into that is how a terminal
/// ends up one row short.
@MainActor
private final class DocumentAreaViewController: NSViewController {
    let strip = DocumentTabStrip(frame: .zero)
    let container = NSView()

    private var isStripVisible = false

    override func loadView() {
        let root = NSView()
        root.addSubview(container)
        view = root
    }

    /// Hidden at a single document, matching Ghostty and Terminal.app: with one
    /// terminal open this app should still just look like a terminal, and the strip
    /// costs 30pt of rows that the primary surface would rather have. ⌘T brings it
    /// back the moment there is anything to switch between.
    func setStripVisible(_ visible: Bool) {
        guard visible != isStripVisible else { return }
        isStripVisible = visible
        if visible {
            view.addSubview(strip)
        } else {
            strip.removeFromSuperview()
        }
        view.needsLayout = true
        viewDidLayout()
    }

    func present(documentView: NSView) {
        for subview in container.subviews where subview !== documentView {
            subview.removeFromSuperview()
        }
        if documentView.superview !== container {
            documentView.frame = container.bounds
            container.addSubview(documentView)
        }
        documentView.frame = container.bounds
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        let stripHeight = isStripVisible ? DocumentTabStrip.height : 0
        // Non-flipped coordinates: the strip is at the TOP, so it takes the high y.
        strip.frame = NSRect(
            x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight)
        container.frame = NSRect(
            x: 0, y: 0, width: bounds.width, height: bounds.height - stripHeight)
        for subview in container.subviews { subview.frame = container.bounds }
    }
}
