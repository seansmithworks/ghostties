---
title: "Background sync for running timers"
status: running
created: 2026-05-22T13:00:00Z
project: pendulum
source: linear
source-id: PND-44
priority: high
branch: feat/background-sync
worktree: ~/Code/pendulum
files-staged: 5
---

## Goal
Keep timers ticking accurately when the app is backgrounded on iOS. Currently the elapsed time jumps forward on foreground if the device was locked.

## Notes
Using `UIApplication.backgroundTask` + storing a start timestamp in UserDefaults. Need to reconcile with the local SQLite state on foreground. BGAppRefreshTask probably overkill here.

## Activity
- 2026-05-22T13:00:00Z — Identified delta-time bug in foreground observer
- 2026-05-23T09:00:00Z — Implemented timestamp-based elapsed calculation
- 2026-05-24T16:30:00Z — Works for lock/unlock, still testing airplane mode edge case
