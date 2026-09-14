# Session row status: implementation plan (draft)

Branch from `origin/main` @ `89e6dfb945e2d2a3622268adb6328555f574c8f5`. PR #138 is merged (it is that SHA's merge commit), so there is nothing to sequence around. This worktree's branch `docs/session-row-status-spec` is 60 behind / 3 ahead of that ref; every source citation below was read from the `origin/main` object store, not from the checkout.

## Three findings that hit the spec before any code

1. **The todo data source named in the spec is dead, and the live one is a different path with a different schema.** `~/.claude/todos/` holds 336 files, 5 non-empty, newest non-empty written 2026-02-02, and **zero files modified since 2026-08-20**. Of the 10 live sessionIds in `~/.claude/sessions/`, **0 have a file there**. The live store is `~/.claude/tasks/<sessionId>/<n>.json`, one JSON object per item, keys `activeForm, blockedBy, blocks, description, id, subject, status`. It has 251 directories, 27 written in 2026-08, newest 2026-08-15, and **0 of the 10 live sessionIds have a directory there either**. Decision 3's breakdown line renders on zero rows today under either path. `reference_claude-todo-data-source.md` documents only the dead path.
2. **The sessions file carries no prompt-shape signal, and its status vocabulary is two values.** All 10 live files share 17 to 18 keys (`bridgeSessionId, cwd, entrypoint, kind, messagingSocketPath, name, nameSince, nameSource, peerFeatures, peerProtocol, pid, pidDomain, procStart, sessionId, startedAt, status, statusUpdatedAt, updatedAt, version`). Observed `status` values: `idle` (5) and `busy` (5). Nothing distinguishes a permission prompt from a freeform question; nothing maps to `needsAttention`, `waiting`, `longRunning`, or `error`. Decision 5's inline Approve button has **no trigger in the source decision 1 chose**, and decision 1 as written collapses seven states to two.
3. **The spec's colours are not the shipped colours.** Shipped mapping, identical in two places (`RecentsRowView.swift:120-128`, `WorkspaceStore.swift:1060-1067`): `error` systemRed, `needsAttention` `WorkspaceLayout.statusNeedsDecisionGold` `#FFC400` (`WorkspaceLayout.swift:178`), `waiting` `statusYourTurnBlue` `#5B8DEF` (`:170`), `longRunning` `statusLongRunningOrange` `#F97316` (`:186`), `processing` systemGreen. `WorkspaceLayout.swift:155-158` states in a comment that `waitingTerracotta` "is NOT the session-status waiting color." The spec's mock paints blocked terracotta and processing blue, and decision 6 claims the mixed dot "reuses terracotta at two opacities, so it costs no new token." Terracotta is not in the status palette at all. The plan follows shipped code: **the blocked/attention colour is gold `#FFC400`**.

Two smaller corrections: the spec cites the colour map at `WorkspaceStore.swift:1004`, which on `origin/main` is 1060-1067. And the blue-ghost evidence behind decision 1 is stale, because the polarity fix already shipped. `SessionCoordinator.swift:1362-1371` returns `.idle` (not `.waiting`) for silent agent-kind sessions, with a comment saying absence of evidence must fall back to the low-salience state.

## Approach

The build is gated on a data join that does not exist and a data source that is empty. So the ordering is: prove the join, prove the payload, then draw. Phase 1 makes every session joinable and reads real status into both caches, changing no pixels. Phase 2 draws the status the join earns, and only that. Phase 3 adds the breakdown line against whichever task store is live at the time, behind an absent-not-disabled rule. Phase 4 adds the project aggregate. The inline Approve button (decision 5) is **not schedulable until a prompt-shape source exists**; Phase 5 specifies what would feed it and stops there rather than shipping a button that fires on a heuristic.

Every phase ships behind the abstain rule already settled in `decision_launcher-uuid-join-replaces-strategy-b.md`: a joined row gets the full vocabulary, a non-joined row gets only `.processing` and `.idle` and is never eligible for an attention colour.

## Phase 1: the join and the read (no visible change)

**1.1 Close the launchBanner gate.** `macos/Sources/Features/Ghostties/SessionCoordinator.swift:225` is `guard let banner = template.launchBanner else { return cmd }` inside the `finalCommand` closure (`:221-244`). Restructure so the wrapper is written whenever `resolvedCommand` is non-nil, emitting the banner line and the `spawnBannerEcho` only when `template.launchBanner` is non-nil. Script path and permissions stay as at `:227-241`.
- Acceptance: launch two sessions, one from an agent template and one from the shell template, then a listing of `~/.ghostties/cache/launchers/*.sh` returns 2 files. Today the directory holds 4 scripts against 10 live Claude sessions.
- New test `SessionCoordinatorLauncherScriptTests.testShellTemplateStillWritesLauncherScript` in `macos/Tests/Ghostties/`, asserting on `SessionCoordinator.launcherScriptDir` (`SessionCoordinator.swift:991`) and a real `AgentTemplate` whose `launchBanner` is nil. Mutant-verify by restoring the guard and watching it fail.

