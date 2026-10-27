import Foundation
import Network
import Testing
import GhosttiesCore
@testable import Ghostty

/// "Driven by" on the browser panel: a browser reads as driven while at
/// least one agent client is attached to its page through the gateway, and
/// names the terminal it is paired with. Debug builds only, like the gateway.
///
/// Every store is the injected persistence-disabled kind, never
/// `WorkspaceStore.shared`, so nothing here writes `workspace.json`.
@Suite(.serialized)
struct BrowserDrivenByTests {
    private static let page = "8F1C2A7DPAGE"

    // MARK: - Counting clients

    @Test func aClientOnAPageRouteDrivesThatPage() {
        var attachments = BrowserAgentAttachments()
        let client = UUID()
        attachments.connect(client: client)
        attachments.attach(client: client, target: Self.page)
        #expect(attachments.drivenTargets == [Self.page])
    }

    @Test func oneOfTwoClientsLeavingKeepsThePageDriven() {
        var attachments = BrowserAgentAttachments()
        let first = UUID(), second = UUID()
        attachments.connect(client: first)
        attachments.connect(client: second)
        attachments.attach(client: first, target: Self.page)
        attachments.attach(client: second, target: Self.page)
        attachments.removeClient(first)
        #expect(attachments.drivenTargets == [Self.page], "the second client still holds the page")
    }

    @Test func theLastClientLeavingEndsIt() {
        var attachments = BrowserAgentAttachments()
        let first = UUID(), second = UUID()
        attachments.connect(client: first)
        attachments.connect(client: second)
        attachments.attach(client: first, target: Self.page)
        attachments.attach(client: second, target: Self.page)
        attachments.removeClient(first)
        attachments.removeClient(second)
        #expect(attachments.drivenTargets.isEmpty)
    }

    // MARK: - Browser-route clients (Playwright connectOverCDP)

