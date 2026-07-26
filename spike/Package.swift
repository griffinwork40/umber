// swift-tools-version: 6.0
import PackageDescription

// Throwaway spike. Purpose: answer the Step 0 gates in
// ../.afk/plans/native-swift-terminal-afk-host.md before committing to the project.
// Delete this whole directory once the gates are answered.
let package = Package(
    name: "TerminalSpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Upstream v1.15.0, NOT CodeEdit's stale `thecoolwinter` fork (last push
        // 2025-07-17). Vendored into vendor/SwiftTerm with ONE local patch: the
        // optional Metal shader resource is excluded, because Xcode 26.6 moved the
        // Metal toolchain to a downloadable component that isn't installed here.
        // See vendor/SwiftTerm/Package.swift for the annotated patch. The gates
        // test the VT engine, which is renderer-independent.
        .package(path: "vendor/SwiftTerm")
    ],
    targets: [
        // Human-judgment gates: G1 (render), G3 (Shift+Tab), G4 (Ctrl+B), G6 (soak).
        .executableTarget(
            name: "TerminalSpike",
            dependencies: ["SwiftTerm"]
        ),
        // Automated gates: G2 (reflow / issue #494), G5 (bracketed paste mode).
        .testTarget(
            name: "SpikeGatesTests",
            dependencies: ["SwiftTerm"]
        )
    ]
)
