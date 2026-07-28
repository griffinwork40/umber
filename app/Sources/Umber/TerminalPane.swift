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
    /// `documentStatus` changed — the tab strip needs to repaint.
    func paneDidChangeStatus(_ pane: TerminalPane)
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
    let view: UmberTerminalView
    private(set) var currentTitle: String = ""
    weak var delegate: TerminalPaneDelegate?

    /// What the tab strip should be saying about this pane.
    ///
    /// Only `.idle` and `.attention` are reachable today; see `DocumentStatus` for
    /// which libghostty delegate fills each of the others in and why building OSC 133
    /// parsing here now would be work done twice (probe plan §6.2).
    private(set) var status: DocumentStatus = .idle {
        didSet {
            guard status != oldValue else { return }
            delegate?.paneDidChangeStatus(self)
        }
    }

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
        self.view = UmberTerminalView(frame: frame)
        super.init()
        view.processDelegate = self
        // Separate from `processDelegate` because the bell is not on
        // `LocalProcessTerminalViewDelegate` at all — see `UmberTerminalView.bellDelegate`
        // for the four members it does carry and why reaching the bell needs a subclass
        // override rather than a delegate slot.
        view.bellDelegate = self
        view.autoresizingMask = [.width, .height]
        apply(config: config)
    }

    // MARK: - Attention state

    /// The user is looking at this pane, so whatever it wanted to tell them has landed.
    ///
    /// Called from `documentDidBecomeActive()` (the `SpaceDocument` conformance) rather
    /// than from a window/focus notification: becoming the visible document is exactly
    /// the moment the signal has been consumed, and it is the same hook that already
    /// takes first responder.
    func clearAttention() {
        status = .idle
    }

    /// Is this the document currently on screen in its Space?
    ///
    /// Derived from the view hierarchy rather than tracked with a flag, because the
    /// container already maintains exactly this invariant: `present(documentView:)`
    /// removes every other document's view from the container and adds the new one
    /// (`SpaceViewController.swift`, `DocumentAreaViewController.present`), so having a
    /// superview *is* being the presented document. A cached flag would be a second
    /// copy of that fact with no "did become inactive" callback to keep it honest.
    private var isActiveDocument: Bool { view.superview != nil }

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
        // `UMBER_DIAG=1` dumps the resolved appearance state to stderr. This app has
        // no test target, so this is its only observability: it is what caught
        // the Menlo-instead-of-SF-Mono fallback and the collapsed scrollbar
        // thumb, both of which were invisible from the source alone. Costs
        // nothing when the variable is unset.
        if ProcessInfo.processInfo.environment["UMBER_DIAG"] != nil {
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
            zoom=\(FontZoom.override.map { String(describing: $0) } ?? "none") \
            bgLuminance=\(String(format: "%.4f", config.effectiveBackground.relativeLuminance)) \
            chrome=\(config.appearance?.name.rawValue ?? "system") \
            windowChrome=\(view.window?.effectiveAppearance.name.rawValue ?? "unattached")\n
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

    /// Moved to `AppConfig.resized(_:to:)` when `FileViewerPane` needed the same
    /// descriptor-preserving resize — see there for why `NSFont(name:size:)` is
    /// wrong. Kept as a shim so the call sites below stay readable.
    private func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        AppConfig.resized(base, to: size)
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
        // Deliberately does NOT set `.failed` on a non-zero exit code. This fires when
        // the *shell itself* exits, at which point the pane is closing
        // (`SpaceViewController.paneDidTerminate`) — a status on a tab about to vanish
        // is a status nobody reads. `.failed` is for a failed *command* inside a live
        // shell, which needs OSC 133 and arrives with libghostty's
        // `TerminalSurfaceCommandFinishedDelegate` (probe plan §6.2).
        delegate?.paneDidTerminate(self)
    }
}

// MARK: - UmberTerminalViewDelegate

extension TerminalPane: UmberTerminalViewDelegate {
    /// BEL is the one attention signal that crosses a pty with no shell integration at
    /// all, which is why it is the single wired case: an agent REPL blocked on a prompt
    /// beeps, and this app exists to host one.
    func terminalViewDidRingBell(_ view: UmberTerminalView) {
        // Not raised on the pane the user is already reading. The whole point of the
        // marker is to label a tab you are *not* looking at, and lighting up the front
        // tab would train the eye to ignore it.
        guard !isActiveDocument else { return }
        status = .attention
    }
}
