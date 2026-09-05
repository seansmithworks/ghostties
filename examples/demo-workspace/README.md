# Demo Workspace

Anonymized demo content for screen-recording, portfolio case studies, and social media promos. All project names, task titles, team references, and company names are fictional. Safe for public screenshots and video.

## Projects

Seven fictional projects across different domains:

| Directory | Domain |
|---|---|
| `atlas-api/` | Backend API service |
| `pendulum/` | Time-tracking mobile app |
| `silo/` | File storage and sync tool |
| `wren/` | Note-taking and writing app |
| `switchboard/` | Developer dashboard / webhook tool |
| `fieldwork/` | Location and field data capture app |
| `trove/` | Personal knowledge base app |

## How to load in Ghostties

Ghostties discovers projects automatically. Any directory containing a `.ghostties/tasks/` subfolder is recognized as a project — no registration required.

To load the demo workspace, open (or navigate to) each project folder in Ghostties:

```
examples/demo-workspace/atlas-api/
examples/demo-workspace/pendulum/
examples/demo-workspace/silo/
examples/demo-workspace/wren/
examples/demo-workspace/switchboard/
examples/demo-workspace/fieldwork/
examples/demo-workspace/trove/
```

Or open `examples/demo-workspace/` as a workspace root if Ghostties supports nested discovery from a parent.

## What this enables

| Capture moment | Coverage |
|---|---|
| Full ghost rail | 7 projects, each auto-assigned a named pixel-art ghost |
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

- Project discovery walks up from the opened directory, so each project folder must be opened individually if the app doesn't support recursive workspace scanning from a parent.
- The `worktree:` paths use `~` expansion (`~/Code/<project>`). If the app resolves these, they point to non-existent directories — this is expected for a fixture.
- PR URLs point to `github.com/example-org/*` which are fictional. These will 404 if opened in a browser.
- All dates are in the April–June 2026 range.
