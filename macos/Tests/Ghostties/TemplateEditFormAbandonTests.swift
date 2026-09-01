import AppKit
import Foundation
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Coverage for the "junk New Template" bug: a template committed by
/// `SessionComposerPalette.commitNewTemplate()` is added to the store
/// BEFORE `TemplateEditForm` runs, so abandoning that form (Cancel, Esc, or
/// click-outside — all funnel through SwiftUI's `.onDisappear`, not just
/// the Cancel button) used to leave an empty, `command: nil` custom
/// template behind forever. Root cause: `docs/plans/session-creation-unified.html`
/// finding D4 (old `TemplatePickerView.addCustomTemplate()` hardcoded the
/// name; the naming-first rebuild fixed that half but never addressed the
/// "added before configured, never cleaned up if abandoned" half — three
/// such rows are still live in production `workspace.json`).
///
/// Names the real production symbols
/// (`TemplateEditForm.shouldDiscardOnDismiss`, `WorkspaceStore.removeTemplate`)
/// — not a re-declared local. Before the fix, `shouldDiscardOnDismiss` did
/// not exist and nothing ever called `removeTemplate` on an abandoned
/// fresh template, so this test's second half (`emptyTemplateGoneAfter...`)
/// FAILS on the pre-fix code: the template that should be gone is still in
/// `store.templates`.
@MainActor
struct TemplateEditFormAbandonTests {

    // MARK: - The pure decision

    @Test func discardsAFreshUnsavedTemplate() {
        #expect(TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: true, didSave: false))
    }

    @Test func keepsAFreshTemplateOnceSaved() {
        #expect(!TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: true, didSave: true))
    }

    @Test func neverDiscardsAnExistingTemplateBeingEdited() {
        // Cancelling an edit of an already-configured template (opened via
        // the context menu's "Edit" action, `isNewlyCreated == false`) must
        // never delete it, saved or not.
        #expect(!TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: false, didSave: false))
        #expect(!TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: false, didSave: true))
    }

    // MARK: - The end-to-end store effect

    /// Fix 3 (review, PR #155): the two tests this replaced
    /// (`emptyTemplateGoneAfterAbandoningTheEditSheet`,
    /// `configuredTemplateSurvivesAbandoningAFollowUpEdit`) never
    /// constructed a `TemplateEditForm` at all — each re-implemented its
    /// `.onDisappear` body inline against `shouldDiscardOnDismiss` and
    /// `store.removeTemplate` directly, so they stayed green even with the
    /// real `.onDisappear` wiring deleted from `TemplateEditForm.body`
    /// entirely (verified: deleting that block leaves this file's tests
    /// green before this rewrite). This one actually mounts the view —
    /// same offscreen `NSHostingView` technique as
    /// `SessionComposerSnapshotTests.renderPNG` — and tears the host down
    /// to fire the real SwiftUI `.onDisappear` lifecycle event, so a
    /// regression that deletes or breaks that wiring fails THIS test.
    ///
    /// Mutant-verified directly: deleting `TemplateEditForm.body`'s
    /// `.onDisappear` block makes this fail (`store.templates` still
    /// contains `created.id`); restoring it makes this pass again.
    @Test @MainActor func emptyTemplateGoneAfterMountingAndAbandoningTheRealEditSheet() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let created = store.addTemplate(AgentTemplate(name: "New Template", kind: .custom))
        #expect(store.templates.contains { $0.id == created.id })

        let view = TemplateEditForm(template: created, isNewlyCreated: true)
            .environmentObject(store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // Cancel/Esc/click-outside all funnel through `.onDisappear`
        // without ever hitting Save — detaching the hosting view from its
        // window (rather than calling `dismiss()`, which has no effect
        // outside a real presentation context) is what fires it here.
        window.contentView = nil
        window.orderOut(nil)

        #expect(!store.templates.contains { $0.id == created.id })
    }
}
