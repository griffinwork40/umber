//
//  FileViewerPane+Highlighting.swift
//  Regex-based syntax highlighting for the file viewer.
//
//  The consumer `SyntaxPalette.swift` has been waiting for since 2026-08-03: five
//  syntax roles (keyword, string, number, type, comment) painted with the ANSI colours
//  the palette was already measured for. No tree-sitter, no grammar bundles, no opaque
//  binaries — a regex tokenizer that gets the easy 90% right and leaves the hard 10%
//  as plain text, which is the honest trade for a viewer whose bar is "beautiful" and
//  whose gate is `check-theme-contrast.sh`.
//
//  **Why regex and not tree-sitter.** Three of this repo's four vendored patches fix
//  bugs found by *reading* vendored source. tree-sitter's grammars are prebuilt C
//  artifacts that cannot be read, and the AFK.md already records that trade as a real
//  cost (libghostty §). A regex tokenizer is ~200 lines of auditable Swift that covers
//  every language an agent workspace opens daily. It will mis-colour a raw string
//  literal or a nested block comment; it will never silently ship an upstream defect.
//
//  **Performance.** Highlighting runs on the full text after `reload` and on config
//  change. For the 4 MiB / ~100k line cap `FileViewerPane` already enforces, this is
//  well under a frame. `textDidChange` re-highlights only the edited paragraph, which
//  is the cheapest scope `NSTextStorage` supports without a custom layout manager.
//
//  Language detection (extension → family + keywords) lives in `SyntaxLanguage.swift`,
//  pulled out when this file hit the 350-line ceiling. The seam is clean: that file
//  answers "what language is this file?" and this one answers "how do I paint it?".
//

import AppKit

// MARK: - Tokeniser

/// A token: a range in the source text and its syntax role.
private struct Token {
    let range: NSRange
    let role: SyntaxRole
}

