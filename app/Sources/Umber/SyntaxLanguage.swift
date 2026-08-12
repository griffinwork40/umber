//
//  SyntaxLanguage.swift
//  File-extension → language mapping for the syntax highlighter.
//
//  **Pure and view-free — Foundation only, on purpose**, like `SyntaxPalette.swift`
//  beside it. The keyword sets and family groupings are data, not rendering — they
//  belong in a file a gate could compile standalone (though no gate does today,
//  because the tokeniser exercising them is AppKit-side).
//
//  Pulled out of `FileViewerPane+Highlighting.swift` when that file hit the 350-line
//  ceiling. The seam is clean: this file answers "what language is this file?" and the
//  other answers "how do I paint it?". Neither needs the other's imports.
//
//  The families are deliberately broad: `cLike` covers Swift, Rust, Go, C, C++, Java,
//  JS/TS and CSS because their comment syntax and string/number literals are the same
//  to a regex. The keyword lists differ, so each extension maps to its own keyword set
//  within the family.
//

import Foundation

/// A language family sharing one set of regex patterns.
enum LanguageFamily {
    case cLike
    case python
    case ruby
    case shell
    case html
    case markdown
}

/// Maps a file extension to (family, keywords). Returns nil for unknown extensions,
/// which disables highlighting — plain text stays plain, never mis-coloured.
func languageForExtension(_ ext: String) -> (family: LanguageFamily, keywords: Set<String>)? {
    switch ext.lowercased() {
    case "swift":
        return (.cLike, ["import", "func", "var", "let", "if", "else", "guard", "return",
            "switch", "case", "default", "for", "while", "repeat", "in", "where",
            "struct", "class", "enum", "protocol", "extension", "self", "super",
            "init", "deinit", "throw", "throws", "try", "catch", "do", "async",
            "await", "public", "private", "internal", "fileprivate", "open",
            "static", "final", "override", "mutating", "weak", "unowned",
            "typealias", "associatedtype", "some", "any", "as", "is", "break",
            "continue", "fallthrough", "defer", "precondition", "fatalError"])
    case "js", "jsx", "ts", "tsx", "mjs", "cjs":
        return (.cLike, ["import", "export", "from", "function", "const", "let", "var",
            "if", "else", "return", "switch", "case", "default", "for", "while",
            "do", "break", "continue", "class", "extends", "new", "this", "super",
            "try", "catch", "finally", "throw", "async", "await", "yield",
            "typeof", "instanceof", "in", "of", "delete", "void", "interface",
            "type", "enum", "as", "readonly", "declare", "abstract", "implements"])
    case "py":
        return (.python, ["import", "from", "def", "class", "if", "elif", "else",
            "return", "for", "while", "break", "continue", "pass", "raise", "try",
            "except", "finally", "with", "as", "yield", "lambda", "global",
            "nonlocal", "assert", "del", "in", "not", "and", "or", "is", "async",
            "await", "match", "case"])
    case "rb":
        return (.ruby, ["def", "class", "module", "if", "elsif", "else", "unless",
            "return", "do", "end", "begin", "rescue", "ensure", "raise", "yield",
            "block_given?", "require", "include", "extend", "attr_reader",
            "attr_writer", "attr_accessor", "self", "super", "while", "until",
            "for", "in", "break", "next", "case", "when", "then", "puts", "print"])
    case "c", "h":
        return (.cLike, ["if", "else", "return", "switch", "case", "default", "for",
            "while", "do", "break", "continue", "struct", "enum", "union", "typedef",
            "const", "static", "extern", "void", "int", "char", "float", "double",
            "long", "short", "unsigned", "signed", "sizeof", "goto", "volatile",
            "register", "inline", "restrict", "include", "define", "ifdef", "ifndef",
            "endif", "pragma"])
    case "cpp", "cc", "cxx", "hpp", "hxx":
        return (.cLike, ["if", "else", "return", "switch", "case", "default", "for",
            "while", "do", "break", "continue", "struct", "class", "enum", "union",
            "typedef", "const", "static", "extern", "virtual", "override", "final",
            "public", "private", "protected", "namespace", "using", "template",
            "typename", "auto", "new", "delete", "this", "throw", "try", "catch",
            "void", "int", "char", "float", "double", "bool", "nullptr", "constexpr",
            "noexcept", "inline", "include", "define", "ifdef", "ifndef", "endif"])
    case "rs":
        return (.cLike, ["fn", "let", "mut", "const", "if", "else", "match", "return",
            "for", "while", "loop", "break", "continue", "struct", "enum", "impl",
            "trait", "pub", "use", "mod", "crate", "self", "super", "as", "in",
            "where", "async", "await", "move", "ref", "type", "unsafe", "extern",
            "static", "dyn", "macro_rules"])
    case "go":
        return (.cLike, ["package", "import", "func", "var", "const", "if", "else",
            "return", "switch", "case", "default", "for", "range", "break",
            "continue", "struct", "interface", "type", "map", "chan", "go", "defer",
            "select", "fallthrough", "goto"])
    case "java", "kt", "kts":
        return (.cLike, ["import", "package", "class", "interface", "enum", "extends",
            "implements", "public", "private", "protected", "static", "final",
            "abstract", "void", "return", "if", "else", "switch", "case", "default",
            "for", "while", "do", "break", "continue", "new", "this", "super",
            "try", "catch", "finally", "throw", "throws", "synchronized", "val",
            "var", "fun", "when", "object", "companion", "override", "open"])
    case "css", "scss", "less":
        return (.cLike, ["import", "media", "keyframes", "font-face", "charset",
            "supports", "page", "namespace"])
    case "json", "jsonc":
        return (.cLike, [])
    case "sh", "bash", "zsh", "fish":
        return (.shell, ["if", "then", "else", "elif", "fi", "for", "while", "do",
            "done", "case", "esac", "in", "function", "return", "exit", "local",
            "export", "source", "alias", "unalias", "set", "unset", "shift",
            "break", "continue", "eval", "exec", "trap", "readonly", "declare"])
    case "yml", "yaml", "toml":
        // Accepted imprecision: `.shell` gives `#` comments, but the backtick
        // template-literal pattern fires on these languages where backtick is not
        // a string delimiter.
        return (.shell, [])
    case "html", "htm", "xml", "svg":
        return (.html, [])
    case "md", "markdown", "mdx":
        return (.markdown, [])
    default:
        return nil
    }
}
