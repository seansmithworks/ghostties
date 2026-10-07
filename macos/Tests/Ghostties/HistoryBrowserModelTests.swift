import XCTest
@testable import Ghostty

/// Behaviour of the history browser's filtering/selection model: fuzzy
/// matching, ordering, selection movement and re-anchoring, empty states,
/// and the key → callback mapping the view routes every key through.
final class HistoryBrowserModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func entry(_ project: String, _ title: String, hoursAgo: Double, archived: Bool = false, pinned: Bool = false) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), projectName: project, title: title,
            lastActiveAt: now.addingTimeInterval(-hoursAgo * 3600),
            isArchived: archived, isPinned: pinned
        )
    }

    private lazy var fixture: [HistoryEntry] = [
        entry("harbor", "rate limit headers", hoursAgo: 30),
        entry("atlas-api", "migrate auth tokens", hoursAgo: 2),
        entry("fieldwork", "offline sync spike", hoursAgo: 5),
        entry("Lumen", "Hero image crops", hoursAgo: 80, archived: true),
    ]

    private func titles(_ model: HistoryBrowserModel) -> [String] { model.rows.map(\.entry.title) }

    // MARK: - Ordering

    func testRowsAreSortedByLastActiveDescending() {
        let model = HistoryBrowserModel(entries: fixture)
        XCTAssertEqual(titles(model), ["migrate auth tokens", "offline sync spike", "rate limit headers", "Hero image crops"])
    }

    func testFilteringKeepsRecencyOrder() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "i"  // matches every entry
        XCTAssertEqual(titles(model), ["migrate auth tokens", "offline sync spike", "rate limit headers", "Hero image crops"])
    }

    // MARK: - Fuzzy filter

    func testFilterMatchesProjectCaseInsensitively() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "LUMEN"
        XCTAssertEqual(titles(model), ["Hero image crops"])
        XCTAssertEqual(model.rows.first?.projectMatches, [0, 1, 2, 3, 4])
        XCTAssertEqual(model.rows.first?.titleMatches, [])
    }

    func testFilterMatchesTitleCaseInsensitively() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "hero"
        XCTAssertEqual(titles(model), ["Hero image crops"])
        XCTAssertEqual(model.rows.first?.titleMatches, [0, 1, 2, 3])
    }

    func testFuzzySubsequenceSpansProjectThenTitle() {
        // "hbrrate" = h-a-r-b-o-r → h,b,r from "harbor", then "rate" from the title.
        let m = HistoryBrowserModel.match(query: "hbrrate", project: "harbor", title: "rate limit headers")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.project, [0, 3, 5])
        XCTAssertEqual(m?.title, [0, 1, 2, 3])
    }

    func testOutOfOrderCharactersDoNotMatch() {
        XCTAssertNil(HistoryBrowserModel.match(query: "rh", project: "harbor", title: "x"))
    }

    func testWhitespaceSeparatedTermsMustAllMatch() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "atlas auth"
        XCTAssertEqual(titles(model), ["migrate auth tokens"])
        model.query = "atlas crops"
        XCTAssertEqual(model.rows, [])
    }

    func testEmptyQueryShowsEverythingWithNoEmphasis() {
        let model = HistoryBrowserModel(entries: fixture)
        XCTAssertEqual(model.shown, 4)
        XCTAssertEqual(model.total, 4)
        XCTAssertTrue(model.rows.allSatisfy { $0.projectMatches.isEmpty && $0.titleMatches.isEmpty })
    }

    // MARK: - Selection

    func testFirstRowIsSelectedInitially() {
        let model = HistoryBrowserModel(entries: fixture)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testMoveClampsAtBothEnds() {
        var model = HistoryBrowserModel(entries: fixture)
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedIndex, 0, "up at the top stays at the top")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 3)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 3, "down at the bottom stays at the bottom")
    }

    func testSelectionSurvivesAFilterThatStillMatchesIt() {
        var model = HistoryBrowserModel(entries: fixture)
        model.moveSelection(by: 2)  // "rate limit headers"
        let selected = model.selectedID
        model.query = "ra"  // "rate limit headers" and "migrate auth tokens" both match
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertEqual(model.rows[model.selectedIndex!].entry.title, "rate limit headers")
    }

    func testSelectionReanchorsToFirstMatchWhenFilteredOut() {
        var model = HistoryBrowserModel(entries: fixture)
        model.moveSelection(by: 3)  // "Hero image crops"
        model.query = "sync"
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.rows.first?.entry.title, "offline sync spike")
    }

    func testSelectionIsNilWithNoMatchesAndReturnsWhenQueryClears() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "zzz"
        XCTAssertNil(model.selectedID)
        model.query = ""
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testSetEntriesKeepsQueryAndSelection() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "a"
        model.moveSelection(by: 1)
        let selected = model.selectedID!
        let updated = fixture.map {
            $0.id == selected
                ? HistoryEntry(id: $0.id, projectName: $0.projectName, title: $0.title, lastActiveAt: $0.lastActiveAt, isArchived: $0.isArchived, isPinned: true)
                : $0
        }
        model.setEntries(updated)
        XCTAssertEqual(model.query, "a")
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertEqual(model.rows[model.selectedIndex!].entry.isPinned, true)
    }

    // MARK: - Empty states

    func testEmptyStates() {
        XCTAssertEqual(HistoryBrowserModel(entries: []).emptyState, .noPastSessions)
        XCTAssertEqual(HistoryBrowserModel.EmptyState.noPastSessions.message, "No past sessions")

        var model = HistoryBrowserModel(entries: fixture)
        XCTAssertNil(model.emptyState)
        model.query = "qqq"
        XCTAssertEqual(model.emptyState, .noMatches)
        XCTAssertEqual(HistoryBrowserModel.EmptyState.noMatches.message, "No matches")
    }

    // MARK: - Keys → callbacks

    private final class Recorder {
        var resumed: [UUID] = []
        var pinned: [UUID] = []
        var closed = 0
        var actions: HistoryBrowserModel.Actions {
            .init(onResume: { self.resumed.append($0) }, onTogglePin: { self.pinned.append($0) }, onClose: { self.closed += 1 })
        }
    }

    func testKeysMapToCallbacksWithTheSelectedID() {
        var model = HistoryBrowserModel(entries: fixture)
        let r = Recorder()
        model.handle(.down, actions: r.actions)
        let second = model.rows[1].id
        XCTAssertEqual(model.selectedID, second)

        model.handle(.resume, actions: r.actions)
        model.handle(.togglePin, actions: r.actions)
        model.handle(.up, actions: r.actions)
        model.handle(.togglePin, actions: r.actions)
        model.handle(.close, actions: r.actions)

        XCTAssertEqual(r.resumed, [second])
        XCTAssertEqual(r.pinned, [second, model.rows[0].id])
        XCTAssertEqual(r.closed, 1)
    }

    func testResumeAndPinDoNothingWithoutASelectionButCloseStillFires() {
        var model = HistoryBrowserModel(entries: fixture)
        model.query = "nothing-matches-this"
        let r = Recorder()
        model.handle(.resume, actions: r.actions)
        model.handle(.togglePin, actions: r.actions)
        model.handle(.close, actions: r.actions)
        XCTAssertEqual(r.resumed, [])
        XCTAssertEqual(r.pinned, [])
        XCTAssertEqual(r.closed, 1)
    }

    // MARK: - Age

    func testAgeFormatting() {
        func age(_ seconds: Double) -> String { HistoryBrowserModel.age(of: now.addingTimeInterval(-seconds), now: now) }
        XCTAssertEqual(age(10), "now")
        XCTAssertEqual(age(5 * 60), "5m")
        XCTAssertEqual(age(2 * 3600), "2h")
        XCTAssertEqual(age(3 * 86400), "3d")
        XCTAssertEqual(age(15 * 86400), "2w")
        XCTAssertEqual(age(95 * 86400), "3mo")
        XCTAssertEqual(age(400 * 86400), "1y")
    }
}
