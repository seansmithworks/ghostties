---
title: "Offline form submission queue"
status: running
created: 2026-05-05T08:00:00Z
project: fieldwork
source: linear
source-id: FWK-39
priority: high
branch: feat/offline-queue
worktree: ~/Code/fieldwork
files-staged: 6
---

## Goal
Queue form submissions locally when the device has no connectivity and sync them to the server when a connection is restored.

## Notes
Using SQLite as the local queue store. NetworkMonitor watches reachability via NWPathMonitor. On reconnect, submissions drain in FIFO order with retry on 5xx. Conflict detection needed for forms that reference server-side IDs.

## Activity
- 2026-05-05T08:00:00Z — Local queue store scaffolded with SQLite
- 2026-05-07T11:00:00Z — NWPathMonitor integration done, queue drains on reconnect
- 2026-05-09T15:00:00Z — Testing conflict edge case: form references deleted resource on server