    @Test func aBrowserRouteClientDrivesThePagesItAttachesTo() {
        var attachments = BrowserAgentAttachments()
        let client = UUID()
        attachments.connect(client: client)
        attachments.observe(upstreamFrame: #"{"method":"Target.attachedToTarget","params":{"sessionId":"S1","targetInfo":{"targetId":"\#(Self.page)","type":"page","title":"","url":"about:blank","attached":true},"waitingForDebugger":false}}"#, client: client)
        #expect(attachments.drivenTargets == [Self.page])

        attachments.observe(upstreamFrame: #"{"method":"Target.detachedFromTarget","params":{"sessionId":"S1","targetId":"\#(Self.page)"}}"#, client: client)
        #expect(attachments.drivenTargets.isEmpty)
    }

    @Test func aLateFrameForAClosedClientCannotDriveAgain() {
        var attachments = BrowserAgentAttachments()
        let client = UUID()
        attachments.connect(client: client)
        attachments.attach(client: client, target: Self.page)
        #expect(attachments.drivenTargets == [Self.page])
        attachments.removeClient(client)
        // An upstream receive already in flight when the socket closed.
        attachments.observe(upstreamFrame: #"{"method":"Target.attachedToTarget","params":{"sessionId":"S9","targetInfo":{"targetId":"\#(Self.page)","type":"page"},"waitingForDebugger":false}}"#, client: client)
        attachments.attach(client: client, target: Self.page)
        #expect(attachments.drivenTargets.isEmpty, "a closed client drove the page again")
    }

    @Test func workersAndOtherFramesAreNotPages() {
        var attachments = BrowserAgentAttachments()
        let client = UUID()
        attachments.connect(client: client)
        attachments.observe(upstreamFrame: #"{"method":"Target.attachedToTarget","params":{"sessionId":"S2","targetInfo":{"targetId":"W1","type":"service_worker"},"waitingForDebugger":false}}"#, client: client)
        attachments.observe(upstreamFrame: #"{"id":4,"result":{"data":"Target.attachedToTarget"}}"#, client: client)
        #expect(attachments.drivenTargets.isEmpty)
    }

    // MARK: - The gateway counts real sockets

    @Test func theGatewayTracksAPageRouteSocketUntilItCloses() async throws {
        let stub = try BrowserAgentGatewayTests.StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        let changes = TargetLog()
        gateway.onDrivenTargetsChange = { changes.append($0) }
        let port = try #require(gateway.routePort(forPath: "/devtools/page/\(Self.page)"))
        defer { gateway.stop() }

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/devtools/page/\(Self.page)")!)
        task.resume()
        try await task.send(.string(#"{"id":1,"method":"Runtime.enable"}"#))
        _ = try await task.receive()
        #expect(await changes.waitFor { $0 == [Self.page] }, "attaching never reported the page as driven")

        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        #expect(await changes.waitFor { $0.isEmpty }, "closing the socket never released the page")
    }

    final class TargetLog: @unchecked Sendable {
        private let lock = NSLock()
        private var latest: Set<String>?

        func append(_ targets: Set<String>) {
            lock.lock(); latest = targets; lock.unlock()
        }

        func waitFor(_ condition: (Set<String>) -> Bool, timeout: TimeInterval = 5) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                lock.lock(); let value = latest; lock.unlock()
                if let value, condition(value) { return true }
                try? await _Concurrency.Task.sleep(for: .milliseconds(20))
            }
            return false
        }
    }

    // MARK: - The panel's driver

    @MainActor
    private struct World {
        let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let terminal: AgentSession
        let browser: AgentSession
        let store: WorkspaceStore
        let coordinator: SessionCoordinator

        init(paired: Bool = true) {
            terminal = AgentSession(name: "reconnect race", templateId: AgentTemplate.shell.id, projectId: atlas.id)
            browser = AgentSession(name: "Browser 2", templateId: AgentTemplate.browser.id, projectId: atlas.id)
            store = WorkspaceStore(testingProjects: [atlas], testingSessions: [terminal, browser])
            coordinator = SessionCoordinator()
            coordinator.agentKindLookupStoreForTesting = store
            coordinator.seedEmptySessionTreeForTesting(id: terminal.id)
            coordinator.seedRunningSessionForTesting(id: terminal.id)
            coordinator.seedBrowserSessionForTesting(id: browser.id)
            if paired { coordinator.seedPairedBrowserForTesting(terminal: terminal.id, browser: browser.id) }
            coordinator.seedDevToolsTargetForTesting(browser: browser.id, target: BrowserDrivenByTests.page)
            coordinator.setActiveSessionIdForTesting(terminal.id)
        }
    }

    @MainActor @Test func attachingAClientDrivesThePairedBrowser() {
        let w = World()
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil, "driven before anything attached")
        w.coordinator.agentAttachmentsChanged([Self.page])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id)?.id == w.terminal.id)
    }

    @MainActor @Test func theLastDetachEndsIt() {
        let w = World()
        w.coordinator.agentAttachmentsChanged([Self.page])
        w.coordinator.agentAttachmentsChanged([])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil)
    }

    @MainActor @Test func anotherPagesClientDoesNotDriveThisBrowser() {
        let w = World()
        w.coordinator.agentAttachmentsChanged(["SOMEOTHERPAGE"])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil)
    }

    @MainActor @Test func theNameIsThePairedTerminalsName() {
        let w = World()
        w.coordinator.agentAttachmentsChanged([Self.page])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id)?.name == "reconnect race", "named after the browser, not its terminal")

        w.store.renameSession(id: w.terminal.id, name: "auth migration")
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id)?.name == "auth migration", "a rename does not reach the pill")
    }

    @MainActor @Test func closingTheBrowserClearsIt() {
        let w = World()
        w.coordinator.agentAttachmentsChanged([Self.page])
        w.coordinator.closeSession(id: w.browser.id)
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil)

        // The same page id coming back (a stale socket) must not revive it.
        w.coordinator.seedPairedBrowserForTesting(terminal: w.terminal.id, browser: w.browser.id)
        w.coordinator.agentAttachmentsChanged([Self.page])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil, "the closed browser kept its target")
    }

    @MainActor @Test func closingTheTerminalClearsIt() {
        let w = World()
        w.coordinator.agentAttachmentsChanged([Self.page])
        w.coordinator.closeSession(id: w.terminal.id)
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil)

        w.coordinator.seedPairedBrowserForTesting(terminal: w.terminal.id, browser: w.browser.id)
        w.coordinator.agentAttachmentsChanged([Self.page])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil, "the closed browser kept its target")
    }

    @MainActor @Test func anUnpairedBrowserHasNoDriverToName() {
        let w = World(paired: false)
        w.coordinator.agentAttachmentsChanged([Self.page])
        #expect(w.coordinator.agentDriver(ofBrowser: w.browser.id) == nil)
    }
}
