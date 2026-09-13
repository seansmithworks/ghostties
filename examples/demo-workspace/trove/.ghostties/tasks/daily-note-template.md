---
title: "Daily note auto-creation with template"
status: done
created: 2026-04-20T09:00:00Z
project: trove
source: shell
priority: medium
completed: 2026-04-30T14:00:00Z
updated: 2026-04-30T14:00:00Z
---

## Goal
Automatically create a new note for today's date when the user opens the app, pre-filled with their selected daily note template.

## Notes
Template uses Handlebars-style tokens: `{{date}}`, `{{day}}`, `{{week_number}}`. Notes are created idempotently — opening the app twice on the same day doesn't create duplicates. Default template ships with three sections: Goals, Log, Reflection.

## Activity
- 2026-04-20T09:00:00Z — Designed template token system
- 2026-04-22T11:00:00Z — Implemented idempotent daily note creation on app launch
- 2026-04-25T14:00:00Z — Template editor UI shipped
- 2026-04-30T14:00:00Z — Shipped to production, well received in beta
