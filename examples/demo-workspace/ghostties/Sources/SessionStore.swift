// SessionStore.swift
// Central @Published state for the workspace sidebar: projects, sessions,
// and per-session indicator status. Persists to disk on a debounced timer.

import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var sessions: [AgentSession] = []

    func persist() {
        // Debounced write to workspace.json — see PersistenceGotchas.md
    }
}
