---
title: "Enforce 24-hour cancellation policy with partial refund"
status: needs-you
created: 2026-06-14T09:00:00Z
project: brukas
source: linear
source-id: BRK-67
priority: high
needs: "Should the 24-hour window be measured from job start time or from when the booking was originally confirmed? Late-confirmed bookings (e.g. same-day emergency slots) create an edge case where the customer immediately falls inside the no-refund window."
---

## Goal
Block full refunds for cancellations made fewer than 24 hours before the scheduled job start, and issue a 50% partial refund through Stripe instead.

## Notes
Stripe refund API is straightforward. The tricky part is the edge case around same-day bookings confirmed within the cancellation window — need a product decision before implementing the time comparison logic. Refund receipts should be sent automatically via the existing Resend integration.

## Activity
- 2026-06-14T09:00:00Z — Cancellation route exists but currently issues full refunds unconditionally
- 2026-06-14T16:00:00Z — Blocked on window-measurement question for same-day bookings
