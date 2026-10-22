import AppKit
import Foundation
import GhosttiesCore
import Testing
@testable import Ghostty

/// Integration tests for `ProjectIconStore`. Cache and support directories are
/// injected temp dirs; nothing touches the real Caches or Application Support.
@MainActor
struct ProjectIconStoreTests {
    @MainActor private struct Rig {
        let base: URL
        let cache: URL
        let support: URL
        let store: ProjectIconStore

        init() throws {
            base = try ProjectIconFixtures.makeRoot("store")
            cache = base.appendingPathComponent("cache", isDirectory: true)
            support = base.appendingPathComponent("support", isDirectory: true)
            store = ProjectIconStore(cacheDirectory: cache, supportDirectory: support)
        }

        func project(root: URL, style: ProjectIconStyle? = nil) -> Project {
            Project(name: "fixture", rootPath: root.path, iconStyle: style)
        }

        func exists(_ dir: URL, _ id: UUID, _ ext: String) -> Bool {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id.uuidString).\(ext)").path)
        }
    }

    @Test func resolvesAndCachesPNG() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        try ProjectIconFixtures.writePNG(root, "public/apple-touch-icon.png", pixels: 300)
        let project = rig.project(root: root)

        await rig.store.refresh(project)

        let image = try #require(rig.store.image(for: project.id))
        #expect(max(image.size.width, image.size.height) <= 128)
        #expect(rig.exists(rig.cache, project.id, "png"))
    }

    @Test func noIconIsNilAndSecondCallHitsNegativeCache() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        let project = rig.project(root: root)

        await rig.store.refresh(project)
        #expect(rig.store.image(for: project.id) == nil)
        #expect(rig.store.resolverRuns == 1)

        await rig.store.refresh(project)
        #expect(rig.store.image(for: project.id) == nil)
        #expect(rig.store.resolverRuns == 1, "second call must be served by the negative cache")
    }

    @Test func negativeCacheExpiresAfterTTL() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        var clock = Date()
        let store = ProjectIconStore(
            cacheDirectory: rig.cache, supportDirectory: rig.support, now: { clock }
        )
        let project = rig.project(root: root)
        await store.refresh(project)
        clock = clock.addingTimeInterval(25 * 3600)
        await store.refresh(project)
        #expect(store.resolverRuns == 2)
    }

    @Test func monogramStyleShowsNoImage() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        try ProjectIconFixtures.writePNG(root, "icon.png")
        let project = rig.project(root: root, style: .monogram)
        await rig.store.refresh(project)
        #expect(rig.store.image(for: project.id) == nil)
    }

    @Test func fileOverrideIsNormalizedAndCopiedNotReferenced() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        let picked = try ProjectIconFixtures.makeRoot("picked")
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: picked)
        }
        let original = try ProjectIconFixtures.writePNG(picked, "mine.png", pixels: 512)
        let project = rig.project(root: root, style: .file)

        try await rig.store.setOverride(projectId: project.id, from: original)
        try FileManager.default.removeItem(at: original) // original path must not matter

        await rig.store.refresh(project)
        let image = try #require(rig.store.image(for: project.id))
        #expect(max(image.size.width, image.size.height) <= 128)
        #expect(rig.exists(rig.support, project.id, "png"))
    }

    @Test func removalDeletesCacheAndOverrideFiles() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        let picked = try ProjectIconFixtures.makeRoot("picked")
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: picked)
        }
        try ProjectIconFixtures.writePNG(root, "icon.png")
        let project = rig.project(root: root)
        await rig.store.refresh(project)
        try await rig.store.setOverride(
            projectId: project.id, from: try ProjectIconFixtures.writePNG(picked, "mine.png")
        )
        #expect(rig.exists(rig.cache, project.id, "png"))
        #expect(rig.exists(rig.support, project.id, "png"))

        rig.store.forget(projectId: project.id)

        for ext in ["png", "key", "none"] {
            #expect(!rig.exists(rig.cache, project.id, ext))
        }
        #expect(!rig.exists(rig.support, project.id, "png"))
        #expect(rig.store.image(for: project.id) == nil)
    }
}
