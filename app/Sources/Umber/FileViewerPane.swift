//
//  FileViewerPane.swift
//  A read-only look at one file, as a document in the Space's strip.
//

import AppKit

@MainActor
protocol FileViewerPaneDelegate: AnyObject {
    /// The unsaved-changes flag flipped — the Space repaints the tab's dot.
    func fileViewerDidChangeEditedState(_ pane: FileViewerPane)
}

/// The second `SpaceDocument` conformer — and deliberately the *cheap* one.
///
/// The file tree shipped before there was anywhere to open a file into, so
/// activating a row typed its path into the terminal and did nothing else: a
/// picker wired to a hole. This closes it with a plain `NSTextView` — editing,
/// undo, ⌘S, and regex-based syntax highlighting for the five roles
/// `SyntaxPalette` defines (keyword, string, number, type, comment). No
/// tree-sitter, no grammar bundles — a tokenizer that gets the easy 90% right
/// and stays auditable, which is the honest trade for a viewer.
///
/// **The hard part of editing here is not typing, it is the race.** This app's
/// premise is that an agent is rewriting these same files in the terminal next
/// door, so "the buffer and the disk disagree" is the normal case, not an edge
/// case. Two rules keep that from eating work, and they are the reason the code
/// below is longer than an editable text view has any right to be:
///
///  1. A dirty buffer is **never** auto-reloaded. `documentWindowDidBecomeKey`
///     re-reads only a clean one; on a dirty one it raises `hasExternalChange`
///     and leaves your text alone.
///  2. Saving over a file that moved under you **asks first**, and every close
///     path in the app funnels through `documentShouldClose()`.
///
/// The third rule is quieter: a *placeholder* body (binary, too large, unreadable)
/// is never editable. Without that, ⌘S on a clicked `.png` would write the string
/// "binary.png is a binary file." over the actual image.
@MainActor
final class FileViewerPane: NSObject {
    /// Exposed so `SpaceViewController` can reuse an already-open tab instead of
    /// stacking a twelfth copy of the same file (`openFile(url:)`).
    let url: URL

    weak var delegate: FileViewerPaneDelegate?

    // Why the state below is `internal` and not `private`: this class is split
    // across three files (`+Editing`, `+Document`) and Swift's `private` is
    // file-scoped, so the extensions cannot see it. `fileprivate` does not reach
    // across a file boundary either — internal is the narrowest level that
    // compiles. None of it is `public`; the module boundary still holds, and no
    // other type in the module has a reason to touch any of it. Where the only
    // writer stays in *this* file the setter stays private, so the promotion buys
    // read access and nothing more.
    var config: AppConfig
    let scrollView = NSScrollView()
    let textView = NSTextView()

    var fontSize: CGFloat

    /// Unsaved edits live in the text view; this is the flag everything else reads.
    /// Writable module-wide only because `setDirty` — its single writer — lives in
    /// `+Editing`; that one-writer discipline is the real invariant, not the
    /// access level.
    var isDirty = false

    /// The body is an explanation ("…is a binary file."), not the file's contents.
    /// Gates editing — see rule 3 in the type comment.
    /// `private(set)` because `reload` below is the only writer: `+Editing` can read
    /// the gate that blocks its own `write()`, but cannot unlock it.
    private(set) var isPlaceholder = true

    /// Set when disk moved while the buffer was dirty. Not an error state: it means
    /// the next save has to ask before it overwrites someone else's work.
    /// All three files write it — cleared on load and after a save, raised on a
    /// refresh that finds a dirty buffer — so it cannot be `private(set)`.
    var hasExternalChange = false

    /// Write the file back as whatever it was read as. Re-encoding a Latin-1 or
    /// UTF-16 file to UTF-8 behind the user's back is a silent, whole-file diff.
    /// Settable because `+Editing` reassigns it when the user explicitly consents
    /// to a UTF-8 rewrite.
    var savedEncoding: String.Encoding = .utf8

    /// Identity of the bytes currently on screen, so `documentWindowDidBecomeKey`
    /// can re-read only when disk actually moved. Comparing content would mean
    /// reading the file on every window focus; comparing (mtime, size) is one stat.
    /// Re-stamped by `+Editing`'s `write()` as well, so the save we just performed
    /// is not read back as someone else's external change.
    var loadedStamp: (date: Date, size: Int)?

