import SwiftUI

/// Settings > Sidebar: the rows' Icons and Text (`SidebarRowIcons`,
/// `SidebarRowText`; the sidebar reads the same keys and follows live) and
/// the composer's theme results, under a preview strip that redraws as
/// they change.
struct SidebarSettingsPane: View {
    @ObservedObject var projects: ProjectsSettingsModel

    @AppStorage(SidebarRowIcons.key, store: AppDefaults.store)
    private var icons: SidebarRowIcons = .large
    @AppStorage(SidebarRowText.key, store: AppDefaults.store)
    private var text: SidebarRowText = .standard
    @AppStorage(ComposerThemePresentation.key, store: GhosttiesThemePicks.appDefaults)
    private var composerThemePresentation: ComposerThemePresentation = .grid

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var chrome = ChromeThemeStore.shared

    var body: some View {
        Form {
            Section {
                SettingsPreviewStrip(palette: .current(colorScheme)) {
                    SettingsPreviewSidebar(
                        projects: SettingsPreviewProject.sample(model: projects),
                        icons: icons,
                        text: text
                    )
                }
                .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Icons", selection: $icons) {
                    ForEach(SidebarRowIcons.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Text", selection: $text) {
                    ForEach(SidebarRowText.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Rows")
            } footer: {
                Text("Standard puts a second line under a thread only when it needs you or hit an error. Detailed puts it under every thread.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Composer") {
                Picker("Composer theme results", selection: $composerThemePresentation) {
                    Text("Grid").tag(ComposerThemePresentation.grid)
                    Text("Chips").tag(ComposerThemePresentation.chips)
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        #if DEBUG
        .onAppear(perform: applyCaptureIconsFlipIfNeeded)
        #endif
    }

    #if DEBUG
    /// `GHOSTTIES_CAPTURE_SETTINGS_ICONS`: what clicking the Icons control
    /// twice does, on a timer.
    private func applyCaptureIconsFlipIfNeeded() {
        guard let flip = CaptureFixture.settingsIconsFlip,
              CaptureFixture.claimHook("settingsIconsFlip") else { return }
        let before = icons
        icons = flip.from
        DispatchQueue.main.asyncAfter(deadline: .now() + flip.delay) {
            icons = flip.to
            DispatchQueue.main.asyncAfter(deadline: .now() + flip.delay) { icons = before }
        }
    }
    #endif
}
