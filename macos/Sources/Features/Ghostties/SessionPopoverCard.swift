import SwiftUI
import GhosttiesCore

/// The card's canvas values (pen.dev Flow 09 `b8Wi6z`, options 01 + 03).
/// Where DESIGN.md has a token (text greys, the ghost red, SF type) the card
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

    // Canvas values with no token.
    static let alertRed = Color(red: 0xD9 / 255.0, green: 0x48 / 255.0, blue: 0x3F / 255.0)
    static let runningGreen = Color(red: 0x2F / 255.0, green: 0x9E / 255.0, blue: 0x5B / 255.0)
}

/// The popover card itself: option 01's shell and header, option 03's
/// Command Hero as the Bash body. Open/Close only — no approve/deny.
struct SessionPopoverCard: View {
    @ObservedObject var model: SessionPopoverModel
    let onOpen: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }
    private var primaryText: Color { dark ? Color(white: 0.94) : Color(white: 0x1A / 255.0) }
    private var secondaryText: Color {
        dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }
    private var surface: Color { dark ? WorkspaceLayout.expandedContainerDark : .white }
    private var block: Color {
        dark ? Color.white.opacity(0.07) : Color(red: 0xF6 / 255.0, green: 0xF3 / 255.0, blue: 0xEF / 255.0)
    }
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
            header(content)
            bodyBlock(content.body)
            Rectangle().fill(Color.black.opacity(dark ? 0.2 : 0.06)).frame(height: 1)
            footer
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

    // MARK: Header

    private func header(_ content: SessionPopoverContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                GhostCharacterView(character: .blinky, color: secondaryText, style: .filled)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(content.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(content.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let time = content.relativeTime {
                    Text(time)
                        .font(.system(size: 10))
                        .foregroundStyle(dark ? WorkspaceLayout.textSecondaryDark : Color(white: 0x9A / 255.0))
                }
            }
            HStack(spacing: 6) {
                Circle().fill(dotColor(content.statusKind)).frame(width: 6, height: 6)
                Text(content.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(content.isApproval ? SessionPopoverLayout.alertRed : primaryText)
                if let detail = content.statusDetail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dotColor(_ kind: SessionPopoverContent.StatusKind) -> Color {
        switch kind {
        case .needsApproval: return WorkspaceLayout.selectedGhostRed
        case .running: return SessionPopoverLayout.runningGreen
        case .error: return SessionPopoverLayout.alertRed
        case .idle, .stopped: return secondaryText.opacity(0.6)
        }
    }

    // MARK: Body

    @ViewBuilder
    private func bodyBlock(_ body: SessionPopoverContent.Body) -> some View {
        switch body {
        case .none:
            EmptyView()
        case let .commandHero(command, description):
            VStack(alignment: .leading, spacing: 6) {
                Text("$ \(command)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(primaryText)
                    .lineLimit(SessionPopoverLayout.maxCommandLines)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(block))
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
        case let .miniTerminal(lines):
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(color(for: line.tone))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(block))
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
        }
    }

    private func color(for tone: SessionPopoverContent.TerminalLine.Tone) -> Color {
        switch tone {
        case .primary: return primaryText
        case .secondary: return secondaryText
        case .alert: return SessionPopoverLayout.alertRed
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            PopoverButton(title: "Open", isPrimary: true, dark: dark, action: onOpen)
            PopoverButton(title: "Close", isPrimary: false, dark: dark, action: onClose)
            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

private struct PopoverButton: View {
    let title: String
    let isPrimary: Bool
    let dark: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        if isPrimary { return dark ? Color(white: 0.1) : .white }
        return dark ? Color(white: 0.94) : Color(white: 0x1A / 255.0)
    }

    private var fill: Color {
        if isPrimary {
            let base = dark ? Color(white: 0.94) : Color(white: 0x1A / 255.0)
            return isHovered ? base.opacity(0.85) : base
        }
        let base = dark ? Color.white : Color.black
        return base.opacity(isHovered ? 0.12 : 0.04)
    }
}
