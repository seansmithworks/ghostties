---
title: "Add webhook endpoint health check probing"
status: backlog
created: 2026-05-12T10:00:00Z
project: switchboard
source: linear
source-id: SWB-90
priority: medium
---

## Goal
Periodically probe registered webhook endpoints with a lightweight ping request so the dashboard can surface unreachable destinations before live deliveries fail.

## Notes
Probe cadence: every 5 minutes per endpoint. Expected response: any 2xx within 5 seconds. Three consecutive failures flip status to "unhealthy" and trigger a dashboard alert. Avoid probing endpoints that have been manually paused. Probe requests should include a distinguishing header (X-Switchboard-Probe: true) so customers can handle them separately in their own logic.

## Activity
- 2026-05-12T10:00:00Z — Added to backlog after support tickets for silent delivery failures to stale endpoints
