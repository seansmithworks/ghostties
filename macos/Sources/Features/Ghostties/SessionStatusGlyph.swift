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

    private static let spinnerFrameInterval: TimeInterval = 0.08

    var body: some View {
        Group {
            switch kind {
            case .working:
                if reduceMotion {
                    glyph("…", color: secondaryTextColor)
                } else {
                    TimelineView(.periodic(from: .now, by: Self.spinnerFrameInterval)) { context in
                        let frameIndex = Int(
                            context.date.timeIntervalSinceReferenceDate / Self.spinnerFrameInterval
                        ) % SpinnerDotFrame.litDots.count
                        spinnerDotGrid(SpinnerDotFrame.litDots[frameIndex], color: secondaryTextColor)
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

    /// Draws one spinner frame as a 2×3 grid of filled dots instead of a
    /// braille character — a braille glyph puts its ink in a small fraction
    /// of its character box (~60% of the advance width at best), so scaling
    /// its font size is guesswork against font metrics and it still read as
    /// 2–3 faint dots at sidebar size (`26dbc54b4`, reverted here). Drawing
    /// the dots directly is sized from the slot, not from a font:
    ///   - dot diameter: `size * 0.16` (~2.2pt at the 14pt sidebar size)
    ///   - column spacing (center-to-center): `size * 0.29` (~4.1pt)
    ///   - row spacing (center-to-center): `size * 0.31` (~4.3pt)
    /// That puts the grid's ink box at roughly `size * 0.45` wide by
    /// `size * 0.78` tall — narrow-tall like a real braille cell, and in the
    /// same ~70-80%-of-slot ink-height range as `✓`/`✕` so the spinner no
    /// longer reads smaller than its neighbors. Unlit dots are hidden
    /// entirely, not dimmed, matching the single-ink look of the other
    /// glyphs in this slot.
    private func spinnerDotGrid(_ litDots: Set<Int>, color: Color) -> some View {
        let dotDiameter = size * 0.16
        let colSpacing = size * 0.29
        let rowSpacing = size * 0.31
        return Canvas { context, canvasSize in
            let originX = canvasSize.width / 2
            let originY = canvasSize.height / 2
            for dot in 1...6 {
                guard litDots.contains(dot) else { continue }
                // Dots 1-3 sit in the left column, 4-6 in the right column;
                // within a column, position 0/1/2 maps to top/middle/bottom.
                let column: CGFloat = dot <= 3 ? -0.5 : 0.5
                let row: CGFloat = CGFloat((dot - 1) % 3) - 1
                let center = CGPoint(
                    x: originX + column * colSpacing,
                    y: originY + row * rowSpacing
                )
                let rect = CGRect(
                    x: center.x - dotDiameter / 2,
                    y: center.y - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
