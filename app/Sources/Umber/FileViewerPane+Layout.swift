//
//  FileViewerPane+Layout.swift
//  Soft-wrap and tab-width display — the two layout behaviours a code editor
//  needs that a plain NSTextView does not ship.
//
//  Its own file because these methods push `FileViewerPane.swift` past the
//  350-line ceiling and they form a clean seam: everything here is "how the
//  text view lays out its content", not "what content is on screen".
//

import AppKit

extension FileViewerPane {
    /// Toggle between wrapping and non-wrapping layout.
    ///
    /// Wrapping: the text container tracks the scroll view's width and lines fold.
    /// Non-wrapping: the container is unbounded and the user scrolls horizontally.
    /// The toggle is live — no reload needed.
    func setWrapping(_ wrap: Bool) {
        isWrapping = wrap
        guard let tc = textView.textContainer else { return }
        if wrap {
            tc.widthTracksTextView = true
            tc.containerSize = NSSize(
                width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
        } else {
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }
        textView.needsLayout = true
    }

    /// Resolve the wrap mode for the current file from config + file extension.
    func applyWrapping() {
        switch config.wordWrap {
        case .on:  setWrapping(true)
        case .off: setWrapping(false)
        case .auto:
            let ext = url.pathExtension
            let wrapByDefault = languageForExtension(ext)?.family == .markdown
                || ext.lowercased() == "txt"
            setWrapping(wrapByDefault)
        }
    }

    /// Install the configured tab width as the text view's tab stop interval.
    func applyTabWidth() {
        // Guard: compare the desired interval against the one already on the text
        // view before touching textStorage. apply(config:) calls this on every
        // config push, including theme changes where tabWidth is unchanged. Without
        // the guard, every such call performs an O(n) addAttribute walk over the
        // full document for no visible effect. Swift extensions cannot hold stored
        // properties, so we derive "already applied?" from the existing paragraph
        // style rather than a tracking var.
        let charWidth = ("m" as NSString).size(
            withAttributes: [.font: textView.font ?? config.font]).width
        let desiredInterval = charWidth * CGFloat(config.tabWidth)
        if let existing = textView.defaultParagraphStyle,
           abs(existing.defaultTabInterval - desiredInterval) < 0.5 { return }

        let ps = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        ps.defaultTabInterval = desiredInterval
        ps.tabStops = []    // Clear AppKit's default 28pt stops.
        textView.defaultParagraphStyle = ps
        // Re-apply to the existing text so literal \t chars render at the right width.
        if let ts = textView.textStorage, ts.length > 0 {
            ts.addAttribute(.paragraphStyle, value: ps,
                            range: NSRange(location: 0, length: ts.length))
        }
    }
}
