import Foundation
import Testing
@testable import Ghostty

/// Short windows: where the Witness goes when it can't stand above the
/// field (`ComposerWitnessSideways`), and how the ↓ list keeps to whole rows
/// (`ComposerDownListView.viewportHeight`, `ComposerVerticalAnchor
/// .listHeightLimit`).
struct ComposerShortWindowTests {
    private static let band: CGFloat = 28
    private static let size: CGFloat = 48
    private static let gap: CGFloat = 6
    private static let card: CGFloat = 640

    private static func placement(fieldTopY: CGFloat, width: CGFloat = 1100) -> ComposerWitnessSideways.Placement {
        ComposerWitnessSideways.placement(
            fieldTopY: fieldTopY, titlebarBand: band, containerWidth: width, cardWidth: card, size: size, gap: gap
        )
    }

    // MARK: - The threshold

    /// red mutation: compare against 0 instead of the titlebar band — the
    /// ghost then stands with its head under the traffic lights.
    @Test func ghostStandsWhileItsTopClearsTheTitlebarBand() {
        #expect(Self.placement(fieldTopY: 300) == .standing)
        #expect(Self.placement(fieldTopY: Self.band + Self.size + Self.gap) == .standing, "its top sits exactly on the band")
    }

    @Test func ghostLiesDownOnePointPastThat() {
        #expect(Self.placement(fieldTopY: Self.band + Self.size + Self.gap - 1) == .lying)
        #expect(Self.placement(fieldTopY: Self.band) == .lying)
    }

    /// With the palette's own field position: the default dials stand in a
    /// 500pt window and lie down in a 499pt one.
    @Test func thresholdForTheDefaultDialsIsAFiveHundredPointWindow() {
        let suite = UserDefaults(suiteName: "ghostties.shortWindow.threshold.test.\(UUID().uuidString)")!
        func placed(_ height: CGFloat) -> ComposerWitnessSideways.Placement {
            Self.placement(
                fieldTopY: SessionComposerPalette.fieldTopY(containerHeight: height, titlebarBand: Self.band, defaults: suite)
            )
        }
        #expect(placed(900) == .standing)
        #expect(placed(500) == .standing)
        #expect(placed(499) == .lying)
        #expect(placed(400) == .lying)
    }

    /// No room beside the card either: hidden, never clipped.
    @Test func ghostIsHiddenWhenTheWindowIsTooNarrowToLieBeside() {
        let needed = Self.card + 2 * (Self.size + Self.gap + ComposerWitnessSideways.sideMargin)
        #expect(Self.placement(fieldTopY: Self.band, width: needed) == .lying)
        #expect(Self.placement(fieldTopY: Self.band, width: needed - 1) == .hidden)
        #expect(Self.placement(fieldTopY: 300, width: 600) == .standing, "standing needs no room beside")
    }

    // MARK: - Where it lies

    @Test func lyingGhostIsAQuarterTurnLeftOfTheCardAndCentredOnTheField() {
        #expect(ComposerWitnessSideways.lyingAngleDegrees == 90)
        let lying = ComposerWitnessSideways.lyingOffset(fieldHeight: 72.6, size: Self.size, gap: Self.gap)
        #expect(lying.width == -54, "its head stops `gap` short of the card's left edge")
        #expect(lying.height == 12, "(72.6 - 48) / 2, on a whole point")
    }

    @Test func standingOffsetMatchesThePalettesOverlayOffset() {
        let standing = ComposerWitnessSideways.standingOffset(horizontalPadding: 25.6, size: Self.size, gap: Self.gap)
        #expect(standing.width == 26)
        #expect(standing.height == SessionComposerPalette.witnessOverlayYOffset(size: Self.size, ghostGap: Self.gap).rounded())
    }

