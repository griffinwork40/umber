//
//  GhosttyPane+Appearance.swift
//  Turning an `AppConfig` into libghostty's configuration vocabulary, and zooming it live.
//
//  Split out of `GhosttyPane.swift` when that file crossed the 350-line ceiling. The seam is a
//  real concern rather than a line-count convenience: everything here answers one question —
//  "what does this engine need to be told to look the way the user asked?" — and none of it is
//  about owning a shell, which is what the pane proper does. `TerminalPane+Renderer.swift` is
//  the same split on the other engine.
//
//  It is also where the three PARITY GAPS live, and they are the reason this file deserves
//  attention out of proportion to its size. `shell`, `scrollback` and `renderer` are config
//  fields libghostty's typed Swift API cannot express; two are attempted through the
//  `.custom(key:value:)` escape hatch with UNVERIFIED keys, and one is inapplicable. See
//  `GhosttyPane.swift`'s header for the full accounting and `diagnoseResolvedState()` below
//  for the runtime report that keeps them honest.
//

import AppKit
import GhosttyTerminal

extension GhosttyPane {
    // MARK: - Appearance

    func apply(config: AppConfig) {
        self.config = config
        // Re-resolve rather than reusing `fontSize`, so editing `font.size` and hitting ⌘R
        // changes the size. A live ⌘+ zoom still outranks the file; ⌘0 drops it.
        setFontSize(FontZoom.override ?? config.font.pointSize, persist: false)
        // Where `TerminalPane.apply(config:)` emits its own diag block (`TerminalPane.swift:190`).
        // Here rather than in `pushConfiguration()` because a live ⌘+ pushes too and would
        // reprint the whole report per keystroke; ⌘R and pane construction are the events worth
        // a line. It is called AT ALL because an uncalled diagnostic is the precise failure
        // class this pane's header says the report exists to prevent — a config-shaped thing
        // that parses and does nothing — and the three `.custom` keys have no other witness.
        diagnoseResolvedState()
    }

    /// Push the whole resolved appearance at the controller in one call.
    ///
    /// One call rather than a setter per field because `setTerminalConfiguration` diffs the
    /// entire configuration against the previous one and early-returns when equal
    /// (`TerminalController.swift:231`), then re-renders and re-pushes everything that
    /// remains. Calling it once per field would re-render N times for one ⌘R.
    func pushConfiguration() {
        controller.setTerminalConfiguration(Self.configuration(for: config, fontSize: fontSize))
    }

    /// `AppConfig` → libghostty's configuration vocabulary.
    ///
    /// `static` and taking everything it needs as parameters so it can run from `init` before
    /// `self` is fully formed, which is what lets the controller be built already-configured.
    static func configuration(
        for config: AppConfig, fontSize: CGFloat
    ) -> TerminalConfiguration {
        var c = TerminalConfiguration()
            .fontFamily(config.font.familyName ?? config.font.fontName)
            .fontSize(Float(fontSize))
            .cursorStyle(config.cursorStyle.ghosttyStyle)
            .cursorStyleBlink(config.cursorStyle.blinks)

        // A nil theme means "install nothing", leaving libghostty's own defaults in place —
        // the same contract `TerminalPane.apply(config:)` honours, and for the same reason:
        // the shipped defaults are good and overriding them is not free.
        if let theme = config.theme {
            c = c.background(theme.background.hexString)
                .foreground(theme.foreground.hexString)
                .cursorColor(theme.cursor.hexString)
            // Exactly 16 entries, guaranteed by Config before it gets here. Indices 0-15 only:
            // unlike SwiftTerm there is no 256-colour palette *strategy* to choose, because
            // ghostty already generates 16-255 as the standard xterm cube rather than
            // interpolating them out of bg/fg — which is precisely the misbehaviour
            // `TerminalPane` has to set `ansi256PaletteStrategy = .xterm` to prevent.
            for (i, colour) in theme.ansi.enumerated() {
                c = c.palette(i, color: colour.hexString)
            }
        }

        // ---- the three gaps, attempted through the escape hatch ----
        // `.custom` injects a raw `key = value` line into the rendered ghostty config
        // (`TerminalConfiguration.swift:332-334`). Whether ghostty's schema recognises any of
        // these keys is NOT knowable from the Swift source; an unrecognised key is expected to
        // be ignored rather than fatal, which is why attempting is safe and why the
        // `UMBER_DIAG` line below reports exactly what was sent.
        c = c.custom("command", "\(config.shell) -l")
        c = c.custom("macos-option-as-alt", config.optionAsMeta ? "true" : "false")
        if let limit = scrollbackLimitBytes(config.scrollback) {
            c = c.custom("scrollback-limit", limit)
        }
        return c
    }

