//
//  StarterConfig.swift
//  The commented config.json written on first ⌘,.
//

/// The starter `config.json` template, as text.
///
/// Its own file because it is documentation that happens to be a string literal:
/// ~25 lines of user-facing prose (every `"// key"` is a comment the user reads in
/// their editor) with no behaviour, versioned alongside the fields it describes in
/// `Config.swift`. Sitting inside `AppDelegate` it made the delegate look 27 lines
/// bigger than the code it actually owns, and an edit to the template read as an
/// edit to app lifecycle in the diff.
///
/// Written only when `~/.config/umber/config.json` does not exist
/// (`AppDelegate.openConfigFile`); the app never rewrites an existing file. Keep
/// the values here in step with `AppConfig.defaults()` — that is the source of
/// truth, this is its annotated copy.
enum StarterConfig {
    static let text = """
    {
      "// font": "any installed monospaced family; omit family for SF Mono (the system monospaced face, and the default)",
      "// font.size": "points, 6-48. Default 14. Cmd+ / Cmd- zoom live on top of this and persist; Cmd0 clears the zoom and hands control back to this value.",
      "font": { "family": "SF Mono", "size": 14 },

      "// cursor": "block | steady-block | bar | steady-bar | underline | steady-underline",
      "cursor": "block",

      "// scrollback": "lines to retain; 0 disables scrollback entirely",
      "// scrollback-note": "past ~3500 the scrollbar thumb hits its 1% floor and stops tracking position, and every window resize walks the whole buffer",
      "scrollback": 1000,

      "// shell": "defaults to $SHELL; launched with -l so your PATH loads",
      "// optionAsMeta": "true lets Option act as Meta instead of typing accents",
      "optionAsMeta": true,

      "// theme": "OMITTED ON PURPOSE. With no theme, SwiftTerm's own colours stand and ANSI 16-255 keep the standard xterm values. Setting a background or foreground makes SwiftTerm regenerate indices 16-255 by interpolating them out of your bg/fg, so 256-colour programs render against synthesised approximations. Uncomment below only if you want that trade.",
      "// theme-example": {
        "preset": "afk-dark",
        "// preset-values": "afk-dark | tokyo-night | classic",
        "// overrides": "background/foreground/cursor/ansi may be set on top of a preset; ansi must be exactly 16 colours, 8 normal then 8 bright",
        "cursor": "#E67E4C"
      }
    }

    """
}
