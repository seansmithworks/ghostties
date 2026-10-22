import SwiftUI

/// The Mac sidebar's Needs You zone: every open ask across agents, newest first.
struct NeedsYouView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(store.openAsks) { ask in
                    AskCard(
                        ask: ask,
                        agent: store.agent(ask.agentId),
                        onAnswer: { answer in Task { await store.answer(ask, with: answer) } },
                        onReply: { reply(to: ask) }
                    )
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            if store.openAsks.isEmpty {
                ContentUnavailableView {
                    VStack(spacing: Theme.Spacing.md) {
                        GhostView(character: "drift", size: 48, color: Theme.inkSecondary)
                        Text("Nothing needs you").font(.ghostRowTitle)
                    }
                } description: {
                    Text("When an agent asks a question or needs a permission, it shows up here.")
                }
                .foregroundStyle(Theme.ink)
            }
        }
        .background(Theme.chrome)
        .navigationTitle("Needs you")
        .navigationDestination(item: $replyRoute) { route in
            ConversationView(route: route)
        }
    }

    /// A free-text question opens the conversation it was asked in.
    private func reply(to ask: Ask) {
        guard let conversation = store.conversations.first(where: { $0.id == ask.conversationId }) else { return }
        replyRoute = ConversationRoute(agentId: conversation.agentId, conversationId: conversation.id)
    }

    @State private var replyRoute: ConversationRoute?
}
