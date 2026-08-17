//
//  TerminalPane+Links.swift
//  URL clicking — ⌘-hover to highlight, ⌘-click to open.
//
//  Its own file because TerminalPane.swift is at the 350-LOC ceiling and this is a
//  whole independent concern: detecting URLs in terminal output and opening them.
//
//  HOW LINK CLICKING WORKS IN SWIFTTERM (the wiring, so future readers do not have
//  to grep the vendor tree):
//
//  1. DETECTION. `MacTerminalView` tracks links via `view.linkReporting`:
//       .none     — no tracking at all
//       .explicit — OSC 8 hyperlinks only (e.g. `\e]8;;https://…\a`)
//       .implicit — OSC 8 first, then falls back to plain-text URL detection
//     We use `.implicit` so that both OSC 8 payloads and bare http(s):// strings
//     printed to the terminal are clickable without requiring the program to emit
//     hyperlink escapes. Set in `UmberTerminalView.init(frame:)`.
//     Source: `Apple/AppleTerminalView.swift:41-49`, `Mac/MacTerminalView.swift:889-890`.
//
//  2. HIGHLIGHTING. `view.linkHighlightMode` controls when underlines appear and
//     when a click is honoured:
//       .hover             — underline on hover; click always activates
//       .hoverWithModifier — underline on ⌘+hover; click activates only if highlighted
//       .always            — always underline explicit links; click activates
//       .alwaysWithModifier — underline explicit links when ⌘ held; click when highlighted
//     `.hoverWithModifier` (the default and our setting) is the standard macOS terminal
//     convention: hold ⌘ to reveal and activate links, plain clicks remain free for
//     selection and mouse reporting. iTerm2, Ghostty, and Terminal.app all behave this way.
//     Source: `Apple/AppleTerminalView.swift:51-68`, `Mac/MacTerminalView.swift:893`.
//
//  3. ACTIVATION. On mouse-up, `MacTerminalView.mouseUp(with:)` calls `linkForClick`,
//     which requires both `hasCommandModifier` AND that the link is currently
//     highlighted (the user was hovering with ⌘ held). If matched, it invokes
//     `terminalDelegate?.requestOpenLink(source:link:params:)`.
//     Source: `Mac/MacTerminalView.swift:2500-2507`,
//             `Apple/AppleTerminalView.swift:935-951`.
//
//  4. DELEGATE. `LocalProcessTerminalView` sets `terminalDelegate = self` in its own
//     `setup()` (`Mac/MacLocalTerminalView.swift:85`). Its `requestOpenLink` forwards
//     to `openLink(_:)`, which validates and opens. We override `requestOpenLink` in
//     `UmberTerminalView` — the subclass that already exists for Umber-specific behaviour —
//     to filter to safe schemes and log under `UMBER_DIAG`. Reassigning `terminalDelegate`
//     is explicitly warned against upstream (`MacLocalTerminalView.swift:59-64`), so the
//     override is the correct hook.
//     Source: `Mac/MacTerminalView.swift:3020-3030`.
//
//  WHY TERMINALVIEW, NOT TERMINALPANE. `requestOpenLink` is on `TerminalViewDelegate`,
//  not `LocalProcessTerminalViewDelegate`. `TerminalPane` conforms to the latter; only
//  `UmberTerminalView` (which extends `LocalProcessTerminalView`) is the delegate.
//  There is nothing for `TerminalPane` to implement here — the link callback never
//  reaches it. The concern file lives here so the architecture is documented in one
//  place, and so any future `TerminalPane`-level hook (custom link handler, open-in-
//  editor routing, security policy) has an obvious home.
//

import AppKit
import SwiftTerm

// MARK: - UmberTerminalView link activation

extension UmberTerminalView {
    /// Open `link` in the default browser, filtering to schemes that are safe to
    /// hand to `NSWorkspace.shared.open` without prompting the user.
    ///
    /// WHY SCHEME-FILTER. `NSWorkspace.shared.open(url)` is a shell-open: it honours
    /// the URL's scheme and dispatches to whatever handler the user has registered.
    /// `openLink(_:)` in the SwiftTerm default (`Mac/MacTerminalView.swift:3020-3025`)
    /// accepts any string parseable as a `URL(string:)`, including `mailto:`,
    /// `ftp:`, and custom schemes that could invoke unexpected applications. Filtering
    /// to a known-safe list matches Terminal.app and Ghostty behaviour and means a
    /// rogue program that emits an OSC 8 with a `javascript:` payload cannot trigger
    /// anything outside a browser's own sandbox. `file://` is included because
    /// programs legitimately emit build-output paths.
    ///
    /// Implicit plain-text matches are always http/https (SwiftTerm's regex accepts
    /// only those two: `Terminal.swift:5971`), so the filter is primarily a defence
    /// against explicitly-crafted OSC 8 payloads.
    func openSafeURL(_ link: String) {
        guard let url = URL(string: link) else {
            if ProcessInfo.processInfo.environment["UMBER_DIAG"] != nil {
                FileHandle.standardError.write(
                    "[diag] link-click: not a valid URL — \(link)\n"
                        .data(using: .utf8)!)
            }
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" || scheme == "file" else {
            if ProcessInfo.processInfo.environment["UMBER_DIAG"] != nil {
                FileHandle.standardError.write(
                    "[diag] link-click: scheme '\(scheme)' blocked — \(link)\n"
                        .data(using: .utf8)!)
            }
            return
        }
        if ProcessInfo.processInfo.environment["UMBER_DIAG"] != nil {
            FileHandle.standardError.write(
                "[diag] link-click: opening \(url.absoluteString)\n"
                    .data(using: .utf8)!)
        }
        NSWorkspace.shared.open(url)
    }
}
