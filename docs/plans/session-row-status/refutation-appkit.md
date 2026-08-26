# Refutation — session-row-status draft plan (AppKit / macOS-systems lens)

Target ref `origin/main` @ `89e6dfb945e2d2a3622268adb6328555f574c8f5`. All `macos/` citations read from the `origin/main` object store. Live-machine measurements taken 2026-08-26 with Ghostties.app running as pid 1288.

---

## 1. WRONG

### F1 — Step 1.1's acceptance criterion is unsatisfiable by step 1.1's own change

Plan 1.1: "Restructure so the wrapper is written whenever `resolvedCommand` is non-nil." Acceptance: "launch two sessions, one from an agent template and one from the **shell template** … returns 2 files."

`SessionCoordinator.swift:189-191` decides `resolvedCommand` before the launcher block, and the comment states the outcome verbatim: "For shell templates (no command), resolvedCommand stays nil -> default shell." — followed by `guard template.command != nil else { return nil }`.

`AgentTemplate.command` is `String?` (`Models/AgentTemplate.swift:26`) and is nil for the shell kind. So for a shell template `resolvedCommand == nil`, and `guard let cmd = resolvedCommand else { return nil }` (`:224`) short-circuits before the `launchBanner` gate the step proposes to move. The change is a no-op for exactly the template its acceptance criterion demands a file for.

Making it true requires synthesizing a command for shell sessions (`exec $SHELL -l`), which changes Ghostty's default-shell path — login-shell semantics, `SHELL` resolution, the `exec -l` wrapper visible in the live process tree. That is not a restructure; it is a behavior change at the upstream seam the plan puts out of scope.

**Consequence:** Phase 1 opens with a step that cannot pass its own test, and the coverage number every later phase depends on never moves.

### F2 — The launcher UUID is in argv only by accident of Sean's `~/.zshrc`

The wrapper's last line is `exec <cmd>` (`SessionCoordinator.swift:236`). `exec` replaces the process — after it runs, argv is the target's argv and the `<uuid>.sh` token is gone from the entire tree.

It has not run, for a reason unrelated to the design. `AgentTemplate.buildCommand()` shell-escapes the command before anything else (`Models/AgentTemplate.swift:234-236`), so the first token is `'claude'` **including the quote characters**. `SessionCoordinator.swift:200-207` takes `built.prefix(while: { !$0.isWhitespace })` as the base command and hands that quoted token to `resolveCommand`, which tests `~/.local/bin/'claude'` and friends for executability (`:930-946`), finds nothing, and returns the token unchanged. A live script on disk confirms it: line 5 reads `exec 'claude' --model 'opus' …`, unresolved. Line 2 of the same script is `. ~/.zshrc`, which defines Sean's `claude()` collision-guard function — so `exec` resolves to a shell function, does not replace the process, and the wrapper `zsh` survives as claude's parent.

Measured ancestor chains for all 11 live `claude` processes:

- 1 of 11 has an ancestor whose argv contains a launcher path (`/bin/zsh -l ~/.ghostties/cache/launchers/AEA48312-….sh`), and that one belongs to a *sibling worktree's* Dev build, not to pid 1288.
- 10 of 11 have the chain `claude` ← `-/bin/zsh` ← `/usr/bin/login … exec -l /bin/zsh` ← `/Applications/Ghostties.app/Contents/MacOS/ghostty`. No uuid at any depth.

**Consequence:** the join works on one machine, for one command shape, because of a quoting bug. Fixing that quoting bug — an obvious future cleanup, since `resolveCommand` exists precisely to produce an absolute path — restores `exec`, erases the uuid from argv, and kills the status feature silently, with no compile error and no failing test.

### F3 — The joinable set and the status-file set are currently disjoint

Plan 1.3 acceptance: "printing joined-count over total-sessions. Target is 10/10."

- The one process with a launcher ancestor (pid 68424) has **no** `.json` in `~/.claude/sessions/`. It has only a `.key` file. Its argv carries no `--remote-*` flag.
- All 10 processes that *do* have a `.json` are the ones with no launcher ancestor. Every one of the 10 reads `entrypoint: cli`, `kind: interactive`, carries a non-nil `bridgeSessionId`, and carries a `--remote-*` flag in argv.