    /// Whole-point offsets at both ends keep the sprite's cells (size / 12)
    /// on the pixel grid, standing and lying.
    @Test func offsetsAndTravelAreWholePointsAtEveryFieldSize() {
        for fieldSize in stride(from: CGFloat(15), through: 28, by: 0.5) {
            let padding = ComposerSingleLineTuning.horizontalPadding(fieldSize: fieldSize)
            let fieldHeight = ComposerSingleLineTuning.lineHeight(fieldSize: fieldSize)
                + 2 * ComposerSingleLineTuning.verticalPadding(fieldSize: fieldSize)
            for size in stride(from: CGFloat(12), through: 72, by: 6) {
                let standing = ComposerWitnessSideways.standingOffset(horizontalPadding: padding, size: size, gap: Self.gap)
                let lying = ComposerWitnessSideways.lyingOffset(fieldHeight: fieldHeight, size: size, gap: Self.gap)
                let travel = ComposerWitnessSideways.travel(
                    horizontalPadding: padding, fieldHeight: fieldHeight, size: size, gap: Self.gap
                )
                for value in [standing.width, standing.height, lying.width, lying.height, travel.width, travel.height] {
                    #expect(value == value.rounded(), "field \(fieldSize) size \(size) gave \(value)")
                }
                #expect(standing.width + travel.width == lying.width)
                #expect(standing.height + travel.height == lying.height)
            }
        }
    }

    // MARK: - The list keeps to whole rows

    private static let title: CGFloat = 18
    private static let row = ComposerDownListView.height(rows: 1, headers: 0, titleSize: title)
    private static let header = ComposerDownListView.height(rows: 0, headers: 1, titleSize: title)

    /// RESUME (3 rows + Show more), TEMPLATES (3 rows + Show more), PROJECTS
    /// (3 rows): the fixture's shape.
    private static let items: [ComposerDownList.Item] = ComposerDownList.items(
        resume: (0..<5).map { _ in UUID() },
        templates: (0..<5).map { _ in UUID() },
        projects: (0..<3).map { _ in UUID() },
        expanded: []
    )
    private static var contentHeight: CGFloat {
        ComposerDownListView.height(rows: 11, headers: 3, titleSize: title)
    }

    private static func viewport(_ maxHeight: CGFloat, items: [ComposerDownList.Item] = items) -> CGFloat {
        ComposerDownListView.viewportHeight(
            contentHeight: contentHeight, items: items, titleSize: title, maxHeight: maxHeight
        )
    }

