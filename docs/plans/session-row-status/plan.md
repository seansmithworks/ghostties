# Session row status: implementation plan

Re-draft after an adversarial gate returned `rethink` twice. The previous draft's foundation (a launcher-UUID argv join plus `~/.claude/sessions/<pid>.json`) is dead and is not patched here. Target ref `origin/main` @ `89e6dfb945e2d2a3622268adb6328555f574c8f5`; every `macos/` citation was read from that object store via `git show`, and every line number is an `origin/main` line number. Origin `SeanSmithWorks/ghostties` only, never upstream.

## 1. The plan in one screen

The sidebar stops inferring what a Claude session is doing from terminal-title regex and reads what Claude reports about itself. Six phases, in order, each shippable alone.

- **Phase 0, one line.** `config.environmentVariables["GHOSTTIES_SESSION_ID"] = session.id.uuidString` at `SessionCoordinator.swift:249`, for every template including plain shell. Environment survives `exec` and is inherited by a `claude` the user types into that surface an hour later. This is the whole join.
- **Phase 1, one script.** A shell script shipped in the app bundle and seeded to `~/.ghostties/hooks/ghostties-status.sh`. Claude Code runs it on seven events; it reads `$GHOSTTIES_SESSION_ID`, writes `~/.ghostties/state/<uuid>.json` by temp-file-plus-rename, and exits. A session outside Ghostties costs one `test -z` and `exit 0`.
- **Phase 2, the read.** A new `ClaudeStateStore` watches that directory and feeds one branch of `SessionCoordinator.indicatorState(for:)`, inside the existing 1Hz tick so both indicator caches stay coherent by construction. Also fixes the 30-minute false-orange bug. Not pixel-neutral: six named things change on screen.
- **Phase 3, the Sessions row.** The second line arrives: a todo breakdown when a todo list exists, an action line when the row is blocked. This is the half of the request Sean led with.
- **Phase 4, Approve mechanics.** The inline button, the identity guard that stops it firing into a session that moved on, and the split-session lockout.
- **Phase 5, the Projects header.** "N need you" as a trailing badge, plus the mixed-glyph legibility gate (which the arithmetic predicts will fail on light, with a fallback Sean pre-authorised).

**The single dependency, and it is not code.** Claude Code hooks can be configured only in a settings file: `~/.claude/settings.json`, a project `.claude/settings.json`, managed policy, or a plugin's `hooks/hooks.json`. There is no injection route for a third-party app. Ghostties cannot install this hook; Sean has to accept one entry in his own settings file. **Under "no", everything from Phase 2 up is dead** and what remains is Phase 0's one line plus the `DESIGN.md` correction. That is decision 1, at the end of this document, with a recommended answer.

**What the gate killed and this plan does not carry:** the launcher-script wrapper and its `template.launchBanner` gate (spec decision 2 is dead, it could never reach shell templates), the `KERN_PROC` ancestor walk, `~/.claude/sessions/<pid>.json` as a status source (undocumented, and its `status` is only `idle` or `busy`), reading a hardened process's environment back with `sysctl` (measured dead: `~/.local/bin/claude` is signed `flags=0x10000(runtime)`, so `ps -wwE` returns argv-only bytes and no `GHOSTTY*` keys), and transcript JSONL parsing.

---

## 2. Phases

Every phase runs the unfiltered suite: `xcodebuild test -derivedDataPath macos/build ONLY_ACTIVE_ARCH=YES ARCHS=arm64`, totals read from `xcrun xcresulttool get test-results summary` (raw log lines carry a constant offset). Do not touch `TEST_TARGET_NAME`: fixing it arms nine GUI-driving UI tests. Never `killall ghostty` or `killall ghostties`. Subagent briefs may capture the screen; synthetic keystrokes and AX driving are forbidden.

**Step 0, before any code.** Re-measure the baseline suite count on the branch point and record it in the PR body. Prior claims range from 625 to 885 and none of them is current. A delta is meaningless without this number.

### Phase 0: stamp the session id into the environment

**Files**
- `macos/Sources/Features/Ghostties/SessionCoordinator.swift`. The env block is `:249-259`: `config.environmentVariables = template.environmentVariables`, then the `GHOSTTIES_TASK_FILE` overlay (`:251`), the `GHOSTTIES_TASK_ID` overlay (`:254`), then the `extraEnvironment` loop (`:257-259`). Extract that assembly into a `nonisolated static func spawnEnvironment(template:taskFilePath:taskId:extra:sessionId:) -> [String: String]` on `SessionCoordinator` and call it from `createSession`. Add the `GHOSTTIES_SESSION_ID` entry inside it, before the `extra` overlay so a caller can still override.

**Why it works.** `SurfaceConfiguration.environmentVariables` is marshalled into `ghostty_env_var_s` in `withCValue` (`macos/Sources/Ghostty/Surface View/SurfaceView.swift:705-723`), unconditionally, with no dependence on `config.command`. So a shell template (which has `command: nil` and therefore never got a launcher script) gets the stamp too. Ghostty spawns through `login -flp`, which preserves the environment, and the refuter measured five `GHOSTTY_*` keys already reaching a live `claude` pid through that path plus an interactive zsh plus `cco`. Nothing here depends on argv, so `exec` cannot erase it.

