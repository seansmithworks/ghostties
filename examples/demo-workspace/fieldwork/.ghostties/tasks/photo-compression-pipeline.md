---
title: "Photo compression pipeline for field uploads"
status: review
created: 2026-05-25T09:00:00Z
project: fieldwork
source: github
source-id: GH-73
priority: medium
pr: 73
pr-state: open
pr-url: https://github.com/example-org/fieldwork/pull/73
branch: feat/photo-compress
---

## Goal
Compress and resize photos captured in the field before upload to reduce data usage on LTE connections and speed up sync.

## Notes
Targeting 1200px max dimension at 0.82 JPEG quality. Using `ImageIO` framework for lossless metadata (EXIF, GPS tags) preservation. Thumbnails generated at 256px for the form preview.

## Activity
- 2026-05-25T09:00:00Z — Implemented compression pipeline using ImageIO
- 2026-05-27T11:00:00Z — PR opened, 87% reduction in average upload size
- 2026-05-29T10:00:00Z — Reviewer asked about HEIC support — added HEIC input path
