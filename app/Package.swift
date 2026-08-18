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
        // Upstream SwiftTerm v1.15.0, vendored at ../vendor/SwiftTerm with SIX
        // local patches — 0001 ships the Metal shader as a `.copy` resource so the
        // GPU renderer is reachable, 0002/0003 are required correctness fixes
        // (SwiftTerm #494 scrollback reflow, and the alt-buffer resize that bled
        // stale cells across tmux panes), 0004 gates an upstream debug `abort()`
        // behind `#if DEBUG`, 0005 adds DCS Ptmux passthrough, and 0006 gates
        // linefeed selection-clear on mouseMode. See ../patches/swiftterm/SwiftTerm.pin
        // for the hashes and README.md ("Dependency note") for how to recreate the tree.
        //
        // A tree missing 0002/0003 compiles, runs, and silently corrupts the
        // buffer, which is why Scripts/verify-vendor.sh is a hard gate in
        // Scripts/make-app-bundle.sh rather than advisory.
        .package(path: "../vendor/SwiftTerm"),
    ],
    targets: [
        .executableTarget(
            name: "Umber",
            dependencies: ["SwiftTerm"],
            path: "Sources/Umber",
            // `shell-integration.zsh` must be declared here so SwiftPM copies it into
            // the product bundle and `Bundle.main.path(forResource:ofType:)` returns a
            // non-nil path. Without this, `swift run Umber` and the release bundle both
            // silently skip UMBER_INTEGRATION, and the zsh integration is never sourced.
            // The path is relative to the target's `path` ("Sources/Umber"), so two levels
            // up to the package root, then into Resources/.
            resources: [.copy("../../Resources/shell-integration.zsh")]
        )
    ]
)
