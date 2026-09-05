---
title: "Enforce payload log retention policy"
status: done
created: 2026-04-25T09:00:00Z
project: switchboard
source: linear
source-id: SWB-61
priority: medium
pr: 61
pr-state: merged
pr-url: https://github.com/example-org/switchboard/pull/61
completed: 2026-05-08T13:00:00Z
updated: 2026-05-08T13:00:00Z
---

## Goal
Automatically delete webhook payload logs older than 90 days (or per-workspace retention setting) to comply with data minimization requirements.

## Notes
Implemented as a nightly cron job using a soft-delete pattern. Workspace admins can configure 30/60/90-day windows. Hard delete runs 7 days after soft delete to allow accidental recovery.

## Activity
- 2026-04-25T09:00:00Z — Retention policy spec written
- 2026-04-28T14:00:00Z — Cron job implemented and tested on staging
- 2026-05-05T10:00:00Z — Admin UI for workspace retention setting shipped
- 2026-05-08T13:00:00Z — Merged and verified in production
