//
//  SpaceViewController+DirectoryFollow.swift
//  Keeping the sidebar pointed at wherever the focused shell actually is.
//
//  Its own file because it is one whole concern with a lifecycle of its own (a timer
//  that must start, stop, and not outlive its window), and because
//  `SpaceViewController.swift` is at 323 lines — inside `check-file-size.sh`'s warning
//  band already, with no room for a poller (AFK.md, "Conventions"). Only the single
//  stored property lives over there, because Swift extensions cannot add stored
//  properties; everything that property *does* is here.
//
//  WHY A POLLER AND NOT A CALLBACK. There is no event to subscribe to. OSC 7 is the
//  notification-shaped answer and SwiftTerm already parses it into
//  `hostCurrentDirectoryUpdate`, but it never fires under Umber: macOS's emitter is
//  `update_terminal_cwd` in `/etc/zshrc_Apple_Terminal`, sourced by `/etc/zshrc:74`
//  only when `TERM_PROGRAM == Apple_Terminal`, and SwiftTerm's
//  `Terminal.getEnvironmentVariables` (`Terminal.swift:5873`) sets no `TERM_PROGRAM`.
//  Full argument in `ShellDirectory.swift`'s header. Asking the kernel on a timer needs
//  no shell integration, works on any shell, and cannot be broken by a user's dotfiles
//  — the cost is a syscall pair every 750ms while a window is key, and nothing at all
//  when it is not.
//
//  DATA FLOWS ONE WAY, WHICH IS WHAT MAKES THIS SAFE. The UI never moves the tree
//  itself. "cd Here" and every other navigate affordance write a `cd` to the shell
//  (`SpaceViewController+Delegates.swift`), and the tree moves only here, only after
//  the shell has actually moved. So the shell is the single source of truth, the UI
//  cannot disagree with it, and there is no second writer to race. The loop closes
//  rather than spinning because `FileTreeViewController.setRoot(_:)` early-returns on
//  an unchanged path and `ShellDirectory` normalises both sides to one spelling.
//

import AppKit

/// The cwd poller for one Space.
///
/// A class rather than a couple of methods on the controller so the timer, the last-seen
/// value, and the start/stop rules sit in one object with one owner — a bare `Timer` on
/// the controller would leave "is it running?" implicit in whether a property is nil.
@MainActor
final class DirectoryFollow {
    /// Weak, and load-bearing. `Timer` retains its target/closure until invalidated, and
    /// a Space's window can close while its timer is mid-flight; a strong reference here
    /// would keep the whole view controller — and its panes, and their ptys — alive after
    /// the window was gone. Weak plus the nil-check in `tick()` means a closed Space
    /// simply stops being polled.
    private weak var space: SpaceViewController?

    private var timer: Timer?

    /// The last directory actually pushed to the tree, used to skip the common case
    /// (nothing changed) before touching the view at all.
    ///
    /// `setRoot(_:)` already early-returns on an unchanged root, so this is not what
    /// makes the feature correct — it is what keeps a 750ms timer from calling into
    /// AppKit 80 times a minute to be told "no". Correctness lives in `setRoot`; this is
    /// the cheap pre-filter in front of it.
    private var lastPushed: URL?

    init(space: SpaceViewController) {
        self.space = space
    }

    /// Begin polling. Idempotent — calling it on an already-running follower is a no-op
    /// rather than a second timer, because `windowDidBecomeKey` can fire more than once
    /// without an intervening resign (a sheet dismissing, a tab switch within a key
    /// window) and two timers would double the syscall rate for nothing.
    func start() {
        guard timer == nil else { return }

        // 0.75s: fast enough that the sidebar feels like it is following you rather than
        // catching up, slow enough to be invisible in Activity Monitor. The work per tick
        // is `tcgetpgrp` + `proc_pidinfo` on one process — microseconds — so the interval
        // is chosen for perceived latency, not for load.
        let interval: TimeInterval = 0.75
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            // `Timer`'s block is `@Sendable` and this type is `@MainActor`, but a run-loop
            // timer scheduled from the main thread always fires on it, so the isolation is
            // real and `assumeIsolated` states that rather than hopping through a `Task`
            // (which would reorder ticks relative to user input for no benefit).
            MainActor.assumeIsolated { self.tick() }
        }

