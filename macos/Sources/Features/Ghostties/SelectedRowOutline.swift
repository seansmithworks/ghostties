import AppKit
import SwiftUI

/// The selected session row's outline and tint (contract
/// `docs/plans/selected-row-mix-contract.md`): a 1pt `inkSecondary` outline
/// inset 1pt at radius 8, at `SelectedRowMix.restOutlineOpacity` over the
/// selected-row tint at rest. The rail draws it round the chip, the
/// expanded list round the whole row, and the morph between them is a
/// straight line (`box`). How it fades in and out is `SelectedRowMix`.
enum SelectedRowOutline {
    static let strokeWidth: CGFloat = 1
    static let inset: CGFloat = 1
    static let cornerRadius: CGFloat = 8

    /// The card's `box()`: the row's rect at morph 0, the chip's at 1,
    /// linear between.
    static func box(row: CGRect, chip: CGRect, morph: Double) -> CGRect {
        if morph <= 0 { return row }
        if morph >= 1 { return chip }
        let m = CGFloat(morph)
        return CGRect(
            x: SidebarMorphMetrics.lerp(row.minX, chip.minX, m),
            y: SidebarMorphMetrics.lerp(row.minY, chip.minY, m),
            width: SidebarMorphMetrics.lerp(row.width, chip.width, m),
            height: SidebarMorphMetrics.lerp(row.height, chip.height, m)
        )
    }
}

// MARK: - Surface

/// The selected-row tint and outline behind a sidebar list row
/// (`SidebarListRowChrome`), the whole row in the expanded list and the
/// hover panel, the chip on the rail, morphing between the two with the
/// row's chip (`MorphGlyphSlot`, `MorphTravel`), at this instant's
/// `SelectedRowMix.RowLook` (drawn on the row's current frame, so a new
/// row's outline grows with it). Draws nothing on a clear row. Colours are
/// resolved per render from the chrome scheme, so an appearance flip repaints.
struct SelectedRowOutlineSurface: View {
    let look: SelectedRowMix.RowLook
    let progress: CGFloat
    /// The chip's centre x in the row at progress 0, and how far it travels by 1.
    let chipCenterX: CGFloat
    let chipTravel: CGFloat
    let chipSizes: (from: CGFloat, to: CGFloat)

    var body: some View {
        Group {
            if look.outline > 0 || look.tint > 0 {
                SelectedRowOutlineShape(
                    progress: progress, look: look,
                    chipCenterX: chipCenterX, chipTravel: chipTravel, chipSizes: chipSizes
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame of the outline and tint, at this step of the morph (animatable,
/// so it rides the morph's spring with the chip).
private struct SelectedRowOutlineShape: View, Animatable {
    var progress: CGFloat
    let look: SelectedRowMix.RowLook
    let chipCenterX: CGFloat
    let chipTravel: CGFloat
    let chipSizes: (from: CGFloat, to: CGFloat)

    @ChromeScheme private var colorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let tint = SidebarColors.selectedRowTint(colorScheme)
        let ink = ChromeTheme.active(colorScheme).inkSecondaryColor
        GeometryReader { proxy in
            let row = CGRect(origin: .zero, size: proxy.size)
            let side = SidebarMorphMetrics.lerp(chipSizes.from, chipSizes.to, progress)
            let chip = CGRect(
                x: chipCenterX + chipTravel * progress - side / 2, y: (row.height - side) / 2,
                width: side, height: side
            )
            let box = SelectedRowOutline.box(row: row, chip: chip, morph: Double(progress))
            let inset = SelectedRowOutline.inset
            ZStack {
                RoundedRectangle(cornerRadius: SelectedRowOutline.cornerRadius, style: .circular)
                    .fill(tint)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .opacity(look.tint)
                // The stroke's centreline is inset 1pt, radius 8 after the inset.
                RoundedRectangle(cornerRadius: SelectedRowOutline.cornerRadius, style: .circular)
                    .stroke(ink, lineWidth: SelectedRowOutline.strokeWidth)
                    .frame(width: max(0, box.width - 2 * inset), height: max(0, box.height - 2 * inset))
                    .position(x: box.midX, y: box.midY)
                    .opacity(look.outline)
            }
        }
    }
}
