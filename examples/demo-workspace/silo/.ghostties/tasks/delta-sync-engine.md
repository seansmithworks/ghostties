---
title: "Implement delta sync for large file trees"
status: running
created: 2026-05-10T09:00:00Z
project: silo
source: github
source-id: GH-112
priority: high
branch: feat/delta-sync
worktree: ~/Code/silo
files-staged: 8
---

## Goal
Replace full-tree hash comparison on sync with a delta approach that only transfers changed blocks, reducing sync time on large vaults by ~80%.

## Notes
Using rolling hash (Rabin fingerprint) for block deduplication. The tricky part is handling renames vs new file + delete. Content-addressed storage means renames are nearly free if the hash matches.

## Activity
- 2026-05-10T09:00:00Z — Designed block chunking strategy, target 4MB average chunk
- 2026-05-12T14:00:00Z — Implemented rolling hash chunker, passing unit tests
- 2026-05-14T11:30:00Z — Working on rename detection heuristic (same hash, different path)
- 2026-05-16T16:00:00Z — Integration tests running, ~73% reduction in bytes transferred on benchmark vault
