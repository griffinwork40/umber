//
//  FileViewerPane+Folding.swift
//  Indent-based code folding and symbol-outline wiring for the file viewer.
//
//  **Code folding** — click a triangle in the gutter to collapse or expand a block.
//  The approach is indent-based (no AST): a line at indent level N followed by at
//  least one line at level > N is the start of a foldable region. This works for
//  Python, YAML, Swift, Go, and most other languages without needing a grammar.
//
//  Architecture note: stored properties cannot live in extensions. The folding
//  engine needs two: `foldedRegions` (currently folded spans) and
//  `symbolOutlinePanel` (the live ⌘⇧O panel). Both live on `FileViewerPane` itself
//  and are declared there as `var foldedRegions` / `var symbolOutlinePanel`. This
//  file provides the logic that drives them.
//
//  **How folding works with NSTextView (TextKit 1)**
//  NSTextView has no built-in folding API. We implement it by:
//    1. Computing the character range of the fold body (lines after the header line,
//       up to the next line at the same or shallower indent).
//    2. Replacing that range in the `NSTextStorage` with a single "…" placeholder.
//    3. Storing the original text in `foldedRegions` keyed by the storage position
//       of the placeholder.
//    4. On unfold: replacing the placeholder with the stored text.
//
//  Folding mutates the text storage — which means the undo manager records it.
//  We wrap the edit in `beginEditing` / `endEditing` and mark the pane dirty.
//  The fold state is ephemeral (not persisted across closes).
//
//  **Gutter triangles** are drawn by `LineNumberRulerView` if it can reach the fold
//  engine. We use a notification-based coupling so `LineNumberRulerView` stays
//  AppKit-only and import-free of Umber types.
//
//  **⌘⇧O symbol outline** lives in this file because it needs `foldedRegions` to
//  translate folded-offset line numbers back to original line numbers, and because
//  the panel's stored reference lives on FileViewerPane alongside the fold state.
//
//  Keyboard shortcuts:
//    ⌘⌥[   fold the block at the cursor
//    ⌘⌥]   unfold the block at the cursor (or all, if nothing is folded there)
//    ⌘⇧O   open symbol outline
//

import AppKit

// MARK: - Stored-property declarations (must live on the type, not an extension)
//
// These are declared as `var` on FileViewerPane in the main class body. This
// extension cannot declare stored properties — it provides the logic only.

// MARK: - Fold region model

/// A single folded region: the storage range of the "…" placeholder and the original
/// text it replaced.
struct FoldRegion {
    /// The character offset in storage where the "…" placeholder sits.
    var placeholderLocation: Int
    /// The original text that was folded away (NOT including the header line).
    let originalText: String
    /// The 1-based line number of the header line (in the pre-fold text).
    let headerLine: Int
}

// MARK: - Folding engine

extension FileViewerPane {

    // MARK: Fold / Unfold actions

    /// Fold the block whose header line contains the cursor (⌘⌥[).
    @objc func foldAtCursor(_ sender: Any?) {
        guard !isPlaceholder else { return }
        guard let storage = textView.textStorage else { return }
        let str = storage.string as NSString
        let insertionLoc = textView.selectedRange().location
        let clampedLoc = min(insertionLoc, str.length > 0 ? str.length - 1 : 0)

        // Identify the header line.
        let lineRange = str.lineRange(for: NSRange(location: clampedLoc, length: 0))
        let headerLine = lineNumber(in: str, forOffset: lineRange.location)
        let headerIndent = indentLevel(of: str.substring(with: lineRange))

        // Find the body: consecutive lines with indent > headerIndent.
        guard let bodyRange = foldBodyRange(
            in: str, afterLine: lineRange, headerIndent: headerIndent) else { return }

        // Don't fold if this region is already folded.
        for region in foldedRegions where region.placeholderLocation == bodyRange.location {
            return
        }

        let originalText = str.substring(with: bodyRange)

        // Replace the body with a single "…" placeholder.
        // We wrap in a no-undo-registration to keep the fold/unfold as a single action.
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.unfoldRegionAt(location: bodyRange.location)
        }
        storage.beginEditing()
        storage.replaceCharacters(in: bodyRange, with: "…")
        storage.addAttribute(.foregroundColor,
                             value: config.effectiveForeground.withAlphaComponent(0.4),
                             range: NSRange(location: bodyRange.location, length: 1))
        storage.endEditing()

