//
//  UmberTerminalView.swift
//  SwiftTerm's view, plus this app's own key handling and link policy.
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
@MainActor
protocol UmberTerminalViewDelegate: AnyObject {
    /// The program in this terminal rang the bell (BEL / `\a`).
    func terminalViewDidRingBell(_ view: UmberTerminalView)
}

final class UmberTerminalView: LocalProcessTerminalView {
    // MARK: - Initialisation

    /// Overrides the super's designated initialiser so we can set Umber's link
    /// policy once, at construction time, rather than requiring `TerminalPane` to
    /// reach into the view's properties after the fact.
    ///
    /// `super.init(frame:)` calls `setup()` (`MacLocalTerminalView.swift:73`), which
    /// sets `terminalDelegate = self` and creates the `LocalProcess`. Both must exist
    /// before link detection can run — specifically, the `terminal` property (a
    /// `Terminal` instance) is created inside `TerminalView.init`, which `super` delegates
    /// to — so setting these properties after the `super` call is required, not optional.
    override init(frame: NSRect) {
        super.init(frame: frame)
        // Detect both OSC 8 payloads and plain-text http(s):// strings. `.implicit`
        // is the SwiftTerm default, but we set it explicitly so this is an assertion
        // rather than an accident: a future upstream change to the default should not
        // silently disable URL clicking. Source: `Mac/MacTerminalView.swift:889-890`.
        linkReporting = .implicit
        // Underline only on ⌘+hover; activate only when highlighted. This is the
        // standard macOS convention (Terminal.app, iTerm2, Ghostty all use it):
        // plain clicks stay free for text selection and mouse reporting, and ⌘ is
        // the intentional "I want the link" gesture. Source: `Mac/MacTerminalView.swift:893`.
        linkHighlightMode = .hoverWithModifier
    }

    /// Required companion to the frame-based initialiser above.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("UmberTerminalView: use init(frame:)") }

    // MARK: - Link activation

    /// Override the inherited `requestOpenLink` to route through `openSafeURL(_:)`,
    /// which filters to safe schemes and logs under `UMBER_DIAG`.
    ///
    /// `LocalProcessTerminalView` is its own `TerminalViewDelegate` and provides a
    /// default `requestOpenLink` that calls `openLink(_:)` → `NSWorkspace.shared.open`.
    /// We override rather than replace so the subclass controls every outbound URL
    /// without needing to reassign `terminalDelegate` (explicitly warned against in
    /// `MacLocalTerminalView.swift:59-64`). See `TerminalPane+Links.swift` for the
    /// full architecture and rationale.
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        openSafeURL(link)
    }

    /// Separate from `processDelegate` because the bell is *not* on
    /// `LocalProcessTerminalViewDelegate` — that protocol carries exactly four
    /// members (`MacLocalTerminalView.swift:14-43`: sizeChanged,
    /// setTerminalTitle, hostCurrentDirectoryUpdate, processTerminated) and the bell
    /// is on the lower-level `TerminalViewDelegate` instead
    /// (`Apple/TerminalViewDelegate.swift:64`). `LocalProcessTerminalView` *is* its own
    /// `TerminalViewDelegate` and does not forward the bell onward — it simply
    /// inherits the default that calls `NSSound.beep()`
    /// (`MacTerminalView.swift:3032-3035`). Reassigning `terminalDelegate` to reach it
    /// is explicitly warned against upstream ("you might inadvertently break the
    /// internal working", `MacLocalTerminalView.swift:59-64`), so the safe hook is to
    /// override the `open` `bell(source: Terminal)` on `TerminalView` itself
    /// (`MacTerminalView.swift:2869`) — which is what this subclass already exists to
    /// do for key handling.
    weak var bellDelegate: UmberTerminalViewDelegate?

    /// `bell(source: Terminal)` rather than `bell(source: TerminalView)`: the former is
    /// the `TerminalDelegate` method `TerminalView` declares `open`, and it is what
    /// `EscapeSequenceParser.swift:362` calls on receiving byte 0x07.
    ///
    /// `nonisolated` + `assumeIsolated` for the same reason as the accessibility
    /// overrides in `DocumentTabStrip`: SwiftTerm predates Swift concurrency, so the
    /// inherited signature is non-isolated. It is safe here because SwiftTerm's own
    /// pty reads are dispatched to `DispatchQueue.main` by default
    /// (`LocalProcess.swift:127`), so the parse that raises this is already on the
    /// main thread — the same runtime-check-over-compile-error trade `TerminalPane`
    /// documents on its `@preconcurrency` conformance.
    override nonisolated func bell(source: Terminal) {
        MainActor.assumeIsolated {
            // Reproduces SwiftTerm's own default rather than calling `super`: `Terminal`
            // is not `Sendable`, so `source` cannot cross into an isolated block, and
            // the default is exactly this one line — `bell(source: Terminal)` forwards
            // to `terminalDelegate?.bell(source: self)` (`MacTerminalView.swift:2870`),
            // which for a `LocalProcessTerminalView` is itself, inheriting
            // `NSSound.beep()` (`MacTerminalView.swift:3032-3035`).
            //
            // Kept because it is behaviour we already shipped: the strip's marker says
            // *which* tab wants you, but the sound is what makes you look at all.
            NSSound.beep()
            bellDelegate?.terminalViewDidRingBell(self)
        }
    }

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