So the intersection of "resolvable by the plan's join" and "has a status payload" is currently **zero**, and whether a session gets a `.json` at all appears to depend on a flag Ghostties does not pass. The acceptance criterion measures a ratio across two sets that do not overlap; it can print 10/10 only if both halves change.

**Consequence:** Phase 1 can be fully implemented, pass its unit tests, and join nothing.

### F4 — `TaskFileWatcher` structurally cannot see a status flip

`TaskFileWatcher` opens **one directory** fd `O_EVTONLY` and takes `[.write, .extend, .rename, .delete, .attrib]` on it (`TaskFileWatcher.swift:58-72`). A directory vnode fires on entry add/remove/rename. It does not fire when a child file is modified in place, because no directory entry changes.

Measured on every `~/.claude/sessions/*.json`: inode stable, birth time hours older than mtime (one file born 22,105 s before its last write, same inode). Atomic replace would produce a fresh inode with birth == mtime on every write. It does not. These files are written **in place**.

**Consequence:** the watcher fires when a session appears or disappears and never again. Combined with the plan's own Risks mitigation — "read only on `TaskFileWatcher` change, caching the parsed map, and letting the tick read the cache" — the shipped indicator freezes at whatever the file said when the session first appeared. That is worse than the heuristic it replaces, and the failure is invisible to a unit test that injects a stub store.

### F5 — Phase 2 is not "no new UI"; Phase 1 alone reorganizes the sidebar

Plan Phase 2: "No new UI. The glyph already tints from `globalIndicatorStates` … This phase is one screenshot pass and one deletion."

`globalIndicatorStates` is not a tint channel. It is section membership:

- `WorkspaceStore.isActiveIndicatorState` (`:1080-1087`) gates project bucketing in `computeSectionedProjects` (`:1141-1143`) and session bucketing into active/recent/idle (`:1224`).
- `RecentsListView.activeSessions` / `inactiveSessions` / `archiveSessions` (`:216, :228, :239`) are pure functions of it — which section a row lives in.
- `WorkspaceStore.swift:574` and `:596` stamp the per-project grace tracker from it.
- `MenuBarController.swift:26` subscribes to `$globalIndicatorStates` for the menu-bar icon, and `MenuBarDropdownView.swift:70, :137` renders rows from it. **The menu bar is a third status surface the plan never names.**
- The `didSet` at `WorkspaceStore.swift:58-62` clears `sessionGroupsCache` and invalidates the sectioned-projects cache on every write.

The code comment at `RecentsListView.swift:212-221` spells out the hazard being reintroduced: rows jumping between sections and "everything below them shift ~38pt" was "exactly the 'rows reshuffling under the cursor' problem this feature set removed."

**Consequence:** the change billed as pixel-neutral changes list membership, ordering, the grace window, and the menu bar. It needs its own review round, not a screenshot pass.

### F6 — The 1.4 branch placement contradicts the plan's own out-of-scope note and puts file work on the render path

Plan: "Add the Claude read as a **branch inside `indicatorState(for:)`'s `.running` case** … Nothing else changes, so both caches stay coherent by construction." Out of scope: "Phase 4 reads the store for its own new count and **touches neither call site**."

`indicatorState(for:)` has two direct callers outside the tick, both in the render path:

- `ProjectDisclosureRow.swift:177` — `indicatorState: coordinator.indicatorState(for: session.id)`, passed into each child row.
- `ProjectDisclosureRow.swift:413` — `projectHeaderIndicator` maps it over **every session in the project** inside a computed property read during `body`.

So the branch is touched by both call sites, at body-evaluation frequency, on the main actor. The coherence claim is correct for the tick and false for the view path: the two tabs already read different sources, and a file-backed branch makes them diverge in time as well as value. `MEMORY.md` already names per-row `ProjectDisclosureRow` render cost as the second bottleneck.

### F7 — The "honest downgrade" has no delta to buy

`indicatorState(for:)` today, for an agent-kind session (`:1345-1372`): output within `activityThreshold` = 2 s (`:88`) yields `.processing` (or `.longRunning` past 1800 s); silence yields `.idle` via the `isAgentKindSession` branch. The plan's mapping is `busy → .processing`, `idle → .idle`, with `needsAttention`/`waiting` left on the heuristics.

