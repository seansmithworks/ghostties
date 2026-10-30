import XCTest
import Combine
import SwiftUI
import Vision
import GhosttiesCore
@testable import Ghostty

/// A permission prompt arrives as two async hook events: `PermissionRequest`
/// (tool and input) and `Notification/permission_prompt` (a message and
/// nothing else). Whichever lands last, the row keeps offering Approve/Deny
/// for the tool, and a genuinely new prompt or a resolution still takes over.
/// Payload keys are the ones measured in `gate-evidence.md` E2.
@MainActor
final class PermissionPromptOrderTests: XCTestCase {
    private let id = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E1")!
    private let surface = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E2")!
    /// Fresh enough for `staleInterval`; each event lands a few seconds on.
    private let t0 = Int(Date().timeIntervalSince1970) - 60

    private var dir: URL!
    private var claude: ClaudeStateStore!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionPromptOrder-\(UUID().uuidString)", isDirectory: true)
        claude = ClaudeStateStore(directoryURL: dir)
        claude.resumeWriterForTesting = { _, _ in }
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - Fixtures

    private struct Tool {
        let name: String
        let requestFields: String
        let question: String
    }

    private let edit = Tool(
        name: "Edit",
        requestFields: #""tool_name":"Edit","tool_input":{"file_path":"/repo/README.md","old_string":"a","new_string":"b"}"#,
        question: "Edit README.md?"
    )
    private let bash = Tool(
        name: "Bash",
        requestFields: #""tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}"#,
        question: "Run npm test?"
    )

    private func request(_ tool: Tool, turn: String = "turn-1") -> String {
        #"{"cwd":"/repo","hook_event_name":"PermissionRequest","permission_mode":"default","permission_suggestions":[],"prompt_id":"\#(turn)","session_id":"c-1",\#(tool.requestFields),"transcript_path":"/tmp/t.jsonl"}"#
    }

