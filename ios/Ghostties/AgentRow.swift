import SwiftUI

/// A sidebar-style row: ghost, name, what it is doing, age, status glyph.
struct AgentRow: View {
    var agent: Agent
    var subtitle: String?

    var body: some View {
        let detail = subtitle ?? agent.summary ?? agent.status.label
        HStack(spacing: Theme.Spacing.md) {
            GhostView(character: agent.ghostCharacter, size: 24)
                .opacity(agent.status.isGone ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.ghostRowTitle)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.ghostRowSubtitle)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text(age(agent.lastActivityAt))
                .font(.ghostRowSubtitle)
                .foregroundStyle(Theme.inkSecondary)
            StatusGlyph(status: agent.status)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.name), \(agent.status.label), \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}
