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
    enum Block: Equatable {
        /// Bash approval: "$ <command>" plus an optional description.
        case command(command: String, description: String?)
        /// Any other tool approval: "<Tool> <subject>", the full path when the
        /// subject is a file, and an optional description.
        case tool(headline: String, path: String?, description: String?)
        /// Running: the session's last prompt and its current step.
        case running(prompt: String, step: String?)
        /// A question that must be answered in the terminal (AskUserQuestion,
        /// an elicitation): the card shows only `question` and the hand-off.
        case freeform
    }

    /// What Approve/Deny answer: the prompt the card showed, so the
    /// responder's stale-guard can tell it from a later one
    /// (`ApprovalTarget`).
    struct ApprovalPrompt: Equatable {
        let updatedAt: Date
        let fingerprint: String
    }

    let sessionId: UUID
    let block: Block
    /// The question a needs-you card leads with ("Run npm test?", "Which env
    /// name?"). Nil on a card for a session that does not genuinely need the
    /// user (`SessionAttention`), which then has no hand-off either.
    var question: String? = nil
    /// Set only for a bounded prompt: the one shape Approve/Deny can answer.
    var approvalPrompt: ApprovalPrompt? = nil

    var isApproval: Bool {
        switch block {
        case .command, .tool: return true
        case .running, .freeform: return false
        }
    }

    /// The session is waiting on the user: the card offers "Answer in
    /// terminal".
    var needsYou: Bool { question != nil }

    /// A command at most this long is named in the question ("Run npm
    /// test?"); a longer or multi-line one is asked about generically and
    /// shown in full below.
    static let maxInlineCommandLength = 32

    /// The freeform question when the hook carried no text of its own
    /// (an elicitation or `agent_needs_input`).
    static let freeformFallbackQuestion = "Waiting for your answer"

    static func make(
        sessionId: UUID,
        indicator: SessionIndicatorState,
        approval: ClaudeState?,
        summary: SessionSummary? = nil,
        now: Date = Date()
    ) -> SessionPopoverContent? {
        // Genuine attention (`SessionAttention`): the card leads with the
        // question and hands off to the terminal.
        if let approval, now.timeIntervalSince(approval.updatedAt) <= ClaudeStateStore.staleInterval,
           let attention = SessionAttention.make(indicator: indicator, state: approval) {
            switch attention {
            case let .freeform(question):
                return SessionPopoverContent(
                    sessionId: sessionId, block: .freeform,
                    question: question ?? approval.structuredPrompt?.message ?? freeformFallbackQuestion
                )
            case let .bounded(prompt, command):
                guard isFreshApproval(approval, now: now), let structured = approval.structuredPrompt,
                      let block = approvalBlock(toolName: structured.toolName, input: structured.toolInput) else { return nil }
                return SessionPopoverContent(
                    sessionId: sessionId, block: block,
                    question: boundedQuestion(prompt: prompt, toolName: structured.toolName, command: command),
                    approvalPrompt: ApprovalPrompt(updatedAt: approval.updatedAt, fingerprint: ApprovalFingerprint.make(approval))
                )
            }
        }

        // AskUserQuestion is a freeform question, never a tool approval.
        if let approval, isFreshApproval(approval, now: now),
           approval.structuredPrompt?.toolName != "AskUserQuestion" {
            guard let prompt = approval.structuredPrompt,
                  let block = approvalBlock(toolName: prompt.toolName, input: prompt.toolInput) else { return nil }
            return SessionPopoverContent(sessionId: sessionId, block: block)
        }

        switch indicator {
        case .processing, .longRunning:
            guard let summary, let prompt = summary.prompt, !summary.isDone,
                  now.timeIntervalSince(summary.updatedAt) <= ClaudeStateStore.staleInterval else { return nil }
            return SessionPopoverContent(
                sessionId: sessionId,
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

    /// A short Bash command is named in the question; anything else keeps
    /// `SessionAttention`'s wording.
    static func boundedQuestion(prompt: String, toolName: String, command: String?) -> String {
        guard toolName == "Bash", let command = command?.trimmingCharacters(in: .whitespaces),
              !command.isEmpty, !command.contains(where: \.isNewline),
              command.count <= maxInlineCommandLength else { return prompt }
        return "Run \(command)?"
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
