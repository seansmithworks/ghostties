import AppKit
import Combine
import GhosttiesCore
import SwiftUI

/// A project's tile face: the sidebar's group header and the rail (one view
/// tree). Built to be reused wherever else a project shows as a tile.
///
/// It draws the project's icon (`ProjectIconStore`, resolved off the main
/// thread; the body only does an in-memory lookup) when the project has one
/// and its `iconStyle` allows it, else the monogram (option D: r8, 10% tint)
/// at `textSize`.
///
/// Selected (the project holding the selected session): a monogram fills
/// with ink; an icon can't turn ink, so it gets an ink ring instead, 1.5pt
/// wide with a 1.5pt gap from the tile (project-icon-tile card 05).
struct ProjectTileView: View {
    /// Nil for the "Unknown" group, which has no project and so no icon.
    let projectId: UUID?
    /// Nil is `.auto`.
    var iconStyle: ProjectIconStyle? = nil
    let monogram: String
    let size: CGFloat
    let textSize: CGFloat
    var isEmpty: Bool = false
    var isSelectedProject: Bool = false
    /// DEBUG Redlines tag for the drawn (scaled) shape.
    var redlineID: String? = nil
    var iconStore: ProjectIconStore = .shared

    /// The selected icon tile's ring: its width and its gap from the tile.
    /// 1.5 + 1.5 = 3pt out, inside the card's 4pt inset with 1pt to spare;
    /// both are whole pixels (3px) at 2x.
    static let ringWidth: CGFloat = 1.5
    static let ringGap: CGFloat = 1.5

    /// Re-renders on every dial write; the fill reads "Selected tile fill".
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @ChromeScheme private var colorScheme
    /// The header's group: its ink follows the group's card (`SelectedRowMix`).
    @Environment(\.selectedRowMixGroup) private var mixGroup
    /// Bumped when the store reports a new image for this project, so the
    /// body re-reads it.
    @State private var iconRevision = 0

    /// The icon this tile draws, if any: a dictionary lookup, never a
    /// resolve. `.monogram` never draws one, even before the store has
    /// caught up with a style change.
    static func icon(projectId: UUID?, style: ProjectIconStyle?, store: ProjectIconStore) -> NSImage? {
        guard let projectId, style != .monogram else { return nil }
        return store.image(for: projectId)
    }

    var body: some View {
        let _ = iconRevision
        let icon = Self.icon(projectId: projectId, style: iconStyle, store: iconStore)
        SelectedRowMixGroupReader(id: mixGroup, fallback: isSelectedProject ? 1 : 0) { card in
            if let icon {
                iconFace(icon, ring: card * RailProjectColumn.selectedTileFill)
            } else {
                monogramFace(inkFill: card * RailProjectColumn.selectedTileFill)
            }
        }
        .onReceive(iconStore.changes.filter { [projectId] in $0 == projectId }) { _ in
            iconRevision &+= 1
        }
    }

    private var cornerRadius: CGFloat { RailProjectTile.cornerRadius }

    /// `inkFill`: ink laid over the tile tint, 0 unselected, the dial when
    /// selected. Past the midpoint the tile reads as ink, so its text flips
    /// to the chrome colour to stay legible.
    private func monogramFace(inkFill: Double) -> some View {
        let isFilled = inkFill > 0.5
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = SidebarColors.tileFill(colorScheme, isEmpty: isEmpty)
        // Tint fades out as ink fades in, so each end draws exactly one
        // fill: the plain tile at 0, solid ink at 1.
        return shape.fill(tint.opacity(1 - inkFill)).overlay(shape.fill(RailProjectTile.ink(colorScheme).opacity(inkFill)))
            .frame(width: size, height: size)
            .redlineFrame(redlineID)
            .overlay {
                Text(monogram)
                    .font(.system(size: textSize, weight: .bold))
                    .foregroundStyle(isEmpty ? SidebarColors.dimmedProject(colorScheme) : (isFilled ? RailProjectTile.badgeText(colorScheme) : RailProjectTile.ink(colorScheme)))
            }
            .frame(width: size, height: size)
    }

    /// The icon clipped to the tile's shape, and the selected ring round
    /// it at `ring` opacity, concentric with the tile.
    private func iconFace(_ icon: NSImage, ring: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let outset = Self.ringGap + Self.ringWidth
        return Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + outset, style: .continuous)
                    .strokeBorder(RailProjectTile.ink(colorScheme), lineWidth: Self.ringWidth)
                    .padding(-outset)
                    .opacity(ring)
            }
            .redlineFrame(redlineID)
            .accessibilityHidden(true)
    }
}

/// Keeps `ProjectIconStore` current for the projects on screen: a refresh
/// at launch (first appearance) and whenever a project is added or its root
/// or icon style changes. Each refresh runs on the store's utility queue,
/// never on a render path. Off in app-hosted tests, so a test never writes
/// icon caches for its fixture projects.
struct ProjectIconRefresh: ViewModifier {
    let projects: [Project]
    var iconStore: ProjectIconStore = .shared

    /// What a refresh depends on, per project.
    struct Key: Hashable {
        let id: UUID
        let rootPath: String
        let iconStyle: ProjectIconStyle?
    }

    @State private var refreshed: Set<Key> = []

    static func key(_ project: Project) -> Key {
        Key(id: project.id, rootPath: project.rootPath, iconStyle: project.iconStyle)
    }

    /// The projects to refresh: those whose key (id, root, style) is not
    /// among the keys already refreshed.
    static func stale(_ projects: [Project], refreshed: Set<Key>) -> [Project] {
        projects.filter { !refreshed.contains(key($0)) }
    }

    func body(content: Content) -> some View {
        let keys = Set(projects.map(Self.key))
        content
            .onAppear { refresh(keys) }
            .onChange(of: keys) { refresh($0) }
    }

    /// Refreshes only the projects whose key is new.
    private func refresh(_ keys: Set<Key>) {
        guard !QuietTestHost.isActive else { return }
        let stale = Self.stale(projects, refreshed: refreshed)
        refreshed = keys
        for project in stale {
            iconStore.refreshInBackground(project)
        }
    }
}
