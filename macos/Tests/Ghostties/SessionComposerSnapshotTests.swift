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
}