**Acceptance**
- New `macos/Tests/Ghostties/SessionEnvironmentStampTests.swift`, test `testShellTemplateStampsGhosttiesSessionId`, calling the real `SessionCoordinator.spawnEnvironment(...)` with `AgentTemplate.shell` and asserting `result["GHOSTTIES_SESSION_ID"] == id.uuidString`. It names a production symbol; the id is generated in the test and read back from production output, so neither side is free to drift. Mutant-verify by deleting the assignment line and watching it fail.
- Second test `testExtraEnvironmentCanOverrideSessionIdStamp`, asserting the overlay ordering, so a future caller reordering the block breaks a test rather than the join.
- Live evidence: launch one shell session and one agent session from the sidebar, type `echo $GHOSTTIES_SESSION_ID` in each, and confirm both print the row's id. Two commands, no build gate.

### Phase 1: the hook

**Files**
- `macos/Resources/hooks/ghostties-status.sh` (new).
- `macos/Sources/Features/Ghostties/HookInstaller.swift` (new). `seedIfNeeded()` modelled directly on `PresetLoader.seedIfNeeded()` (`PresetLoader.swift:44`), same versioned `.seed-version` marker, same `0o700` directory mode. One deliberate difference: the hook script is app-owned code, not user content, so it is **overwritten** on a version bump rather than preserved. Presets are preserved because they are user-editable; a stale hook script is a bug.
- `macos/Sources/Features/Ghostties/WorkspaceStore.swift:178`. Call `HookInstaller.seedIfNeeded()` on the line after `PresetLoader.seedIfNeeded()`.
- `macos/Ghostties.xcodeproj/project.pbxproj`. `presets` ships as a folder reference in four places: a `PBXBuildFile` (`:36`), a `PBXFileReference` with `lastKnownFileType = folder; path = Resources/presets` (`:110`), a group child (`:344`), and a Resources build-phase member (`:634`). `hooks` needs the identical four entries.

**Where the script lives, decided.** `macos/Resources/hooks/`, not `scripts/`. `scripts/` holds build-time shell that never enters the bundle; this file has to be reachable from a stable path at runtime. Seeding to `~/.ghostties/hooks/` means Sean's settings entry points at one path that survives worktree churn, repo moves, and app updates.

**What the script does.** Six steps and no JSON parser.

1. `[ -z "$GHOSTTIES_SESSION_ID" ] && exit 0`.
2. Read stdin whole into a variable.
3. Wrap it: `{"ghosttiesSessionId":"<uuid>","updatedAt":<epoch>,"hook":<raw stdin>}`.
4. Write to `<dest>.$$.tmp`, then `mv -f` onto `<dest>`. Same-directory `mv` is `rename(2)`, which changes a directory entry, which is what a directory vnode source fires on. The previous draft's in-place write was the bug the gate found twice.
5. If the raw bytes contain `"tool_name":"TodoWrite"`, the destination is `~/.ghostties/state/<uuid>.todos.json`; otherwise it is `~/.ghostties/state/<uuid>.json`. A `case` glob match, no parser.
6. `exit 0`, always.

**Deviation from the brief, stated.** The brief specified the script derive `state` and write a flat `{state, structuredPrompt, todos, ...}` shape. Deriving state in shell needs a JSON parser, which means a hard runtime dependency on `jq` (not guaranteed) or `/usr/bin/python3` (can trigger a Command Line Tools prompt). So the **on-disk** format is the raw hook payload plus a two-field wrapper, and the derivation moves into Swift where `JSONDecoder` is free and the mapping table is unit-testable against fixtures. The contract the brief named survives exactly, as the `ClaudeState` struct in Phase 2. Splitting todos into their own file is what stops the next `PreToolUse` from overwriting the last `TodoWrite` payload.

**Events registered, all `"async": true`.**