That is the same two-state output, from a slower and (per F4) unobservable source, in exchange for a launcher-gate rewrite, a `sysctl` port from another repo, a new store, and a new watcher. The pty is a real-time signal; the file is not.

### F8 — The mixed dot fails on light chrome by arithmetic, and the sidebar has no dots

Composite of gold `#FFC400` at 35 % over chrome light `#F0E9E6` (`WorkspaceLayout.swift:139`): ≈ (245, 220, 150) against a (240, 233, 230) ground — a luminance ratio near 1.05:1. Not "hard to read"; not there. The same composite over chrome dark `NSColor(white: 0.14)` (`:142`) is ≈ (112, 92, 23) against (36, 36, 36) and reads clearly. A token that survives one theme only is not shippable against the Round-4 lock that both themes follow system.

Separately, the shape is wrong for the surface. There is no status dot in this sidebar: session rows draw `GhostCharacterView` at `sessionGhostSize = 14` (`WorkspaceLayout.swift:260`, used at `RecentsRowView.swift:53-56`) and the project header draws a 12 × 12 ghost (`ProjectDisclosureRow.swift:330-335`). A 7 pt two-tone circle introduces a primitive the vocabulary does not contain, sitting next to a glyph that already carries the same colour.

**Consequence:** the plan's legibility gate is well-designed and will fail. Running it costs a build cycle to learn what the composite arithmetic already says.

---

## 2. MISSING

### F9 — `RecentsRowView` is manually `Equatable` and the caller applies `.equatable()`

`static func ==` at `RecentsRowView.swift:42-48` compares exactly `session`, `projectName`, `indicatorState`, `isActive`, `isEditing`. `RecentsListView.swift:167` applies `.equatable()`. Phase 3's breakdown line arrives as a new input; if it is not added to `==`, the row renders once and freezes — the same failure family as the `LazyVStack` freeze in `reference_sidebar-rows-frozen-lazyvstack.md`, and one no unit test on a `ClaudeTaskStore` can catch. The plan never mentions the comparator.

### F10 — Neither new element reaches VoiceOver

`RecentsRowView` ends `.accessibilityElement(children: .combine)` + `.accessibilityLabel(accessibilityLabel)` (`:112-113`), and `ProjectDisclosureRow` hardcodes `.accessibilityLabel("<name> project, expanded/collapsed")` (`:393`). A combined element discards child text. The breakdown line and "N need you" both need explicit label changes or they do not exist for a screen reader. `CLAUDE.md` declares `a11y` as a design layer for this repo.

### F11 — Phase 4's trailing badge lands inside a `Button`

The whole project header is a `Button` whose label carries `.contentShape(Rectangle())` (`ProjectDisclosureRow.swift:356-364`). A badge placed in that HStack inherits the disclosure toggle; clicking "2 need you" collapses the group. If it is decorative, say so; if it is meant to navigate, it has to sit outside the button.

The plan's stated reason for reading the store — "so the number and the tint cannot disagree" — picks one of two tints. The header carries both: the ghost from `store.projectGhostColor(for:)` (`:330-334`) and the chevron from `coordinator.indicatorState(for:)` via `projectHeaderIndicator` (`:406-410`). Reading the store aligns the count with the ghost and leaves it free to disagree with the chevron.

### F12 — "The project name is already implied by the tab's grouping" is false

The Sessions tab groups by **indicator state**, not by project: `activeSessions` / `inactiveSessions` / `archiveSessions` (`RecentsListView.swift:216-243`), each a pure function of `globalIndicatorStates`. Rows from different projects interleave inside every bucket — which is why the row carries `projectName` at all (`RecentsRowView.swift:3-5`). Replacing that line deletes the only project attribution on the tab, for a user who runs 2-7 sessions across several worktrees.

### F13 — Split sessions have no root leaf

