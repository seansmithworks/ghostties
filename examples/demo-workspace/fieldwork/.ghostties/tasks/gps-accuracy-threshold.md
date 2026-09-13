---
title: "Confirm GPS accuracy threshold for field capture"
status: needs-you
created: 2026-05-12T10:00:00Z
project: fieldwork
source: linear
source-id: FWK-45
priority: high
needs: "What horizontal accuracy threshold should we require before accepting a GPS fix? Options: 5m (strict, slower), 20m (fast, good enough for most field use), or user-configurable. This gates the capture button UI state."
---

## Goal
Set the minimum acceptable horizontal accuracy for a GPS fix before allowing a location-tagged form submission.

## Notes
High-accuracy mode burns battery but is critical for surveying workflows. Lower threshold makes the app faster in urban canyons. Some customers do rough-proximity tagging, others need sub-10m. Might need per-form-type config.

## Activity
- 2026-05-12T10:00:00Z — Surfaced to product lead; blocked
- 2026-05-13T09:00:00Z — Added fallback to manual coordinate entry as stop-gap
