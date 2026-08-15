import SwiftUI

/// A single row in the Sessions recents list.
///
/// Displays a status dot (colored by `SessionIndicatorState`), the session name,
/// the owning project name in muted text, and a right-aligned relative timestamp.
/// Tapping focuses the session in the terminal area.
///
/// `Equatable` (manual, not synthesized — several stored properties are
/// closures/bindings and can't derive `==`) so the caller can apply
/// `.equatable()` and skip re-executing `body` when none of this row's own
/// inputs changed. This is the same pattern as `ProjectDisclosureRowContent`
/// (PR #40) and is a body-re-execution **perf gate**, not what makes a row
/// pick up new values — `RecentsListView` keys its `ForEach` on the stable
/// `\.id` (required so hover state and an in-progress inline rename survive
/// `WorkspaceStore` writes that don't touch this row, e.g. another session's
/// `lastActiveAt`), and freshness on that stable identity comes from the
/// caller using a non-lazy `VStack` rather than `LazyVStack` — a lazy
/// container retains a realized row and never re-invokes the `ForEach`
/// content closure when only the element changes, so `.equatable()` alone
/// cannot fix a frozen row (there is no new value to compare against).
/// See the `VStack` comment in `RecentsListView.body`.
struct RecentsRowView: View, Equatable {
    let session: AgentSession
    let projectName: String
    let indicatorState: SessionIndicatorState
    let isActive: Bool
    var isEditing: Bool = false
    @Binding var editingName: String
    var isRenameFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    /// Every field that affects rendered output. Deliberately excludes
    /// `editingName`/`isRenameFocused`/the closures — those are live
    /// bindings the `TextField` reads directly, not values `body` needs to
    /// re-run for.
    static func == (lhs: RecentsRowView, rhs: RecentsRowView) -> Bool {
        lhs.session == rhs.session
            && lhs.projectName == rhs.projectName
            && lhs.indicatorState == rhs.indicatorState
            && lhs.isActive == rhs.isActive
            && lhs.isEditing == rhs.isEditing
    }

    var body: some View {
        HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
            // Per-session ghost character, tinted by status — same color mapping
            // as MenuBarDropdownView.
            GhostCharacterView(character: session.resolvedGhostCharacter, color: dotColor)
                .frame(width: WorkspaceLayout.sessionGhostSize, height: WorkspaceLayout.sessionGhostSize)
                .frame(width: WorkspaceLayout.sidebarIconColumnWidth, alignment: .center)

            // Session name + project name stacked
            VStack(alignment: .leading, spacing: 1) {
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
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }

                Text(projectName)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.tertiaryLabelColor))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Relative timestamp
            if let ts = session.lastActiveAt {
                Text(Self.relativeLabel(ts))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.tertiaryLabelColor))
                    .monospacedDigit()
            }
        }
        .padding(.leading, WorkspaceLayout.sidebarRowLeadingPadding)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !isEditing else { return }
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Dot Color

    private var dotColor: Color {
        switch indicatorState {
        case .error:          return Color(.systemRed)
        case .needsAttention: return WorkspaceLayout.statusNeedsDecisionGold
        case .waiting:        return WorkspaceLayout.statusYourTurnBlue
        case .longRunning:    return WorkspaceLayout.statusLongRunningOrange
        case .processing:     return Color(.systemGreen)
        case .idle:           return Color.primary.opacity(0.30)
        case .inactive:       return Color.primary.opacity(0.12)
        }
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(rowFill)
    }

    private var rowFill: Color {
        if isActive {
            return colorScheme == .dark
                ? WorkspaceLayout.activeRowDark
                : WorkspaceLayout.activeRowLight
        }
        if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [session.name, "in \(projectName)"]
        if let ts = session.lastActiveAt {
            parts.append(Self.relativeLabel(ts))
        }
        if isActive { parts.append("active") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Relative Time

    /// Formats a past date as a compact relative string.
    /// - "just now" for < 1 min
    /// - "2m", "45m" for < 1 hr
    /// - "3h" for < 24 hr
    /// - Day abbreviation ("Mon") for < 7 days
    /// - "May 5" for older
    static func relativeLabel(_ date: Date) -> String {
        let elapsed = Date.now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        if elapsed < 604800 { return dayFormatter.string(from: date) }
        return monthDayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
