import SwiftUI

/// The Mac sidebar's status slot ("type is the icon", DESIGN.md §4): one
/// monospaced glyph. Braille spinner while working, `?` in full ink when it
/// needs you (the only emphasis), `✓` idle, empty when ended or offline.
/// Reduce Motion swaps the spinner for a static `…`.
struct StatusGlyph: View {
    var status: AgentStatus
    var size: CGFloat = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"]

    var body: some View {
        Group {
            if status == .busy && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
                    let index = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
                    glyph(Self.frames[index])
                }
            } else {
                glyph(staticGlyph)
            }
        }
        .frame(width: size)
        .accessibilityLabel(status.label)
    }

    private var staticGlyph: String {
        switch status {
        case .busy: "…"
        case .needsInput, .needsPermission: "?"
        case .idle: "✓"
        case .ended, .offline: ""
        }
    }

    private func glyph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: status.needsYou ? .bold : .regular, design: .monospaced))
            .foregroundStyle(status.needsYou ? Theme.ink : Theme.inkSecondary)
    }
}
