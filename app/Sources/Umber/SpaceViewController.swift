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

    var terminalPanes: [TerminalPane] { documents.compactMap { $0 as? TerminalPane } }

    var activeTerminalPane: TerminalPane? {
        documents.indices.contains(activeIndex) ? documents[activeIndex] as? TerminalPane : nil
    }

    @discardableResult
    func addTerminalDocument(start: Bool = true) -> TerminalPane {
        let pane = TerminalPane(config: config, frame: documentArea.container.bounds)
        pane.delegate = self
        documents.append(pane)
        if start { pane.start() }
        selectDocument(at: documents.count - 1)
        return pane
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
                .init(title: $0.documentTitle, symbolName: $0.documentSymbolName)
            },
            activeIndex: activeIndex)
    }

    // MARK: - Config / lifecycle

    func apply(config: AppConfig) {
        self.config = config
        for pane in terminalPanes { pane.apply(config: config) }
        documentArea.strip.apply(
            background: config.effectiveBackground, foreground: config.effectiveForeground)
    }

    /// Called when the Space's window becomes key — see `FileTreeViewController.refresh()`
    /// for why that is the chosen trigger rather than FSEvents.
    func refreshFileTree() { fileTree.refresh() }
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
    /// There is no editor yet (CodeEditSourceEditor still ships a "not ready for
    /// production use" banner — plan §4.3), so activating a file does the most
    /// useful terminal-first thing available: types its path into the focused
    /// terminal, single-quoted so spaces and `$` survive. When an editor document
    /// kind exists this becomes "open it in a tab" instead.
    func fileTree(_ controller: FileTreeViewController, didActivate url: URL) {
        guard let pane = activeTerminalPane else { return }
        let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        pane.view.send(txt: quoted + " ")
        pane.documentDidBecomeActive()
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
