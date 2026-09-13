---
title: "Wire token refresh interceptor"
status: running
created: 2026-05-14T09:00:00Z
project: atlas-api
source: linear
source-id: ATL-28
priority: high
branch: feat/auth-interceptor
worktree: ~/Code/atlas-api
files-staged: 3
---

## Goal
Implement an Axios interceptor that silently refreshes the access token on 401 responses and retries the original request with the new token.

## Notes
Using a request queue pattern to avoid parallel refresh calls racing each other. Interceptor lives in `src/api/interceptors/auth.ts`.

## Activity
- 2026-05-14T09:00:00Z — Scaffolded interceptor file, wired into Axios instance
- 2026-05-15T10:30:00Z — Added queue drain logic for concurrent requests during refresh
- 2026-05-16T14:12:00Z — Unit tests passing, integration test still flaky on fast refresh sequences
