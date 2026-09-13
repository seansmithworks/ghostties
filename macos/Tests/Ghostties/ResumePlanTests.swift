import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Table tests for `ResumePlan.command(resume:template:)` — every branch of
/// the precedence Sean decided (`project_relaunch-resume-plan.md`), plus the
/// shell-quoting rule shared with `AgentTemplate.shellEscape`.
struct ResumePlanTests {
    @Test func nilRecordReturnsNil() {
        #expect(ResumePlan.command(resume: nil, template: .shell) == nil)
    }

    @Test func emptySessionIdReturnsNil() {
        let resume = AgentResume(agent: .claude, sessionId: "", transcriptPath: nil, cwd: nil, launcher: nil)
        #expect(ResumePlan.command(resume: resume, template: .claudeCode) == nil)
    }

    @Test func ccoLauncherResumesThroughCco() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: "cco")
        #expect(ResumePlan.command(resume: resume, template: .claudeCode) == "cco --resume 'abc-123'")
    }

    /// A session launched by `ccob` still resumes through `cco`, never
    /// `ccob` — `ccob` always appends `/orchestrator-boot`, which would
    /// re-run the boot sequence into an already-resumed conversation.
    @Test func ccobLauncherAlsoResumesThroughCcoNeverCcob() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: "ccob")
        #expect(ResumePlan.command(resume: resume, template: .claudeCode) == "cco --resume 'abc-123'")
    }

    @Test func claudeCodeTemplateWithNoLauncherUsesBuiltCommand() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: nil)
        let command = ResumePlan.command(resume: resume, template: .claudeCode)
        #expect(command == "'claude' --resume 'abc-123'")
    }

    @Test func claudeCodeTemplateWithAgentConfigIncludesItsFlags() {
        let template = AgentTemplate(
            name: "Orchestrator",
            kind: .claudeCode,
            command: "claude",
            agent: AgentTemplate.AgentConfig(model: "opus")
        )
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: nil)
        let command = ResumePlan.command(resume: resume, template: template)
        #expect(command == "'claude' --model 'opus' --resume 'abc-123'")
    }

    @Test func nonClaudeCodeTemplateFallsBackToBareClaude() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: nil)
        #expect(ResumePlan.command(resume: resume, template: .shell) == "claude --resume 'abc-123'")
    }

    @Test func codexUsesGlobalCdFlagBeforeResumeSubcommand() {
        let resume = AgentResume(agent: .codex, sessionId: "rollout-1", transcriptPath: nil, cwd: "/Users/sean/proj", launcher: nil)
        #expect(ResumePlan.command(resume: resume, template: .codex) == "codex -C '/Users/sean/proj' resume 'rollout-1'")
    }

    @Test func codexWithNilCwdQuotesAnEmptyString() {
        let resume = AgentResume(agent: .codex, sessionId: "rollout-1", transcriptPath: nil, cwd: nil, launcher: nil)
        #expect(ResumePlan.command(resume: resume, template: .codex) == "codex -C '' resume 'rollout-1'")
    }

    // MARK: - Shell quoting

    @Test func shellQuoteWrapsPlainValueInSingleQuotes() {
        #expect(ResumePlan.shellQuote("abc-123") == "'abc-123'")
    }

    @Test func shellQuoteEscapesEmbeddedSingleQuotes() {
        #expect(ResumePlan.shellQuote("it's") == "'it'\\''s'")
    }

    @Test func shellQuoteHandlesAPathWithASpaceAndAQuote() {
        let path = "/Users/sean/My Project's Folder/rollout.jsonl"
        let quoted = ResumePlan.shellQuote(path)
        #expect(quoted == "'/Users/sean/My Project'\\''s Folder/rollout.jsonl'")

        // Round-trip through sh -c to prove this is actually valid shell,
        // not just a plausible-looking string.
        let script = "printf '%s' \(quoted)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(output == path)
    }
}
