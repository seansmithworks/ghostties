import SwiftUI

/// One agent waiting on the user. Options answer in place, the recommended
/// one filled with ink; a free-text question hands off with `onReply`.
struct AskCard: View {
    var ask: Ask
    var agent: Agent?
    var onAnswer: (AskAnswer) -> Void
    var onReply: (() -> Void)?

    private var primaryId: String? { ask.recommendedOptionId ?? ask.options.first?.id }
    private var recommended: AskOption? { ask.options.first { $0.id == primaryId } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                GhostView(character: agent?.ghostCharacter, size: 16)
                Text("\(agent?.name ?? "Agent") · \(ask.kind.label) · \(age(ask.createdAt))")
                    .font(.ghostRowSubtitle)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Text(ask.prompt)
                .font(.ghostRowTitle)
                .foregroundStyle(Theme.ink)
            if let recommended, let detail = recommended.detail {
                Text("\(recommended.label): \(detail)")
                    .font(.ghostRowSubtitle)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: Theme.Spacing.sm) {
                if ask.options.isEmpty {
                    if let onReply {
                        PillButton(label: "Reply", primary: true, action: onReply)
                    }
                } else {
                    ForEach(ask.options) { option in
                        PillButton(label: option.label, primary: option.id == primaryId) {
                            onAnswer(AskAnswer(optionId: option.id))
                        }
                        .accessibilityHint(option.detail ?? "")
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Solid ink when primary, a hairline outline otherwise. No accent colour.
struct PillButton: View {
    var label: String
    var primary = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.ghostRowSubtitle.weight(.semibold))
                .foregroundStyle(primary ? Theme.canvas : Theme.ink)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 44)
                .background {
                    if primary {
                        Capsule().fill(Theme.ink)
                    } else {
                        Capsule().strokeBorder(Theme.border, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension AskKind {
    var label: String {
        switch self {
        case .question: "Question"
        case .permission: "Permission"
        case .decision: "Decision"
        }
    }
}
