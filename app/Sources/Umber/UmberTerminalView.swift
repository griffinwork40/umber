//
//  UmberTerminalView.swift
//  SwiftTerm's view, plus this app's own key handling.
//

import AppKit
import SwiftTerm

/// `LocalProcessTerminalView` with the mac line-editing keys wired up.
///
/// A subclass rather than a patch to `vendor/SwiftTerm`: the vendored copy
/// already carries one local patch (the Metal shader exclusion, see README), and
/// every additional one is future merge cost plus another step in the recreation
/// instructions. Key handling is this app's own opinion anyway, so it belongs
/// here — swapping back to the stock upstream package stays a one-line change in
/// `Package.swift`.
///
/// The hook is `performKeyEquivalent(with:)`, not `keyDown(with:)`. Two reasons,
/// in order of force:
///
/// 1. `keyDown` **cannot** be overridden from here — SwiftTerm declares it
///    `public`, not `open`, so overriding it outside its module is a compile
///    error ("overriding non-open instance method outside of its defining
///    module"). `performKeyEquivalent` is `NSView`'s own method, which SwiftTerm
///    does not touch, so it is open to us.
/// 2. It is also the right phase. AppKit offers a ⌘-modified key event to the key
///    window's view hierarchy *before* the main menu, so claiming these four
///    combos here is exactly how a view is supposed to take a ⌘ chord — and
///    returning false leaves every other ⌘ key (⌘C, ⌘T, ⌘+, …) to the menu,
///    untouched.
final class UmberTerminalView: LocalProcessTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let bytes = MacLineEditing.controlBytes(
            keyCode: event.keyCode, modifiers: event.modifierFlags)
        else { return super.performKeyEquivalent(with: event) }

        // Every view in the key window is offered the equivalent, not just the
        // focused one. Today there is one pane per window so this is moot; once
        // splits exist it is what keeps ^U out of the pane you are not typing in.
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }

        // A program that turned on the kitty keyboard protocol (`CSI > 1 u`)
        // explicitly asked to receive modifiers itself, and SwiftTerm will encode
        // ⌘ for it as `super`. Rewriting ⌘⌫ to ^U in that state would silently
        // take a binding away from an editor that asked for the raw keystroke, so
        // hand it back to the normal path. Neovim and Helix enable it; afk's REPL
        // never does (plan §4.1: "kitty keyboard protocol — OPTIONAL, never
        // enabled"), so the translation stays live for the case this app exists
        // to host.
        guard getTerminal().keyboardEnhancementFlags.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }

        send(bytes)
        return true
    }
}
