// swift-tools-version: 6.0
import PackageDescription

// The real app. Step 2 of ../.afk/plans/native-swift-terminal-afk-host.md.
//
// `MacTerminal` is a PLACEHOLDER name — rename freely, nothing depends on it
// except Scripts/make-app-bundle.sh and the Info.plist it generates.
let package = Package(
    name: "MacTerminal",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Upstream SwiftTerm v1.15.0, vendored at ../vendor/SwiftTerm with one
        // local patch (the optional Metal shader resource is excluded, because
        // Xcode 26.6 moved the Metal toolchain to a downloadable component that
        // is not installed here). See README.md ("Dependency note") for the
        // rationale and how to recreate it. Swapping to the real upstream
        // package once `xcodebuild -downloadComponent MetalToolchain` has run is
        // a one-line change.
        .package(path: "../vendor/SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "MacTerminal",
            dependencies: ["SwiftTerm"],
            path: "Sources/MacTerminal"
        )
    ]
)
