import XCTest
import SwiftUI
import Vision
import GhosttiesCore
@testable import Ghostty

/// C2 gate: "hover with approvals" (mild2wild 2026-10-21 hover-approvals, card
/// 01 "spec as settled"). RED on the base that has `SessionAttention` and
/// `ApprovalResponder` but no UI for them.
///
/// These pin what a user SEES, not which type draws it. Each test builds
/// fixture state (invented payloads, a temp `ClaudeStateStore`, no
/// `~/.claude` or `~/.ghostties` read), renders the real SwiftUI view in an
/// off-screen window and reads the pixels back with Vision text recognition.
/// No test depends on a type or method C2 has yet to add, so the bundle
/// compiles on the base and a correct C2 turns these green whatever it names
/// its seams. `testHarnessReadsRenderedText` proves the reader can read text
/// at all, so a red below is the feature missing, not the reader blind.
///
/// Not gated here: that "Answer in terminal →" focuses the session. That
/// needs a live surface (`SessionCoordinator.focusSession` returns early
/// without one), the same limit `FocusRunningTaskTests` notes.
@MainActor
final class HoverApprovalsGateTests: XCTestCase {
    private let bashId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C1")!
    private let askId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C2")!
    private let idleId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C3")!
    private let staleId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C4")!

    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private let askQuestion = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-2","tool_name":"AskUserQuestion","tool_use_id":"tu-1","tool_input":{"questions":[{"question":"Which env name?","header":"Env","options":[{"label":"staging"},{"label":"prod"}],"multiSelect":false}]}}"#
    private let idlePrompt = #"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"idle_prompt","message":"idle","session_id":"c-3"}"#

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

