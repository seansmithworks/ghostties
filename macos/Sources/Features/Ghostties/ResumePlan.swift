import Foundation
import GhosttiesCore

/// Pure resolution of the shell command that resumes an agent's prior
/// conversation, given a persisted `AgentResume` record and the session's
/// current template. No filesystem, no `self` — every branch is a table
/// test in `ResumePlanTests`.
///
/// Precedence (Sean's decision, `project_relaunch-resume-plan.md`):
///   1. `.codex` — `codex -C '<cwd>' resume '<id>'`. Codex's `resume` does
///      not restore cwd on its own, so it's passed explicitly via the
///      GLOBAL `-C`/`--cd` flag (verified against `codex --help` /
///      `codex resume --help`, codex-cli 0.153.0 — `-C` is NOT a `resume`
///      subcommand flag).
///   2. `.claude` launched via `cco`/`ccob` — `cco --resume '<id>'`. `cco`
///      forwards extra args to `claude` (verified in `~/.claude/shell/zshrc`).
///   3. `.claude`, current template is Claude Code — the template's own
///      built command (model, system prompt, etc.) plus `--resume '<id>'`,
///      so a resumed session keeps today's template config.
///   4. `.claude`, anything else (shell-hosted `claude`, no launcher marker)
///      — bare `claude --resume '<id>'`.
///   5. No record — nil (caller falls back to a fresh launch).
enum ResumePlan {
    /// Launcher markers that resume through the `cco`/`ccob` wrapper rather
    /// than a bare `claude` invocation.
    private static let ccoLaunchers: Set<String> = ["cco", "ccob"]

    static func command(resume: AgentResume?, template: AgentTemplate) -> String? {
        guard let resume, !resume.sessionId.isEmpty else { return nil }

        switch resume.agent {
        case .codex:
            let cwd = resume.cwd ?? ""
            return "codex -C \(shellQuote(cwd)) resume \(shellQuote(resume.sessionId))"

        case .claude:
            if let launcher = resume.launcher, ccoLaunchers.contains(launcher) {
                // Always resume through `cco`, never `ccob` — `ccob` always
                // appends `/orchestrator-boot` as a final positional prompt
                // (`~/.claude/shell/zshrc:598`), which would re-run the boot
                // sequence into an already-resumed conversation. `cco`
                // forwards extra args straight to `claude` when any are
                // given (`:537-541`), so `cco --resume '<id>'` alone is a
                // clean resume for a session launched by either wrapper.
                return "cco --resume \(shellQuote(resume.sessionId))"
            }
            if template.kind == .claudeCode {
                let built = template.buildCommand()
                guard !built.isEmpty else {
                    return "claude --resume \(shellQuote(resume.sessionId))"
                }
                return "\(built) --resume \(shellQuote(resume.sessionId))"
            }
            return "claude --resume \(shellQuote(resume.sessionId))"
        }
    }

    /// Wrap `value` in single quotes, escaping any embedded single quote via
    /// the standard `'\''` close-escape-open sequence — the same scheme
    /// `AgentTemplate.shellEscape` uses. Safe for paths containing spaces
    /// and quotes.
    static func shellQuote(_ value: String) -> String {
        let escaped = value.contains("'") ? value.replacingOccurrences(of: "'", with: "'\\''") : value
        return "'\(escaped)'"
    }
}
