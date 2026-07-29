//
//  ShellHosting.swift
//  A document that hosts a live shell, and the one thing you are allowed to say to it.
//
//  Its own file, holding the protocol *and* `TerminalPane`'s conformance, for two
//  reasons. The first is the ceiling: `TerminalPane.swift` sits at 336/350 lines
//  (AFK.md, "Conventions"), so a concern that merely *plugs into* it belongs beside
//  it rather than inside it — the same call `FileViewerPane+Document.swift` makes for
//  the `SpaceDocument` conformance. The second is that a protocol with exactly one
//  member and one conformer is readable end to end in one screen only while both
//  halves sit together; `SpaceDocument.swift` is the precedent (it declares the
//  protocol and carries `TerminalPane`'s conformance in the same file).
//
//  Why this exists at all: the container needs to answer "which of these documents
//  can I write shell input to?" without naming a concrete pane type. That question
//  used to be answered by a cast to `TerminalPane`
//  (`SpaceViewController.focusedTerminalPane`, pre-change), which blocked a second
//  engine-backed document kind — the whole subject of
//  `.afk/plans/libghostty-swap-sequencing-2026-07-28.md` §2.
//
//  Why it is NOT answered by widening that cast to `SpaceDocument`: a shell-directed
//  action must land in a *shell*. `SpaceDocument` is satisfied by `FileViewerPane`,
//  so widening would let the file tree's "insert path" inject a filesystem path into
//  a text-editor buffer as if the user had typed it there — a silent data-corrupting
//  wrong target, not a cosmetic mistake. §2's "the one cast that must NOT widen to
//  `SpaceDocument`" and `next-sequencing-2026-07-28.md` §1's closing note both land
//  on a *narrower* protocol instead, which is this one.
//

import AppKit
import SwiftTerm

/// A `SpaceDocument` whose content is a live shell you can write input to.
///
/// Refines `SpaceDocument` rather than standing alone as an `AnyObject` protocol so
/// that "hosts a shell" cannot be claimed by something that is not a document in the
/// first place, and so the container can act on one without casting back: the
/// file-tree handler both writes to the host and brings its tab forward
/// (`documentDidBecomeActive()`, a `SpaceDocument` member), and a bare protocol would
/// have forced an `as? SpaceDocument` there — reintroducing a silent-failure branch
/// on the exact path this protocol exists to make total.
///
/// Deliberately one member. Everything else a terminal can do is either already on
/// `SpaceDocument` (paint, zoom, title, status) or is nobody else's business. The
/// value of the seam is inversely proportional to its width: a second conformer
/// (`GhosttyPane`, plan §4) has to satisfy exactly one method to inherit the
/// file-tree path-insert feature whole.
///
/// `FileViewerPane` must never conform. That is not enforceable by the compiler, so
/// it is stated here and in the header above: the conformance list *is* the
/// specification of "what counts as a shell".
@MainActor
protocol ShellHosting: SpaceDocument {
    /// Write `text` to the shell's input as if the user had typed it.
    ///
    /// Labelled `text:` and not SwiftTerm's own `txt:` on purpose. This member is the
    /// line the caller stops crossing: `SpaceViewController+Delegates.swift` used to
    /// call `pane.view.send(txt:)` — a SwiftTerm-concrete API reached through a
    /// concrete pane's concrete view — which meant the file-tree feature was coupled
    /// to the emulator, not to the idea of a shell (plan §2, "Note also that
    /// `pane.view.send(txt:)` is a **SwiftTerm-concrete** call"). A future
    /// `GhosttyPane` satisfies this with libghostty's own text write instead.
    ///
    /// No newline is implied — the caller decides whether the text is submitted or
    /// left on the prompt for editing. The one caller today deliberately leaves it
    /// unsubmitted, because inserting a path is for composing a command, not running
    /// one.
    func send(text: String)
}

// MARK: - TerminalPane

extension TerminalPane: ShellHosting {
    /// Forwards to SwiftTerm's `send(txt:)` (`vendor/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift:2259`),
    /// which writes the string to the pty as input — indistinguishable to the shell
    /// from typing, so it lands on the prompt and is subject to normal line editing.
    func send(text: String) {
        view.send(txt: text)
    }
}

// MARK: - Finding one in a Space

/// The container's shell-host queries, here rather than in `SpaceViewController.swift`
/// for the reason that file's own header gives for `DocumentAreaViewController`: this is
/// one whole concern ("which document can take shell input, and which one should"), and
/// the container was left with 12 lines of headroom under the 350-LOC ceiling by the
/// change that introduced them. Reading the fallback rule beside the protocol it selects
/// on is also simply better — the rule *is* the meaning of `ShellHosting`.
extension SpaceViewController {
    /// Every document that can accept shell input, in strip order.
    ///
    /// Typed by capability (`ShellHosting`) rather than by class (`TerminalPane`), which
    /// is the narrowest type that answers the only question asked of it. `TerminalPane`
    /// is still the sole conformer, so this is a pure retype with no behavioural delta —
    /// `compactMap` selects exactly the same documents in the same order.
    var shellHosts: [ShellHosting] { allDocuments.compactMap { $0 as? ShellHosting } }

    /// The shell a shell-directed action should land in.
    ///
    /// Falls back to the most recent shell in this Space rather than returning
    /// nil when the active document does *not* host one. Without the fallback,
    /// "insert this path into the shell" would do nothing whenever a file viewer
    /// happened to be the front tab — the failure would be invisible, and the
    /// feature would look broken exactly when the file tree is most in use.
    ///
    /// **Deliberately not widened to `SpaceDocument`.** This is the one cast in the
    /// container that must stay narrow: `FileViewerPane` satisfies `SpaceDocument`, so a
    /// `SpaceDocument?` here would let the file tree inject a filesystem path into a
    /// text-editor buffer as though the user had typed it — silent corruption of a
    /// document the user is editing, not a cosmetic miss. `ShellHosting` keeps the
    /// fallback total over shells only, which is exactly what the feature means
    /// (`libghostty-swap-sequencing-2026-07-28.md` §2; `next-sequencing-2026-07-28.md` §1).
    var focusedShellHost: ShellHosting? {
        (activeDocument as? ShellHosting) ?? shellHosts.last
    }
}
