//
//  GhosttyPane.swift
//  One terminal: a libghostty surface bound to one shell.
//
//  The second engine-backed `SpaceDocument`, landing BESIDE `TerminalPane` rather than
//  replacing it. That is the whole approach of
//  `.afk/plans/emulator-foundation-probe-and-vendor-integrity.md` §5 — "don't decide, probe
//  — the seam makes the bet reversible": both panes conform to the same protocol, both are
//  live at once, and exactly one dependency gets deleted at Step 2 after the operator has
//  actually lived in the winner. Nothing here is allowed to modify `TerminalPane`.
//
//  WHAT THIS ENGINE GIVES FOR FREE that SwiftTerm did not, wired in
//  `GhosttyPane+Document.swift`: OSC 7 working directory, OSC 133 command boundaries with exit
//  code and duration, hover links, and a first-class bell delegate.
//  `TerminalPane.hostCurrentDirectoryUpdate` has been a wired-but-empty callback for the life
//  of the project because a stock zsh emits no OSC 7 under Umber (`ShellHosting.swift:97`
//  explains why); here it arrives without shell cooperation.
//
//  OSC 7 IS OBSERVED, and the story of how it was nearly recorded as unconfirmed is worth
//  keeping. `check-ghostty-pane.sh` case 5b now runs a real shell in a real pane and asserts
//  both that OSC 7 arrives and that the path it names is THIS pane's root. It reports one every
//  run. PR #20 shipped a disclaimer saying the opposite — "wired but the gate reports `pwd=-`,
//  inherited from the spike, not re-confirmed" — and that disclaimer was an artifact of the
//  gate, not a fact about libghostty: case 5 pumped the run loop `until title || pwd`, `pump`
//  returns as soon as its condition holds, and a zsh sends the title first, so the harness
//  stopped a beat before the OSC 7 sequence landed. Two signals folded into one `||` produced a
//  confident false negative that was then written down as a correction.
//
//  WHAT PHASE 4 MUST DO BEFORE IT CONSTRUCTS ONE OF THESE. Nothing in the app builds a
//  `GhosttyPane` yet, which is what makes this latent rather than live:
//
//    TEARDOWN. Nothing frees the surface. There is no `deinit` here, `SpaceDocument` has no
//    close hook, `SpaceViewController.closeDocument(at:)` only drops the document and removes
//    its view, and the dependency deliberately removed its own safety net
//    (`Surface/TerminalSurface.swift:405-410`: "Surface should be freed explicitly via free()
//    before deinit. The deinit safety net is intentionally removed"). The only `surface?.free()`
//    is inside `TerminalSurfaceCoordinator.tearDownSurface`, reachable by nilling
//    `view.controller`. So a closed Ghostty tab leaks the surface AND its child process. The fix
//    is a teardown verb on the document seam called from `closeDocument`, and it belongs in the
//    commit that first constructs a pane — added now it would be a function with no caller,
//    which is the failure class the `.custom` accounting below rails against.
//
//  THREE PARITY GAPS, NAMED RATHER THAN PAPERED OVER. Each is a real config field that this
//  engine cannot honour through its typed Swift API, and each is attempted through the
//  `.custom(key:value:)` escape hatch and then REPORTED under `UMBER_DIAG` — never silently
//  dropped, because a config line that parses and does nothing is the exact failure class
//  this repo has been bitten by twice (patch 0001's excluded shader, and the `renderer`
//  string that named a renderer it never reached).
//
//    1. `shell` — `TerminalSurfaceOptions` has backend/fontSize/workingDirectory/envVars/
//       context and NO command field (`Surface/TerminalSurfaceOptions.swift:10-34`). The raw
//       C struct does have `command` (`ghostty.h:489-494`) but `createSurface` never sets it
//       (`TerminalController+Surface.swift:15-145`), so `.exec` runs whatever libghostty
//       resolves internally. Attempted as `command`.
//    2. `scrollback` — no scrollback/history symbol exists anywhere in the Swift sources or
//       `ghostty.h`. Attempted as `scrollback-limit`, WHICH IS A DIFFERENT UNIT: ghostty
//       counts bytes, Umber counts lines. The conversion below is an explicit assumption,
//       not a measurement.
//    3. `renderer` — inapplicable rather than missing. libghostty is GPU-only, so there is no
//       Core Text path to select and `Renderer` has no meaning here.
//
//  None of the three `.custom` keys has been verified to exist in ghostty's config schema —
//  the schema lives in the binary. They are attempts with a diagnostic, and Phase 5 is where
//  they get confirmed or removed.
//

import AppKit
import GhosttyTerminal

/// A single terminal pane backed by libghostty.
@MainActor
final class GhosttyPane: NSObject {
    let view: GhosttyTerminalView

