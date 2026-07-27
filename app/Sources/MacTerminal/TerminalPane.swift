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
    let view: MTTerminalView
    private(set) var currentTitle: String = ""
    weak var delegate: TerminalPaneDelegate?

    private var config: AppConfig
    private var fontSize: CGFloat

    init(config: AppConfig, frame: NSRect) {
        self.config = config
        // A zoom set with ⌘+ applies to every pane, including ones opened later
        // and ones opened in a future launch — so a new tab never springs back to
        // the configured size while the tab beside it stays zoomed.
        self.fontSize = FontZoom.override ?? config.font.pointSize
        // LocalProcessTerminalView only exposes init(frame:) — the font-taking
        // initialiser belongs to TerminalView and is not inherited here, so the
        // font is applied via the property in apply(config:) below.
        self.view = MTTerminalView(frame: frame)
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

        // Keep the historical xterm 6x6x6 cube and greyscale ramp for indices
        // 16–255. SwiftTerm defaults to `.base16Lab`, which *derives* those 240
        // colours by interpolating between this terminal's background and
        // foreground (`Terminal.swift:725` rebuildAnsiPalette), so any
        // 256-colour TUI renders against synthesised approximations rather than
        // the values it was actually designed for — and every other terminal
        // (Ghostty, iTerm2, Terminal.app) shows the standard cube. Set this
        // before any colour below: under `.xterm`, installing colours stops
        // triggering a palette rebuild altogether (`Terminal.swift:523`).
        view.getTerminal().ansi256PaletteStrategy = .xterm

        // A nil theme means "install nothing", leaving SwiftTerm's own defaults
        // in place — which is the default configuration. Setting a background or
        // foreground is not free (see above), so we only pay for it on request.
        if let theme = config.theme {
            view.nativeBackgroundColor = theme.background
            view.nativeForegroundColor = theme.foreground
            view.caretColor = theme.cursor
            // installColors is a no-op unless the array is exactly 16 long; Config
            // guarantees that invariant before we get here.
            view.installColors(theme.ansi.map { $0.asSwiftTermColor })
        }
        view.optionAsMetaKey = config.optionAsMeta
        view.changeScrollback(config.scrollback == 0 ? nil : config.scrollback)
        // Re-resolve rather than reusing `fontSize`, so editing `font.size` and
        // hitting ⌘R actually changes the size. A live ⌘+ zoom still outranks the
        // file — ⌘0 drops it and hands control back to the config.
        setFontSize(FontZoom.override ?? config.font.pointSize, persist: false)
        // `MT_DIAG=1` dumps the resolved appearance state to stderr. This app has
        // no test target, so this is its only observability: it is what caught
        // the Menlo-instead-of-SF-Mono fallback and the collapsed scrollbar
        // thumb, both of which were invisible from the source alone. Costs
        // nothing when the variable is unset.
        if ProcessInfo.processInfo.environment["MT_DIAG"] != nil {
            let t = view.getTerminal()
            // Projected thumb once the scrollback is full — the steady state that
            // matters. `view.scrollThumbsize` right now is ~1.0 (empty buffer).
            let projected = max(CGFloat(t.rows) / CGFloat(config.scrollback + t.rows), 0.01)
            FileHandle.standardError.write("""
            [diag] theme=\(config.theme == nil ? "nil(SwiftTerm-defaults)" : "custom") \
            strategy=\(t.ansi256PaletteStrategy) scrollback=\(config.scrollback) \
            rows=\(t.rows) thumbNow=\(String(format: "%.3f", view.scrollThumbsize)) \
            thumbWhenFull=\(String(format: "%.4f", projected)) font=\(view.font.fontName) \
            size=\(view.font.pointSize) configSize=\(config.font.pointSize) \
            zoom=\(FontZoom.override.map { String(describing: $0) } ?? "none")\n
            """.data(using: .utf8)!)
        }
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

    private static let minFontSize = CGFloat(AppConfig.minFontSize)
    private static let maxFontSize = CGFloat(AppConfig.maxFontSize)

    /// Resize the configured face. Derived from the resolved font's **descriptor**,
    /// not re-resolved from its family name: the system monospaced face is
    /// `.AppleSystemUIFontMonospaced`, a dot-prefixed internal family that is not
    /// guaranteed to survive `NSFont(name:)`, and the old code's fallback for that
    /// miss was hardcoded Menlo — the exact silent substitution that made v0.1
    /// render worse than the spike (see `Config.preferredMonoFont`). The
    /// descriptor carries the resolved face, so zooming cannot change it.
    private func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        NSFont(descriptor: base.fontDescriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// `persist: false` is for applying someone else's already-stored zoom (a
    /// reload, or a newly-opened tab) — only a real user gesture should write.
    func setFontSize(_ size: CGFloat, persist: Bool = true) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        fontSize = clamped
        view.font = resized(config.font, to: clamped)
        if persist {
            // Store nothing when the zoom lands back on the configured size, so
            // editing `font.size` later still takes effect instead of being
            // permanently masked by a stale override.
            FontZoom.override = clamped == config.font.pointSize ? nil : clamped
        }
    }

    func adjustFontSize(by delta: CGFloat) { setFontSize(fontSize + delta) }

    /// ⌘0 — back to the configured size, dropping the stored zoom.
    func resetFontSize() {
        FontZoom.override = nil
        setFontSize(config.font.pointSize, persist: false)
    }

    /// The size this pane is currently rendering at, so a zoom applied in one tab
    /// can be mirrored into the others.
    var currentFontSize: CGFloat { fontSize }

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
