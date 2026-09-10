---
title: "Surface document version history with annotation diffs"
status: needs-you
created: 2026-06-13T10:00:00Z
project: annotie
source: linear
source-id: ANT-57
priority: medium
needs: "Should version history be tied to explicit saves (user clicks 'Save version') or automatic snapshots on a time interval? Explicit saves are less surprising but rely on users remembering to save; automatic snapshots are seamless but could create a lot of noise for active documents."
---

## Goal
Let users browse previous versions of a document and see which annotations were added, modified, or resolved between versions — without losing the current state.

## Notes
Annotation store already writes immutable event records, so reconstructing historical state is feasible. The open question is what triggers a new version entry in the history index. Once that's settled, the diff view is a straightforward before/after comparison of annotation sets keyed by `annotation_id`.

## Activity
- 2026-06-13T10:00:00Z — Versioning approach designed; blocked on save-trigger decision
- 2026-06-13T17:00:00Z — Mockups shared in Linear; both models mocked, awaiting product call
