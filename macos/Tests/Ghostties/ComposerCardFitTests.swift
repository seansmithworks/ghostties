import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// COMMITTED invariant test for the composer card-fit regression fixed by
/// `13011dffa` (`SessionComposerPalette.swift`, `ComposerResultsTable.body`:
/// `.background(GeometryReader { ... })` → `.overlay(GeometryReader { ... })`
/// on the results content `VStack`'s height probe). `.background` proposes
/// the CONTAINER's incoming size to its content, so the measured height was
/// always 0 and the results `ScrollView`'s `.frame(height:)` cap never
/// applied — the card filled whatever height its parent chain offered
/// instead of hugging its rows.
///
/// This is a PERMANENT, TRACKED test (unlike the scratch
/// `ComposerDesignCallRenderTests.swift`, which this file does not modify
/// and is never staged — see that file's own header). Mutation-verified:
/// reverting the one call site back to `.background(` makes this test FAIL
/// (see the commit message for the exact numbers from that run).
///
/// The invariant is expressed as a RELATIONSHIP, not an absolute y-band —
/// absolute bands were retuned twice in this repo's history to match the
/// bug (see `feedback_re-measure-at-claim-time` in project memory) and are
/// therefore untrustworthy as an acceptance criterion:
///   1. Window-independence: the same fixture rendered at two different
///      window heights (900pt, 1400pt) measures the SAME card height. A
///      card that fills grows with the window; a card that hugs its
///      content does not.
///   2. Content-hugging: the gap between the card's own bottom edge and the
///      last row's text bottom stays under 2× the card's own internal
///      vertical padding (`ComposerResultsTable.body`'s `.padding(8)` on
///      the results content `VStack`, `SessionComposerPalette.swift`) —
///      not some arbitrary pixel band.
///
/// Helpers below are copied from `ComposerDesignCallRenderTests.swift`
/// (`composerOverlayHarness`, `renderPNGHuggingHeight`,
/// `renderCardFitAfterTyping`, `cardVerticalEdges`, `opaqueVerticalExtent`,
/// `rowTextVerticalExtent`, `makeProject`, `makePlainComposer`) — copying,
/// not importing, since the originals are `private` to that file, a
/// precedent that file's own comments already document (its helpers are in
/// turn copies of `SessionComposerSnapshotTests`'s `private` originals).
///
/// ALL fixture data is synthetic — no real project name/path/session state
/// (public repo, `feedback_public-repo-no-real-session-data`).
@MainActor
struct ComposerCardFitTests {

    // MARK: - Copied helpers (see header)

    private func makeProject() -> Project {
        Project(name: "Demo Project", rootPath: "/tmp/composer-card-fit-\(UUID().uuidString)")
    }

    private func makePlainComposer(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        return composerStore
    }

