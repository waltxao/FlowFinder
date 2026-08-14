// swift-tools-version:5.9
import PackageDescription

// NOTE: This manifest declares the app executable target only.
//
// Tests are NOT declared here on purpose. The project's unit tests are
// XCTest and must run through the Xcode project — `FlowFinderNative.xcodeproj`
// owns the `FlowFinderNativeTests` unit-test bundle and the shared
// `FlowFinderNativeTests` scheme (`xcodebuild test -scheme FlowFinderNativeTests`).
// `swift test` cannot run XCTest, and SwiftPM has no `testTarget` for this
// project by design (a fake one that does not compile/run would only mislead).
let package = Package(
    name: "FlowFinderNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FlowFinderNative",
            targets: ["FlowFinderNative"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FlowFinderNative",
            path: "FlowFinderNative",
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
