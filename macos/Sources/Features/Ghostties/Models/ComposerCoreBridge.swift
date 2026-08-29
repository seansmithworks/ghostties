import Foundation
import GhosttiesCore

/// Bridges the session-composer command grammar and its supporting models
/// into the app target from `GhosttiesCore`, where they moved so
/// `swift test` in `cli/` can run their tests in CI (app-hosted tests
/// cannot run there — see `.github/workflows/test-ghostties.yml`).
///
/// Mirrors `TaskModel.swift`'s `typealias TaskPriority = GhosttiesCore.TaskPriority`
/// pattern: every existing call site across the app and its tests keeps
/// using the bare type name unchanged.
typealias GhostCharacter = GhosttiesCore.GhostCharacter
typealias Project = GhosttiesCore.Project
typealias AgentTemplate = GhosttiesCore.AgentTemplate
typealias SessionComposerCommitError = GhosttiesCore.SessionComposerCommitError
typealias SessionComposerCommandParser = GhosttiesCore.SessionComposerCommandParser
typealias GitWorktreeEnumerator = GhosttiesCore.GitWorktreeEnumerator
