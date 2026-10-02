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

    /// The word this glyph speaks to VoiceOver — the single source of truth
    /// for status wording, so a row's visible glyph and its accessibility
    /// label can never disagree. `.done` also covers `.waiting`'s silent
    /// fallback (see `SessionIndicatorState.statusGlyphKind`), so it speaks
    /// "idle" rather than a done-specific word.
    var spokenStatus: String {
        switch self {
        case .working:    return "working"
        case .needsInput: return "needs your input"
        case .done:       return "idle"
        case .error:      return "error"
        case .stopped:    return "stopped"
        }
    }
}

/// Pure mapping from a spinner animation frame index to the braille dot
/// numbers (1–6) it lights, kept free of SwiftUI so it's testable without a
/// view host. Dot numbers follow standard braille cell numbering — 1, 2, 3
/// top-to-bottom in the left column, 4, 5, 6 top-to-bottom in the right
/// column. Dots 7/8 (the second row) are never lit: none of these 8 frames
/// use them.
///
/// Named after the braille characters it replaces — `SessionStatusGlyph`
/// used to render these frames as literal ⠋⠙⠹⠸⠼⠴⠦⠧ text, which drew as 2–3
/// tiny dots at sidebar size because a braille glyph puts its ink in a small
/// fraction of its character box. Drawing the same dot sets directly, sized
/// from the slot instead of from font metrics, is what fixes that.
enum SpinnerDotFrame {
    /// Index-aligned with the animation cycle. Each entry is the exact dot
    /// set the braille character it replaces would have lit — e.g. frame 0
    /// is ⠋, dots 1, 2, 4.
    static let litDots: [Set<Int>] = [
        [1, 2, 4],       // ⠋
        [1, 4, 5],       // ⠙
        [1, 4, 5, 6],    // ⠹
        [4, 5, 6],       // ⠸
        [3, 4, 5, 6],    // ⠼
        [3, 5, 6],       // ⠴
        [2, 3, 6],       // ⠦
        [1, 2, 3, 6],    // ⠧
    ]
}

extension SessionIndicatorState {
    /// Maps this indicator state to the glyph that stands in for it in a
    /// session row's status slot (BACKLOG J/K, decision 2026-09-13, "for the
    /// moment"). `.processing`/`.longRunning` read as "working" — observed
    /// activity, not blocked on the user. `.waiting` is a FALLBACK returned
    /// when there's no observed evidence either way (see
    /// `SessionCoordinator.indicatorState(for:)`), not confirmed work, so it
    /// reads as the same low-salience `.done` state as `.idle` rather than
    /// spinning indefinitely — a silent shell session launched via `cco`
    /// would otherwise show a permanent spinner once hook state goes stale.
    var statusGlyphKind: SessionStatusGlyphKind {
        switch self {
        case .processing, .longRunning: return .working
        case .waiting:                  return .done
        case .needsAttention:           return .needsInput
        case .idle:                     return .done
        case .error:                    return .error
        case .inactive:                 return .stopped
        }
    }
}

/// The session row's status slot, drawn as a ghost — Flow 07 (pen.dev frame
/// `t4XvdY`) round 6, superseding pattern D's monospaced type glyph
/// (✓/?/⋮): the design uses one ghost silhouette on every row regardless of
/// status, gray by default and red only on the selected row (`isSelected`).
/// A row still gets exactly ONE status icon — see `agent-craft.md`'s Gotcha
/// on ghost + glyph never coexisting on a row; this glyph IS that icon now.
///
/// `kind` is kept (not removed) purely as the accessibility source of truth
/// — `SessionStatusGlyphKind.spokenStatus` still drives VoiceOver via
/// `RecentsRowView.accessibilityLabel` and `SessionDetailView` — even though
/// the visual no longer branches on it. `stopped` still renders nothing, so
/// an inactive session's row stays glyph-free as before.
///
/// This does NOT replace `GhostCharacterView` anywhere else — project rollup
/// rows, empty states, the ghost picker, and app identity already used the
/// ghost and are unaffected.
struct SessionStatusGlyph: View {
    let kind: SessionStatusGlyphKind
    var size: CGFloat = WorkspaceLayout.sessionGhostSize
    /// True on the selected/active row — renders the ghost in
    /// `WorkspaceLayout.selectedGhostRed` instead of the muted secondary
    /// color, per Flow 07's "portfolio" row.
    var isSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if kind == .stopped {
                Color.clear
            } else {
                GhostCharacterView(character: .blinky, color: ghostColor, style: .filled)
            }
        }
        .frame(width: size, height: size)
    }

    private var ghostColor: Color {
        isSelected ? WorkspaceLayout.selectedGhostRed : secondaryTextColor
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }
}
