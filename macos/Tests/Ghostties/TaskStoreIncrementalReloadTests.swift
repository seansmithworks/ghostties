// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
// See .github/workflows/test-ghostties.yml — macos-app job is build-only due to
// XCTest host app hang in headless GH Actions runners.
import XCTest
@testable import Ghostty
import GhosttiesCore

/// Correctness check for the incremental `TaskStore.loadFromDisk()` reload path
/// added in PR 3 of the multi-agent perf fix
/// (`project_perf-activity-invalidation-storm` in agent memory).
///
/// The change is a pure performance optimization: on a debounced fs event,
/// `loadFromDisk()` now diffs per-file (mtime, size) signatures against the
/// last successful load and only re-reads + re-parses new/changed files,
/// instead of re-reading and re-parsing every `.md` fixture in the directory.
///
/// This test's job is to prove that optimization is behavior-invisible: after
/// mutating exactly one file out of several and reloading, the incrementally
/// updated store's published arrays must be byte-for-byte identical to what a
/// brand-new `TaskStore` doing a full from-scratch load of the same directory
/// produces.
@MainActor
final class TaskStoreIncrementalReloadTests: XCTestCase {

    // MARK: - Fixture helpers

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ghostties-incremental-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // The shared xctestplan sets GHOSTTIES_TASKS_DIR="" for the whole test
        // run (test isolation default — see TaskStore.resolveTasksDirectory).
        // Point it at our temp fixture directory for the duration of this test
        // so TaskStore resolves the same directory a real window would.
        setenv("GHOSTTIES_TASKS_DIR", tmp.path, 1)
    }

    override func tearDownWithError() throws {
        setenv("GHOSTTIES_TASKS_DIR", "", 1)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Write a minimal, parseable task fixture.
    @discardableResult
    private func writeFixture(
        id: String,
        title: String = "Test task",
        status: String = "backlog",
        created: String = "2026-04-25T10:00:00Z"
    ) throws -> URL {
        let markdown = """
        ---
        title: \(title)
        source: shell
        source-id: \(id)
        project: ghostties
        created: \(created)
        status: \(status)
        ---

        ## Goal

        Test goal for \(id).

        ## Notes

        ## Activity

        - \(created) — created for tests
        """
        let url = tmp.appendingPathComponent("\(id).md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Incremental reload matches full reload

    /// Writes 5 task fixtures, does an initial load (necessarily a full load —
    /// the cache starts empty), mutates exactly ONE file's status, then
    /// reloads incrementally. Asserts the result equals a brand-new
    /// `TaskStore` doing a from-scratch load of the same directory.
    func testIncrementalReload_afterSingleFileMutation_matchesFullReload() throws {
        for i in 0..<5 {
            try writeFixture(
                id: "incr-task-\(i)",
                status: i == 2 ? "running" : "backlog",
                created: "2026-04-2\(i)T10:00:00Z"
            )
        }

        // Initial load — cache is empty, so this is a full load under the hood.
        let store = TaskStore()
        XCTAssertEqual(store.tasks.count, 5, "All 5 fixtures should load on first pass")

        // Mutate exactly one file on disk (status flip), simulating an MCP
        // write from a single agent while others are untouched.
        try writeFixture(
            id: "incr-task-2",
            status: "done",
            created: "2026-04-22T10:00:00Z"
        )

        // Reload the existing store incrementally (this is what
        // TaskFileWatcher.onChange triggers on a debounced fs event).
        store.loadFromDisk()

        // A brand-new store has no cache at all, so its load of the same
        // directory is unavoidably a full from-scratch reload — the ground
        // truth this test compares against.
        let freshStore = TaskStore()

        XCTAssertEqual(
            store.tasks, freshStore.tasks,
            "Incrementally reloaded tasks must exactly match a full from-scratch reload"
        )
        XCTAssertEqual(store.needsYou, freshStore.needsYou)
        XCTAssertEqual(store.active, freshStore.active)
        XCTAssertEqual(store.inbox, freshStore.inbox)
        XCTAssertEqual(store.backlog, freshStore.backlog)
        XCTAssertEqual(store.review, freshStore.review)
        XCTAssertEqual(store.done, freshStore.done)
        XCTAssertEqual(store.externalInbox, freshStore.externalInbox)
        XCTAssertEqual(store.sortedExternalInbox, freshStore.sortedExternalInbox)

        // Sanity: the mutated task actually moved lanes, proving the
        // incremental path picked up the change rather than silently no-op'ing.
        XCTAssertTrue(store.done.contains { $0.id == "incr-task-2" },
                      "Mutated task must have migrated into the done lane")
        XCTAssertFalse(store.backlog.contains { $0.id == "incr-task-2" },
                       "Mutated task must no longer be in backlog")
    }

    /// Deleting one file out of several and reloading must drop only that
    /// task, leaving the rest untouched — verifies the "removed" branch of
    /// the diff logic, not just "changed".
    func testIncrementalReload_afterSingleFileDeletion_matchesFullReload() throws {
        for i in 0..<4 {
            try writeFixture(id: "del-task-\(i)", created: "2026-04-1\(i)T10:00:00Z")
        }

        let store = TaskStore()
        XCTAssertEqual(store.tasks.count, 4)

        try FileManager.default.removeItem(at: tmp.appendingPathComponent("del-task-1.md"))
        store.loadFromDisk()

        let freshStore = TaskStore()

        XCTAssertEqual(store.tasks, freshStore.tasks)
        XCTAssertEqual(store.tasks.count, 3)
        XCTAssertFalse(store.tasks.contains { $0.id == "del-task-1" })
    }

    /// Adding a new file (simulating another agent's `createTask`) alongside
    /// untouched existing files must incrementally pick up just the new one.
    func testIncrementalReload_afterNewFileAdded_matchesFullReload() throws {
        for i in 0..<3 {
            try writeFixture(id: "add-task-\(i)", created: "2026-04-0\(i+1)T10:00:00Z")
        }

        let store = TaskStore()
        XCTAssertEqual(store.tasks.count, 3)

        try writeFixture(id: "add-task-new", status: "needs-you", created: "2026-04-30T10:00:00Z")
        store.loadFromDisk()

        let freshStore = TaskStore()

        XCTAssertEqual(store.tasks, freshStore.tasks)
        XCTAssertEqual(store.tasks.count, 4)
        XCTAssertTrue(store.needsYou.contains { $0.id == "add-task-new" })
    }

    /// Regression coverage for the known (mtime, size) signature limitation:
    /// `status: backlog` and `status: running` are both 7 characters, so a
    /// status flip between exactly those two lanes rewrites the file at the
    /// SAME byte size. The 3 tests above all happen to test size-changing
    /// mutations, so none of them would catch a naive "skip if size matches"
    /// bug. This test proves the common case — a same-size rewrite with any
    /// real-world timing gap between writes — is still picked up, because
    /// the diff also keys on `contentModificationDate`, which a real second
    /// write always advances.
    func testIncrementalReload_afterSameSizeStatusFlip_matchesFullReload() throws {
        try writeFixture(id: "flip-task", status: "backlog", created: "2026-04-15T10:00:00Z")

        let store = TaskStore()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertTrue(store.backlog.contains { $0.id == "flip-task" })

        // Guarantee an observable mtime delta between the two writes even on
        // filesystems/machines with coarser mtime resolution than this
        // process's wall clock — the point of this test is the common case
        // (same-size transition with a real timing gap), not the sub-tick
        // race, which is inherently untestable deterministically and is
        // exactly Gap 1's documented, accepted limitation (see the comment
        // at the signature-comparison site in loadFromDisk()).
        Thread.sleep(forTimeInterval: 0.01)

        // Same 7-char length as "backlog" — file size on disk is unchanged.
        try writeFixture(id: "flip-task", status: "running", created: "2026-04-15T10:00:00Z")
        store.loadFromDisk()

        let freshStore = TaskStore()

        XCTAssertEqual(store.tasks, freshStore.tasks)
        XCTAssertEqual(store.active, freshStore.active)
        XCTAssertEqual(store.backlog, freshStore.backlog)

        // Sanity: the status flip must have actually been picked up rather
        // than silently skipped because the file size didn't change.
        XCTAssertTrue(store.active.contains { $0.id == "flip-task" },
                      "Same-size status flip must migrate the task into the active/running lane")
        XCTAssertFalse(store.backlog.contains { $0.id == "flip-task" },
                       "Same-size status flip must remove the task from backlog")
    }
}
