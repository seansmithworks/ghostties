import XCTest
import SwiftUI
import Vision
import GhosttiesCore
@testable import Ghostty

/// Hover-approvals follow-up A (Sean, 2026-10-22): the floating hover card
/// never shows Approve/Deny, even with `ApprovalFlag` on and a bounded
/// prompt; the sidebar row owns them. The card keeps its question and
/// "Answer in terminal →".
///
/// Fixture state only: an invented hook payload in a temp `ClaudeStateStore`.
@MainActor
final class HoverCardNoApproveDenyTests: XCTestCase {
    private let bashId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000F1")!
    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private var tempDir: URL?

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: ApprovalFlag.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        super.tearDown()
    }

    /// Lower-cased text Vision reads in the rendered card, upscaled 3x first
    /// so 11pt type survives a 1x headless backing store.
    private func renderedText<V: View>(_ view: V, size: CGSize) -> String {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top).background(Color.white))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
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
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").lowercased()
    }

    func testHoverCardNeverShowsApproveOrDeny() {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        let project = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let session = AgentSession(
            id: bashId, name: "deploy preview", templateId: UUID(), projectId: project.id,
            lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
        )
        let workspace = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        workspace.updateIndicatorState(id: bashId, state: .needsAttention)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverCardNoApproveDeny-\(UUID().uuidString)", isDirectory: true)
        tempDir = dir
        let claude = ClaudeStateStore(directoryURL: dir)
        claude.resumeWriterForTesting = { _, _ in }
        let json = #"{"ghosttiesSessionId":"\#(bashId.uuidString)","updatedAt":\#(Int(Date().timeIntervalSince1970)),"hook":\#(bashPermission)}"#
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? json.write(to: dir.appendingPathComponent("\(bashId.uuidString).json"), atomically: true, encoding: .utf8)
        claude.refreshForTesting()

        let controller = SessionPopoverController(coordinator: nil, workspace: workspace, claudeState: claude)
        controller.openForTesting(sessionId: bashId)
        let model = SessionPopoverModel()
        model.content = controller.contentForTesting

        let shown = renderedText(
            SessionPopoverCard(model: model, onHover: { _ in }),
            size: CGSize(width: SessionPopoverLayout.width + 2 * SessionPopoverLayout.shadowInset, height: 320)
        )
        XCTAssertTrue(shown.contains("run npm test?"), "control: the card keeps its question; it shows \(shown.debugDescription)")
        XCTAssertTrue(shown.contains("answer in terminal"), "the card keeps \"Answer in terminal →\"; it shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("approve"), "flag on, bounded prompt: no Approve on the card; it shows \(shown.debugDescription)")
        XCTAssertFalse(shown.contains("deny"), "flag on, bounded prompt: no Deny on the card; it shows \(shown.debugDescription)")
    }
}
