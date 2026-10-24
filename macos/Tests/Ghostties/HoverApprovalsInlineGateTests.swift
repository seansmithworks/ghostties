import XCTest
import Combine
import SwiftUI
import Vision
import GhosttiesCore
@testable import Ghostty

/// C2 inline gate: hover-approvals card 01 "Spec, as settled" puts the
/// question and the actions INLINE in the sidebar session row (visible in
/// the revealed sidebar and when pinned), not on the floating hover card.
/// RED on `05bac92b9`, where the row subtitle only ever says "needs you" and
/// the row has no action line.
///
/// Card 01 (`.mild2wild/2026-10-21-hover-approvals/r1/card-01`), under
/// ATLAS-API "2 need you":
/// - "deploy preview": `?`, title, subtitle "Run npm test?", then an inline
///   Approve (ink) and Deny (quiet).
/// - "schema notes": `?`, title, subtitle "Which env name?", then the inline
///   link "Answer in terminal →".
/// - "auth refactor": spinner, subtitle "working", no action line.
///
/// Same harness as `HoverApprovalsGateTests`: real `RecentsListView` (or the
/// real `WorkspaceViewContainer` for rail and tile-x), fixture hook state in
/// a temp `ClaudeStateStore`, Vision OCR on the rendered pixels. No test
/// names a type the builder has yet to add.
///
/// Not gated here: that Approve/Deny/"Answer in terminal" fire (needs a live
/// surface; see `HoverApprovalsGateTests`).
@MainActor
final class HoverApprovalsInlineGateTests: XCTestCase {
    private let bashId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D1")!
    private let askId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D2")!
    private let idleId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D3")!
    private let staleId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D4")!
    private let workingId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D5")!
    private let noQuestionId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000D6")!

    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private let askQuestion = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-2","tool_name":"AskUserQuestion","tool_use_id":"tu-1","tool_input":{"questions":[{"question":"Which env name?","header":"Env","options":[{"label":"staging"},{"label":"prod"}],"multiSelect":false}]}}"#
    private let idlePrompt = #"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"idle_prompt","message":"idle","session_id":"c-3"}"#
    private let busyTool = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-5","tool_name":"Bash","tool_use_id":"tu-5","tool_input":{"command":"ls"}}"#
    private let noQuestion = #"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"agent_needs_input","message":"needs input","session_id":"c-6"}"#

