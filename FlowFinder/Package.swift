// swift-tools-version:5.9
import PackageDescription

// NOTE: This manifest declares the app executable target only.
//
// Tests are NOT declared here on purpose. The project's unit tests are
// XCTest and must run through the Xcode project — `FlowFinder.xcodeproj`
// owns the `FlowFinderTests` unit-test bundle and the shared
// `FlowFinderTests` scheme (`xcodebuild test -scheme FlowFinderTests`).
// `swift test` cannot run XCTest, and SwiftPM has no `testTarget` for this
// project by design (a fake one that does not compile/run would only mislead).
let package = Package(
    name: "FlowFinder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FlowFinder",
            targets: ["FlowFinder"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FlowFinder",
            path: "FlowFinder",
            exclude: ["Resources", "Libraries"],
            publicHeadersPath: "include",
            swiftSettings: [
                .unsafeFlags(["-I", "../rust-core/include"]),
                .unsafeFlags(["-I", "include"])
            ],
            linkerSettings: [
                .linkedLibrary("flowfinder_core", .when(platforms: [.macOS])),
                .linkedFramework("QuickLook", .when(platforms: [.macOS])),
                .unsafeFlags(["-L", "../rust-core/target/debug"], .when(platforms: [.macOS]))
            ]
        )
    ]
)
