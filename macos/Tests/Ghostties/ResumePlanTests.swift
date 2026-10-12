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

    /// A session launched by `devdesk` (which runs `cco --name desk`)
    /// resumes through `cco`, exactly like a `cco` session.
    @Test func devdeskLauncherResumesThroughCco() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: "devdesk")
        #expect(ResumePlan.command(resume: resume, template: .claudeCode) == "cco --resume 'abc-123'")
    }

    /// An unrecognized launcher falls through to the
    /// template path rather than `cco`.
    @Test func unknownLauncherDoesNotTakeCcoPath() {
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: "unknown-launcher")
        #expect(ResumePlan.command(resume: resume, template: .claudeCode) == "'claude' --resume 'abc-123'")
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

/// `SessionCoordinator.relaunchTemplate(for:templates:)`: the one place a
/// relaunch resolves its template.
@MainActor
struct RelaunchTemplateTests {
    private let orchestratorId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private func session(templateId: UUID) -> AgentSession {
        AgentSession(name: "thread", templateId: templateId, projectId: UUID())
    }

    /// Orchestrator was removed in 0.1.0-beta.26. Relaunching a saved
    /// Orchestrator session starts Claude Code (what Orchestrator ran,
    /// minus its prompt) at the project root, and resumes its transcript
    /// through `claude`, instead of silently doing nothing.
    @Test func relaunchingAnOrchestratorSessionStartsClaudeCode() {
        let template = SessionCoordinator.relaunchTemplate(
            for: session(templateId: orchestratorId), templates: AgentTemplate.defaults
        )
        #expect(template?.id == AgentTemplate.claudeCode.id)
        #expect(template?.workingDirectory == nil, "starts at the project root, as Orchestrator did")
        let resume = AgentResume(agent: .claude, sessionId: "abc-123", transcriptPath: nil, cwd: nil, launcher: nil)
        #expect(template.flatMap { ResumePlan.command(resume: resume, template: $0) } == "'claude' --resume 'abc-123'")
    }

    /// A template id that is neither known nor retired is unchanged: no
    /// template, so relaunch keeps its not-found path.
    @Test func anUnknownTemplateIdStillResolvesToNothing() {
        #expect(SessionCoordinator.relaunchTemplate(for: session(templateId: UUID()), templates: AgentTemplate.defaults) == nil)
    }

    @Test func aKnownTemplateResolvesToItself() {
        let template = SessionCoordinator.relaunchTemplate(
            for: session(templateId: AgentTemplate.codex.id), templates: AgentTemplate.defaults
        )
        #expect(template?.id == AgentTemplate.codex.id)
    }
}
