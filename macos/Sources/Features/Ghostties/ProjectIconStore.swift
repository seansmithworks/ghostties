import AppKit
import Combine
import Foundation
import GhosttiesCore
import ImageIO
import UniformTypeIdentifiers

/// Owns the 128px icon image for each project. `ProjectTileView` reads it;
/// `ProjectIconRefresh` keeps it current.
///
/// Resolution happens off the main thread on a utility queue and never on a
/// render path: views call `image(for:)`, which is an in-memory lookup only,
/// and listen to `changes` to re-read after a refresh.
///
/// Concurrency model: one generation token per project. Every `refresh`,
/// `forget`, and a landing `setOverride`, bumps it. Background work only
/// computes (it returns a plan and never touches the cache or the
/// override); the plan is applied on the main actor, and only if the token
/// it started with is still current. A late result from a superseded
/// refresh, or from before a `forget`, is dropped. `forget` keeps the
/// bumped token as a tombstone.
///
/// A chosen image (`setOverride`) has its own token, bumped by a newer
/// choice, by any other style change (`styleDidChange`) and by `forget`:
/// the caller sets `iconStyle = .file` first, and the refresh that style
/// change sets off runs while the image is still being normalized, so a
/// refresh alone must not cancel it, but picking Auto or Monogram must.
///
/// A forced refresh (past the negative cache) stays forced until a refresh
/// lands: a refresh that supersedes it is forced too, so the sidebar's
/// own refresh for the same change can't drop the re-check.
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
    private let limits: ProjectIconResolver.Limits
    /// A dictionary, not NSCache: NSCache may evict under memory pressure, which
    /// would silently turn a project back into its monogram. 128px per project is tiny.
    private var memory: [UUID: NSImage] = [:]
    private var generations: [UUID: Int] = [:]
    private var overrideTokens: [UUID: Int] = [:]
    /// Projects with a forced refresh that hasn't landed yet.
    private var pendingForce: Set<UUID> = []
    private static let queue = DispatchQueue(label: "ghostties.project-icons", qos: .utility)

    /// Directories are the final `project-icons` folders. Defaults:
    /// `~/Library/Caches/<bundle id>/project-icons` and
    /// `<Application Support state dir>/project-icons`.
    init(
        cacheDirectory: URL? = nil,
        supportDirectory: URL? = nil,
        now: @escaping () -> Date = Date.init,
        limits: ProjectIconResolver.Limits = ProjectIconResolver.Limits()
    ) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Ghostties", isDirectory: true)
            .appendingPathComponent("project-icons", isDirectory: true)
        self.supportDirectory = supportDirectory ?? WorkspacePersistence.directory
            .appendingPathComponent("project-icons", isDirectory: true)
        self.now = now
        self.limits = limits
    }

    // MARK: - Reading

    /// In-memory lookup only. Nil means "draw the monogram".
    func image(for projectId: UUID) -> NSImage? {
        memory[projectId]
    }

    // MARK: - Generation token

    private func bump(_ id: UUID) -> Int {
        let next = (generations[id] ?? 0) + 1
        generations[id] = next
        return next
    }

    private func isCurrent(_ id: UUID, _ generation: Int) -> Bool {
        generations[id] == generation
    }

    // MARK: - Refresh

    /// Fire-and-forget refresh for launch, project add, and Settings open.
    func refreshInBackground(_ project: Project, force: Bool = false) {
        _Concurrency.Task { await refresh(project, force: force) }
    }

    /// Recomputes the effective image for `project` off the main thread.
    /// `force` skips the negative cache, which otherwise hides an icon
    /// added under the root for up to `negativeCacheTTL` (Settings open,
    /// and its Auto button, force).
    func refresh(_ project: Project, force: Bool = false) async {
        let id = project.id
        let force = force || pendingForce.contains(id)
        if force { pendingForce.insert(id) }
        let generation = bump(id)
        let cacheDir = cacheDirectory
        let supportDir = supportDirectory
        let root = URL(fileURLWithPath: project.rootPath, isDirectory: true)
        let clock = now()
        let limits = limits

        switch project.iconStyle ?? .auto {
        case .monogram:
            pendingForce.remove(id)
            setImage(nil, for: id)
            return
        case .file:
            let override = await Self.onQueue { Self.loadPNG(Self.file(supportDir, id, "png")) }
            guard isCurrent(id, generation) else { return }
            if let override {
                pendingForce.remove(id)
                setImage(override.image, for: id)
                return
            }
            // Override file missing: fall through to auto-detection.
        case .auto:
            break
        }

        let outcome = await Self.onQueue {
            Self.resolveOnDisk(root: root, id: id, dir: cacheDir, now: clock, limits: limits, force: force)
        }
        if outcome.ranResolver { resolverRuns += 1 }
        guard isCurrent(id, generation) else { return }
        pendingForce.remove(id)
        apply(outcome.plan, in: cacheDir)
        setImage(outcome.image?.image, for: id)
    }

    // MARK: - Style change

    /// `project.iconStyle` just changed (Settings). Cancels a chosen image
    /// still being copied, deletes the copy unless the style is `.file`,
    /// and refreshes. The cancel and delete happen now, before this
    /// returns; the task is the refresh.
    @discardableResult
    func styleDidChange(_ project: Project, force: Bool = false) -> _Concurrency.Task<Void, Never> {
        let id = project.id
        overrideTokens[id] = (overrideTokens[id] ?? 0) + 1
        if project.iconStyle != .file {
            try? FileManager.default.removeItem(at: Self.file(supportDirectory, id, "png"))
        }
        return _Concurrency.Task { await refresh(project, force: force) }
    }

    // MARK: - Override

    /// Normalizes the chosen image to <=128px PNG and copies it into
    /// Application Support. Set `iconStyle = .file` before calling: a
    /// refresh while this runs doesn't cancel it (see the type's doc), and
    /// landing supersedes any refresh still in flight. A newer choice, any
    /// other style change (`styleDidChange`), or the project's removal
    /// drops this one.
    func setOverride(projectId: UUID, from source: URL) async throws {
        let token = (overrideTokens[projectId] ?? 0) + 1
        overrideTokens[projectId] = token
        let decoded = await Self.onQueue { () -> Decoded? in
            guard let cg = ProjectIconResolver.normalizedThumbnail(fromFileAt: source),
                  let data = Self.pngData(cg) else { return nil }
            return Decoded(image: cg, png: data)
        }
        guard let decoded else { throw StoreError.unreadableImage }
        guard overrideTokens[projectId] == token else { return }
        _ = bump(projectId)
        pendingForce.remove(projectId) // the refresh this supersedes never lands
        apply(Plan(writes: [(Self.file(supportDirectory, projectId, "png"), decoded.png)], removals: []),
              in: supportDirectory)
        setImage(decoded.image, for: projectId)
    }

    // MARK: - Removal

    /// Deletes every cached file and the override for a removed project, and
    /// invalidates any in-flight work for it.
    func forget(projectId id: UUID) {
        _ = bump(id) // tombstone: late results from before this call are dropped
        overrideTokens[id] = (overrideTokens[id] ?? 0) + 1
        pendingForce.remove(id)
        for ext in ["png", "key", "none"] {
            try? FileManager.default.removeItem(at: Self.file(cacheDirectory, id, ext))
        }
        try? FileManager.default.removeItem(at: Self.file(supportDirectory, id, "png"))
        setImage(nil, for: id)
    }

    // MARK: - Internals

    private func setImage(_ cg: CGImage?, for id: UUID) {
        if let cg {
            memory[id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else {
            memory[id] = nil
        }
        changes.send(id)
    }

    /// Small file writes decided by background work, applied on the main actor
    /// only while the project's generation is current.
    private struct Plan: Sendable {
        var writes: [(URL, Data)]
        var removals: [URL]
    }

    private func apply(_ plan: Plan, in directory: URL) {
        let fm = FileManager.default
        for url in plan.removals { try? fm.removeItem(at: url) }
        guard !plan.writes.isEmpty else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (url, data) in plan.writes { try? data.write(to: url, options: .atomic) }
    }

    /// CGImage is immutable; the box lets it cross the queue boundary.
    private struct ImageBox: @unchecked Sendable { let image: CGImage }

    private struct Decoded: @unchecked Sendable {
        let image: CGImage
        let png: Data
    }

    private struct Outcome: @unchecked Sendable {
        var image: ImageBox?
        var ranResolver: Bool
        var plan = Plan(writes: [], removals: [])
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
    /// the resolver. Runs on the utility queue and only reads; it returns the
    /// cache writes for the main actor to apply if still current.
    private nonisolated static func resolveOnDisk(
        root: URL, id: UUID, dir: URL, now: Date, limits: ProjectIconResolver.Limits, force: Bool
    ) -> Outcome {
        let rootMtime = mtime(of: root)
        let noneURL = file(dir, id, "none")
        let pngURL = file(dir, id, "png")
        let keyURL = file(dir, id, "key")

        // Negative cache: same root mtime, checked within the TTL.
        if !force, let rootMtime,
           let text = try? String(contentsOf: noneURL, encoding: .utf8) {
            let parts = text.split(separator: "\n").compactMap { Double($0) }
            if parts.count == 2, parts[0] == rootMtime, now.timeIntervalSince1970 - parts[1] < negativeCacheTTL {
                return Outcome(image: nil, ranResolver: false)
            }
        }

        let storedKey = try? String(contentsOf: keyURL, encoding: .utf8)
        var servedFromCache = false
        let resolution = ProjectIconResolver.resolveDetailed(root: root, limits: limits) { candidate in
            if storedKey == keyString(for: candidate), let cached = loadPNG(pngURL) {
                servedFromCache = true
                return cached.image
            }
            return candidate.thumbnail()
        }

        switch resolution {
        case .truncated:
            // Unproven absence: show nothing now, cache nothing, retry next time.
            return Outcome(image: nil, ranResolver: true)
        case .none:
            var plan = Plan(writes: [], removals: [pngURL, keyURL])
            if let rootMtime {
                let text = "\(rootMtime)\n\(now.timeIntervalSince1970)"
                plan.writes.append((noneURL, Data(text.utf8)))
            }
            return Outcome(image: nil, ranResolver: true, plan: plan)
        case .hit(let hit):
            var plan = Plan(writes: [], removals: [noneURL])
            if !servedFromCache, let data = pngData(hit.image) {
                plan.writes.append((pngURL, data))
                plan.writes.append((keyURL, Data(keyString(for: hit.source).utf8)))
            }
            return Outcome(image: ImageBox(image: hit.image), ranResolver: true, plan: plan)
        }
    }
}
