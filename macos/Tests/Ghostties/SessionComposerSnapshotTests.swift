import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// The Step 2 snapshot harness (Composer UI 11 plan §3, evidence contract
/// §6): mounts `SessionComposerPalette` (`.centered`, isolated fixture
/// stores) in an offscreen `NSWindow` via `NSHostingView` and writes
/// `bitmapImageRepForCachingDisplay` PNGs to
/// `docs/plans/composer-ui-11/evidence/`. Layout evidence only — spacing,
/// type, presence/absence — NOT material/vibrancy fidelity; final visual
/// acceptance is Sean's hands-on pass (plan §6 caveat).
///
/// ALL fixture data is synthetic (fake project name/path, the app's own
/// built-in template set) — this is a public repo, no real session state is
/// ever captured (`feedback_public-repo-no-real-session-data`).
///
/// Uses `SessionComposerStore(isolatedForTesting:)` and
/// `SessionComposerPalette`'s `composerStore:` initializer parameter (added
/// alongside this harness) so nothing here touches the developer's real,
/// persisted UserDefaults — the `.shared` composer store singleton has no
/// other environment-object seam.
@MainActor
struct SessionComposerSnapshotTests {

    private func makeProject() -> Project {
        Project(name: "Demo Project", rootPath: "/tmp/composer-ui-11-snapshot-\(UUID().uuidString)")
    }

    private func evidenceDirectory() -> URL {
        // #filePath: .../macos/Tests/Ghostties/SessionComposerSnapshotTests.swift
        // Four `deletingLastPathComponent()` calls reach the repo root:
        // Ghostties -> Tests -> macos -> repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
            .appendingPathComponent("docs/plans/composer-ui-11/evidence", isDirectory: true)
    }

    /// Renders `content` inside an offscreen, appearance-forced `NSWindow`
    /// and returns a PNG capture. `orderFrontRegardless()` mirrors this
    /// file's existing `hitTestDisabledExcludesViewFromHitTesting` precedent
    /// (`SessionComposerPhase3ReviewTests`) — SwiftUI's dynamic `NSColor`
    /// resolution (`.windowBackgroundColor`, etc.) needs a real window in
    /// the window server to resolve against the forced `appearance`; a
    /// borderless, ordered-out-immediately-after window never takes key or
    /// steals focus from anything the user is doing (no synthetic input is
    /// ever sent — capture only, never driving, per this repo's hard rule).
    private func renderPNG<Content: View>(
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

        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Step 7 only: `ComposerGhostTextField`'s ghost-origin math
    /// (`firstRect(forCharacterRange:)`, A-F5) needs a window to convert
    /// screen coordinates, and its `NSTextView` subclass re-runs
    /// `applyStyles()` the moment `viewDidMoveToWindow()` fires (see that
    /// override's doc comment). Found empirically: in THIS offscreen,
    /// single-shot capture harness, that first `viewDidMoveToWindow` call
    /// lands one layout pass before the text container has generated
    /// glyphs for the just-set `query` text, so the very first ghost
    /// position comes out wrong (measured: pinned to the field's left
    /// edge, overlapping the typed text, in a dedicated debug test written
    /// to chase this down). A second `layoutSubtreeIfNeeded()` pass closes
    /// the gap — confirmed against the same debug test. Every OTHER
    /// snapshot in this file renders pure SwiftUI content with no
    /// `NSViewRepresentable` in it, so this dependency is specific to
    /// Step 7 and this helper is kept separate from `renderPNG` rather
    /// than adding a second layout pass there for content that doesn't
    /// need it.
    private func renderPNGWithExtraLayoutPass<Content: View>(
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

    private func writeEvidence(_ data: Data?, filename: String) {
        guard let data else {
            Issue.record("Failed to render PNG for \(filename)")
            return
        }
        let dir = evidenceDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
        } catch {
            Issue.record("Failed to write \(filename): \(error)")
        }
    }

    /// Builds an isolated composer, pre-seeded with one pin and one recent
    /// selection distinct from the pin (so the lane-state PNG shows both a
    /// `.pinned` and a `.recent` row) — `dispatchOverrideForTesting` keeps
    /// `precommit` (used only to exercise the real `recordRecent` write
    /// path) from touching `WorkspaceStore.shared`/a real coordinator.
    private func makeLaneStateComposer(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.dispatchOverrideForTesting = { _, _ in }

        let templates = workspaceStore.templates
        guard templates.count >= 2 else { return composerStore }
        let pinned = templates[0]
        let recent = templates[1]

        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        _ = composerStore.precommit(template: recent, coordinator: SessionCoordinator(), workspaceStore: workspaceStore)

        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        composerStore.togglePin(templateId: pinned.id)

        // Leave it open, ready to mount — matches what `.onAppear` would do
        // on a fresh popover open.
        return composerStore
    }

    private func makePlainComposer(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        return composerStore
    }

    private func paletteView(project: Project, workspaceStore: WorkspaceStore, composerStore: SessionComposerStore) -> some View {
        SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
    }

    // MARK: - Lane state (pins + recents)

    @Test func laneStateWithPinsAndRecentsRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeLaneStateComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step2-lane-state-light.png")
        #expect(light != nil)

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step2-lane-state-dark.png")
        #expect(dark != nil)
    }

