import Foundation
import Testing
@testable import Ghostty

/// D2: the fixture seeds the coordinator, so the Sessions tab (store cache)
/// and the Projects tab (`coordinator.indicatorState`) read one source.
@MainActor
struct CaptureFixtureSeedingTests {

    private func seeded() -> (SessionCoordinator, WorkspaceStore) {
        let store = CaptureFixture.makeStore()
        let coordinator = SessionCoordinator()
        coordinator.agentKindLookupStoreForTesting = store
        CaptureFixture.seedCoordinator(coordinator, store: store)
        return (coordinator, store)
    }

    @Test func storeCacheEqualsTheCoordinatorForEveryAliveFixtureSession() {
        let (coordinator, store) = seeded()
        // Not-alive sessions (inactive, error) read the store's statuses, which in
        // the app is `WorkspaceStore.shared` itself; this test's private store
        // isn't, so they're out of scope here.
        var compared = 0
        for session in CaptureFixture.sessions {
            guard let cached = store.globalIndicatorStates[session.id],
                  cached != .inactive, cached != .error else { continue }
            #expect(coordinator.indicatorState(for: session.id) == cached, "\(session.name)")
            compared += 1
        }
        #expect(compared == 6)
    }

    @Test func seededStatesAreTheOnesTheCoordinatorDerives() {
        let (coordinator, _) = seeded()
        let byName = Dictionary(grouping: CaptureFixture.sessions, by: \.name)
        // Claude Code 4 / 3: processing; Claude Code 6: needs attention.
        #expect(coordinator.indicatorState(for: byName["Claude Code 4"]![0].id) == .processing)
        #expect(coordinator.indicatorState(for: byName["Claude Code 6"]![0].id) == .needsAttention)
        // Agent sessions with no evidence resolve to idle, never waiting.
        #expect(coordinator.indicatorState(for: byName["Claude Code 2"]![0].id) == .idle)
    }

    @Test func processingDoesNotDecay() {
        let (coordinator, _) = seeded()
        let id = CaptureFixture.sessions[0].id
        #expect(coordinator.indicatorState(for: id) == .processing)
        Thread.sleep(forTimeInterval: 2.2)
        #expect(coordinator.indicatorState(for: id) == .processing)
    }
}