    /// Read by `setFontSize` in `+Document`, which does the clamping.
    static let minFontSize = CGFloat(AppConfig.minFontSize)
    static let maxFontSize = CGFloat(AppConfig.maxFontSize)

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

        // Re-set per load: `reload` locks this back down for placeholder bodies.
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = self
        // Plain-text editing conveniences that are actively wrong for code.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
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
    private struct Contents {
        let text: String
        let isPlaceholder: Bool
        let encoding: String.Encoding
    }

    private func read() -> Contents {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0

        if size > Self.maxBytes {
            return tooLargePlaceholder(bytes: size)
        }

        guard let data = try? Data(contentsOf: url) else {
            return Contents(
                text: "Could not read \(url.lastPathComponent).", isPlaceholder: true,
                encoding: .utf8)
        }

        // Re-check against what actually loaded, not just the pre-read stat above:
        // the file can grow between that stat and this read completing — this
        // app's own concurrent-agent-write premise — and trusting a stale "it was
        // small a moment ago" would defeat the whole point of the guard
        // (PR #2 review, finding 3).
        if data.count > Self.maxBytes {
            return tooLargePlaceholder(bytes: data.count)
        }

        if data.prefix(Self.sniffBytes).contains(0) {
            return Contents(
                text: "\(url.lastPathComponent) is a binary file.", isPlaceholder: true,
                encoding: .utf8)
        }

        // UTF-8 first because it is essentially always the answer; the second
        // attempt catches the Latin-1 and UTF-16 stragglers without which a
        // legitimately-readable file would be mislabelled binary.
        if let text = String(data: data, encoding: .utf8) {
            return Contents(text: text, isPlaceholder: false, encoding: .utf8)
        }
        var encoding: String.Encoding = .utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            return Contents(text: text, isPlaceholder: false, encoding: encoding)
        }
        return Contents(
            text: "\(url.lastPathComponent) is not text in any encoding Umber recognises.",
            isPlaceholder: true, encoding: .utf8)
    }

    /// Shared by both the pre-read stat check and the post-read TOCTOU re-check in
    /// `read()`, so the message can't drift between the two call sites.
    private func tooLargePlaceholder(bytes: Int) -> Contents {
        let mb = Double(bytes) / Double(1 << 20)
        return Contents(
            text: "\(url.lastPathComponent) is \(String(format: "%.1f", mb)) MB — too large to view.\n"
                + "Umber's viewer lays out the whole file at once, so it caps at "
                + "\(Self.maxBytes >> 20) MB. Open it in the terminal instead.",
            isPlaceholder: true, encoding: .utf8)
    }

    /// Pull the current bytes onto the screen.
    ///
    /// `preservingScroll` is what makes the refresh-on-focus behaviour tolerable:
    /// an agent appending to a log you are reading should not fling you back to
    /// line 1 every time you ⌘-tab into the window.
    ///
    /// Internal rather than private because both extensions reload: `+Document`'s
    /// `refresh(diskChanged:)` on a clean buffer, and `+Editing`'s "Discard Mine and
    /// Reload" branch. It stays the single way bytes reach the screen.
    func reload(preservingScroll: Bool) {
        let origin = scrollView.contentView.bounds.origin
        let contents = read()
        let text = contents.text
        isPlaceholder = contents.isPlaceholder
        savedEncoding = contents.encoding

        textView.string = text
        // Assigning `string` does not notify the delegate, so `isDirty` has to be
        // cleared by hand — and the undo stack with it, or ⌘Z would "restore" text
        // from a previous revision of a file that has since changed on disk.
        textView.undoManager?.removeAllActions()
        setDirty(false)
        hasExternalChange = false
        // Rule 3: an explanation is not the file, so it must not be savable.
        textView.isEditable = !isPlaceholder
        // Set the font after the string: assigning `string` on a plain-text view
        // re-applies `font` to the whole run, but only if `font` is already set —
        // ordering it the other way leaves placeholder text at the system default.
        textView.font = Self.resized(config.font, to: fontSize)
        textView.textColor = isPlaceholder
            ? config.effectiveForeground.withAlphaComponent(0.6)
            : config.effectiveForeground
        textView.insertionPointColor = config.theme?.cursor ?? config.effectiveForeground
        highlightSyntax()

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
    /// Internal because `+Document`'s `setFontSize` resizes through it too.
    static func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        AppConfig.resized(base, to: size)
    }
}
