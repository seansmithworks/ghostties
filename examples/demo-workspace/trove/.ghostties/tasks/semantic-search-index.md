---
title: "Build semantic search index with embeddings"
status: running
created: 2026-05-30T09:00:00Z
project: trove
source: linear
source-id: TRV-71
priority: high
branch: feat/semantic-search
worktree: ~/Code/trove
files-staged: 4
---

## Goal
Generate embeddings for all notes and enable vector-similarity search so users can find conceptually related content, not just keyword matches.

## Notes
Using OpenAI `text-embedding-3-small` for cost efficiency. Vectors stored in pgvector. Re-indexing on note save via a background queue to avoid blocking the write path. Chunking long notes into 512-token segments.

## Activity
- 2026-05-30T09:00:00Z — pgvector extension enabled, embeddings table created
- 2026-06-01T11:00:00Z — Background indexer implemented, processing backfill job
- 2026-06-03T15:00:00Z — Search endpoint working, tuning similarity threshold (currently 0.78)
