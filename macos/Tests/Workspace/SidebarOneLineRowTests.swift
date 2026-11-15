import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// One view's thread rows are one line, glyph and title, unless the thread
/// needs the user (`SessionRowSecondLine`): which statuses draw the second
/// line, what a one-line row measures, that VoiceOver still hears every
/// row's status, and the rule that keeps the selected row clear of the
/// tray when the list's layout moves it (`SidebarSelectionFollow.KeepClear`).
@MainActor
final class SidebarOneLineRowTests: PrivateDefaultsTestCase {
    // MARK: - Which rows draw a second line

    func testOnlyNeedsYouAndErrorDrawASecondLine() {
        XCTAssertTrue(SessionRowSecondLine.isShown(.needsInput))
        XCTAssertTrue(SessionRowSecondLine.isShown(.error))
        XCTAssertFalse(SessionRowSecondLine.isShown(.working))
        XCTAssertFalse(SessionRowSecondLine.isShown(.done))
        XCTAssertFalse(SessionRowSecondLine.isShown(.stopped))
    }

    /// The words are the status vocabulary's, unchanged.
    func testTheSecondLinesWordingIsUnchanged() {
        XCTAssertEqual(SessionStatusGlyphKind.needsInput.groupedRowSubtitle, "needs you")
        XCTAssertEqual(SessionStatusGlyphKind.error.groupedRowSubtitle, "error")
        XCTAssertEqual(SessionRowPrompt(question: nil, approvalPrompt: nil).subtitle, "needs you")
        XCTAssertEqual(SessionRowPrompt(question: "Run npm test?", approvalPrompt: nil).subtitle, "Run npm test?")
    }

    func testARowsSecondLineIsItsSubtitleOnlyWhileShown() {
        func line(_ subtitle: String?, shows: Bool, hook: Bool = false) -> String? {
            RecentsRowView.secondLine(subtitle: subtitle, projectName: "atlas-api", showsSubtitle: shows, hookUnconfirmed: hook)
        }
        XCTAssertNil(line("working", shows: false), "a working row is one line")
        XCTAssertNil(line("done", shows: false))
        XCTAssertNil(line("stopped", shows: false))
        XCTAssertEqual(line("needs you", shows: true), "needs you")
        XCTAssertEqual(line("error", shows: true), "error")
        XCTAssertEqual(line(nil, shows: true), "atlas-api", "outside one view the row still names its project")
        XCTAssertEqual(line("working", shows: false, hook: true), "Approve the Ghostties hook in Codex", "the hook hint asks something of the user")
    }

    // MARK: - Height

    func testAOneLineRowIsThirtyTwoPointsAndOnTheGrid() {
        let oneLine = SidebarListRowHeight.row(hasSubtitle: false, hasActions: false)
        XCTAssertEqual(oneLine, 32)
        XCTAssertEqual(oneLine.truncatingRemainder(dividingBy: 8), 0, "on the 8pt grid")
        XCTAssertEqual(SidebarListRowHeight.row(hasSubtitle: true, hasActions: false), SidebarDialTuning.rowHeight(), "two lines: the dial's height")
        XCTAssertEqual(
            SidebarListRowHeight.row(hasSubtitle: true, hasActions: true),
            SidebarDialTuning.rowHeight() + SessionRowActionLine.addedHeight, "needs you: two lines and the action line"
        )
        XCTAssertEqual(SidebarListRowHeight.row(hasActions: false), SidebarDialTuning.rowHeight(), "callers that name no lines get two")
    }

    func testTheRailsRowKeepsTheDialsHeight() {
        XCTAssertEqual(SidebarListRowHeight.railRow(hasActions: false), SidebarDialTuning.rowHeight())
        XCTAssertEqual(SidebarListRowHeight.railRow(hasActions: true), SidebarDialTuning.rowHeight() + SessionRowActionLine.addedHeight)
    }

    /// The drawn row: its frame is the one-line height, so its hit area
    /// and selection outline (both the row's frame) follow.
    func testAOneLineRowDrawsAtItsMeasuredHeight() {
        func height(subtitle: String?) -> CGFloat {
            let view = SidebarListRowChrome(
                subtitle: subtitle, isActive: false, redlineID: "row.test",
                title: { SidebarListRowTitle(text: "reconnect race", isActive: false) },
                glyph: { size in SessionStatusGlyph(kind: .working, size: size) }
            )
            .environmentObject(SidebarWidthModel(width: 260))
            .frame(width: 260)
            let hosting = NSHostingView(rootView: view)
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }
        XCTAssertEqual(height(subtitle: nil), 32, accuracy: 0.5)
        XCTAssertEqual(height(subtitle: "needs you"), SidebarDialTuning.rowHeight(), accuracy: 0.5, "control: a two-line row")
    }

