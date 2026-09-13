---
title: "Build technician day-view schedule screen"
status: running
created: 2026-06-09T08:30:00Z
project: brukas
source: linear
source-id: BRK-61
priority: high
branch: feat/tech-schedule-view
worktree: ~/Code/brukas
files-staged: 4
---

## Goal
Give technicians a native mobile screen showing their jobs for the day — time slots, customer address, job type, and a one-tap nav button — so they don't need to call dispatch for their schedule.

## Notes
Timeline component renders 30-minute slots from 7am–7pm. Jobs snap to their start time and show duration as a colored block. Color encodes job category (plumbing = blue, electrical = orange, general = gray). Pulling schedule data from the existing `bookings` table filtered by `assigned_tech_id` and `date`. Conflict detection (overlapping jobs) will be a follow-up; out of scope here.

## Activity
- 2026-06-09T08:30:00Z — Timeline component scaffolded in React Native
- 2026-06-11T14:00:00Z — Job blocks rendering, category colors applied
- 2026-06-13T09:45:00Z — Nav deeplink to Apple Maps working on device
