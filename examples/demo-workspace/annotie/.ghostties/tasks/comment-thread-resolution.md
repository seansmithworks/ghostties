---
title: "Add resolve/reopen flow for comment threads"
status: running
created: 2026-06-10T09:00:00Z
project: annotie
source: linear
source-id: ANT-51
priority: high
branch: feat/comment-resolution
worktree: ~/Code/annotie
files-staged: 3
---

## Goal
Let reviewers mark a comment thread as resolved so it collapses out of the active annotation list, with the option to reopen it if the concern resurfaces.

## Notes
Resolved threads still stored in the DB with `resolved_at` timestamp — never deleted. UI filters them to a "Resolved" section accessible via toggle. Resolving broadcasts a presence event so collaborators see the change without refresh. The annotation highlight for a resolved thread dims to 40% opacity in the viewer to signal it's been addressed.

## Activity
- 2026-06-10T09:00:00Z — DB schema updated: `resolved_at`, `resolved_by` columns on `comment_threads`
- 2026-06-12T14:30:00Z — Resolve button implemented, presence event broadcasting
- 2026-06-14T10:00:00Z — Highlight dimming on resolved threads applied in canvas layer
