import Foundation
import ImageIO

/// Finds a project's own icon by looking at a fixed list of well-known files
/// under its root. Pure and read-only: it never writes, never executes
/// anything, and never follows a path out of the project root.
///
/// Candidate order (first decodable hit wins):
/// 1. `apple-touch-icon.png` in `public/ static/ web/ app/` then the root
/// 2. the largest PNG named by an `*.xcassets/AppIcon.appiconset/Contents.json`
///    (depth <= 4; build and dependency directories skipped)
/// 3. `app/icon.png`, `app/apple-icon.png`, `src/app/icon.png`
/// 4. `favicon.png` / `favicon.ico` in `public/ static/ assets/ web/ app/` then the root
/// 5. `icon.png` at the root
///
/// No SVG in v1.
///
/// Safety model: a file is opened first and judged second. The descriptor is
/// `fstat`ed (must be a regular file within the size cap) and `F_GETPATH`
/// must report a location inside the root, so a symlink swapped in after a
/// path check cannot redirect the read. Pixels are only ever decoded through
/// ImageIO's thumbnail path, capped at 128px.
enum ProjectIconResolver {
    static let maxThumbnailPixels = 128

    struct Limits {
        var maxFileBytes = 1_048_576
        var maxEntries = 2000
        var timeBudget: TimeInterval = 0.2
        /// Reject images whose declared pixel count exceeds this (decode-bomb guard).
        var maxSourcePixels = 16_000_000
    }

    /// A validated, already-read candidate file. `data` was read from the same
    /// descriptor that passed the checks.
    struct Candidate {
        let url: URL
        let mtime: TimeInterval
        let size: Int
        fileprivate let data: Data
        fileprivate let maxSourcePixels: Int

        /// Decodes through ImageIO's thumbnail path only. Nil if undecodable.
        func thumbnail(maxPixels: Int = ProjectIconResolver.maxThumbnailPixels) -> CGImage? {
            ProjectIconResolver.thumbnail(from: data, maxPixels: maxPixels, maxSourcePixels: maxSourcePixels)
        }
    }

    struct Hit {
        let source: Candidate
        let image: CGImage
    }

    enum Resolution {
        case hit(Hit)
        /// Searched everything reachable and found nothing.
        case none
        /// The walk hit its entry or time cap before finishing, so "nothing"
        /// is unproven. Callers must not cache this as a negative result.
        case truncated
    }

    static func resolve(
        root: URL,
        limits: Limits = Limits(),
        image: (Candidate) -> CGImage? = { $0.thumbnail() }
    ) -> Hit? {
        if case .hit(let hit) = resolveDetailed(root: root, limits: limits, image: image) { return hit }
        return nil
    }

    /// Resolves `root` to an icon. `image` turns a candidate into pixels; the
    /// default decodes it, and the store passes a closure that can answer from
    /// its on-disk cache without decoding. Returning nil rejects the candidate
    /// and moves on to the next.
    static func resolveDetailed(
        root: URL,
        limits: Limits = Limits(),
        image: (Candidate) -> CGImage? = { $0.thumbnail() }
    ) -> Resolution {
        guard let realRoot = localRealRoot(root) else { return .none }
        let deadline = ProcessInfo.processInfo.systemUptime + limits.timeBudget

        func attempt(_ path: String) -> Hit? {
            guard let candidate = readCandidate(path: path, realRoot: realRoot, limits: limits),
                  let pixels = image(candidate) else { return nil }
            return Hit(source: candidate, image: pixels)
        }

        func first(_ relatives: [String]) -> Hit? {
            for relative in relatives {
                if let hit = attempt(realRoot + "/" + relative) { return hit }
            }
            return nil
        }

        func inDirs(_ dirs: [String], _ names: [String]) -> [String] {
            dirs.flatMap { dir in names.map { dir.isEmpty ? $0 : "\(dir)/\($0)" } }
        }

        if let hit = first(inDirs(["public", "static", "web", "app", ""], ["apple-touch-icon.png"])) {
            return .hit(hit)
        }
        let walk = appIconSets(realRoot: realRoot, limits: limits, deadline: deadline)
        for set in walk.sets {
            for file in largestFirstFilenames(inSetAt: set, realRoot: realRoot, limits: limits) {
                if let hit = attempt(set + "/" + file) { return .hit(hit) }
            }
        }
        if let hit = first(["app/icon.png", "app/apple-icon.png", "src/app/icon.png"]) { return .hit(hit) }
        if let hit = first(inDirs(["public", "static", "assets", "web", "app", ""], ["favicon.png", "favicon.ico"])) {
            return .hit(hit)
        }
        if let hit = first(["icon.png"]) { return .hit(hit) }
        return walk.truncated ? .truncated : .none
    }

    // MARK: - Root

