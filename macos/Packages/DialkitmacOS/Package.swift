// swift-tools-version: 5.10
import PackageDescription

// Vendored subset of mikelikesdesign/dialkit-macos @ cc305b46beb731e50cbdde84aed5530d83842acc.
// See VENDORED.md. Only the tuning API and the debug agent; the inspector
// app is built from the upstream checkout, never from here.
// Ghostties: every source file is wrapped in `#if DIALKIT_ENABLED`, defined only for the
// debug package configuration, so Release links empty modules.
let debugOnly: [SwiftSetting] = [.define("DIALKIT_ENABLED", .when(configuration: .debug))]

let package = Package(
    name: "DialkitmacOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DialkitmacOS", targets: ["DialkitmacOS"]),
        .library(name: "DialkitmacOSAgent", targets: ["DialkitmacOSAgent"])
    ],
    targets: [
        .target(
            name: "DialkitmacOSProtocol",
            path: "Sources/DialKitProtocol",
            swiftSettings: debugOnly
        ),
        .target(
            name: "DialkitmacOSCore",
            dependencies: ["DialkitmacOSProtocol"],
            path: "Sources/DialKitCore",
            swiftSettings: debugOnly
        ),
        .target(
            name: "DialkitmacOS",
            dependencies: ["DialkitmacOSCore"],
            path: "Sources/DialKit",
            swiftSettings: debugOnly
        ),
        .target(
            name: "DialkitmacOSAgent",
            dependencies: ["DialkitmacOSCore", "DialkitmacOSProtocol"],
            path: "Sources/DialKitAgent",
            swiftSettings: debugOnly
        )
    ]
)