    private var tempDirs: [URL] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        super.tearDown()
    }

    // MARK: - Fixtures

    private struct Row {
        let id: UUID
        let name: String
        let hook: String
        let indicator: SessionIndicatorState
    }

    private var bash: Row { Row(id: bashId, name: "deploy preview", hook: bashPermission, indicator: .needsAttention) }
    private var ask: Row { Row(id: askId, name: "schema notes", hook: askQuestion, indicator: .needsAttention) }
    private var noQ: Row { Row(id: noQuestionId, name: "release notes", hook: noQuestion, indicator: .needsAttention) }
    private var working: Row { Row(id: workingId, name: "auth refactor", hook: busyTool, indicator: .processing) }
    private var done: Row { Row(id: idleId, name: "field notes", hook: idlePrompt, indicator: .idle) }
    /// Cached indicator still says needs-attention; the hook has since gone idle.
    private var stale: Row { Row(id: staleId, name: "old thread", hook: idlePrompt, indicator: .needsAttention) }

    private func makeClaudeStore() -> (ClaudeStateStore, (String, UUID) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverApprovalsInlineGate-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        let store = ClaudeStateStore(directoryURL: dir)
        store.resumeWriterForTesting = { _, _ in }
        let write: (String, UUID) -> Void = { hook, id in
            let json = #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(Int(Date().timeIntervalSince1970)),"hook":\#(hook)}"#
            try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
            store.refreshForTesting()
        }
        return (store, write)
    }

    private struct World {
        let project: Project
        let store: WorkspaceStore
        let claude: ClaudeStateStore
        let sessions: [AgentSession]
    }

    private func world(_ rows: [Row]) -> World {
        let project = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let sessions = rows.map {
            AgentSession(
                id: $0.id, name: $0.name, templateId: UUID(), projectId: project.id,
                lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
            )
        }
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        let (claude, write) = makeClaudeStore()
        for row in rows {
            write(row.hook, row.id)
            store.updateIndicatorState(id: row.id, state: row.indicator)
            store.updateSessionStatus(id: row.id, status: .running)
        }
        return World(project: project, store: store, claude: claude, sessions: sessions)
    }

    // MARK: - Reading pixels back as text

    private func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
        let framed = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Lower-cased text Vision reads in `rep`, upscaled 3x first.
    private func text(in rep: NSBitmapImageRep?) -> String {
        guard let cg = rep?.cgImage else { return "" }
        let scale = 3
        let w = cg.width * scale, h = cg.height * scale
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
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").lowercased()
    }

    /// One project, one row per entry, through the real list.
    private func listText(_ rows: [Row]) -> String {
        let w = world(rows)
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = w.claude
        let width: CGFloat = 320
        let list = RecentsListView(previewDragState: SessionDragState())
            .environmentObject(w.store)
            .environmentObject(coordinator)
            .environmentObject(SidebarWidthModel(width: width))
        return text(in: render(list, size: CGSize(width: width, height: 420)))
    }

    /// Control: the reader sees the rows at all, so a red below is the
    /// feature missing, not the reader blind. Green on the base.
    func testHarnessReadsTheRows() {
        let shown = listText([bash, ask, working])
        for title in ["deploy preview", "schema notes", "auth refactor"] {
            XCTAssertTrue(shown.contains(title), "reader failed on \"\(title)\": \(shown.debugDescription)")
        }
        XCTAssertTrue(shown.contains("working"), "a working row says \"working\": \(shown.debugDescription)")
    }

    // MARK: - (g) a bounded prompt's subtitle is its question

    func testBoundedRowSubtitleIsTheQuestion() {
        let shown = listText([bash])
        XCTAssertTrue(shown.contains("run npm test?"), "bounded row subtitle must be \"Run npm test?\"; list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("needs you"), "the question replaces \"needs you\" as the subtitle; list shows \(shown.debugDescription)")
    }

    // MARK: - (h) a freeform row's subtitle is its question; no text falls back

    func testFreeformRowSubtitleIsTheQuestion() {
        let shown = listText([ask])
        XCTAssertTrue(shown.contains("which env name?"), "freeform row subtitle must be \"Which env name?\"; list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("needs you"), "the question replaces \"needs you\"; list shows \(shown.debugDescription)")
    }

    func testNeedsYouRowWithNoQuestionTextFallsBackToNeedsYou() {
        let shown = listText([noQ])
        XCTAssertTrue(shown.contains("release notes"), "control: the row renders; list shows \(shown.debugDescription)")
        XCTAssertTrue(shown.contains("needs you"), "no question text: subtitle falls back to \"needs you\"; list shows \(shown.debugDescription)")
        XCTAssertTrue(shown.contains("answer in terminal"), "a needs-you row with no question still gets the inline \"Answer in terminal\"; list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("approve"), "never an Approve without a bounded prompt; list shows \(shown.debugDescription)")
    }

    // MARK: - (i) the inline action line

    func testFlagOffBoundedRowShowsAnswerInTerminalAndNoApproveDeny() {
        XCTAssertFalse(ApprovalFlag.isEnabled, "precondition: the flag defaults off")
        let shown = listText([bash])
        XCTAssertTrue(shown.contains("answer in terminal"), "flag off: the bounded row shows an inline \"Answer in terminal\"; list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("approve"), "flag off: no Approve; list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("deny"), "flag off: no Deny; list shows \(shown.debugDescription)")
    }

    func testFlagOnBoundedRowShowsInlineApproveAndDeny() {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        let shown = listText([bash])
        XCTAssertTrue(shown.contains("approve"), "flag on: the bounded row shows an inline Approve; list shows \(shown.debugDescription)")
        XCTAssertTrue(shown.contains("deny"), "flag on: the bounded row shows an inline Deny; list shows \(shown.debugDescription)")
    }

    func testFreeformRowAlwaysShowsAnswerInTerminalNeverApproveDeny() {
        for flag in [false, true] {
            if flag { UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey) }
            let shown = listText([ask])
            XCTAssertTrue(shown.contains("answer in terminal"), "flag \(flag): the freeform row shows an inline \"Answer in terminal\"; list shows \(shown.debugDescription)")
            XCTAssertFalse(shown.contains("approve"), "flag \(flag): a freeform row never shows Approve; list shows \(shown.debugDescription)")
            XCTAssertFalse(shown.contains("deny"), "flag \(flag): a freeform row never shows Deny; list shows \(shown.debugDescription)")
        }
    }

    // MARK: - (j) rows that don't need you have no action line, no question

    func testRowsThatDoNotNeedYouHaveNoActionLineAndNoQuestion() {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        // The needs-you rows prove the same list DOES draw questions and an
        // action line when asked to, so the absences below are not vacuous.
        let needing = listText([bash, ask])
        XCTAssertTrue(needing.contains("run npm test?") && needing.contains("which env name?"),
                      "control: needs-you rows show their questions; list shows \(needing.debugDescription)")
        XCTAssertTrue(needing.contains("answer in terminal"), "control: needs-you rows draw an action line; list shows \(needing.debugDescription)")

        for (label, row, subtitle) in [("working", working, "working"), ("done", done, "done"), ("idle_prompt stale", stale, "done")] {
            let shown = listText([row])
            XCTAssertTrue(shown.contains(row.name), "\(label): the row renders; list shows \(shown.debugDescription)")
            XCTAssertTrue(shown.contains(subtitle), "\(label): subtitle \"\(subtitle)\"; list shows \(shown.debugDescription)")
            for forbidden in ["approve", "deny", "answer in terminal", "run npm test?", "which env name?", "needs you"] {
                XCTAssertFalse(shown.contains(forbidden), "\(label): no \"\(forbidden)\" on a row that doesn't need you; list shows \(shown.debugDescription)")
            }
        }
    }

    // MARK: - Container: rail (k) and tile x (l)

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// The real pinned sidebar holding `rows`, held at each morph progress in
    /// `steps` in turn; `body` runs once per step with the container.
    /// `redlines` off draws no badge, so OCR can't read through it; rects
    /// need it on.
    private func withContainer(_ rows: [Row], morph steps: [CGFloat], redlines: Bool = true, _ body: (WorkspaceViewContainer, CGFloat) throws -> Void) throws {
        try withDials({ $0.set(redlines, forKey: SidebarDialTuning.redlinesKey) }) {
            let tabKey = "ghostties.sidebarTab"
            let previousTab = UserDefaults.standard.object(forKey: tabKey)
            UserDefaults.standard.set(SidebarTab.projects.rawValue, forKey: tabKey)
            defer {
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }
            let w = world(rows)
            w.store.updateSidebarMode(.pinned)
            let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: w.store)
            container.coordinatorForTesting.claudeStateStoreForTesting = w.claude
            container.coordinatorForTesting.setActiveSessionIdForTesting(w.sessions[0].id)
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = container
            window.orderFrontRegardless()
            defer {
                window.contentView = nil
                window.orderOut(nil)
                window.close()
            }
            for _ in 0..<10 { container.layoutSubtreeIfNeeded(); spin(0.05) }
            for p in steps {
                container.applyMorphStep(p)
                for _ in 0..<6 { container.layoutSubtreeIfNeeded(); spin(0.05) }
                try body(container, p)
            }
        }
    }

    private func containerText(_ container: WorkspaceViewContainer) -> String {
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return "" }
        container.cacheDisplay(in: container.bounds, to: rep)
        return text(in: rep)
    }

    // (k) inline actions live in the expanded/revealed layout only.
    func testInlineActionsShowExpandedAndNeverOnTheCollapsedRail() throws {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        var expanded = "", rail = ""
        var railGlyph: CGRect?
        // Rects with Redlines on (its badge sits at mid-height and can
        // overlap OCR'd text); text with Redlines off.
        try withContainer([bash, ask], morph: [1]) { container, _ in
            let rects = container.redlineRegistryForTesting.rects
            railGlyph = rects[RedlineID.row(bashId) + ".glyph"] ?? rects[RedlineID.row(bashId) + ".chip"]
        }
        try withContainer([bash, ask], morph: [0, 1], redlines: false) { container, p in
            let shown = containerText(container)
            if p == 0 { expanded = shown } else { rail = shown }
        }
        for want in ["run npm test?", "which env name?", "approve", "deny", "answer in terminal"] {
            XCTAssertTrue(expanded.contains(want), "expanded sidebar must show inline \"\(want)\"; it shows \(expanded.debugDescription)")
        }
        XCTAssertNotNil(railGlyph, "control: the collapsed rail still draws the row's ? glyph slot")
        for banned in ["run npm test?", "which env name?", "approve", "deny", "answer in terminal", "needs you"] {
            XCTAssertFalse(rail.contains(banned), "collapsed rail is the ? glyph only, no \"\(banned)\"; it shows \(rail.debugDescription)")
        }
    }

    // (l) no tile shift: an action line never moves the glyph/tile column.
    func testActionLineDoesNotShiftTheTileOrGlyphColumn() throws {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        try withContainer([bash, working], morph: [0]) { container, _ in
            let shown = containerText(container)
            XCTAssertTrue(shown.contains("approve"), "precondition: the needs-you row draws its action line; it shows \(shown.debugDescription)")
            let rects = container.redlineRegistryForTesting.rects
            let withAction = rects[RedlineID.row(bashId) + ".glyph"]
            let without = rects[RedlineID.row(workingId) + ".glyph"]
            XCTAssertNotNil(withAction, "no glyph frame for the row with an action line")
            XCTAssertNotNil(without, "no glyph frame for the row without one")
            if let a = withAction, let b = without {
                XCTAssertEqual(a.minX, b.minX, accuracy: 0.5, "glyph x with action line \(a.minX) vs without \(b.minX)")
                XCTAssertEqual(a.width, b.width, accuracy: 0.5, "glyph width with action line \(a.width) vs without \(b.width)")
            }
            if let a = rects[RedlineID.row(bashId) + ".chip"], let b = rects[RedlineID.row(workingId) + ".chip"] {
                XCTAssertEqual(a.midX, b.midX, accuracy: 0.5, "chip centre x with action line \(a.midX) vs without \(b.midX)")
            }
        }
    }
}
