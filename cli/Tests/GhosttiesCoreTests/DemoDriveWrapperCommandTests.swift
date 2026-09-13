import XCTest
@testable import GhosttiesCore

/// Verifies the demo-drive wrapper-script fix (scripts/demo/_stage-demo-sessions.sh):
/// a staged AgentTemplate whose prompt is baked into an executable wrapper
/// script — command pointed at the wrapper's absolute path, no
/// agent.additionalFlags — produces the wrapper path intact through
/// AgentTemplate.buildCommand(), and is a no-op for
/// WorkspacePersistence.sanitizeTemplate's flag/env filtering (reimplemented
/// here since that function lives in the macOS app target, not this SPM
/// package — see cli/Tests/.../DemoDriveWrapperCommandTests for context).
final class DemoDriveWrapperCommandTests: XCTestCase {
    /// Mirrors WorkspacePersistence.sanitizeTemplate's allowlist regex
    /// exactly (macos/Sources/Features/Ghostties/WorkspacePersistence.swift).
    /// Kept in sync by inspection — this package cannot import the macOS
    /// app target directly.
    private static let validFlagPattern = "^--?[a-zA-Z][a-zA-Z0-9_-]*(=[a-zA-Z0-9_./:@=-]+)?$"

    private func sanitizedAdditionalFlags(_ flags: [String]) -> [String] {
        flags.filter { $0.range(of: Self.validFlagPattern, options: .regularExpression) != nil }
    }

    func testWrapperPathSurvivesBuildCommandIntact() {
        // A space-free absolute path, as staged by
        // scripts/demo/_stage-demo-sessions.sh under DEMO_WRAPPER_DIR
        // ($HOME/.ghostties-demo-wrappers).
        let wrapperPath = "/Users/demo/.ghostties-demo-wrappers/demo-drive-ABCDEF.sh"

        let template = AgentTemplate(
            name: "Demo Drive: atlas-api",
            kind: .claudeCode,
            command: wrapperPath,
            workingDirectory: "/Users/Shared/Ghostties Demo/repos/atlas-api",
            agent: nil // no additionalFlags — the prompt lives inside the wrapper, not here
        )

        let built = template.buildCommand()

        // buildCommand() shell-escapes `command` as a single quoted token.
        XCTAssertEqual(built, "'\(wrapperPath)'")

        // The base-command extraction SessionCoordinator.createSession performs
        // (split on first whitespace) must yield the whole quoted token, since
        // the wrapper path itself contains no whitespace.
        let baseCommand = String(built.prefix(while: { !$0.isWhitespace }))
        XCTAssertEqual(baseCommand, built, "wrapper path must contain no whitespace")
    }

    func testWrapperTemplateHasNoAdditionalFlagsForSanitizeTemplateToStrip() {
        let wrapperPath = "/Users/demo/.ghostties-demo-wrappers/demo-drive-ABCDEF.sh"
        let template = AgentTemplate(
            name: "Demo Drive: atlas-api",
            kind: .claudeCode,
            command: wrapperPath,
            agent: nil
        )

        // sanitizeTemplate only ever mutates environmentVariables and
        // agent.additionalFlags — command is untouched. With agent == nil,
        // there is nothing for the allowlist regex to strip, so the prompt
        // (now inside the wrapper script, not a template field) can never be
        // silently dropped the way the old additionalFlags-based prompt was.
        XCTAssertNil(template.agent)
        XCTAssertEqual(template.command, wrapperPath)

        // Sanity check on the old, now-unused approach: confirms *why* the
        // fix was needed — a plain prompt sentence never matches the regex.
        let oldStylePrompt = "Summarize this repository's README in 3 bullet points. Read-only — do not modify any files."
        XCTAssertTrue(sanitizedAdditionalFlags([oldStylePrompt]).isEmpty)
    }
}