| Event | Matcher | Derived state |
|---|---|---|
| `UserPromptSubmit` | none | `busy` |
| `PreToolUse` | none | `busy` (this is also what clears an attention state after Sean answers in the terminal) |
| `PostToolUse` | `TodoWrite` | todos only, no state change |
| `Stop` | none | `idle` |
| `Notification` | none | `needsPermission` if `notification_type == permission_prompt`; `needsInput` if `idle_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, or `agent_needs_input`; ignored otherwise |
| `PermissionRequest` | none | `needsPermission`, carrying `tool_name` |
| `SessionEnd` | none | `ended` |

`"async": true` on `PermissionRequest` is not a performance choice. An async hook cannot return a `decision`, so it is the mechanism that guarantees v1 can never alter a permission outcome. Observe-only is enforced by the transport, not by discipline.

**Pruning `~/.ghostties/state/`.** Three mechanisms, because the launcher directory leaked for exactly the reason of having only one.

- `SessionCoordinator.setStatus(_:for:)` (`:1464-1477`), `.completed`/`.exited`/`.killed` branch: delete both files for that id. This is the right seam because `closeSession` and `handleSurfaceClose` both funnel through it; the launcher script's delete sits in `closeSession` alone (`:664`), which is why stale scripts accumulate.
- App-launch sweep, `ClaudeStateStore.sweepStale()`, called from `macos/Sources/App/macOS/AppDelegate.swift:265` alongside `SessionCoordinator.sweepStaleLauncherScripts()`. Delete `*.json` older than 24h, using the same symlink-aware `attributesOfItem` plus `.typeRegular` check the launcher sweep uses (`:1006-1025`).
- A `SessionEnd` event marks the file `ended`; the store deletes it on the next read.

Directory mode `0o700`. These files carry todo text and tool names, the same per-session context class the launcher-script comment warns about at `SessionCoordinator.swift:987-990`.

**Acceptance**
- New `macos/Tests/Ghostties/HookInstallerTests.swift`: `testSeedWritesExecutableHookScript` asserts the seeded file exists at `HookInstaller.hooksDirectoryPath` with mode `0o700`, and `testSeedOverwritesOnVersionBump` asserts a modified seeded script is replaced when `seedVersion` advances (the deliberate divergence from `PresetLoader`). Both name production symbols. Mutant-verify the second by restoring `PresetLoader`'s preserve-on-exists behaviour and watching it fail.
- Live evidence: the three experiments in section 3. There is no useful unit test of the script itself; its correctness is the observed payloads.

### Phase 2: the read, into both caches

**Files**
- `macos/Sources/Features/Ghostties/ClaudeStateStore.swift` (new). A `@MainActor final class` with a `static let shared`, not a per-coordinator instance: `SessionCoordinator` is per-window (`:19-20`) and `~/.ghostties/state/` is global. Holds `private var states: [UUID: ClaudeState]`, refreshed by a single `TaskFileWatcher(url:debounceInterval:onChange:)` on `~/.ghostties/state/`. The watcher needs no change: it is already a general directory vnode source over `[.write, .extend, .rename, .delete, .attrib]` (`TaskFileWatcher.swift:58-72`), it fires once on attach, it retries every 500ms if the directory does not exist yet, and Phase 1 writes by rename so directory entries genuinely change.
- `ClaudeState` is the struct the brief specified: `ghosttiesSessionId`, `claudeSessionId`, `cwd`, `state` (`busy` / `idle` / `needsInput` / `needsPermission` / `ended`), `structuredPrompt: (toolName: String, toolUseId: String?)?`, `todos: [ClaudeTodo]?`, `updatedAt: Date`. Decoded from the raw wrapper; the event-to-state mapping is a `static func derive(from:)` so it is testable without a filesystem.
- `macos/Sources/Features/Ghostties/SessionCoordinator.swift:1345-1372`. One branch at the top of the `.running` case, before the `lastOutputTimestamps` check.

**All file IO stays off the render path.** `indicatorState(for:)` has two callers in `body` (`ProjectDisclosureRow.swift:176` and `:413`, the latter mapping over every session in the project). The branch does a dictionary lookup on an already-parsed in-memory map. Parsing happens only in the watcher callback, which arrives on the main queue debounced at 150ms. Nothing in `body` touches the disk.

**Mapping into the seven-case enum**

| `ClaudeState.state` | `SessionIndicatorState` | Note |
|---|---|---|
| `busy` | `.processing`, promoted to `.longRunning` past 1800s | Promotion keeps `processingStartTimes` and `Self.longRunningThreshold` (`:138`) |
| `idle` | `.idle` | Also clears `processingStartTimes[id]` |
| `needsInput` | `.needsAttention` | Payload `.freeform` |
| `needsPermission` | `.needsAttention` | Payload `.permission(toolName:toolUseId:)` |
| `ended`, or `updatedAt` older than 30 minutes | no branch taken | Falls through to today's heuristics |

`.waiting` is never produced by the hook, and that is correct: it was always the branch inference fell into when it could not tell, and `:1362-1371` already returns `.idle` for silent agent sessions.

**The payload does not go on the enum.** `SessionIndicatorState` is a plain `Comparable` enum with a `priority` switch (`Models/AgentSession.swift:175-199`). Adding an associated value changes its synthesized `Equatable`, which is what `Perf.publishIfChanged`'s `guard cached != current` compares, so a tool-name change would republish and re-render the whole sidebar. The payload lives in `ClaudeStateStore.attention(for: UUID) -> AttentionPayload?`, read by the row view directly. The enum, its ordering, and all six colour maps stay untouched, which is what decision 5 asked for.

**Fix the 30-minute false orange.** `processingStartTimes` is set on the first title-change output (`:1100-1101`) and cleared in exactly one place: `promptDidBecomeReady`, on OSC 133 (`:1235-1236`), which Claude's TUI never emits. So every Claude session promotes to `.longRunning` orange 30 minutes after its first output and stays there. The branch clears `processingStartTimes[id]` on a hook `idle`, the same mutation `promptDidBecomeReady` performs. Hook-covered rows get correct orange; rows without a hook are unchanged.

**Both caches stay coherent by construction.** The read enters through `indicatorState(for:)`, which `performActivityTick()` (`:1279-1320`) already calls to build `current`, hands to `Perf.publishIfChanged` with the coordinator's own `cachedIndicatorStates` passed inout (`:1301-1304`), and publishes into `WorkspaceStore.updateIndicatorState` (`:1311`). No second publish path is added. A second path is the exact shape of the PR #90 and #92 bugs.

**No abstain rule.** A row with no state file keeps today's heuristics unchanged. The previous draft's "non-joined rows are never eligible for an attention colour" is a regression switch until hook coverage is real, and it contradicted its own mapping section.

**What changes on screen. Phase 2 is not pixel-neutral.**

1. Agent rows stop flickering between `.processing` and `.idle` every 2 seconds of silence (`activityThreshold`, `:88`). A busy turn holds green for its whole duration.
2. Projects stop bouncing in and out of the ACTIVE NOW section during that flicker. `WorkspaceStore.isActiveIndicatorState` (`:1080-1087`) excludes `.idle`, and `computeSectionedProjects` reads it at `:1141-1143`.
3. The menu-bar dot stops flickering for the same reason. `MenuBarController.swift:26` subscribes to the published indicator dict; `MenuBarIconRenderer.dotColor` is at `:151-161`.
4. Gold appears when a permission prompt is genuinely up and clears when it is answered, instead of whenever the terminal title happens to end in `?` or `:` (`isLikelyPromptingForInput`, `:1416-1432`).
5. Orange stops appearing on every Claude session older than 30 minutes.
6. Sessions-tab section membership does **not** move: `belongsInActive` is a plain "not inactive" test (`RecentsListView.swift:305`), so processing and idle are both Active. No row reshuffling under the cursor.

**Every surface the global indicator dict drives**, so a review round covers all of them: the row glyph (`RecentsRowView.swift:119-128`), Sessions-tab section membership (`RecentsListView.swift:215`, `:225`, `:236`), the project ghost tint (`WorkspaceStore.projectGhostColor`, `:1049-1073`), project section bucketing (`:1141`), the per-project grace tracker (`:574`, `:596`), the sectioned-projects and session-groups cache invalidation in the `didSet` (`:58-62`), the menu-bar icon (`MenuBarController.swift:26`), and the menu-bar dropdown rows (`MenuBarDropdownView.swift:164-174`). The sixth colour map is `SessionDetailView.swift:156-166`; the fourth is `ProjectDisclosureRow.projectHeaderColor` (`:418-428`).

**Acceptance**
- New `macos/Tests/Ghostties/ClaudeStateStoreTests.swift`: `testDerivesNeedsPermissionFromNotificationPayload`, `testDerivesBusyFromPreToolUse`, `testDerivesIdleFromStop`, `testStateOlderThanThirtyMinutesIsIgnored`, each calling the real `ClaudeStateStore.derive(from:)` against a fixture captured in experiment E1 or E2, never a hand-written literal. Mutant-verify by swapping two rows of the mapping.
- New `macos/Tests/Ghostties/SessionCoordinatorClaudeStateTests.swift`, following `SessionCoordinatorIndicatorCacheTests.swift:115-158`: inject a stub state provider, `seedRunningSessionForTesting(id:)` (`:1537`), `runActivityTickForTesting()` (`:1544`), assert the published indicator for that id. One test per mapping row. Mutant-verify by inverting `busy` and `idle`.
- `testHookIdleClearsProcessingStartTime`: seed via `seedIndicatorStateForTesting(id:processingStartSecondsAgo:)` (`:1552-1572`) at 2000 seconds, feed a hook `idle` then a hook `busy`, assert the result is `.processing` and not `.longRunning`. This is the false-orange regression test and it fails without the clear.
- Capture the sidebar at @1x and @2x with at least three real sessions in mixed states, light and dark. The chip-width line shipped wrong three times running on source-reading alone in this repo; a layout or colour claim needs pixels.

### Phase 3: the Sessions row second line

**Files**
- `macos/Sources/Features/Ghostties/RecentsRowView.swift`
- `macos/Sources/Features/Ghostties/RecentsListView.swift:148-164`

**The layout, decided.** The breakdown or action line **replaces** `Text(projectName)` (`RecentsRowView.swift:84-87`) while present, and the row reverts to `projectName` when it clears. Row height stays 36 (`:104`), the two-line stack at `:59` keeps its shape, and density is unchanged. The glyph owns status; the second line is a breakdown or an action, never a status word.

**The cost of that, named.** The Sessions tab groups by indicator state, not by project (`activeSessions` / `inactiveSessions` / `archiveSessions`, `RecentsListView.swift:215-243`), so rows from different worktrees interleave and `projectName` is the only project attribution on the tab. While the second line is a breakdown, that attribution is gone from the pixels. Mitigation: it stays in the accessibility label, which already reads "in <projectName>" (`RecentsRowView.swift:152-164`). This is decision 3 at the end, and the alternative (grow the row to three lines at 48pt) is the fork.

**Two shapes for the line**
- **Breakdown**, when the store has a non-empty todo list: the `activeForm` of the single `in_progress` item, then a middot, then "N of M". Absent when the list is empty or missing. No placeholder, no disabled state.
- **Action**, when the state is `.needsAttention`: `needsPermission` renders an inline Approve button labelled from `toolName` (for example "Approve Bash"); `needsInput` renders the text action "Answer in terminal", which calls the same `coordinator.focusSession(id:)` (`SessionCoordinator.swift:421`) that tapping the row already calls.

Action wins over breakdown when both apply. A blocked row's job is to be actioned.

**The comparator, which is where this breaks silently.** `RecentsRowView` is manually `Equatable` and its `==` compares exactly `session`, `projectName`, `indicatorState`, `isActive`, `isEditing` (`:42-48`), and `RecentsListView` applies `.equatable()` at `:164`. **Every new prop must be added to `==` or the line renders once and freezes**, which is the same failure family as the lazy-container freeze and no store-level unit test can see it. Add one prop, `rowDetail: RowDetail?`, an `Equatable` enum with `.breakdown(text:)` and `.action(AttentionPayload)` cases, computed in `sessionRow(for:)` (`RecentsListView.swift:148`) and compared in `==`.

**Colour.** Gold is a glyph tint and never a text colour (about 1.3:1 as text on light chrome). The breakdown line uses `WorkspaceLayout.textSecondaryLight` / `textSecondaryDark` (`:216`, `:219`), the same tokens `projectName` uses today. The Approve button is a filled control, so its label is white on a filled background, and its fill is the accent, not the status gold.

**Accessibility.** `RecentsRowView` ends with a combined accessibility element plus an explicit `.accessibilityLabel(accessibilityLabel)` (`:112-113`), and the explicit label overrides the combined children, so a new visual line reaches VoiceOver only if it is appended in `accessibilityLabel` (`:152-164`). The Approve button inside a combined element is not focusable, so the row also gains `.accessibilityAction(named:)` carrying the same label. `a11y` is a declared design layer for this repo.

**Acceptance**
- `RecentsRowDetailTests.testEqualityIncludesRowDetail`: construct two `RecentsRowView` values differing only in `rowDetail` and assert they compare unequal. Names the production `==`. Mutant-verify by removing the `rowDetail` clause from `==`.
- `ClaudeTodoBreakdownTests.testBreakdownUsesActiveFormAndFraction` and `testEmptyTodoListYieldsNoBreakdown`, against the real formatter and an E1 fixture.
- `RecentsRowAccessibilityTests.testAccessibilityLabelIncludesBreakdown`, asserting on the production `accessibilityLabel`.
- Capture at @1x and @2x, light and dark, with one breakdown row, one `needsPermission` row, one `needsInput` row, and one plain row in frame. Budget two review rounds: UI fixes in this repo have regressed each other six times for six.

### Phase 4: Approve mechanics

**Files**
- `macos/Sources/Features/Ghostties/SessionCoordinator.swift`, new method `func sendApproval(for id: UUID, matching: AttentionPayload) -> Bool`.
- `macos/Sources/Features/Ghostties/RecentsRowView.swift`, the button action.
- Nothing in `macos/Sources/Ghostty/`. That is the upstream seam and is consume-only.

**The path, confirmed.** `SplitTree` conforms to `Sequence` and `Collection` over leaf views (`SplitTree.swift:1181-1195`), so `sessionTrees[id]?.first` is the leftmost leaf `Ghostty.SurfaceView`. `SurfaceView` exposes `private(set) var surfaceModel: Ghostty.Surface?` (`SurfaceView_AppKit.swift:180`), internal to the same module because `PRODUCT_MODULE_NAME` is `Ghostty`. `Ghostty.Surface.sendText(_:)` is at `Ghostty.Surface.swift:41`. `focusSession` already uses `tree.first` this way (`SessionCoordinator.swift:448`).

**Split sessions are locked out.** The previous draft filed "root reaches a single leaf" as confirmed; it is not. A split session's root is a `.split`, and the leftmost leaf is not necessarily where Claude runs. If `sessionTrees[id]` has more than one leaf, the Approve button is not drawn at all and the row falls back to "Answer in terminal". A wrong-pane keystroke is worse than a hand-off.

**The guard, which is the whole of this phase.** `sendApproval` re-reads the state file from disk inside the action, immediately before sending, and no-ops unless **both** hold: `state == needsPermission`, and the prompt identity matches the one the button was drawn from. **Identity is `tool_use_id`, not `updatedAt`.** `updatedAt` is a wall-clock stamp that two consecutive prompts inside one second can share, and it also changes for reasons that are not a new prompt. `tool_use_id` is the field Claude assigns per tool invocation and is the only value in the payload that is unique to this prompt. If `tool_use_id` is absent from the observed payload (E2 answers this), the button does not ship and Approve moves to the v2 route below. Returning `false` flashes an inline "already resolved" on the row and does not send.

**What gets sent.** The literal text `1\r`, which selects the first option in Claude Code's permission select. E2 must confirm the prompt shape in Sean's installed version before this line ships; if the affirmative keystroke is not stable across the prompt variants observed, Phase 4 ships "Answer in terminal" only and Approve waits for v2.

**The injection-free alternative, and why it is v2.** A **synchronous** `PermissionRequest` hook can return a JSON `decision`, so Ghostties could answer the permission without ever touching the terminal: the hook writes its request, then polls `~/.ghostties/state/<uuid>.answer` for up to N seconds and returns the decision it finds. That removes input injection entirely. It is v2 because a synchronous hook **blocks the agent**: every permission prompt would stall for N seconds before the terminal even draws it, so the cost of the safer route is paid by Sean on every prompt whether or not he uses the sidebar. Ship the guarded injection first, measure how often the sidebar is actually the answering surface, then decide whether the stall is worth it.

**Acceptance**
- `SendApprovalGuardTests.testNoOpWhenToolUseIdDoesNotMatch` and `testNoOpWhenStateIsNoLongerNeedsPermission`, both asserting `sendApproval` returns `false` and that no send occurred (assert on a send-count spy, not on the absence of a crash). Mutant-verify by relaxing the guard to check `state` alone and watching the identity test fail; the repo's precedent is that a test which cannot discriminate the mutant is vacuous.
- `testApproveHiddenForSplitSession`, asserting the row detail resolves to `.action(.freeform)` when the tree has more than one leaf.
- No synthetic-keystroke verification by an agent. Sean drives the live send himself, once, and the evidence is his word plus a screen capture of the row before and after.

### Phase 5: the Projects header, and the DESIGN.md correction

**Files**
- `macos/Sources/Features/Ghostties/WorkspaceStore.swift`, new `nonisolated static func needsYouCount(project:sessions:indicatorStates:) -> Int`, mirroring the pure-static `projectGhostColor` at `:1049-1073` so the count is testable without a view.
- `macos/Sources/Features/Ghostties/ProjectDisclosureRow.swift:339-355`.
- `DESIGN.md` and `docs/plans/session-row-status-spec.html`, in the same commit.

**Read the store, not the coordinator.** The header currently mixes two sources: the ghost tint comes from `store.projectGhostColor(for:)` (`:330-334`, global dict) while the chevron comes from `projectHeaderIndicator`, which maps `coordinator.indicatorState(for:)` over every session (`:406-410`). The count reads the store, so it can never disagree with the ghost beside it. It can still disagree with the chevron; fixing that mixed read is out of scope here and is listed in section 5.

**Coexisting with the plus button.** The trailing slot already holds a `plus` `Button` when expanded (`:345-355`), and `Text(project.name)` is greedy at `.frame(maxWidth: .infinity, alignment: .leading)` (`:343`). The badge goes between them with `.layoutPriority(1)` so the greedy name truncates instead of the count. Row height stays 32. **This is a pixel claim, not a source claim**: verify with a capture on a long project name at 220pt sidebar width.

**The badge is decorative.** The whole header is one `Button` whose label carries `.contentShape(Rectangle())` (`:305-364`), so clicking the badge toggles the disclosure. That is correct behaviour, not a defect: the badge reports, the header expands. The header's hardcoded accessibility label at `:394` gains ", N need you".

**The mixed glyph (decision 6), with an honest prediction.** The gate: render the two-tone dot as a SwiftUI shape at its real 7pt size, capture at @1x and @2x, view at 100%, in light and dark, with the shipped `WorkspaceLayout.statusNeedsDecisionGold` `#FFC400` (`:178`) and not terracotta. Pass condition is that the two halves are distinguishable side by side against the sidebar chrome in **both** themes. **Expect it to fail on light.** Gold at 35 percent over chrome light `#F0E9E6` (`:139`) composites to roughly (245, 220, 150) against (240, 233, 230), a luminance ratio near 1.05 to 1. The dark composite reads clearly. A token that survives one theme is not shippable against the round-4 lock that both themes follow system. The fallback is the plain single number with no dot, which Sean pre-authorised ("maybe 1 later if it feels off"). A failed pixel check is new information, not a reopened decision, and the two captures are the evidence.