        // Poll once immediately instead of waiting out the first interval: a Space that
        // has just become key is exactly when the sidebar is most likely to be stale, and
        // a visible 750ms lag on window activation reads as lag, not as polling.
        tick()
    }

    /// Stop polling and release the timer.
    ///
    /// Called when the window resigns key, not when it closes: a background Space cannot
    /// be looked at, so following it is pure cost. This is also why the poller is not a
    /// per-pane concern — N terminals in a Space share one timer, and only the focused
    /// one is ever asked.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Poll right now, outside the timer's rhythm.
    ///
    /// Exists for the moments when waiting up to 750ms would be visibly wrong: switching
    /// document tabs (⌘1–⌘9, ⌘⌥←/→) changes which shell is focused, so the sidebar must
    /// re-root to the new tab's directory in the same frame the tab came forward, not on
    /// the next tick.
    func pollNow() {
        tick()
    }

    private func tick() {
        guard let space else { return stop() }

        // `focusedShellHost` — the active document if it hosts a shell, otherwise the most
        // recent shell in the Space (`ShellHosting.swift`). Deliberately reusing that one
        // rule rather than adding a second: with a file viewer in front, the sidebar keeps
        // following the shell you last used, which is the same answer "insert path" and
        // "cd Here" already give, so all three features agree about which shell is "the"
        // shell.
        guard let directory = space.focusedShellHost?.currentDirectory else { return }

        // nil `currentDirectory` above is a deliberate no-op, not a reset: a pane whose
        // shell is still starting, or has just exited, answers nil, and blanking the
        // sidebar in either case would be worse than leaving it one `exit` stale.
        guard directory != lastPushed else { return }
        lastPushed = directory
        space.followDirectory(directory)
    }
}

// MARK: - The Space's side

extension SpaceViewController {
    /// Start following, creating the follower on first use.
    ///
    /// Lazily created rather than built in `init` because a Space that is never made key
    /// never needs one, and because `init` runs before the controller is in a window.
    func startDirectoryFollow() {
        if directoryFollow == nil { directoryFollow = DirectoryFollow(space: self) }
        directoryFollow?.start()
    }

    /// Stop following. Safe to call when never started.
    func stopDirectoryFollow() {
        directoryFollow?.stop()
    }

    /// Called when the Space's window stops being key — the mirror of
    /// `windowDidBecomeKey()`, which lives in `SpaceViewController.swift` because it drives
    /// several concerns (tree refresh, document staleness, chrome). This one lives *here*
    /// instead, even though its twin does not, because polling is the only thing that
    /// happens on resign: it is a cwd-follow method wearing a window-lifecycle name, and
    /// the container is 2 lines from `check-file-size.sh`'s ceiling with nothing to spare
    /// for a concern that is not its own. Called from
    /// `SpaceWindowController.windowDidResignKey(_:)`.
    func windowDidResignKey() {
        stopDirectoryFollow()
    }

    /// Re-poll immediately — see `DirectoryFollow.pollNow()` for why the timer's rhythm
    /// is not good enough at a tab switch.
    func directoryFollowPollNow() {
        directoryFollow?.pollNow()
    }

    /// Point the sidebar at `directory`.
    ///
    /// The only place in the app that moves the tree, and it is reached only from a
    /// shell's reported cwd — never directly from a click. That is the one-way flow the
    /// file header describes; routing a UI gesture through here instead of through the
    /// shell would create a second writer and, with it, the feedback loop this design
    /// does not have.
    ///
    /// The Space's *identity* deliberately does not move with it: `SpaceWindowController.root`,
    /// the `UmberSpace:<path>` frame-autosave key, `OpenSpaceRoots`, `LastSpaceRoot` and
    /// ⌘O's dedupe all keep using the root the Space was created with. So a `cd /tmp`
    /// moves the sidebar and nothing else — it cannot rename the Space, relocate its
    /// remembered window frame, or change what relaunch restores, which is what keeps
    /// `SpaceRestore.swift`'s written contract ("its cwd after you `cd`... died with the
    /// last launch") literally true. Net persisted-state delta of this whole feature: zero.
    func followDirectory(_ directory: URL) {
        fileTree.setRoot(directory)
    }
}
