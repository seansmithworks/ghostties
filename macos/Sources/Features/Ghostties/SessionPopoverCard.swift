import SwiftUI
import GhosttiesCore

/// The card's canvas values (pen.dev Flow 09 `b8Wi6z`, option 03's Command
/// Hero block). Where DESIGN.md has a token (text greys, SF type) the card
/// uses it; the rest are canvas values with no token yet, kept in one place.
enum SessionPopoverLayout {
    static let width: CGFloat = 288
    static let cornerRadius: CGFloat = 12
    /// Gap between the sidebar/rail edge and the card.
    static let edgeGap: CGFloat = 8
    /// Keep the card this far inside the window when clamping.
    static let windowMargin: CGFloat = 8
    /// Transparent room around the card so its two shadows aren't clipped by
    /// the hosting view. Hit-testing ignores it — see `SessionPopoverHostingView`.
    static let shadowInset: CGFloat = 48

    /// Wait before the card appears over a hovered row.
    static let hoverDelay: TimeInterval = 0.35
    /// Wait before it goes away after the pointer leaves the row AND the card,
    /// so the pointer can cross the 8pt gap into the card.
    static let dismissGrace: TimeInterval = 0.25
    static let fadeDuration: TimeInterval = 0.14
    /// Same 120ms cross-fade Flow 05 uses under Reduce Motion.
    static let reducedMotionFadeDuration: TimeInterval = WorkspaceLayout.sidebarReducedMotionCrossfadeDuration
    static let slideDistance: CGFloat = 4

    static let maxCommandLines = 3
    static let maxPromptLines = 2

    /// The gap above a needs-you card's "Answer in terminal →".
    static let actionsTopGap: CGFloat = 8
}

/// The popover card: the card shell around one content block (a Bash command,
/// a tool approval, or what a running session is doing), set directly on the
/// white card — no inner block (Sean, 2026-10-04: one card). Clicking the row
/// opens the session, moving off it dismisses the card. A session that needs
/// the user leads with its question and ends with "Answer in terminal →".
/// Approve/Deny live on the sidebar row only (`SessionRowActionLine`), never
/// here.
struct SessionPopoverCard: View {
    @ObservedObject var model: SessionPopoverModel
    let onHover: (Bool) -> Void

    @ChromeScheme private var colorScheme

    private var dark: Bool { colorScheme == .dark }
    private var primaryText: Color { dark ? Color(white: 0.94) : Color(white: 0x1A / 255.0) }
    private var secondaryText: Color { ChromeTheme.active(colorScheme).inkSecondaryColor }
    private var surface: Color { Color(ChromeTheme.active(colorScheme).lifted(.container)) }
    private var hairline: Color { dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07) }

    var body: some View {
        Group {
            if let content = model.content {
                card(content)
                    .padding(SessionPopoverLayout.shadowInset)
            }
        }
    }

    private func card(_ content: SessionPopoverContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            blockView(content)
        }
        .frame(width: SessionPopoverLayout.width)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: SessionPopoverLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SessionPopoverLayout.cornerRadius, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.078), radius: 5, x: 0, y: 2)
        .shadow(color: Color.black.opacity(0.122), radius: 18, x: 0, y: 14)
        .onHover(perform: onHover)
    }

    @ViewBuilder
    private func blockView(_ content: SessionPopoverContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // A needs-you card leads with what is being asked.
            if let question = content.question {
                Text(question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primaryText)
                    .lineLimit(SessionPopoverLayout.maxPromptLines)
            }
            switch content.block {
            case let .command(command, description):
                Text("$ \(command)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(primaryText)
                    .lineLimit(SessionPopoverLayout.maxCommandLines)
                secondary(description)
            case let .tool(headline, path, description):
                Text(headline)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)
                if let path {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                secondary(description)
            case let .running(prompt, step):
                Text(prompt)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primaryText)
                    .lineLimit(SessionPopoverLayout.maxPromptLines)
                secondary(step)
            case .freeform:
                EmptyView()
            }
            if content.needsYou {
                answerInTerminal
                    .padding(.top, SessionPopoverLayout.actionsTopGap)
            }
        }
        .truncationMode(.tail)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WorkspaceLayout.sessionPopoverContentPadding)
    }

    /// The hand-off every needs-you card carries.
    private var answerInTerminal: some View {
        Button {
            model.onAnswerInTerminal?()
        } label: {
            Text("Answer in terminal →")
                .font(.system(size: 11, weight: .medium))
                .underline()
                .foregroundStyle(primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this session's terminal")
    }

    @ViewBuilder
    private func secondary(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
