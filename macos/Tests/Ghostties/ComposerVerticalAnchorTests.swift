import Foundation
import Testing
@testable import Ghostty

/// `ComposerVerticalAnchor.fieldTopY` — where the composer's field card sits
/// — and the palette's wrapper that feeds it the real dial values.
struct ComposerVerticalAnchorTests {
    private static let band: CGFloat = 28
    private static let ghost: CGFloat = 54
    private static let field: CGFloat = 72.6
    private static let list: CGFloat = 253
    private static let margin: CGFloat = 24

    private static func y(height: CGFloat, fraction: CGFloat = 1.0 / 3) -> CGFloat {
        ComposerVerticalAnchor.fieldTopY(
            containerHeight: height,
            fraction: fraction,
            titlebarBand: band,
            ghostClearance: ghost,
            fieldHeight: field,
            listHeight: list,
            bottomMargin: margin
        )
    }

    @Test func tallWindowPutsTheFieldTopAtTheDefaultThird() {
        #expect(Self.y(height: 900) == 300)
        #expect(Self.y(height: 800) == 266, "266.67 rounds down to a whole point")
    }

    @Test func fieldTopIsAlwaysAWholePoint() {
        for height in stride(from: CGFloat(0), through: 1400, by: 7.3) {
            let y = Self.y(height: height)
            #expect(y == y.rounded(), "height \(height) gave \(y)")
        }
    }

    @Test func shortWindowMovesTheFieldUpOnlyEnoughToKeepAFullListOnScreen() {
        let height: CGFloat = 480
        let y = Self.y(height: height)
        #expect(y < height / 3, "the third (160) would push the list off screen")
        #expect(y + Self.field + Self.list + Self.margin <= height)
        #expect(y + 1 + Self.field + Self.list + Self.margin > height, "moved up further than needed")
    }

    @Test func neverAboveTheTitlebarBand() {
        #expect(Self.y(height: 300) == Self.band, "the list can't fit at all; the band still holds")
        #expect(Self.y(height: 0) == Self.band)
        #expect(Self.y(height: 10) == Self.band)
        #expect(Self.y(height: -50) == Self.band)
    }

    @Test func keepsTheGhostBelowTheBandWhenTheListStillFits() {
        // A low fraction would put the ghost under the titlebar band.
        #expect(Self.y(height: 900, fraction: 0.05) == Self.band + Self.ghost)
    }

    @Test func theListWinsOverTheGhostWhenBothCannotHold() {
        // Room for field + list only 60pt down: less than band + ghost (82).
        let height = 60 + Self.field + Self.list + Self.margin
        let y = Self.y(height: height)
        #expect(y == 60)
        #expect(y < Self.band + Self.ghost)
    }

    /// The palette's wrapper reads nothing that opening the Resume list,
    /// typing, or the layout dial changes: the same window gives the same y
    /// for the list layout and the two-column one.
    @Test func paletteFieldTopIsTheSameForEveryResumeLayout() {
        let suite = UserDefaults(suiteName: "ghostties.verticalAnchor.layout.test.\(UUID().uuidString)")!
        suite.set(ComposerResumeLayout.list.rawValue, forKey: ComposerResumeLayout.storageKey)
        let asList = SessionComposerPalette.fieldTopY(containerHeight: 720, titlebarBand: Self.band, defaults: suite)
        suite.set(ComposerResumeLayout.columns.rawValue, forKey: ComposerResumeLayout.storageKey)
        let asColumns = SessionComposerPalette.fieldTopY(containerHeight: 720, titlebarBand: Self.band, defaults: suite)
        #expect(asList == asColumns)
        #expect(asList == 240)
    }

    @Test func paletteFieldTopFollowsTheFractionDial() {
        let suite = UserDefaults(suiteName: "ghostties.verticalAnchor.fraction.test.\(UUID().uuidString)")!
        suite.set(0.25, forKey: ComposerFieldTopFraction.storageKey)
        #expect(SessionComposerPalette.fieldTopY(containerHeight: 1000, titlebarBand: Self.band, defaults: suite) == 250)
    }

    /// At a short height the clamp keeps the field and five Resume rows on
    /// screen, measured with the palette's own list height.
    @Test func paletteClampKeepsFiveResumeRowsOnScreen() {
        let suite = UserDefaults(suiteName: "ghostties.verticalAnchor.clamp.test.\(UUID().uuidString)")!
        let height: CGFloat = 480
        let y = SessionComposerPalette.fieldTopY(containerHeight: height, titlebarBand: Self.band, defaults: suite)
        let fieldSize = ComposerSingleLineTuning.fieldSize(defaults: suite)
        let field = ComposerSingleLineTuning.lineHeight(fieldSize: fieldSize)
            + 2 * ComposerSingleLineTuning.verticalPadding(fieldSize: fieldSize)
        let list = SessionComposerPalette.resumeListHeight(titleSize: ComposerSingleLineTuning.rowSize(defaults: suite))
        #expect(y < (height / 3).rounded(.down))
        #expect(y + field + list + ComposerVerticalAnchor.defaultBottomMargin <= height)
    }

    @Test func resumeListHeightCoversFiveRowsAndAHeader() {
        let rows = ComposerDownListView.height(rows: 5, headers: 1, titleSize: 18)
        #expect(SessionComposerPalette.resumeListHeight(titleSize: 18) > rows)
        #expect(ComposerDownListView.height(rows: 1, headers: 0, titleSize: 18) == 42)
        #expect(ComposerDownListView.maxHeight(titleSize: 18) == ComposerDownListView.height(rows: 6, headers: 2, titleSize: 18))
    }
}
