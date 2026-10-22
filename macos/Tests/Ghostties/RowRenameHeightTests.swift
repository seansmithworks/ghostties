import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Renaming a needs-you row never changes its height, so nothing below it
/// moves, and drag reflow (which measures with `SidebarListRowHeight`)
/// agrees with what is drawn.
@MainActor
final class RowRenameHeightTests: XCTestCase {
    private struct Host: View {
        let session: AgentSession
        let prompt: SessionRowPrompt?
        let editing: Bool
        @FocusState private var focused: Bool

        var body: some View {
            RecentsRowView(
                session: session, projectName: "atlas-api", indicatorState: .needsAttention,
                prompt: prompt, approvalsEnabled: true, isActive: false, isEditing: editing,
                editingName: .constant(session.name), isRenameFocused: $focused, onTap: {}
            )
        }
    }

    private func height(prompt: SessionRowPrompt?, editing: Bool) -> CGFloat {
        let session = AgentSession(name: "deploy preview", templateId: UUID(), projectId: UUID())
        let view = Host(session: session, prompt: prompt, editing: editing)
            .environmentObject(SessionCoordinator())
            .environmentObject(SidebarWidthModel(width: 320))
            .frame(width: 320)
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    func testRenamingANeedsYouRowKeepsItsHeight() {
        let prompt = SessionRowPrompt(question: "Run npm test?", approvalPrompt: nil)
        let showing = height(prompt: prompt, editing: false)
        XCTAssertEqual(showing, SidebarListRowHeight.row(hasActions: true), accuracy: 0.5, "control: the row draws at its measured height")
        XCTAssertEqual(height(prompt: prompt, editing: true), showing, accuracy: 0.5, "renaming keeps the action line's room")
        XCTAssertEqual(height(prompt: nil, editing: true), SidebarListRowHeight.row(hasActions: false), accuracy: 0.5, "control: a plain row being renamed")
    }

    /// While a needs-you row is renamed its hidden action line takes no
    /// input (clicks, Full Keyboard Access, VoiceOver), and the row offers
    /// none of its approval actions.
    func testRenamingANeedsYouRowSilencesItsActions() {
        let approval = SessionPopoverContent.ApprovalPrompt(updatedAt: Date(), fingerprint: "Bash")
        let prompt = SessionRowPrompt(question: "Run npm test?", approvalPrompt: approval)
        typealias A11y = SessionRowPromptAccessibility
        XCTAssertEqual(A11y.actions(prompt: prompt, approval: approval, isEditing: false), [.approve(approval), .deny(approval)],
                       "control: a needs-you row offers Approve and Deny")
        XCTAssertEqual(A11y.actions(prompt: prompt, approval: nil, isEditing: false), [.answerInTerminal],
                       "control: or Answer in terminal")
        XCTAssertEqual(A11y.actions(prompt: prompt, approval: approval, isEditing: true), [], "renaming: no approval actions")
        XCTAssertEqual(A11y.actions(prompt: prompt, approval: nil, isEditing: true), [], "renaming: no Answer in terminal")

        func line(hidden: Bool) -> SessionRowActionLine {
            SessionRowActionLine(sessionId: UUID(), approval: approval, isHidden: hidden,
                                 answers: SessionPopoverModel(), onApprovalDecision: { _, _ in }, onAnswerInTerminal: {})
        }
        XCTAssertTrue(line(hidden: false).acceptsInput, "control: a showing line takes input")
        XCTAssertFalse(line(hidden: true).acceptsInput, "renaming: the hidden line's controls are disabled")
    }
}
