# Session Name Sync — Cache Invalidation Load Measurement

**Status:** measured, not fixed. This is a measurement-only harness (task
scope excluded fixing the `didSet`). No production behavior was changed.

**Harness:** `macos/Tests/Workspace/SessionNameSyncCacheLoadTests.swift`
**Bug under measurement:** PR #54 (`0ad1e05d3`) syncs the Claude Code window
title into the sidebar session name via
`WorkspaceStore.syncSessionNameFromTitle`. That write path mutates
`sessions`, whose `didSet` clears `sessionGroupsCache` for **every**
project, not just the one whose session was renamed
(`WorkspaceStore.swift`, `sessions` property, ~line 32).

## Headline number

**Excess wall-clock cost attributable to the over-broad invalidation: ~181ms
over 50 minutes of simulated continuous 6-agent load — about 60
microseconds of extra CPU work per second of load, or ~50µs per title-sync
write.**

**Is it a real problem at 5–7 agents? No — not as a CPU/recompute cost.**
The store-wide clear does measurably more work than necessary (3x the
recompute count: 21,600 vs. 7,200 over the run), but `computeSessionGroups`
itself is cheap (a handful of sessions per project, O(n) filter+sort), so
even 3x too much of a cheap operation is still cheap in absolute terms.
This harness does NOT show a "third instance of the activity-invalidation
storm" in the sense of unbounded work — the earlier storm incidents
(`project_perf-activity-invalidation-storm.md`, SEA-214) were expensive
because of `objectWillChange`-driven **SwiftUI view-tree re-renders**
cascading across the sidebar, not because the underlying computation itself
was slow. This harness deliberately measures only the store's own
recompute cost, not the downstream render cost — see **Scope & limits**
below for why that matters and what it doesn't tell you.

## Method

### Fixture

6 projects (matching the "5–7 concurrent agents" cadence basis in the task
brief), sized 3–8 sessions each (8, 7, 6, 5, 4, 3 — 33 sessions total),
matching the observed shape of a handful of concurrently-worked projects
with several accumulated sessions each. One session per project (6 total)
is the "active agent" whose title gets synced on the real cadence.

### Cadence

The real-world cadence from the task brief: ~1 title write per session
every 5 seconds. The harness ticks every `5.0/6.0`s (≈0.833s) and, on each
tick, one of the 6 active sessions (round-robin) gets a fresh,
sanitizer-passing title via `syncSessionNameFromTitle` — the exact PR #54
write path. Round-robining 6 sessions at this tick rate means each
INDIVIDUAL session's title syncs exactly once every 5 simulated seconds,
and the AGGREGATE write rate across all 6 is 1.2 writes/sec — matching the
brief's "~1–1.4 store-wide invalidations/sec at 5–7 agents" estimate.

### Read pattern (redraw simulation)

After each write, the harness simulates a sidebar redraw by calling
`sessionGroups(forProject:)` for **every** project — the worst-realistic
case where all 6 projects are pinned/expanded simultaneously. This is a
documented assumption, not a measurement: if fewer projects are expanded at
once, both models' costs scale down proportionally with the number of
expanded projects actually read, and the excess (the store-wide vs.
per-project delta) scales down with them too, since it is driven by reads,
not by the write itself.

### Two models, same data

1. **Store-wide (real).** The real `WorkspaceStore`, the real
   `sessionGroupsCache`, exercised through the real write → read path.
