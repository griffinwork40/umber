//
//  FileViewerPane+Navigation.swift
//  Go-to-line: the one navigation affordance a terminal-adjacent editor needs.
//
//  When a compiler error says "line 42", the user should be able to jump there
//  without counting. ⌘L opens a sheet, the user types a line number, and the
//  editor scrolls to it.
//
//  Its own file because the concern (a sheet, a text field, line↔offset math)
//  is completely self-contained and does not touch the save path, the syntax
//  highlighter, or the dirty flag. Adding it to `FileViewerPane.swift` or
//  `+Editing.swift` would push them into the ceiling warning band for no reason.
//

import AppKit

extension FileViewerPane {
    /// Action target for the Edit → "Go to Line…" (⌘L) menu item.
    ///
    /// `target: nil` in `AppMenu.swift` means AppKit walks the responder chain.
    /// `NSTextView` does not answer `goToLine:`, so it falls through to this
    /// extension on `FileViewerPane` — which is in the responder chain because
    /// it is the text view's delegate. The selector name matches Xcode's and
    /// BBEdit's convention.
    @objc func goToLine(_ sender: Any?) {
        guard let window = scrollView.window else { return }

        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a line number."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "Line number"
        field.formatter = Self.lineNumberFormatter
        alert.accessoryView = field
        // Focus the text field so typing starts immediately.
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self else { return }
            let lineNumber = field.integerValue
            guard lineNumber > 0 else { return }
            self.scrollToLine(lineNumber)
        }
    }

    // MARK: - Line number ↔ character offset

    /// Scroll the text view to a 1-based line number and place the cursor there.
    private func scrollToLine(_ line: Int) {
        let str = textView.string as NSString
        let length = str.length
        var currentLine = 1
        var offset = 0

        // Walk forward through line boundaries. `lineRange(for:)` gives the full
        // range of the logical line at a given location, so advancing past it
        // lands on the next line.
        while currentLine < line && offset < length {
            let range = str.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(range)
            currentLine += 1
        }
        // `offset` is now the start of the target line, or the end of the string
        // if the requested line is past the document.
        let targetRange = NSRange(location: min(offset, length), length: 0)
        textView.setSelectedRange(targetRange)
        textView.scrollRangeToVisible(targetRange)
    }

    /// Accepts positive integers only — no decimals, no negatives.
    ///
    /// Static so the formatter is allocated once per process rather than once per
    /// ⌘L invocation. NumberFormatter is expensive to construct (it loads locale
    /// data), and its configuration here is stateless, so sharing is safe.
    private static let lineNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.allowsFloats = false
        f.minimum = 1
        f.maximum = NSNumber(value: Int.max)
        return f
    }()
}
