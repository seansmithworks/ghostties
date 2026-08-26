import Foundation
import Testing
@testable import Ghostty

struct PresetLoaderTests {

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
