//
//  FileViewerPane+Chrome.swift
//  Editor chrome that makes the viewer feel alive: current-line highlight,
//  bracket-match highlight, column guide, trailing-whitespace visualization,
//  and a status bar showing cursor position, language, encoding and indent mode.
//
//  Its own file because none of this touches the save path, the syntax
//  highlighter, or the dirty flag — it is pure "how the editor looks when
//  you are staring at it", and it would push `FileViewerPane.swift` back
//  toward the ceiling if folded in.
//

import AppKit

// MARK: - Current-line highlight

/// A custom `NSTextView` subclass that draws a subtle highlight on the line
/// containing the insertion point. Subclassing is the only way to intercept
/// `drawBackground(in:)` — `NSTextView` does not expose a delegate hook for it.
///
/// Also draws a column guide (vertical line at a configurable column) and dims
/// trailing whitespace so it is visible without being distracting.
@MainActor
final class EditorTextView: NSTextView {
    /// The column at which to draw a vertical guide line, or nil for none.
    /// Set from `apply(config:)` once config fields exist; hard-coded to 80
    /// until then.
    var columnGuide: Int? = 80

    /// Whether to visualize trailing whitespace with dim dots.
    var showTrailingWhitespace = true

    /// The background colour for the current line — a very slight lift from the
    /// editor background. Recalculated on every `apply(config:)`.
    var currentLineColor: NSColor = NSColor.white.withAlphaComponent(0.04)

    /// The colour for the column guide line.
    var columnGuideColor: NSColor = NSColor.white.withAlphaComponent(0.08)

    /// The colour for trailing-whitespace dots.
    var trailingWhitespaceColor: NSColor = NSColor.white.withAlphaComponent(0.15)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let lm = layoutManager, let tc = textContainer else { return }

        // -- Current line highlight --
        let insertion = selectedRange().location
        let str = (string as NSString)
        guard str.length > 0 else { return }
        let lineRange = str.lineRange(for: NSRange(location: min(insertion, str.length - 1), length: 0))
        let glyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        // boundingRect gives the visual extent of the line's glyphs, but we want
        // full-width so the highlight stretches edge to edge.
        let lineRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let fullWidthRect = NSRect(
            x: 0,
            y: lineRect.origin.y + textContainerInset.height,
            width: bounds.width,
            height: lineRect.height)

        if fullWidthRect.intersects(rect) {
            currentLineColor.setFill()
            fullWidthRect.fill()
        }

        // -- Column guide --
        if let col = columnGuide, col > 0 {
            let charWidth = ("m" as NSString).size(
                withAttributes: [.font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width
            let guideX = textContainerOrigin.x + tc.lineFragmentPadding + charWidth * CGFloat(col)
            let guideLine = NSRect(x: guideX, y: rect.origin.y, width: 1 / (window?.backingScaleFactor ?? 2), height: rect.height)
            if guideLine.intersects(rect) {
                columnGuideColor.setFill()
                guideLine.fill()
            }
        }

        // Draw trailing-whitespace dots. Must come after the column guide so
        // dots land above the guide line in the compositing order.
        drawTrailingWhitespace(in: rect)
    }

    /// Called by drawBackground(in:) after the column guide to draw trailing
    /// whitespace indicators — hooked there because drawBackground is already
    /// our override point and firing here keeps the dots composited in the right
    /// Z-order (above background, below glyphs).
    func drawTrailingWhitespace(in rect: NSRect) {
        guard showTrailingWhitespace,
              let lm = layoutManager, let tc = textContainer else { return }

        let str = string as NSString
        guard str.length > 0 else { return }

        // Only process lines visible in the dirty rect for performance.
        let glyphRange = lm.glyphRange(forBoundingRect: rect, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineStart = charRange.location
        while lineStart < NSMaxRange(charRange) && lineStart < str.length {
            let lineRange = str.lineRange(for: NSRange(location: lineStart, length: 0))

            // Find trailing whitespace (spaces and tabs before the line ending).
            var trailStart = NSMaxRange(lineRange)
            // Skip past the newline character(s). CRLF files end each line with
            // two characters (0x0D 0x0A), so we must peel both — otherwise the
            // lone \r is classified as trailing whitespace and draws a spurious dot.
            if trailStart > lineRange.location {
                if str.character(at: trailStart - 1) == 0x0A { trailStart -= 1 }
                if trailStart > lineRange.location,
                   str.character(at: trailStart - 1) == 0x0D { trailStart -= 1 }
            }
            let contentEnd = trailStart
            while trailStart > lineRange.location {
                let ch = str.character(at: trailStart - 1)
                if ch != 0x20 && ch != 0x09 { break }  // space or tab
                trailStart -= 1
            }

            if trailStart < contentEnd {
                // Draw a small dot for each trailing whitespace character.
                let dotSize: CGFloat = 2.5
                trailingWhitespaceColor.setFill()
                for i in trailStart..<contentEnd {
                    let glyphIdx = lm.glyphIndexForCharacter(at: i)
                    let loc = lm.location(forGlyphAt: glyphIdx)
                    let fragRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                    let x = textContainerOrigin.x + fragRect.origin.x + loc.x + 2
                    let y = textContainerOrigin.y + fragRect.origin.y + loc.y - dotSize / 2 - 1
                    let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                    NSBezierPath(ovalIn: dotRect).fill()
                }
            }

            lineStart = NSMaxRange(lineRange)
        }
    }
}

// MARK: - Status bar

/// A thin bar below the editor showing cursor position, language, encoding, and
/// indent mode. Follows the CotEditor / BBEdit pattern of a single informational
/// line at the bottom.
@MainActor
final class EditorStatusBar: NSView {
    private let label = NSTextField(labelWithString: "")

    /// The pane updates these properties; the bar redraws.
    var line: Int = 1
    var column: Int = 1
    var language: String = "Plain Text"
    var encoding: String = "UTF-8"
    var indentMode: String = "Spaces: 4"

    static let barHeight: CGFloat = 22

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        label.stringValue = "Ln \(line), Col \(column)  ·  \(language)  ·  \(encoding)  ·  \(indentMode)"
    }

    func applyTheme(background: NSColor, foreground: NSColor, isLight: Bool) {
        // A slightly lifted background separates the bar from the editor body.
        // On dark themes blend toward white (lift); on light themes blend toward
        // black (darken) — blending toward white on a light background produces
        // a bar indistinguishable from the editor itself.
        wantsLayer = true
        layer?.backgroundColor = background.blended(
            withFraction: 0.07, of: isLight ? .black : .white)?.cgColor ?? background.cgColor
        label.textColor = foreground.withAlphaComponent(0.55)
    }
}

// MARK: - FileViewerPane chrome wiring

extension FileViewerPane {
    /// Push theme colours into the editor text view's chrome layers.
    /// Called from `apply(config:)` in `+Document.swift`.
    func applyChrome(config: AppConfig) {
        let bg = config.effectiveBackground
        let fg = config.effectiveForeground
        // Current-line highlight: 4% white lift on dark backgrounds, 4% black lift on light.
        let isLight = config.appearance?.name == .aqua
        textView.currentLineColor = bg.blended(
            withFraction: 0.04, of: isLight ? .black : .white) ?? bg
        textView.columnGuideColor = fg.withAlphaComponent(0.08)
        textView.trailingWhitespaceColor = fg.withAlphaComponent(0.15)
        textView.insertionPointColor = config.theme?.cursor ?? fg
        statusBar?.applyTheme(background: bg, foreground: fg, isLight: isLight)
        updateStatusBar()
    }

