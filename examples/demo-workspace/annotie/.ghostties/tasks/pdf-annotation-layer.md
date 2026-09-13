---
title: "Render annotation layer on top of PDF viewer"
status: done
created: 2026-05-02T10:00:00Z
project: annotie
source: linear
source-id: ANT-29
priority: high
pr: 29
pr-state: merged
pr-url: https://github.com/example-org/annotie/pull/29
completed: 2026-05-20T15:00:00Z
updated: 2026-05-20T15:00:00Z
---

## Goal
Overlay a transparent canvas on the PDF viewer so annotations (highlights, underlines, notes) composite correctly on top of the document without modifying the underlying PDF bytes.

## Notes
PDF rendered via pdf.js into a canvas element. Annotation layer is a second canvas positioned absolutely over it with `pointer-events: none` when not in edit mode. Z-index management was the main complexity — toolbar and annotation canvas needed separate stacking contexts. Hit-testing for selection uses the annotation store coordinates, not DOM events on the canvas.

## Activity
- 2026-05-02T10:00:00Z — Evaluated canvas vs. SVG overlay; canvas chosen for performance
- 2026-05-08T13:00:00Z — Overlay positioning stable across zoom levels
- 2026-05-14T11:00:00Z — Hit-testing implemented for annotation selection
- 2026-05-20T15:00:00Z — Merged after final review on scroll position edge case
