import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

struct PresetLoaderTests {

    // MARK: - Seeding

    /// The app bundles no presets since Linear Sync was removed
    /// (0.5.0-beta.26). Seeding must treat that as "nothing to copy", not
    /// a failure: no crash, nothing written but the version marker, and
    /// the marker so it doesn't re-run every launch.
    @Test func seedingWithNoBundledPresetsWritesOnlyTheMarker() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("preset-seed-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let dir = root.appendingPathComponent("presets").path
        let missingBundle = root.appendingPathComponent("bundle/presets")

        let outcome = PresetLoader.seedIfNeeded(presetsDirectoryPath: dir, bundledPresetsURL: missingBundle)

        #expect(outcome == .nothingBundled)
        #expect(try fm.contentsOfDirectory(atPath: dir) == [".seed-version"])
        let marker = try String(contentsOfFile: dir + "/.seed-version", encoding: .utf8)
        #expect(marker == "\(PresetLoader.seedVersion)")
        #expect(PresetLoader.seedIfNeeded(presetsDirectoryPath: dir, bundledPresetsURL: missingBundle) == .alreadySeeded)
    }

    /// Seeding never deletes a preset the bundle stopped shipping unless it
    /// is retired and unmodified; an edited copy is the user's.
    @Test func seedingNeverRemovesAPresetTheBundleNoLongerShips() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("preset-seed-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let dir = root.appendingPathComponent("presets")
        let kept = dir.appendingPathComponent("linear-sync/preset.json")
        try fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: kept)

        _ = PresetLoader.seedIfNeeded(presetsDirectoryPath: dir.path, bundledPresetsURL: root.appendingPathComponent("bundle/presets"))

