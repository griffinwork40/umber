//
//  SpaceViewController+DocumentConstruction.swift
//  How a Space builds a terminal document — the one place in the app that names both engines.
//
//  Its own file for two reasons, one structural and one arithmetic.
//
//  Structural: `add(document:beforeActivating:)` in `SpaceViewController.swift` is deliberately
//  polymorphic — it installs any `SpaceDocument` and knows nothing about kinds. Deciding WHICH
//  kind to build is a different concern, and it is the concern that has to name `TerminalPane`
//  and `GhosttyPane` concretely. Keeping it here means the container proper still contains no
//  engine knowledge at all, so `grep -l 'GhosttyPane\|TerminalPane' Sources/Umber/Space*` names
//  exactly this file and nothing else. Phase 6 deletes the loser by editing one switch.
//
//  Arithmetic: `SpaceViewController.swift` was at 346 lines against a hard 350-line ceiling
//  (`Scripts/check-file-size.sh`). An engine branch and a teardown call could not both land
//  there. The convention when a file reaches the ceiling is to find its seam and move one whole
//  concern out rather than shave comments — this is that seam, and moving `addTerminalDocument`
//  here also bought the room for `closeDocument`'s teardown call.
//

import AppKit

extension SpaceViewController {
    /// Add a terminal document rooted at `workingDirectory`, defaulting to the Space's own
    /// `root`, backed by whichever engine the config names.
    ///
    /// The root default is the point. A Space *is* a project root (plan §12.4 item 1) and every
    /// terminal in it inherited `$HOME` instead, because this function created the pane without
    /// ever mentioning `root` — so ⌘T in a Space opened on a project landed outside that project
    /// and the first thing you typed was a `cd`. The root was already right here, one property
    /// away, which is exactly why it went unnoticed.
    ///
    /// `workingDirectory` is an override rather than a replacement so the tree's "New Terminal
    /// Here" can pass a subdirectory (`fileTree(_:didRequestNewTerminalAt:)`) without every other
    /// caller — first launch, ⌘T, the strip's `+` — having to restate the root it already implies.
    ///
    /// Returns `SpaceDocument`, not a concrete pane. It returned `TerminalPane` until the second
    /// engine arrived, which would now be a lie in half the cases; every caller already discarded
    /// the value (`AppDelegate.swift`, `SpaceWindowController.swift`,
    /// `SpaceViewController+Delegates.swift` × 2), so widening it costs nothing and removes the
    /// last concrete-type assumption from the ⌘T path.
    @discardableResult
    func addTerminalDocument(start: Bool = true, workingDirectory: URL? = nil) -> SpaceDocument {
        let directory = workingDirectory ?? root

        // Read from `config` at construction, deliberately once. `AppConfig.engine`'s own doc
        // comment carries the argument: a live pane cannot change engine, so this is the only
        // moment the choice is meaningful. A ⌘R after editing `engine` therefore affects the
        // next ⌘T rather than the tab in front of you — which also means both engines can be
        // open in one window at the same time, and that is the point rather than a side effect.
        // Evaluating a replacement emulator means running it beside the incumbent on the same
        // work, not rebuilding to switch.
        let pane: SpaceDocument
        switch config.engine {
        case .swiftTerm:
            pane = TerminalPane(
                config: config, frame: documentArea.container.bounds, workingDirectory: directory)
        case .ghostty:
            pane = GhosttyPane(
                config: config, frame: documentArea.container.bounds, workingDirectory: directory)
        }

        // `beforeActivating`, not after, and this ordering is load-bearing rather than stylistic.
        // `start()` hands the pty its initial `winsize` from the view's *current* geometry
        // (SwiftTerm: `MacLocalTerminalView.swift:204-209` builds it from `terminal.rows`/`cols`),
        // while activation is what makes the tab strip appear at the second document — costing the
        // container ~30pt, i.e. about two rows (`DocumentAreaViewController.viewDidLayout`).
        // Starting after activation would therefore hand a *different* initial row count to every
        // terminal but the first and add a SIGWINCH before the first prompt. Both are reflow
        // inputs, and reflow is the one area of this app with a known upstream defect
        // (SwiftTerm #494, patched locally as `0002`), so the original sequence — append, start,
        // select — is reproduced exactly for both engines.
        //
        // `start()` is reached through `ShellStarting` rather than a concrete cast so this stays
        // one code path: both panes spell it `start()`, and `GhosttyPane` documents that it is
        // named to match `TerminalPane` precisely so the container need not remember which is
        // which.
        add(document: pane, beforeActivating: { if start { (pane as? any ShellStarting)?.start() } })
        return pane
    }
}

/// A document that spawns a process, and must be told when its view geometry is final.
///
/// Two members would be one too many: the container's whole contract with a process-backed
/// document is "you may spawn now", and `beforeActivating` already expresses *when*. This exists
/// only so `addTerminalDocument` can call `start()` without a `switch` over concrete types in a
/// function whose entire job is to have made that switch once already.
///
/// Not folded into `SpaceDocument`, because `FileViewerPane` has no process and a protocol member
/// it must stub is how `documentWindowDidBecomeKey` nearly became a no-op everyone ignored. Not
/// folded into `ShellHosting` either: hosting a shell is about *reaching* one that already runs
/// (`send(text:)`, `currentDirectory`), and a pane is a valid shell host before and after the
/// moment it starts.
@MainActor
protocol ShellStarting: AnyObject {
    func start()
}

extension TerminalPane: ShellStarting {}
extension GhosttyPane: ShellStarting {}
