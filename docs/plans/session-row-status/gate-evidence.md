# Session-row status — Phase 0+1 gate evidence (2026-08-27)

Build plan: `docs/session-row-status-spec` branch, `docs/plans/session-row-status/plan.md`, section 3 — three build-time experiments (E1 TodoWrite payload, E2 permission prompt, E3 env reaches the hook). Measured live from Claude Code 2.1.247/2.1.248 with the hook registered in `~/.claude/settings.json` and a temporary probe line appending every payload to a log (since removed).

## E3 — PASS

7 sessions across 3 Dev-build launches reported their sidebar row's `GHOSTTIES_SESSION_ID` to the hook, all matched to rows in the Dev build's `workspace.json`.

- Agent template → `cco` → `claude()` shell function → worktree-isolated `claude`: rows `995A94F8` "Testing task lists", `1DF97DC2`, `EC115AB1`
- Plain shell template → `claude` typed by hand: `BD5CB38E` "Create d.txt with hi", `59D161DF` "Create f.txt with hi"
- Plain shell `echo $GHOSTTIES_SESSION_ID` printed `B6813E5E…` = row "Shell 40" (Phase 0 shell-template acceptance)

Phase 1 installer: on first launch of the build carrying `seedVersion = 2`, `~/.ghostties/hooks/.seed-version` went 1→2 and the seeded script was replaced by the bundle copy (md5 identical to source) — the app-owned overwrite path runs.

## E2 — measured, with one change to the plan

`PermissionRequest` fires and is the immediate signal (same second as the `PreToolUse` for the gated tool).

| Event | Keys | Timing | Notes |
|---|---|---|---|
| `PermissionRequest` | `cwd, effort, hook_event_name, permission_mode, permission_suggestions, prompt_id, session_id, tool_input, tool_name, transcript_path` | immediate | no `tool_use_id` |
| preceding `PreToolUse` | same + `tool_use_id` | immediate | same session, same `tool_name` |
| `Notification/permission_prompt` | `cwd, hook_event_name, message, notification_type, prompt_id, session_id, transcript_path` | ~6s later | no `tool_use_id`; did NOT fire when the prompt was answered within ~4s |
| `Notification/idle_prompt` | — | ~60s idle | — |

Consequence for Phase 2: `needsPermission` comes from `PermissionRequest` primarily, `Notification` secondarily; the identity for Phase 4's guard is the preceding `PreToolUse.tool_use_id` paired by `tool_name`, not a field on the request itself.

Rate: Sean's mode is `permission_mode: auto` with `Bash(*)` and `WebFetch(*)` allowed, so prompts occur only on classifier blocks or non-allowlisted tools (`Write` in default mode prompted; Bash never did). Over ~90 minutes of test sessions, 3 prompts, all deliberately provoked — no badge floor needed (plan §7 decision 5: no floor).

Side finding: the `ask: Bash(gh pr create:*)` rule never prompted — `gh pr create --help` ran unasked in default mode; `allow: Bash(*)` appears to swallow it.

## E1 — FAIL as specified; source must change

- `TodoWrite` is not in the main thread's tool list (a session did `ToolSearch select:TodoWrite` + a semantic search, found nothing, and fell back to Bash).
- `TaskCreate/TaskUpdate/TaskGet/TaskList` exist in the 2.1.247 binary but are not offered to the main thread either (confirmed from inside a live session).
- `~/.claude/tasks/` was last written 2026-08-15; `~/.claude/todos/` last written 2026-03-01.
- `TodoWrite` IS granted to subagents (`implementer`, `planner`).

Candidate sources for the Phase 3 second line, none yet chosen — **DECIDE, Sean**:

| Candidate | Description | Caveat |
|---|---|---|
| (a) | Subagent `TodoWrite` via the `PostToolUse` hook — a subagent inherits the env, so its payload would land in `<uuid>.todos.json` | unverified; it is the subagent's list, not the thread's |
| (b) | `Stop.last_assistant_message` | present on every Stop |
| (c) | `Stop.background_tasks` | array, present; empty in all observed Stops |
| (d) | Re-enable `~/.claude/tasks/<claude session_id>/<n>.json` | schema `{id, subject, description, activeForm, status, blocks, blockedBy}`, one file per task, rewritten in place (no rename), `.lock` + `.highwatermark` beside them; hook payload's `session_id` is the join key |

## Other measured payload facts for Phase 2's decoder

| Event | Keys |
|---|---|
| `UserPromptSubmit` | `cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id, transcript_path` |
| `PreToolUse` | adds `effort, tool_input, tool_name, tool_use_id` |
| `Stop` | `background_tasks, cwd, effort, hook_event_name, last_assistant_message, permission_mode, prompt_id, session_crons, session_id, stop_hook_active, transcript_path`; fires only at end of turn (verified: not while a permission prompt is pending) |
| `SessionEnd` | `cwd, hook_event_name, prompt_id, reason, session_id, transcript_path` (`reason: other` observed) |

Every payload carries Claude's own `session_id` and `cwd`. State files are last-event-wins per session; `.todos.json` is only written for `PostToolUse` + `TodoWrite`.

## Dev-only gotcha

Launching the Dev build with `open` from inside a Claude Code session passes that session's env to the app; its sessions then inherit `CLAUDE_CODE_CHILD_SESSION` ("Transcript saving is off"). Launch with `env -i HOME=… PATH=… open …` for realistic tests.
