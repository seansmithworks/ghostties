import Foundation

/// What the sidebar session popover renders, as a pure value derived from a
/// session's identity, its indicator state, and (only while it is genuinely
/// waiting on an approval) its Claude hook state.
///
/// Everything the card shows comes out of `make(...)`, so the "never show a
/// stale approval" rule lives in exactly one place: approval content is built
/// only from a FRESH `.needsPermission` `ClaudeState`. Any other state — or a
/// permission state older than `ClaudeStateStore.staleInterval` — yields the
/// passive card, with no command, no description, no tool name.
struct SessionPopoverContent: Equatable {
    enum StatusKind: Equatable {
        case needsApproval
        case running
        case idle
        case error
        case stopped
    }

    /// One line of the Mini Terminal block.
    struct TerminalLine: Equatable {
        enum Tone: Equatable { case primary, secondary, alert }
        let text: String
        let tone: Tone
    }

    enum Body: Equatable {
        /// Option 03's Command Hero: "$ <command>" plus an optional description.
        case commandHero(command: String, description: String?)
        /// Option 01's Mini Terminal.
        case miniTerminal(lines: [TerminalLine])
        /// Passive card, or a permission prompt with no tool detail.
        case none
    }

    let sessionId: UUID
    let title: String
    let subtitle: String
    /// Compact relative time ("now", "3m", "2h"), trailing in the header.
    let relativeTime: String?
    let statusKind: StatusKind
    let statusLabel: String
    /// Mono text after the label — the tool name while approving.
    let statusDetail: String?
    let body: Body

    var isApproval: Bool { statusKind == .needsApproval }

    /// The tool line's first argument: `file_path`, else the first other
    /// single-target key.
    static func toolSubject(_ input: ToolInputSummary?) -> String? {
        input?.filePath ?? input?.firstArgument
    }

    static func make(
        sessionId: UUID,
        title: String,
        cwd: String?,
        agent: String,
        indicator: SessionIndicatorState,
        approval: ClaudeState?,
        fallbackDate: Date?,
        now: Date = Date(),
        homeDirectory: String = NSHomeDirectory()
    ) -> SessionPopoverContent {
        let subtitle = [cwd.flatMap { $0.isEmpty ? nil : abbreviate($0, home: homeDirectory) }, agent]
            .compactMap { $0 }
            .joined(separator: " · ")

        if let approval, isFreshApproval(approval, now: now) {
            let prompt = approval.structuredPrompt
            let toolName = prompt.map(\.toolName).flatMap { $0.isEmpty ? nil : $0 }
            return SessionPopoverContent(
                sessionId: sessionId,
                title: title,
                subtitle: subtitle,
                relativeTime: relativeLabel(approval.updatedAt, now: now),
                statusKind: .needsApproval,
                statusLabel: "Needs approval",
                statusDetail: toolName,
                body: approvalBody(toolName: toolName, input: prompt?.toolInput)
            )
        }

        let (kind, label): (StatusKind, String) = {
            switch indicator {
            case .processing, .longRunning: return (.running, "Running")
            case .needsAttention: return (.idle, "Waiting")
            case .idle, .waiting: return (.idle, "Idle")
            case .error: return (.error, "Error")
            case .inactive: return (.stopped, "Stopped")
            }
        }()
        return SessionPopoverContent(
            sessionId: sessionId,
            title: title,
            subtitle: subtitle,
            relativeTime: fallbackDate.map { relativeLabel($0, now: now) },
            statusKind: kind,
            statusLabel: label,
            statusDetail: nil,
            body: .none
        )
    }

    /// True only for a `.needsPermission` state whose hook event is still
    /// recent. Anything else (`.busy` after the user answered in the
    /// terminal, `.idle`, `.ended`, or an old file) is not an approval.
    static func isFreshApproval(_ state: ClaudeState, now: Date) -> Bool {
        state.state == .needsPermission
            && now.timeIntervalSince(state.updatedAt) <= ClaudeStateStore.staleInterval
    }

    private static func approvalBody(toolName: String?, input: ToolInputSummary?) -> Body {
        if toolName == "Bash", let command = input?.command {
            return .commandHero(command: command, description: input?.description)
        }
        guard let toolName else { return .none }
        var lines = [TerminalLine(
            text: "● \(toolName)(\(toolSubject(input) ?? ""))",
            tone: .primary
        )]
        if let description = input?.description {
            lines.append(TerminalLine(text: "  \(description)", tone: .secondary))
        }
        lines.append(TerminalLine(text: "  Do you want to proceed?", tone: .alert))
        return .miniTerminal(lines: lines)
    }

    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// "now", "3m", "2h", "4d" — the card's own compact form, not
    /// `RecentsRowView.relativeLabel` ("just now"), to match the canvas.
    static func relativeLabel(_ date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        return "\(Int(elapsed / 86400))d"
    }
}
