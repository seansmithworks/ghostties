---
title: "Confirm token expiry behavior with backend"
status: needs-you
created: 2026-05-14T09:22:00Z
project: atlas-api
source: linear
source-id: ATL-31
priority: high
needs: "Do we silently refresh or force re-auth after 24h? Need to know before I wire the interceptor logic for long sessions."
---

## Goal
Clarify token refresh strategy so the auth interceptor handles long-lived sessions correctly.

## Notes
Two options on the table: silent refresh via refresh token, or hard re-auth modal at expiry. Backend team needs to decide before I branch the interceptor logic.

## Activity
- 2026-05-14T09:22:00Z — Opened question with backend team in Slack
- 2026-05-14T11:05:00Z — Blocked, awaiting response from @jared