Separately: there is no status dot in this sidebar. Session rows draw a 14pt ghost (`WorkspaceLayout.sessionGhostSize`, `:260`, used at `RecentsRowView.swift:53-56`) and the project header a 12pt ghost (`ProjectDisclosureRow.swift:330-335`). A 7pt two-tone circle introduces a primitive the vocabulary does not contain, sitting beside a glyph already carrying the same colour. Say that in the PR body alongside the captures so Sean rules on it once.

**Fix `DESIGN.md`, not just the spec.** `DESIGN.md` on `origin/main` asserts six times that terracotta `#C97350` is the `waiting` colour: `:72` ("reserved for `waiting` state"), `:104` (the palette table row "Accent (waiting)"), `:109` ("reserved exclusively for the `waiting` activity indicator state"), `:203` (the indicator table row), `:261` and `:270` (the do and do-not lists), `:303` (the summary rule). `:65` mentions terracotta as a general warmth cue and is correct as written. The shipped palette is `error` systemRed, `needsAttention` gold `#FFC400`, `waiting` blue `#5B8DEF`, `longRunning` orange `#F97316`, `processing` systemGreen, all six maps agreeing, and `WorkspaceLayout.swift:155-158` says in a comment that terracotta "is NOT the session-status waiting color." Correct `DESIGN.md` to the shipped palette and update the spec's mock colours in the same commit, or the next agent reintroduces terracotta from the source of truth.

