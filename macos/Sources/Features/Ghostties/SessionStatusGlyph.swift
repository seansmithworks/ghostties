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

/// A single monospaced type glyph in a session row's status slot, replacing
/// the ghost as the status signal there — pattern D, "type is the icon"
/// (BACKLOG J, K; Sean 2026-09-13: "lets try D for the moment. simplifying
/// things down is a good idea."). A row still gets exactly ONE status icon —
/// see `agent-craft.md`'s Gotcha on ghost + glyph never coexisting on a row.
///
/// This does NOT replace `GhostCharacterView` anywhere else — project rollup
/// rows, empty states, the ghost picker, and app identity keep the ghost.
///
/// The working-state spinner is isolated in its own `TimelineView` so only
/// rows that are actually working redraw each frame; everything else in this
/// view is a static `Text`. See `project_perf-contextmenu-render-cost`.
struct SessionStatusGlyph: View {
    let kind: SessionStatusGlyphKind
    var size: CGFloat = WorkspaceLayout.sessionGhostSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let spinnerFrames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"]
    private static let spinnerFrameInterval: TimeInterval = 0.08

    var body: some View {
        Group {
            switch kind {
            case .working:
                if reduceMotion {
                    spinnerGlyph("…", color: secondaryTextColor)
                } else {
                    TimelineView(.periodic(from: .now, by: Self.spinnerFrameInterval)) { context in
                        let frameIndex = Int(
                            context.date.timeIntervalSinceReferenceDate / Self.spinnerFrameInterval
                        ) % Self.spinnerFrames.count
                        spinnerGlyph(Self.spinnerFrames[frameIndex], color: secondaryTextColor)
                    }
                }
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

    /// The braille spinner frames (and their Reduce Motion stand-in, `…`)
    /// draw a small ink box within their character cell — the dots/ellipsis
    /// only fill roughly 60% of the glyph's advance width, versus ~85% for
    /// `✓`/`✕`. At the shared `size * 0.8` font size the spinner reads as two
    /// faint dots next to the other glyphs' full marks. Scaling the font to
    /// `size * 1.1` (~1.4x the base) and bumping the weight from `.medium` to
    /// `.bold` brings the spinner's visual ink box in line with `✓`/`✕`
    /// without changing the slot frame, so rows don't shift.
    private func spinnerGlyph(_ symbol: String, color: Color) -> some View {
        Text(symbol)
            .font(.system(size: size * 1.1, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .minimumScaleFactor(0.6)
    }
}