    /// The root's real path, or nil when it is missing, not local, or ubiquitous.
    private static func localRealRoot(_ root: URL) -> String? {
        // `realpath`, not `resolvingSymlinksInPath`: Foundation rewrites
        // /private/var to /var, but F_GETPATH reports the /private form.
        guard let resolved = realpath(root.path, nil) else { return nil }
        defer { free(resolved) }
        let real = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        guard let values = try? real.resourceValues(forKeys: [
            .isDirectoryKey, .volumeIsLocalKey, .isUbiquitousItemKey,
        ]), values.isDirectory == true,
        values.volumeIsLocal ?? false,
        !(values.isUbiquitousItem ?? false) else { return nil }
        // Take the root's spelling from the same API that later judges each
        // file (F_GETPATH), so case-insensitive volumes compare like with like.
        let fd = open(real.path, O_RDONLY | O_DIRECTORY | O_NOCTTY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Reading

    /// Open by descriptor, then judge: regular file, within the size cap, and
    /// actually located inside the root.
    private static func readCandidate(path: String, realRoot: String, limits: Limits) -> Candidate? {
        guard let file = readFile(path: path, realRoot: realRoot, maxBytes: limits.maxFileBytes) else { return nil }
        return Candidate(
            url: URL(fileURLWithPath: file.path), mtime: file.mtime, size: file.data.count,
            data: file.data, maxSourcePixels: limits.maxSourcePixels
        )
    }

    private static func readFile(
        path: String, realRoot: String, maxBytes: Int
    ) -> (data: Data, path: String, mtime: TimeInterval)? {
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              st.st_size > 0, Int(st.st_size) <= maxBytes else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        let actual = String(cString: buffer)
        guard actual.hasPrefix(realRoot + "/") else { return nil }

        var data = Data(capacity: Int(st.st_size))
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= maxBytes {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 { return nil }
            if n == 0 { break }
            data.append(chunk, count: n)
        }
        guard !data.isEmpty, data.count <= maxBytes else { return nil }

        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        return (data, actual, mtime)
    }

    // MARK: - AppIcon.appiconset

    private static let skippedDirectories: Set<String> = [
        "node_modules", ".git", "build", "DerivedData", "Pods", ".build",
    ]

    /// `AppIcon.appiconset` directories inside an `*.xcassets`, depth <= 4,
    /// bounded by entry count and wall-clock budget. Sorted for determinism.
    private static func appIconSets(realRoot: String, limits: Limits, deadline: TimeInterval) -> (sets: [String], truncated: Bool) {
        let rootURL = URL(fileURLWithPath: realRoot, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return ([], false) }

        var found: [String] = []
        var seen = 0
        var truncated = false
        while let url = walker.nextObject() as? URL {
            seen += 1
            if seen > limits.maxEntries || ProcessInfo.processInfo.systemUptime > deadline {
                truncated = true
                break
            }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let name = url.lastPathComponent
            if skippedDirectories.contains(name) { walker.skipDescendants(); continue }
            if name == "AppIcon.appiconset" {
                if walker.level <= 4, url.deletingLastPathComponent().pathExtension == "xcassets" {
                    found.append(url.path)
                }
                walker.skipDescendants()
                continue
            }
            if walker.level >= 4 { walker.skipDescendants() }
        }
        return (found.sorted(), truncated)
    }

    /// Filenames from `Contents.json`, largest pixel size first. Only PNGs.
    private static func largestFirstFilenames(inSetAt set: String, realRoot: String, limits: Limits) -> [String] {
        guard let file = readFile(path: set + "/Contents.json", realRoot: realRoot, maxBytes: limits.maxFileBytes),
              let root = try? JSONSerialization.jsonObject(with: file.data) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else { return [] }

        let entries: [(name: String, pixels: Int)] = images.compactMap { entry in
            guard let name = entry["filename"] as? String,
                  name.lowercased().hasSuffix(".png"),
                  !name.contains("/") else { return nil }
            let points = (entry["size"] as? String)
                .flatMap { $0.split(separator: "x").first }
                .flatMap { Double($0) } ?? 0
            let scale = (entry["scale"] as? String)
                .flatMap { Double($0.replacingOccurrences(of: "x", with: "")) } ?? 1
            return (name, Int(points * scale))
        }
        return entries.sorted { $0.pixels != $1.pixels ? $0.pixels > $1.pixels : $0.name < $1.name }.map(\.name)
    }

    // MARK: - Decode

    /// The only place pixels are decoded: ImageIO thumbnail, never the full image.
    fileprivate static func thumbnail(from data: Data, maxPixels: Int, maxSourcePixels: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }

        // ICO and friends hold several frames; take the largest one.
        var bestIndex = 0
        var bestArea = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int else { continue }
            if w * h > maxSourcePixels { return nil }
            if w * h > bestArea { bestArea = w * h; bestIndex = index }
        }
        guard bestArea > 0 else { return nil }

        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, bestIndex, thumbOptions)
    }

    /// Decode a user-chosen image (the `.file` override) the same way.
    static func normalizedThumbnail(fromFileAt url: URL, maxBytes: Int = 20_000_000) -> CGImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= maxBytes else { return nil }
        return thumbnail(from: data, maxPixels: maxThumbnailPixels, maxSourcePixels: Limits().maxSourcePixels)
    }
}