**Acceptance**
- `NeedsYouCountTests.testCountsOnlyNeedsAttentionSessions` against the real static, with sessions in all seven states. Mutant-verify by widening the filter to include `.waiting`.
- Name collision to avoid: `NeedsYouZoneView` already exists (`NeedsYouZoneView.swift:11`) and reads an unrelated task concept in the hidden `taskFirst` view. Do not reuse the symbol.
- Captures: header with badge at @1x and @2x, light and dark, collapsed and expanded, with a long project name. Plus the two mixed-glyph gate captures.

---

## 3. Build-time experiments that gate later phases

All three run from one temporary log-only hook: a script registered for every event that appends its stdin to `~/.ghostties/state/_probe.log` and exits. It is the Phase 1 script with the write target changed, so writing it is not throwaway work. Nothing in Phases 2 to 5 starts until all three have run.

**E1. Observe one real `TodoWrite` hook payload.** Gates Phase 3. The `tool_input` shape for `TodoWrite` is undocumented; the expectation is `todos: [{content, status, activeForm}]` but that must be observed, not assumed. Capture one payload, commit it as a test fixture (redact the content strings), and write `ClaudeTodoBreakdownTests` against it. If `activeForm` is absent, the breakdown line uses `content` and the spec's copy changes.

**E2. Confirm `Notification` with `notification_type: permission_prompt` actually fires, in Sean's permission mode.** Gates Phase 2's attention mapping and all of Phase 4. Two things to record: whether the event fires at all (if he runs in a mode that auto-approves, it never will, and gold has no source), and whether the payload carries `tool_use_id`. Phase 4's guard has no identity without it and the button does not ship. Also record the observed rate over one working hour, which is the input to the risk in section 4.