**1.2 Port the ancestor walk.** New file `macos/Sources/Features/Ghostties/ClaudeSessionJoin.swift`. Pure type: given a pid, walk `ppid` via `sysctl` `KERN_PROC_PID`, read each ancestor's argv via `KERN_PROCARGS2`, return the first UUID parsed out of a `~/.ghostties/cache/launchers/<uuid>.sh` argument. `SystemProcessAncestorLookup` is **not in this repo** (it lives in `~/Code/Agent-Status/`), so this is a port with real implementation cost, not wiring.
- Acceptance: a unit test that feeds a recorded argv fixture string and asserts the extracted UUID, plus a manual check that `ps auxww` (never `ps -eo command`, which truncates) shows a launcher path for a freshly launched session.

**1.3 Read the sessions directory.** New file `macos/Sources/Features/Ghostties/ClaudeSessionStore.swift`. Enumerate `~/.claude/sessions/*.json`, decode the subset the fork needs (`pid`, `sessionId`, `status`, `cwd`, `statusUpdatedAt`), and expose `state(forGhostiesSession: UUID) -> ClaudeSessionState?` keyed through 1.2. Watch the directory with `TaskFileWatcher(url:debounceInterval:onChange:)` (`TaskFileWatcher.swift:33-35`), which is already a general directory watcher and needs no change. Ignore the `*.key` files, which sit in the same directory.
- **A live session's launcher script is deleted at teardown** (`SessionCoordinator.removeLauncherScript(for:)`, `:997-1000`, plus a 24h sweep at `:1007-1025`). So the join resolves only while the process is alive, which is exactly when status matters. Do not attempt to hold status for a dead pid; drop to `.inactive` per the abstain design.
- Acceptance: a debug-only log line, run against the live machine, printing joined-count over total-sessions. Target is 10/10 after 1.1 has been live for a full session cycle.

**1.4 Feed BOTH caches.** The read must enter through the existing 1Hz tick, not beside it. `SessionCoordinator.performActivityTick()` (`:1279-1320`) computes `current` from `indicatorState(for:)` and hands it to `Perf.publishIfChanged` (`PerfSignpost.swift:25-38`) with `cached: &self.cachedIndicatorStates` (`:135`); the publish closure writes `WorkspaceStore.updateIndicatorState` (`:1311`). Add the Claude read as a **branch inside `indicatorState(for:)`'s `.running` case** (`SessionCoordinator.swift:1345-1375`), before the output heuristics. Nothing else changes, so both caches stay coherent by construction. Writing a second publish path is the #90/#92 bug shape.
- Mapping, given only `idle` and `busy` exist: `busy` maps to `.processing` (with the existing 30-minute `.longRunning` promotion from `processingStartTimes` still applied), `idle` maps to `.idle`. `needsAttention` and `waiting` keep coming from the existing heuristics until a real source exists (see Phase 5). **This is an honest downgrade, not a feature**: it replaces a guess about running-versus-idle with a fact, and leaves the attention states exactly as wrong as they are today rather than pretending to fix them.
- Acceptance: new `SessionCoordinatorClaudeStatusTests` reusing `seedRunningSessionForTesting(id:)` (`:1537`) and `runActivityTickForTesting()` (`:1544`), injecting a stub `ClaudeSessionStore`, asserting `WorkspaceStore.shared.globalIndicatorStates[id]` equals `.processing` for a `busy` fixture and `.idle` for an `idle` one. Follow the existing pattern in `macos/Tests/Ghostties/SessionCoordinatorIndicatorCacheTests.swift:115-158`. Mutant-verify by inverting the mapping.
- Full run: `xcodebuild test -derivedDataPath macos/build ONLY_ACTIVE_ARCH=YES ARCHS=arm64`, totals read from `xcrun xcresulttool get test-results summary`. Do not touch `TEST_TARGET_NAME`.

## Phase 2: the glyph tells the truth

No new UI. The glyph already tints from `globalIndicatorStates`, so Phase 1 alone changes what it says. This phase is one screenshot pass and one deletion.

