import AppKit
import SwiftUI

/// The springs the sidebar's small UI motion runs on (Sean, 2026-10-11:
/// "the motion needs a little bit of bounce/spring ... fluidity"): the
/// project accordion's fold and its chevrons and rail count badge, the
/// selection chip travelling between rows, the drag-reflow gap and section
/// reorder, and hover on row chips, rail tiles and tray buttons. One source
/// of truth, read from the Sidebar DialKit panel's "UI springs" group at the
/// moment each animation starts, so a dial change lands on the next one.
///
/// Not the sidebar ⇄ rail morph or the hover reveal: those run on the
/// morph's own clock (`WorkspaceViewContainer`).
///
/// Apple's terms: `response` is the undamped period in seconds; `bounce` 0
/// is critically damped (no overshoot), higher overshoots more (damping
/// fraction `1 - bounce`, as SwiftUI's `Spring(response:bounce:)`).
///
/// Motion rules (motion-standards): overshoot is for entrances and travel
/// only, so a close, a hover-out and any opacity or colour change take
/// `settle` — the same response, never an overshoot. Reduce Motion: no
/// spring at all; every caller snaps, as each did before (nil).
enum SidebarUISpring {
    /// The accordion's fold and unfold, its chevrons, the rail count badge.
    case fold
    /// Something travelling to a new place: the selection chip between
    /// rows, the drag-reflow gap, a section reorder.
    case move
    /// Hover on a row chip, rail tile or tray button: snappier.
    case hover

    static let defaultResponse: Double = 0.3
    static let defaultBounce: Double = 0.15
    static let defaultHoverResponse: Double = 0.2

    /// The selection chip's `matchedGeometryEffect` id
    /// (`SidebarRowChipBackground`).
    static let selectionChipID = "sidebar.selectionChip"

    struct Parameters: Equatable {
        var response: Double
        var bounce: Double

        /// `1 - bounce`, bounce held to 0...0.9 so a dial can't reach an
        /// undamped (never-settling) spring.
        var dampingFraction: Double { 1 - min(max(bounce, 0), 0.9) }
        /// Never 0: SwiftUI needs a period.
        var safeResponse: Double { max(response, 0.01) }
    }

    func parameters(defaults: UserDefaults = SidebarDialTuning.store) -> Parameters {
        switch self {
        case .fold, .move:
            Parameters(response: SidebarDialTuning.uiSpringResponse(defaults: defaults),
                       bounce: SidebarDialTuning.uiSpringBounce(defaults: defaults))
        case .hover:
            Parameters(response: SidebarDialTuning.uiSpringHoverResponse(defaults: defaults),
                       bounce: SidebarDialTuning.uiSpringBounce(defaults: defaults))
        }
    }

    /// An entrance or a travel: overshoots by the "Bounce" dial. nil under
    /// Reduce Motion.
    func animation(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        defaults: UserDefaults = SidebarDialTuning.store
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let p = parameters(defaults: defaults)
        return .spring(response: p.safeResponse, dampingFraction: p.dampingFraction)
    }

    /// A close, a hover-out, or an opacity or colour change: the same
    /// response, critically damped, so it never overshoots. nil under
    /// Reduce Motion.
    func settle(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        defaults: UserDefaults = SidebarDialTuning.store
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: parameters(defaults: defaults).safeResponse, dampingFraction: 1)
    }

    /// `animation` when something is appearing or opening, `settle` when it
    /// is closing or going away.
    func animation(
        entering: Bool,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        defaults: UserDefaults = SidebarDialTuning.store
    ) -> Animation? {
        entering
            ? animation(reduceMotion: reduceMotion, defaults: defaults)
            : settle(reduceMotion: reduceMotion, defaults: defaults)
    }
}

// MARK: - Selection chip namespace

private struct SidebarSelectionChipNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The list's namespace for the selection chip: with one set, the chip
    /// travels from the old selected row to the new one on the `.move`
    /// spring; without one (a lone row, a test), it appears in place.
    var sidebarSelectionChipNamespace: Namespace.ID? {
        get { self[SidebarSelectionChipNamespaceKey.self] }
        set { self[SidebarSelectionChipNamespaceKey.self] = newValue }
    }
}
