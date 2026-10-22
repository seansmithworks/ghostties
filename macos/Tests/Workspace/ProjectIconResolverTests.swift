import Foundation
import Testing
@testable import Ghostty

/// Integration tests for `ProjectIconResolver` over temp fixture directories.
struct ProjectIconResolverTests {
    private func winner(_ root: URL) -> String? {
        ProjectIconResolver.resolve(root: root)?.source.url.path
            .replacingOccurrences(of: root.path + "/", with: "")
    }

    @Test func candidatesWinInPriorityOrder() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Lowest priority first; each removal promotes the next.
        let ordered = [
            "icon.png",
            "favicon.ico",
            "favicon.png",
            "public/favicon.png",
            "src/app/icon.png",
            "app/apple-icon.png",
            "app/icon.png",
            "Sources/Assets.xcassets/AppIcon.appiconset/big.png",
            "public/apple-touch-icon.png",
        ]
        for rel in ordered where !rel.contains("xcassets") && rel != "favicon.ico" {
            try ProjectIconFixtures.writePNG(root, rel)
        }
        try ProjectIconFixtures.write(root, "favicon.ico", data: ProjectIconFixtures.pngData())
        try ProjectIconFixtures.writeAppIconSet(
            root, under: "Sources/Assets.xcassets/AppIcon.appiconset",
            entries: [("big.png", "512x512", "1x", 128)]
        )

        for expected in ordered.reversed() {
            #expect(winner(root) == expected)
            try FileManager.default.removeItem(at: root.appendingPathComponent(expected))
        }
        #expect(winner(root) == nil)
    }

    @Test func appIconSetPicksLargestPixelSize() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectIconFixtures.writeAppIconSet(
            root, under: "App/Assets.xcassets/AppIcon.appiconset",
            entries: [
                ("small.png", "16x16", "2x", 32),
                ("huge.png", "512x512", "2x", 128),
                ("mid.png", "128x128", "1x", 128),
            ]
        )
        #expect(winner(root) == "App/Assets.xcassets/AppIcon.appiconset/huge.png")
    }

    @Test func oversizeFileIsRejected() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var big = ProjectIconFixtures.pngData()
        big.append(Data(count: 1_100_000)) // valid PNG + trailing padding > 1 MB
        try ProjectIconFixtures.write(root, "public/apple-touch-icon.png", data: big)
        try ProjectIconFixtures.writePNG(root, "icon.png")
        #expect(winner(root) == "icon.png")
    }

    @Test func symlinkEscapingRootIsRejected() throws {
        let root = try ProjectIconFixtures.makeRoot()
        let outside = try ProjectIconFixtures.makeRoot("outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let target = try ProjectIconFixtures.writePNG(outside, "secret.png")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("public"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("public/apple-touch-icon.png"), withDestinationURL: target
        )
        #expect(winner(root) == nil)
        try ProjectIconFixtures.writePNG(root, "icon.png")
        #expect(winner(root) == "icon.png")
    }

    @Test func symlinkInsideRootIsAccepted() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try ProjectIconFixtures.writePNG(root, "brand/logo.png")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("public"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("public/apple-touch-icon.png"), withDestinationURL: target
        )
        #expect(ProjectIconResolver.resolve(root: root) != nil)
    }

    @Test func skippedDirectoriesAreNotSearched() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for skipped in ["node_modules", ".git", "build", "DerivedData", "Pods", ".build"] {
            try ProjectIconFixtures.writeAppIconSet(
                root, under: "\(skipped)/Assets.xcassets/AppIcon.appiconset",
                entries: [("a.png", "512x512", "1x", 64)]
            )
        }
        #expect(winner(root) == nil)
    }

    @Test func deepAppIconSetBeyondDepthFourIsNotFound() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectIconFixtures.writeAppIconSet(
            root, under: "a/b/c/d/Assets.xcassets/AppIcon.appiconset",
            entries: [("a.png", "512x512", "1x", 64)]
        )
        #expect(winner(root) == nil)
    }

    @Test func undecodableCandidateFallsThrough() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectIconFixtures.write(root, "public/apple-touch-icon.png", data: Data("not an image".utf8))
        try ProjectIconFixtures.writePNG(root, "icon.png")
        #expect(winner(root) == "icon.png")
    }

    @Test func thumbnailIsCappedAt128() throws {
        let root = try ProjectIconFixtures.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectIconFixtures.writePNG(root, "icon.png", pixels: 400)
        let hit = try #require(ProjectIconResolver.resolve(root: root))
        #expect(max(hit.image.width, hit.image.height) <= 128)
    }

    @Test func missingRootIsNil() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(ProjectIconResolver.resolve(root: url) == nil)
    }
}
