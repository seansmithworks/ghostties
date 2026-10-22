import XCTest
import GhosttiesCore
@testable import Ghostty

/// A browser an agent opened (`gt browser open`) sits directly under its
/// terminal in the one-view list and reads `from <terminal name>`. The
/// pairing is the coordinator's runtime-only terminal-to-browser map, passed
/// in here; an empty map is "no pairing". Every store is persistence-disabled
/// (`WorkspaceStore(testingProjects:)`), never `WorkspaceStore.shared`.
@MainActor
final class PairedBrowserRowTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")

    private func session(_ name: String, _ project: Project, template: UUID = UUID()) -> AgentSession {
        AgentSession(name: name, templateId: template, projectId: project.id)
    }

    private func names(_ groups: [SidebarProjectGroup], _ project: Project) -> [String] {
        groups.first { $0.projectId == project.id }?.sessions.map(\.name) ?? []
    }

    func testAPairedBrowserSitsDirectlyUnderItsTerminalEvenIfCreatedLater() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [race, other, browser]

        let plain = SidebarProjectGroup.make(active: active, projects: [atlas])
        let paired = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [race.id: browser.id])

        XCTAssertEqual(names(plain, atlas), ["reconnect race", "other", "Browser 3"])
        XCTAssertEqual(names(paired, atlas), ["reconnect race", "Browser 3", "other"])
    }

    func testThePairedBrowserFollowsItsTerminalWhenItMoves() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let pairs = [race.id: browser.id]

        let moved = SidebarProjectGroup.make(active: [other, browser, race], projects: [atlas], pairedBrowsers: pairs)

        XCTAssertEqual(names(moved, atlas), ["other", "reconnect race", "Browser 3"])
    }

    func testTheSubtitleNamesTheTerminal() {
        let race = session("reconnect race", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let pairs = [race.id: browser.id]

        XCTAssertEqual(PairedBrowserRows.subtitle(for: browser, in: [race, browser], pairedBrowsers: pairs), "from reconnect race")
        XCTAssertNil(PairedBrowserRows.subtitle(for: race, in: [race, browser], pairedBrowsers: pairs), "the terminal keeps its status word")
    }

    func testUnpairingRestoresOrderAndSubtitle() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [race, other, browser]

        let unpaired = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [:])

        XCTAssertEqual(names(unpaired, atlas), ["reconnect race", "other", "Browser 3"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: browser, in: active, pairedBrowsers: [:]))
    }

    func testUnpairedBrowsersAndEveryOtherRowAreUnchanged() {
        let race = session("reconnect race", atlas)
        let paired = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let loose = session("Browser 4", atlas, template: AgentTemplate.browser.id)
        let field = session("f1", fieldwork)
        let active = [race, loose, paired, field]

        let groups = SidebarProjectGroup.make(active: active, projects: [atlas, fieldwork], pairedBrowsers: [race.id: paired.id])

        XCTAssertEqual(names(groups, atlas), ["reconnect race", "Browser 3", "Browser 4"])
        XCTAssertEqual(names(groups, fieldwork), ["f1"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: loose, in: active, pairedBrowsers: [race.id: paired.id]))
        XCTAssertNil(PairedBrowserRows.subtitle(for: field, in: active, pairedBrowsers: [race.id: paired.id]))
    }

    func testAPairWhoseTerminalIsNotInTheGroupKeepsTheBrowserWhereItIs() {
        let pinnedTerminal = session("pinned", atlas)
        let a1 = session("a1", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [a1, browser]

        let groups = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [pinnedTerminal.id: browser.id])

        XCTAssertEqual(names(groups, atlas), ["a1", "Browser 3"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: browser, in: active, pairedBrowsers: [pinnedTerminal.id: browser.id]))
    }

    func testTheRailFollowsTheSameOrder() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let all = [race, other, browser]
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }

        XCTAssertEqual(store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name), ["reconnect race", "other", "Browser 3"])
        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true, pairedBrowsers: [race.id: browser.id]).map(\.name),
            ["reconnect race", "Browser 3", "other"]
        )
    }
}