2. **Per-project (counterfactual, MEASURED not derived).** A local shadow
   cache in the test file, keyed by project id and TTL'd identically to the
   real cache (2s — duplicated from `WorkspaceStore.cacheTTL`, which is
   private), but invalidated only for the ONE project whose session was
   just renamed. Cache misses call the store's own pure, exported
   `WorkspaceStore.computeSessionGroups` static function over the exact
   same live `store.sessions` / `store.globalIndicatorStates` data the real
   model saw at that tick. Because this reuses the real computation
   function over real data, this is a genuine measurement of the
   counterfactual, not an estimate multiplied out from a single-project
   cost (the task's fallback method for cases where per-project
   invalidation "is not trivially simulable" — it was trivially simulable
   here, so the fallback wasn't needed).

An important, expected wrinkle: because the cache TTL (2s) is shorter than
the per-session write interval (5s), the per-project counterfactual is NOT
zero-cost — every project's shadow entry also goes stale from **pure time
elapsing** roughly every ~2.5 ticks, independent of any write. This is
correct and intentional: the delta between the two models isolates exactly
the cost caused by the over-broad `didSet`, with the unavoidable
TTL-driven baseline churn (present in both models) subtracted out.

### Time compression

Ticks are driven by `WorkspaceStore._setTestClock` (a `#if DEBUG` test-only
hook that already existed in `WorkspaceStore.swift` before this task) with
NO real `Task.sleep` / wall-clock wait between ticks. The work performed
per tick — one sanitized title write plus a full 6-project redraw read
against both models — is byte-for-byte identical to what the real cadence
would run; only the *wait* between ticks was removed.

**Compression factor:** 3,000 simulated seconds (50 minutes of continuous
6-agent load) were represented in a real xcodebuild-measured test run of
**0.51 seconds** of wall-clock time — a compression factor of ≈5,880x. Of
that 0.51s, ~369ms was the actual instrumented work (`storeWideElapsed` +
`perProjectElapsed` below); the remainder is fixture setup and per-tick
Swift/XCTest overhead not part of the measured recompute cost.

## Raw numbers (one real run, unfiltered)

```
=== Session Name Sync Cache Load — Results ===
Simulated duration: 3000.0s over 3600 ticks (compressed — no real sleep between ticks)
Writes (title syncs): 3600
Store-wide model  — recomputes: 21600, elapsed: 275.41565895080566ms
Per-project model — recomputes: 7200, elapsed: 93.99950504302979ms
Excess recomputes attributable to store-wide invalidation: 14400
Excess wall-clock attributable to store-wide invalidation: 181.41615390777588ms
Excess recomputes per write: 4.0
Excess elapsed per write: 50.393376085493294µs
Excess elapsed per simulated second of load: 0.060472051302591964ms/s
===============================================
```

| Metric | Store-wide (real) | Per-project (counterfactual) | Excess (delta) |
|---|---|---|---|
| Recomputes over 3,600 writes | 21,600 | 7,200 | **14,400** (3.0x) |
| Wall-clock (compressed run) | 275.4ms | 94.0ms | **181.4ms** |
| Per write | 6.0 recomputes | 2.0 recomputes | 4.0 recomputes / **50.4µs** |
| Per simulated second of load | — | — | **0.060ms/s** (≈0.006% of one core) |

`21,600 = 3,600 ticks × 6 projects` — every read after every write
recomputes ALL 6 projects, because the store-wide clear invalidates the
entire `sessionGroupsCache` dictionary on every single write, and every
tick performs exactly one write. `7,200 = 3,600 × 2.0` — the per-project
model still recomputes ~2 of 6 projects per tick, almost entirely from the
2s TTL naturally expiring faster than the 5s per-project write interval
(not from write-triggered invalidation, which fires for only 1 of 6
projects per write).

## Full test suite (unfiltered)

```
xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties \
  -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -only-testing:GhosttyTests test-without-building
```

Exit code: 65 (non-zero — see below). `xcresulttool get test-results
summary` for the run:

```
totalTestCount: 627
passedTests: 625
failedTests: 1
skippedTests: 1
```

- **Failing test:** `UpdateViewModelTests.testNotFoundText()` — the ONE
  pre-existing failure the task brief called out on clean main. Confirmed
  no other test failed.
- **Skipped test:** `BenchmarkTests.example()` — pre-existing, unrelated to
  this change (a placeholder/example benchmark suite entry).
- Both new tests in this harness (`SessionNameSyncCacheLoadTests`) passed:
  `testSessionNameSyncCadence_StoreWideVsPerProjectInvalidation()` and
  `testSessionGroupsRedrawCost_AfterStoreWideInvalidation()`.
- `xcodebuild test` (not `test-without-building`) was also run standalone
  for `SessionNameSyncCacheLoadTests` alone and passed with exit code 0 —
  confirmed the app-hosted test target runs to completion locally, not just
  `build-for-testing`.

## Scope & limits — what this measurement does NOT tell you

- **This is a store-recompute-cost measurement, not a render-cost
  measurement.** The prior "storm" incidents in this repo
  (`project_perf-activity-invalidation-storm.md`, SEA-214 coordinator tick)
  were expensive because `objectWillChange` cascaded into full SwiftUI
  view-tree re-evaluation across the sidebar — a cost this harness
  deliberately does not model, because doing so would require driving real
  `WorkspaceSidebarView`/`ProjectDisclosureRow` SwiftUI bodies under test,
  which is a materially different (and much heavier) harness. If Sean wants
  that number, it needs a UI-level or `XCTMetric`-based measurement of an
  actual sidebar re-render, not this store-level harness.
- **`sectionedProjectsCache` is also cleared store-wide by the same
  `didSet`** (`invalidateSectionedProjectsCache()` runs alongside
  `sessionGroupsCache.removeAll()`). This harness does not instrument that
  cache — it targets `sessionGroupsCache` specifically because that's the
  cache the task brief named. `computeSectionedProjects` is O(projects +
  sessions) and already single-slot (not keyed per-project), so its
  store-wide clear is *inherent* to its design, not a bug — there was
  nothing narrower to compare it against.
- **All-projects-expanded is a worst-case assumption**, not a measurement
  of real usage. If fewer projects are typically pinned/expanded at once,
  the absolute costs (both models) and the excess scale down together.
- **Single machine, single run.** This is a sanity-scale measurement (~180ms
  of excess CPU work spread across 50 minutes of load), not a statistically
  rigorous multi-run benchmark — the number is small enough that run-to-run
  noise could move it by a factor of 2 without changing the conclusion.

## Production-code footprint

One `#if DEBUG`-gated, read-only counter was added to
`WorkspaceStore.swift` so the harness could distinguish a cache hit from a
miss without reaching into the (rightly) private `sessionGroupsCache`
dictionary — the same pattern already used by the existing `persistCallCount`
test hook in that file:

```swift
#if DEBUG
private(set) var _sessionGroupsRecomputeCount = 0
#endif
```

incremented on the existing cache-miss path inside `sessionGroups(forProject:)`.
Compiled out of release builds entirely; no other production code was
touched, and the `didSet` under test was NOT modified.

## What a fix would involve (not implemented — Sean's call)

The mechanical fix is straightforward: on the `sessions` `didSet`, instead
of `sessionGroupsCache.removeAll()`, diff the old and new `sessions` arrays
for which `projectId`s actually changed (added/removed/mutated session) and
remove only those entries from `sessionGroupsCache`. `syncSessionNameFromTitle`
already knows the exact session (and therefore project) being written —
the simplest version would let mutating methods report which project id(s)
they touched rather than relying purely on `didSet` diffing the whole
array. Given the measured cost here is small, this is a "worth doing for
correctness/design-cleanliness" fix, not an urgent perf fix — worth
weighing against the `didSet`-invalidation design's stated benefit (a
future mutation site can never forget to bust the cache) before touching
it.
