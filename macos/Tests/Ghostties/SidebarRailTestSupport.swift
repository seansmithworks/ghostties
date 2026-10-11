import SwiftUI
@testable import Ghostty

extension View {
    /// Renders this sidebar content as the rail does: one tree laid out at
    /// the expanded width, held at morph 1, clipped to `width`, with the
    /// rail `width` wide (`SidebarMorphFrame`). The content is the
    /// expanded list's: a row inside the list column's padding, or a whole
    /// column (`SidebarRailColumn`).
    @MainActor
    func asRail(width: CGFloat, expandedWidth: CGFloat = WorkspaceLayout.sidebarWidth) -> some View {
        let model = SidebarWidthModel(width: width, morph: 1, expandedWidth: expandedWidth)
        model.railWidth = width
        return SidebarMorphFrame(model: model, content: self)
            .environmentObject(model)
    }
}
