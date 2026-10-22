// swift-tools-version:5.9
import PackageDescription

// Swift mirror of index.ts, for the native iOS app and the Mac app's desk
// bridge. No dependencies: callers decode rows from supabase-swift into these.
let package = Package(
    name: "GhosttiesCloud",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "GhosttiesCloud", targets: ["GhosttiesCloud"])
    ],
    targets: [
        .target(name: "GhosttiesCloud", path: "Sources/GhosttiesCloud"),
        .testTarget(
            name: "GhosttiesCloudTests",
            dependencies: ["GhosttiesCloud"],
            path: "Tests/GhosttiesCloudTests"
        )
    ]
)
