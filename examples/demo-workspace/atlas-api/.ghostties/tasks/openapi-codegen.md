---
title: "Set up OpenAPI codegen pipeline"
status: backlog
created: 2026-04-30T08:00:00Z
project: atlas-api
source: linear
source-id: ATL-19
priority: medium
---

## Goal
Automate TypeScript type generation from the OpenAPI spec so the SDK stays in sync with the server contract without manual updates.

## Notes
Evaluating `openapi-typescript` vs `orval`. Need to decide whether to check in generated files or gitignore and generate on `postinstall`.

## Activity
- 2026-04-30T08:00:00Z — Added to backlog after v1 type drift caused a prod incident
