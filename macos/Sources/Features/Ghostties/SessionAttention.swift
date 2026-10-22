import Foundation

/// Why a session needs the user, derived purely from the indicator and the
/// hook-derived `ClaudeState`. Idle is NOT attention: `Notification/idle_prompt`
/// ("Claude finished ~60s ago") maps to `.idle` upstream in
/// `ClaudeStateStore.derive`, so it never reaches here as `.needsInput`.
///
/// Event names: https://code.claude.com/docs/en/hooks (Notification matchers
/// `permission_prompt`, `elicitation_*`, `agent_needs_input`; `AskUserQuestion`
/// `tool_input.questions[].question`). No transcript reading.
enum SessionAttention: Equatable {
    /// A permission prompt: answerable with approve/deny. `command` is the Bash
    /// command being approved, when the hook carried it.
    case bounded(prompt: String, command: String?)
    /// A question that needs typing/picking in the terminal. `question` is
    /// the AskUserQuestion text, nil for elicitation / agent_needs_input.
    case freeform(question: String?)

    static func make(indicator: SessionIndicatorState, state: ClaudeState?) -> SessionAttention? {
        guard indicator == .needsAttention, let state else { return nil }
        switch state.state {
        case .needsPermission:
            let input = state.structuredPrompt?.toolInput
            return .bounded(
                prompt: permissionPrompt(tool: state.structuredPrompt?.toolName, input: input),
                command: input?.command
            )
        case .needsInput:
            return .freeform(question: state.structuredPrompt?.toolInput?.questions.first)
        case .busy, .idle, .ended:
            return nil
        }
    }

    /// The "N need you" number for a project: only genuine attention counts.
    static func count(
        sessions: [UUID],
        indicator: (UUID) -> SessionIndicatorState,
        state: (UUID) -> ClaudeState?
    ) -> Int {
        sessions.filter { make(indicator: indicator($0), state: state($0)) != nil }.count
    }

    private static func permissionPrompt(tool: String?, input: ToolInputSummary?) -> String {
        guard let tool, !tool.isEmpty else { return "Needs permission" }
        switch tool {
        case "Bash":
            return "Run this command?"
        case "Edit", "Write", "MultiEdit":
            let name = input?.filePath.map { ($0 as NSString).lastPathComponent }
            return name.map { "Edit \($0)?" } ?? "Edit a file?"
        default:
            return "Allow \(tool)?"
        }
    }
}
