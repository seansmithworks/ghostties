import Foundation

/// What the sidebar session popover renders: one block of essential
/// information, as a pure value derived from a session's indicator state and
/// (only while it is genuinely waiting on an approval) its Claude hook state.
///
/// `make(...)` returns nil when there is nothing essential to show (done,
/// idle, stopped, error, running with no summary yet, or a permission prompt
/// with no tool detail), so "never show a stale approval" lives in one place:
/// approval content is built only from a FRESH `.needsPermission`
/// `ClaudeState`. Anything else, or a permission state older than
/// `ClaudeStateStore.staleInterval`, yields no approval block.
struct SessionPopoverContent: Equatable {
    /// The rail shows ghosts only, so its card names the session.
    struct NameLine: Equatable {
        let name: String
        let project: String?
    }

    enum Block: Equatable {
        /// Bash approval: "$ <command>" plus an optional description.
        case command(command: String, description: String?)
        /// Any other tool approval: "<Tool> <subject>", the full path when the
        /// subject is a file, and an optional description.
        case tool(headline: String, path: String?, description: String?)
        /// Running: the session's last prompt and its current step.
        case running(prompt: String, step: String?)
    }

    let sessionId: UUID
    /// Non-nil only in rail mode.
    let nameLine: NameLine?
    let block: Block

    var isApproval: Bool {
        switch block {
        case .command, .tool: return true
        case .running: return false
        }
    }

    static func make(
        sessionId: UUID,
        name: String,
        project: String?,
        showsName: Bool,
        indicator: SessionIndicatorState,
        approval: ClaudeState?,
        summary: SessionSummary? = nil,
        now: Date = Date()
    ) -> SessionPopoverContent? {
        let nameLine = showsName ? NameLine(name: name, project: project) : nil

        if let approval, isFreshApproval(approval, now: now) {
            guard let prompt = approval.structuredPrompt,
                  let block = approvalBlock(toolName: prompt.toolName, input: prompt.toolInput) else { return nil }
            return SessionPopoverContent(sessionId: sessionId, nameLine: nameLine, block: block)
        }

        switch indicator {
        case .processing, .longRunning:
            guard let summary, let prompt = summary.prompt, !summary.isDone,
                  now.timeIntervalSince(summary.updatedAt) <= ClaudeStateStore.staleInterval else { return nil }
            return SessionPopoverContent(
                sessionId: sessionId, nameLine: nameLine,
                block: .running(prompt: prompt, step: summary.currentStep)
            )
        default:
            return nil
        }
    }

    /// True only for a `.needsPermission` state whose hook event is still
    /// recent. Anything else (`.busy` after the user answered in the
    /// terminal, `.idle`, `.ended`, or an old file) is not an approval.
    static func isFreshApproval(_ state: ClaudeState, now: Date) -> Bool {
        state.state == .needsPermission
            && now.timeIntervalSince(state.updatedAt) <= ClaudeStateStore.staleInterval
    }

    private static func approvalBlock(toolName: String, input: ToolInputSummary?) -> Block? {
        if toolName == "Bash", let command = input?.command {
            return .command(command: command, description: input?.description)
        }
        guard !toolName.isEmpty else { return nil }
        let path = input?.filePath
        let subject = path.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
            ?? input?.firstArgument
        return .tool(
            headline: [toolName, subject].compactMap { $0 }.joined(separator: " "),
            path: path,
            description: input?.description
        )
    }
}
