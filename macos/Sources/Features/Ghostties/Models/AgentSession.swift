import Foundation

/// Persistent metadata for a terminal session.
///
/// This is the Codable record stored in workspace.json. Runtime state (the actual
/// SurfaceView reference, live status) lives in SessionCoordinator and is NOT persisted.
///
/// On app restart, previously active sessions appear as "Exited" with a relaunch option.
struct AgentSession: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var templateId: UUID
    var projectId: UUID

    /// Explicit ordering within a project. Nil means this session predates
    /// drag-and-drop reorder and will be sorted alphabetically. This field is
    /// scoped PER-PROJECT ONLY (`WorkspaceStore.sessions(for:)`/`moveSession`
    /// number each project's sessions independently starting at 0) — never use
    /// it as a sort key for a flat, cross-project list. `RecentsListView`'s
    /// Sessions tab intentionally ignores it for exactly this reason: two
    /// projects both numbering from 0 would otherwise interleave (A1, B1, A2,
    /// B2, A3) instead of preserving each session's true creation order.
    var sortOrder: Int?

    /// The last moment this session produced output, was focused, or transitioned
    /// out of idle. Drives the session-level "Recent" bucket inside an expanded project.
    /// Nil means this session predates the timestamp system or has never been touched.
    var lastActiveAt: Date?

    /// The last moment this session actually produced terminal output — written
    /// ONLY by `SessionCoordinator.subscribeToOutput`'s sink, never by focus,
    /// selection, or keyboard cycling. Unlike `lastActiveAt` (which also
    /// advances on a plain "touch"), this is what the Sessions-row timestamp
    /// and the Archive sort mean by "last active": last did something, not
    /// last looked at. Nil means this session predates the field or has never
    /// produced output this launch — see `displayTimestamp` for the read-side
    /// fallback.
    var lastOutputAt: Date?

    /// True once the user has manually renamed this session via the sidebar
    /// context menu. A pinned name is locked — incoming agent title updates
    /// (see `SessionTitleSanitizer` / `SessionCoordinator`) stop overwriting it
    /// until the pin is explicitly cleared. Defaults to `false` so existing
    /// sessions keep syncing automatically.
    var isNamePinned: Bool

    /// The pixel-art ghost character displayed for this session in the Sessions list.
    /// Nil means this session predates the per-session ghost system (falls back to a
    /// hash-derived ghost or a plain colored indicator — never re-rolled on render).
    var ghostCharacter: GhostCharacter?

    init(
        id: UUID = UUID(),
        name: String,
        templateId: UUID,
        projectId: UUID,
        sortOrder: Int? = nil,
        lastActiveAt: Date? = nil,
        lastOutputAt: Date? = nil,
        isNamePinned: Bool = false,
        ghostCharacter: GhostCharacter? = nil
    ) {
        self.id = id
        self.name = name
        self.templateId = templateId
        self.projectId = projectId
        self.sortOrder = sortOrder
        self.lastActiveAt = lastActiveAt
        self.lastOutputAt = lastOutputAt
        self.isNamePinned = isNamePinned
        self.ghostCharacter = ghostCharacter
    }

    // Custom decoder so existing workspace.json files (without sortOrder/lastActiveAt/
    // lastOutputAt/isNamePinned/ghostCharacter) load without error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.templateId = try container.decode(UUID.self, forKey: .templateId)
        self.projectId = try container.decode(UUID.self, forKey: .projectId)
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        self.lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        // Absent on every workspace.json written before this field existed —
        // `displayTimestamp` below falls back to `lastActiveAt` per-session so
        // existing sessions keep their own distinct recency instead of all
        // collapsing to the same "just migrated" timestamp.
        self.lastOutputAt = try container.decodeIfPresent(Date.self, forKey: .lastOutputAt)
        self.isNamePinned = try container.decodeIfPresent(Bool.self, forKey: .isNamePinned) ?? false
        self.ghostCharacter = try container.decodeIfPresent(GhostCharacter.self, forKey: .ghostCharacter)
    }

    /// The timestamp Sessions rows and the Archive sort should display and
    /// sort by: "last did something" (real output), falling back to
    /// "last looked at" only for sessions that predate `lastOutputAt` or have
    /// never produced output this launch. Project bucketing does NOT use
    /// this — it reads `lastActiveAt` directly (see `WorkspaceStore.recordActivity`).
    var displayTimestamp: Date? {
        lastOutputAt ?? lastActiveAt
    }

    /// Stable ghost for this session — the assigned `ghostCharacter` if present,
    /// otherwise a byte-derived fallback so pre-existing sessions render
    /// sensibly without ever being re-rolled.
    ///
    /// This fallback should only ever be visible transiently, between decode
    /// and `WorkspaceStore`'s launch-time backfill (see
    /// `WorkspaceStore.backfillGhostCharactersAtLaunch()`), which assigns and
    /// persists a real `ghostCharacter` for every session that lacks one so
    /// the value is written once and stable forever after.
    var resolvedGhostCharacter: GhostCharacter {
        if let ghostCharacter { return ghostCharacter }
        return Self.deterministicFallbackGhost(for: id)
    }

    /// Deterministic fallback ghost derived from the UUID's raw bytes.
    ///
    /// Swift's `Hasher`/`UUID.hashValue` is randomly re-seeded every process
    /// launch — the SAME hardcoded UUID has been observed to hash to four
    /// different indices across four consecutive launches. Deriving from the
    /// UUID's own bytes instead (never `hashValue`) makes this stable across
    /// launches, processes, and machines.
    static func deterministicFallbackGhost(for id: UUID) -> GhostCharacter {
        let all = GhostCharacter.allCases
        var accumulator: UInt64 = 0
        withUnsafeBytes(of: id.uuid) { buffer in
            for byte in buffer {
                accumulator = accumulator &* 31 &+ UInt64(byte)
            }
        }
        let index = Int(accumulator % UInt64(all.count))
        return all[index]
    }
}