- **Capture, do not argue.** Launch a build with 3 or more real sessions in mixed states and screenshot the sidebar at @1x and @2x. `.frame(maxWidth:)` shipped wrong three times running on source-reading alone here; a layout or colour claim needs pixels.
- **Delete the terracotta assumption from the spec** before Phase 4 builds on it. Update `docs/plans/session-row-status-spec.html` so the mock's `.glyph.blocked` is `#FFC400` and `.glyph.processing` is systemGreen.

## Phase 3: the breakdown line

**Blocked on a live data source.** Do not start until a probe shows a non-zero count. Probe: for each live sessionId, test both `~/.claude/todos/<sid>-agent-<sid>.json` and `~/.claude/tasks/<sid>/`. Today both return 0 of 10.

When one is live:
- New `macos/Sources/Features/Ghostties/ClaudeTaskStore.swift`, watching that directory with `TaskFileWatcher`. Note `~/.claude/tasks/` is one directory **per session**, so a single watcher on the parent will not see writes into a child; watch per joined session, or poll the joined set on the existing 1Hz tick.
- The line reads `activeForm` of the single `in_progress` item plus `"N of M"`. Both schemas carry `activeForm` and a `status` of `pending`/`in_progress`/`completed`, so the render code is source-agnostic.
- **Neither row has a free second line.** `RecentsRowView` is a fixed `.frame(height: 36)` with name over `projectName` in a two-line `VStack` (`RecentsRowView.swift:59-88, 104`). The Projects-tab `SessionRow` is a fixed `.frame(height: 28)`, single line, ghost on the **trailing** edge after a `Spacer()` (`SessionDetailView.swift:32-75`). The breakdown line must either replace `projectName` on the Sessions tab or grow the row, and the Projects tab has no second line at all. This is a design fork for Sean, strawman below.
- **Strawman:** on the Sessions tab, the breakdown line **replaces** `projectName` while a task list is live and reverts when it clears. Row height stays 36, density stays, and the project name is already implied by the tab's grouping. On the Projects tab, no breakdown line at all, consistent with the spec's own "projects don't get the accordion."
- Acceptance: `ClaudeTaskStoreTests` on a temp-directory fixture asserting `activeForm` extraction and the `N of M` fraction, plus an absent-list case returning nil. Screenshot at both sizes.

## Phase 4: project aggregate and the mixed glyph

- `ProjectDisclosureRow` already aggregates. `projectHeaderIndicator` (`ProjectDisclosureRow.swift:406-410`) uses `coordinator.indicatorState(for:)` while `store.projectGhostColor(for:)` (`:332`, implemented `WorkspaceStore.swift:1049-1073`) uses `globalIndicatorStates`. Two sources in one view. Read the **store** for the count so the number and the tint cannot disagree.
- The header row is `.frame(height: 32)` with `Text(project.name)` and no subtitle (`ProjectDisclosureRow.swift:339-359`). "N need you" needs a second line and a height change, or it goes trailing as a badge. Strawman: **trailing badge**, gold, no height change; a 32pt row growing to 44 to hold a count is a bad trade against the density `agent-craft.md` defends.
- Acceptance: extend the existing pure-function test pattern with a static `needsYouCount(project:sessions:indicatorStates:)` so the count is testable without a view, mirroring `projectGhostColor`'s static variant at `WorkspaceStore.swift:1049`.
- Name collision to avoid: `NeedsYouZoneView` already exists (`NeedsYouZoneView.swift:11`) and reads `taskStore.needsYou`, an unrelated task concept in the hidden taskFirst view. Do not reuse the symbol.

## Phase 5: inline Approve (specified, not scheduled)

The capability is real; the trigger is not.
- **Capability confirmed, with one hop the spec missed.** `sendText(_ text: String)` at `macos/Sources/Ghostty/Ghostty.Surface.swift:41` and `sendKeyEvent(_ event: Input.KeyEvent)` at `:59` are on `Ghostty.Surface` (`:12`). `SessionCoordinator.sessionTrees` (`:39`) holds `SplitTree<Ghostty.SurfaceView>`, and `SurfaceView` reaches the model through `private(set) var surfaceModel: Ghostty.Surface?` (`SurfaceView_AppKit.swift:180`). Same module (`PRODUCT_MODULE_NAME` is `Ghostty`), so internal access works. Path: `sessionTrees[id]` to `SplitTree.root` (`SplitTree.swift:15-16`, `.leaf(view:)`) to `surfaceModel` to `sendText`. Nothing in `Ghostty/` changes.
- **What must exist first:** a field that says a bounded choice is pending and what the affirmative keystroke is. The sessions file has none. The only candidate is the peer IPC surface (`messagingSocketPath`, `peerProtocol: 1`, `peerFeatures: ["notify_idle", "artifact_yield"]`), which is unread and unspecified here. Until that is characterised, the sidebar cannot know a prompt is structured, and `isLikelyPromptingForInput` (`SessionCoordinator.swift:1416-1432`, a suffix-char plus regex heuristic on the last surface title) is exactly the inference decision 1 rejected. **Do not wire a button to it.**
- Freeform "Answer in terminal" is buildable now and is the whole of decision 5 that ships: it is a text action that calls the same `coordinator.focusSession(id:)` the row's tap already calls (`RecentsListView.swift:161`).