        #expect(fm.fileExists(atPath: kept.path))
    }

    /// `linear-sync/preset.json` exactly as an earlier beta seeded it.
    private static let shippedLinearSyncPreset = """
    {
      "name": "Linear Sync",
      "description": "Syncs Linear issues into Ghostties tasks",
      "icon": "arrow.triangle.2.circlepath",
      "model": null,
      "permissionMode": null
    }

    """

    private func seedRetired(_ name: String, contents: String) throws -> (root: URL, dir: URL, preset: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("preset-seed-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("presets")
        let preset = dir.appendingPathComponent("\(name)/preset.json")
        try fm.createDirectory(at: preset.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: preset)
        _ = PresetLoader.seedIfNeeded(presetsDirectoryPath: dir.path, bundledPresetsURL: root.appendingPathComponent("bundle/presets"))
        return (root, dir, preset)
    }

    @Test func seedingRemovesAnUnmodifiedRetiredLinearSync() throws {
        let seeded = try seedRetired("linear-sync", contents: Self.shippedLinearSyncPreset)
        defer { try? FileManager.default.removeItem(at: seeded.root) }

        #expect(!FileManager.default.fileExists(atPath: seeded.preset.deletingLastPathComponent().path))
    }

    /// The whole shipped file set, with the home path rewritten into
    /// `mcp-servers.json` the way the seed does it. Uses an injected home,
    /// never the real one.
    @Test func seedingRemovesTheFullShippedLinearSyncSetWithHomeRewritten() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("preset-seed-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let home = "/Users/someone-else"
        let dir = root.appendingPathComponent("presets")
        let linear = dir.appendingPathComponent("linear-sync")
        try fm.createDirectory(at: linear, withIntermediateDirectories: true)
        for (name, data) in LinearSyncShippedFixture.files {
            let text = String(decoding: data, as: UTF8.self)
            let onDisk = name.hasSuffix(".json") ? text.replacingOccurrences(of: "${HOME}", with: home) : text
            try Data(onDisk.utf8).write(to: linear.appendingPathComponent(name))
        }
        let mcp = try String(contentsOf: linear.appendingPathComponent("mcp-servers.json"), encoding: .utf8)
        #expect(mcp.contains(home) && !mcp.contains("${HOME}"))

        _ = PresetLoader.seedIfNeeded(
            presetsDirectoryPath: dir.path,
            bundledPresetsURL: root.appendingPathComponent("bundle/presets"),
            homeDirectoryPath: home
        )

        #expect(!fm.fileExists(atPath: linear.path))
    }

    @Test func seedingKeepsAnEditedRetiredLinearSync() throws {
        let seeded = try seedRetired("linear-sync", contents: Self.shippedLinearSyncPreset + "// mine\n")
        defer { try? FileManager.default.removeItem(at: seeded.root) }

        #expect(FileManager.default.fileExists(atPath: seeded.preset.path))
    }

    @Test func seedingKeepsAUserPresetWithAnotherName() throws {
        let seeded = try seedRetired("my-preset", contents: Self.shippedLinearSyncPreset)
        defer { try? FileManager.default.removeItem(at: seeded.root) }

        #expect(FileManager.default.fileExists(atPath: seeded.preset.path))
    }

    // MARK: - parseFrontmatter (via parsePreset)

    @Test func testParseFrontmatterSimple() throws {
        let content = """
        ---
        name: Code Reviewer
        model: sonnet
        description: Reviews code for bugs
        command: claude
        ---

        You are a code reviewer.
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-simple-\(UUID().uuidString).md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let template = PresetLoader.parsePreset(at: file, filename: file.lastPathComponent)
        #expect(template != nil)
        #expect(template?.name == "Code Reviewer")
        #expect(template?.agent?.model == "sonnet")
        #expect(template?.templateDescription == "Reviews code for bugs")
        #expect(template?.command == "claude")
        #expect(template?.kind == .claudeCode)
    }

    @Test func testParseFrontmatterMissingName() throws {
        let content = """
        ---
        model: sonnet
        description: No name field
        ---

        Body text here.
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-noname-\(UUID().uuidString).md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let template = PresetLoader.parsePreset(at: file, filename: file.lastPathComponent)
        #expect(template == nil)
    }

    @Test func testParseFrontmatterMissingDelimiter() throws {
        let content = """
        name: No Delimiter
        model: sonnet
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-nodelim-\(UUID().uuidString).md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let template = PresetLoader.parsePreset(at: file, filename: file.lastPathComponent)
        #expect(template == nil)
    }

    @Test func testParseFrontmatterWithAllowedToolsList() throws {
        let content = """
        ---
        name: Restricted Agent
        command: claude
        model: sonnet
        allowedTools:
          - Read
          - Grep
          - Glob
        ---

        You have limited tool access.
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-tools-\(UUID().uuidString).md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let template = PresetLoader.parsePreset(at: file, filename: file.lastPathComponent)
        #expect(template != nil)
        #expect(template?.name == "Restricted Agent")
        #expect(template?.agent?.allowedTools == ["Read", "Grep", "Glob"])
    }

    // MARK: - Deterministic UUID

    @Test func testDeterministicUUID() {
        // Same filename must always produce the same UUID.
        let uuid1 = PresetLoader.deterministicUUID(from: "code-reviewer.md")
        let uuid2 = PresetLoader.deterministicUUID(from: "code-reviewer.md")
        #expect(uuid1 == uuid2)
    }

    @Test func testDeterministicUUIDDifferentInputs() {
        // Different filenames must produce different UUIDs.
        let uuid1 = PresetLoader.deterministicUUID(from: "code-reviewer.md")
        let uuid2 = PresetLoader.deterministicUUID(from: "orchestrator.md")
        #expect(uuid1 != uuid2)
    }

    // MARK: - loadPresetsResult's loadSucceeded (FIX 1, final review round)

    /// A malformed preset file (invalid frontmatter) must NOT be reported as
    /// a load success. Before this fix, `loadPresetsResult` skipped
    /// per-file `parsePreset` failures silently and returned
    /// `loadSucceeded: true`, which `SessionComposerStore.prunePins` reads
    /// as "nothing was lost" — the exact condition that permanently drops a
    /// pin for a preset with a frontmatter typo (see `loadPresetsResult`'s
    /// doc comment). Manipulates the real `~/.ghostties/presets` directory
    /// because `presetsDirectoryPath` is a fixed path, not injectable;
    /// backs up and restores its contents around the test.
    @Test func loadPresetsResultReportsFailureOnAMalformedEntry() throws {
        let fm = FileManager.default
        let dirPath = PresetLoader.presetsDirectoryPath
        let dirURL = URL(fileURLWithPath: dirPath)
        let backupURL = fm.temporaryDirectory.appendingPathComponent("presets-backup-\(UUID().uuidString)")

        var hadOriginalDir = false
        if fm.fileExists(atPath: dirPath) {
            hadOriginalDir = true
            try fm.moveItem(at: dirURL, to: backupURL)
        }
        defer {
            try? fm.removeItem(at: dirURL)
            if hadOriginalDir {
                try? fm.moveItem(at: backupURL, to: dirURL)
            }
        }

        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // One valid preset, one with a missing "name" field (parsePreset
        // returns nil for this — see testParseFrontmatterMissingName above).
        let validContent = """
        ---
        name: Valid Preset
        command: claude
        ---

        Body.
        """
        try validContent.write(
            to: dirURL.appendingPathComponent("valid.md"),
            atomically: true,
            encoding: .utf8
        )

        let malformedContent = """
        ---
        model: sonnet
        description: No name field
        ---

        Body.
        """
        try malformedContent.write(
            to: dirURL.appendingPathComponent("malformed.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = PresetLoader.loadPresetsResult()

        #expect(result.templates.count == 1)
        #expect(result.templates.first?.name == "Valid Preset")
        #expect(result.loadSucceeded == false)
    }

    /// Pins survive the failure: `prunePins` reads `loadSucceeded == false`
    /// (from the malformed-entry case above, reproduced against
    /// `SessionComposerStore` directly to avoid a second real-directory
    /// round-trip) and must not drop a pin whose template is temporarily
    /// missing from the id universe as a result.
    @Test @MainActor func pinsSurviveAMalformedPresetEntry() throws {
        let store = SessionComposerStore(isolatedForTesting: ())
        let pinnedId = UUID()
        store.togglePin(templateId: pinnedId)

        // The malformed entry means `pinnedId`'s template is absent from the
        // valid-id universe, but `presetsLoadSucceeded: false` (what
        // `loadPresetsResult` now reports per the test above) must still
        // block the prune.
        store.prunePins(validIds: [], presetsLoadSucceeded: false)

        #expect(store.pinnedTemplateIds == [pinnedId])
    }
}
