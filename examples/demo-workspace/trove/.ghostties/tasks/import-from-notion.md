---
title: "Notion import parser"
status: review
created: 2026-06-05T10:00:00Z
project: trove
source: github
source-id: GH-134
priority: medium
pr: 134
pr-state: open
pr-url: https://github.com/example-org/trove/pull/134
branch: feat/notion-import
---

## Goal
Parse Notion's HTML export format and convert it to Trove's internal note schema, preserving headings, callouts, tables, and inline code.

## Notes
Notion export is messy HTML — lots of non-semantic wrappers and proprietary data attributes. Using a two-pass parser: clean the HTML, then map to the ProseMirror document model. Callout block mapping is the hairiest part.

## Activity
- 2026-06-05T10:00:00Z — Parser scaffolded, handling headings/paragraphs/lists
- 2026-06-07T14:00:00Z — Table and code block support added
- 2026-06-09T10:00:00Z — PR open; callout mapping flagged for follow-up
