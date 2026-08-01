// swift-tools-version: 6.0
import PackageDescription

// The real app. Step 2 of ../.afk/plans/native-swift-terminal-afk-host.md.
//
// The product name is `Umber` — a warm earth pigment, matching the app's own
// accent (#E67E4C, see Config.swift). Settled 2026-07-27; the reasoning and the
// availability checks live in ../.afk/research/naming-decision-2026-07-27.md.
let package = Package(
    name: "Umber",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Upstream SwiftTerm v1.15.0, vendored at ../vendor/SwiftTerm with FOUR
        // local patches — 0001 ships the Metal shader as a `.copy` resource so the
        // GPU renderer is reachable, 0002/0003 are required correctness fixes
        // (SwiftTerm #494 scrollback reflow, and the alt-buffer resize that bled
        // stale cells across tmux panes), 0004 gates an upstream debug `abort()`
        // behind `#if DEBUG`. See ../patches/swiftterm/SwiftTerm.pin for the hashes
        // and README.md ("Dependency note") for how to recreate the tree.
        //
        // A tree missing 0002/0003 compiles, runs, and silently corrupts the
        // buffer, which is why Scripts/verify-vendor.sh is a hard gate in
        // Scripts/make-app-bundle.sh rather than advisory.
        .package(path: "../vendor/SwiftTerm"),

        // libghostty — the candidate replacement emulator core. Phase 2 of
        // ../.afk/plans/libghostty-swap-sequencing-2026-07-28.md §3.
        //
        // `.exact`, NOT `from:`. The spike (afk/libghostty-spike @ 123919f) used
        // `from: "1.2.0"`, and the probe plan §8.1 names that as precisely the
        // mistake not to repeat: libghostty's ABI is PRE-STABLE and its embedding
        // API is undocumented outside Zig source, so a floating constraint lets a
        // stray `swift package update` move it silently. §7 risk 2 records that the
        // mitigation "becomes real only when production declares .exact("1.3.2")" —
        // this line is that mitigation.
        //
        // This is a 51.8 MB prebuilt XCFramework (MIT). It is NOT auditable text, which
        // contradicts a stated project convention; ../AFK.md is amended in the same
        // commit rather than left standing while this line violates it (§7 risk 3).
        // Its checksum IS verified — `checksum: "9dcfaa19…"` in the dependency's own
        // Package.swift:49 — so the risk is version drift, not an unverified download.
        //
        // ONE transitive dep, not two: it declares only MSDisplayLink
        // (its Package.swift:18). swift-argument-parser comes from the VENDORED SwiftTerm
        // (vendor/SwiftTerm/Package.swift:151) and predates this line.
        //
        // `.exact` here pins only THIS edge. Both live transitive constraints are
        // floating `from:`, so the pin becomes reproducible only because
        // `Package.resolved` is committed — see the `!app/Package.resolved` negation in
        // ../.gitignore. Ignoring it was correct while every dependency was a local
        // path (nothing to pin); a versioned remote dependency changed that.
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.3.2"),
    ],
    targets: [
        .executableTarget(
            name: "Umber",
            dependencies: [
                "SwiftTerm",
                // Both engines are linked ON PURPOSE for the duration of the probe.
                // `GhosttyPane` lands beside `TerminalPane` behind the `SpaceDocument`
                // seam so the foundation choice stays reversible instead of becoming a
                // bet (probe plan §5). Exactly one of these dependencies gets deleted
                // at Step 2 — "decide, then delete the loser" — and not before the
                // operator has actually lived in the winner (§7 Phase 6).
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ],
            path: "Sources/Umber"
        )
    ]
)
