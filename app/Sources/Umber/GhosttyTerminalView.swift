//
//  GhosttyTerminalView.swift
//  libghostty's view, plus this app's own key handling.
//
//  The exact counterpart of `UmberTerminalView`, and deliberately so: the ⌘-chord table in
//  `KeyBindings.swift` is this app's opinion about mac line editing, not either emulator's,
//  so it must reach a Ghostty-backed pane the same way it reaches a SwiftTerm-backed one or
//  ⌘⌫ silently stops working the moment you switch engines.
//
//  WHAT IS DIFFERENT FROM THE SWIFTTERM SUBCLASS, and it matters:
//
//  * `AppTerminalView` (aliased `TerminalView`, `View/TerminalView.swift:15`) is declared
//    `open class ... : NSView` (`AppTerminalView.swift:13`), and it **already overrides**
//    `performKeyEquivalent(with:)` as `open` (`AppTerminalView+Input.swift:17-84`). So unlike
//    SwiftTerm — where `keyDown` is `public`, not `open`, and could not be overridden at all
//    (see `UmberTerminalView`'s header) — here `super` is a real implementation that does
//    libghostty's own keybind resolution. Calling it is mandatory, not decorative: skipping
//    it would silently drop every binding the engine owns.
//
//  * There is no kitty-keyboard guard here yet, and its absence is a KNOWN GAP rather than a
//    decision. `UmberTerminalView` checks `getTerminal().keyboardEnhancementFlags.isEmpty`
//    before rewriting a chord, so a program that asked for raw modifiers (`CSI > 1 u`) keeps
//    them. libghostty exposes no equivalent query through the Swift wrapper — grepping
//    `Sources/GhosttyTerminal` finds no `keyboardEnhancement`/`kitty` symbol at all — so the
//    check cannot be reproduced. Consequence, stated plainly: under this engine, ⌘⌫ is
//    rewritten to ^U even inside an editor that enabled the kitty protocol. afk's REPL never
//    enables it (plan §4.1), which is the case this app exists to host, so this is acceptable
//    for a probe and is NOT acceptable as a shipped default. Phase 5's 17-case chord parity
//    run is where this has to be resolved.
//

import AppKit
import GhosttyTerminal

/// `AppTerminalView` with the mac line-editing keys wired up.
@MainActor
final class GhosttyTerminalView: TerminalView {
    /// The bell arrives here as a real delegate callback (`TerminalSurfaceBellDelegate`,
    /// `TerminalSurfaceViewDelegate.swift:36-38`) rather than through a subclass override, so
    /// this class needs no bell member at all — `GhosttyPane` adopts that protocol directly.
    /// Noted rather than left as an absence, because the SwiftTerm side needed a whole
    /// `bellDelegate` slot and an override to reach the same signal, and a reader comparing
    /// the two files should know the difference is the engine's, not an oversight.

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let bytes = MacLineEditing.controlBytes(
            keyCode: event.keyCode, modifiers: event.modifierFlags)
        else { return super.performKeyEquivalent(with: event) }

        // Every view in the key window is offered the equivalent, not just the focused one —
        // same reasoning as the SwiftTerm subclass: today there is one pane per window so
        // this is moot, and once splits exist it is what keeps ^U out of the pane you are not
        // typing in.
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }

        // `sendText` rather than a raw byte write: the Swift wrapper exposes
        // `AppTerminalView.sendText(_:)` (`AppTerminalView+PublicInput.swift:17-19`) and keeps
        // the underlying `TerminalSurface` internal (`AppTerminalView.swift:42-44`), so there
        // is no public path for a `[UInt8]`. The control bytes are all C0 (0x01…0x1F), every
        // one of which is a valid single Unicode scalar, so the round-trip through String is
        // lossless here — it would NOT be for arbitrary bytes, which is why this decodes
        // explicitly rather than reaching for `String(decoding:as:)` on untrusted input.
        sendText(String(bytes.map { Character(UnicodeScalar($0)) }))
        return true
    }
}
