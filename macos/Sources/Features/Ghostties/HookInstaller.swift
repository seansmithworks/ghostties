import Foundation
import OSLog

/// Seeds the `ghostties-status.sh` Claude Code hook script to
/// `~/.ghostties/hooks/` so Sean can register it in `~/.claude/settings.json`.
///
/// Modeled on `PresetLoader.seedIfNeeded()`, with one deliberate divergence:
/// `PresetLoader` never overwrites files that already exist, because preset
/// files are user-editable content. This script is app-owned — Sean never
/// hand-edits it — so on a version bump the seeded copy is OVERWRITTEN
/// rather than left alone. That is required for a hook bugfix to ever reach
/// an already-seeded machine.
///
/// Unlike `PresetLoader`, a missing bundle resource does NOT write the
/// version marker, so seeding retries on every launch — deliberate, do not
/// "fix" back.
struct HookInstaller {
    static let hooksDirectoryPath = ("~/.ghostties/hooks" as NSString).expandingTildeInPath

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ghostties",
        category: "HookInstaller"
    )

    // MARK: - Public API

    /// Current seed version. Bump this when `ghostties-status.sh` changes to
    /// trigger re-seeding (and overwrite any previously-seeded copy).
    static let seedVersion = 1

    /// Name of the bundled/seeded hook script.
    static let scriptName = "ghostties-status.sh"

    /// Full path to the seeded script at `~/.ghostties/hooks/ghostties-status.sh`.
    static var scriptPath: String {
        (hooksDirectoryPath as NSString).appendingPathComponent(scriptName)
    }

    /// Seed the bundled hook script to `~/.ghostties/hooks/` using versioned
    /// seeding. Unlike `PresetLoader`, this OVERWRITES the destination when
    /// the seed version advances, because the script is app-owned.
    static func seedIfNeeded() {
        let signpostState = Perf.signposter.beginInterval("hooks.seed")
        defer { Perf.signposter.endInterval("hooks.seed", signpostState) }

        guard let bundledScriptURL = Bundle.main.resourceURL?
            .appendingPathComponent("hooks")
            .appendingPathComponent(scriptName) else {
            logger.warning("No bundled hooks directory found in app bundle")
            return
        }

        _ = seed(from: bundledScriptURL, into: hooksDirectoryPath, version: seedVersion)
    }

    // MARK: - Seed Helpers

    /// Seed `sourceURL.lastPathComponent` into `directoryPath`, gated by a
    /// `.seed-version` marker file. Returns `true` if a (re)seed occurred.
    ///
    /// Extracted from `seedIfNeeded()` so tests can exercise the real seeding
    /// logic against a temp directory and a temp source file, without needing
    /// `Bundle.main`.
    @discardableResult
    static func seed(from sourceURL: URL, into directoryPath: String, version: Int) -> Bool {
        let fm = FileManager.default
        let versionFilePath = (directoryPath as NSString).appendingPathComponent(".seed-version")

        // Check the current seed version.
        let currentVersion: Int
        if let versionData = fm.contents(atPath: versionFilePath),
           let versionString = String(data: versionData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsedVersion = Int(versionString) {
            currentVersion = parsedVersion
        } else {
            currentVersion = 0
        }

        let destPath = (directoryPath as NSString).appendingPathComponent(sourceURL.lastPathComponent)

        // Skip if already at or above the current seed version — unless the
        // seeded script itself has gone missing (e.g. deleted by hand), in
        // which case we must reseed even at the same version.
        guard currentVersion < version || !fm.fileExists(atPath: destPath) else { return false }

        // Create the destination directory if it doesn't exist.
        if !fm.fileExists(atPath: directoryPath) {
            do {
                try fm.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o700,
                ])
            } catch {
                logger.error("Failed to create hooks directory: \(error.localizedDescription)")
                return false
            }
        }

        // App-owned: copy to a temp path first and replace atomically, so a
        // failed copy never leaves the destination with no script at all.
        let tmpPath = destPath + ".tmp"
        if fm.fileExists(atPath: tmpPath) {
            try? fm.removeItem(atPath: tmpPath)
        }

        do {
            try fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: tmpPath))
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tmpPath)
            _ = try fm.replaceItemAt(URL(fileURLWithPath: destPath), withItemAt: URL(fileURLWithPath: tmpPath))
        } catch {
            logger.error("Failed to seed hook script: \(error.localizedDescription)")
            try? fm.removeItem(atPath: tmpPath)
            return false
        }

        // Write the new seed version marker.
        do {
            try "\(version)".write(toFile: versionFilePath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write seed version marker: \(error.localizedDescription)")
        }

        return true
    }
}
