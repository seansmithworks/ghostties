---
title: "Parse and expose rate-limit headers"
status: review
created: 2026-05-18T11:00:00Z
project: atlas-api
source: github
source-id: GH-47
priority: medium
pr: 47
pr-state: open
pr-url: https://github.com/example-org/atlas-api/pull/47
branch: feat/rate-limit-headers
---

## Goal
Read `X-RateLimit-Remaining` and `X-RateLimit-Reset` from API responses and surface them through the SDK client so callers can implement backoff logic.

## Notes
Headers are inconsistently named across v1 and v2 endpoints. Added a normalization layer in the response transformer. PR includes regression tests for both versions.

## Activity
- 2026-05-18T11:00:00Z — Implemented header parsing in response transformer
- 2026-05-19T09:45:00Z — Added tests, opened PR
- 2026-05-20T10:10:00Z — Addressed review comment on null handling when headers are absent
