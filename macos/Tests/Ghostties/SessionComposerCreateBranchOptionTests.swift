import Testing
import Foundation
import GhosttiesCore
@testable import Ghostty

/// The create-branch results row (typed unknown branch token, then Down,
/// then Return) lost its only test when the anchored card was removed.
/// `createBranchOption` is the pure decision behind that row.
@MainActor
struct SessionComposerCreateBranchOptionTests {
    private func makeProject() -> Project {
        Project(id: UUID(), name: "ghostties", rootPath: "/tmp/ghostties", isPinned: false)
    }

    @Test func unknownBranchTokenYieldsSelectableCreateBranchOption() {
        var fired = false
        let option = SessionComposerPalette.createBranchOption(
            offerToken: "mybrnach",
            project: makeProject(),
            isKnownBranchWithoutWorktree: false,
            action: { fired = true }
        )
        #expect(option != nil)
        #expect(option?.id == SessionComposerCommandParser.createWorktreeRowId)
        #expect(option?.title == "Create branch \"mybrnach\"")
        #expect(option?.subtitle == "ghostties")
        option?.action()
        #expect(fired)
    }

    @Test func noOfferTokenOrNoProjectYieldsNoOption() {
        #expect(SessionComposerPalette.createBranchOption(
            offerToken: nil, project: makeProject(), isKnownBranchWithoutWorktree: false, action: {}) == nil)
        #expect(SessionComposerPalette.createBranchOption(
            offerToken: "x", project: nil, isKnownBranchWithoutWorktree: false, action: {}) == nil)
    }
}