**E3. Confirm the hook sees `GHOSTTIES_SESSION_ID` from a `cco`-typed session.** Gates everything. Phase 0 stamps the env at spawn; the chain to the hook is `login -flp`, an interactive zsh, `cco`, the `claude()` shell function, `claude`, then the hook process. Every link preserves the environment in principle and five `GHOSTTY_*` keys were measured arriving at a live `claude` pid, but the hook process itself has never been observed. One line in the probe log settles it. If it fails, the whole plan fails here and nothing downstream is worth building.

---

## 4. Risks

- **Input injection is real and the guard is the only thing between it and a wrong keystroke.** `sendText` goes straight to `ghostty_surface_text` with no confirmation (`Ghostty.Surface.swift:41-50`), so a fired keystroke lands wherever the TUI now is: a running command, an editor, a new turn. The guard is a fresh disk read plus a `tool_use_id` match plus the split-session lockout, evaluated inside the action. The row's cached state is never sufficient. State match alone is not sufficient either, because two consecutive prompts both read as pending.
- **The hook runs on every tool call.** `PreToolUse` has no matcher, so a busy agent spawns one short-lived process per tool invocation, plus one more per `TodoWrite`. `"async": true` means it never blocks the agent, and the script's first statement is the env check, but this is a real cost on a machine already running 2 to 7 parallel sessions. E1 measures the rate; if it is bad, the mitigation is dropping `PreToolUse` and accepting that an attention state clears on tool completion instead of tool start.
- **The needs-you badge may be lit constantly.** In default permission mode Claude prompts often, so "N need you" could be permanently non-zero and therefore meaningless. This is a design risk, not a bug: a badge that is always on is furniture. E2's rate measurement is what tells us whether the badge needs a floor (for example, only count prompts older than 10 seconds) before Phase 5 ships.
- **A user with no hook installed sees exactly today's sidebar.** No abstain rule, no degraded mode, no empty states. That is deliberate and it is also what makes decision 1 load-bearing: the feature does not partially work without the hook, it does not exist.
- **A killed `claude` leaves a `busy` file behind.** The 30-minute staleness cap handles it, and the branch only runs inside the `.running` lifecycle case so a dead surface never reads it. A working agent refreshes `updatedAt` on every tool call, so 30 minutes of silence while claiming busy is genuinely dead.
- **Two hooks from one session can interleave.** Both write by rename, so no file is ever half-written; last-write-wins, ordered by `updatedAt`. Acceptable.

