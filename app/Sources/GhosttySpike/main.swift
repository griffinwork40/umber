//
//  main.swift
//  SPIKE ONLY — branch afk/libghostty-spike. Not part of Umber.
//
//  Answers the three Step 1 questions from
//  ../.afk/plans/emulator-foundation-probe-and-vendor-integrity.md §5 / §6.1:
//
//    Q1  Does a real login shell render in an AppKit NSView via libghostty?
//    Q2  Can `performBindingAction` start a search? (§6.1 found the C ABI has NO
//        callable search entry point — only outbound actions — so this string
//        interface is the only candidate trigger. If it fails, search must be
//        rebuilt on ghostty_surface_read_text with no incremental highlighting,
//        which is the one outcome that makes the A/D trade close.)
//    Q3  What does owning the PTY cost? — ANSWERED BEFORE WRITING THIS FILE:
//        nothing. `TerminalSessionBackend` has exactly two cases, `.exec` and
//        `.inMemory`, and `.exec` is the DEFAULT: libghostty spawns the child
//        itself and honours `workingDirectory` + `envVars`. The earlier claim
//        that Umber would have to own forkpty was wrong — it came from the
//        README's examples, which use `.inMemory` because the sample app is
//        sandboxed.
//
//  Deliberately does NOT conform to SpaceDocument. Wrapping comes only after
//  this prints a working shell.
//

import AppKit
import GhosttyTerminal

// MARK: - Diagnostics

/// Everything the spike learns, printed as `[spike]` lines. The point is a
/// transcript that answers the three questions without a human watching pixels.
@MainActor
final class SpikeLog {
    /// stderr, not stdout. `print` to a redirected stdout is block-buffered by
    /// libc, so a killed spike loses its whole transcript — which is exactly what
    /// happened on the first run. stderr is unbuffered, and it matches the
    /// UMBER_DIAG convention the real app already uses.
    static func say(_ message: String) {
        FileHandle.standardError.write(Data("[spike] \(message)\n".utf8))
    }
}

// MARK: - Terminal host

@MainActor
final class SpikeViewController: NSViewController {
    private lazy var terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))

    /// `.none` config source: no ~/.config/ghostty/config is read, so the spike
    /// measures the library's defaults rather than whatever Ghostty config the
    /// machine happens to carry.
    private lazy var controller = TerminalController(configSource: .none)

    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 560)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        terminal.delegate = self
        // .exec is the default; naming it makes the finding explicit in code.
        terminal.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: FileManager.default.currentDirectoryPath)
        terminal.controller = controller
        terminal.autoresizingMask = [.width, .height]
        view.addSubview(terminal)
        SpikeLog.say("Q1: surface configured, backend=.exec (libghostty spawns the shell)")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        terminal.fitToSize()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(terminal)
        // Give the shell a moment to spawn and paint a prompt before probing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.probeBindingActions()
        }
    }

    /// Q2. `performBindingAction` parses a Ghostty keybind action string and
    /// returns whether it was accepted. Ghostty's action vocabulary is not in the
    /// C header, so the candidates are probed empirically: controls first (known
    /// real actions), then every plausible spelling of "search".
    private func probeBindingActions() {
        let controls = ["scroll_to_top", "copy_to_clipboard", "jump_to_prompt:-1"]
        let searchCandidates = [
            "toggle_search", "search", "open_search", "show_search", "find",
            "toggle_find", "search_forward", "start_search",
        ]

        SpikeLog.say("Q2: probing binding actions — controls first")
        for action in controls {
            SpikeLog.say("  control  \(action.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(terminal.performBindingAction(action))")
        }
        SpikeLog.say("Q2: search candidates")
        var accepted: [String] = []
        for action in searchCandidates {
            let ok = terminal.performBindingAction(action)
            if ok { accepted.append(action) }
            SpikeLog.say("  search   \(action.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(ok)")
        }
        SpikeLog.say("Q2 RESULT: accepted search actions = \(accepted.isEmpty ? "NONE" : accepted.joined(separator: ", "))")

        // Prompt navigation is documented and should work; it is the OSC 133
        // consumer, so it doubles as a shell-integration check.
        SpikeLog.say("Q4: jumpToPrompt(by:-1) -> \(terminal.jumpToPrompt(by: -1)), scrollToRow(0) -> \(terminal.scrollToRow(0))")
    }
}

// MARK: - Delegates
//
// Conforming to the shell-integration delegates is itself a finding: these are
// the OSC 7 / OSC 133 / hyperlink signals Umber currently has as empty stubs or
// as unbuilt items on its "Not Built Yet" list.

extension SpikeViewController:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceHoverLinkDelegate,
    TerminalSurfaceCloseDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        view.window?.title = "GhosttySpike — \(title)"
        SpikeLog.say("title -> \(title)")
    }

    func terminalDidChangeWorkingDirectory(_ path: String) {
        SpikeLog.say("OSC 7 pwd -> \(path)")
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        let ms = Double(durationNanos) / 1_000_000
        SpikeLog.say("OSC 133 command finished: exit=\(exitCode.map(String.init) ?? "nil") in \(String(format: "%.1f", ms))ms")
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        SpikeLog.say("hover link -> \(url ?? "nil")")
    }

    func terminalDidClose(processAlive: Bool) {
        SpikeLog.say("shell closed (processAlive=\(processAlive)) — exiting")
        NSApp.terminate(nil)
    }
}

// MARK: - Bootstrap
//
// Same manual NSApplication shape as Umber's own main.swift — no @main, explicit
// .regular activation policy — so the spike behaves like the real app.

@MainActor
final class SpikeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        let controller = SpikeViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "GhosttySpike"
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        SpikeLog.say("launched — libghostty via GhosttyKit, AppKit NSView host")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = SpikeAppDelegate()
app.delegate = delegate
app.run()
