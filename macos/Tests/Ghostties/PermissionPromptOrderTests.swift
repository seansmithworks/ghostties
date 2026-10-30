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
/// Claude Code's real `permission_prompt` message names no tool, so the tool
/// comes from the hook's pending-permission sidecar (`<id>.permission.json`):
/// written on `PermissionRequest`, untouched by `Notification`, deleted by any
/// other event. `land` mimics the hook's file routing; `landCoalesced` and
/// `landMainOnly` model the watcher skipping events.
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

    /// Claude Code's real message: it names no tool.
    private func notification(turn: String? = "turn-1") -> String {
        let promptId = turn.map { #""prompt_id":"\#($0)","# } ?? ""
        return #"{"cwd":"/repo","hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"permission_prompt",\#(promptId)"session_id":"c-1","transcript_path":"/tmp/t.jsonl"}"#
    }

    private func event(_ name: String, turn: String = "turn-1", fields: String = "") -> String {
        #"{"cwd":"/repo","hook_event_name":"\#(name)","prompt_id":"\#(turn)","session_id":"c-1"\#(fields)}"#
    }

    private func envelope(_ hook: String, at second: Int) -> String {
        #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(t0 + second),"hook":\#(hook)}"#
    }

    private var mainURL: URL { dir.appendingPathComponent("\(id.uuidString).json") }
    private var sidecarURL: URL { dir.appendingPathComponent("\(id.uuidString).permission.json") }

    private func write(_ json: String, to url: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// One hook event, routed as `ghostties-status.sh` routes it:
    /// PermissionRequest -> main + sidecar; Notification -> main only;
    /// anything else -> main, sidecar deleted.
    private func land(_ hook: String, at second: Int) {
        let json = envelope(hook, at: second)
        if hook.contains(#""hook_event_name":"PermissionRequest""#) {
            write(json, to: sidecarURL)
        }
        write(json, to: mainURL)
        if !hook.contains(#""hook_event_name":"PermissionRequest""#), !hook.contains(#""hook_event_name":"Notification""#) {
            try? FileManager.default.removeItem(at: sidecarURL)
        }
        claude.refreshForTesting()
    }

    /// The watcher coalesced: the store reads only `hook` from the main file,
    /// while the sidecar holds `pending`, the request that really is up.
    private func landCoalesced(_ hook: String, at second: Int, pending: String, pendingAt: Int) {
        write(envelope(pending, at: pendingAt), to: sidecarURL)
        write(envelope(hook, at: second), to: mainURL)
        claude.refreshForTesting()
    }

    /// The main file with no sidecar beside it (an older hook, or a failed write).
    private func landMainOnly(_ hook: String, at second: Int) {
        try? FileManager.default.removeItem(at: sidecarURL)
        write(envelope(hook, at: second), to: mainURL)
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

        land(notification(), at: 6)
        XCTAssertEqual(row()?.question, tool.question, "the row's model still names the tool", file: file, line: line)
        assertRowOffersApproveDeny(tool, in: list, file: file, line: line)
        // The row kept what it drew, so that exact prompt must still be answerable.
        XCTAssertEqual(try tap(shown), .sent, "the Approve on screen still reaches the terminal", file: file, line: line)
    }

    private func notificationThenRequest(_ tool: Tool, file: StaticString = #filePath, line: UInt = #line) throws {
        land(notification(), at: 0)
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

        land(notification(), at: 6)
        land(request(bash), at: 7)
        XCTAssertEqual(row()?.question, bash.question)
        assertRowOffersApproveDeny(bash, in: list)
        XCTAssertEqual(try tap(old), .stale, "an Approve for the old prompt must not answer the new one")
        XCTAssertEqual(try tap(row()?.approvalPrompt), .sent)
    }

    /// The watcher coalesces PostToolUse(Edit) + PermissionRequest(Bash) +
    /// Notification into one read: the store sees only the Notification, with
    /// Edit as its previous state. The sidecar holds Bash, so Bash it is.
    func testACoalescedNotificationShowsTheSidecarsToolNeverThePreviousOne() throws {
        land(request(edit), at: 0)
        let old = row()?.approvalPrompt
        landCoalesced(notification(), at: 6, pending: request(bash, turn: "turn-2"), pendingAt: 5)
        XCTAssertEqual(claude.state(for: id)?.state, .needsPermission)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "Bash")
        XCTAssertEqual(row()?.question, bash.question)
        XCTAssertEqual(try tap(old), .stale, "Approve for Edit must not reach a Bash prompt")
        XCTAssertEqual(try tap(row()?.approvalPrompt), .sent)
    }

    /// No sidecar: the tool is unknown, so the row is tool-less and the
    /// Approve it showed for the request is stale.
    func testANotificationWithNoSidecarIsToolLessAndStale() throws {
        land(request(edit), at: 0)
        let old = row()?.approvalPrompt
        landMainOnly(notification(), at: 6)
        XCTAssertEqual(claude.state(for: id)?.state, .needsPermission)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
        XCTAssertEqual(try tap(old), .stale)
    }

    /// A notification read before any request (nothing written yet) is tool-less too.
    func testANotificationAloneIsToolLess() {
        land(notification(), at: 0)
        XCTAssertEqual(claude.state(for: id)?.structuredPrompt?.toolName, "")
    }

    /// A sidecar left behind is not a prompt: only a `permission_prompt`
    /// main file reads it.
    func testASidecarAloneNeverCreatesAPrompt() {
        land(event("Stop"), at: 1)
        write(envelope(request(edit), at: 0), to: sidecarURL)
        claude.refreshForTesting()
        XCTAssertNil(claude.state(for: id)?.structuredPrompt)
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
            land(notification(), at: base + 6)
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
        XCTAssertNil(FileManager.default.contents(atPath: sidecarURL.path), "the resolution deleted the sidecar")
        land(notification(), at: 6)
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
        land(notification(), at: 8)
        XCTAssertEqual(redraws, 1, "the same prompt: nothing to redraw")
        land(request(bash), at: 9)
        XCTAssertEqual(redraws, 2)
        land(event("PostToolUse", fields: #","tool_name":"Bash","tool_use_id":"tu-2","tool_input":{}"#), at: 10)
        XCTAssertEqual(redraws, 3)
    }
}