## Risks

- **Input injection on stale state (the reason Phase 5 is parked).** Guard, when it is eventually built: re-read the live state file inside the button action, immediately before sending, and no-op unless the live read still shows a pending structured prompt whose identity matches the one the button was drawn from. The row's cached state is never sufficient. `sendText` goes straight to `ghostty_surface_text` with no confirmation (`Ghostty.Surface.swift:41-50`), so a fired keystroke lands wherever the TUI now is: a running command, an editor, a new turn. The identity match, not just the state match, is the guard, because two consecutive prompts both read as pending.
- **Downgrade regret.** Phase 1.4 makes `.processing` and `.idle` correct while leaving `.needsAttention` heuristic. Sean may read the improved rows as evidence the attention states are also fixed. Say so explicitly in the PR body.
- **Reading 10 or more JSON files on a 1Hz tick.** Mitigate by reading only on `TaskFileWatcher` change, caching the parsed map, and letting the tick read the cache. The tick is already the measured hot path (SEA-214, `SessionCoordinator.swift:1290-1300`).
- **A per-window coordinator learns a pid it did not launch.** `SessionCoordinator` is per-window (`:19-20`, constructed at `WorkspaceViewContainer.swift:453`). The join in 1.2 keys on the launcher UUID in argv, which is the Ghostties session id, **not** on anything the coordinator holds. So any window can resolve any session's pid by scanning the process table, and the result lands in the shared `WorkspaceStore.shared.globalIndicatorStates`. This neither uses nor worsens the per-instance `isRunning(id:)` asymmetry (`:605-606`).

## Legibility gate for the mixed glyph (before any Phase 4 code)

The two-tone dot was approved as a 7px CSS circle with a `conic-gradient` half at 35% opacity, rendered in a browser at CSS pixels (spec `:163-174`). That is not what ships. Gate:
1. Render the dot as a SwiftUI shape at its real size (7pt) in a scratch preview, screenshot at @1x and @2x, and view at 100%.
2. Pass condition: at @1x, the two halves are distinguishable side by side against the sidebar chrome, in **both** light and dark, with the shipped gold `#FFC400` rather than terracotta. Gold at 35% opacity on a light chrome (`#F0E9E6`, `WorkspaceLayout.swift:139`) is the hard case.
3. If it fails, fall back to **a plain single number with no dot**, which is what the spec itself recommended before decision 6 overrode it. Sean's override was made against a browser render; a failed pixel check is new information, not a reopened decision.
4. Evidence: both screenshots attached to the PR. `feedback_ui-fixes-regress-each-other.md` is six-for-six here, so budget two review rounds minimum on this row.

## Out of scope

- **The cross-window coordinator defect.** `ProjectDisclosureRow` reading `coordinator.indicatorState(for:)` at `:409` while `projectGhostColor` reads the store is a real inconsistency. Phase 4 reads the store for its own new count and touches neither call site. Not fixed here.
- **Un-hiding the Tasks view.** `taskFirst` stays reachable only by a defaults write. No `AppDelegate.swift` edit.
- **Anything in `macos/Sources/Ghostty/`.** Consumed only.
- **An eighth enum case.** Settled by decision 5.
- **Cleaning up `~/.claude/todos/`** or migrating the dead store.

## ASSUMPTIONS

