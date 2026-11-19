import AppKit
import GhosttiesCore
import SwiftUI

/// The live strip above a visual pane's form (card 11, "Preview strip"): a
/// crop of the Ghostties window, the sidebar at left and the terminal at
/// right, drawn from the same values the real window reads, so it redraws
/// the moment a setting changes. A faithful simplified rendering: the real
/// tile face (`ProjectMonogramTileFace`), the real tile sizes
/// (`SidebarRowIcons.sidebarTiles`), the real second-line rule
/// (`SessionRowSecondLine`), the real chrome colours (`ChromeTheme`); the
/// rows themselves are lighter than the sidebar's.
struct SettingsPreviewStrip<Sidebar: View>: View {
    struct Palette {
        var chrome: Color
        var canvas: Color
        var text: Color
        var accents: [Color]
    }

    let palette: Palette
    @ViewBuilder let sidebar: () -> Sidebar

    static var height: CGFloat { 196 }
    static var sidebarWidth: CGFloat { 248 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                trafficLights
                    .padding(.leading, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                sidebar()
                Spacer(minLength: 0)
            }
            // A crop: rows past the strip's height are cut, never centred.
            .frame(width: Self.sidebarWidth, height: Self.height, alignment: .topLeading)
            .clipped()
            .background(palette.chrome)
            terminal
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the Ghostties window")
    }

    private var trafficLights: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(palette.text.opacity(0.25)).frame(width: 9, height: 9)
            }
        }
    }

    /// Lines of "output" as bars in the theme's own palette colours: what
    /// changes with a theme is colour, so no invented transcript.
    private var terminal: some View {
        let widths: [CGFloat] = [0.42, 0.7, 0.55, 0.3, 0.64, 0.48, 0.76, 0.36]
        return VStack(alignment: .leading, spacing: 9) {
            ForEach(widths.indices, id: \.self) { index in
                GeometryReader { geo in
                    Capsule()
                        .fill(index == 0 ? palette.text : palette.accents.isEmpty
                            ? palette.text.opacity(0.6)
                            : palette.accents[index % palette.accents.count].opacity(0.85))
                        .frame(width: geo.size.width * widths[index], height: 7)
                }
                .frame(height: 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }
}

extension SettingsPreviewStrip.Palette {
    /// The colours the workspace window draws now (`ChromeThemeStore`),
    /// falling back to the Ghostties pair for `scheme`.
    @MainActor
    static func current(_ scheme: ColorScheme) -> Self {
        let theme = ChromeThemeStore.shared.current ?? ChromeTheme.active(scheme)
        return Self(chrome: Color(theme.chrome), canvas: Color(theme.canvas), text: Color(theme.ink), accents: [])
    }

    /// One bundled theme's colours.
    static func theme(_ preview: ThemePreview) -> Self {
        Self(chrome: preview.chrome, canvas: preview.canvas, text: preview.text, accents: preview.accents)
    }
}

// MARK: - Sidebar rows

/// One project in the preview's sidebar: its tile and name, and the threads
/// drawn under it.
struct SettingsPreviewProject: Identifiable {
    struct Thread: Identifiable {
        let id: UUID
        let name: String
        let kind: SessionStatusGlyphKind
    }

    let id: UUID
    let name: String
    let monogram: String
    let icon: NSImage?
    let isSelected: Bool
    let threads: [Thread]

    /// The sidebar's first `limit` projects in its order, `selected` (or
    /// the first) expanded with up to three of its threads. Thread statuses
    /// are a fixed needs-you / working / done sample, so the Text setting
    /// always has a row it changes.
    @MainActor
    static func sample(
        model: ProjectsSettingsModel,
        selected: UUID? = nil,
        limit: Int = 3
    ) -> [SettingsPreviewProject] {
        let all = model.projects
        let monograms = ProjectMonogram.monograms(for: all.map(\.name))
        var shown = Array(zip(all, monograms).prefix(limit))
        if let selected, !shown.contains(where: { $0.0.id == selected }),
           let index = all.firstIndex(where: { $0.id == selected }) {
            shown = Array(shown.prefix(limit - 1)) + [(all[index], monograms[index])]
        }
        let expanded = selected ?? shown.first?.0.id
        let kinds: [SessionStatusGlyphKind] = [.needsInput, .working, .done]
        return shown.map { project, monogram in
            let threads = project.id == expanded
                ? zip(model.store.sessions(for: project.id).prefix(kinds.count), kinds).map {
                    Thread(id: $0.0.id, name: $0.0.name, kind: $0.1)
                }
                : []
            return SettingsPreviewProject(
                id: project.id,
                name: project.name,
                monogram: monogram,
                icon: model.icon(for: project),
                isSelected: project.id == selected,
                threads: threads
            )
        }
    }
}

/// The preview's sidebar: project headers with their tiles, threads under
/// the expanded one, at the Icons and Text settings given.
struct SettingsPreviewSidebar: View {
    let projects: [SettingsPreviewProject]
    let icons: SidebarRowIcons
    let text: SidebarRowText

    @ChromeScheme private var colorScheme

    var body: some View {
        let theme = ChromeThemeStore.shared.current ?? ChromeTheme.active(colorScheme)
        let tiles = icons.sidebarTiles()
        VStack(alignment: .leading, spacing: 2) {
            ForEach(projects) { project in
                header(project, tiles: tiles, theme: theme)
                ForEach(project.threads) { thread in
                    row(thread, tiles: tiles, theme: theme)
                }
            }
        }
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: icons)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: text)
    }

    private func header(_ project: SettingsPreviewProject, tiles: SidebarTileSizes, theme: ChromeTheme) -> some View {
        HStack(spacing: SidebarTileSizes.labelSpacing(tile: tiles.projectTile)) {
            if tiles.projectTile > 0 {
                ProjectMonogramTileFace(
                    monogram: project.monogram,
                    size: tiles.projectTile,
                    textSize: tiles.projectText,
                    isSelectedProject: project.isSelected,
                    icon: project.icon
                )
            }
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.ink))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: max(tiles.projectTile, 20) + 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(project.isSelected ? Color(theme.lifted(.container)) : .clear)
        )
    }

    private func row(_ thread: SettingsPreviewProject.Thread, tiles: SidebarTileSizes, theme: ChromeTheme) -> some View {
        let secondLine = SessionRowSecondLine.isShown(thread.kind, text: text)
        return HStack(spacing: SidebarTileSizes.labelSpacing(tile: tiles.projectTile)) {
            if tiles.projectTile > 0 {
                Color.clear.frame(width: tiles.projectTile, height: 1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(theme.ink))
                    .lineLimit(1)
                if secondLine {
                    Text(thread.kind.spokenStatus.prefix(1).uppercased() + thread.kind.spokenStatus.dropFirst())
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkSecondaryColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if tiles.threadIcon > 0, let symbol = thread.kind.symbol {
                Text(symbol)
                    .font(.system(size: tiles.threadIcon, weight: .semibold))
                    .foregroundStyle(theme.inkSecondaryColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

/// Appearance's sidebar: rows as bars in a theme's own ink, since a theme
/// changes colour, not content.
struct SettingsPreviewSidebarSketch: View {
    let ink: Color
    let inkSecondary: Color

    var body: some View {
        let rows: [(indent: Bool, width: CGFloat)] = [(false, 96), (true, 120), (true, 84), (false, 72), (false, 108)]
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(rows[index].indent ? .clear : inkSecondary.opacity(0.5))
                        .frame(width: 18, height: 18)
                    Capsule()
                        .fill(rows[index].indent ? inkSecondary : ink)
                        .frame(width: rows[index].width, height: 7)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }
}
