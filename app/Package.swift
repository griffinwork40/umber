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
        // Upstream SwiftTerm v1.15.0, vendored at ../vendor/SwiftTerm with one
        // local patch (the optional Metal shader resource is excluded, because
        // Xcode 26.6 moved the Metal toolchain to a downloadable component that
        // is not installed here). See README.md ("Dependency note") for the
        // rationale and how to recreate it. Swapping to the real upstream
        // package once `xcodebuild -downloadComponent MetalToolchain` has run is
        // a one-line change.
        .package(path: "../vendor/SwiftTerm"),
        // SPIKE ONLY (branch afk/libghostty-spike): evaluating libghostty as a
        // replacement emulator core. Prebuilt GhosttyKit.xcframework, MIT.
        // See ../.afk/plans/emulator-foundation-probe-and-vendor-integrity.md §5 Step 1.
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Umber",
            dependencies: ["SwiftTerm"],
            path: "Sources/Umber"
        ),
        // SPIKE ONLY. Separate target so Umber's own sources stay untouched while
        // the foundation question is open.
        .executableTarget(
            name: "GhosttySpike",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm")
            ],
            path: "Sources/GhosttySpike"
        )
    ]
)
