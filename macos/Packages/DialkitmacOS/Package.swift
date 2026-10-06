// swift-tools-version: 5.10
import PackageDescription

// Vendored subset of mikelikesdesign/dialkit-macos @ cc305b46beb731e50cbdde84aed5530d83842acc.
// See VENDORED.md. Only the tuning API and the debug agent; the inspector
// app is built from the upstream checkout, never from here.
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
            path: "Sources/DialKitProtocol"
        ),
        .target(
            name: "DialkitmacOSCore",
            dependencies: ["DialkitmacOSProtocol"],
            path: "Sources/DialKitCore"
        ),
        .target(
            name: "DialkitmacOS",
            dependencies: ["DialkitmacOSCore"],
            path: "Sources/DialKit"
        ),
        .target(
            name: "DialkitmacOSAgent",
            dependencies: ["DialkitmacOSCore", "DialkitmacOSProtocol"],
            path: "Sources/DialKitAgent"
        )
    ]
)