    private func makeClaudeStore() -> (ClaudeStateStore, (String, UUID) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverApprovalsGate-\(UUID().uuidString)", isDirectory: true)
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

    private func session(_ id: UUID, _ name: String, in project: Project) -> AgentSession {
        AgentSession(
            id: id, name: name, templateId: UUID(), projectId: project.id,
            lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
        )
    }

    // MARK: - Reading pixels back as text

    private func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name = .aqua) -> NSBitmapImageRep? {
        let framed = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: appearance == .darkAqua ? .black : .white))
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Lower-cased text Vision reads in `rep`, upscaled 3x first so 11pt type
    /// survives a 1x headless backing store.
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

    // MARK: - Hover card

    private struct CardFixture {
        let controller: SessionPopoverController
        let model: SessionPopoverModel
    }

    /// The hover card for one fixture session, the way `SessionPopoverController`
    /// builds it from the indicator and the Claude hook state.
    private func hoverCard(hook: String, id: UUID, indicator: SessionIndicatorState = .needsAttention) -> CardFixture {
        let project = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let workspace = WorkspaceStore(testingProjects: [project], testingSessions: [session(id, "deploy preview", in: project)])
        workspace.updateIndicatorState(id: id, state: indicator)
        let (claude, write) = makeClaudeStore()
        write(hook, id)
        let controller = SessionPopoverController(coordinator: nil, workspace: workspace, claudeState: claude)
        controller.openForTesting(sessionId: id)
        let model = SessionPopoverModel()
        model.content = controller.contentForTesting
        return CardFixture(controller: controller, model: model)
    }

    private func cardText(hook: String, id: UUID) -> (text: String, hasContent: Bool) {
        let card = hoverCard(hook: hook, id: id)
        let rep = render(
            SessionPopoverCard(model: card.model, onHover: { _ in }),
            size: CGSize(width: SessionPopoverLayout.width + 2 * SessionPopoverLayout.shadowInset, height: 320)
        )
        return (text(in: rep), card.model.content != nil)
    }

    /// Control: the reader sees text on today's card and today's row. Green on
    /// the base; if it goes red, the reader is broken and every red below is noise.
    func testHarnessReadsRenderedText() {
        let card = cardText(hook: bashPermission, id: bashId)
        XCTAssertTrue(card.text.contains("npm test"), "reader failed on the card: \(card.text.debugDescription)")
        XCTAssertTrue(listText(sessions: [.bash]).contains("deploy preview"), "reader failed on the list")
    }

    // (a) a bounded permission prompt shows its question.
    func testBoundedPromptShowsItsQuestionOnTheHoverCard() {
        let card = cardText(hook: bashPermission, id: bashId)
        XCTAssertTrue(card.hasContent, "the card has content for a bounded prompt")
        XCTAssertTrue(card.text.contains("run npm test?"), "hover card must show the question \"Run npm test?\"; it shows \(card.text.debugDescription)")
    }

    // (b) an AskUserQuestion / freeform session shows its question text.
    func testFreeformQuestionShowsItsTextOnTheHoverCard() {
        let card = cardText(hook: askQuestion, id: askId)
        XCTAssertTrue(card.hasContent, "AskUserQuestion must get a hover card (the controller dismisses it today)")
        XCTAssertTrue(card.text.contains("which env name?"), "hover card must show \"Which env name?\"; it shows \(card.text.debugDescription)")
    }

    // (c) Approve/Deny stay off with the flag off; "Answer in terminal" is always there.
    func testApproveDenyAbsentWhileFlagOffAndAnswerInTerminalAlwaysPresent() {
        XCTAssertFalse(ApprovalFlag.isEnabled, "precondition: the flag defaults off")
        for (label, hook, id) in [("bounded", bashPermission, bashId), ("freeform", askQuestion, askId)] {
            let card = cardText(hook: hook, id: id)
            XCTAssertFalse(card.text.contains("approve"), "\(label): no Approve while the flag is off")
            XCTAssertFalse(card.text.contains("deny"), "\(label): no Deny while the flag is off")
            XCTAssertTrue(card.text.contains("answer in terminal"), "\(label): \"Answer in terminal →\" is always present; card shows \(card.text.debugDescription)")
        }
    }

    /// Control for the absence test above: with the flag on, a bounded prompt
    /// does render Approve and Deny, so "absent while off" is not vacuous.
    func testApproveDenyRenderForABoundedPromptWhenFlagOn() {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        let card = cardText(hook: bashPermission, id: bashId)
        // Sean decision 2026-10-22: actions live in the row only
        XCTAssertTrue(card.text.contains("run npm test?"), "flag on: the card still shows the question; card shows \(card.text.debugDescription)")
        XCTAssertTrue(card.text.contains("answer in terminal"), "flag on: \"Answer in terminal →\" stays; card shows \(card.text.debugDescription)")
        XCTAssertFalse(card.text.contains("approve"), "flag on: the card never shows Approve; card shows \(card.text.debugDescription)")
        XCTAssertFalse(card.text.contains("deny"), "flag on: the card never shows Deny; card shows \(card.text.debugDescription)")
        // A freeform question is never approvable, flag or not.
        let freeform = cardText(hook: askQuestion, id: askId)
        XCTAssertFalse(freeform.text.contains("approve"), "freeform: never an Approve")
    }

    // MARK: - Project header and row subtitle

    private enum Kind { case bash, ask, idlePrompt, staleIndicator }

    /// One project, one row per `sessions` entry, through the real list. The
    /// indicator cache and the Claude hook state are fed the way the
    /// coordinator feeds them: `.staleIndicator` is a row whose cached
    /// indicator still says needs-attention while its hook state has since
    /// gone idle (a finished session; `idle_prompt` is not attention).
    private func listText(sessions kinds: [Kind]) -> String {
        let project = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let ids: [Kind: UUID] = [.bash: bashId, .ask: askId, .idlePrompt: idleId, .staleIndicator: staleId]
        let names: [Kind: String] = [.bash: "deploy preview", .ask: "schema notes", .idlePrompt: "field notes", .staleIndicator: "auth refactor"]
        let rows = kinds.map { session(ids[$0]!, names[$0]!, in: project) }
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: rows,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        let (claude, write) = makeClaudeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = claude
        for kind in kinds {
            let id = ids[kind]!
            switch kind {
            case .bash:
                write(bashPermission, id)
                store.updateIndicatorState(id: id, state: .needsAttention)
            case .ask:
                write(askQuestion, id)
                store.updateIndicatorState(id: id, state: .needsAttention)
            case .idlePrompt:
                write(idlePrompt, id)
                store.updateIndicatorState(id: id, state: .idle)
            case .staleIndicator:
                write(idlePrompt, id)
                store.updateIndicatorState(id: id, state: .needsAttention)
            }
            store.updateSessionStatus(id: id, status: .running)
        }
        let width: CGFloat = 320
        let list = RecentsListView(previewDragState: SessionDragState())
            .environmentObject(store)
            .environmentObject(coordinator)
            .environmentObject(SidebarWidthModel(width: width))
        return text(in: render(list, size: CGSize(width: width, height: 420)))
    }

    // (d) "N need you" counts genuine attention only; idle_prompt never counts.
    func testProjectHeaderCountsOnlyGenuineAttention() {
        let shown = listText(sessions: [.bash, .ask, .idlePrompt, .staleIndicator])
        XCTAssertTrue(shown.contains("2 need you"), "header must read \"2 need you\" (bash + ask); list shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("3 need you"), "idle_prompt must not count")
        XCTAssertFalse(shown.contains("4 need you"), "a stale needs-attention indicator must not count")
    }

    // (e) the row subtitle says "needs you" only for genuine attention.
    func testRowSubtitleSaysNeedsYouOnlyForGenuineAttention() {
        let genuine = listText(sessions: [.bash])
        XCTAssertTrue(genuine.contains("run npm test?"), "control: a genuine prompt's row subtitle is its question (card 01); list shows \(genuine.debugDescription)")

        let stale = listText(sessions: [.staleIndicator])
        XCTAssertFalse(stale.contains("needs you"), "a session whose hook state is idle (idle_prompt) must not say \"needs you\"; list shows \(stale.debugDescription)")
        XCTAssertFalse(stale.contains("need you"), "and the header counts nothing; list shows \(stale.debugDescription)")
    }

    // MARK: - (f) the ? glyph is ink, not terracotta (DESIGN.md §4)

    func testNeedsInputGlyphIsInkNotTerracotta() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let rep = try XCTUnwrap(render(
                SessionStatusGlyph(kind: .needsInput, size: 64).padding(8),
                size: CGSize(width: 80, height: 80), appearance: appearance
            ))
            var inked = 0, warm = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let bg: CGFloat = appearance == .darkAqua ? 0 : 1
                    if abs(c.redComponent - bg) + abs(c.greenComponent - bg) + abs(c.blueComponent - bg) > 0.6 { inked += 1 }
                    // Terracotta #C97350 is red-heavy: red leads blue by ~0.48.
                    if c.redComponent - c.blueComponent > 0.2 { warm += 1 }
                }
            }
            XCTAssertGreaterThan(inked, 0, "the ? draws (\(appearance.rawValue))")
            XCTAssertEqual(warm, 0, "the ? is ink, not terracotta (\(appearance.rawValue))")
        }
    }
}
