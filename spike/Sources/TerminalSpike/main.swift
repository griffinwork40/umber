// Step 0 spike: can SwiftTerm host agent-afk's REPL correctly?
//
// Covers the gates that need human eyes:
//   G1  afk REPL paints, status line intact, no tearing
//   G3  Shift+Tab cycles the permission-mode ring   <-- KNOWN RISK
//   G4  Ctrl+B backgrounds a turn
//   G6  soak: multi-hour session, forced resizes, scrollback overflow
//
// G2 (reflow, SwiftTerm issue #494) and G5 (bracketed paste) are covered
// deterministically by the headless tests in Tests/SpikeGatesTests.
//
// Run:  swift run TerminalSpike
// Then: type `afk` and work through the checklist printed on launch.

import AppKit
import SwiftTerm

final class SpikeController: NSObject, LocalProcessTerminalViewDelegate {
    let terminalView: LocalProcessTerminalView
    private weak var window: NSWindow?

    init(frame: NSRect, window: NSWindow) {
        self.terminalView = LocalProcessTerminalView(frame: frame)
        self.window = window
        super.init()
        terminalView.processDelegate = self
        terminalView.autoresizingMask = [.width, .height]
    }

    func start() {
        // Login shell so the user's real PATH / rc files load and `afk` resolves.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(executable: shell, args: ["-l"])
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Resize is the #494 danger zone. Log every geometry change so a visual
        // artifact can be correlated with the exact transition that produced it.
        FileHandle.standardError.write("[spike] resize -> \(newCols)x\(newRows)\n".data(using: .utf8)!)
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window?.title = title.isEmpty ? "TerminalSpike" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // OSC 7 / shell integration. afk does not require it; noted, ignored.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        FileHandle.standardError.write("[spike] shell exited: \(exitCode.map(String.init) ?? "nil")\n".data(using: .utf8)!)
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - App bootstrap (no .xcodeproj, no bundle)

let checklist = """
=========================================================================
 TerminalSpike - Step 0 gates
 plan: ../.afk/plans/native-swift-terminal-afk-host.md
=========================================================================
 Type `afk` in the window, then verify:

 [G1] REPL paints correctly. Status line intact. No tearing or stray rows.
      (afk emits ZERO newlines - pure absolute CUP positioning.)

 [G3] Press Shift+Tab -> the permission-mode ring should cycle.
      ALREADY PASSED by static analysis; this is just live confirmation.
      AppKit routes Shift+Tab to insertBacktab(_:), and SwiftTerm's
      plain-xterm fallback switch sends EscapeSequences.cmdBackTab =
      [0x1b, 0x5b, 0x5a] = CSI Z, which is exactly what afk parses as
      {name:'tab', shift:true}. The kitty path is gated on
      `!terminal.keyboardEnhancementFlags.isEmpty` and afk never enables
      the protocol, so it is skipped entirely.

 [G4] Start a turn, press Ctrl+B -> the turn should background.

 [G6] Leave a long session running. Force several window resizes,
      especially NARROWING with scrollback present. Overflow the
      scrollback. Compare against Ghostty / Terminal.app side by side.
      Watch for duplicate or orphaned lines (SwiftTerm issue #494, OPEN).

 Geometry changes are logged to stderr as they happen.
=========================================================================

"""
FileHandle.standardError.write(checklist.data(using: .utf8)!)

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let frame = NSRect(x: 0, y: 0, width: 1000, height: 640)
let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "TerminalSpike"
window.center()

let controller = SpikeController(frame: frame, window: window)
window.contentView = controller.terminalView
window.makeFirstResponder(controller.terminalView)
window.makeKeyAndOrderFront(nil)

controller.start()
app.activate(ignoringOtherApps: true)
app.run()