    @Test func contentThatFitsShowsWhole() {
        #expect(ComposerDownListView.viewportHeight(
            contentHeight: 110, items: Self.items, titleSize: Self.title, maxHeight: 304
        ) == 110)
    }

    /// The full height is six rows under two headers, and it lands on a row.
    @Test func fullHeightIsSixRowsAndTwoHeaders() {
        let full = ComposerDownListView.maxHeight(titleSize: Self.title)
        #expect(full == 6 * Self.row + 2 * Self.header)
        #expect(Self.viewport(full) == full)
    }

    /// red mutation: return `min(contentHeight, maxHeight)` — every height
    /// below then lands part-way down a row.
    @Test func tallerContentShowsOnlyWholeRows() {
        // Every bottom edge a whole row can end on, with this content.
        var rowEnds: Set<CGFloat> = [0]
        var bottom: CGFloat = 0
        for item in Self.items {
            if case .header = item { bottom += Self.header } else { bottom += Self.row; rowEnds.insert(bottom) }
        }
        for maxHeight in stride(from: CGFloat(0), through: Self.contentHeight - 1, by: 1) {
            let shown = Self.viewport(maxHeight)
            #expect(shown <= maxHeight)
            #expect(rowEnds.contains(shown), "limit \(maxHeight) cut a row at \(shown)")
            #expect(!rowEnds.contains { $0 > shown && $0 <= maxHeight }, "limit \(maxHeight) could show more than \(shown)")
        }
    }

    /// One point short of a row drops that whole row.
    @Test func onePointShortOfARowDropsIt() {
        let threeRows = Self.header + 3 * Self.row
        #expect(Self.viewport(threeRows) == threeRows)
        #expect(Self.viewport(threeRows - 1) == Self.header + 2 * Self.row)
    }

    /// The viewport never ends on a section header with no row under it.
    @Test func neverEndsOnAHeader() {
        // RESUME header, 3 rows, Show more — then the TEMPLATES header.
        let throughShowMore = Self.header + 4 * Self.row
        #expect(Self.viewport(throughShowMore + Self.header) == throughShowMore)
        #expect(Self.viewport(throughShowMore + Self.header + Self.row - 1) == throughShowMore)
        #expect(Self.viewport(throughShowMore + Self.header + Self.row) == throughShowMore + Self.header + Self.row)
    }

    /// An expanded section (ten rows under one header) no longer lines up
    /// with six-rows-and-two-headers; the full height still shows whole rows.
    @Test func expandedSectionStillShowsWholeRowsAtFullHeight() {
        let expanded = ComposerDownList.items(
            resume: (0..<10).map { _ in UUID() }, templates: [], projects: [], expanded: [.resume]
        )
        let full = ComposerDownListView.maxHeight(titleSize: Self.title)
        #expect(Self.viewport(full, items: expanded) == Self.header + 6 * Self.row)
        #expect(Self.header + 6 * Self.row < full)
    }

    @Test func noRoomForEvenOneRowShowsNone() {
        #expect(Self.viewport(Self.header + Self.row - 1) == 0)
        #expect(Self.viewport(0) == 0)
        #expect(Self.viewport(-40) == 0)
    }

    // MARK: - The room the window leaves the list

    @Test func listHeightLimitIsTheRoomAboveTheBottomMargin() {
        #expect(ComposerVerticalAnchor.listHeightLimit(
            containerHeight: 400, listTopY: 109.6, listInset: 8, bottomMargin: 24
        ) == 258.4)
        #expect(ComposerVerticalAnchor.listHeightLimit(
            containerHeight: 100, listTopY: 109.6, listInset: 8, bottomMargin: 24
        ) == 0, "never negative")
    }

    /// The field position now reserves the list's real full height, so a
    /// 520pt window (where the last row used to be cut) holds all of it.
    @Test func a520PointWindowHoldsTheFullList() {
        let suite = UserDefaults(suiteName: "ghostties.shortWindow.520.test.\(UUID().uuidString)")!
        let height: CGFloat = 520
        let y = SessionComposerPalette.fieldTopY(containerHeight: height, titlebarBand: Self.band, defaults: suite)
        let fieldSize = ComposerSingleLineTuning.fieldSize(defaults: suite)
        let field = ComposerSingleLineTuning.lineHeight(fieldSize: fieldSize)
            + 2 * ComposerSingleLineTuning.verticalPadding(fieldSize: fieldSize)
        let full = ComposerDownListView.maxHeight(titleSize: Self.title)
        #expect(SessionComposerPalette.resumeListHeight(titleSize: Self.title) == 1 + 16 + full)
        let limit = ComposerVerticalAnchor.listHeightLimit(
            containerHeight: height, listTopY: y + field + 1 + 8, listInset: 8,
            bottomMargin: ComposerVerticalAnchor.defaultBottomMargin
        )
        #expect(limit >= full)
    }

    /// A 400pt window can't hold it: the field is already at the band, and
    /// the list shows the whole rows that fit above the bottom margin.
    @Test func a400PointWindowShowsFewerWholeRows() {
        let suite = UserDefaults(suiteName: "ghostties.shortWindow.400.test.\(UUID().uuidString)")!
        let height: CGFloat = 400
        let y = SessionComposerPalette.fieldTopY(containerHeight: height, titlebarBand: Self.band, defaults: suite)
        #expect(y == Self.band)
        let limit = ComposerVerticalAnchor.listHeightLimit(
            containerHeight: height, listTopY: y + 72.6 + 1 + 8, listInset: 8,
            bottomMargin: ComposerVerticalAnchor.defaultBottomMargin
        )
        let shown = Self.viewport(min(limit, ComposerDownListView.maxHeight(titleSize: Self.title)))
        #expect(shown == Self.header + 4 * Self.row, "RESUME, its three rows and Show more")
        #expect(y + 72.6 + 1 + 8 + shown + 8 + ComposerVerticalAnchor.defaultBottomMargin <= height)
    }

    // MARK: - Capture hooks

    @Test func windowSizeSequenceParses() {
        #expect(CaptureFixture.parseWindowSizeSequence("3:1100x700,1100x400") == CaptureFixture.WindowSizeSequence(
            interval: 3, sizes: [CGSize(width: 1100, height: 700), CGSize(width: 1100, height: 400)]
        ))
        #expect(CaptureFixture.parseWindowSizeSequence("0.5:900x500")?.interval == 0.5)
        #expect(CaptureFixture.parseWindowSizeSequence(nil) == nil)
        #expect(CaptureFixture.parseWindowSizeSequence("1100x700") == nil, "no interval")
        #expect(CaptureFixture.parseWindowSizeSequence("0:1100x700") == nil)
        #expect(CaptureFixture.parseWindowSizeSequence("3:1100x700,oops") == nil, "one bad size spoils it")
        #expect(CaptureFixture.parseWindowSizeSequence("3:") == nil)
    }
}
