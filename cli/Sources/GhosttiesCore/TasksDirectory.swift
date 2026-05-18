import Foundation

/// Locate `.ghostties/tasks/` by walking up from cwd, git-style. Stops at
/// `$HOME` or `/` — no global fallback, no magic.
public enum TasksDirectory {

    /// Canonical global tasks directory: `~/.ghostties/tasks`.
    ///
    /// Used as the default for MCP server registration and app-level fallback
    /// when no project-local `.ghostties/tasks/` is found.
    public static let globalDefault: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/.ghostties/tasks"
    }()

    /// Create `~/.ghostties/tasks/` with 0o700 permissions if it doesn't exist.
    ///
    /// Throws a `CLIError.io` if the directory cannot be created.
    public static func findOrCreateGlobal() throws {
        let path = globalDefault
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        do {
            try fm.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700 as NSNumber]
            )
        } catch {
            throw CLIError.io("could not create \(path): \(error.localizedDescription)")
        }
    }
    /// Find an existing tasks directory. Returns nil if none is found up to
    /// $HOME or filesystem root.
    public static func find(startingAt cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL
        var cursor: URL? = cwd.standardizedFileURL

        while let here = cursor {
            let candidate = here.appendingPathComponent(".ghostties/tasks", isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }

            // Stop once we've checked $HOME itself, to avoid scanning siblings.
            if here.path == home.path { return nil }

            let parent = here.deletingLastPathComponent()
            if parent.path == here.path { return nil }
            cursor = parent
        }
        return nil
    }

    /// Find the directory, or throw a CLIError with the standard message.
    public static func require() throws -> URL {
        try require(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }

    /// Same as `require()` but takes an explicit starting directory. Use this
    /// from tests so they don't have to mutate process-global cwd.
    public static func require(startingAt cwd: URL) throws -> URL {
        guard let dir = find(startingAt: cwd) else {
            throw CLIError.notFound("no .ghostties/tasks/ in any ancestor. run 'gt new' to create one")
        }
        return dir
    }

    /// Resolve the directory for `gt new`, creating `./.ghostties/tasks/` in
    /// cwd if no ancestor already has one.
    public static func findOrCreate() throws -> URL {
        try findOrCreate(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    }

    /// Same as `findOrCreate()` but takes an explicit starting directory. Use
    /// this from tests so they don't have to mutate process-global cwd.
    public static func findOrCreate(startingAt cwd: URL) throws -> URL {
        if let existing = find(startingAt: cwd) { return existing }

        let target = cwd.appendingPathComponent(".ghostties/tasks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target,
                                                    withIntermediateDirectories: true)
        } catch {
            throw CLIError.io("could not create \(target.path): \(error.localizedDescription)")
        }
        return target
    }

    /// Resolve the `.ghostties/` parent of the tasks directory (for `.focus`).
    public static func stateDirectory(from tasksDir: URL) -> URL {
        tasksDir.deletingLastPathComponent()
    }
}