---

## 5. Out of scope

- **The cross-window coordinator defect.** `ProjectDisclosureRow` reads `coordinator.indicatorState(for:)` at `:409` and `:176` while the ghost beside it reads the store. `SessionCoordinator` is per-window (`:19-20`), so the two can disagree. Phase 5 reads the store for its own new count and touches neither call site.
- **`isRunning(id:)`'s per-instance asymmetry** (`:605-606`). Same family, same decision.
- **Un-hiding the Tasks view.** `taskFirst` stays reachable only by a defaults write. No `AppDelegate.swift` edit.
- **Anything in `macos/Sources/Ghostty/`.** Consumed only. `sendText` and `SplitTree` are read, never modified.
- **An eighth enum case.** Settled by decision 5, and Phase 2 explains why the payload cannot live on the enum either.
- **Transcript parsing** of `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`. The AppKit refuter is right that it is the live todo store, but `PostToolUse` on `TodoWrite` delivers the same list directly and the docs say the JSONL format is unsupported for external parsing. Rejected as a mechanism, accepted as the evidence that Phase 3 is buildable.
- **The `KERN_PROCARGS2` environment read-back.** Both refuters proposed it; it is measured dead against a hardened binary. See the final row of the findings ledger.
- **`~/.claude/sessions/<pid>.json`, `~/.claude/todos/`, `~/.claude/tasks/`.** All three are either undocumented, dormant, or too coarse. Not read, not cleaned up, not migrated.
- **A Settings affordance that writes the hook for Sean.** Decision 2, recommended for v2.

---

## 6. ASSUMPTIONS

Numbered, and anything not opened is here.

1. **The hook process inherits `GHOSTTIES_SESSION_ID`.** Documented behaviour (hooks inherit the parent environment except `OTEL_*`) and every intermediate link preserves the environment, but the hook process itself has not been observed. E3 settles it. If false, the plan dies at Phase 1.
2. **`tool_use_id` is present on the `Notification` or `PermissionRequest` payload for a permission prompt.** Documented for `PostToolUse`; not documented for the other two. E2 settles it. If false, Phase 4's Approve does not ship.
3. **`TodoWrite`'s `tool_input` carries `activeForm` and a `pending`/`in_progress`/`completed` status.** Expected, undocumented. E1 settles it.
4. **`Notification` fires with `permission_prompt` in Sean's current permission mode.** E2 settles it.
5. **Claude Code's permission prompt is a numbered select where option 1 is affirmative.** Not verified against the installed version. E2 settles it; Phase 4 is conditional on it.
6. **`AgentTemplate.shell` is constructible in a test** for the Phase 0 test. I did not open `Models/AgentTemplate.swift` on this pass; the refutations cite `:115-121` for the shell kind and `:26` for `command: String?`.
7. **The suite is green and its count.** Not measured. Step 0 measures it.
8. **The `hooks` folder reference in `project.pbxproj` behaves like `presets`.** I read the four `presets` entries but did not add or build the `hooks` ones.
9. **No fork code outside the files listed reads the global indicator dict in a way Phase 2 breaks.** I enumerated `WorkspaceStore`, both row views, both menu-bar files, and `SessionDetailView`. I did not grep the whole tree.
10. **`TaskFileWatcher` fires on a same-directory `mv`.** Strongly implied (a rename changes a directory entry, and the source takes `.rename` and `.write` on the directory fd at `:58-72`), but not observed on this specific write pattern. Cheap to confirm during Phase 1.
11. **The 30-minute staleness cap does not cut a legitimately long turn.** Rests on `PreToolUse` firing during long turns, which E1's log will show.
12. **Nothing else in `~/.ghostties/` collides with a `state/` subdirectory.** `cache/launchers`, `presets`, and per-project `.ghostties/tasks/` are the known users.

