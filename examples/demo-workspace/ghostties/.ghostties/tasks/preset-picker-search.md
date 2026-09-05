---
title: "Add fuzzy search to the session template picker"
status: needs-you
created: 2026-08-20T12:00:00Z
project: ghostties
source: github
source-id: GH-152
priority: medium
pr: 152
pr-state: open
pr-url: https://github.com/example-org/ghostties/pull/152
---

## Goal
Template picker popover lists presets alphabetically; needs a search field
for users with more than ~10 saved templates.

## Blocking question
Should search match only the template name, or also the first line of the
prompt body? Second option is more useful but needs an index built at load
time rather than a simple substring filter.

## Activity
- 2026-08-20T12:00:00Z — Opened PR with name-only search
- 2026-08-22T10:00:00Z — Review requested a decision on prompt-body matching
