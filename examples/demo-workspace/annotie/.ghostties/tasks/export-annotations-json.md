---
title: "Export annotations as structured JSON for API consumers"
status: review
created: 2026-06-06T11:00:00Z
project: annotie
source: github
source-id: GH-62
priority: medium
pr: 62
pr-state: open
pr-url: https://github.com/example-org/annotie/pull/62
branch: feat/annotation-json-export
---

## Goal
Expose a `/documents/:id/annotations/export` endpoint that returns all annotations for a document as a typed JSON payload — type, page, bounding box, text, author, timestamps — so external tools can consume Annotie data without screen-scraping.

## Notes
Schema versioned from the start (`"schema_version": "1"`) to leave room for breaking changes. Highlights carry the selected text if available. Bounding boxes are in normalized coordinates (0.0–1.0 relative to page dimensions) so they're zoom-independent. Author is returned as a public-profile object — no email addresses in the export.

## Activity
- 2026-06-06T11:00:00Z — Endpoint scaffolded, schema designed
- 2026-06-09T14:00:00Z — All annotation types covered, tests written
- 2026-06-11T10:30:00Z — Opened PR; added schema_version field after reviewer request
