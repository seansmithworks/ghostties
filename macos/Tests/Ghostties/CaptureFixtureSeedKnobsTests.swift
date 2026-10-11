import Foundation
import GhosttiesCore
import Testing
@testable import Ghostty

/// The two opt-in seed knobs (contract X3 and T6) and the unchanged default.
@MainActor
struct CaptureFixtureSeedKnobsTests {

    @Test func envGrammarOnlyAcceptsTheDocumentedValues() {
        #expect(CaptureFixture.parseSeedKnobs([:]) == CaptureFixture.SeedKnobs())
        #expect(CaptureFixture.parseSeedKnobs(["GHOSTTIES_CAPTURE_FIXTURE_PROJECTS": "none"]).zeroProjects)
        #expect(!CaptureFixture.parseSeedKnobs(["GHOSTTIES_CAPTURE_FIXTURE_PROJECTS": "all"]).zeroProjects)
        #expect(CaptureFixture.parseSeedKnobs(["GHOSTTIES_CAPTURE_FIXTURE_TEMPLATE_IN_USE": "1"]).templateInUse)
        #expect(!CaptureFixture.parseSeedKnobs(["GHOSTTIES_CAPTURE_FIXTURE_TEMPLATE_IN_USE": "0"]).templateInUse)
    }

    @Test func defaultCastIsUnchanged() {
        let store = CaptureFixture.makeStore(knobs: .init())
        #expect(store.projects.count == 7)
        #expect(store.sessions.count == 11)
        #expect(store.sessions.allSatisfy { $0.templateId == AgentTemplate.claudeCode.id })
        #expect(store.templates.allSatisfy { $0.isDefault })
    }

    @Test func zeroProjectsSeedsNoProjectsAndNoSessions() {
        let store = CaptureFixture.makeStore(knobs: .init(zeroProjects: true))
        #expect(store.projects.isEmpty)
        #expect(store.sessions.isEmpty)
    }

    @Test func templateInUseSeedsMineUsedByTwoSessionsOnOneProject() {
        let store = CaptureFixture.makeStore(knobs: .init(templateInUse: true))
        let mine = store.templates.filter { !$0.isDefault }
        #expect(mine.map(\.name) == ["Mine"])
        let users = store.sessions.filter { $0.templateId == mine[0].id }
        #expect(users.count == 2)
        #expect(Set(users.map(\.projectId)).count == 1)
        #expect(store.templateInUse(id: mine[0].id))
        #expect(TemplateManagement.deleteMessage(for: mine[0], store: store).hasPrefix("Used by "))
        // Everything else is the default cast.
        #expect(store.projects.count == 7)
        #expect(store.sessions.count == 11)
    }
}