    /// The config owner. `TerminalController` is `final` (`Controller/TerminalController.swift:25`)
    /// so it cannot be subclassed; it is held rather than inherited, and it is the only route
    /// to a live appearance change — `setTerminalConfiguration` calls
    /// `ghostty_surface_update_config` on the existing surface WITHOUT recreating it
    /// (`TerminalController+Config.swift:55-78`).
    ///
    /// One controller per pane, deliberately, even though it is heavier than sharing one.
    /// A shared controller would push every ⌘+ zoom into every open pane at once, because a
    /// config change fans out to every surface the controller retains — and Umber's zoom is
    /// explicitly per-document with the container doing the fan-out
    /// (`AppDelegate.zoomAllDocuments`). Sharing would move that decision into the dependency
    /// and make a single-pane zoom impossible to express.
    // Internal for the same file-scope reason as `config`/`fontSize` below: the only live
    // appearance path, `pushConfiguration()`, lives in `GhosttyPane+Appearance.swift`.
    let controller: TerminalController

    private(set) var currentTitle: String = ""

    /// Set by `SpaceViewController.add(document:)` through `SpaceDocumentReporting`.
    weak var documentDelegate: SpaceDocumentDelegate?

    /// The most recent OSC 7 working directory, or nil before the shell reports one.
    ///
    /// Stored because `ShellHosting.currentDirectory` is a synchronous read and OSC 7 is a
    /// push. This is the engine's real advantage over the SwiftTerm pane, which has to ask
    /// the KERNEL for the same fact (`ShellDirectory.swift`, and its header argues at length
    /// why that was necessary) — here the shell simply says so.
    private(set) var reportedDirectory: String?

    /// What the tab strip should be saying about this pane. Same stored-with-didSet shape as
    /// `TerminalPane.status` so the two panes are comparable at a glance.
    private(set) var status: DocumentStatus = .idle {
        didSet {
            guard status != oldValue else { return }
            documentDelegate?.documentDidChangeStatus(self)
        }
    }

    // Internal rather than `private` because the appearance concern lives in
    // `GhosttyPane+Appearance.swift` and Swift's `private` is FILE-scoped. Widened to the
    // module, not to the world: `GhosttyPane` itself is internal, so this is still
    // unreachable from anywhere but Umber.
    var config: AppConfig
    var fontSize: CGFloat
    private let workingDirectory: URL
    /// Guards `start()`. See its doc comment for why a second call would cost a session.
    private var didStart = false

    /// The directory this pane was created for, before the shell has reported one.
    /// Read by `ShellHosting.currentDirectory` so a brand-new tab answers with the truth
    /// rather than nil; `workingDirectory` itself stays private so nothing can mistake the
    /// launch root for the live cwd.
    var launchDirectory: URL { workingDirectory }

    /// Same contract as `TerminalPane.init` — `workingDirectory` is neither defaulted nor
    /// optional, so a call site with no opinion fails to compile rather than silently
    /// inheriting the app's cwd.
    init(config: AppConfig, frame: NSRect, workingDirectory: URL) {
        self.config = config
        self.workingDirectory = workingDirectory
        self.fontSize = FontZoom.override ?? config.font.pointSize
        self.view = GhosttyTerminalView(frame: frame)
        // The controller is built with the resolved appearance already in it rather than
        // constructed bare and reconfigured: `init` renders the config, validates it through
        // ghostty, and creates the app in one pass (`TerminalController.swift:138-157`), so
        // handing it the real values here avoids a visible restyle on the first frame.
        self.controller = TerminalController(
            configSource: .none,
            terminalConfiguration: Self.configuration(for: config, fontSize: self.fontSize))
        super.init()
        view.delegate = self
        // NOTE: `view.controller` is deliberately NOT set here — see `start()`. Assigning it is
        // what spawns the shell, and doing that in `init` starts one in the wrong directory.
        view.autoresizingMask = [.width, .height]
    }

