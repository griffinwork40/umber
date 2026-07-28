//
//  FileViewerPane.swift
//  A read-only look at one file, as a document in the Space's strip.
//

import AppKit

/// The second `SpaceDocument` conformer — and deliberately the *cheap* one.
///
/// The file tree shipped before there was anywhere to open a file into, so
/// activating a row typed its path into the terminal and did nothing else: a
/// picker wired to a hole. This closes it with the smallest thing that is honestly
/// useful — an `NSTextView` in read-only mode. No editing, no save, no dirty state,
/// no undo, no syntax highlighting, no tree-sitter.
///
/// That is a scope decision, not an unfinished one. The plan's editor candidate is
/// CodeEditSourceEditor, whose own README still says "not ready for production use"
/// (plan §4.3), and half an editor is worse than an honest viewer in an app whose
/// premise is that an agent is rewriting these files in the terminal next door: a
/// buffer you can type into but not trust is a data-loss surface. You edit in the
/// terminal. You *look* here. Promoting this to an editor later means adding save
/// and dirty-state to this class, not replacing it.
@MainActor
final class FileViewerPane: NSObject {
    /// Exposed so `SpaceViewController` can reuse an already-open tab instead of
    /// stacking a twelfth copy of the same file (`openFile(url:)`).
    let url: URL

    private var config: AppConfig
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    private var fontSize: CGFloat

    /// Identity of the bytes currently on screen, so `documentWindowDidBecomeKey`
    /// can re-read only when disk actually moved. Comparing content would mean
    /// reading the file on every window focus; comparing (mtime, size) is one stat.
    private var loadedStamp: (date: Date, size: Int)?

    private static let minFontSize = CGFloat(AppConfig.minFontSize)
    private static let maxFontSize = CGFloat(AppConfig.maxFontSize)

    /// Refuse rather than beachball. `NSTextView` lays out the whole string up
    /// front, so a multi-hundred-megabyte log — a genuinely likely thing to click
    /// in an agent workspace — would hang the app, not scroll slowly. 4 MiB is
    /// roughly 100k lines of source, far past anything worth reading in a viewer
    /// with no editor affordances.
    private static let maxBytes = 4 << 20

    /// A NUL in the first block is the same heuristic `git diff` uses to call a
    /// file binary, and for the same reason: no text encoding this viewer can
    /// render puts one there.
    private static let sniffBytes = 8 << 10

    init(config: AppConfig, url: URL, frame: NSRect) {
        self.config = config
        self.url = url
        self.fontSize = FontZoom.override ?? config.font.pointSize
        super.init()

        // Non-wrapping, horizontally scrollable: this is code, and soft-wrapping
        // code re-flows indentation into nonsense. Every constant below is load
        // bearing for that — an `NSTextView` wraps by default and only stops when
        // the container is told it no longer tracks the view's width.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.isEditable = false
        // Selectable but not editable: copying a path or a stack frame out of a
        // file is most of why you opened it.
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // ⌘F/⌘G come free. The Edit-menu items in `AppDelegate.buildMenu()` send
        // `performFindPanelAction:` down the responder chain with an `NSFindPanelAction`
        // tag — SwiftTerm implements that for terminals, and `NSTextView` implements
        // it natively, so the same three menu items drive both document kinds with
        // no branching. Without `usesFindBar` AppKit would try to open the ancient
        // modal find *panel* instead of the inline bar.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        scrollView.frame = frame
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // Explicit, because `FileTreeViewController` sets the opposite on its own
        // scroll view to let the sidebar's vibrancy through. Here the theme
        // background is the point, so this view must actually paint it.
        scrollView.drawsBackground = true
        scrollView.autoresizingMask = [.width, .height]

        apply(config: config)
        reload(preservingScroll: false)
    }

    // MARK: - Contents

    /// Read the file, or explain why not.
    ///
    /// Mirrors `AppConfig.load()`'s fail-soft contract (AFK.md, Conventions): this
    /// never throws and never shows an alert. A missing, huge, or binary file is an
    /// ordinary thing to click in a file tree, so each one degrades to a legible
    /// line of text in the document body — the tab still opens, the app still works.
    private func read() -> (text: String, isPlaceholder: Bool) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0

        if size > Self.maxBytes {
            let mb = Double(size) / Double(1 << 20)
            return (
                "\(url.lastPathComponent) is \(String(format: "%.1f", mb)) MB — too large to view.\n"
                    + "Umber's viewer lays out the whole file at once, so it caps at "
                    + "\(Self.maxBytes >> 20) MB. Open it in the terminal instead.",
                true
            )
        }