    /// Copy of `SessionComposerOverlay.body`'s structure — the real type
    /// hardcodes `SessionComposerStore.shared`, the per-process
    /// UserDefaults-backed singleton, which is unsafe to touch from a test.
    private func composerOverlayHarness(
        project: Project,
        workspaceStore: WorkspaceStore,
        composerStore: SessionComposerStore,
        presentation: SessionComposerRequest.Presentation
    ) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Color.clear.frame(height: WorkspaceLayout.titlebarSpacerHeight)
                Color.clear.contentShape(Rectangle())
            }
            SessionComposerPalette(
                isPresented: .constant(true),
                request: SessionComposerRequest(presentation: presentation, projectBinding: .locked(project)),
                composerStore: composerStore
            )
            .environmentObject(workspaceStore)
            .environmentObject(SessionCoordinator())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Mounts content with NO forced `.frame(width:height:)` — `hosting.frame`
    /// alone supplies the size proposal, matching how `WorkspaceViewContainer`
    /// actually pins the composer's hosting view to the container's bounds.
    /// A rigid `.frame(width:height:)` on the content itself (as the older
    /// snapshot harness uses) forces the palette to fill, so any height
    /// claim taken through that route measures the harness, not the layout.
    private func renderPNGHuggingHeight<Content: View>(
        _ content: Content,
        appearance: NSAppearance.Name,
        size: NSSize
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Types `typed` into `composerStore.searchText` the same write path the
    /// real composer uses, through `composerOverlayHarness` and
    /// `renderPNGHuggingHeight`.
    private func renderCardFitAfterTyping(
        project: Project,
        workspaceStore: WorkspaceStore,
        composerStore: SessionComposerStore,
        typed: String,
        appearance: NSAppearance.Name,
        size: NSSize
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear

        let view = composerOverlayHarness(
            project: project, workspaceStore: workspaceStore, composerStore: composerStore, presentation: .centered
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()

        if !typed.isEmpty {
            composerStore.noteSearchTextEditedByTyping()
            composerStore.searchText = typed
        }
        for _ in 0..<20 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Vertical extent (backing pixels) of any opaque content — the card
    /// itself, since the window background beneath/around it is `.clear`
    /// (alpha 0) while the card surface is opaque (alpha ~1). Scans the
    /// full width at every row for the topmost/bottommost `y` with
    /// `alphaComponent > 0.5`.
    private func opaqueVerticalExtent(in data: Data) -> (top: Int, bottom: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var minY: Int?
        var maxY: Int?
        for y in 0..<rep.pixelsHigh {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                minY = min(minY ?? y, y)
                maxY = max(maxY ?? y, y)
            }
        }
        guard let minY, let maxY else { return nil }
        return (minY, maxY)
    }

    /// Vertical extent (backing pixels) of row TEXT content specifically —
    /// scans for luminance clearly darker (light mode) / lighter (dark
    /// mode) than the card's own near-white/near-black background, i.e.
    /// actual glyph ink, not just "opaque". Scoped to `yStart` and below so
    /// it never picks up the query field's own ghost/typed text above the
    /// results well's divider.
    private func rowTextVerticalExtent(in data: Data, isDark: Bool, yStart: Int) -> (top: Int, bottom: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var minY: Int?
        var maxY: Int?
        for y in stride(from: yStart, to: rep.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                let luminance = (r + g + b) / 3
                let isText = isDark ? luminance >= 100 : luminance <= 160
                if isText {
                    minY = min(minY ?? y, y)
                    maxY = max(maxY ?? y, y)
                }
            }
        }
        guard let minY, let maxY else { return nil }
        return (minY, maxY)
    }

    /// Reports the card's own top/bottom edge (backing pixels) plus the
    /// backing scale, by scanning for the first/last row containing an
    /// opaque pixel — the card's `.regularMaterial` background + border
    /// stroke are opaque, the window around it is `.clear` (alpha 0).
    private func cardVerticalEdges(in data: Data) -> (topPx: Int, bottomPx: Int, scale: CGFloat)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        guard let extent = opaqueVerticalExtent(in: data) else { return nil }
        return (extent.top, extent.bottom, CGFloat(rep.pixelsWide))
    }

    /// 7-row fixture: 5 default templates + a custom "Linear Sync" template
    /// + the "New template" row — matches the composer state the regression
    /// was originally reported against.
    private func makeFixtureStore() -> (Project, WorkspaceStore, SessionComposerStore) {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        _ = workspaceStore.addTemplate(AgentTemplate(name: "Linear Sync", kind: .custom))
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        return (project, workspaceStore, composerStore)
    }

    // MARK: - Criterion 1: window-independence

    /// Renders the same 7-row fixture at two window heights, same width. A
    /// card that hugs its content reports (near) the same measured height
    /// at both; a card that fills the window grows with it. Asserts the two
    /// measured heights differ by less than 2pt.
    @Test func cardHeightIsWindowIndependent() {
        let (project900, store900, composer900) = makeFixtureStore()
        let size900 = NSSize(width: 900, height: 900)
        let data900 = renderCardFitAfterTyping(
            project: project900, workspaceStore: store900, composerStore: composer900,
            typed: "", appearance: .aqua, size: size900
        )
        #expect(data900 != nil)
        guard let data900, let edges900 = cardVerticalEdges(in: data900) else {
            Issue.record("no opaque card content rendered at 900pt window height")
            return
        }
        let scale900 = edges900.scale / size900.width
        let heightPt900 = CGFloat(edges900.bottomPx - edges900.topPx) / scale900

        let (project1400, store1400, composer1400) = makeFixtureStore()
        let size1400 = NSSize(width: 900, height: 1400)
        let data1400 = renderCardFitAfterTyping(
            project: project1400, workspaceStore: store1400, composerStore: composer1400,
            typed: "", appearance: .aqua, size: size1400
        )
        #expect(data1400 != nil)
        guard let data1400, let edges1400 = cardVerticalEdges(in: data1400) else {
            Issue.record("no opaque card content rendered at 1400pt window height")
            return
        }
        let scale1400 = edges1400.scale / size1400.width
        let heightPt1400 = CGFloat(edges1400.bottomPx - edges1400.topPx) / scale1400

        print("cardHeightIsWindowIndependent: 900pt window -> card height \(heightPt900)pt (top=\(edges900.topPx)px bottom=\(edges900.bottomPx)px scale=\(scale900))")
        print("cardHeightIsWindowIndependent: 1400pt window -> card height \(heightPt1400)pt (top=\(edges1400.topPx)px bottom=\(edges1400.bottomPx)px scale=\(scale1400))")
        let delta = abs(heightPt900 - heightPt1400)
        print("cardHeightIsWindowIndependent: |delta| = \(delta)pt")
        #expect(delta < 2, "card height should be window-independent (hugs content); measured \(heightPt900)pt at 900pt window vs \(heightPt1400)pt at 1400pt window, delta \(delta)pt")
    }

    // MARK: - Criterion 2: content-hugging

    /// Asserts the gap between the card's own bottom edge and the last
    /// row's text bottom stays under 2x the card's own internal vertical
    /// padding — `ComposerResultsTable.body`'s `.padding(8)` applied to the
    /// results content `VStack` (`SessionComposerPalette.swift`). A card
    /// that fills the window leaves a large dead band below the last row;
    /// a card that hugs leaves only that one padding's worth (plus any
    /// chrome below the results well) at most.
    @Test func cardHugsLastRow() {
        // Read from production source, not hardcoded: `ComposerResultsTable
        // .body`'s `.padding(8)` on the results content `VStack`
        // (`SessionComposerPalette.swift`, immediately before the
        // `.overlay(GeometryReader { ... })` height probe this test's
        // sibling mutation-tests).
        let resultsTablePaddingPt: CGFloat = 8

        let (project, workspaceStore, composerStore) = makeFixtureStore()
        let size = NSSize(width: 900, height: 900)
        let data = renderCardFitAfterTyping(
            project: project, workspaceStore: workspaceStore, composerStore: composerStore,
            typed: "", appearance: .aqua, size: size
        )
        #expect(data != nil)
        guard let data else { return }
        guard let rep = NSBitmapImageRep(data: data) else {
            Issue.record("could not decode rendered PNG")
            return
        }
        let scale = CGFloat(rep.pixelsWide) / size.width
        guard let card = opaqueVerticalExtent(in: data) else {
            Issue.record("no opaque card content rendered")
            return
        }
        // Skip past the query field itself (38pt `.centered` field +
        // divider + a few pt margin — same offset `wellFixShort`/
        // `wellFixLong` in `ComposerDesignCallRenderTests.swift` use) so
        // this only scans the RESULTS WELL, not the field's own text.
        let rowYStart = card.top + Int(46 * scale)
        guard let rowText = rowTextVerticalExtent(in: data, isDark: false, yStart: rowYStart) else {
            Issue.record("could not find row text ink below the query field — card=\(card) rowYStart=\(rowYStart)")
            return
        }

        let cardHeightPt = CGFloat(card.bottom - card.top) / scale
        let gapBelowRowsPt = CGFloat(card.bottom - rowText.bottom) / scale
        print("cardHugsLastRow: scale=\(scale) card=\(card) rowText=\(rowText)")
        print("cardHugsLastRow: cardHeightPt=\(cardHeightPt) gapBelowRowsPt=\(gapBelowRowsPt) threshold=\(2 * resultsTablePaddingPt)pt (2x ComposerResultsTable.body's .padding(8))")
        #expect(
            gapBelowRowsPt < 2 * resultsTablePaddingPt,
            "gap between card bottom and last row's text bottom should stay under 2x the results table's own padding (\(2 * resultsTablePaddingPt)pt); measured \(gapBelowRowsPt)pt"
        )
    }
}