    /// Attach the surface and let libghostty spawn the shell.
    ///
    /// Named `start()` to match `TerminalPane` exactly, because the container calls it
    /// through neither protocol — `SpaceViewController.addTerminalDocument` calls it on the
    /// concrete type — and a differently-named member would be a second thing to remember.
    ///
    /// Unlike the SwiftTerm pane there is no `startProcess(executable:args:)` here: the
    /// `.exec` backend owns the spawn and honours `workingDirectory` itself, which is the
    /// finding that dissolved probe question Q3 (§6.2, "Cost is zero, not a day"). It also
    /// retires the `Pty.swift:103` silent-`chdir` risk documented in AFK.md's Known Risks,
    /// because Umber is no longer the thing calling `chdir`.
    /// THE ORDER OF THESE TWO ASSIGNMENTS IS LOAD-BEARING, and getting it wrong fails silently
    /// in both directions. `TerminalSurfaceCoordinator` rebuilds the surface from the `didSet`
    /// of BOTH `controller` and `configuration`, and `rebuildIfReady` opens with
    /// `guard let controller else { return }` (`Surface/TerminalSurfaceCoordinator.swift:97-99`).
    /// So:
    ///
    ///   * controller first  ⇒ the rebuild fires immediately against the DEFAULT
    ///     `TerminalSurfaceOptions()`, whose backend is already `.exec` and whose
    ///     `workingDirectory` is nil — a real shell, in the app's cwd, before anyone asked for
    ///     one. Assigning the real configuration then tears it down and spawns a second.
    ///   * configuration first ⇒ the rebuild early-returns for want of a controller, and the
    ///     controller assignment that follows is the single event that creates the surface,
    ///     with the correct root already in place.
    ///
    /// This is not theoretical. The pane originally set the controller in `init`, and
    /// `check-ghostty-pane.sh`'s control case caught it: a pane that was never started reported
    /// a title and an OSC 7 pwd for the app's own directory. The spike had this order right
    /// (`afk/libghostty-spike` main.swift:61-64) and this diverged from it.
    ///
    /// IDEMPOTENT, and not as defensive bookkeeping. `fontSize` is part of
    /// `TerminalSurfaceOptions` below and therefore part of its `isEquivalent(to:)`
    /// (`Surface/TerminalSurfaceOptions.swift:36-42`), so a second `start()` after ANY zoom
    /// builds a non-equivalent configuration, trips `configuration`'s didSet, and respawns the
    /// shell — losing the running session. `controller`'s own didSet guards on `!==` and would
    /// not catch it, so the guard has to be here.
    func start() {
        guard !didStart else { return }
        didStart = true
        view.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: Float(fontSize),
            workingDirectory: resolvedWorkingDirectory(),
            envVars: [:])
        view.controller = controller
    }

    /// The cwd to hand the surface, or nil to let it inherit.
    ///
    /// Validated up front for the same reason `TerminalPane.resolvedWorkingDirectory()` is,
    /// and reusing the same `FileManager.isUsableSpaceRoot` predicate rather than inlining a
    /// second copy — `Defaults.swift:96` warns that two copies of a check-don't-trust rule is
    /// two places for it to drift, and this would have been the fourth caller.
    ///
    /// Worth stating what is DIFFERENT: SwiftTerm discarded `chdir`'s result in the forked
    /// child, so an unusable root failed silently and this check was the only guard. Here the
    /// spawn belongs to libghostty and its failure behaviour is not visible from the Swift
    /// source, so this check is now a *courtesy* that produces a diagnostic rather than the
    /// last line of defence. It is kept because the diagnostic is the point.
    private func resolvedWorkingDirectory() -> String? {
        let path = workingDirectory.standardizedFileURL.path
        guard FileManager.default.isUsableSpaceRoot(atPath: path) else {
            diag("pane root not a usable directory, shell will inherit app cwd: \(path)")
            return nil
        }
        return path
    }

    // MARK: - State recorded by the surface delegates
    //
    // The five delegates live in `GhosttyPane+Document.swift` and Swift's `private(set)` is
    // FILE-scoped, so they cannot assign these directly. Narrow mutators rather than widening
    // the setters to `internal(set)`: an intent-revealing name is where the "why" for each
    // transition lives, and it keeps the writable surface to exactly four verbs instead of
    // every property in the pane.

    /// OSC 0/2 arrived. Records it and tells the container, which repaints the tab and — when
    /// this is the active document — the window subtitle.
    func recordTitle(_ title: String) {
        currentTitle = title
        documentDelegate?.document(self, didChangeTitle: title)
    }

    /// OSC 7 arrived. Recorded only; moving the file tree is deliberately not done from here
    /// (see the delegate's own note on why the tree must keep one master).
    func recordDirectory(_ path: String) {
        reportedDirectory = path
    }

    /// The user is now looking at this tab, so whatever it wanted to say has landed.
    func resetStatus() {
        status = .idle
    }

    /// The program rang the bell and the user is not looking at this tab.
    func raiseAttention() {
        status = .attention
    }

    /// A command finished in a tab the user is not watching. `CommandOutcome` decided what it
    /// means (and, importantly, decided `.ignore` for most commands); this only applies it.
    ///
    /// The switch is exhaustive with no `default`, so adding a `CommandOutcome` case becomes a
    /// build error here rather than a silently unhandled outcome — the same reason the config
    /// enums derive their user-facing strings from `allCases`.
    func recordCommandOutcome(_ outcome: CommandOutcome) {
        switch outcome {
        case .failed: status = .failed
        case .succeeded: status = .succeeded
        case .ignore: break
        }
    }

    // MARK: - Diagnostics

    /// `UMBER_DIAG=1` only, stderr, same `[diag]` prefix the rest of the app uses. This is the
    /// app's whole observability story — there is no test target — and for this pane it is
    /// load-bearing rather than decorative, because the three `.custom` keys above are
    /// unverified guesses and this is the only place that says what was actually sent.
    /// Internal rather than `private` because `private` is FILE-scoped in Swift and the five
    /// surface delegates live in `GhosttyPane+Document.swift`. They are the callbacks whose
    /// arrival is the probe's actual finding, so they are the ones that most need to be able
    /// to say so.
    func diag(_ message: String) {
        guard ProcessInfo.processInfo.environment["UMBER_DIAG"] != nil else { return }
        FileHandle.standardError.write(Data("[diag] ghostty: \(message)\n".utf8))
    }

}