        guard let data = try? Data(contentsOf: url) else {
            return ("Could not read \(url.lastPathComponent).", true)
        }

        if data.prefix(Self.sniffBytes).contains(0) {
            return ("\(url.lastPathComponent) is a binary file.", true)
        }

        // UTF-8 first because it is essentially always the answer; the second
        // attempt catches the Latin-1 and UTF-16 stragglers without which a
        // legitimately-readable file would be mislabelled binary.
        if let text = String(data: data, encoding: .utf8) {
            return (text, false)
        }
        var encoding: String.Encoding = .utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            return (text, false)
        }
        return ("\(url.lastPathComponent) is not text in any encoding Umber recognises.", true)
    }

    /// Pull the current bytes onto the screen.
    ///
    /// `preservingScroll` is what makes the refresh-on-focus behaviour tolerable:
    /// an agent appending to a log you are reading should not fling you back to
    /// line 1 every time you ⌘-tab into the window.
    private func reload(preservingScroll: Bool) {
        let origin = scrollView.contentView.bounds.origin
        let (text, isPlaceholder) = read()

        textView.string = text
        // Set the font after the string: assigning `string` on a plain-text view
        // re-applies `font` to the whole run, but only if `font` is already set —
        // ordering it the other way leaves placeholder text at the system default.
        textView.font = Self.resized(config.font, to: fontSize)
        textView.textColor = isPlaceholder
            ? config.effectiveForeground.withAlphaComponent(0.6)
            : config.effectiveForeground

        let stamp = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if let date = stamp?.contentModificationDate, let size = stamp?.fileSize {
            loadedStamp = (date, size)
        } else {
            loadedStamp = nil
        }

        if preservingScroll {
            // Force layout before scrolling: `NSTextView` lays out lazily, so the
            // document is still zero-height at this point and the scroll would be
            // clamped to the top. Optional-chained rather than force-unwrapped —
            // no `try!`/`!` outside compile-time constants in this repo (AFK.md).
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            // AppKit clamps if the file shrank past the old offset, which is the
            // right answer — land at the new bottom rather than in blank space.
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Same trick as `TerminalPane.resized` — see `AppConfig.resized(_:to:)` for why
    /// this cannot go through `NSFont(name:size:)`.
    private static func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        AppConfig.resized(base, to: size)
    }
}

// MARK: - SpaceDocument

extension FileViewerPane: SpaceDocument {
    var documentView: NSView { scrollView }

    var documentTitle: String { url.lastPathComponent }

    /// Distinguishable from `TerminalPane`'s "terminal" at tab size, which is the
    /// whole reason `documentSymbolName` is on the protocol (`SpaceDocument.swift:33`).
    var documentSymbolName: String { "doc.text" }

    func documentDidBecomeActive() {
        // Takes first responder for the same reason the terminal does: so ⌘F,
        // arrow-key scrolling and ⌘C work without a stray click into the view first.
        scrollView.window?.makeFirstResponder(textView)
    }

    func apply(config: AppConfig) {
        self.config = config
        scrollView.backgroundColor = config.effectiveBackground
        textView.backgroundColor = config.effectiveBackground
        textView.textColor = config.effectiveForeground
        // Re-resolve rather than reusing `fontSize`, so editing `font.size` and
        // hitting ⌘R changes the size here exactly as it does in a terminal
        // (`TerminalPane.apply(config:)`). A live ⌘+ zoom still outranks the file.
        setFontSize(FontZoom.override ?? config.font.pointSize, persist: false)
    }

    var currentFontSize: CGFloat { fontSize }

    func setFontSize(_ size: CGFloat, persist: Bool = true) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        fontSize = clamped
        textView.font = Self.resized(config.font, to: clamped)
        if persist {
            FontZoom.override = clamped == config.font.pointSize ? nil : clamped
        }
    }

    func resetFontSize() {
        FontZoom.override = nil
        setFontSize(config.font.pointSize, persist: false)
    }

    /// Re-read if disk moved under us. This is the difference between a viewer and
    /// a screenshot: in this app the file on screen is being rewritten by an agent
    /// in the terminal beside it, so a viewer that never re-reads would spend most
    /// of its life confidently showing a stale file.
    func documentWindowDidBecomeKey() {
        let current = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        // A vanished file counts as changed — `reload` renders the "could not read"
        // placeholder rather than leaving stale content up pretending it is still there.
        guard let date = current?.contentModificationDate, let size = current?.fileSize,
            let loaded = loadedStamp
        else {
            reload(preservingScroll: true)
            return
        }
        if loaded.date != date || loaded.size != size {
            reload(preservingScroll: true)
        }
    }
}
