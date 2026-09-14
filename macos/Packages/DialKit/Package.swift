// swift-tools-version: 5.10
import PackageDescription

// Ghostties: DialKit compiles to nothing outside the debug package configuration.
let debugOnly: [SwiftSetting] = [.define("DIALKIT_ENABLED", .when(configuration: .debug))]

let package = Package(
    name: "DialKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DialKit",
            targets: ["DialKit"]
        )
    ],
    targets: [
        .target(
            name: "DialKitCore",
            swiftSettings: debugOnly
        ),
        .target(
            name: "DialKit",
            dependencies: ["DialKitCore"],
            swiftSettings: debugOnly
        )
    ]
)
