import SwiftUI

/// One past (inactive or archived) session as the history browser lists it.
/// Built from the store by `HistoryEntry.entries(...)` (`SidebarHistory.swift`).
struct HistoryEntry: Identifiable, Equatable {
    let id: UUID
    let projectName: String
    let title: String
    let lastActiveAt: Date
    let isArchived: Bool
    let isPinned: Bool
}

/// The canvas history browser shown when the sidebar's History row is
/// selected (mock I3).
///
/// PLACEHOLDER: the real fzf-style browser is built on another branch with
/// this exact signature; that branch replaces this view's body. Plumbing
/// (entries, resume, pin, close) lives in `SidebarHistory.swift`, not here.
struct HistoryBrowserView: View {
    let entries: [HistoryEntry]
    let onResume: (UUID) -> Void
    let onTogglePin: (UUID) -> Void
    let onClose: () -> Void

    init(
        entries: [HistoryEntry],
        onResume: @escaping (UUID) -> Void,
        onTogglePin: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.entries = entries
        self.onResume = onResume
        self.onTogglePin = onTogglePin
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History · \(entries.count)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        HStack(spacing: 12) {
                            Text(entry.projectName).foregroundStyle(.secondary)
                            Text(entry.title)
                            Spacer()
                            Text(entry.isArchived ? "archived" : "inactive").foregroundStyle(.secondary)
                            Button(entry.isPinned ? "Unpin" : "Pin") { onTogglePin(entry.id) }
                            Button("Resume") { onResume(entry.id) }
                        }
                        .font(.system(size: 13, design: .monospaced))
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
