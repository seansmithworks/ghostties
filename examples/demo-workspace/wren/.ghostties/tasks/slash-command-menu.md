---
title: "Build slash-command insertion menu"
status: review
created: 2026-05-28T09:00:00Z
project: wren
source: github
source-id: GH-201
priority: medium
pr: 201
pr-state: open
pr-url: https://github.com/example-org/wren/pull/201
branch: feat/slash-commands
---

## Goal
Trigger a floating command palette when the user types `/` at the start of a line, allowing insertion of headings, callouts, code blocks, and embeds.

## Notes
Built on top of the ProseMirror plugin system. Filtering is fuzzy-matched client-side. Arrow-key navigation and Escape to dismiss are wired. Accessibility review still pending.

## Activity
- 2026-05-28T09:00:00Z — Core plugin scaffolded
- 2026-05-30T14:00:00Z — Fuzzy filter and keyboard nav implemented
- 2026-06-02T10:00:00Z — PR opened for review
- 2026-06-04T09:30:00Z — Addressed reviewer feedback on focus trap handling
