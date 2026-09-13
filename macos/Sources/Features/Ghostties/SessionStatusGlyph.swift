import SwiftUI

/// The five glyph states a session row's status slot can render.
///
/// Collapses `SessionIndicatorState`'s seven cases down to the vocabulary
/// pattern D ("type is the icon") needs — see `statusGlyphKind` below for
/// the mapping. Does not change how `SessionIndicatorState` itself is
/// derived or read.
enum SessionStatusGlyphKind: Equatable {
    case working
    case needsInput
    case done
    case error
    case stopped
}

extension SessionIndicatorState {
    /// Maps this indicator state to the glyph that stands in for it in a
    /// session row's status slot (BACKLOG J/K, decision 2026-09-13, "for the
    /// moment"). `.processing`/`.longRunning`/`.waiting` all read as "working"
    /// — none of them are blocked on the user, so one spinner covers all three.
    var statusGlyphKind: SessionStatusGlyphKind {
        switch self {
        case .processing, .longRunning, .waiting: return .working
        case .needsAttention:                     return .needsInput
        case .idle:                               return .done
        case .error:                               return .error
        case .inactive:                            return .stopped
        }
    }
}

/// A single monospaced type glyph in a session row's status slot, replacing
/// the ghost as the status signal there — pattern D, "type is the icon"
/// (BACKLOG J, K; Sean 2026-09-13: "lets try D for the moment. simplifying
/// things down is a good idea."). A row still gets exactly ONE status icon —
/// see `agent-craft.md`'s Gotcha on ghost + glyph never coexisting on a row.
///
/// This does NOT replace `GhostCharacterView` anywhere else — project rollup
/// rows, empty states, the ghost picker, and app identity keep the ghost.
///
/// The working state is a static `…` — Claude sessions stay busy for minutes
/// at a time, so an animated spinner there reads as constantly cycling
/// rather than as a truthful moment-to-moment signal (Sean 2026-09-13).
struct SessionStatusGlyph: View {
    let kind: SessionStatusGlyphKind
    var size: CGFloat = WorkspaceLayout.sessionGhostSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch kind {
            case .working:
                glyph("…", color: secondaryTextColor)
            case .needsInput:
                // The only emphasis glyph — primary text color, no accent.
                glyph("?", color: .primary)
            case .done:
                glyph("✓", color: secondaryTextColor)
            case .error:
                glyph("✕", color: secondaryTextColor)
            case .stopped:
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }

    private func glyph(_ symbol: String, color: Color) -> some View {
        Text(symbol)
            .font(.system(size: size * 0.8, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .minimumScaleFactor(0.6)
    }
}