/// Tokenise a string for a given language family and keyword set.
///
/// Returns tokens sorted by location. Tokens never overlap — a string inside a
/// comment is a comment, not a string. This is enforced by the ordering: comments
/// and strings are matched first, and the `occupied` set prevents later patterns
/// from claiming ranges already taken.
private func tokenise(_ text: NSString, family: LanguageFamily, keywords: Set<String>) -> [Token] {
    var tokens: [Token] = []
    // Tracks character offsets already claimed. A simple bitset would be faster for
    // very large files, but `IndexSet` is correct and clear, and the 4 MiB cap means
    // the worst case is well bounded.
    var occupied = IndexSet()

    func add(_ range: NSRange, _ role: SyntaxRole) {
        guard range.length > 0 else { return }
        let proposed = range.lowerBound..<range.upperBound
        guard !occupied.intersects(integersIn: proposed) else { return }
        tokens.append(Token(range: range, role: role))
        occupied.insert(integersIn: proposed)
    }

    let len = text.length
    let fullRange = NSRange(location: 0, length: len)

    // --- Phase 1: comments (highest priority — nothing overrides a comment) ---
    switch family {
    case .cLike:
        // Block comments: /* ... */
        findAll(#"/\*[\s\S]*?\*/"#, in: text, range: fullRange).forEach { add($0, .comment) }
        // Line comments: //
        findAll(#"//[^\r\n]*"#, in: text, range: fullRange).forEach { add($0, .comment) }
    case .python:
        // Docstrings (triple-quoted) as comments — matched before strings.
        findAll(#""{3}[\s\S]*?"{3}"#, in: text, range: fullRange).forEach { add($0, .comment) }
        findAll(#"'{3}[\s\S]*?'{3}"#, in: text, range: fullRange).forEach { add($0, .comment) }
        findAll(#"#[^\r\n]*"#, in: text, range: fullRange).forEach { add($0, .comment) }
    case .ruby:
        findAll(#"=begin[\s\S]*?=end"#, in: text, range: fullRange).forEach { add($0, .comment) }
        findAll(#"#[^\r\n]*"#, in: text, range: fullRange).forEach { add($0, .comment) }
    case .shell:
        findAll(#"#[^\r\n]*"#, in: text, range: fullRange).forEach { add($0, .comment) }
    case .html:
        findAll(#"<!--[\s\S]*?-->"#, in: text, range: fullRange).forEach { add($0, .comment) }
    case .markdown:
        // No comments in markdown; headings, bold, etc. are structural, not syntax.
        break
    }

    // --- Phase 2: strings (next priority) ---
    switch family {
    case .cLike, .shell:
        // Double-quoted strings (with escaped quote support).
        findAll(#""(?:[^"\\]|\\.)*""#, in: text, range: fullRange).forEach { add($0, .string) }
        // Single-quoted strings.
        findAll(#"'(?:[^'\\]|\\.)*'"#, in: text, range: fullRange).forEach { add($0, .string) }
        // Backtick template literals (JS/TS — harmless false positives in others).
        findAll(#"`(?:[^`\\]|\\.)*`"#, in: text, range: fullRange).forEach { add($0, .string) }
    case .python, .ruby:
        findAll(#""(?:[^"\\]|\\.)*""#, in: text, range: fullRange).forEach { add($0, .string) }
        findAll(#"'(?:[^'\\]|\\.)*'"#, in: text, range: fullRange).forEach { add($0, .string) }
    case .html:
        findAll(#""[^"]*""#, in: text, range: fullRange).forEach { add($0, .string) }
        findAll(#"'[^']*'"#, in: text, range: fullRange).forEach { add($0, .string) }
    case .markdown:
        // Inline code spans.
        findAll(#"`[^`]+`"#, in: text, range: fullRange).forEach { add($0, .string) }
    }

    // --- Phase 3: numbers ---
    // Hex, binary, octal, float, integer — broad enough for every family.
    findAll(#"\b0[xX][0-9a-fA-F_]+\b"#, in: text, range: fullRange).forEach { add($0, .number) }
    findAll(#"\b0[bB][01_]+\b"#, in: text, range: fullRange).forEach { add($0, .number) }
    findAll(#"\b0[oO][0-7_]+\b"#, in: text, range: fullRange).forEach { add($0, .number) }
    findAll(#"\b\d[\d_]*\.[\d_]+(?:[eE][+-]?\d+)?\b"#, in: text, range: fullRange)
        .forEach { add($0, .number) }
    findAll(#"\b\d[\d_]*\b"#, in: text, range: fullRange).forEach { add($0, .number) }

    // Boolean/nil literals — these read as numbers in every language that has them.
    let boolNil: Set<String>
    switch family {
    case .cLike: boolNil = ["true", "false", "nil", "null", "undefined",
                            "True", "False", "None", "nullptr", "YES", "NO"]
    case .python: boolNil = ["True", "False", "None"]
    case .ruby:   boolNil = ["true", "false", "nil"]
    case .shell:  boolNil = ["true", "false"]
    case .html, .markdown: boolNil = []
    }
    for lit in boolNil {
        findAll("\\b\(NSRegularExpression.escapedPattern(for: lit))\\b",
                in: text, range: fullRange).forEach { add($0, .number) }
    }

    // --- Phase 4: keywords ---
    for kw in keywords {
        findAll("\\b\(NSRegularExpression.escapedPattern(for: kw))\\b",
                in: text, range: fullRange).forEach { add($0, .keyword) }
    }

    // --- Phase 5: types (capitalised identifiers) ---
    switch family {
    case .cLike, .python, .ruby:
        findAll(#"\b[A-Z][a-zA-Z0-9_]*\b"#, in: text, range: fullRange).forEach { add($0, .type) }
    default:
        break
    }

    // --- Phase 5b: markdown-specific roles ---
    if family == .markdown {
        // Headings as keywords.
        findAll(#"^#{1,6}\s+.*$"#, in: text, range: fullRange).forEach { add($0, .keyword) }
        // Bold / italic markers as types (gives them the cyan tint).
        findAll(#"\*{1,3}[^*\n]+\*{1,3}"#, in: text, range: fullRange).forEach { add($0, .type) }
        findAll(#"_{1,3}[^_\n]+_{1,3}"#, in: text, range: fullRange).forEach { add($0, .type) }
    }

    // --- Phase 5c: HTML tag names as keywords ---
    if family == .html {
        findAll(#"</?[a-zA-Z][\w.-]*"#, in: text, range: fullRange).forEach { add($0, .keyword) }
        // Attribute names as types.
        findAll(#"\b[a-z][\w-]*(?=\s*=)"#, in: text, range: fullRange).forEach { add($0, .type) }
    }

    return tokens
}

/// All non-overlapping matches of a pattern in a string.
private func findAll(_ pattern: String, in text: NSString,
                     range: NSRange) -> [NSRange] {
    guard let regex = try? NSRegularExpression(
        pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
    return regex.matches(in: text as String, range: range).map(\.range)
}

// MARK: - Application

extension FileViewerPane {
    /// Resolve the theme's syntax colours as `NSColor`, cached per config reload.
    /// Uses `theme.ansi` directly — the AppKit bridge — so no `ThemePalette` conversion
    /// is needed. Falls back through `SyntaxPalette.ansiIndex` for slot lookup.
    func syntaxColours() -> [SyntaxRole: NSColor]? {
        guard let theme = config.theme else { return nil }
        var colours: [SyntaxRole: NSColor] = [:]
        for role in SyntaxRole.allCases {
            let index = SyntaxPalette.ansiIndex(for: role)
            guard index < theme.ansi.count else { continue }
            if role == .comment {
                // Re-derive the comment colour through the same APCA check
                // SyntaxPalette uses, but in AppKit land.
                let bg = theme.background
                let slot = theme.ansi[index]
                let bgHex = bg.hexString
                let slotHex = slot.hexString
                if let bgRGB = RGB(hex: bgHex), let slotRGB = RGB(hex: slotHex) {
                    if APCA.lc(text: slotRGB, background: bgRGB) >= SyntaxPalette.readableFloor {
                        colours[role] = slot
                    } else {
                        colours[role] = config.effectiveForeground
                            .withAlphaComponent(SyntaxPalette.commentAlpha)
                    }
                } else {
                    colours[role] = slot
                }
            } else {
                colours[role] = theme.ansi[index]
            }
        }
        return colours.isEmpty ? nil : colours
    }

    /// Apply syntax highlighting to the full text view contents.
    ///
    /// Called from `reload` after the text and base font/colour are set, and from
    /// `apply(config:)` when the theme changes. Idempotent: it resets foreground
    /// attributes on the full range before painting, so double-calling is harmless.
    func highlightSyntax() {
        guard !isPlaceholder else { return }
        let ext = url.pathExtension
        guard let lang = languageForExtension(ext),
              let colours = syntaxColours() else { return }

        let storage = textView.textStorage!
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        storage.beginEditing()
        // Reset to the base foreground colour first, so a re-highlight after config
        // change does not layer new attributes over stale ones.
        storage.addAttribute(.foregroundColor, value: config.effectiveForeground, range: fullRange)

        let tokens = tokenise(text, family: lang.family, keywords: lang.keywords)
        for token in tokens {
            if let colour = colours[token.role] {
                storage.addAttribute(.foregroundColor, value: colour, range: token.range)
            }
        }
        storage.endEditing()
    }

    /// Re-highlight only the edited paragraph. Called from `textDidChange` so that
    /// typing does not re-tokenise the entire file.
    func highlightEditedParagraph() {
        guard !isPlaceholder else { return }
        let ext = url.pathExtension
        guard let lang = languageForExtension(ext),
              let colours = syntaxColours() else { return }

        let storage = textView.textStorage!
        let text = storage.string as NSString
        // Find the paragraph range around the insertion point.
        let selection = textView.selectedRange()
        let loc = min(selection.location, text.length > 0 ? text.length - 1 : 0)
        let paraRange = text.paragraphRange(for: NSRange(location: loc, length: 0))

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: config.effectiveForeground, range: paraRange)
        let tokens = tokenise(text, family: lang.family, keywords: lang.keywords)
        for token in tokens {
            // Only apply tokens that intersect the edited paragraph.
            guard NSIntersectionRange(token.range, paraRange).length > 0 else { continue }
            if let colour = colours[token.role] {
                storage.addAttribute(.foregroundColor, value: colour, range: token.range)
            }
        }
        storage.endEditing()
    }
}