    /// The message names the tool, as Claude Code's does; `nil` leaves it unsaid.
    private func notification(turn: String? = "turn-1", tool: String? = nil) -> String {
        let message = tool.map { "Claude needs your permission to use \($0)" } ?? "Claude needs your permission"
        let promptId = turn.map { #""prompt_id":"\#($0)","# } ?? ""
        return #"{"cwd":"/repo","hook_event_name":"Notification","message":"\#(message)","notification_type":"permission_prompt",\#(promptId)"session_id":"c-1","transcript_path":"/tmp/t.jsonl"}"#
    }

    private func notification(for tool: Tool, turn: String? = "turn-1") -> String {
        notification(turn: turn, tool: tool.name)
    }

    private func event(_ name: String, turn: String = "turn-1", fields: String = "") -> String {
        #"{"cwd":"/repo","hook_event_name":"\#(name)","prompt_id":"\#(turn)","session_id":"c-1"\#(fields)}"#
    }

    private func land(_ hook: String, at second: Int) {
        let json = #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(t0 + second),"hook":\#(hook)}"#
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
        claude.refreshForTesting()
    }

    private func row() -> SessionRowPrompt? {
        SessionRowPrompt.make(indicator: .needsAttention, state: claude.state(for: id))
    }

    /// What tapping `shown` does through the real stale guard.
    private func tap(_ shown: SessionPopoverContent.ApprovalPrompt?) throws -> ApprovalOutcome {
        let shown = try XCTUnwrap(shown, "the row offered no Approve/Deny")
        let responder = GuardedApprovalResponder(
            isEnabled: { true }, currentState: { [claude] in claude?.state(for: $0) },
            ownSurface: { [surface] _ in surface }, send: { (_: ApprovalDecision, _: UUID) in }
        )
        return responder.respond(.approve, to: ApprovalTarget(
            sessionId: id, updatedAt: shown.updatedAt, surfaceId: surface, fingerprint: shown.fingerprint
        ))
    }

    // MARK: - Reading the real list back as text

    /// The real list, kept on screen so a later hook event has to reach it
    /// through whatever redraws it, not through a fresh render.
    private final class LiveList {
        let window: NSWindow
        let hosting: NSView
        let store: WorkspaceStore
        let coordinator: SessionCoordinator

        @MainActor init(id: UUID, claude: ClaudeStateStore) {
            let project = Project(name: "demo", rootPath: "/repo")
            let session = AgentSession(
                id: id, name: "demo line", templateId: UUID(), projectId: project.id,
                lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
            )
            store = WorkspaceStore(
                testingProjects: [project], testingSessions: [session],
                hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
            )
            store.updateIndicatorState(id: id, state: .needsAttention)
            store.updateSessionStatus(id: id, status: .running)
            coordinator = SessionCoordinator()
            coordinator.claudeStateStoreForTesting = claude
            let size = CGSize(width: 320, height: 300)
            let list = RecentsListView(previewDragState: SessionDragState())
                .environmentObject(store)
                .environmentObject(coordinator)
                .environmentObject(SidebarWidthModel(width: size.width))
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
            hosting = NSHostingView(rootView: list)
            hosting.frame = NSRect(origin: .zero, size: size)
            window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
        }

        /// Lower-cased text Vision reads off the window, upscaled 3x first.
        @MainActor func text() -> String {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return "" }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let cg = rep.cgImage else { return "" }
            let w = cg.width * 3, h = cg.height * 3
            guard let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return "" }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let big = ctx.makeImage() else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: big, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n").lowercased()
        }
    }

    private func assertRowOffersApproveDeny(_ tool: Tool, in list: LiveList, file: StaticString = #filePath, line: UInt = #line) {
        let shown = list.text()
        XCTAssertTrue(shown.contains(tool.question.lowercased()), "row must ask \"\(tool.question)\"; shows \(shown.debugDescription)", file: file, line: line)
        XCTAssertTrue(shown.contains("approve"), "row must offer Approve; shows \(shown.debugDescription)", file: file, line: line)
        XCTAssertTrue(shown.contains("deny"), "row must offer Deny; shows \(shown.debugDescription)", file: file, line: line)
        XCTAssertFalse(shown.contains("needs permission"), "the tool-less wording must not win; shows \(shown.debugDescription)", file: file, line: line)
    }

    private func requestThenNotification(_ tool: Tool, file: StaticString = #filePath, line: UInt = #line) throws {
        land(request(tool), at: 0)
        let list = LiveList(id: id, claude: claude)
        assertRowOffersApproveDeny(tool, in: list, file: file, line: line)
        let shown = row()?.approvalPrompt

        land(notification(for: tool), at: 6)
        XCTAssertEqual(row()?.question, tool.question, "the row's model still names the tool", file: file, line: line)
        assertRowOffersApproveDeny(tool, in: list, file: file, line: line)
        // The row kept what it drew, so that exact prompt must still be answerable.
        XCTAssertEqual(try tap(shown), .sent, "the Approve on screen still reaches the terminal", file: file, line: line)
    }

    private func notificationThenRequest(_ tool: Tool, file: StaticString = #filePath, line: UInt = #line) throws {
        land(notification(for: tool), at: 0)
        let list = LiveList(id: id, claude: claude)
        _ = list.text()

        land(request(tool), at: 1)
        XCTAssertEqual(row()?.question, tool.question, "the row's model names the tool", file: file, line: line)
        assertRowOffersApproveDeny(tool, in: list, file: file, line: line)
        XCTAssertEqual(try tap(row()?.approvalPrompt), .sent, file: file, line: line)
    }

    // MARK: - (b) both orders, Edit and Bash

    func testEditRequestThenNotificationKeepsApproveDeny() throws { try requestThenNotification(edit) }
    func testBashRequestThenNotificationKeepsApproveDeny() throws { try requestThenNotification(bash) }
    func testEditNotificationThenRequestOffersApproveDeny() throws { try notificationThenRequest(edit) }
    func testBashNotificationThenRequestOffersApproveDeny() throws { try notificationThenRequest(bash) }

    // MARK: - (c) a new prompt replaces, a resolution clears

    func testANewRequestInTheSameTurnReplacesThePendingPrompt() throws {
        land(request(edit), at: 0)
        let list = LiveList(id: id, claude: claude)
        assertRowOffersApproveDeny(edit, in: list)
        let old = row()?.approvalPrompt

        land(notification(for: edit), at: 6)
        land(request(bash), at: 7)
        XCTAssertEqual(row()?.question, bash.question)
        assertRowOffersApproveDeny(bash, in: list)
        XCTAssertEqual(try tap(old), .stale, "an Approve for the old prompt must not answer the new one")
        XCTAssertEqual(try tap(row()?.approvalPrompt), .sent)
    }

    /// The new turn's own `PermissionRequest` was never seen, so all that is
    /// known is the message. Keeping the old tool would approve the wrong thing.
    func testANotificationFromANewTurnIsANewPrompt() throws {
        land(request(edit), at: 0)
        let old = row()?.approvalPrompt
        land(notification(turn: "turn-2", tool: "Edit"), at: 6)
        XCTAssertEqual(claude.state(for: id)?.state, .needsPermission)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
        XCTAssertEqual(try tap(old), .stale)
    }

    /// The watcher coalesces PostToolUse(Edit) + PermissionRequest(Bash) +
    /// Notification into one read: only the Notification is seen. It names
    /// Bash, so the pending Edit prompt must not survive under it.
    func testACoalescedNotificationForAnotherToolNeverKeepsTheOldTool() throws {
        land(request(edit), at: 0)
        let old = row()?.approvalPrompt
        land(notification(for: bash), at: 6)
        XCTAssertEqual(claude.state(for: id)?.state, .needsPermission)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
        XCTAssertEqual(try tap(old), .stale, "Approve for Edit must not reach a Bash prompt")
    }

    /// A message that names no tool proves nothing about which prompt is up.
    func testANotificationThatNamesNoToolNeverKeepsTheOldTool() throws {
        land(request(edit), at: 0)
        let old = row()?.approvalPrompt
        land(notification(), at: 6)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
        XCTAssertEqual(try tap(old), .stale)
    }

    /// No `prompt_id` on either side (older Claude Code) is not "the same turn".
    func testANilPromptIdIsNeverTheSameTurn() throws {
        land(#"{"cwd":"/repo","hook_event_name":"PermissionRequest","session_id":"c-1",\#(edit.requestFields)}"#, at: 0)
        XCTAssertNil(claude.state(for: id)?.structuredPrompt?.promptId)
        let old = row()?.approvalPrompt
        land(notification(turn: nil, tool: "Edit"), at: 6)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
        XCTAssertEqual(try tap(old), .stale)
    }

    func testEveryResolutionClearsThePrompt() {
        let resolutions: [(String, ClaudeState.Kind)] = [
            (event("PreToolUse", fields: #","tool_name":"Edit","tool_use_id":"tu-1","tool_input":{}"#), .busy),
            (event("PostToolUse", fields: #","tool_name":"Edit","tool_use_id":"tu-1","tool_input":{}"#), .busy),
            (event("PostToolUseFailure", fields: #","tool_name":"Edit","tool_use_id":"tu-1""#), .busy),
            (event("PermissionDenied", fields: #","tool_name":"Edit""#), .busy),
            (event("UserPromptSubmit", fields: #","prompt":"go""#), .busy),
            (event("Stop"), .idle),
        ]
        for (index, (hook, kind)) in resolutions.enumerated() {
            let base = index * 100
            land(request(edit), at: base)
            land(notification(for: edit), at: base + 6)
            XCTAssertEqual(claude.state(for: id)?.state, .needsPermission, hook)
            land(hook, at: base + 7)
            XCTAssertEqual(claude.state(for: id)?.state, kind, hook)
            XCTAssertNil(claude.state(for: id)?.structuredPrompt, hook)
            XCTAssertNil(SessionRowPrompt.make(indicator: .needsAttention, state: claude.state(for: id)), hook)
        }
    }

    /// The prompt is gone, so a late notification has nothing to attach to:
    /// the tool of a resolved prompt is never brought back.
    func testALateNotificationDoesNotReviveAResolvedPrompt() {
        land(request(edit), at: 0)
        land(event("PostToolUse", fields: #","tool_name":"Edit","tool_use_id":"tu-1","tool_input":{}"#), at: 1)
        land(notification(for: edit), at: 6)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
    }

    /// `AskUserQuestion` answers by picking, so Approve's "1" would choose
    /// for the user. A tool-less notification must not turn it bounded.
    func testAPermissionNotificationNeverTurnsAQuestionIntoAnApproval() {
        land(event("PreToolUse", fields: #","tool_name":"AskUserQuestion","tool_use_id":"tu-1","tool_input":{"questions":[{"question":"Which env name?"}]}"#), at: 0)
        land(notification(), at: 6)
        XCTAssertEqual(claude.state(for: id)?.state, .needsInput)
        XCTAssertEqual(row()?.question, "Which env name?")
        XCTAssertNil(row()?.approvalPrompt)
    }

    // MARK: - The redraw signal

    func testOnlyAChangedPromptAsksRowsToRedraw() {
        var redraws = 0
        let subscription = claude.promptsDidChange.sink { redraws += 1 }
        defer { subscription.cancel() }

        land(event("PreToolUse", fields: #","tool_name":"Edit","tool_use_id":"tu-1","tool_input":{}"#), at: 0)
        land(event("PostToolUse", fields: #","tool_name":"Edit","tool_use_id":"tu-1","tool_input":{}"#), at: 1)
        XCTAssertEqual(redraws, 0, "ordinary tool events must not redraw the list")

        land(request(edit), at: 2)
        XCTAssertEqual(redraws, 1)
        land(notification(for: edit), at: 8)
        XCTAssertEqual(redraws, 1, "the same prompt: nothing to redraw")
        land(request(bash), at: 9)
        XCTAssertEqual(redraws, 2)
        land(event("PostToolUse", fields: #","tool_name":"Bash","tool_use_id":"tu-2","tool_input":{}"#), at: 10)
        XCTAssertEqual(redraws, 3)
    }
}
