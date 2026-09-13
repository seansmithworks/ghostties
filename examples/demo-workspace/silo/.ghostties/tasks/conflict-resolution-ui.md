---
title: "Design conflict resolution modal"
status: needs-you
created: 2026-05-20T09:00:00Z
project: silo
source: linear
source-id: SLO-67
priority: medium
needs: "When two devices edit the same file offline, should we auto-merge (last-write-wins), show a diff UI, or keep both versions as fork copies? This is a product call that blocks the sync engine's conflict handler."
---

## Goal
Define the conflict resolution strategy so the sync engine knows what to do when it detects a diverged file.

## Notes
Last-write-wins is simplest but loses data silently. Diff UI is best UX but complex to build. Fork copies (both kept with a suffix) is a safe middle ground. Dropbox and iCloud use different strategies.

## Activity
- 2026-05-20T09:00:00Z — Conflict scenario documented, three options sketched
- 2026-05-21T11:00:00Z — Awaiting product direction before implementing handler
