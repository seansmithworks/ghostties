import SwiftUI
import GhosttiesCore

/// A single session row: name + type-glyph status indicator.
///
/// Used by ProjectDisclosureRow to render sessions under each project.
/// The glyph (SessionStatusGlyph) appears on the right, mapped from the
/// session's indicator state — pattern D, "type is the icon" (BACKLOG J).
struct SessionRow: View {
    let session: AgentSession
    let indicatorState: SessionIndicatorState
    var isActive: Bool = false
    var isEditing: Bool = false
    /// Template name shown as a subtle badge when the session was launched with agent config.
    var agentTemplateName: String?
    @Binding var editingName: String
    var isRenameFocused: FocusState<Bool>.Binding
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("Session name", text: $editingName)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused(isRenameFocused)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
                    .onChange(of: isRenameFocused.wrappedValue) { focused in
                        // Deferred: Esc can drop focus (firing this) before
                        // SwiftUI's onExitCommand runs cancelRename(). Dispatching
                        // async lets cancelRename() clear editingSessionId first,
                        // so the id guard in commitRename(session:) rejects this
                        // call instead of writing a stale name to the store.
                        if !focused, isEditing {
                            DispatchQueue.main.async { onCommitRename() }
                        }
                    }
            } else {
                Text(session.name)
                    .font(.system(size: 12, weight: indicatorState == .needsAttention ? .semibold : indicatorState == .waiting ? .medium : .regular))
                    .foregroundColor(sessionTextColor)
                    .lineLimit(1)

                // Agent template badge — hidden for now, revisit when more agent types exist.
                // if let agentTemplateName {
                //     HStack(spacing: 2) {
                //         Image(systemName: "cpu")
                //             .font(.system(size: 8))
                //         Text(agentTemplateName)
                //             .font(.system(size: 9, weight: .medium))
                //     }
                //     .foregroundColor(Color(.tertiaryLabelColor))
                //     .lineLimit(1)
                // }
            }

            Spacer()

            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: 16)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .shadow(
            color: isActive ? Color.black.opacity(0.1) : .clear,
            radius: 2, x: 0, y: 1
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name)\(agentTemplateName.map { ", \($0) agent" } ?? ""), \(statusLabel)\(isActive ? ", active" : "")")
    }

    // MARK: - Colors

    private var sessionTextColor: Color {
        if isActive { return .primary }
        switch indicatorState {
        case .waiting, .needsAttention, .processing, .longRunning: return .primary
        case .idle:     return Color(.secondaryLabelColor)
        case .inactive: return colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
        case .error:    return .primary
        }
    }

    private var rowBackground: Color {
        if isActive {
            return colorScheme == .dark
                ? WorkspaceLayout.activeRowDark
                : WorkspaceLayout.activeRowLight
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return .clear
    }

    /// Derived from the same `SessionStatusGlyphKind` the visible glyph
    /// renders — a parallel per-state switch here previously spoke "your
    /// turn" for `.waiting` while the glyph showed a spinner, so VoiceOver
    /// and sighted users disagreed about whether the session needed Sean.
    private var statusLabel: String {
        indicatorState.statusGlyphKind.spokenStatus
    }
}