---

## 7. Decisions for Sean

**1. Does the hook go in `~/.claude/settings.json` (all projects) or a per-project `.claude/settings.json`?**
Recommended: **user-level `~/.claude/settings.json`**. He already runs `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`, and `SubagentStop` there, so this is one more entry in a file he maintains, and it covers every project without per-repo bookkeeping. Per-project means editing N settings files and re-editing every new repo, for no benefit: the script already no-ops outside Ghostties. **What "no" costs:** there is no third-party injection route for a Claude Code hook, so "no" is "no hook anywhere". Phases 2 through 5 are dead, the feature does not exist, and what ships is Phase 0's one line plus the `DESIGN.md` correction. This is the first decision because everything else is downstream of it.

**2. Should Ghostties later grow a Settings affordance that writes the hook entry for him?**
Recommended: **v2, not now.** It is a small amount of code (read, merge, write JSON, with a backup) but it means a third-party app editing his Claude Code configuration, which is a trust surface worth designing rather than bolting on. For v1 the install is one paste into a file he already edits. Revisit when the feature has earned its place.

**3. Does the breakdown/action line replace `projectName`, or does the row grow?**
Recommended: **replace.** Row height stays 36pt, density holds, and the change is temporary (the line reverts to `projectName` the moment the todo list clears or the block resolves). The honest cost: the Sessions tab groups by state, not project, so while the breakdown is showing, that row loses its only visible project attribution, and he runs 2 to 7 sessions across several worktrees. The alternative is a 48pt three-line row, which is a permanent density cost for an intermittent line. This is his call, not mine; the strawman is built for replace.

**4. If the mixed-glyph gate fails on light (expect it to), does the plain number ship?**
Recommended: **yes, plain number, no dot.** He pre-authorised it. The alternative that would survive both themes is a second solid hue for the freeform share, which reads as a second status and costs a new token. Flagged here so a predicted failure does not turn into a stalled phase.

**5. Does the badge need a floor before it ships?**
Recommended: **decide after E2's rate measurement, default no floor.** If permission prompts turn out to be near-constant in his mode, "N need you" is lit permanently and stops carrying information. Only count prompts older than a few seconds if the measurement shows it. Not building it speculatively.

---

## 8. What I opened

All `macos/` and root-level paths were read from the `origin/main` object store via `git show origin/main:<path>`, not from this worktree's checkout (which is 60 commits behind). Line numbers are `origin/main` line numbers.

- `macos/Sources/Features/Ghostties/SessionCoordinator.swift`
- `macos/Sources/Features/Ghostties/WorkspaceStore.swift`
- `macos/Sources/Features/Ghostties/WorkspaceLayout.swift`
- `macos/Sources/Features/Ghostties/RecentsRowView.swift`
- `macos/Sources/Features/Ghostties/RecentsListView.swift`
- `macos/Sources/Features/Ghostties/ProjectDisclosureRow.swift`
- `macos/Sources/Features/Ghostties/SessionDetailView.swift`
- `macos/Sources/Features/Ghostties/TaskFileWatcher.swift`
- `macos/Sources/Features/Ghostties/PresetLoader.swift`
- `macos/Sources/Features/Ghostties/MenuBar/MenuBarController.swift`
- `macos/Sources/Features/Ghostties/MenuBar/MenuBarDropdownView.swift`
- `macos/Sources/Features/Ghostties/MenuBar/MenuBarIconRenderer.swift`
- `macos/Sources/Features/Ghostties/Models/AgentSession.swift`
- `macos/Sources/Features/Splits/SplitTree.swift`
- `macos/Sources/Ghostty/Ghostty.Surface.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (grepped for `surfaceModel`)
- `macos/Sources/App/macOS/AppDelegate.swift`
- `macos/Tests/Ghostties/SessionCoordinatorIndicatorCacheTests.swift`
- `macos/Ghostties.xcodeproj/project.pbxproj` (grepped for the `presets` folder reference)
- `DESIGN.md` (grepped for terracotta)
- `docs/plans/composer-ui-11/plan.md` and `docs/plans/composer-ui-11/findings-ledger.md` (shape precedent)

Read from this worktree's checkout:

- `docs/plans/session-row-status/draft-plan.md`
- `docs/plans/session-row-status/refutation.md`
- `docs/plans/session-row-status/refutation-appkit.md`
- `docs/plans/session-row-status-spec.html`

Memory and instruction files:

- `~/.claude/BREVITY.md`
- `MEMORY.md`, `agent-craft.md`, `decision_session-row-status-vocabulary.md`, `reference_indicator-state-two-cache-coupling.md`, `feedback_vacuous-tests-pass-green.md`, `feedback_ui-fixes-regress-each-other.md`

Not opened, and listed as assumptions: `Models/AgentTemplate.swift`, the whole-tree grep for the global indicator dict, and the Claude Code hooks reference beyond the facts the orchestrator verified.

---

Cut or demoted: the previous draft's launcher-script phases, its ancestor-walk port, and its "specified but not scheduled" Approve section are gone rather than demoted, because the foundation they stood on is dead. The full six-surface enumeration and the six colour-map sites sit inside Phase 2 rather than in a section of their own.
