---
title: "Notify users when @mentioned in annotation comments"
status: inbox
created: 2026-06-17T11:00:00Z
project: annotie
source: shell
priority: medium
---

## Goal
Send an in-app and email notification when a user is @mentioned inside an annotation comment thread so reviewers don't miss direct questions buried in long documents.

## Notes
Not started. Mention parsing would extract `@username` tokens from comment text at save time. In-app notification via existing notification center. Email notification uses Resend with a 15-minute debounce to batch multiple mentions in the same session into one digest. Need to confirm whether workspace guests (view-only role) can be @mentioned.

## Activity
- 2026-06-17T11:00:00Z — Requested by three separate beta teams; added to inbox
