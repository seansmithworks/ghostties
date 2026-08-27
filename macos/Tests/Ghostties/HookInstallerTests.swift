import Foundation
import Testing
@testable import Ghostty

/// Coverage for `HookInstaller.seed(from:into:version:)` (session-row-status
/// spec, Phase 1). Exercises the real seeding logic against a temp directory
/// and a temp source script, without needing `Bundle.main`.
struct HookInstallerTests {

    /// Write a fixture "source" hook script to a fresh temp file and return
    /// its URL. Caller owns cleanup.
    private func makeSourceScript(contents: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookInstallerTests-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(HookInstaller.scriptName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDestDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookInstallerTests-dest-\(UUID().uuidString)")
        return dir.path
    }

    @Test
    func testSeedWritesExecutableHookScript() throws {
        let sourceURL = try makeSourceScript()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let destDir = makeDestDirectory()
        defer { try? FileManager.default.removeItem(atPath: destDir) }

        let seeded = HookInstaller.seed(from: sourceURL, into: destDir, version: 1)
        #expect(seeded)

        let destPath = (destDir as NSString).appendingPathComponent(HookInstaller.scriptName)
        #expect(FileManager.default.fileExists(atPath: destPath))

        let attrs = try FileManager.default.attributesOfItem(atPath: destPath)
        let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o700)

        let versionPath = (destDir as NSString).appendingPathComponent(".seed-version")
        let versionString = try String(contentsOfFile: versionPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(versionString == "1")
    }

    @Test
    func testSeedOverwritesOnVersionBump() throws {
        let sourceURL = try makeSourceScript(contents: "#!/bin/sh\necho original\n")
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let destDir = makeDestDirectory()
        defer { try? FileManager.default.removeItem(atPath: destDir) }

        #expect(HookInstaller.seed(from: sourceURL, into: destDir, version: 1))

        let destPath = (destDir as NSString).appendingPathComponent(HookInstaller.scriptName)
        try "tampered".write(toFile: destPath, atomically: true, encoding: .utf8)

        #expect(HookInstaller.seed(from: sourceURL, into: destDir, version: 2))

        let contents = try String(contentsOfFile: destPath, encoding: .utf8)
        #expect(contents == "#!/bin/sh\necho original\n")
    }

    @Test
    func testSeedIsNoOpAtSameVersion() throws {
        let sourceURL = try makeSourceScript(contents: "#!/bin/sh\necho original\n")
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let destDir = makeDestDirectory()
        defer { try? FileManager.default.removeItem(atPath: destDir) }

        #expect(HookInstaller.seed(from: sourceURL, into: destDir, version: 1))

        let destPath = (destDir as NSString).appendingPathComponent(HookInstaller.scriptName)
        try "tampered".write(toFile: destPath, atomically: true, encoding: .utf8)

        #expect(!HookInstaller.seed(from: sourceURL, into: destDir, version: 1))

        let contents = try String(contentsOfFile: destPath, encoding: .utf8)
        #expect(contents == "tampered")
    }

    @Test
    func testSeedRestoresMissingScriptAtSameVersion() throws {
        let sourceURL = try makeSourceScript(contents: "#!/bin/sh\necho original\n")
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let destDir = makeDestDirectory()
        defer { try? FileManager.default.removeItem(atPath: destDir) }

        #expect(HookInstaller.seed(from: sourceURL, into: destDir, version: 1))

        let destPath = (destDir as NSString).appendingPathComponent(HookInstaller.scriptName)
        try FileManager.default.removeItem(atPath: destPath)
        #expect(!FileManager.default.fileExists(atPath: destPath))

        // Marker still reads version 1 — reseeding at the same version must
        // still restore the missing script, not treat it as already seeded.
        #expect(HookInstaller.seed(from: sourceURL, into: destDir, version: 1))

        #expect(FileManager.default.fileExists(atPath: destPath))
        let contents = try String(contentsOfFile: destPath, encoding: .utf8)
        #expect(contents == "#!/bin/sh\necho original\n")
    }
}