    // MARK: - Plain templates state (no pins, no recents)

    @Test func plainTemplatesStateRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step2-plain-templates-light.png")
        #expect(light != nil)

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step2-plain-templates-dark.png")
        #expect(dark != nil)
    }

    // MARK: - Step 3: rest-state ghost path (11.1)

    /// A fresh, empty-search composer against a resolvable, unlocked
    /// project — `onAppear`'s S5 seed selects the project's default
    /// template, so the ghost placeholder renders the FULL path (rule 1),
    /// comparable side-by-side with `V02Quieted22.dc.html`'s rest state
    /// (one grey, full path, no sub-ranges).
    ///
    /// LIMITATION: this repo's HEAD already has Step 5 (resolution-line
    /// deletion) landed, so this capture necessarily shows the
    /// post-Step-5 layout — there is no pre-deletion build left to render
    /// against. It still evidences Step 3's actual subject, the ghost
    /// path's rendering/opacity, which Step 5 doesn't touch; it just isn't
    /// a capture of "Step 3 layout in isolation" as the original plan
    /// framed it. Do not read the resolution line's absence here as new
    /// information about Step 3.
    @Test func step3RestStateGhostPathRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step3-rest-ghost-path-light.png")
        #expect(light != nil)

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step3-rest-ghost-path-dark.png")
        #expect(dark != nil)
    }

    // MARK: - Step 5: resolution line deleted, trailing controls shown

    /// An UNLOCKED project (`.open`, not `.locked`) so `projectControl`
    /// renders — `trailingControlVisibility`'s locked-hides-projectControl
    /// branch is covered structurally by `SessionComposerTrailingControlTests`,
    /// not a second screenshot. Proves the resolution line is gone (field +
    /// hairline + rows only) and the trailing controls are the field row's
    /// mouse route now.
    @Test func step5LineDeletedShowsTrailingControlsLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step5-line-deleted-light.png")
        #expect(light != nil)

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step5-line-deleted-dark.png")
        #expect(dark != nil)
    }

    // MARK: - Step 3: ghost placeholder opacity

    /// Pins `ComposerQueryField.ghostPlaceholderOpacity` — the production
    /// symbol the overlay `Text` actually renders with — to the `DESIGN.md`
    /// §4 target (`#1A1A1A7E`, 0x7E/0xFF ≈ 0.49). Guards against a
    /// regression back to the `prompt:` route's un-honoured
    /// `.foregroundColor`, which measured at ~0.83 (`step3-rest-ghost-path-
    /// light.png`'s darkest pixel, `rgb(64,64,64)` against a white ground).
    @Test func ghostPlaceholderOpacityMatchesDesignSpec() {
        #expect(ComposerQueryField.ghostPlaceholderOpacity == 0.49)
    }

    // MARK: - Step 4: zero-project empty state

    /// Zero projects anywhere (`WorkspaceStore(testingProjects: [], ...)`)
    /// — the ghost placeholder falls to "Add a project to begin" (Step 3
    /// rule 3) and the results area renders the "Add project…" row instead
    /// of a dead-end "No matches" (G-F7).
    @Test func step4ZeroProjectEmptyStateRendersLightAndDark() {
        let workspaceStore = WorkspaceStore(testingProjects: [], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step4-zero-project-light.png")
        #expect(light != nil)

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step4-zero-project-dark.png")
        #expect(dark != nil)
    }

    // MARK: - Step 7: model B ghost field (UNVERIFIED-INTERACTION)

    /// Scans a PNG for its darkest non-black pixel (excludes true black,
    /// which this card never intentionally paints, to avoid a stray
    /// 1px seam/border pixel winning over the actual ghost glyph fill).
    /// Same technique this repo used to catch the `prompt:` route's
    /// un-honoured opacity (`ghostPlaceholderOpacityMatchesDesignSpec`'s
    /// doc comment, `rgb(64,64,64)` measured that way).
    /// The typed text (`"Gho"`, `#1A1A1A` at full opacity) is DARKER than
    /// the ghost (49% alpha), so a plain "darkest pixel in the whole image"
    /// scan always finds the typed text, not the ghost — verified against
    /// this exact PNG (measured column extents: `"Gho"`'s solid fill spans
    /// roughly x:2–54, the ghost's spans roughly x:52–132, at 2x backing
    /// scale; LIGHT mode only — this per-channel "near-black" heuristic
    /// does not hold in dark mode, where typed text is near-WHITE, not
    /// near-black). This isolates the ghost's region instead: finds the
    /// last column containing a per-channel near-black pixel (each
    /// component `< 60`) — the typed text's own solid fill — then scans
    /// strictly to the right of it for the darkest non-white pixel, which
    /// is the ghost's own solid fill.
    private func darkestGhostPixel(in data: Data) -> (r: Int, g: Int, b: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var lastTypedTextColumn = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r < 60, g < 60, b < 60 { lastTypedTextColumn = x }
            }
        }

        var darkest: (r: Int, g: Int, b: Int)?
        var darkestSum = Int.max
        for x in (lastTypedTextColumn + 3)..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                guard !(r == 255 && g == 255 && b == 255) else { continue }
                let sum = r + g + b
                if sum < darkestSum {
                    darkestSum = sum
                    darkest = (r, g, b)
                }
            }
        }
        return darkest
    }

    /// Step 7 (Composer UI 11 plan §5/§7, evidence contract §6): flag ON,
    /// `ComposerGhostTextField` rendered directly (not through
    /// `SessionComposerPalette` — the flag is default OFF there, and this
    /// evidence targets the field's OWN rendering, not the swap point,
    /// which `ComposerGhostTextFieldTests.flagDefaultsToOff…` already
    /// covers). `query` is `Gho`, `ghostFullPath` is the same shape D-B's
    /// model A source produces — the active-segment ghost should render
    /// `stties` in grey per `activeSegmentGhostTruncatesAtNextSeparator`.
    ///
    /// UNVERIFIED-INTERACTION: this proves the ghost RENDERS off-screen at
    /// construction time, in an app-hosted, non-key window — nothing about
    /// typing, scrolling, or focus (plan §7's manual key matrix, still
    /// entirely undriven).
    @Test func step7ModelBGhostFieldRendersLightAndDark() {
        let field = ComposerGhostTextField(
            query: .constant("Gho"),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: .constant(false),
            hasSelection: false,
            isPickerOpen: false,
            ghostFullPath: "Ghostties > Default > Orchestrator"
        ) { _ in }
        let view = field.background(Color(nsColor: .windowBackgroundColor))
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth, height: 38)

        let lightData = renderPNGWithExtraLayoutPass(view, appearance: .aqua, size: size)
        writeEvidence(lightData, filename: "step7-modelb-light.png")
        #expect(lightData != nil)

        let darkData = renderPNGWithExtraLayoutPass(view, appearance: .darkAqua, size: size)
        writeEvidence(darkData, filename: "step7-modelb-dark.png")
        #expect(darkData != nil)

        // Ghost pixel measurement (acceptance criterion 5): report, don't
        // hard-assert an exact RGB triple — AppKit font rendering/hinting
        // makes the exact darkest antialiased pixel environment-dependent,
        // and per the task brief, a MISSING ghost (A-F2 reproducing) must
        // be reported plainly, not hidden behind an assertion that only
        // checks "rendered something".
        if let lightData, let pixel = darkestGhostPixel(in: lightData) {
            print("step7-modelb-light.png darkest ghost-region pixel: rgb(\(pixel.r),\(pixel.g),\(pixel.b))")
        } else {
            print("step7-modelb-light.png: NO ghost pixel found (all-white to the right of the typed text) — possible A-F2 reproduction, see plan §7 acceptance criterion 5")
        }
    }
}
