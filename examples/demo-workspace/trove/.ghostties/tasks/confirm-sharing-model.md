---
title: "Confirm public sharing model before implementing"
status: needs-you
created: 2026-06-10T11:00:00Z
project: trove
source: linear
source-id: TRV-85
priority: high
needs: "Should shared notes be published as static pages (no auth, public URL) or require the viewer to have a Trove account? This affects the rendering path, auth middleware, and how we handle embedded media."
---

## Goal
Define whether note sharing is public-URL (static publish) or account-gated (authenticated viewer) before building the share flow.

## Notes
Public sharing is simpler for the sharer and has higher virality. Account-gated lets us track views and restrict sensitive notes. A hybrid (default public, optional account-gate) is possible but doubles the implementation surface.

## Activity
- 2026-06-10T11:00:00Z — Sharing modal design is ready; blocked on model decision