    /// ghostty's `scrollback-limit` in BYTES, or nil when the user asked for no scrollback.
    ///
    /// Lines -> bytes. ghostty's `scrollback-limit` is a BYTE budget; Umber's `scrollback` is a
    /// line count. 512 bytes/line is a deliberate over-estimate of a typical 80-120 column line
    /// so the user gets at least the history they asked for. This is an assumption, not a
    /// measurement, and it is the single least defensible number in this file — Phase 5 either
    /// confirms the key and the unit or this comes out and `scrollback` becomes engine-specific.
    ///
    /// A function rather than two inline multiplications because `diagnoseResolvedState()` has
    /// to report the same number, and the diagnostic drifting from what was actually sent would
    /// defeat its whole purpose.
    ///
    /// OVERFLOW IS CLAMPED, NOT TRAPPED. `Config.swift` validates `scrollback` as `>= 0` with no
    /// ceiling, so `lines * 512` traps above `Int.max / 512` — turning a bad config field into a
    /// crash, which is exactly what this repo's fail-soft-per-field invariant exists to prevent.
    /// The guard belongs here rather than in `Config.swift` because the overflow is created by
    /// THIS file's unit conversion: the line count itself is representable, and `TerminalPane`
    /// never multiplies it.
    static func scrollbackLimitBytes(_ lines: Int) -> String? {
        guard lines > 0 else { return nil }
        let (bytes, overflowed) = lines.multipliedReportingOverflow(by: 512)
        return String(overflowed ? Int.max : bytes)
    }

    // MARK: - Font sizing

    private static let minFontSize = CGFloat(AppConfig.minFontSize)
    private static let maxFontSize = CGFloat(AppConfig.maxFontSize)

    func setFontSize(_ size: CGFloat, persist: Bool = true) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        fontSize = clamped
        // Through the CONTROLLER, not through `TerminalSurfaceOptions.fontSize`. That field is
        // part of the options' `isEquivalent(to:)` (`TerminalSurfaceOptions.swift:36-42`), so
        // reassigning it trips `configuration`'s didSet and REBUILDS the surface
        // (`TerminalSurfaceCoordinator.swift:30-35`) — which discards the scrollback. Zooming
        // must not erase history, so the live path is the only correct one.
        pushConfiguration()
        if persist {
            FontZoom.override = clamped == config.font.pointSize ? nil : clamped
        }
    }

    func adjustFontSize(by delta: CGFloat) { setFontSize(fontSize + delta) }

    func resetFontSize() {
        FontZoom.override = nil
        setFontSize(config.font.pointSize, persist: false)
    }

    var currentFontSize: CGFloat { fontSize }

    /// Dump the resolved state, mirroring `TerminalPane.apply(config:)`'s diag block so the
    /// two engines can be compared line for line in one terminal session.
    func diagnoseResolvedState() {
        diag("""
        theme=\(config.theme == nil ? "nil(ghostty-defaults)" : "custom") \
        font=\(config.font.familyName ?? config.font.fontName) size=\(fontSize) \
        configSize=\(config.font.pointSize) \
        zoom=\(FontZoom.override.map { String(describing: $0) } ?? "none") \
        cursor=\(config.cursorStyle.ghosttyStyle.rawValue)/blink=\(config.cursorStyle.blinks) \
        cwd=\(reportedDirectory ?? "unreported")
        """)
        diag("""
        UNVERIFIED custom keys sent: command='\(config.shell) -l' \
        macos-option-as-alt=\(config.optionAsMeta) \
        scrollback-limit=\(Self.scrollbackLimitBytes(config.scrollback) ?? "unset") \
        — none confirmed against ghostty's schema; renderer='\(config.renderer.configName)' \
        is INAPPLICABLE here (libghostty is GPU-only)
        """)
    }
}

// MARK: - CursorStyle bridging

extension CursorStyle {
    /// The shape half, in libghostty's vocabulary. The blink half is `blinks`.
    ///
    /// Here rather than in `CursorStyle.swift` on purpose: that file is Foundation-only by
    /// design so `check-cursor-style.sh` can compile it standalone, and naming
    /// `TerminalCursorStyle` there would drag GhosttyTerminal into it and kill the gate. The
    /// pure enum owns the *decomposition* (`shape`, `blinks`); this owns the *translation*.
    var ghosttyStyle: TerminalCursorStyle {
        switch shape {
        case .block: return .block
        case .underline: return .underline
        case .bar: return .bar
        }
    }
}
