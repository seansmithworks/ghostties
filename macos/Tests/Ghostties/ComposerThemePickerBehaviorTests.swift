import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The composer theme picker's wiring beyond the gate
/// (`ComposerThemePickerTests`): overlay teardown reverts a preview, the
/// project hijack guard covers the full word, C1 chips preview what Return
/// stores, and an empty grid hands ← / → back to the caret. Defaults are an
/// injected suite and the reload hook a recorder; nothing reaches the app.
@MainActor
struct ComposerThemePickerBehaviorTests {
    private final class Reloads {
        var calls: [GhosttiesThemePicks?] = []
    }

    private func makeModel(_ defaults: UserDefaults, _ reloads: Reloads) -> ComposerThemePickerModel {
        ComposerThemePickerModel(
            defaults: defaults,
            reload: { reloads.calls.append($0) },
            appearance: { .dark },
            appearanceState: { _ in .ghostties }
        )
    }

    private func suite() -> (String, UserDefaults, () -> Void) {
        let name = "ghostties.tests.themepicker.behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (name, defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: - 1. Overlay teardown

    /// The host tearing the overlay down (app resigned active, another
    /// window took the composer) reverts the preview itself, without
    /// waiting for SwiftUI's `.onDisappear`.
    @Test func overlayTeardownRevertsALivePreview() {
        let (name, defaults, cleanup) = suite()
        defer { cleanup() }
        let reloads = Reloads()
        let model = makeModel(defaults, reloads)
        let store = SessionComposerStore(isolatedForTesting: name, themePicker: model)

        model.sync(text: "theme ", projectNames: [])
        model.select(5)   // Gruvbox
        #expect(model.preview.isPreviewing)
        #expect(reloads.calls.last == .some(GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark")))

        store.closeForOverlayTeardown()

        #expect(reloads.calls.last == .some(nil), "teardown must reload the stored picks")
        #expect(!model.preview.isPreviewing)
        #expect(model.preview.previewing == nil)
        #expect(!model.isActive)
        #expect(GhosttiesThemePicks.stored(in: defaults).isEmpty)
    }

    @Test func overlayTeardownWithNoPreviewReloadsNothing() {
        let (name, defaults, cleanup) = suite()
        defer { cleanup() }
        let reloads = Reloads()
        let store = SessionComposerStore(isolatedForTesting: name, themePicker: makeModel(defaults, reloads))

        store.closeForOverlayTeardown()

        #expect(reloads.calls.isEmpty)
    }

    // MARK: - 2. Hijack guard

    @Test func theFullWordStaysAProjectsWhenItStartsAProjectName() {
        let projects = ["themes-app"]
        #expect(ComposerThemeCommand.parse("theme", projectNames: projects) == .none)
        #expect(ComposerThemeCommand.parse("theme ", projectNames: projects) == .none)
        #expect(ComposerThemeCommand.parse("theme dra", projectNames: projects) == .none)
        #expect(ComposerThemeCommand.parse("the", projectNames: projects) == .none)
        // The slash is the explicit command.
        #expect(ComposerThemeCommand.parse("/theme", projectNames: projects) == .theme(query: ""))
        #expect(ComposerThemeCommand.parse("/the", projectNames: projects) == .partial(completion: "me "))
    }

    // MARK: - 3. Chips preview what Return stores

    @Test func aChipPreviewsTheFamilyPairThatReturnStores() {
        let (_, defaults, cleanup) = suite()
        defer { cleanup() }
        ComposerThemePresentation.chips.save(to: defaults)
        let reloads = Reloads()
        let model = makeModel(defaults, reloads)

        model.sync(text: "theme gruv", projectNames: [])
        let gruvbox = GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark")
        #expect(model.preview.previewing == gruvbox)

        // The pointer over the chip previews the same pair.
        if let chip = model.chipResults.first { model.peekChip(chip) }
        #expect(model.preview.previewing == gruvbox)

        #expect(model.commit())
        #expect(GhosttiesThemePicks.stored(in: defaults) == gruvbox)
    }

    /// One chip per family: two chips that store the same pair would be two
    /// controls for one action.
    @Test func chipsAreOnePerFamilyCarryingTheMatchedTheme() {
        let (_, defaults, cleanup) = suite()
        defer { cleanup() }
        ComposerThemePresentation.chips.save(to: defaults)
        let model = makeModel(defaults, Reloads())

        model.sync(text: "theme gruv", projectNames: [])
        #expect(model.chipResults.map(\.family) == ["Gruvbox"])
        #expect(model.chipResults.first?.name == "Gruvbox Dark")   // dark appearance ranks its own side

        model.sync(text: "theme ", projectNames: [])
        let families = model.chipResults.map(\.family)
        #expect(families.count == ComposerThemePickerModel.chipLimit)
        #expect(Set(families).count == families.count)
    }

    // MARK: - 4. Arrow keys with an empty grid

    @Test func anEmptyGridLeavesHorizontalArrowsToTheCaret() {
        let (_, defaults, cleanup) = suite()
        defer { cleanup() }
        let model = makeModel(defaults, Reloads())

        model.sync(text: "theme gru", projectNames: [])
        #expect(model.claimsHorizontalArrows)

        model.sync(text: "theme zzz", projectNames: [])
        #expect(model.isGridShown)
        #expect(!model.claimsHorizontalArrows)
        #expect(!model.move(.left, columns: 3))
    }
}
