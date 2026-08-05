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

      "// renderer": "coretext (default) | metal. metal is SwiftTerm's GPU path: a glyph atlas plus per-row vertex caching, which should scroll a big log noticeably faster than coretext, where every visible row is re-shaped through Core Text on every frame.",
      "// renderer-note": "OPT-IN because upstream calls the GPU path experimental and its speedup here has not been measured. Falls back to coretext by itself if it cannot start, and says so on stderr. Change it and hit Cmd-R; run app/Scripts/check-metal-renderer.sh if you suspect it silently fell back.",
      "renderer": "coretext",

      "// engine": "swiftterm (default) | ghostty. Which terminal core backs a NEW tab. swiftterm is the vendored SwiftTerm this app was built on; ghostty is libghostty, which is actively maintained and gives shell integration (OSC 7 working-directory and OSC 133 command-status reporting) that swiftterm structurally cannot.",
      "// engine-note": "OPT-IN, and read only when a tab is created — edit it and hit Cmd-R and the NEXT Cmd-T uses it, while the tab in front of you keeps its core (swapping an engine under a live shell would discard its scrollback). That is deliberate: it means you can run both cores side by side in one window and compare them on the same work. ghostty is still un-gated for the one bug class that matters most here (buffer reflow when you narrow a window), so it is not the default yet.",
      "// engine-caveat": "renderer above applies to swiftterm only; libghostty draws with its own renderer and ignores it.",
      "engine": "swiftterm",

      "// theme": "OMITTED HERE, WHICH MEANS UMBER — since 2026-08-03 the built-in default is the umber palette, so leaving this out gives you a measured theme rather than the emulator's raw colours. Installing a palette does NOT harm the 256-colour cube: this app pins ansi256PaletteStrategy to .xterm before any colour, so indices 16-255 stay the standard xterm values whatever you set. Set preset to classic if you genuinely want no colours installed.",
      "// theme-example": {
        "preset": "umber",
        "// preset-values": "umber | classic-repaired | afk-dark | afk-light | tokyo-night | classic",
        "// preset-note": "umber is the DEFAULT and the palette designed and measured for this app. classic-repaired keeps classic's true black, quiet body text and saturated ANSI colours while repairing its unreadable blue and collapsed blue bright step. classic itself still installs nothing. Verified by Scripts/check-theme-contrast.sh.",
        "// overrides": "background/foreground/cursor/ansi may be set on top of a preset; ansi must be exactly 16 colours, 8 normal then 8 bright",
        "cursor": "#FF9B5A"
      }
    }

    """
}
