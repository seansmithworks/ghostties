import SwiftUI

/// A conversation with a chief of staff or general manager. No terminal:
/// words and asks only. Opens the conversation in the route, else the agent's
/// latest; the first message to an agent with none starts one.
struct ConversationView: View {
    var route: ConversationRoute

    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private var agent: Agent? { store.agent(route.agentId) }
    private var conversationId: String? {
        route.conversationId ?? store.latestConversation(for: route.agentId)?.id
    }

    var body: some View {
        let thread = store.thread(agentId: route.agentId, conversationId: conversationId)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    if thread.isEmpty, let agent {
                        Text(agent.summary ?? "Start a conversation with \(agent.name).")
                            .font(.ghostRowSubtitle)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.top, Theme.Spacing.xxl)
                    }
                    ForEach(thread) { message in
                        row(for: message).id(message.clientId ?? message.id)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: thread.count) {
                if let last = thread.last {
                    withAnimation { proxy.scrollTo(last.clientId ?? last.id, anchor: .bottom) }
                }
            }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { title }
        }
        .task(id: conversationId) {
            if let conversationId { await store.loadMessages(conversationId) }
        }
    }

    @ViewBuilder
    private func row(for message: Message) -> some View {
        if message.kind == .ask, let askId = message.payload.askId,
           let ask = store.openAsks.first(where: { $0.id == askId }) {
            AskCard(ask: ask, agent: store.agent(ask.agentId)) { answer in
                Task { await store.answer(ask, with: answer) }
            }
        } else {
            MessageRow(message: message, pending: message.id == message.clientId)
        }
    }

    @ViewBuilder
    private var title: some View {
        if let agent {
            HStack(spacing: Theme.Spacing.sm) {
                GhostView(character: agent.ghostCharacter, size: 18)
                Text(agent.name).font(.ghostRowTitle).foregroundStyle(Theme.ink)
                StatusGlyph(status: agent.status, size: 13)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(agent.name), \(agent.status.label)")
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var composer: some View {
        let unavailable = agent?.status.isGone ?? true
        let canSend = !unavailable && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField(
                unavailable ? "\(agent?.name ?? "Agent") is offline" : "Message \(agent?.name ?? "")",
                text: $draft,
                axis: .vertical
            )
            .font(.ghostBody)
            .lineLimit(1...6)
            .focused($composerFocused)
            .disabled(unavailable)
            .padding(.vertical, Theme.Spacing.sm)
            .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Theme.canvas : Theme.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? Theme.ink : Theme.rowFill))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.leading, Theme.Spacing.lg)
        .padding(.trailing, Theme.Spacing.xs)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .frame(maxWidth: 720)
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, agent?.status.isGone == false else { return }
        draft = ""
        let agentId = route.agentId
        let conversationId = conversationId
        Task { await store.send(body, to: agentId, in: conversationId) }
    }
}
