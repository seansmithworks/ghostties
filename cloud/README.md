# cloud

The backend the Ghostties web and mobile clients share, and that the Mac app
joins as a "desk". Prep only: schema, auth, realtime and the contract. No agent
runtime runs here yet.

| Path | What |
|---|---|
| `contract/` | `@ghostties/contract` (TS, for web) and `GhosttiesCloud` (Swift package, for the native iOS app and the Mac desk): row types, RPC signatures, realtime channels. No dependencies. |
| `supabase/migrations/` | Postgres schema, RLS, RPCs, realtime publication. Types mirror `contract/`; change both together. |
| `supabase/tests/` | Smoke test on plain Postgres: `PGHOST=… PGPORT=… bash cloud/supabase/tests/run-local.sh` |

## Model

- **Workspace** owns everything. A new account gets one with a chief of staff.
- **Desk**: a machine that hosts agents (the Mac app today, a cloud runner later). It connects outbound, so nothing needs an inbound port.
- **Agent**: `chief_of_staff` (one per workspace, no project) → `general_manager` (one per project) → `worker` (a session on a branch). Status uses the sidebar's vocabulary.
- **Conversation / Message**: a human talking to one agent. Messages are append-only; `client_id` makes sends idempotent.
- **Ask**: an agent waiting on a human. Open asks are the "needs you" list and drive push, sent straight to APNs.
- **Task**: the sidebar's lanes (`inbox … done`).

## Talking to it

- Reads: `supabase.from(table).select()`; RLS scopes to the caller's workspaces.
- Writes that matter go through RPCs (`send_message`, `start_conversation`, `answer_ask`, `register_push_token`, `desk_heartbeat`).
- Live: `postgres_changes` on `REALTIME_TABLES` filtered by `workspace_id`, plus a private `workspace:<id>` channel for typing, streamed replies and desk presence.

## Applying

`cd cloud && supabase link --project-ref <ref> && supabase db push`. Enable
email magic link, Apple and GitHub in Auth, and turn off public Realtime
channels in Realtime settings so the workspace channel policy is enforced.