// MARK: - Runtime State

/// Live status of a running session. Not persisted.
enum SessionStatus: Equatable {
    /// Process is alive and running.
    case running
    /// Process exited naturally (process_alive was false when surface closed).
    case exited
    /// Command completed successfully (exit code 0).
    case completed
    /// Command failed with a non-zero exit code.
    case error(exitCode: Int16)
    /// Surface was closed while the process was still running (force-killed by user).
    case killed

    /// Whether the underlying process is still alive.
    var isAlive: Bool {
        switch self {
        case .running: return true
        case .exited, .completed, .error, .killed: return false
        }
    }
}

// MARK: - Indicator State

/// View-layer state combining lifecycle status + output activity + prompt state.
///
/// `SessionStatus` tracks *what happened* to the process. This enum tracks
/// *what the user should see* — it folds in output recency and shell prompt signals
/// so the ghost indicator can distinguish seven distinct visual states.
///
/// Conforms to `Comparable` so project headers can aggregate by priority.
/// States needing user attention (`needsAttention`, `waiting`) rank highest below `error`.
enum SessionIndicatorState: Comparable {
    case inactive       // exited/completed/killed — collapsed, outline ghost
    case idle           // at shell prompt, nothing to do
    case processing     // actively producing output
    case longRunning    // processing for 30+ min continuously
    case waiting        // silent, not at shell prompt (subprocess may be running)
    case needsAttention // agent blocked on user input (permission prompt, question)
    case error

    /// The priority for aggregation — higher value wins in project headers.
    private var priority: Int {
        switch self {
        case .inactive:       return 0
        case .idle:           return 1
        case .processing:     return 2
        case .longRunning:    return 3
        case .waiting:        return 4
        case .needsAttention: return 5
        case .error:          return 6
        }
    }

    static func < (lhs: SessionIndicatorState, rhs: SessionIndicatorState) -> Bool {
        lhs.priority < rhs.priority
    }
}
