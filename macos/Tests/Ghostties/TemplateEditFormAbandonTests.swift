import Foundation
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

    /// Reproduces the exact production shape: `commitNewTemplate` calls
    /// `store.addTemplate` with a bare name and no command, THEN the edit
    /// sheet is abandoned. Simulates the sheet's `onDisappear` decision
    /// directly against a real `WorkspaceStore`, the same call
    /// `TemplateEditForm.body`'s `.onDisappear` makes.
    @Test func emptyTemplateGoneAfterAbandoningTheEditSheet() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])

        let created = store.addTemplate(AgentTemplate(name: "New Template", kind: .custom))
        #expect(store.templates.contains { $0.id == created.id })

        // The sheet is dismissed (Cancel/Esc/click-outside) without ever
        // calling `save()` — `didSave` stays false.
        if TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: true, didSave: false) {
            store.removeTemplate(id: created.id)
        }

        #expect(!store.templates.contains { $0.id == created.id })
        #expect(created.command == nil)
    }

    /// The counter-case: the same abandon path must never touch a template
    /// that was actually configured and saved.
    @Test func configuredTemplateSurvivesAbandoningAFollowUpEdit() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])

        let created = store.addTemplate(AgentTemplate(name: "Real Template", kind: .custom, command: "claude"))

        if TemplateEditForm.shouldDiscardOnDismiss(isNewlyCreated: false, didSave: false) {
            store.removeTemplate(id: created.id)
        }

        #expect(store.templates.contains { $0.id == created.id })
    }
}
