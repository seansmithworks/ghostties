---
title: "Implement HMAC signature verification for inbound webhooks"
status: running
created: 2026-06-01T08:00:00Z
project: switchboard
source: linear
source-id: SWB-82
priority: high
branch: feat/webhook-hmac
worktree: ~/Code/switchboard
files-staged: 2
---

## Goal
Verify HMAC-SHA256 signatures on inbound webhook payloads to reject spoofed requests before they hit handler logic.

## Notes
Each integration (Stripe, GitHub, Shopify) uses a slightly different signing scheme. Building a pluggable verifier interface with per-integration adapters. Timing-safe comparison is mandatory to prevent timing attacks.

## Activity
- 2026-06-01T08:00:00Z — Scaffolded verifier interface
- 2026-06-03T11:00:00Z — Implemented Stripe and GitHub adapters
- 2026-06-05T14:30:00Z — Added constant-time comparison, unit tests passing
- 2026-07-06T00:00:00Z — Wired timingSafeEqual into verifySignature + added replay-window check (default 300s); 16-case verification script passing
