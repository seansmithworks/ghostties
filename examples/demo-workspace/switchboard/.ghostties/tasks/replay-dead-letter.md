---
title: "Add replay UI for dead-letter queue"
status: needs-you
created: 2026-06-06T09:00:00Z
project: switchboard
source: linear
source-id: SWB-88
priority: medium
needs: "Should replay be automatic (retry on schedule) or manual (user clicks replay per event)? The queue drain strategy changes the UI significantly and affects how we store retry metadata."
---

## Goal
Let users inspect and replay failed webhook deliveries from the dead-letter queue without needing to re-trigger the source event.

## Notes
Failed events are already stored with payload + failure reason. Need to decide: automatic scheduled retry with exponential backoff, or a manual replay button in the dashboard. Both are reasonable but the data model differs.

## Activity
- 2026-06-06T09:00:00Z — DLQ storage in place, UI strategy unclear
- 2026-06-06T14:00:00Z — Blocked on product decision for retry strategy
