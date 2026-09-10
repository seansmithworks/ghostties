---
title: "Add live agent-count badge to the menu bar status item"
status: running
created: 2026-08-10T09:00:00Z
project: ghostties
source: linear
source-id: GHT-41
priority: medium
branch: feat/menubar-status-badge
worktree: ~/Code/ghostties
files-staged: 3
---

## Goal
Show a small count badge on the menu bar status item for sessions currently
in a "needs you" state, so the signal is visible without opening the window.

## Notes
Badge should clear itself the moment the underlying session's indicator
state changes away from `.waiting`. Avoid polling — hook into the existing
`@Published` session state instead.

## Activity
- 2026-08-10T09:00:00Z — Scaffolded MenuBarController
- 2026-08-14T15:00:00Z — Badge renders, count updates on state change
