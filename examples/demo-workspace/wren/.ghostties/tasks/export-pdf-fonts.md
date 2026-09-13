---
title: "Fix font embedding in PDF export"
status: done
created: 2026-04-18T10:00:00Z
project: wren
source: github
source-id: GH-178
priority: high
pr: 178
pr-state: merged
pr-url: https://github.com/example-org/wren/pull/178
completed: 2026-04-26T11:00:00Z
updated: 2026-04-26T11:00:00Z
---

## Goal
Exported PDFs were rendering fallback system fonts instead of the document's selected typeface. Embed fonts correctly in the PDF output.

## Notes
Root cause: Puppeteer's PDF renderer wasn't waiting for @font-face resources to load before capturing. Fixed by waiting for `document.fonts.ready` before triggering print.

## Activity
- 2026-04-18T10:00:00Z — Bug reported by multiple users
- 2026-04-20T14:00:00Z — Root cause identified (race condition on font load)
- 2026-04-22T09:00:00Z — Fix implemented with `fonts.ready` await
- 2026-04-26T11:00:00Z — PR merged, deployed to production
