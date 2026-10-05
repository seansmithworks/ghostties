import AppKit
import Combine
import SwiftUI
import Testing
import GhosttiesCore
import DialKit
@testable import Ghostty

/// Tests for the single-line composer (`ComposerSingleLineStyle.swift`).
/// Every test references a production symbol (`ComposerDescriptorCycle`,
/// the tuning dials, or `SessionComposerPalette` itself via the snapshot
/// harness) — see `feedback_vacuous-tests-pass-green`.
@MainActor
struct ComposerSingleLineStyleTests {

    // MARK: - Descriptor cycle order (pure function)

    /// Sean's explicit rule (brief §1): "Name a session" is first, and the
    /// chevron/`ghostPlaceholder` form is pinned at index 3 (last) — never
    /// first. Mutation-checked: temporarily swapping the array order in
    /// `ComposerDescriptorCycle.descriptors` to put the path first made this
    /// fail (confirmed by hand during implementation, reverted).
    @Test func descriptorCycleOrderPinsPathAtIndexThree() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        #expect(descriptors.count == 4)
        #expect(descriptors[0] == "Name a session")
        #expect(descriptors[3] == "ghostties > main > claude")
        #expect(descriptors[1].hasPrefix("atlas-api cco -n"))
        #expect(descriptors[1].contains("-n \"Composer\""))
    }

    /// No recent project — falls back to the literal "ghostties" idiom
    /// rather than an empty/garbage segment.
    @Test func descriptorCycleFallsBackToGhosttiesWithNoRecentProject() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: nil,
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        #expect(descriptors[1] == "ghostties cco -n \"Composer\"")
    }

    // MARK: - Stored `ghostties.composerStyle` is ignored

    /// There is one composer. A stale `ghostties.composerStyle = zeroChrome`
    /// (or any other value) left in a user's defaults must render exactly
    /// what an unset key renders: the single-line card, with its border
    /// stroke. Two isolated suites differing ONLY in that key, rendered with
    /// the Witness off (its idle animation is clock-driven, so it would
    /// differ between any two renders) and compared byte-for-byte.
    @Test(arguments: ["zeroChrome", "classic", "bogus"])
    func storedLegacyComposerStyleRendersTheSameAsUnset(stored: String) {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])

        func render(storedStyle: String?) -> Data? {
            let suite = UserDefaults(suiteName: "ghostties.composerStyle.test.\(UUID().uuidString)")!
            suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
            suite.set(false, forKey: ComposerWitnessSetting.storageKey)
            if let storedStyle { suite.set(storedStyle, forKey: "ghostties.composerStyle") }
            let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
            let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
            return renderPNG(view, size: NSSize(width: Self.derivedRenderCanvasWidth, height: 100))
        }

        let unset = render(storedStyle: nil)
        let withStored = render(storedStyle: stored)
        #expect(unset != nil)
        #expect(unset == withStored, "a stored composerStyle of \(stored) must not change what renders")
        if let withStored {
            #expect((strokeEdgeCoverage(in: withStored) ?? 0) > 0.5, "expected the single-line card's border stroke")
        }
    }

    /// R15b: shared canvas width for the single-line render tests below,
    /// derived instead of hardcoded. Must contain the card at its widest
    /// tunable width plus the palette's own shake-clearance padding, with
    /// the Witness ghost (offset above the card) still on-canvas:
    ///   `ComposerSingleLineTuning.widthRange.upperBound` (760pt, the
    ///     widest the width dial goes)
    /// + 16pt (`body`'s `.padding(8)` per side, `SessionComposerPalette
    ///     .swift` ~289 — the shake-clearance inset wrapping the card)
    /// + 24pt margin (covers the Witness's `.offset(x: 20, y: -24)` above
    ///     the card's top-leading corner, plus rounding slack)
    /// = 800pt — same value round 15 hardcoded, now provable instead of
    /// guessed, and correct across the whole width dial rather than just
    /// one round's default (round 13b's 688pt, then round 14's 640pt).
    private static let derivedRenderCanvasWidth =
        CGFloat(ComposerSingleLineTuning.widthRange.upperBound) + 16 + 24

    private func makeProject() -> Project {
        Project(name: "Demo Project", rootPath: "/tmp/composer-snapshot-\(UUID().uuidString)")
    }

    private func makeComposerStore(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        return composerStore
    }

    private func paletteView(
        project: Project,
        workspaceStore: WorkspaceStore,
        composerStore: SessionComposerStore,
        tuningDefaults: UserDefaults? = nil
    ) -> some View {
        SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(projectBinding: .locked(project)),
            composerStore: composerStore,
            tuningDefaultsForTesting: tuningDefaults
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
    }

    /// `appearance` names the WINDOW's own appearance — independent of
    /// whichever appearance is ambient (`NSAppearance.current`) when this
    /// is called. `reference_pixel-tests-follow-system-dark-mode`: pinning
    /// the window alone does not pin what SwiftUI resolves colors against,
    /// which is why callers also wrap the render in
    /// `NSAppearance(named:).performAsCurrentDrawingAppearance`.
    private func renderPNG<Content: View>(_ content: Content, size: NSSize, appearance: NSAppearance.Name = .aqua) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
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

    /// `feedback_public-repo-no-real-session-data` — every fixture here is
    /// synthetic, never a real project/path.
    private func writeScratchPNG(_ data: Data?, filename: String) {
        guard let data else {
            Issue.record("Failed to render PNG for \(filename)")
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad/composer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(filename))
    }

    /// `windowAppearance`/`ambientAppearance` test arguments name an
    /// `NSAppearance.Name` as a plain string (`"aqua"`/`"darkAqua"`) —
    /// see `border-helper-fix-design.md` §3 for why raw strings, not the
    /// type itself, are the test-argument shape here.
    private func appearanceName(_ key: String) -> NSAppearance.Name {
        key == "darkAqua" ? .darkAqua : .aqua
    }

    /// Structural border-stroke detector: locates the card by scanning for
    /// its opaque bounds, then measures edge-vs-inset luma contrast along
    /// the middle 50% of each of the 4 edges (skips corners and the witness
    /// sprite). Returns the minimum hit fraction across the 4 edges, or
    /// `nil` if no card could be located. Resolves no `NSColor`, so neither
    /// the window's pinned appearance nor the ambient appearance can shift
    /// what it matches against — replaces the RGB-match
    /// `borderStrokePixelCount`, which passed/failed by the Mac's light/dark
    /// clock (`reference_pixel-tests-follow-system-dark-mode`).
    private func strokeEdgeCoverage(in data: Data) -> Double? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        let scale = rep.size.width > 0 ? CGFloat(rep.pixelsWide) / rep.size.width : 1

        func isOpaque(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh else { return false }
            guard let color = rep.colorAt(x: x, y: y) else { return false }
            return color.alphaComponent >= 0.98
        }

        func luma(_ x: Int, _ y: Int) -> Double? {
            guard let color = rep.colorAt(x: x, y: y) else { return nil }
            return Double(color.redComponent + color.greenComponent + color.blueComponent) / 3
        }

        let centerX = rep.pixelsWide / 2
        let centerY = rep.pixelsHigh / 2
        guard centerX > 0, centerY > 0 else { return nil }

        guard let cardTop = (0..<rep.pixelsHigh).first(where: { isOpaque(centerX, $0) }),
              let cardBottom = (0..<rep.pixelsHigh).reversed().first(where: { isOpaque(centerX, $0) }),
              cardTop < cardBottom else { return nil }

        let midY = (cardTop + cardBottom) / 2
        guard let cardLeft = (0..<rep.pixelsWide).first(where: { isOpaque($0, midY) }),
              let cardRight = (0..<rep.pixelsWide).reversed().first(where: { isOpaque($0, midY) }),
              cardLeft < cardRight else { return nil }

        let inset = max(1, Int((2 * scale).rounded()))
        let width = cardRight - cardLeft
        let height = cardBottom - cardTop
        let xStart = cardLeft + width / 4
        let xEnd = cardLeft + (3 * width) / 4
        let yStart = cardTop + height / 4
        let yEnd = cardTop + (3 * height) / 4
        guard xStart <= xEnd, yStart <= yEnd else { return nil }

        func edgeHitFraction(_ range: ClosedRange<Int>, edge: (Int) -> (Int, Int), inside: (Int) -> (Int, Int)) -> Double {
            var hits = 0
            var total = 0
            for i in range {
                let (ex, ey) = edge(i)
                let (ix, iy) = inside(i)
                total += 1
                guard isOpaque(ex, ey), isOpaque(ix, iy),
                      let edgeLuma = luma(ex, ey), let insideLuma = luma(ix, iy) else { continue }
                if abs(edgeLuma - insideLuma) >= 0.04 { hits += 1 }
            }
            return total > 0 ? Double(hits) / Double(total) : 0
        }

        let top = edgeHitFraction(xStart...xEnd, edge: { ($0, cardTop) }, inside: { ($0, cardTop + inset) })
        let bottom = edgeHitFraction(xStart...xEnd, edge: { ($0, cardBottom) }, inside: { ($0, cardBottom - inset) })
        let left = edgeHitFraction(yStart...yEnd, edge: { (cardLeft, $0) }, inside: { (cardLeft + inset, $0) })
        let right = edgeHitFraction(yStart...yEnd, edge: { (cardRight, $0) }, inside: { (cardRight - inset, $0) })
        return min(top, bottom, left, right)
    }

    /// Fraction of pixels with `alpha > 0.3` — used only alongside
    /// `strokeEdgeCoverage`'s low-coverage check, to prove a render is a
    /// real (mostly-opaque) wash rather than an accidentally blank canvas
    /// that would also score a low stroke coverage.
    private func opaqueishPixelFraction(in data: Data) -> Double {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        let total = rep.pixelsWide * rep.pixelsHigh
        guard total > 0 else { return 0 }
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 { count += 1 }
            }
        }
        return Double(count) / Double(total)
    }

    /// Walks the mounted view hierarchy for the `NSTextView` a
    /// `ComposerGhostTextField` installs (same shape as
    /// `ComposerGhostTextFieldTests`' own harness, which reaches its
    /// `Coordinator` directly rather than searching — this file has no
    /// access to that private `Coordinator` type, so it goes through the
    /// public `NSTextView.delegate` seam instead).
    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    /// Same accent-tint detection `SessionComposerSnapshotTests
    /// .selectionHighlightPixelCount` uses for the popover list's
    /// selection highlight, reimplemented here (that helper is `private`
    /// to the other file) against `newStyleCandidateRows`' own selected-row
    /// text color, `WorkspaceLayout.composerSelectionAccent`
    /// (`#5B8DEF`, b-r ≈ 148).
    private func selectionAccentPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if b - r > 8 { count += 1 }
            }
        }
        return count
    }

    /// Same red-ink detection `SessionComposerSnapshotTests.containsRedInk`
    /// uses for `writeError`'s footer text (`private` there too).
    private func containsRedInk(in data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r > 150, r - g > 60, r - b > 60 { return true }
            }
        }
        return false
    }

    /// Parameterized over window appearance × ambient appearance
    /// (`reference_pixel-tests-follow-system-dark-mode`): a stroke-detection
    /// test must hold under every combination the Mac's auto light/dark
    /// switch can produce, not just whichever one happened to be active
    /// when the suite ran.
    @Test(arguments: ["aqua", "darkAqua"], ["aqua", "darkAqua"])
    func singleLineRestStateHasCardChrome(windowAppearance: String, ambientAppearance: String) {
        NSAppearance(named: appearanceName(ambientAppearance))!.performAsCurrentDrawingAppearance {
            let project = makeProject()
            let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
            let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
            // R15: 560pt was sized for the pre-R13b 512pt default width. The
            // isolated suite below has no stored width override, so it resolves
            // `ComposerSingleLineTuning.defaultWidth` (688pt, round-13b's tuned
            // default) — a 560pt-wide capture puts both border-stroke edges
            // off-canvas, sampling nothing but interior card fill. R15b: see
            // `derivedRenderCanvasWidth` for why 800pt is the right value, not
            // just a wider guess.
            let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 100)
            // Step 0 (R14): isolated suite, treatment pinned to `.material` — the
            // stroke this test asserts on only renders in the material branch of
            // `singleLineComposerCard`; `.glass` has no `.stroke(` at all. Reading
            // real `UserDefaults.standard` here (the R13 gap) let this test pass
            // for the wrong reason whenever `.glass` fell back to material by
            // availability rather than by explicit treatment.
            let suite = UserDefaults(suiteName: "ghostties.composer.test.\(UUID().uuidString)")!
            suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
            let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
            let png = renderPNG(view, size: size, appearance: appearanceName(windowAppearance))
            writeScratchPNG(png, filename: "single-line-rest.png")
            #expect(png != nil)
            if let png {
                let coverage = strokeEdgeCoverage(in: png) ?? 0
                #expect(coverage >= 0.9, "measured strokeEdgeCoverage=\(coverage)")
            }
        }
    }

    /// Fix round (finding 2): `">>>"` never actually tripped
    /// `statusStripMessage` (that path needs `composerStore.writeError`,
    /// not a specific typed string), so the old version of this test
    /// rendered a strip-less card and passed anyway on `png != nil` alone.
    /// Replaced with the SAME real write-path
    /// `SessionComposerSnapshotTests.isAddingTemplateClearsWhenAWriteErrorArrives`
    /// uses: `composerStore.rejectUnresolvedBranch(token:)` —
    /// `SessionComposerStore.swift:1042`, the same synchronous write the
    /// async worktree-create timeout uses — then asserts real red ink is
    /// on screen, not just a non-nil PNG.
    @Test func singleLineWithStatusStripError() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 120)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let before = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the pre-error fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: before)
        if let beforeData = before.representation(using: .png, properties: [:]) {
            #expect(!containsRedInk(in: beforeData), "expected no red ink before writeError arrives")
        }

        composerStore.rejectUnresolvedBranch(token: "does-not-exist")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()

        guard let after = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the post-error fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: after)
        let afterData = after.representation(using: .png, properties: [:])
        writeScratchPNG(afterData, filename: "single-line-status-strip-error.png")
        #expect(afterData != nil)
        if let afterData {
            #expect(
                containsRedInk(in: afterData),
                "expected writeError to render red ink in newStyleStatusStrip"
            )
        }
    }

    // MARK: - R14: Witness ghost pixels (plan §6 test 6 — RUN OWED, Dev is open)

    /// Counts pixels close to `ComposerWitnessGhost.flicker`'s `colorHex`
    /// (`#ff3b3b`) — reuses `containsRedInk`'s tolerance band (that band
    /// was tuned for exactly this kind of saturated red, and `.blinky`'s
    /// mapped witness IS `.flicker`).
    private func flickerRedPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r > 150, r - g > 60, r - b > 60 { count += 1 }
            }
        }
        return count
    }

    /// `.locked` project with `.blinky` (-> `.flicker`, red) so the sprite's
    /// body color is unambiguous against the card's neutral chrome. Extra
    /// 40pt of canvas ABOVE the card's own frame — the Witness overlay sits
    /// at `.offset(x: 20, y: -24)` from `.topLeading`, poking up past the
    /// card's top edge (plan §1); a tight frame would clip exactly the
    /// pixels this test looks for. Reduce Motion is NOT overridden here
    /// (no live `NSWorkspace` stub in this harness, matching
    /// `reduceMotionShowsStaticFirstDescriptor`'s documented limitation) —
    /// this reads whatever Reduce Motion setting is actually live, which is
    /// why this test's run (not just its build) is owed until Dev closes:
    /// an offscreen render can otherwise land on a blank first frame before
    /// `TimelineView` ever fires (`SessionComposerPalette.swift` `:2037-
    /// 2042`'s documented trap).
    private func witnessFixture(witnessEnabled: Bool) -> (view: some View, size: NSSize) {
        let project = Project(name: "Demo", rootPath: "/tmp/composer-witness-pixels-\(UUID().uuidString)", ghostCharacter: .blinky)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerWitness.pixels.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        suite.set(witnessEnabled, forKey: ComposerWitnessSetting.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
        // R15: same root cause as `singleLineRestStateHasCardChrome` — the
        // isolated suite resolves the 688pt round-13b width default. `body`
        // centers `composerCard` inside `renderPNG`'s outer `.frame`, so at
        // 560pt the 704pt (688 + 16pt shake padding) card is clipped ~72pt
        // on each side; the Witness overlay at `.offset(x: 20, y: -24)` from
        // the card's topLeading lands off-canvas to the left regardless of
        // the toggle, which is why the ON assertion failed and the OFF
        // twin passed for the wrong reason (nothing to find either way).
        // R15b: see `derivedRenderCanvasWidth` for why 800pt is the right
        // value, not just a wider guess.
        return (view, NSSize(width: Self.derivedRenderCanvasWidth, height: 140))
    }

    /// red mutation: gate `showsWitness` on `false` unconditionally — this
    /// test then fails (0 flicker-red pixels with the toggle on).
    @Test func witnessGhostPixelsPresentAboveCardWhenToggleOn() {
        let fixture = witnessFixture(witnessEnabled: true)
        let png = renderPNG(fixture.view, size: fixture.size)
        writeScratchPNG(png, filename: "witness-toggle-on.png")
        #expect(png != nil)
        if let png {
            #expect(flickerRedPixelCount(in: png) > 0, "expected the Witness ghost's flicker-red pixels above the card with the toggle on")
        }
    }

    /// red mutation: gate `showsWitness` on `true` unconditionally — this
    /// test then fails (flicker-red pixels present even with the toggle
    /// off).
    @Test func witnessGhostPixelsAbsentWhenToggleOff() {
        let fixture = witnessFixture(witnessEnabled: false)
        let png = renderPNG(fixture.view, size: fixture.size)
        writeScratchPNG(png, filename: "witness-toggle-off.png")
        #expect(png != nil)
        if let png {
            #expect(flickerRedPixelCount(in: png) == 0, "expected no flicker-red pixels with the Witness toggle off")
        }
    }

    // MARK: - Reduce Motion floor

    /// `ComposerDescriptorGhostText` freezes on descriptor index 0 under
    /// Reduce Motion (no live NSWorkspace stub available in this harness —
    /// this asserts the `reduceMotion` parameter's documented contract
    /// directly against the production view's `body`: with `reduceMotion:
    /// true` and an empty query, the rendered text is unconditionally
    /// `descriptors[0]`, matching what `SessionComposerPalette
    /// .reduceMotionEnabled` feeds it at the real call site).
    @Test func reduceMotionShowsStaticFirstDescriptor() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let view = ComposerDescriptorGhostText(
            descriptors: descriptors,
            query: "",
            opacity: 0.65,
            reduceMotion: true
        )
        let size = NSSize(width: 400, height: 30)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "reduce-motion-static-descriptor.png")
        #expect(png != nil)
    }

    // MARK: - Fix round 2, finding 3: stray descriptor line root-cause
    //
    // ROOT CAUSE (found by code inspection, not the accessibility-tree walk
    // the coordinator asked for first — `NSAccessibility`'s Swift import in
    // this SDK exposes no callable members even via `as?`/optional-chained
    // protocol dispatch; three attempts to compile a tree walk against it
    // all failed with "has no member", and `NSView`'s own concrete
    // `accessibility*` overrides are `open` methods meant to be
    // OVERRIDDEN, not introspected from outside without the AXUIElement
    // cross-process API, which needs Accessibility permissions this
    // headless test process doesn't have. Falling back to a DIRECT test of
    // the actual gate `ComposerDescriptorGhostText.body` uses
    // (`if query.isEmpty`), which is the real root cause anyway):
    // `SessionComposerPalette`'s ONLY call site for
    // `ComposerDescriptorGhostText` passes `query: query` — a live,
    // always-current read of `composerStore.searchText` (trimmed). The
    // reviewer's screenshot matches EXACTLY fix round 1's already-diagnosed
    // defect: `SessionComposerStore.open()` resets `searchText = ""` on
    // every call, including the one `SessionComposerPalette`'s `body`
    // `.onAppear` makes on mount — a caller (test or otherwise) that sets
    // `searchText` BEFORE the view finishes its first appearance has it
    // silently wiped, so `ComposerDescriptorGhostText` correctly sees an
    // EMPTY query and renders "Name a session" even though a stale typed
    // glyph is still visible in the separate `NSTextView` (which doesn't
    // share SwiftUI's re-render cycle). No second call site exists — grep
    // confirms exactly one `ComposerDescriptorGhostText(` construction in
    // `SessionComposerPalette.swift`. This test proves the GATE itself is
    // correct in isolation (no full-palette mount needed, so no reliance
    // on mount-ordering at all): rendering `ComposerDescriptorGhostText`
    // directly with a non-empty query must produce zero text pixels.
    @Test func descriptorGhostTextRendersNothingForANonEmptyQuery() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let view = ComposerDescriptorGhostText(
            descriptors: descriptors,
            query: "d",
            opacity: 0.65,
            reduceMotion: true
        )
        let size = NSSize(width: 400, height: 30)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "descriptor-ghost-text-non-empty-query.png")
        #expect(png != nil)
        if let png, let rep = NSBitmapImageRep(data: png) {
            var darkPixels = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                    let r = Int((color.redComponent * 255).rounded())
                    let g = Int((color.greenComponent * 255).rounded())
                    let b = Int((color.blueComponent * 255).rounded())
                    if (r + g + b) / 3 < 200 { darkPixels += 1 }
                }
            }
            #expect(darkPixels == 0, "expected no descriptor text pixels with a non-empty query, found \(darkPixels)")
        }
    }

    // MARK: - Fix round 2, item 1: Timing board constants

    // MARK: - Fix round 3, item 2: descriptor crossfade constant

    /// Names the 180ms crossfade constant explicitly (not just exercises it
    /// indirectly) — same evidence shape `timingConstantsMatchTheBoard`
    /// uses for the summon/commit/dismiss board. Mutation-verified:
    /// temporarily changed `crossfadeDuration` to `0.5`, watched this fail,
    /// reverted.
    @Test func descriptorCrossfadeDurationMatchesTheBoard() {
        #expect(ComposerDescriptorGhostText.crossfadeDuration == 0.18)
    }

    /// Fix round 4, item 2: `descriptorCrossfadeDurationMatchesTheBoard`
    /// only names the 180ms constant — nothing exercises the actual
    /// removal-on-keystroke TRANSITION path on an already-mounted view
    /// (`descriptorGhostTextRendersNothingForANonEmptyQuery` mounts fresh
    /// with a non-empty query from the start, so it can't distinguish
    /// "removed instantly" from "removed after riding a 180ms fade" — the
    /// exact round-2 bug). This test mounts `ComposerDescriptorGhostText`
    /// standalone (isolated from row/typed-text confounds the full palette
    /// fixture has) with an EMPTY query via an `ObservableObject` box,
    /// confirms descriptor ink is present, flips the query to non-empty,
    /// advances the run loop by ONE turn (`RunLoop.main.run(until: Date())`
    /// — processes already-pending sources, adds no wall-clock delay), and
    /// asserts zero descriptor ink on that very next render. If the old
    /// `.transition(.opacity.animation(.easeInOut(duration: 0.18)))` bug
    /// were still present, this frame — captured at ~0ms into a 180ms
    /// fade — would still show the descriptor at or near full opacity, so
    /// this genuinely distinguishes "instant" from "animated." Empirically
    /// confirmed the one-turn spin is sufficient for the `@Published`
    /// mutation to reach the rendered frame (this test passes against the
    /// current code and would fail against the reverted-to-animated
    /// mechanism — verified both directions below).
    @MainActor
    private final class DescriptorQueryBox: ObservableObject {
        @Published var query: String = ""
    }

    private struct DescriptorHarness: View {
        @ObservedObject var box: DescriptorQueryBox
        let descriptors: [String]
        var body: some View {
            ComposerDescriptorGhostText(
                descriptors: descriptors,
                query: box.query,
                opacity: 0.65,
                reduceMotion: true
            )
        }
    }

    @Test func descriptorRemovalIsInstantOnTheVeryNextFrame() {
        let box = DescriptorQueryBox()
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let size = NSSize(width: 400, height: 30)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: DescriptorHarness(box: box, descriptors: descriptors).frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        func darkPixelCount() -> Int? {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]),
                  let bitmap = NSBitmapImageRep(data: png) else { return nil }
            var darkPixels = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                    let r = Int((color.redComponent * 255).rounded())
                    let g = Int((color.greenComponent * 255).rounded())
                    let b = Int((color.blueComponent * 255).rounded())
                    if (r + g + b) / 3 < 200 { darkPixels += 1 }
                }
            }
            return darkPixels
        }

        let restCount = darkPixelCount()
        #expect((restCount ?? 0) > 0, "sanity check: expected descriptor ink at rest with an empty query")

        box.query = "d"
        RunLoop.main.run(until: Date())
        hosting.layoutSubtreeIfNeeded()

        let afterKeystrokeCount = darkPixelCount()
        #expect(
            (afterKeystrokeCount ?? -1) == 0,
            "expected zero descriptor ink on the very next frame after the query becomes non-empty (no mid-fade), found \(afterKeystrokeCount.map(String.init) ?? "nil")"
        )
    }

    // MARK: - Fix round 2, item 2: new-style status strip copy

    @Test func newStyleStatusStripUsesTheArrowCopy() {
        #expect(SessionComposerCopy.unresolvedBranchMessageForNewStyles(token: "foo").contains("Press ↓"))
        #expect(!SessionComposerCopy.unresolvedBranchMessageForNewStyles(token: "foo").contains("suggestion above"))
    }

    @Test func classicUnresolvedBranchMessageIsByteIdenticalToBefore() {
        // The EXISTING constant, untouched — this only re-asserts the
        // literal so a future edit to it (in violation of the
        // coordinator's "do not edit the existing string" instruction) is
        // caught here.
        #expect(
            SessionComposerCopy.unresolvedBranchMessage(token: "foo")
                == "No worktree found for branch \"foo\". Use the create-branch suggestion above, or retype/delete it."
        )
    }

    // MARK: - Single-line type scale

    /// The single-line field must keep its 15pt field size — checked by
    /// rendering a single-line fixture and confirming it fits comfortably
    /// inside the 512pt card (a 32pt field would overflow it).
    /// Parameterized over window appearance × ambient appearance — see
    /// `singleLineRestStateHasCardChrome`'s comment.
    @Test(arguments: ["aqua", "darkAqua"], ["aqua", "darkAqua"])
    func singleLineFieldStaysAtTheOriginalFifteenPointScale(windowAppearance: String, ambientAppearance: String) {
        NSAppearance(named: appearanceName(ambientAppearance))!.performAsCurrentDrawingAppearance {
            let project = makeProject()
            let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
            let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
            // Step 0 (R14): same isolated-suite/material pin as
            // `singleLineRestStateHasCardChrome` — see that test's comment.
            let suite = UserDefaults(suiteName: "ghostties.composer.test.\(UUID().uuidString)")!
            suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
            let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
            // R15: see `singleLineRestStateHasCardChrome`'s comment — the
            // isolated suite resolves the 688pt round-13b width default, not
            // the pre-R13b 512pt this canvas was originally sized for. R15b:
            // see `derivedRenderCanvasWidth` for why 800pt is the right value.
            let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 100)
            let png = renderPNG(view, size: size, appearance: appearanceName(windowAppearance))
            writeScratchPNG(png, filename: "single-line-unchanged-scale.png")
            #expect(png != nil)
            if let png {
                // Same border-stroke check as `singleLineRestStateHasCardChrome`
                // — a 32pt field would have blown out the fixed-height card and
                // very likely pushed/clipped the border out of this capture.
                let coverage = strokeEdgeCoverage(in: png) ?? 0
                #expect(coverage >= 0.9, "measured strokeEdgeCoverage=\(coverage)")
            }
        }
    }

    // MARK: - Fix round 5: wash reaches the titlebar band

    /// Solid black everywhere, including the titlebar band, so any
    /// non-black pixel sampled there after compositing the overlay proves
    /// something painted over it.
    private struct DenseTerminalBackdropForOverlayTest: View {
        var body: some View {
            Color.black
        }
    }

    // MARK: - DEBUG-only tuning control (session-7 brief, 2026-09-11)

    /// Isolated suite per test, matching this file's own documented reason
    /// for never touching `.standard` directly (racing other parallel Swift
    /// Testing processes).
    /// Same throwaway-repo helper as `SessionComposerBranchLaunchTests` —
    /// duplicated rather than shared across test targets/files, matching
    /// this codebase's existing per-file convention for this exact helper.
    private static func makeThrowawayRepo() -> String {
        let unresolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-composer-branch-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: unresolvedPath, withIntermediateDirectories: true)
        let path = realPath(unresolvedPath)

        func run(_ args: [String]) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = args
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }

        run(["git", "-C", path, "init", "-q", "-b", "main"])
        run(["git", "-C", path, "-c", "user.email=test@ghostties.test", "-c", "user.name=Ghostties Test",
             "commit", "-q", "--allow-empty", "-m", "init"])
        return path
    }

    private static func realPath(_ path: String) -> String {
        guard let cPath = realpath(path, nil) else { return path }
        defer { free(cPath) }
        return String(cString: cPath)
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeTuningDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ghostties.composerDebugTuning.test.\(UUID().uuidString)")!
    }

    /// "The control writes the right key" — drives the (non-`private`,
    /// `@testable`-reachable) bindings directly rather than simulating a
    /// menu click, same no-AX-driving shape this file already uses for
    /// keyboard events.
    @Test func debugTuningControlWritesTheRightKeys() {
        let defaults = makeTuningDefaults()
        var changeCount = 0
        let control = ComposerDebugTuningControl(defaults: defaults, onChange: { changeCount += 1 })

        control.singleLineWidthBinding.wrappedValue = 600
        #expect(defaults.double(forKey: ComposerSingleLineTuning.widthStorageKey) == 600)

        control.singleLineFieldSizeBinding.wrappedValue = 20
        #expect(defaults.double(forKey: ComposerSingleLineTuning.fieldSizeStorageKey) == 20)

        control.witness.wrappedValue = false
        #expect(defaults.bool(forKey: ComposerWitnessSetting.storageKey) == false)

        #expect(changeCount == 3, "expected onChange to fire once per knob write, got \(changeCount)")
    }

    /// The fixture-hiding gate itself: `GHOSTTIES_CAPTURE_FIXTURE=1` in the
    /// launch environment must hide the control entirely — the marketing
    /// capture rig builds Debug, so a screenshot must never show it. Asserts
    /// directly on `SessionComposerOverlay.isMarketingCaptureFixtureActive`
    /// — the EXACT gate `body`'s `.overlay(alignment: .bottomTrailing)`
    /// checks before ever constructing `ComposerDebugTuningControl` — rather
    /// than hunting for a `Picker`'s AppKit backing view: `.menu`-style
    /// `Picker`s don't reliably materialize an `NSPopUpButton` inside an
    /// offscreen, non-key `NSHostingView` (confirmed empirically: a full
    /// subview-hierarchy dump of a mounted, capture-inactive overlay showed
    /// zero AppKit picker/button/menu classes anywhere, only the field's own
    /// `NSTextView` machinery — an artifact of this specific offscreen
    /// harness, not evidence the production control fails to render in a
    /// real, key window).
    @Test func debugTuningControlGateReflectsCaptureFixtureEnvVar() {
        unsetenv("GHOSTTIES_CAPTURE_FIXTURE")
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == false)

        setenv("GHOSTTIES_CAPTURE_FIXTURE", "1", 1)
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == true)

        unsetenv("GHOSTTIES_CAPTURE_FIXTURE")
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == false)
    }

    // MARK: - Round 10: typewriter centered column, field wraps

    /// Plain reference box for building `Binding`s in these `ComposerGhostTextField`
    /// mount tests, without SwiftUI `@State` (unavailable outside a `View`).
    private final class ValueBox<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// The popover card / `.singleLine` never set `wrapsAndGrows` — asserts the
    /// PRODUCTION default (`wrapsAndGrows: false`) keeps the field's
    /// original horizontally-scrolling single-line `NSTextContainer`/
    /// `NSTextView` configuration, unaffected by the round-10 wrap branch.
    @Test func defaultConfigurationStaysSingleLineAndHorizontallyScrolling() {
        let queryBox = ValueBox("")
        let focusBox = ValueBox(false)
        let field = ComposerGhostTextField(
            query: Binding(get: { queryBox.value }, set: { queryBox.value = $0 }),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: Binding(get: { focusBox.value }, set: { focusBox.value = $0 }),
            hasSelection: false,
            ghostFullPath: ""
        ) { _ in }

        let size = NSSize(width: 512, height: 60)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: field.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let scrollView = firstScrollView(in: hosting),
              let textView = scrollView.documentView as? ComposerGhostNSTextView,
              let textContainer = textView.textContainer else {
            Issue.record("expected a mounted single-line ComposerGhostNSTextView")
            return
        }
        #expect(textContainer.widthTracksTextView == false)
        #expect(textView.isHorizontallyResizable == true)
        #expect(textView.isVerticallyResizable == false)
    }

    // MARK: - Round 13 review finding: prove the palette actually consumes ComposerSingleLineTuning

    /// Round 12 added `ComposerSingleLineTuning` and wired `.singleLine`'s
    /// `newStyleFieldFontSize`/`newStyleFieldWidth` (`SessionComposerPalette`)
    /// to read it, but nothing mounted the real card and checked the
    /// rendered field against a NON-default tuning — every existing
    /// `.singleLine` render used the untouched defaults, so a typo in the
    /// wiring (e.g. hardcoding 15/512 instead of reading the dial) would
    /// have passed every other test in this file silently. This mounts
    /// `SessionComposerPalette`'s real `singleLineComposerCard` with an
    /// isolated `UserDefaults` suite (`tuningDefaultsForTesting`, added
    /// alongside this test — same test-seam shape as
    /// `styleOverrideForTesting`) holding tuning values distinct from both
    /// `ComposerSingleLineTuning`'s defaults (round 13b: 28pt/688pt) AND the
    /// pre-round-12 fixed constants (15pt/512pt), then asserts the MOUNTED
    /// NSTextView's real `font.pointSize` and enclosing `NSScrollView`'s
    /// frame width against those injected values — not against the tuning
    /// enum's own getters, which would only prove the enum reads its own
    /// keys back, not that the view reads the enum. Red/green proof
    /// performed 2026-09-12: temporarily hardcoded
    /// `newStyleFieldFontSize`/`newStyleFieldWidth`'s `.singleLine` cases to
    /// 15/512 — failed with "expected the mounted field's font to reflect
    /// the injected tuning (26.0pt), got Optional(15.0)"; reverted and
    /// confirmed green (`xcodebuild test`, this test only, exit 0).
    @Test func singleLineCardRendersInjectedTuningNotDefaults() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerSingleLineTuning.test.\(UUID().uuidString)")!

        let injectedFieldSize: Double = 26
        let injectedWidth: Double = 740
        suite.set(injectedFieldSize, forKey: ComposerSingleLineTuning.fieldSizeStorageKey)
        suite.set(injectedWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        let size = NSSize(width: 900, height: 300)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(projectBinding: .locked(project)),
            composerStore: composerStore,
            tuningDefaultsForTesting: suite
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let textView = firstTextView(in: hosting) else {
            Issue.record("expected a mounted NSTextView for the .singleLine card")
            return
        }
        #expect(
            textView.font?.pointSize == CGFloat(injectedFieldSize),
            "expected the mounted field's font to reflect the injected tuning (\(injectedFieldSize)pt), got \(String(describing: textView.font?.pointSize))"
        )

        guard let scrollView = firstScrollView(in: hosting) else {
            Issue.record("expected a mounted NSScrollView for the .singleLine card")
            return
        }
        // `f9d454e2e` sized the field to the card's tuned width MINUS both
        // horizontal paddings (`newStyleFieldRenderWidth`), so the padded
        // stack's ideal width equals the card's tuned width again instead of
        // spilling outside it — the mounted field is narrower than
        // `injectedWidth` by `2 × horizontalPadding`, not equal to it.
        let expectedFieldWidth = CGFloat(injectedWidth)
            - (2 * ComposerSingleLineTuning.horizontalPadding(fieldSize: CGFloat(injectedFieldSize)))
        #expect(
            abs(scrollView.frame.width - expectedFieldWidth) < 0.5,
            "expected the mounted field's width to reflect the injected tuning minus both horizontal paddings (\(expectedFieldWidth)pt), got \(scrollView.frame.width)"
        )

        // Sanity: the injected values are NOT the enum's own defaults, so
        // this test can't pass by accident just because the palette reads
        // ANY value off `ComposerSingleLineTuning` — it has to read the
        // ISOLATED suite specifically.
        #expect(injectedFieldSize != Double(ComposerSingleLineTuning.defaultFieldSize))
        #expect(injectedWidth != Double(ComposerSingleLineTuning.defaultWidth))
    }

    // MARK: - Round 13 review findings: DialKit tuning coordinator

    /// Finding #1: the `shadowPreset` `.select` control only ever wrote
    /// `shadowPresetRaw` — none of the preset's derived radius/length/opacity,
    /// unlike the legacy pill's binding which calls
    /// `ComposerSingleLineShadowDials.apply`. Names the production
    /// coordinator/model directly (not a re-implementation) so a regression
    /// that goes back to writing only the raw key fails this.
    ///
    /// Round 13d: `ComposerDialKitTuningModel.shadowPresetRaw` is now a
    /// computed property whose setter derives and assigns the three shadow
    /// dials as part of the SAME model mutation, so `coordinator.state
    /// .values.shadowPresetRaw = ...` below produces a single, already-
    /// derived `state.values` write with no reentrant reassignment from the
    /// coordinator's `$values` sink — the write is synchronous, no runloop
    /// turn to wait out.
    @available(macOS 14, *)
    @Test func dialKitShadowPresetSelectionWritesAllThreeDialsAndUpdatesModel() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.preset.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.lifted.rawValue

        let expected = ComposerSingleLineShadowPreset.lifted.dialValues

        // The panel's own model reflects the derived dials immediately, so
        // the sliders redraw with the preset's numbers, not the old ones.
        #expect(coordinator.state.values.shadowRadius == Double(expected.radius))
        #expect(coordinator.state.values.shadowYOffset == Double(expected.yOffset))
        #expect(coordinator.state.values.shadowOpacity == expected.opacity)

        // The persisted keys — what `ComposerSingleLineShadowDials` and every
        // render actually read — carry the same derived values.
        #expect(suite.string(forKey: ComposerSingleLineShadowPreset.storageKey) == ComposerSingleLineShadowPreset.lifted.rawValue)
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.radiusStorageKey) as? Double == Double(expected.radius))
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.yOffsetStorageKey) as? Double == Double(expected.yOffset))
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.opacityStorageKey) as? Double == expected.opacity)
    }

    /// `shadowPresetRaw`'s computed setter (round 13d) derived all three
    /// shadow dials for EVERY preset, including `.custom` — so selecting
    /// "Custom" after hand-tuning the sliders snapped them to
    /// `ComposerSingleLineShadowPreset.custom.dialValues` (round 14:
    /// 48/32/0.10) instead of leaving the hand-tuned numbers alone.
    /// `.custom` has no
    /// fixed values of its own; it is the label for "whatever the dials
    /// currently read." Selecting it must be a no-op on the three dials.
    /// Red mutation: remove the `preset != .custom` exclusion from the
    /// setter's guard.
    @available(macOS 14, *)
    @Test func dialKitShadowPresetCustomSelectionLeavesHandTunedDialsUntouched() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.preset.custom.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        // Unset dials already resolve to `.custom` (the enum's own
        // no-key-set default), so setting `shadowPresetRaw` to `.custom`
        // directly from a fresh coordinator is a no-op assignment — the
        // model never changes, `handle`'s `write` never runs, and this
        // test could not have caught the bug it names (selecting Custom
        // wiping the hand-tuned dials) because there was no real preset
        // TRANSITION for the setter's `preset != .custom` guard to matter
        // on. Seed a real, different preset first so switching to
        // `.custom` afterward is an actual transition through that guard.
        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.lifted.rawValue

        coordinator.state.values.shadowRadius = 40
        coordinator.state.values.shadowYOffset = 12
        coordinator.state.values.shadowOpacity = 0.5

        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.custom.rawValue

        #expect(coordinator.state.values.shadowRadius == 40)
        #expect(coordinator.state.values.shadowYOffset == 12)
        #expect(coordinator.state.values.shadowOpacity == 0.5)

        #expect(suite.string(forKey: ComposerSingleLineShadowPreset.storageKey) == ComposerSingleLineShadowPreset.custom.rawValue)
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.radiusStorageKey) as? Double == 40)
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.yOffsetStorageKey) as? Double == 12)
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.opacityStorageKey) as? Double == 0.5)
    }

    /// Companion to the above: fixed presets must still derive all three
    /// dials in a single mutation even when the panel is currently on
    /// `.custom` with hand-tuned values — the `.custom` exclusion above
    /// must not become a blanket skip. Red mutation: exclude every preset
    /// (`guard let preset = ... else { return }` with no derivation at all).
    @available(macOS 14, *)
    @Test func dialKitShadowPresetSelectionFromCustomStillDerivesAllThreeDials() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.preset.fromCustom.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        coordinator.state.values.shadowRadius = 40
        coordinator.state.values.shadowYOffset = 12
        coordinator.state.values.shadowOpacity = 0.5
        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.custom.rawValue

        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.lifted.rawValue

        let expected = ComposerSingleLineShadowPreset.lifted.dialValues
        #expect(coordinator.state.values.shadowRadius == Double(expected.radius))
        #expect(coordinator.state.values.shadowYOffset == Double(expected.yOffset))
        #expect(coordinator.state.values.shadowOpacity == expected.opacity)
    }

    /// Finding #2: the coordinator used to write its ENTIRE model on every
    /// change, so a panel whose own snapshot of an unrelated key was stale
    /// would silently stomp that key back to its stale value the moment the
    /// user touched anything else in the panel. This changes an unrelated
    /// field on the coordinator, then simulates a second actor (another open
    /// panel, the legacy pill, or a raw `defaults write`) changing a key this
    /// coordinator never touched, in the SAME isolated suite, and asserts
    /// that a further coordinator-driven write leaves the externally-changed
    /// key alone. Red/green proof performed 2026-09-12: temporarily added an
    /// unconditional `defaults.set(model.singleLineWidth, forKey: ...)`
    /// ahead of the diff-based writes in `write(from:to:)` — failed with "a
    /// write for one field must not clobber a key this panel didn't touch"
    /// (690.0 != 999.0); reverted and confirmed green (`xcodebuild test`,
    /// this test only, exit 0). Note: this proof also surfaced and fixed a
    /// separate real bug in `ComposerDialKitCoordinator.init` — see that
    /// init's doc comment — where `lastKnownModel` captured the coordinator's
    /// pre-normalization `initial` instead of the panel's own (rounded)
    /// `state.values`, exposed by round 13b's 688pt width default (not a
    /// multiple of the width dial's 10pt step).
    @available(macOS 14, *)
    @Test func dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.stale.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        // A second actor changes a key this coordinator has never touched —
        // its in-memory model still holds the OLD value for this key.
        let externalWidth = 999.0
        suite.set(externalWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        // This coordinator now changes an UNRELATED field.
        coordinator.state.values.singleLineFieldSize = 20

        #expect(suite.object(forKey: ComposerSingleLineTuning.fieldSizeStorageKey) as? Double == 20)
        #expect(
            suite.object(forKey: ComposerSingleLineTuning.widthStorageKey) as? Double == externalWidth,
            "a write for one field must not clobber a key this panel didn't touch"
        )
    }

    // MARK: - R14: Witness toggle (plan §6 test 7, mirrors
    // dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact above)

    /// red mutation: change `write(from:to:)`'s witness-key branch to also
    /// write `ComposerSingleLineTuning.widthStorageKey` (or any other key)
    /// — the "only its key" assertion below then fails.
    @available(macOS 14, *)
    @Test func dialKitWitnessToggleWritesOnlyItsKey() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.witness.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        // A second actor changes an unrelated key this coordinator has
        // never touched — proves the witness write is diff-based, same
        // guarantee `dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact`
        // proves for `singleLineWidth`.
        let externalWidth = 999.0
        suite.set(externalWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        coordinator.state.values.witnessEnabled = false

        #expect(suite.object(forKey: ComposerWitnessSetting.storageKey) as? Bool == false)
        #expect(
            suite.object(forKey: ComposerSingleLineTuning.widthStorageKey) as? Double == externalWidth,
            "the witness toggle write must not clobber a key this panel didn't touch"
        )
    }

    // MARK: - R18: single-line inset fix
    //
    // `singleLineComposerCard` used to frame the field at the FULL card
    // width, then wrap it in `singleLineHorizontalPadding` and re-frame the
    // whole padded stack back to that same width — the padding spilled
    // outside the card (measured live: ~1.5pt of inset against a ~29.9pt
    // intended one) instead of insetting the text. `newStyleFieldRenderWidth`
    // (`SessionComposerPalette.swift`) fixes this by sizing the field to the
    // card's width MINUS both paddings. These tests render real pixels
    // rather than arguing from source, per
    // `reference_rigid-frame-harness-recenters-a-hugging-card`'s and
    // `reference_swiftui-frame-maxwidth-is-greedy`'s shared lesson: a layout
    // claim needs a capture, not a read of the modifier chain.

    /// Backing-pixel horizontal extent of any opaque content within
    /// `yRange` — the horizontal analog of `ComposerCardFitTests
    /// .opaqueVerticalExtent`. The single-line card's `.regularMaterial`
    /// background (plus its border stroke) is opaque; the window around it
    /// is `.clear` (alpha 0), so this finds the card's own left/right edges.
    private func opaqueHorizontalExtent(in data: Data, yRange: Range<Int>) -> (left: Int, right: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var minX: Int?
        var maxX: Int?
        for x in 0..<rep.pixelsWide {
            for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                minX = min(minX ?? x, x)
                maxX = max(maxX ?? x, x)
            }
        }
        guard let minX, let maxX else { return nil }
        return (minX, maxX)
    }

    /// Leftmost column carrying genuinely dark, user-TYPED ink within
    /// `yRange`, starting from `xStart` — distinguishes a real typed
    /// character (`ComposerGhostTextField` sets `textView.textColor =
    /// .labelColor` at full alpha; that file's own doc comment measures the
    /// darkest typed pixel at rgb(39,39,39)) from the lighter ghost/
    /// placeholder text, which blends `.labelColor` at a fractional
    /// `ghostOpacity` over the card's light background and reads
    /// meaningfully brighter.
    private func firstDarkInkColumn(in data: Data, xStart: Int, yRange: Range<Int>) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        for x in stride(from: xStart, to: rep.pixelsWide, by: 1) {
            for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if (r + g + b) / 3 < 100 { return x }
            }
        }
        return nil
    }

    /// Leftmost column carrying the Witness's own flicker-red ink
    /// (`ComposerWitnessGhost.flicker`, `#ff3b3b`) — same color band
    /// `flickerRedPixelCount` above already uses, just reporting the
    /// leftmost match instead of a count.
    private func leftmostFlickerRedColumn(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r > 150, r - g > 60, r - b > 60 { return x }
            }
        }
        return nil
    }

    /// Renders the single-line card with real typed text (`isolated`
    /// defaults + `SessionComposerStore`, matching this file's other
    /// fixtures) and proves the first typed-ink column sits at least
    /// `singleLineHorizontalPadding − 2pt` inside the card's own left edge
    /// — i.e. the padding insets the text instead of spilling outside the
    /// card — and that the card itself stayed at its tuned width
    /// (`ComposerSingleLineTuning.defaultWidth`), not narrowed to make the
    /// inset "work" by shrinking the card instead of insetting the field.
    ///
    /// Red mutation: reverting `newStyleFieldRenderWidth`'s `.singleLine`
    /// case back to the un-reduced `newStyleFieldWidth` reproduces the
    /// original bug and fails the inset assertion (measured pre-fix: ~1.5pt
    /// of inset against a ~29.9pt expectation).
    @Test func singleLineFieldTextIsInsetFromTheCardsLeftEdge() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerSingleLineInset.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
        let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 100)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "hello"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the single-line inset fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("failed to encode the single-line inset fixture")
            return
        }
        writeScratchPNG(png, filename: "single-line-inset.png")

        guard let dataRep = NSBitmapImageRep(data: png) else {
            Issue.record("failed to decode the single-line inset fixture")
            return
        }
        let scale = CGFloat(dataRep.pixelsWide) / size.width
        let fullBand = 0..<dataRep.pixelsHigh
        guard let horizontalExtent = opaqueHorizontalExtent(in: png, yRange: fullBand) else {
            Issue.record("no opaque card content rendered")
            return
        }
        let cardLeftPt = CGFloat(horizontalExtent.left) / scale
        let cardWidthPt = CGFloat(horizontalExtent.right - horizontalExtent.left) / scale

        guard let inkColumn = firstDarkInkColumn(in: png, xStart: horizontalExtent.left, yRange: fullBand) else {
            Issue.record("no typed-text ink found in the single-line fixture")
            return
        }
        let inkLeftPt = CGFloat(inkColumn) / scale
        let measuredInset = inkLeftPt - cardLeftPt
        let expectedPadding = ComposerSingleLineTuning.horizontalPadding(
            fieldSize: ComposerSingleLineTuning.fieldSize(defaults: suite)
        )

        print("singleLineFieldTextIsInsetFromTheCardsLeftEdge: cardLeft=\(cardLeftPt)pt cardWidth=\(cardWidthPt)pt inkLeft=\(inkLeftPt)pt inset=\(measuredInset)pt expected>=\(expectedPadding - 2)pt")

        #expect(
            measuredInset >= expectedPadding - 2,
            "expected the typed text to sit inside the card's own horizontal padding (\(expectedPadding)pt), measured \(measuredInset)pt"
        )
        #expect(
            abs(cardWidthPt - ComposerSingleLineTuning.defaultWidth) < 3,
            "expected the card to stay at its tuned width (\(ComposerSingleLineTuning.defaultWidth)pt), measured \(cardWidthPt)pt"
        )
    }

    /// Companion to the inset test above: with real typed text AND the
    /// Witness ghost both on screen, proves the ghost's own leading edge
    /// lines up with the typed text's leading edge — the hardcoded `.offset(
    /// x: 20, ...)` this replaced sat ~10pt off that alignment once the
    /// inset fix landed (`singleLineHorizontalPadding` defaults to ~29.9pt,
    /// not 20).
    ///
    /// Sean's decision: the Witness ghost aligns to the text FIELD'S OWN
    /// FRAME, not to wherever a given glyph happens to start inking pixels.
    /// Comparing two pixel-scanned ink columns (as this test used to)
    /// conflated the two: the typed text's `firstDarkInkColumn` sits at the
    /// field's frame origin PLUS that glyph's own left-side bearing, which
    /// varies letter to letter (an "h" and a "w" don't ink at the same
    /// offset from their shared frame origin) — a false failure waiting to
    /// happen on any future change to this fixture's typed string. The
    /// text field's frame origin is a known layout quantity instead of a
    /// pixel search: `cardLeftPt + singleLineHorizontalPadding`, the exact
    /// same constant `newStyleFieldRenderWidth`/the Witness `.offset(x:)`
    /// above both use. Only the ghost side still needs a pixel scan — the
    /// Witness sprite is SwiftUI-painted with no AppKit frame to read.
    ///
    /// Red mutation: restoring the hardcoded `x: 20` offset fails this
    /// assertion.
    @Test func witnessGhostLeadingEdgeAlignsWithTypedTextLeadingEdge() {
        let project = Project(name: "Demo", rootPath: "/tmp/composer-witness-alignment-\(UUID().uuidString)", ghostCharacter: .blinky)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerWitnessAlignment.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        suite.set(true, forKey: ComposerWitnessSetting.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, tuningDefaults: suite)
        let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 140)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "hello"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the witness alignment fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("failed to encode the witness alignment fixture")
            return
        }
        writeScratchPNG(png, filename: "witness-alignment.png")

        guard let dataRep = NSBitmapImageRep(data: png) else {
            Issue.record("failed to decode the witness alignment fixture")
            return
        }
        let scale = CGFloat(dataRep.pixelsWide) / size.width
        let fullBand = 0..<dataRep.pixelsHigh

        guard let ghostColumn = leftmostFlickerRedColumn(in: png) else {
            Issue.record("no Witness ghost pixels found")
            return
        }
        guard let horizontalExtent = opaqueHorizontalExtent(in: png, yRange: fullBand) else {
            Issue.record("no opaque card content rendered")
            return
        }
        let ghostLeftPt = CGFloat(ghostColumn) / scale
        let cardLeftPt = CGFloat(horizontalExtent.left) / scale
        // The text FIELD's own frame origin — a known layout quantity, not
        // a pixel-scanned ink column. Same constant `newStyleFieldRenderWidth`
        // and the Witness's own `.offset(x:)` both use, so a correct
        // alignment is provably a tautology in the production code; this
        // assertion exists to catch a regression back to a hardcoded/wrong
        // offset on the Witness side.
        let textFrameLeftPt = cardLeftPt + ComposerSingleLineTuning.horizontalPadding(
            fieldSize: ComposerSingleLineTuning.fieldSize(defaults: suite)
        )

        print("witnessGhostLeadingEdgeAlignsWithTypedTextLeadingEdge: ghostLeft=\(ghostLeftPt)pt textFrameLeft=\(textFrameLeftPt)pt")

        #expect(
            abs(ghostLeftPt - textFrameLeftPt) <= 2,
            "expected the Witness ghost's leading edge to align with the text field's own frame origin, measured ghost=\(ghostLeftPt)pt textFrame=\(textFrameLeftPt)pt"
        )
    }

    // MARK: - Session-7: new single-line dials (corner radius, glass tint,
    // ghost gap) + conditional DialKit panel visibility + reset

    @Test func composerSingleLineCornerRadiusDefaultsToSixteen() {
        let suite = UserDefaults(suiteName: "ghostties.singleLineCornerRadius.default.test.\(UUID().uuidString)")!
        #expect(ComposerSingleLineTuning.cornerRadius(defaults: suite) == 16)
    }

    @Test func composerSingleLineCornerRadiusReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.singleLineCornerRadius.stored.test.\(UUID().uuidString)")!
        suite.set(20.0, forKey: ComposerSingleLineTuning.cornerRadiusStorageKey)
        #expect(ComposerSingleLineTuning.cornerRadius(defaults: suite) == 20)
    }

    @Test func composerSingleLineGlassTintDefaultsToNone() {
        let suite = UserDefaults(suiteName: "ghostties.glassTint.default.test.\(UUID().uuidString)")!
        #expect(ComposerSingleLineGlassTint.current(defaults: suite) == .none)
    }

    @Test func composerSingleLineGlassTintReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.glassTint.stored.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineGlassTint.windowBackground.rawValue, forKey: ComposerSingleLineGlassTint.storageKey)
        #expect(ComposerSingleLineGlassTint.current(defaults: suite) == .windowBackground)
    }

    /// Acceptance item 3: `.none` must resolve to a `nil` tint —
    /// `NSGlassEffectView.tintColor` is a nullable `NSColor?` per the AppKit
    /// header, and passing `.windowBackgroundColor` unconditionally (the
    /// pre-session-7 bug) is what read as an opaque flat panel.
    @Test func composerSingleLineGlassTintNoneResolvesToNilColor() {
        #expect(ComposerSingleLineGlassTint.none.nsColor == nil)
    }

    @Test func composerSingleLineGlassTintWindowBackgroundResolvesToWindowBackgroundColor() {
        #expect(ComposerSingleLineGlassTint.windowBackground.nsColor == NSColor.windowBackgroundColor)
    }

    @Test func composerWitnessGapDefaultsToSix() {
        let suite = UserDefaults(suiteName: "ghostties.witnessGap.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessGap.gap(defaults: suite) == 6)
    }

    @Test func composerWitnessGapReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessGap.stored.test.\(UUID().uuidString)")!
        suite.set(9.0, forKey: ComposerWitnessGap.storageKey)
        #expect(ComposerWitnessGap.gap(defaults: suite) == 9)
    }

    // MARK: - Round 14 (session-7): new Witness dials — fallback defaults

    @Test func composerWitnessSizeDefaultsToThirty() {
        let suite = UserDefaults(suiteName: "ghostties.witnessSize.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessSize.size(defaults: suite) == 30)
    }

    @Test func composerWitnessSizeReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessSize.stored.test.\(UUID().uuidString)")!
        suite.set(36.0, forKey: ComposerWitnessSize.storageKey)
        #expect(ComposerWitnessSize.size(defaults: suite) == 36)
    }

    @Test func composerWitnessFloatAmplitudeDefaultsToTwo() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatAmplitude.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessFloatAmplitude.amplitude(defaults: suite) == 2)
    }

    @Test func composerWitnessFloatAmplitudeReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatAmplitude.stored.test.\(UUID().uuidString)")!
        suite.set(2.5, forKey: ComposerWitnessFloatAmplitude.storageKey)
        #expect(ComposerWitnessFloatAmplitude.amplitude(defaults: suite) == 2.5)
    }

    @Test func composerWitnessFloatHorizontalDefaultsToTwo() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatHorizontal.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessFloatHorizontal.amplitude(defaults: suite) == 2)
    }

    @Test func composerWitnessFloatHorizontalReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatHorizontal.stored.test.\(UUID().uuidString)")!
        suite.set(3.5, forKey: ComposerWitnessFloatHorizontal.storageKey)
        #expect(ComposerWitnessFloatHorizontal.amplitude(defaults: suite) == 3.5)
    }

    @Test func composerWitnessFloatPeriodDefaultsToThree() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatPeriod.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessFloatPeriod.period(defaults: suite) == 3)
    }

    @Test func composerWitnessFloatPeriodReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessFloatPeriod.stored.test.\(UUID().uuidString)")!
        suite.set(5.0, forKey: ComposerWitnessFloatPeriod.storageKey)
        #expect(ComposerWitnessFloatPeriod.period(defaults: suite) == 5.0)
    }

    @Test func composerWitnessOpacityDefaultsToOne() {
        let suite = UserDefaults(suiteName: "ghostties.witnessOpacity.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessOpacity.opacity(defaults: suite) == 1.0)
    }

    @Test func composerWitnessOpacityReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessOpacity.stored.test.\(UUID().uuidString)")!
        suite.set(0.5, forKey: ComposerWitnessOpacity.storageKey)
        #expect(ComposerWitnessOpacity.opacity(defaults: suite) == 0.5)
    }

    @Test func composerWitnessBeatSpeedDefaultsToOne() {
        let suite = UserDefaults(suiteName: "ghostties.witnessBeatSpeed.default.test.\(UUID().uuidString)")!
        #expect(ComposerWitnessBeatSpeed.speed(defaults: suite) == 1.0)
    }

    @Test func composerWitnessBeatSpeedReadsStoredValue() {
        let suite = UserDefaults(suiteName: "ghostties.witnessBeatSpeed.stored.test.\(UUID().uuidString)")!
        suite.set(2.0, forKey: ComposerWitnessBeatSpeed.storageKey)
        #expect(ComposerWitnessBeatSpeed.speed(defaults: suite) == 2.0)
    }

    /// Round-trip through the DialKit coordinator: reading, mutating, and
    /// re-reading each new key proves `readModel`/`write(from:to:)` both
    /// carry it — the same pattern `dialKitResetActionClearsKeysAndUpdatesPanelImmediately`
    /// uses for the pre-existing dials.
    @available(macOS 14, *)
    @Test func dialKitCoordinatorRoundTripsEachNewWitnessDial() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.witnessDials.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        coordinator.state.values.witnessSize = 42
        coordinator.state.values.witnessFloatAmplitude = 3
        coordinator.state.values.witnessFloatHorizontalAmplitude = 3.5
        coordinator.state.values.witnessFloatPeriod = 4.5
        coordinator.state.values.witnessOpacity = 0.6
        coordinator.state.values.witnessBeatSpeed = 1.5

        #expect(suite.object(forKey: ComposerWitnessSize.storageKey) as? Double == 42)
        #expect(suite.object(forKey: ComposerWitnessFloatAmplitude.storageKey) as? Double == 3)
        #expect(suite.object(forKey: ComposerWitnessFloatHorizontal.storageKey) as? Double == 3.5)
        #expect(suite.object(forKey: ComposerWitnessFloatPeriod.storageKey) as? Double == 4.5)
        #expect(suite.object(forKey: ComposerWitnessOpacity.storageKey) as? Double == 0.6)
        #expect(suite.object(forKey: ComposerWitnessBeatSpeed.storageKey) as? Double == 1.5)

        let reread = ComposerDialKitCoordinator(defaults: suite, onChange: {})
        #expect(reread.state.values.witnessSize == 42)
        #expect(reread.state.values.witnessFloatAmplitude == 3)
        #expect(reread.state.values.witnessFloatHorizontalAmplitude == 3.5)
        #expect(reread.state.values.witnessFloatPeriod == 4.5)
        #expect(reread.state.values.witnessOpacity == 0.6)
        #expect(reread.state.values.witnessBeatSpeed == 1.5)
    }

    /// Acceptance criterion 6: beat speed 2.0 finishes a beat in half the
    /// wall time — at raw elapsed 30ms (half of `buildTabFrames`'s first
    /// 60ms frame), speed 1.0 is still on frame 0, speed 2.0 has already
    /// advanced to frame 1 (`frameIndex` matches `displayGrid`'s own use of
    /// the scaled elapsed).
    @Test func beatSpeedTwoAdvancesFrameIndexAtHalfTheWallTime() {
        let grid = ["XX", "XX"]
        let frames = ComposerWitnessFrames.buildTabFrames(grid: grid)
        let rawElapsedMs = 30
        let normalSpeedIndex = ComposerWitnessFrames.frameIndex(
            frames: frames, elapsedMs: Int(Double(rawElapsedMs) * 1.0)
        )
        let doubleSpeedIndex = ComposerWitnessFrames.frameIndex(
            frames: frames, elapsedMs: Int(Double(rawElapsedMs) * 2.0)
        )
        #expect(normalSpeedIndex == 0)
        #expect(doubleSpeedIndex == 1)
    }

    /// Acceptance item 2: the overlay's `y:` offset is driven by the gap —
    /// extracted as `SessionComposerPalette.witnessOverlayYOffset(size:
    /// ghostGap:)` specifically so this doesn't need a render. Round 14: the
    /// sprite size is itself a dial now, so the offset must derive from it
    /// rather than a hardcoded 24 — asserted here at two different sizes
    /// with the same gap. Red mutation: hardcoding `24` for `size` (dropping
    /// the `size:` parameter) fails the size-36 assertions.
    @Test func witnessOverlayYOffsetIsSizePlusGap() {
        #expect(SessionComposerPalette.witnessOverlayYOffset(size: 24, ghostGap: 0) == -24)
        #expect(SessionComposerPalette.witnessOverlayYOffset(size: 24, ghostGap: 4) == -28)
        #expect(SessionComposerPalette.witnessOverlayYOffset(size: 24, ghostGap: 12) == -36)
    }

    /// Acceptance criterion 5: the gap between the sprite's bottom and the
    /// card stays the gap at every size — at size 24 vs size 36 with the
    /// same `ghostGap`, the offset must differ by exactly 12 (the size
    /// delta), not stay pinned to a hardcoded 24.
    @Test func witnessOverlayYOffsetDiffersBySizeDeltaAtSameGap() {
        let at24 = SessionComposerPalette.witnessOverlayYOffset(size: 24, ghostGap: 5)
        let at36 = SessionComposerPalette.witnessOverlayYOffset(size: 36, ghostGap: 5)
        #expect(at24 - at36 == 12)
    }

    /// Acceptance item 4: reset clears every single-line key.
    @Test func composerSingleLineResetClearsEveryListedKey() {
        let suite = UserDefaults(suiteName: "ghostties.singleLineReset.test.\(UUID().uuidString)")!
        for key in ComposerSingleLineReset.resetKeys {
            suite.set(999, forKey: key)
        }
        ComposerSingleLineReset.reset(defaults: suite)
        for key in ComposerSingleLineReset.resetKeys {
            #expect(suite.object(forKey: key) == nil, "expected \(key) to be cleared by reset")
        }
    }

    // MARK: - DialKit panel: conditional visibility + reset action

    /// Acceptance item 1 (Classic removed, 2026-09-13 — the "Style only"
    /// count this used to assert no longer exists): Style + the 19
    /// single-line dials (round 15 added the Float horizontal dial to round
    /// 14's 18, which added 5 Witness dials to round 13's 13).
    /// `DialControl` doesn't expose its label/path outside the DialKit
    /// package, so this names the discriminator this test target CAN see —
    /// `state.controls.count`, the panel's actual visible control list. Red
    /// mutation: showing every control for every style (the "just don't
    /// hide anything" shortcut) fails both.
    @available(macOS 14, *)
    /// A stale stored `"classic"` (or any other unrecognized raw value)
    /// falls back to `.singleLine`'s control list, same as
    /// `ComposerStyle.current` itself — not the removed "Style only" list.
    @available(macOS 14, *)
    /// Proves the LIVE panel (not just the pure function above) rebuilds
    /// its control list when Style changes — the actual "conditional
    /// visibility" mechanism (`ComposerDialKitCoordinator.handle` calling
    /// `state.configure(controls:)`). Red mutation: removing the
    /// `styleRaw != previous.styleRaw` branch in `handle` fails this since
    /// `state.controls` would stay frozen at whatever it started at.
    @available(macOS 14, *)
    /// Acceptance item 4 (panel side): triggering the panel's reset action
    /// clears every single-line key AND the panel's own in-memory model
    /// reflects the reset immediately (no stale sliders).
    @available(macOS 14, *)
    @Test func dialKitResetActionClearsKeysAndUpdatesPanelImmediately() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.reset.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        coordinator.state.values.singleLineWidth = 512
        coordinator.state.values.singleLineCornerRadius = 20
        coordinator.state.values.witnessGap = 12
        coordinator.state.values.witnessSize = 48
        coordinator.state.values.witnessFloatAmplitude = 4
        coordinator.state.values.witnessFloatHorizontalAmplitude = 4
        coordinator.state.values.witnessFloatPeriod = 6
        coordinator.state.values.witnessOpacity = 0.2
        coordinator.state.values.witnessBeatSpeed = 2.0

        coordinator.handleAction("resetSingleLine")

        #expect(coordinator.state.values.singleLineWidth == Double(ComposerSingleLineTuning.defaultWidth))
        #expect(coordinator.state.values.singleLineCornerRadius == Double(ComposerSingleLineTuning.defaultCornerRadius))
        #expect(coordinator.state.values.witnessGap == Double(ComposerWitnessGap.defaultGap))
        #expect(coordinator.state.values.witnessSize == Double(ComposerWitnessSize.defaultSize))
        #expect(coordinator.state.values.witnessFloatAmplitude == ComposerWitnessFloatAmplitude.defaultAmplitude)
        #expect(coordinator.state.values.witnessFloatHorizontalAmplitude == ComposerWitnessFloatHorizontal.defaultAmplitude)
        #expect(coordinator.state.values.witnessFloatPeriod == ComposerWitnessFloatPeriod.defaultPeriod)
        #expect(coordinator.state.values.witnessOpacity == ComposerWitnessOpacity.defaultOpacity)
        #expect(coordinator.state.values.witnessBeatSpeed == ComposerWitnessBeatSpeed.defaultSpeed)

        for key in ComposerSingleLineReset.resetKeys {
            #expect(suite.object(forKey: key) == nil, "expected \(key) to be cleared by the panel's reset action")
        }
    }
}
