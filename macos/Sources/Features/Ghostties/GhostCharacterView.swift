import SwiftUI
import GhosttiesCore

/// Whether the ghost is rendered filled or as an outline stroke.
enum GhostStyle {
    case filled
    case outline
}

/// A `GhostCharacter`'s pixel grid as a `Shape`.
///
/// `Shape.path(in:)` receives its rect directly from SwiftUI's layout pass —
/// unlike `GeometryReader`, it doesn't introduce its own layout container in
/// the view tree (relevant here: this exact view tree was flagged in
/// `project_perf-contextmenu-render-cost.md` for per-row layout cost). Also
/// trivially `Equatable` since it only carries a `GhostCharacter` value.
struct GhostShape: Shape, Equatable {
    let character: GhostCharacter

    func path(in rect: CGRect) -> Path {
        character.drawPath(in: rect)
    }
}

/// Renders a `GhostCharacter` pixel grid as a crisp vector shape.
///
/// Sizing comes from whatever frame the parent provides (e.g.
/// `.frame(width:14, height:14)`), same as before — `GhostShape` gets its
/// rect from layout with no `GeometryReader`.
struct GhostCharacterView: View {
    let character: GhostCharacter
    var color: Color = .primary
    var style: GhostStyle = .filled

    var body: some View {
        Group {
            switch style {
            case .filled:
                GhostShape(character: character).fill(color)
            case .outline:
                GhostShape(character: character).stroke(color, lineWidth: 1)
            }
        }
        .accessibilityLabel("\(character.rawValue) ghost")
    }
}
