import SwiftUI

@main
struct GhosttiesApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.run() }
        }
    }
}

/// Where a tap on an agent or an ask goes.
struct ConversationRoute: Hashable {
    var agentId: String
    var conversationId: String?
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            Tab("Needs you", systemImage: "tray") {
                NavigationStack { NeedsYouView().withConversationDestination() }
            }
            .badge(store.openAsks.count)

            Tab("Agents", systemImage: "person.2") {
                NavigationStack { AgentsView().withConversationDestination() }
            }
        }
        .tint(Theme.ink)
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } }),
            actions: { Button("OK") {} },
            message: { Text(store.lastError ?? "") }
        )
    }
}

extension View {
    func withConversationDestination() -> some View {
        navigationDestination(for: ConversationRoute.self) { route in
            ConversationView(route: route)
        }
    }
}
