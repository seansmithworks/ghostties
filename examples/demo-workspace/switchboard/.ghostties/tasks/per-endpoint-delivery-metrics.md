---
title: "Expose per-endpoint delivery success metrics"
status: review
created: 2026-06-08T09:00:00Z
project: switchboard
source: github
source-id: GH-74
priority: medium
pr: 74
pr-state: open
pr-url: https://github.com/example-org/switchboard/pull/74
branch: feat/endpoint-delivery-metrics
---

## Goal
Surface per-endpoint delivery success rate, p95 latency, and error breakdown in the dashboard so teams can identify degraded destinations without digging through raw logs.

## Notes
Metrics are computed from the existing delivery_attempts table using a 24h rolling window. Added a materialized view (endpoint_delivery_stats) that refreshes every 60 seconds. Dashboard panel uses a bar chart for success vs. failure count and a sparkline for latency trend. No new data collection required.

## Activity
- 2026-06-08T09:00:00Z — Materialized view created, query plan confirmed index-only scan on delivery_attempts(endpoint_id, attempted_at)
- 2026-06-10T14:00:00Z — Dashboard panel built, connected to stats view, screenshots shared in PR
- 2026-06-11T10:30:00Z — Addressed review comment on refresh interval: switched from 30s to 60s after load testing showed contention at 30s under high write volume