        let region = FoldRegion(
            placeholderLocation: bodyRange.location,
            originalText: originalText,
            headerLine: headerLine)
        foldedRegions.append(region)

        setDirty(true)
        rulerView?.needsDisplay = true
        // Re-apply folded-placeholder colour in case the highlighter reset it.
        applyFoldPlaceholderColours()
    }

    /// Unfold the block at the cursor location (⌘⌥]).
    @objc func unfoldAtCursor(_ sender: Any?) {
        guard !isPlaceholder else { return }
        guard let storage = textView.textStorage else { return }
        let str = storage.string as NSString
        let insertionLoc = textView.selectedRange().location
        let clampedLoc = min(insertionLoc, str.length > 0 ? str.length - 1 : 0)

        // Find the fold region whose placeholder is on or near the cursor line.
        let lineRange = str.lineRange(for: NSRange(location: clampedLoc, length: 0))
        if let idx = foldedRegions.firstIndex(where: { region in
            // The placeholder is a single character; the cursor must be in the same line.
            lineRange.contains(region.placeholderLocation)
                || region.placeholderLocation == lineRange.location
        }) {
            unfoldRegionAt(location: foldedRegions[idx].placeholderLocation)
        }
    }

    // MARK: Open/close via gutter click

    /// Toggle the fold state for the block starting at the given 1-based line number.
    /// Called by `LineNumberRulerView` when the user clicks a fold triangle.
    func toggleFold(atLine line: Int) {
        guard !isPlaceholder else { return }
        guard let storage = textView.textStorage else { return }
        let str = storage.string as NSString

        // Check if this line is the header of an existing fold region.
        if let idx = foldedRegions.firstIndex(where: { $0.headerLine == line }) {
            unfoldRegionAt(location: foldedRegions[idx].placeholderLocation)
            return
        }

        // Otherwise, try to fold it.
        var offset = 0
        var currentLine = 1
        while currentLine < line && offset < str.length {
            let range = str.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(range)
            currentLine += 1
        }
        let lineRange = str.lineRange(for: NSRange(location: min(offset, str.length > 0 ? str.length - 1 : 0), length: 0))
        let headerIndent = indentLevel(of: str.substring(with: lineRange))
        guard let bodyRange = foldBodyRange(
            in: str, afterLine: lineRange, headerIndent: headerIndent) else { return }

        let originalText = str.substring(with: bodyRange)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.unfoldRegionAt(location: bodyRange.location)
        }
        storage.beginEditing()
        storage.replaceCharacters(in: bodyRange, with: "…")
        storage.addAttribute(.foregroundColor,
                             value: config.effectiveForeground.withAlphaComponent(0.4),
                             range: NSRange(location: bodyRange.location, length: 1))
        storage.endEditing()

        let region = FoldRegion(
            placeholderLocation: bodyRange.location,
            originalText: originalText,
            headerLine: line)
        foldedRegions.append(region)
        setDirty(true)
        rulerView?.needsDisplay = true
        applyFoldPlaceholderColours()
    }

    // MARK: - Foldable line query (used by the gutter)

    /// Returns the set of 1-based line numbers that start a foldable region in
    /// the current text. Called by `LineNumberRulerView` to decide where to draw
    /// fold triangles. Cheap enough for gutter draw: O(n lines visible).
    func foldableLines() -> Set<Int> {
        guard !isPlaceholder else { return [] }
        guard let storage = textView.textStorage else { return [] }
        let str = storage.string as NSString
        let length = str.length
        guard length > 0 else { return [] }

        var result = Set<Int>()
        var offset = 0
        var lineNum = 1

        while offset < length {
            let lineRange = str.lineRange(for: NSRange(location: offset, length: 0))
            let lineText = str.substring(with: lineRange)
            let currentIndent = indentLevel(of: lineText)

            // Look at the next line.
            let nextOffset = NSMaxRange(lineRange)
            if nextOffset < length {
                let nextLineRange = str.lineRange(for: NSRange(location: nextOffset, length: 0))
                let nextLineText = str.substring(with: nextLineRange)
                let nextIndent = indentLevel(of: nextLineText)
                // A line is foldable if the next line is strictly more indented and
                // the current line is not blank.
                let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
                if nextIndent > currentIndent && !trimmed.isEmpty {
                    result.insert(lineNum)
                }
            }
            offset = NSMaxRange(lineRange)
            lineNum += 1
        }
        return result
    }

    /// Returns the set of 1-based line numbers that are currently folded headers.
    func foldedHeaderLines() -> Set<Int> {
        Set(foldedRegions.map(\.headerLine))
    }

    // MARK: - Symbol outline (⌘⇧O)

    /// Open the ⌘⇧O symbol outline panel for this pane.
    @objc func showSymbolOutline(_ sender: Any?) {
        guard !isPlaceholder, let window = scrollView.window else { return }

        // Dismiss any existing panel first.
        symbolOutlinePanel?.dismiss()
        symbolOutlinePanel = nil

        let ext = url.pathExtension
        guard let lang = languageForExtension(ext) else {
            // No known language — show an empty outline with an explanatory title.
            return
        }
        let symbols = extractSymbols(from: textView.string, family: lang.family)
        let panel = SymbolOutlinePanel(pane: self, symbols: symbols)
        symbolOutlinePanel = panel
        panel.show(relativeTo: window)
    }

    // MARK: - Internal helpers

    /// Unfold the region whose placeholder is at `location` in the current storage.
    func unfoldRegionAt(location: Int) {
        guard let idx = foldedRegions.firstIndex(where: {
            $0.placeholderLocation == location
        }) else { return }
        guard let storage = textView.textStorage else { return }
        let region = foldedRegions[idx]
        let placeholderRange = NSRange(location: region.placeholderLocation, length: 1)
        guard NSMaxRange(placeholderRange) <= storage.length else {
            // Stale region (shouldn't happen after a reload, but guard it).
            foldedRegions.remove(at: idx)
            return
        }

        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.foldAtCursor(nil)
        }
        storage.beginEditing()
        storage.replaceCharacters(in: placeholderRange, with: region.originalText)
        storage.endEditing()

        foldedRegions.remove(at: idx)
        // Shift all placeholder locations that come after this one.
        let delta = region.originalText.utf16.count - 1   // replaced 1 char ("…") with original
        for i in foldedRegions.indices {
            if foldedRegions[i].placeholderLocation > location {
                foldedRegions[i].placeholderLocation += delta
            }
        }
        setDirty(true)
        rulerView?.needsDisplay = true
        highlightSyntax()
    }

    /// Re-dim the "…" placeholders after a full `highlightSyntax()` call resets colours.
    /// The highlighter resets every character to the foreground colour; this restores
    /// the placeholder's subdued appearance.
    func applyFoldPlaceholderColours() {
        guard let storage = textView.textStorage else { return }
        let dimColour = config.effectiveForeground.withAlphaComponent(0.4)
        storage.beginEditing()
        for region in foldedRegions {
            let r = NSRange(location: region.placeholderLocation, length: 1)
            guard NSMaxRange(r) <= storage.length else { continue }
            storage.addAttribute(.foregroundColor, value: dimColour, range: r)
        }
        storage.endEditing()
    }

    /// The body range to fold: consecutive lines after `afterLine` whose indent
    /// level is strictly greater than `headerIndent`. Returns nil when no such
    /// lines exist (not a foldable region).
    private func foldBodyRange(
        in str: NSString, afterLine lineRange: NSRange, headerIndent: Int
    ) -> NSRange? {
        let length = str.length
        var offset = NSMaxRange(lineRange)
        var bodyEnd = offset
        var foundAny = false

        while offset < length {
            let nextLineRange = str.lineRange(for: NSRange(location: offset, length: 0))
            let nextText = str.substring(with: nextLineRange)
            let trimmed = nextText.trimmingCharacters(in: .whitespacesAndNewlines)
            // A blank line is included in the fold body (it's inside the block).
            let nextIndent = trimmed.isEmpty ? headerIndent + 1 : indentLevel(of: nextText)
            if nextIndent <= headerIndent && !trimmed.isEmpty { break }
            bodyEnd = NSMaxRange(nextLineRange)
            foundAny = true
            offset = NSMaxRange(nextLineRange)
        }

        guard foundAny && bodyEnd > NSMaxRange(lineRange) else { return nil }
        // The body starts at the end of the header line (i.e. includes the newline
        // at the end of the header).
        return NSRange(location: NSMaxRange(lineRange), length: bodyEnd - NSMaxRange(lineRange))
    }

    // indentLevel(of:) and lineNumber(in:forOffset:) → FileViewerPane+Navigation.swift

}
