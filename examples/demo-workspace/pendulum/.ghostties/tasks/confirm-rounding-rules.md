---
title: "Confirm billing rounding rules for export"
status: needs-you
created: 2026-05-27T10:00:00Z
project: pendulum
source: linear
source-id: PND-51
priority: high
needs: "Should time entries round to the nearest 6 minutes (0.1h) or 15 minutes on export? This affects the invoice totals and I need to lock it before writing the export formatter."
---

## Goal
Lock the rounding increment used when exporting time entries to CSV/invoice format.

## Notes
Different accounting tools expect different granularities. Quickbooks wants 0.1h increments, some legal billing software wants 15-min blocks. Need a product decision before the export formatter branches.

## Activity
- 2026-05-27T10:00:00Z — Surfaced to product; blocked on decision