    /// Refresh the status bar with current cursor position and file metadata.
    /// Called on every selection change (via `+SmartEditing`'s delegate) and on
    /// config reload.
    func updateStatusBar() {
        guard let bar = statusBar else { return }
        let str = textView.string as NSString
        let loc = textView.selectedRange().location
        // Compute line and column from the insertion point.
        var line = 1
        var col = 1
        let clampedLoc = min(loc, str.length)
        var i = 0
        while i < clampedLoc {
            let range = str.lineRange(for: NSRange(location: i, length: 0))
            // Advance `line` only when we are truly past a line terminator.
            // The original `<=` incorrectly fired when maxRange == clampedLoc at
            // an unterminated EOF (e.g. "hello" with cursor at 5), reporting
            // Ln 2 Col 1 instead of Ln 1 Col 6. The extra `clampedLoc < str.length`
            // guard ensures we only count a completed line when the cursor sits
            // inside a later line, not when it sits at the very end of the last
            // unterminated line.
            if NSMaxRange(range) < clampedLoc ||
               (NSMaxRange(range) == clampedLoc && clampedLoc < str.length) {
                line += 1
                i = NSMaxRange(range)
            } else {
                col = clampedLoc - i + 1
                break
            }
        }
        if i == clampedLoc { col = 1 }  // cursor at line start

        bar.line = line
        bar.column = col

        // Language from file extension.
        if let lang = languageForExtension(url.pathExtension) {
            bar.language = Self.displayName(for: url.pathExtension, family: lang.family)
        } else {
            bar.language = "Plain Text"
        }

        // Encoding.
        switch savedEncoding {
        case .utf8: bar.encoding = "UTF-8"
        case .utf16: bar.encoding = "UTF-16"
        case .isoLatin1: bar.encoding = "Latin-1"
        default: bar.encoding = "UTF-8"
        }

        // Indent mode.
        bar.indentMode = config.softTabs ? "Spaces: \(config.tabWidth)" : "Tabs: \(config.tabWidth)"

        bar.refresh()
    }

    /// Human-readable language name for the status bar.
    private static func displayName(for ext: String, family: LanguageFamily) -> String {
        switch ext.lowercased() {
        case "swift": return "Swift"
        case "js", "jsx", "mjs", "cjs": return "JavaScript"
        case "ts", "tsx": return "TypeScript"
        case "py": return "Python"
        case "rb": return "Ruby"
        case "c", "h": return "C"
        case "cpp", "cc", "cxx", "hpp", "hxx": return "C++"
        case "rs": return "Rust"
        case "go": return "Go"
        case "java": return "Java"
        case "kt", "kts": return "Kotlin"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "less": return "Less"
        case "json", "jsonc": return "JSON"
        case "sh", "bash": return "Shell"
        case "zsh": return "Zsh"
        case "fish": return "Fish"
        case "yml", "yaml": return "YAML"
        case "toml": return "TOML"
        case "html", "htm": return "HTML"
        case "xml": return "XML"
        case "svg": return "SVG"
        case "md", "markdown", "mdx": return "Markdown"
        default: return ext.uppercased()
        }
    }
}
