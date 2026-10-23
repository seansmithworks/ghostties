import SwiftUI

/// Who you can talk to: the chief of staff, then one general manager per
/// project, then the desks they run on. Workers stay behind their GM.
struct AgentsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let chief = store.agents.filter { $0.role == .chiefOfStaff }
        let managers = store.agents.filter { $0.role == .generalManager }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !chief.isEmpty {
                    SectionLabel("Chief of staff")
                    agentCard(chief)
                }
                if !managers.isEmpty {
                    SectionLabel("General managers")
                    agentCard(managers)
                }
                if !store.desks.isEmpty {
                    SectionLabel("Desks")
                    deskCard
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.chrome)
        .navigationTitle("Agents")
    }

    private func agentCard(_ agents: [Agent]) -> some View {
        VStack(spacing: 0) {
            ForEach(agents) { agent in
                NavigationLink(value: ConversationRoute(agentId: agent.id)) {
                    AgentRow(agent: agent, subtitle: agent.role == .generalManager ? managerSubtitle(agent) : nil)
                }
                .buttonStyle(RowButtonStyle())
                if agent.id != agents.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .card()
    }

    private var deskCard: some View {
        VStack(spacing: 0) {
            ForEach(store.desks) { desk in
                let online = desk.isOnline()
                HStack {
                    Text(desk.name).font(.ghostRowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(online ? "Online" : "Offline")
                        .font(.ghostRowSubtitle)
                        .foregroundStyle(online ? Theme.ink : Theme.inkSecondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
                if desk.id != store.desks.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .card()
    }

    /// "Running tests · 2 workers · 1 waiting"
    private func managerSubtitle(_ manager: Agent) -> String {
        let workers = store.agents.filter { $0.parentAgentId == manager.id && $0.role == .worker }
        let waiting = workers.filter(\.status.needsYou).count
        let project = store.projects.first { $0.id == manager.projectId }?.name
        let parts: [String?] = [
            manager.summary ?? project,
            workers.isEmpty ? nil : "\(workers.count) worker\(workers.count == 1 ? "" : "s")",
            waiting == 0 ? nil : "\(waiting) waiting",
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.ghostCaption)
            .tracking(0.4)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Pressed rows take the Mac app's `.row` ink step.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.rowFill : .clear)
    }
}
