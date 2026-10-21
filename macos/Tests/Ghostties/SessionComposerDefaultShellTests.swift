import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Sean's rule: the composer's default is always Shell. A project whose
/// last-used / default / first-listed template is Browser must still
/// pre-select Shell at a blank query, so the ghost text, Tab and Return
/// all resolve to Shell. Browser opens only when explicitly typed/picked.
@MainActor
struct SessionComposerDefaultShellTests {

    private func option(_ template: AgentTemplate) -> ComposerOption {
        ComposerOption(
            id: template.id, title: template.name, subtitle: nil,
            leadingIcon: nil, action: {}, template: template
        )
    }

    /// Lane 1 (recent) leads with Browser, as when Browser was last used
    /// in the project: index 0 used to be seeded and so was Browser.
    @Test func blankQuerySelectsShellEvenWhenBrowserLeads() {
        let options = [option(.browser), option(.shell), option(.claudeCode)]
        let index = SessionComposerPalette.restStateSelectionIndex(in: options)
        #expect(options[index].template?.kind == .shell)
    }

    /// With Browser as the project default, lane 2 is [Browser, ...]; the
    /// 3-row rest-state cap must not drop Shell.
    @Test func restStateCapKeepsShellWhenBrowserIsProjectDefault() {
        let ordered = [option(.browser), option(.claudeCode), option(.codex), option(.shell)]
        let lane = SessionComposerPalette.applyRestStateCap(
            to: SessionComposerPalette.shellFirst(ordered), query: ""
        )
        #expect(lane.contains { $0.template?.kind == .shell })
    }

    private func projectRow() -> ComposerOption {
        ComposerOption(id: UUID(), title: "repo", subtitle: nil, leadingIcon: nil, action: {})
    }

    /// No Shell row: never implicitly select a non-Shell template. A
    /// project row is safe (Return opens a Shell at its root).
    @Test func noShellRowSelectsTheProjectRowNotBrowser() {
        let options = [option(.browser), option(.claudeCode), projectRow()]
        let index: Int? = SessionComposerPalette.restStateSelectionIndex(in: options)
        #expect(index == 2)
    }

    /// No Shell row and no project row: select nothing.
    @Test func noShellRowAndNoSafeRowSelectsNothing() {
        let options = [option(.browser), option(.claudeCode)]
        let index: Int? = SessionComposerPalette.restStateSelectionIndex(in: options)
        #expect(index == nil)
    }

    /// A custom shell-kind template ahead of the built-in Shell: both the
    /// hoist and the selection must prefer the built-in Shell id.
    @Test func defaultShellIdBeatsAnotherShellKindTemplate() {
        let custom = AgentTemplate(name: "My Shell", kind: .shell)
        let options = [option(.browser), option(custom), option(.shell)]
        let hoisted = SessionComposerPalette.shellFirst(options)
        #expect(hoisted.first?.id == AgentTemplate.shell.id)
        let index: Int? = SessionComposerPalette.restStateSelectionIndex(in: options)
        #expect(options[index ?? 0].id == AgentTemplate.shell.id)
    }
}
