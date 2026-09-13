---
title: "Generate downloadable PDF quote for customers"
status: review
created: 2026-06-05T10:00:00Z
project: brukas
source: github
source-id: GH-58
priority: medium
pr: 58
pr-state: open
pr-url: https://github.com/example-org/brukas/pull/58
branch: feat/quote-pdf
---

## Goal
Let customers download a branded PDF of their quote from the booking detail page so they can share it with a landlord or file it for reimbursement.

## Notes
Using `@react-pdf/renderer` server-side to keep fonts consistent. PDF includes company logo, line-item breakdown, labor and materials subtotals, tax, and a "valid for 30 days" footer. Quote number is stamped at generation time and stored on the `quotes` table for audit trail. Font licensing checked — Inter is OFL licensed, safe to embed.

## Activity
- 2026-06-05T10:00:00Z — PDF template built, line items rendering correctly
- 2026-06-09T13:30:00Z — Logo embedding resolved (was encoding as base64 inline)
- 2026-06-12T11:00:00Z — Opened PR, screenshots of generated PDF in description
- 2026-06-13T15:00:00Z — Addressed review comment on tax line formatting
