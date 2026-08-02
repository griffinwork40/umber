//
//  TerminalEngine.swift
//  Which emulator core backs a terminal document, and how a config string becomes that choice.
//
//  Its own file, and deliberately view-free (Foundation only), for exactly the reasons
//  `Renderer.swift` gives: the *decision* is a pure mapping from a user-supplied string to a
//  case, and a pure mapping can be compiled into a headless check without an NSView — or an
//  emulator — in scope. `check-engine-config.sh` compiles this file alone. *Acting* on the
//  decision is `SpaceViewController+DocumentConstruction.swift`, which is the only place in
//  the app that names both pane types.
//
//  The separation matters more here than it did for `Renderer`. A typo in a mapping table is
//  the quietest possible bug: `"engine": "ghosty"` reads correctly, parses without a throw,
//  and silently gets SwiftTerm — the user then evaluates the wrong engine for a week and
//  reports on it. That is the same failure `check-renderer-config.sh` exists to prevent, and
//  it is why this enum is reachable without a GPU, a window server, or `swift build`.
//

import Foundation

/// The emulator core behind a terminal document.
///
/// Both cores are linked into the app **on purpose** and neither is written here. This exists
/// because `.afk/plans/emulator-foundation-probe-and-vendor-integrity.md` chose a reversible
/// swap over a bet: `GhosttyPane` ships beside `TerminalPane` behind the `SpaceDocument` seam,
/// the operator lives in one of them for real work, and the loser is deleted in Phase 6 —
/// after which this enum collapses to nothing and should be deleted with it.
///
/// * `.swiftTerm` — `TerminalPane`, on vendored SwiftTerm v1.15.0 + four local patches. Four
///   years of use behind it and three upstream defects fixed here by reading its source
///   (`patches/swiftterm/0002` scrollback reflow, `0003` the alt-buffer tmux bleed, `0004` an
///   ungated release-build `abort()`). What it cannot do is shell integration: OSC 7 and
///   OSC 133 never arrive, because SwiftTerm sets no `TERM_PROGRAM`
///   (`Terminal.swift:5873`) and macOS's own emitter is gated on it (`/etc/zshrc:74`).
///
/// * `.ghostty` — `GhosttyPane`, on libghostty-spm `.exact("1.3.2")`. Actively maintained,
///   ships none of the three defects above, and gives OSC 7 and OSC 133 for free — both
///   observed arriving (`check-ghostty-pane.sh` case 5b asserts the OSC 7 path against the
///   pane's own root). The cost is auditability: a 51.8 MB prebuilt `GhosttyKit.xcframework`
///   is not readable source, so a defect found here is an upstream issue and a wait rather
///   than a local patch. `AFK.md` records that trade as a real convention loss, not a win.
enum TerminalEngine: String, CaseIterable {
    case swiftTerm
    case ghostty

    /// `.swiftTerm`, and this default is the whole point of shipping both.
    ///
    /// Not an endorsement and not inertia — it is what makes the swap reversible. Three
    /// things are still open on the Ghostty side as of 2026-08-01: the Phase 5 gate
    /// (`check-reflow-ghostty.sh`, the 8 narrowing-with-scrollback cases that
    /// `.afk/plans/libghostty-swap-sequencing-2026-07-28.md` §6 calls a **hard** acceptance
    /// criterion) is not written yet; `GhosttyTerminalView` has no kitty-keyboard guard
    /// because libghostty exposes no equivalent query; and G6, the multi-hour soak, resets
    /// when the engine changes (§7). Flipping this default is what Phase 5 is *for*, and it
    /// should follow the gate and real use — not this note.
    static let `default`: TerminalEngine = .swiftTerm

    /// Map a config string onto a case, or `nil` if it names nothing.
    ///
    /// Spellings are generous for the reason `Renderer.named` is: this is a hand-edited JSON
    /// file and a strict match fails by silently ignoring the setting. `nil` becomes a
    /// `warnings` entry in `AppConfig.load()` rather than a throw, so a typo degrades to the
    /// default and says so on stderr.
    ///
    /// `"swiftterm"` and `"ghostty"` are the canonical spellings; the rest are what someone
    /// actually types. `"libghostty"` is included because that is the dependency's name and
    /// therefore the word in every commit message and plan doc that discusses it.
    static func named(_ raw: String) -> TerminalEngine? {
        switch raw.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "swiftterm", "swift-term", "swift", "legacy":
            return .swiftTerm
        case "ghostty", "libghostty", "lib-ghostty":
            return .ghostty
        default:
            return nil
        }
    }

    /// The canonical spellings, one per case. Derived from `allCases` rather than written out,
    /// so adding a case cannot leave the user-facing message behind.
    ///
    /// Deliberately narrower than what `named(_:)` accepts, and `check-engine-config.sh`
    /// asserts exactly that: it requires every case's `configName` to appear here, so this
    /// must stay one-name-per-case. Widening the *warning* is `acceptedConfigNames` below.
    static var configNames: String {
        allCases.map(\.configName).joined(separator: ", ")
    }

    /// Every spelling `named(_:)` actually accepts — what `AppConfig.load()` puts in front of a
    /// user who just mistyped the field (`Config.swift:293-295`).
    ///
    /// Separate from `configNames` because the two answer different questions. That one is
    /// "what should I write in the file", one canonical name per engine, and the gate pins it
    /// to `allCases`. This one is "what would have worked", and naming only the canonical two
    /// told a user that `libghostty` — the dependency's own name, the word in every commit
    /// message and plan doc about it — was invalid when `named(_:)` takes it happily
    /// (PR #21 review, item 5).
    ///
    /// Hand-written, and that is the cost: it is a second copy of `named(_:)`'s switch and can
    /// drift from it. Accepted because the alias table cannot be derived from `allCases` the
    /// way `configNames` can, and the failure mode is a warning that understates rather than a
    /// mapping that misfires. Add an alias to `named(_:)` and add it here.
    static var acceptedConfigNames: String {
        "swiftterm, swift-term, swift, legacy, ghostty, libghostty, lib-ghostty"
    }

    /// The canonical spelling to write in a config file.
    var configName: String {
        switch self {
        case .swiftTerm: return "swiftterm"
        case .ghostty: return "ghostty"
        }
    }
}
