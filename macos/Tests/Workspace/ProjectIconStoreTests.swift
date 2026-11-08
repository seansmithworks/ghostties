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

    // MARK: - Generation token

    @Test func forgetDuringInFlightRefreshLeavesNothingBehind() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        try ProjectIconFixtures.writePNG(root, "icon.png")
        let project = rig.project(root: root)

        let inFlight = _Concurrency.Task { await rig.store.refresh(project) }
        await _Concurrency.Task.yield() // refresh is now suspended on its resolve
        rig.store.forget(projectId: project.id)
        await inFlight.value

        for ext in ["png", "key", "none"] {
            #expect(!rig.exists(rig.cache, project.id, ext))
        }
        #expect(rig.store.image(for: project.id) == nil)
    }

    @Test func forgetDuringInFlightOverrideDoesNotRecreateIt() async throws {
        let rig = try Rig()
        let picked = try ProjectIconFixtures.makeRoot("picked")
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: picked)
        }
        let original = try ProjectIconFixtures.writePNG(picked, "mine.png")
        let id = UUID()

        let inFlight = _Concurrency.Task { try? await rig.store.setOverride(projectId: id, from: original) }
        await _Concurrency.Task.yield()
        rig.store.forget(projectId: id)
        _ = await inFlight.value

        #expect(!rig.exists(rig.support, id, "png"))
        #expect(rig.store.image(for: id) == nil)
    }

    @Test func staleAutoRefreshDoesNotOverwriteNewerMonogramChoice() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        try ProjectIconFixtures.writePNG(root, "icon.png")
        let auto = rig.project(root: root)
        var mono = auto
        mono.iconStyle = .monogram

        let inFlight = _Concurrency.Task { await rig.store.refresh(auto) }
        await _Concurrency.Task.yield()
        await rig.store.refresh(mono)
        await inFlight.value

        #expect(rig.store.image(for: auto.id) == nil)
    }

    @Test func truncatedWalkDoesNotWriteNegativeCache() async throws {
        let rig = try Rig()
        let root = try ProjectIconFixtures.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rig.base)
            try? FileManager.default.removeItem(at: root)
        }
        for i in 0..<20 {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("dir\(i)"), withIntermediateDirectories: true
            )
        }
        var limits = ProjectIconResolver.Limits()
        limits.maxEntries = 3
        let store = ProjectIconStore(cacheDirectory: rig.cache, supportDirectory: rig.support, limits: limits)
        let project = rig.project(root: root)

        await store.refresh(project)
        await store.refresh(project)

        #expect(!rig.exists(rig.cache, project.id, "none"))
        #expect(store.resolverRuns == 2, "a truncated walk must be retried, not negatively cached")
    }
}
