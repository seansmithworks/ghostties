---
title: "Validate customer address against service area radius"
status: backlog
created: 2026-05-20T11:00:00Z
project: brukas
source: linear
source-id: BRK-52
priority: medium
---

## Goal
Block booking attempts from addresses outside the configured service radius so dispatch doesn't get requests they can't fulfill.

## Notes
Each franchisee has a center lat/lng and radius in miles stored in `service_areas`. Haversine calculation on the server at quote-request time. Error state returns a user-friendly "We don't serve your area yet" message with a mailing-list signup. Edge case: customers on the exact boundary — round down (exclude) to keep dispatch manageable.

## Activity
- 2026-05-20T11:00:00Z — Added to backlog after multiple out-of-area bookings slipped through
