//
//  FileViewerPane+SmartEditing.swift
//  Auto-indent, tab→spaces, and bracket/quote auto-pairing.
//
//  Owns the `NSTextViewDelegate` conformance that `+Editing.swift` used to hold.
//  Moved here because `textDidChange` and `shouldChangeTextIn` must live in the
//  same Swift extension (same protocol conformance), and the smart-editing
//  logic is the concern that grew large enough to justify its own file. The write
//  path (`setDirty`, `write()`, alerts) stays in `+Editing.swift` — the *dangerous*
//  half of the viewer — which is the audit boundary that matters.
//

import AppKit

// MARK: - NSTextViewDelegate

extension FileViewerPane: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        setDirty(true)
        highlightEditedParagraph()
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                  replacementString replacement: String?) -> Bool {
        guard let replacement, !isPlaceholder else { return true }

        // Tab → spaces.
        if replacement == "\t" && config.softTabs {
            let spaces = String(repeating: " ", count: config.tabWidth)
            textView.insertText(spaces, replacementRange: range)
            return false
        }

        // Auto-indent on Enter.
        if replacement == "\n" {
            let inserted = autoIndentedNewline(in: textView, at: range)
            textView.insertText(inserted, replacementRange: range)
            return false
        }

        // Bracket / quote auto-pairing (single-character typed, no selection).
        if replacement.count == 1 && range.length == 0 {
            let ch = replacement.first!
            if let close = Self.closerFor(ch) {
                // Skip-close: typing a closer when cursor is already on it.
                if ch == close, let str = textView.string as NSString?,
                   range.location < str.length,
                   str.character(at: range.location) == ch.asciiValue! {
                    textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                    return false
                }
                // Don't pair inside strings or comments.
                if !isInsideStringOrComment(at: range.location) {
                    let pair = "\(ch)\(close)"
                    textView.insertText(pair, replacementRange: range)
                    // Place cursor between the pair.
                    textView.setSelectedRange(
                        NSRange(location: range.location + 1, length: 0))
                    return false
                }
            }
        }

        // Delete-pair: backspace between an empty pair → remove both.
        if replacement.isEmpty && range.length == 1 && range.location > 0 {
            let str = textView.string as NSString
            let before = range.location - 1
            let after = range.location
            if after < str.length {
                let open = Character(UnicodeScalar(str.character(at: before))!)
                let close = Character(UnicodeScalar(str.character(at: after))!)
                if Self.closerFor(open) == close {
                    // Delete both characters.
                    textView.insertText("",
                        replacementRange: NSRange(location: before, length: 2))
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Auto-indent

    /// Build a newline string carrying the current line's leading whitespace,
    /// plus one extra indent level after `{`, `(`, `[`, or `:` (Python).
    private func autoIndentedNewline(in tv: NSTextView, at range: NSRange) -> String {
        let str = tv.string as NSString

        // Find current line's range and extract its leading whitespace.
        let lineRange = str.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = str.substring(with: lineRange)
        let leadingWS = String(lineText.prefix(while: { $0 == " " || $0 == "\t" }))

        // Smart indent: if the character before the cursor is an opener or colon,
        // add one indent level.
        var extra = ""
        if range.location > 0 {
            let beforeCursor = str.character(at: range.location - 1)
            if let ch = UnicodeScalar(beforeCursor),
               Self.smartIndentOpeners.contains(Character(ch)) {
                extra = config.softTabs
                    ? String(repeating: " ", count: config.tabWidth)
                    : "\t"
            }
        }

        return "\n" + leadingWS + extra
    }

    private static let smartIndentOpeners: Set<Character> = ["{", "(", "[", ":"]

    // MARK: - Auto-pairing

    /// Returns the closing character for an opener, or nil.
    private static func closerFor(_ ch: Character) -> Character? {
        switch ch {
        case "{": return "}"
        case "(": return ")"
        case "[": return "]"
        case "\"": return "\""
        case "'": return "'"
        case "`": return "`"
        // Close-bracket characters: return themselves so skip-close works.
        case "}", ")", "]": return ch
        default: return nil
        }
    }

    /// Heuristic: check whether the cursor is inside a string or comment span
    /// by looking at the foreground colour attribute. The syntax highlighter marks
    /// strings and comments with specific colours; if the cursor sits inside one
    /// of those spans, auto-pairing would double-quote inside an already-quoted
    /// string.
    private func isInsideStringOrComment(at location: Int) -> Bool {
        guard location > 0 else { return false }
        guard let colours = syntaxColours(),
              let stringColour = colours[.string],
              let commentColour = colours[.comment] else { return false }
        guard let ts = textView.textStorage else { return false }
        let checkLoc = min(location, ts.length - 1)
        guard checkLoc >= 0 else { return false }
        guard let fg = ts.attribute(.foregroundColor, at: checkLoc, effectiveRange: nil)
                as? NSColor else { return false }
        return fg == stringColour || fg == commentColour
    }
}
