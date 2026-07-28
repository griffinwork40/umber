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
/// undo and ⌘S, but no syntax highlighting and no tree-sitter. The plan's
/// highlighting candidate, CodeEditSourceEditor, still self-describes as "not ready
/// for production use" (plan §4.3), and it is a separate decision from whether you
/// can type.
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

    private var config: AppConfig
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    private var fontSize: CGFloat

    /// Unsaved edits live in the text view; this is the flag everything else reads.
    private var isDirty = false

    /// The body is an explanation ("…is a binary file."), not the file's contents.
    /// Gates editing — see rule 3 in the type comment.
    private var isPlaceholder = true

    /// Set when disk moved while the buffer was dirty. Not an error state: it means
    /// the next save has to ask before it overwrites someone else's work.
    private var hasExternalChange = false

    /// Write the file back as whatever it was read as. Re-encoding a Latin-1 or
    /// UTF-16 file to UTF-8 behind the user's back is a silent, whole-file diff.
    private var savedEncoding: String.Encoding = .utf8

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
            let mb = Double(size) / Double(1 << 20)
            return Contents(
                text: "\(url.lastPathComponent) is \(String(format: "%.1f", mb)) MB — too large to view.\n"
                    + "Umber's viewer lays out the whole file at once, so it caps at "
                    + "\(Self.maxBytes >> 20) MB. Open it in the terminal instead.",
                isPlaceholder: true, encoding: .utf8)
        }

        guard let data = try? Data(contentsOf: url) else {
            return Contents(
                text: "Could not read \(url.lastPathComponent).", isPlaceholder: true,
                encoding: .utf8)
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

    /// Pull the current bytes onto the screen.
    ///
    /// `preservingScroll` is what makes the refresh-on-focus behaviour tolerable:
    /// an agent appending to a log you are reading should not fling you back to
    /// line 1 every time you ⌘-tab into the window.
    private func reload(preservingScroll: Bool) {
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

// MARK: - Editing

extension FileViewerPane: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        setDirty(true)
    }
}

extension FileViewerPane {
    fileprivate func setDirty(_ dirty: Bool) {
        guard dirty != isDirty else { return }
        isDirty = dirty
        delegate?.fileViewerDidChangeEditedState(self)
    }

    /// Write the buffer back to disk. Returns false if the user cancelled or the
    /// write failed — callers treat that as "do not close".
    fileprivate func write() -> Bool {
        // Nothing to write, and nothing that *should* be written: a placeholder body
        // is Umber's prose, not the user's file.
        guard !isPlaceholder else { return true }
        guard isDirty else { return true }

        if hasExternalChange && !confirmOverwriteOfChangedFile() { return false }

        guard let data = encodedBuffer() else { return false }

        // Capture the mode before writing. `.atomic` writes a temp file and renames
        // it over the target, which means a NEW inode — so the original's permission
        // bits do not carry across on their own, and saving a shell script would
        // quietly drop its +x. Re-applied below.
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path))?[
            .posixPermissions] as? NSNumber

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentError(
                "Could not save \(url.lastPathComponent).", detail: error.localizedDescription)
            return false
        }
        if let mode {
            try? FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: url.path)
        }

        // Re-stamp from what is now on disk, so the very save we just performed is
        // not mistaken for someone else's external change on the next window focus.
        let stamp = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if let date = stamp?.contentModificationDate, let size = stamp?.fileSize {
            loadedStamp = (date, size)
        }
        hasExternalChange = false
        setDirty(false)
        return true
    }

    /// Encode with the file's original encoding, or get explicit permission to change
    /// it. Typing an emoji into a Latin-1 file is the usual way to land here.
    private func encodedBuffer() -> Data? {
        if let data = textView.string.data(using: savedEncoding) { return data }

        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) cannot be saved as \(encodingName)."
        alert.informativeText =
            "Some characters you typed do not exist in that encoding. Saving as UTF-8 will "
            + "rewrite the whole file's encoding."
        alert.addButton(withTitle: "Save as UTF-8")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        savedEncoding = .utf8
        return textView.string.data(using: .utf8)
    }

    private var encodingName: String {
        String.localizedName(of: savedEncoding)
    }

    private func confirmOverwriteOfChangedFile() -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) has changed on disk."
        alert.informativeText =
            "Something else — most likely the agent in the terminal — rewrote this file after "
            + "you started editing. Saving replaces its version with yours."
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Mine and Reload")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertThirdButtonReturn:
            reload(preservingScroll: true)
            return false
        default: return false
        }
    }

    private func presentError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        // A vanished file counts as changed — a clean viewer re-reads and renders the
        // "could not read" placeholder rather than leaving stale content up.
        guard let date = current?.contentModificationDate, let size = current?.fileSize,
            let loaded = loadedStamp
        else {
            refresh(diskChanged: true)
            return
        }
        refresh(diskChanged: loaded.date != date || loaded.size != size)
    }

    /// Rule 1, in one place: reload a clean buffer, never a dirty one.
    ///
    /// Auto-reloading over unsaved edits would destroy work with no gesture from the
    /// user and no way back — the single worst thing this class could do. So a dirty
    /// buffer only records that disk moved; the choice gets made later, deliberately,
    /// at save time (`confirmOverwriteOfChangedFile`).
    private func refresh(diskChanged: Bool) {
        guard diskChanged else { return }
        guard !isDirty else {
            hasExternalChange = true
            return
        }
        reload(preservingScroll: true)
    }

    var documentIsEdited: Bool { isDirty }

    func documentShouldClose() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(url.lastPathComponent)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        // Save / Cancel / Don't Save, in that order — the macOS HIG arrangement, and
        // the one muscle memory expects when ⌘W is followed by a blind ⏎.
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return write()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func saveDocument() -> Bool { write() }
}
