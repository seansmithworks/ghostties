import SwiftUI

/// Agent replies read as plain text on the canvas, like terminal output; the
/// user's own lines sit in a quiet ink-tinted bubble on the right. No accent.
/// Status and system messages are one centred secondary line.
struct MessageRow: View {
    var message: Message
    var pending = false

    var body: some View {
        if message.authorKind == .system || message.kind == .status {
            Text(message.body)
                .font(.ghostRowSubtitle)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if message.authorKind == .user {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 2) {
                    if message.kind == .answer {
                        Text("ANSWERED").font(.ghostCaption).foregroundStyle(Theme.inkSecondary)
                    }
                    Text(message.body)
                        .font(.ghostBody)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                }
                .opacity(pending ? 0.5 : 1)
            }
        } else {
            Text(message.body)
                .font(.ghostBody)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(.trailing, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