ASSUMPTION 5 is filed under "Capability confirmed." `SplitTree.root` is `Node?`, and `Node` is `.leaf(view:)` **or** `.split(Split)` (`SplitTree.swift:15-25`); a split session's root is a `.split` with no `surfaceModel` on it, and `zoomed: Node?` is a separate concept (`:11-13`). "`sessionTrees[id]` → `SplitTree.root` → `surfaceModel`" is not a path for any session the user has split. Parked or not, do not carry this forward as confirmed.

### F14 — No failure mode for pid reuse

`~/.claude/sessions/` is keyed by pid, and pids recycle. The abstain rule covers "not joined"; nothing covers "joined to the wrong process." The session file carries `procStart` — that is the disambiguator, and it is unused in the plan.

---

## 3. OVERVALUED / GOLD-PLATED

### F15 — The ancestor walk (1.2) and the gate rewrite (1.1) are both unnecessary; one env var replaces them

Cut step 1.1 and most of 1.2.

`SessionCoordinator.createSession` already writes environment variables into every surface config, unconditionally, for every template including shell — `config.environmentVariables = template.environmentVariables`, then `GHOSTTIES_TASK_FILE` and `GHOSTTIES_TASK_ID` overlays (`SessionCoordinator.swift:247-256`).

Adding `config.environmentVariables["GHOSTTIES_SESSION_ID"] = session.id.uuidString` there is one line, and is strictly better than the argv route on every axis:

- **Environment survives `exec`; an argv token does not.** F2's failure mode disappears by construction.
- It covers sessions the sidebar did not launch the agent in — a `claude` the user types into a shell surface an hour later inherits it. The launcher script can never cover that case, so 1.1 could not have reached full coverage even with F1 fixed.
- No launcher-script lifecycle coupling: no `launchBanner` gate, no teardown delete (`:997-1000`), no 24 h sweep (`:1007-1025`) able to break the join.
- **No ppid walk.** `KERN_PROCARGS2` returns argv *and* envp in one buffer; the read is one `sysctl` per candidate pid, not a chain.

And the entitlement question the plan reserved as its biggest unknown is a non-issue: there is **no `com.apple.security.app-sandbox` key in any entitlements file on `origin/main`** — `Ghostties.entitlements`, `GhosttyDebug.entitlements`, `GhosttyReleaseLocal.entitlements`, `GhosttiesHelper.entitlements`. The only sandbox string in `project.pbxproj` is `ENABLE_USER_SCRIPT_SANDBOXING`, a build-phase setting with no runtime effect. `ENABLE_HARDENED_RUNTIME = YES` with Developer ID signing (`project.pbxproj:1326-1334`) constrains code loading and debugging, not same-uid `KERN_PROC_ARGS`. Reading argv and envp of another process owned by the same user works.

### F16 — Phase 3 is blocked on the wrong evidence, and it is the thing Sean actually asked for

Sean's request leads with "how do you see what is done and not done?" The plan parks that behind "both return 0 of 10."

I reproduced the 0/10 (both `~/.claude/todos/` and `~/.claude/tasks/<sessionId>/`, matched on `sessionId` *and* `bridgeSessionId`), and `~/.claude/tasks/` has zero directories touched in 24 h — newest is ~10.7 days old. The plan's reading of those two stores is correct.

But 0/10 across two dormant stores does not establish "no todo data exists." It establishes that neither is the live store. The live one is `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` — **106 transcripts written in the last 24 h, several updated within the last minute, and 8 of the 12 most recent contain `TodoWrite` payloads.** The plan never enumerated `~/.claude/projects/`, though its own "What I opened" lists a live-data sweep of four other paths under `~/.claude/`.

Two properties make it the better target:
- The directory name is the **encoded cwd**, and cwd→project is the join this project already verified exact (`project_switchboard-phase0-verdict.md`, 11/11).
- The file is **append-only**, so a `DispatchSource` on the file fd with `.extend` genuinely fires — unlike F4's directory watcher over in-place-written JSON.

Cost is real (replay the last `TodoWrite` call rather than read a state object; tail rather than re-read), but bounded, and it is the difference between shipping decision 3 and parking it.

### F17 — Phase 5's specification is longer than the decision needs

Phase 5 plus its Risks bullet spends ~15 lines specifying a button that is explicitly not scheduled. Parking is right; the shippable half is one sentence — "no structured-prompt source exists; decision 5 ships as *Answer in terminal*, which is `coordinator.focusSession(id:)`." Cut the rest until a source exists.

