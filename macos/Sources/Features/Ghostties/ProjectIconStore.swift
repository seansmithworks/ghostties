import AppKit
import Combine
import Foundation
import GhosttiesCore
import ImageIO
import UniformTypeIdentifiers

/// Owns the 128px icon image for each project. Not wired into any view yet.
///
/// Resolution happens off the main thread on a utility queue and never on a
/// render path: views call `image(for:)`, which is an in-memory lookup only,
/// and listen to `changes` to re-read after a refresh.
///
/// On disk:
/// - `<caches>/project-icons/<id>.png`  resolved icon (a cache; safe to delete)
/// - `<caches>/project-icons/<id>.key`  source path + mtime + size the PNG came from
/// - `<caches>/project-icons/<id>.none` negative cache: "no icon at this root",
///   keyed on the root's mtime and expiring after 24 hours
/// - `<support>/project-icons/<id>.png` the user's `.file` choice, normalized
///   and copied; the original path is never referenced again
@MainActor
final class ProjectIconStore {
    static let shared = ProjectIconStore()

    static let negativeCacheTTL: TimeInterval = 24 * 60 * 60

    enum StoreError: Error { case unreadableImage }

    /// Emits a project id whenever its image may have changed.
    let changes = PassthroughSubject<UUID, Never>()

    /// How many times the resolver actually walked a project root (negative-cache
    /// hits don't count). Exposed for tests.
    private(set) var resolverRuns = 0

    private let cacheDirectory: URL
    private let supportDirectory: URL
    private let now: () -> Date
    private let memory = NSCache<NSString, NSImage>()
    private static let queue = DispatchQueue(label: "ghostties.project-icons", qos: .utility)

    /// Directories are the final `project-icons` folders. Defaults:
    /// `~/Library/Caches/<bundle id>/project-icons` and
    /// `<Application Support state dir>/project-icons`.
    init(cacheDirectory: URL? = nil, supportDirectory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Ghostties", isDirectory: true)
            .appendingPathComponent("project-icons", isDirectory: true)
        self.supportDirectory = supportDirectory ?? WorkspacePersistence.directory
            .appendingPathComponent("project-icons", isDirectory: true)
        self.now = now
    }

    // MARK: - Reading

    /// In-memory lookup only. Nil means "draw the monogram".
    func image(for projectId: UUID) -> NSImage? {
        memory.object(forKey: projectId.uuidString as NSString)
    }

    // MARK: - Refresh

    /// Fire-and-forget refresh for launch, project add, and Settings open.
    func refreshInBackground(_ project: Project) {
        _Concurrency.Task { await refresh(project) }
    }

    /// Recomputes the effective image for `project` off the main thread.
    func refresh(_ project: Project) async {
        let id = project.id
        let cacheDir = cacheDirectory
        let supportDir = supportDirectory
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let clock = now()

        switch project.iconStyle ?? .auto {
        case .monogram:
            setImage(nil, for: id)
            return
        case .file:
            let override = await Self.onQueue { Self.loadPNG(Self.file(supportDir, id, "png")) }
            if let override {
                setImage(override.image, for: id)
                return
            }
            // Override file missing: fall through to auto-detection.
        case .auto:
            break
        }

        let outcome = await Self.onQueue { Self.resolveOnDisk(root: root, id: id, dir: cacheDir, now: clock) }
        if outcome.ranResolver { resolverRuns += 1 }
        setImage(outcome.image?.image, for: id)
    }

    // MARK: - Override

    /// Normalizes the chosen image to <=128px PNG and copies it into
    /// Application Support. The caller then sets `iconStyle = .file`.
    func setOverride(projectId: UUID, from source: URL) async throws {
        let target = Self.file(supportDirectory, projectId, "png")
        let dir = supportDirectory
        let box = await Self.onQueue { () -> ImageBox? in
            guard let cg = ProjectIconResolver.normalizedThumbnail(fromFileAt: source),
                  let data = Self.pngData(cg) else { return nil }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard (try? data.write(to: target, options: .atomic)) != nil else { return nil }
            return ImageBox(image: cg)
        }
        guard let box else { throw StoreError.unreadableImage }
        setImage(box.image, for: projectId)
    }

    // MARK: - Removal

    /// Deletes every cached file and the override for a removed project.
    func forget(projectId id: UUID) {
        for ext in ["png", "key", "none"] {
            try? FileManager.default.removeItem(at: Self.file(cacheDirectory, id, ext))
        }
        try? FileManager.default.removeItem(at: Self.file(supportDirectory, id, "png"))
        setImage(nil, for: id)
    }

    // MARK: - Internals

    private func setImage(_ cg: CGImage?, for id: UUID) {
        let key = id.uuidString as NSString
        if let cg {
            memory.setObject(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), forKey: key)
        } else {
            memory.removeObject(forKey: key)
        }
        changes.send(id)
    }

    /// CGImage is immutable; the box lets it cross the queue boundary.
    private struct ImageBox: @unchecked Sendable { let image: CGImage }

    private struct Outcome: @unchecked Sendable {
        var image: ImageBox?
        var ranResolver: Bool
    }

    private nonisolated static func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private nonisolated static func file(_ dir: URL, _ id: UUID, _ ext: String) -> URL {
        dir.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    private nonisolated static func loadPNG(_ url: URL) -> ImageBox? {
        ProjectIconResolver.normalizedThumbnail(fromFileAt: url).map(ImageBox.init)
    }

    private nonisolated static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private nonisolated static func mtime(of url: URL) -> TimeInterval? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970
    }

    private nonisolated static func keyString(for source: ProjectIconResolver.Candidate) -> String {
        "\(source.url.path)\n\(source.mtime)\n\(source.size)"
    }

    /// The disk half of `refresh`: negative cache, source-keyed PNG cache, then
    /// the resolver. Runs on the utility queue.
    private nonisolated static func resolveOnDisk(root: URL, id: UUID, dir: URL, now: Date) -> Outcome {
        let fm = FileManager.default
        let rootMtime = mtime(of: root)
        let noneURL = file(dir, id, "none")
        let pngURL = file(dir, id, "png")
        let keyURL = file(dir, id, "key")

        // Negative cache: same root mtime, checked within the TTL.
        if let rootMtime,
           let text = try? String(contentsOf: noneURL, encoding: .utf8) {
            let parts = text.split(separator: "\n").compactMap { Double($0) }
            if parts.count == 2, parts[0] == rootMtime, now.timeIntervalSince1970 - parts[1] < negativeCacheTTL {
                return Outcome(image: nil, ranResolver: false)
            }
        }

        let storedKey = try? String(contentsOf: keyURL, encoding: .utf8)
        var servedFromCache = false
        let hit = ProjectIconResolver.resolve(root: root) { candidate in
            if storedKey == keyString(for: candidate), let cached = loadPNG(pngURL) {
                servedFromCache = true
                return cached.image
            }
            return candidate.thumbnail()
        }

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let hit else {
            try? fm.removeItem(at: pngURL)
            try? fm.removeItem(at: keyURL)
            if let rootMtime {
                try? "\(rootMtime)\n\(now.timeIntervalSince1970)".write(to: noneURL, atomically: true, encoding: .utf8)
            }
            return Outcome(image: nil, ranResolver: true)
        }
        try? fm.removeItem(at: noneURL)
        if !servedFromCache, let data = pngData(hit.image) {
            try? data.write(to: pngURL, options: .atomic)
            try? keyString(for: hit.source).write(to: keyURL, atomically: true, encoding: .utf8)
        }
        return Outcome(image: ImageBox(image: hit.image), ranResolver: true)
    }
}