1. `status` in `~/.claude/sessions/<pid>.json` has values beyond `idle` and `busy`. Not verified. I observed only those two across 10 files, and a search of `~/.claude/logs/` returned 8,430 hits all reading `idle`. A `strings` scan of the 220MB CLI binary at `~/.local/share/claude/versions/2.1.246` did not surface a status union for the local file. It DID surface a separate remote/fleet vocabulary (`worker_status` of `running` / `requires_action` / `idle`, alongside a `pending_action` field), which is a different subsystem and is not evidence about the local file. That is the most promising next place to look. If a `requires_action` equivalent reaches the local file, Phase 1.4 needs a mapping row and Phase 5 may unblock.
2. `peerFeatures` and `messagingSocketPath` expose richer per-turn state. Not verified. I did not connect to the socket or read the peer protocol.
3. `~/.claude/tasks/<sessionId>/` is the current TodoWrite destination. Inferred from schema shape and recency versus `~/.claude/todos/`, not confirmed against the CLI.
4. The `KERN_PROCARGS2` ancestor walk works under the app's sandbox and hardened-runtime entitlements. Not verified. I did not read the entitlements files. If it does not, the whole join dies and Strategy B is back.
5. `SplitTree.root` reaches a single leaf for a normal unsplit session. I read the enum (`SplitTree.swift:15-16`) but not the traversal helpers, so the exact accessor for "the one surface" is unconfirmed.
6. The suite is currently green, and its count. Not measured. `feedback_app-hosted-tests-do-run-from-cli.md` claims about 625 in 33s; a prior plan claimed 885. Step 0 of any implementation must re-measure before trusting a delta.
7. `AgentTemplate` exposes a constructible case with a nil `launchBanner` for the 1.1 test. I did not open `Models/AgentTemplate.swift`.
8. No fork code outside the files listed reads `globalIndicatorStates` in a way Phase 1.4 breaks. I searched `WorkspaceStore.swift` and the row files, not the whole tree.
9. `DESIGN.md` is stale on status colour. I did not open it; the claim rests on the source comment at `WorkspaceLayout.swift:155-158` and on `MEMORY.md`.
10. The `.key` files beside each session JSON are irrelevant to this feature. Not opened.

## What I opened

All `macos/` and `docs/` source paths below were read from the `origin/main` object store, not the working checkout. Line numbers are `origin/main` line numbers.

- `macos/Sources/Features/Ghostties/Models/AgentSession.swift`
- `macos/Sources/Features/Ghostties/WorkspaceStore.swift`
- `macos/Sources/Features/Ghostties/WorkspaceLayout.swift`
- `macos/Sources/Features/Ghostties/SessionCoordinator.swift`
- `macos/Sources/Features/Ghostties/RecentsListView.swift`
- `macos/Sources/Features/Ghostties/RecentsRowView.swift`
- `macos/Sources/Features/Ghostties/ProjectDisclosureRow.swift`
- `macos/Sources/Features/Ghostties/SessionDetailView.swift`
- `macos/Sources/Features/Ghostties/NeedsYouZoneView.swift`
- `macos/Sources/Features/Ghostties/PerfSignpost.swift`
- `macos/Sources/Features/Ghostties/TaskFileWatcher.swift`
- `macos/Sources/Features/Ghostties/WorkspaceViewContainer.swift`
- `macos/Sources/Features/Splits/SplitTree.swift`
- `macos/Sources/Ghostty/Ghostty.Surface.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
- `macos/Tests/Ghostties/SessionCoordinatorIndicatorCacheTests.swift`
- `macos/Ghostties.xcodeproj/project.pbxproj` (worktree checkout, searched for deployment targets)
- `docs/plans/session-row-status-spec.html` (worktree checkout, read in full)
- `docs/plans/composer-ui-11/draft-plan.md` (structure precedent)
- Memory: `MEMORY.md`, `mission.md`, `agent-build.md`, `agent-craft.md`, `decision_session-row-status-vocabulary.md`, `reference_indicator-state-two-cache-coupling.md`, `reference_claude-todo-data-source.md`, `decision_launcher-uuid-join-replaces-strategy-b.md`, `feedback_vacuous-tests-pass-green.md`, `reference_backport-onkeypress-noop-macos13.md`, `decision_align-to-upstream-degrade-gracefully.md`
- `~/.claude/BREVITY.md`
- Live data, enumerated and parsed, values redacted: `~/.claude/sessions/*.json` (10 files), `~/.claude/todos/*.json` (336 enumerated, 5 non-empty, 1 parsed), `~/.claude/tasks/*/` (251 dirs enumerated, 1 record parsed), `~/.ghostties/cache/launchers/` (4 scripts, listed only), `~/.claude/logs/` (searched for status values), `~/.local/share/claude/versions/2.1.246` (string-scanned for a status vocabulary)

Note: `Backport.onKeyPress` and `.onSubmit` never became load-bearing. Nothing in this plan adds a key handler; the only new interactive element that survives triage is a click target. If a keyboard route is added to the Approve or Answer action later, it needs `.onSubmit` paired with any `Backport.onKeyPress`, because the deployment target is 13.0 (`project.pbxproj:892, 916, 939, 962`) and the Backport path is a no-op below 14.
