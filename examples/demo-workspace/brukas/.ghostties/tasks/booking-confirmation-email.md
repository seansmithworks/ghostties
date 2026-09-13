---
title: "Send booking confirmation emails with job summary"
status: done
created: 2026-05-14T09:00:00Z
project: brukas
source: linear
source-id: BRK-44
priority: high
pr: 44
pr-state: merged
pr-url: https://github.com/example-org/brukas/pull/44
completed: 2026-05-28T16:00:00Z
updated: 2026-05-28T16:00:00Z
---

## Goal
Trigger a transactional email to the customer immediately after a booking is confirmed, including job date, time window, assigned technician, and total quote.

## Notes
Built with Resend. Template uses React Email components so the markup stays maintainable. Technician headshot is pulled from the staff profile if one exists; falls back to a generic avatar. Unsubscribe link is required for CAN-SPAM — routed through a preference page, not a one-click pixel.

## Activity
- 2026-05-14T09:00:00Z — Scaffolded Resend integration and React Email template
- 2026-05-19T13:00:00Z — Added technician photo fallback logic
- 2026-05-23T10:30:00Z — Preference center wired, unsubscribe tested
- 2026-05-28T16:00:00Z — Merged and verified in production send