    // MARK: - Accessibility

    func testAccessibilityLabelIncludesTheStatusForOneLineRows() {
        func label(_ kind: SessionStatusGlyphKind) -> String {
            RecentsRowView.accessibilityLabel(name: "reconnect race", projectName: "switchboard", kind: kind, isActive: false)
        }
        // The three statuses whose row hides its second line.
        XCTAssertEqual(label(.working), "reconnect race, in switchboard, working")
        XCTAssertEqual(label(.done), "reconnect race, in switchboard, idle")
        XCTAssertEqual(label(.stopped), "reconnect race, in switchboard, stopped")
        for kind in [SessionStatusGlyphKind.working, .done, .stopped] {
            XCTAssertFalse(SessionRowSecondLine.isShown(kind))
            XCTAssertTrue(label(kind).contains(kind.spokenStatus), "\(kind): the status is spoken though its line is hidden")
        }
    }

    // MARK: - Keeping the selected row clear of the tray

    private typealias Placement = SidebarSelectionFollow.Placement

    /// A 32pt row with its 8pt clearance, in a viewport 500pt tall above
    /// the tray: `top` on screen, `contentTop` in the list's layout.
    private func placement(_ row: String = "a", top: CGFloat, contentTop: CGFloat, visible: CGFloat = 500) -> Placement {
        Placement(rowId: row, contentMinY: contentTop, minY: top, maxY: top + 32 + SidebarSelectionFollow.trayClearance, visibleHeight: visible)
    }

    func testARowAboveGrowingScrollsTheSelectedRowBackClearOfTheTray() {
        var keep = SidebarSelectionFollow.KeepClear()
        // Resting 8pt above the tray: its target ends at the viewport's end.
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900)))
        // A row above grows 48pt: the selected row is pushed under the tray.
        XCTAssertTrue(keep.take(placement(top: 508, contentTop: 948)), "pushed under the tray: scroll it back")
        // The scroll lands: same layout, back in view.
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 948)))
    }

    func testGrowthThatLeavesTheRowInViewDoesNotScroll() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 100, contentTop: 300)))
        XCTAssertFalse(keep.take(placement(top: 148, contentTop: 348)), "still in full view")
    }

    func testARowTheUserScrolledAwayFromIsLeftAlone() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900)))
        // The user scrolls: the layout is unchanged, the row leaves the viewport.
        XCTAssertFalse(keep.take(placement(top: 700, contentTop: 900)), "a scroll never scrolls back")
        // Then a row above grows.
        XCTAssertFalse(keep.take(placement(top: 748, contentTop: 948)), "it was out of view already: nothing to keep")
    }

    func testEveryStepOfAnAnimatedGrowthIsHeld() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900)))
        // Growth arrives over several frames before the scroll lands.
        XCTAssertTrue(keep.take(placement(top: 470, contentTop: 910)))
        XCTAssertTrue(keep.take(placement(top: 490, contentTop: 930)), "still owed its place")
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 930)), "the scroll lands")
        XCTAssertTrue(keep.take(placement(top: 478, contentTop: 948)), "and the next step is held too")
    }

    /// A spring's first and last frames move the row less than half a
    /// point at a time. Each is still the layout moving it, not a scroll,
    /// so the row stays owed its place all the way through.
    func testAGrowthArrivingInTinyStepsIsStillHeld() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900)))
        XCTAssertFalse(keep.take(placement(top: 460.3, contentTop: 900.3)), "within the tolerance: still clear")
        XCTAssertTrue(keep.take(placement(top: 460.7, contentTop: 900.7)), "0.4pt further, now past the tolerance")
        XCTAssertTrue(keep.take(placement(top: 461.1, contentTop: 901.1)))
        XCTAssertTrue(keep.take(placement(top: 480, contentTop: 920)), "the large steps that follow are held too")
    }

    func testANewSelectionIsLeftToTheFollower() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement("a", top: 460, contentTop: 900)))
        XCTAssertFalse(keep.take(placement("b", top: 700, contentTop: 1200)), "a different row: the follower scrolls to it")
    }

    func testARowAboveShrinkingPastTheTopScrollsTheRowBack() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 10, contentTop: 900)))
        XCTAssertTrue(keep.take(placement(top: -38, contentTop: 852)), "pulled past the top: scroll it back")
    }

    func testATallerTrayThatCoversTheRowScrollsItBack() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900, visible: 500)))
        XCTAssertTrue(keep.take(placement(top: 460, contentTop: 900, visible: 440)))
    }
}
