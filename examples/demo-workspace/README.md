# Demo Workspace

Seed data for screen-recording, portfolio case studies, and social media promos.

## Projects

Seven real, public repos (`SeanSmithWorks/<name>` on GitHub), cloned at a
pinned commit SHA — see `DEMO_PROJECT_SPECS` in `scripts/demo/_demo-paths.sh`
for the exact repo/SHA/branch/ghost-character mapping.

| Repo | Domain |
|---|---|
| `ghostties/` | This fork itself, dogfooded as a fixture |
| `riff/` | (see repo) |
| `surface-fx/` | (see repo) |
| `colophon/` | (see repo) |
| `impeccable-swift/` | (see repo) |
| `agent-skills/` | (see repo) |
| `vista-sheet/` | (see repo) |

## How to load in Ghostties

These repos aren't opened directly from this checkout. `scripts/demo/seed-demo-workspace.sh`
clones each one (from a persistent local cache, so re-seeding doesn't re-download once a SHA
is cached) into `~/Library/Application Support/Ghostties Demo/repos/<name>/` at its pinned
commit, and points the demo app's `workspace.json` at those clones — so the demo doesn't
depend on this checkout's branch. See `scripts/demo/README.md` for the full refresh + seed
procedure.

## Note on task-first fixtures

Prior to 2026-09-13 this directory held 10 synthetic stub projects, each with a
`.ghostties/tasks/*.md` overlay (`atlas-api`, `pendulum`, `silo`, `wren`,
`switchboard`, `fieldwork`, `trove`, `brukas`, `annotie`, plus a copy of
`ghostties`) that fed `choreograph.sh` / `terminal-flow.sh` and a task-first
sidebar capture (Inbox/Backlog/Running/Needs You/Review/Graveyard zones).
Those stub dirs were removed when the fixture set switched to the 7 real
cloned repos above. **No replacement task-overlay content was authored for
the new repos** — `choreograph.sh`, `terminal-flow.sh`, and any task-first
zone capture are orphaned until someone decides whether to retire them or
author real `.ghostties/tasks/` content against one of the 7 repos.
