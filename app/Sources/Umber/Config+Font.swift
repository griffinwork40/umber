//
//  Config+Font.swift
//  Font resolution for `AppConfig`: size/family constants, face lookup, and fail-soft application.
//
//  Its own file for the same reason as `Config+Theme.swift` and `Config+Editor.swift`:
//  `Config.swift` is at the 350-line ceiling and this is a clean seam. Everything
//  here is one question — "given some optional font values a user typed, which face
//  and metrics do we install?" — and answering it needs none of the theme/engine
//  machinery in `AppConfig`.
//
//  Takes primitives rather than `FontSpec` because `ConfigFile` is `private` in
//  `Config.swift`. Passing individual optionals keeps that boundary intact and makes
//  this callable from anywhere without constructing a Decodable.
//
//  THE INVARIANT THIS FILE OWNS: it never throws. A bad value costs that one field
//  and appends one warning. `AppConfig.load()` has no error path — preserve that.
//
//  Font-adjacent terminal settings (`fontThicken`, `lineHeight`, `ligatures`) also
//  live here because they share the same fail-soft shape and are logically part of
//  the "how text is rendered" concern rather than the "which shell to run" concern.
//

import AppKit

extension AppConfig {
    /// 14pt, not 13. The default has to be comfortable on a Retina display
    /// without touching a config file, and 13 read as cramped in use. Both
    /// `font.size` and ⌘+ / ⌘− override this.
    static let defaultFontSize: Double = 14

    /// Bounds for both `font.size` and the live zoom. Below ~6pt the glyphs stop
    /// being legible; above ~48 a standard window holds too few columns for a TUI
    /// to lay out. Shared so the config path and the zoom path cannot disagree.
    static let minFontSize: Double = 6
    static let maxFontSize: Double = 48

    /// Resize the configured face. Derived from the resolved font's **descriptor**,
    /// not re-resolved from its family name: the system monospaced face is
    /// `.AppleSystemUIFontMonospaced`, a dot-prefixed internal family that is not
    /// guaranteed to survive `NSFont(name:)`, and the old code's fallback for that
    /// miss was hardcoded Menlo — the exact silent substitution that made v0.1
    /// render worse than the spike (see `preferredMonoFont`). The descriptor
    /// carries the resolved face, so zooming cannot change it.
    ///
    /// Lives here rather than on one pane because every document kind zooms
    /// (`SpaceDocument.setFontSize`), and a second private copy in `FileViewerPane`
    /// is a second place for this fallback to rot.
    static func resized(_ base: NSFont, to size: CGFloat) -> NSFont {
        NSFont(descriptor: base.fontDescriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Resolve the `font` block (plus font-adjacent fields) from config primitives,
    /// fail-soft per field. Mutates `self` directly and appends to `warnings` for
    /// any degradations.
    ///
    /// An out-of-range size is reported rather than silently clamped: every other
    /// field in `load()` explains itself when it is ignored, and a size that quietly
    /// did nothing is precisely the failure that makes a configurable setting feel
    /// unconfigurable.
    mutating func applyFont(family: String?, requestedSize: Double?,
                            fontThicken: Bool? = nil,
                            lineHeight: Double? = nil,
                            ligatures: Bool? = nil) {
        var size = AppConfig.defaultFontSize
        if let requested = requestedSize {
            if requested >= AppConfig.minFontSize && requested <= AppConfig.maxFontSize {
                size = requested
            } else {
                warnings.append(
                    "font.size \(requested) is outside \(Int(AppConfig.minFontSize))–\(Int(AppConfig.maxFontSize)) — using \(Int(size))")
            }
        }
        let resolved = AppConfig.preferredMonoFont(family: family, size: size)
        self.font = resolved.font
        if let warning = resolved.warning { warnings.append(warning) }

        if let v = fontThicken { self.fontThicken = v }
        if let v = lineHeight {
            let lo = 0.8, hi = 2.0
            if v >= lo && v <= hi { self.lineHeight = CGFloat(v) }
            else { warnings.append("lineHeight \(v) is outside \(lo)–\(hi) — using \(self.lineHeight)") }
        }
        // `ligatures` is accepted in the config file but not yet acted on — the field
        // is parsed here so the file stays valid when the feature ships. See the header
        // of TerminalPane+Typography.swift for why it is deferred.
        if ligatures != nil {
            warnings.append("ligatures: not yet implemented — ignored")
        }
    }

    /// Names people write in a config when they mean the system monospaced face.
    /// None of these resolve through `NSFont(name:)`, so they must be mapped.
    static let systemMonoAliases: Set<String> = [
        "sf mono", "sfmono", "sfmono-regular", "sf mono regular", "system", "system mono",
    ]

    /// Resolve a monospaced font, reporting a human-readable problem when a
    /// requested family cannot be honoured. Never returns nil — a terminal with
    /// no font is not a useful failure mode.
    ///
    /// With nothing requested this returns the **system monospaced face**, which
    /// is SF Mono and is also exactly what SwiftTerm's own `FontSet.defaultFont`
    /// uses. It is deliberately NOT reached via `NSFont(name: "SF Mono")`: that
    /// call returns nil, because SF Mono is not registered under that name (nor
    /// under "SFMono-Regular"). v0.1 asked for it by name, silently got Menlo as
    /// the next candidate, and therefore rendered visibly worse than the Step 0
    /// spike — which set no font at all and so kept SwiftTerm's default. The
    /// system-mono call used to sit at the BOTTOM of this function, unreachable,
    /// because Menlo always resolves first.
    static func preferredMonoFont(family: String?, size: Double) -> (font: NSFont, warning: String?) {
        let systemMono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        guard let family, !systemMonoAliases.contains(family.lowercased()) else {
            return (systemMono, nil)
        }
        if let f = NSFont(name: family, size: size) { return (f, nil) }
        return (systemMono, "font.family '\(family)' unavailable — using the system monospaced face")
    }
}