---

## 4. EVIDENCE

### F18 — The plan reserved its assumption slot for the wrong risk

ASSUMPTION 4 names entitlements as the thing that, if false, means "the whole join dies." It is one object-store read away, and the answer is that it works (F15). Meanwhile the assumption that actually kills the join — that the uuid is present in some ancestor's argv — is not in the assumptions list at all. It is filed as *acceptance criteria for future work*: "a manual check that `ps auxww` … shows a launcher path for a freshly launched session." That check was available before planning and was not run. Run now: 1 of 11.

### F19 — Listing the launcher directory cannot measure join coverage

Both the plan ("the directory holds 4 scripts against 10 live Claude sessions") and the spec ("only 8 of 13 live sessions have it today") count **scripts on disk** and treat the count as join coverage. Script-on-disk and uuid-in-argv are different measurements; on this machine they are 4 and 1. Every coverage number in both documents is produced by an instrument that cannot see the quantity being claimed.

### F20 — The spec's "13/13 after closing the gate" is inherited, not re-derived

The plan corrects the spec on colours, on the `WorkspaceStore.swift:1004` line number, and on the stale blue-ghost evidence — all good — then adopts the spec's coverage *method* unchanged and restates it with fresher numbers. `feedback_re-measure-at-claim-time.md` applies to method as much as to values.

### F21 — The todo-store search stopped at the second candidate

`reference_claude-todo-data-source.md` names `~/.claude/todos/`. The plan proved it dead, found `~/.claude/tasks/`, proved that dormant too, and concluded the feature has no source — without asking where a currently-running CLI writes todo state. It writes it into the transcript (F16). Two dead stores is a signal to widen the search, not to stop.

### F22 — The plan kills decision 1's premise and then implements decision 1 anyway

The plan correctly reports that the polarity fix already shipped and that `indicatorState(for:)` now returns `.idle`, not `.waiting`, for silent agent sessions (`SessionCoordinator.swift:1362-1371`). The spec's decision 1 — "read, don't infer" — was approved on the strength of "0 of 11 genuinely-waiting sessions were actually waiting," i.e. on the bug that has since been fixed. The plan notes the staleness in a two-line aside and then builds the whole of Phase 1 to satisfy the decision. If the evidence that bought the approval is gone, that goes back to Sean as one line; it does not get implemented on inertia.

---

## 5. WEAKEST ASSUMPTION

Not ASSUMPTION 4. The load-bearing one is unstated:

> **A launcher script existing on disk for session X means X's process tree carries X's uuid.**

Every coverage number in the plan and the spec is derived from it, Phase 1 exists to raise the number it produces, and Phases 2-4 have nothing to draw without it.

It is false for 10 of 11 live sessions, and true for the 11th only because `buildCommand()` shell-escapes the command into `'claude'`, which defeats `resolveCommand`, which leaves `exec 'claude'` resolving to a zsh function defined by the user's own dotfile, which is the only reason the wrapper process is still alive to hold the argv. Fix any one of those three unrelated things and the last joinable session stops joining.

If it is false: 1.1 changes nothing measurable, 1.2 ships a `sysctl` port that returns nil for every session, 1.3's store has no key to look up, 1.4 has no branch to take, Phase 2 has nothing new to screenshot, and Phases 3-4 draw an aggregate over an empty set.

---

## VERDICT

**Rethink.** Phases 1 and 2 rest on a join that does not resolve and a watcher that cannot fire; Phase 3 — the half of the request Sean led with — is parked on a search that stopped one directory short.

**The single most important change:** drop the launcher-UUID argv join entirely. Inject `GHOSTTIES_SESSION_ID = session.id.uuidString` into `config.environmentVariables` at `SessionCoordinator.swift:247` — one line, every template, inherited across `exec` and by every descendant — and read it back from `KERN_PROCARGS2`'s envp with a single `sysctl` per candidate pid. That deletes step 1.1, most of 1.2, the launcher-lifecycle coupling, and the entitlements question in one move. Then point the status read at a source whose changes a `DispatchSource` can actually observe, and unblock the breakdown line against `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`.
