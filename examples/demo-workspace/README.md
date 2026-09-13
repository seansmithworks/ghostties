# Demo Workspace

Anonymized demo content for screen-recording, portfolio case studies, and social media promos. All project names, task titles, team references, and company names are fictional. Safe for public screenshots and video.

## Projects

Ten fictional projects across different domains:

| Directory | Domain |
|---|---|
| `atlas-api/` | Backend API service |
| `pendulum/` | Time-tracking mobile app |
| `silo/` | File storage and sync tool |
| `wren/` | Note-taking and writing app |
| `switchboard/` | Developer dashboard / webhook tool |
| `fieldwork/` | Location and field data capture app |
| `trove/` | Personal knowledge base app |
| `brukas/` | Booking / quoting app |
| `annotie/` | Document annotation and review tool |
| `ghostties/` | Ghostties itself, dogfooded as a fixture |

## How to load in Ghostties

These fixtures aren't opened directly from this checkout. `scripts/demo/seed-demo-workspace.sh`
copies each one into `~/Library/Application Support/Ghostties Demo/repos/<name>/`, turns it into
a real git repo, and points the demo app's `workspace.json` at those copies — so the demo doesn't
depend on this checkout's branch. See `scripts/demo/README.md` for the full refresh + seed
procedure.

## What this enables

| Capture moment | Coverage |
|---|---|
| Full ghost rail | 10 projects, each auto-assigned a named pixel-art ghost |
| All six zones | Inbox, Backlog, Running, Needs You, Review, Graveyard all populated |
| Terracotta Needs You cards | 4 tasks across 4 projects, each with a realistic blocking question |
| Running tasks with branches | 5 tasks with `branch:`, `worktree:`, `files-staged:` fields |
| Review tasks with PRs | 4 tasks with PR numbers, states, and URLs |
| Mixed sources | Linear (`ATL-*`, `PND-*`, `SWB-*`, `TRV-*`, `FWK-*`, `SLO-*`, `WRN-*`), GitHub (`GH-*`), Shell |
| Done / Graveyard | 4 completed tasks with timestamps |

## Task count by zone

| Zone | Count |
|---|---|
| Running | 5 |
| Needs You | 4 |
| Review | 4 |
| Inbox | 3 |
| Backlog | 2 |
| Done / Graveyard | 4 |
| **Total** | **22** |

## Assumptions

- The `worktree:` paths use `~` expansion (`~/Code/<project>`). If the app resolves these, they point to non-existent directories — this is expected for a fixture.
- PR URLs point to `github.com/example-org/*` which are fictional. These will 404 if opened in a browser.
- All dates are in the April–June 2026 range.
