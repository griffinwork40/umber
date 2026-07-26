//
//  TerminalPane.swift
//  One terminal: a SwiftTerm view bound to one login shell.
//

import AppKit
import SwiftTerm

@MainActor
protocol TerminalPaneDelegate: AnyObject {
    /// The shell exited; the owning window/tab should close.
    func paneDidTerminate(_ pane: TerminalPane)
    /// The shell reported a new title (OSC 0/2).
    func pane(_ pane: TerminalPane, didChangeTitle title: String)
}

/// A single terminal pane.
///
/// Owns the SwiftTerm view and the shell process, and applies config/theme.
/// Deliberately does NOT know about tabs or windows — that is the window
/// controller's job — so panes stay reusable for splits later.
/// `@preconcurrency` on the SwiftTerm conformance: SwiftTerm predates Swift
/// concurrency annotations, so its delegate protocol is non-isolated even though
/// it is an AppKit view that only ever calls back on the main thread. Without it,
/// Swift 6 rejects a `@MainActor` conformer outright. This keeps the isolation
/// guarantee as a runtime check instead of a compile error, which is the
/// sanctioned migration path for an un-annotated dependency.
@MainActor
final class TerminalPane: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    private(set) var currentTitle: String = ""
    weak var delegate: TerminalPaneDelegate?

    private var config: AppConfig
    private var fontSize: CGFloat

    init(config: AppConfig, frame: NSRect) {
        self.config = config
        self.fontSize = config.font.pointSize
        // LocalProcessTerminalView only exposes init(frame:) — the font-taking
        // initialiser belongs to TerminalView and is not inherited here, so the
        // font is applied via the property in apply(config:) below.
        self.view = LocalProcessTerminalView(frame: frame)
        super.init()
        view.processDelegate = self
        view.autoresizingMask = [.width, .height]
        apply(config: config)
    }

    /// Start the user's login shell. `-l` so their real PATH and rc files load —
    /// without it, tools installed via Homebrew or a node version manager are
    /// missing and the terminal is useless for actual work.
    func start() {
        view.startProcess(executable: config.shell, args: ["-l"])
        applyCursorStyle(config.cursorStyle)
    }

    // MARK: - Appearance

    func apply(config: AppConfig) {
        self.config = config
        view.nativeBackgroundColor = config.theme.background
        view.nativeForegroundColor = config.theme.foreground
        view.caretColor = config.theme.cursor
        // installColors is a no-op unless the array is exactly 16 long; Config
        // guarantees that invariant before we get here.
        view.installColors(config.theme.ansi.map { $0.asSwiftTermColor })
        view.optionAsMetaKey = config.optionAsMeta
        view.changeScrollback(config.scrollback == 0 ? nil : config.scrollback)
        setFontSize(fontSize)
    }

    /// Cursor style is not settable through a public initialiser, so drive it the
    /// way any program would: the DECSCUSR sequence.
    private func applyCursorStyle(_ style: CursorStyle) {
        let code: Int
        switch style {
        case .blinkBlock: code = 1
        case .steadyBlock: code = 2
        case .blinkUnderline: code = 3
        case .steadyUnderline: code = 4
        case .blinkBar: code = 5
        case .steadyBar: code = 6
        }
        view.feed(text: "\u{1b}[\(code) q")
    }

    // MARK: - Font sizing

    private static let minFontSize: CGFloat = 6
    private static let maxFontSize: CGFloat = 48

    func setFontSize(_ size: CGFloat) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        fontSize = clamped
        let family = config.font.familyName ?? "Menlo"
        view.font = NSFont(name: family, size: clamped)
            ?? NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
    }

    func adjustFontSize(by delta: CGFloat) { setFontSize(fontSize + delta) }
    func resetFontSize() { setFontSize(config.font.pointSize) }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Intentionally empty. Kept as an explicit no-op rather than omitted so
        // it is obvious this is handled, not forgotten: SwiftTerm issue #494
        // (open) reports duplicate/orphan lines on narrowing reflow, and this is
        // the hook to instrument if that is ever observed here.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        currentTitle = title
        delegate?.pane(self, didChangeTitle: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // OSC 7. Not used yet; a future tab title could prefer it over OSC 0/2.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        delegate?.paneDidTerminate(self)
    }
}
