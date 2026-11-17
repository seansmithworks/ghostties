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

    /// A chip is the dial's side, never taller than its row's band: the
    /// rail's 40pt chip is 32pt in a one-line row.
    func testAChipNeverSpillsOutOfItsRowsBand() {
        XCTAssertEqual(SidebarListRowHeight.chip(40, band: 32), 32)
        XCTAssertEqual(SidebarListRowHeight.chip(40, band: 48), 40)
        XCTAssertEqual(SidebarListRowHeight.chip(24, band: 32), 24)
    }

    /// The drawn row: its frame is the one-line height, so its hit area
    /// and selection outline (both the row's frame) follow. The rail draws
    /// the row at the same height as the sidebar, at every step between.
    func testARowDrawsAtItsMeasuredHeightOnTheSidebarAndTheRail() {
        func height(subtitle: String?, morph: CGFloat) -> CGFloat {
            let view = SidebarListRowChrome(
                subtitle: subtitle, isActive: false, redlineID: "row.test",
                title: { SidebarListRowTitle(text: "reconnect race", isActive: false) },
                glyph: { size in SessionStatusGlyph(kind: .working, size: size) }
            )
            .environment(\.sidebarMorphOverride, morph)
            .environmentObject(SidebarWidthModel(width: 260))
            .frame(width: 260)
            let hosting = NSHostingView(rootView: view)
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }
        for morph: CGFloat in [0, 0.5, 1] {
            XCTAssertEqual(height(subtitle: nil, morph: morph), 32, accuracy: 0.5, "one line, morph \(morph)")
            XCTAssertEqual(
                height(subtitle: "needs you", morph: morph), SidebarDialTuning.rowHeight(), accuracy: 0.5,
                "two lines, morph \(morph)"
            )
        }
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

    /// The user scrolls the selected row away while a row above is still
    /// animating taller. Each frame carries the growth and the scroll
    /// together, so it reads as the layout moving the row; the scroll
    /// event is what says otherwise, and from then the growth is not held.
    func testAUserScrollDuringAGrowthWinsUntilTheGrowthEnds() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900), at: 10.00))
        XCTAssertTrue(keep.take(placement(top: 470, contentTop: 910), at: 10.02), "control: the growth is held")
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 910), at: 10.03), "control: the scroll lands")

        // The user scrolls the row down under the tray as the growth goes on.
        keep.userScrolled(at: 10.04)
        XCTAssertFalse(keep.take(placement(top: 500, contentTop: 920), at: 10.05), "their scroll and a growth step in one frame: not scrolled back")
        XCTAssertFalse(keep.take(placement(top: 540, contentTop: 930), at: 10.07), "nor on any later step of this growth")
        XCTAssertFalse(keep.take(placement(top: 548, contentTop: 938), at: 10.09), "even with no further scroll event")
    }

    func testAScrollUnderWayWhenAGrowthStartsWinsFromItsFirstStep() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900), at: 10.00))
        keep.userScrolled(at: 10.10)
        XCTAssertFalse(keep.take(placement(top: 480, contentTop: 910), at: 10.12), "mid-scroll: the growth's first step is not held")
    }

    func testAfterAUserScrollTheNextSeparateGrowthIsHeldAgain() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 300, contentTop: 900), at: 10.00))
        XCTAssertFalse(keep.take(placement(top: 310, contentTop: 910), at: 10.02))
        keep.userScrolled(at: 10.03)
        // They leave the row resting 8pt above the tray, and the growth ends.
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 920), at: 10.04))
        // Seconds later another row above grows.
        XCTAssertTrue(keep.take(placement(top: 470, contentTop: 930), at: 14.00), "a separate growth: held again")
    }

    func testAfterAUserScrollANewSelectionIsHeldAgain() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement("a", top: 460, contentTop: 900), at: 10.00))
        XCTAssertTrue(keep.take(placement("a", top: 470, contentTop: 910), at: 10.02))
        keep.userScrolled(at: 10.03)
        XCTAssertFalse(keep.take(placement("a", top: 500, contentTop: 920), at: 10.04), "control: yielded")
        // The selection moves to a row resting above the tray, mid-growth.
        XCTAssertFalse(keep.take(placement("b", top: 460, contentTop: 700), at: 10.05))
        XCTAssertTrue(keep.take(placement("b", top: 470, contentTop: 710), at: 10.06), "the new selection's row is held")
    }

    func testAUserScrollWithNoGrowthUnderWayChangesNothing() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900), at: 10.00))
        keep.userScrolled(at: 11.00)
        // The scroll put the row back where it rests; long after, a row grows.
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900, visible: 500), at: 11.02))
        XCTAssertTrue(keep.take(placement(top: 470, contentTop: 910), at: 15.00), "held: the scroll was long over")
    }

    func testATallerTrayThatCoversTheRowScrollsItBack() {
        var keep = SidebarSelectionFollow.KeepClear()
        XCTAssertFalse(keep.take(placement(top: 460, contentTop: 900, visible: 500)))
        XCTAssertTrue(keep.take(placement(top: 460, contentTop: 900, visible: 440)))
    }
}
