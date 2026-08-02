# Ghostties Backlog

Greppable parking lot for open items that survive context resets. Newest dated section on top.

## 2026-07-22

- [ ] **Sweep stale `SeanSmithDesign` references from memory files + docs** — the account renamed to `SeanSmithWorks` (2026-07-21). Code refs are fixed (PRs #51/#52), but lingering `SeanSmithDesign` strings in memory/docs (and possibly a cached "configured origin") make the harness security scanner FALSE-POSITIVE on every correct PR to `SeanSmithWorks/ghostties`. Harmless but noisy. Sweep to silence it. Intentionally left: test-fixture/doc-comment example URLs (`CrossSurfaceCoherenceTests.swift`, `TaskModelTests.swift`, `TaskModel.swift` — illustrative `pull/99` examples) and `web/appcast-beta.xml` (CI-regenerated). See memory `feedback-scanner-false-positive-account-rename.md`. | ops | quick
- [ ] **Close PR #33** — superseded by the merged #47 CI fix; close attempt was permission-denied this session. | ops | quick

## 2026-07-21

- [ ] **Merge PR #48** (`feat/website-product-shots`) — ghostties.org refresh: product section, single-window video, ambient ghost drift, top-clipping fix, black-video fix, GitHub-rename doc fix. Awaiting Sean's review + merge. Two red CI checks (`Swift Package (cli/)`, `macOS App (xcodebuild test)`) look like pre-existing app-test flakiness unrelated to this web-only diff — shouldn't block the merge button (branch protection only blocks force-push/deletion). Vercel preview passed, so merge → should auto-deploy to production. | web | needs-Sean
- [ ] **Approve or edit the 4 social drafts** at `drafts/ghostties-social-question-series.md` — question-hook posts paired with the site's two hero visuals. Drafted and shown to Sean, not yet reacted to. | content | needs-Sean
- [ ] **Ghost physics playground — full port, deferred** — the fuller interactive playground (drift physics, drag-throw, trading-card hover) from the sibling `2026-web-playground` repo was explicitly parked in favor of the lighter ambient-drift-only version that shipped in PR #48. Repo isn't cloned on this machine. Revisit only if Sean asks for the fuller version specifically. | web | deferred

## 2026-07-18

- [ ] **Re-enable app-hosted macOS test execution on CI** — `test-ghostties.yml`'s `macos-app` job now runs `build-for-testing` (compile-only), not `test`. Reason: launching `Ghostties Dev.app` as the XCTest host reliably hangs ~6 min on headless GitHub runners ("test runner hung before establishing connection" → exit 65), even though the three-layer XCTest short-circuit makes local Cmd+U launch fast. The pure-Swift logic suites still run in the `swift-package` (cli/) job; app-hosted `GhosttyTests` execution is local-Cmd+U-only. Real fix: move the host-independent test classes (TaskModelTests, TaskFileWatcherTests, TaskStoreWriteTests, router/dedup/zone logic, etc.) into a non-app-hosted logic bundle so they run without launching the GUI. See memory `project-ci-host-app-hang.md`. | build | session

## 2026-07-17

- [ ] **Esc doesn't cancel inline session rename** (#43 polish) — right-click → Rename → type → `Esc` keeps the typed value instead of reverting; only `Enter` commits and re-typing reverts. Wire up Escape-to-cancel. Minor, out of scope of beta.20 verify. | craft | quick
- [ ] **Phase 1 file-watch not live-verified** — blocked by TCC: the ad-hoc `Ghostties Demo` build lacks Files & Folders permission ("Data Access Blocked"), so it can't read `examples/demo-workspace/*/.ghostties/tasks/`. Needs Sean to grant it in System Settings → Privacy → Files & Folders, OR accept the Phase 1 close on code verification. | build | needs-Sean
- [ ] **`.gitignore` build-output dirs** — `.build-demo/` and `.build-verify/` are untracked build artifacts sitting in the repo root; add to `.gitignore`. (`.build-demo/` gitignore already noted in ORCHESTRATOR demo-capture entry.) | build | quick
- [ ] **Stale updater test on main** — `GhosttyTests/UpdateViewModelTests.testNotFoundText()` expects `"No Updates Available"` but the shipped `.notFound` copy (changed in fork PR #34, in beta.19) is `"You're on the latest"` / `"No stable releases yet"`. Pre-existing, unrelated to beta.20; our red CI never caught it. One-line fix: update the test's expected string to match current copy. | quality | quick
- [ ] **Perf track (contextMenu render cost, #1/#2)** — confirmed this session the per-row `.contextMenu`/`.popover`/`.draggable` modifiers are still present in `ProjectDisclosureRow.swift` (not code-fixed). Full state + the one remaining interaction-under-load check live in ORCHESTRATOR In-Flight Work. Separate objective from beta.20 verify. | perf | session

## 2026-08-01 — repo documentation refresh

Objective: get the GitHub repo presentable for incoming interest, with correct Ghostty-vs-Ghostties calibration. Wave 1 shipped; branch `docs/repo-documentation-refresh` pushed, no PR. Plan: `docs/plans/repo-documentation-refresh.html`.

- [ ] **Wave 0 — repo settings (Sean's hands, GATED on Wave 1 merging to main)** — enable Issues + Discussions (Q&A and Ideas only, delete other categories), private vulnerability reporting, Dependabot alerts. Set description, 10 topics (currently empty), and a 1280x640 social preview. **Do not enable Issues before the merge** — `issues`-triggered workflows run from the default branch, so the inherited auto-close vouching workflow is still armed on `main`. | docs | needs-Sean
- [ ] **Wave 2 — licensing & attribution** — `LICENSE` stacked copyright (Sean above Mitchell) + new `THIRD-PARTY-NOTICES.md` (Ghostty MIT, CEF BSD-3 verbatim, Sparkle MIT, nerd-fonts OFL). Then verify the notice reaches the shipped `.app`, or add a Help-menu Acknowledgments item. The only genuine legal gap. | docs | session
- [ ] **Wave 4 — intake & support docs** — rewrite `CONTRIBUTING.md` (~40 lines, no-code-PRs posture), new `SECURITY.md` + `CODE_OF_CONDUCT.md` + `TESTING.md`, convert issue templates to YAML forms (incl. the "does this happen in upstream Ghostty?" dropdown), `blank_issues_enabled: false`, prune to 6 labels. | docs | session
- [ ] **Wave 3 — README rewrite** — ~90-120 lines, identity + Ghostty credit at line 3, install section (signed/notarized/Sparkle), cropped hero + `<video>` embed, known-limitations `<details>`, non-affiliation line in License. | docs | session
- [ ] **Wave 5 — inherited-doc cleanup** — delete `PACKAGING.md` and `AI_POLICY.md`, trim `AGENTS.md` (cut upstream's "sad, dumb little AI driver" joke at line 67), add a Ghostties header to `HACKING.md`, retarget `.github/dependabot.yml`. | docs | session
- [ ] **Hero crop decision** — cropped 2880x820 banner variant built and sent to Sean; keeps sidebar + active session, loses the bottom window frame. Not yet reacted to. Fallback is the uncropped original. | design | needs-Sean
- [ ] **Dark-mode hero capture — deferred** — hero is light-only, and a light screenshot on GitHub's dark theme reads as broken. `<picture>` theme-swapping needs a dark capture. Not worth a session on its own; do it next time Ghostties is open with Screen Recording granted. | design | deferred
- [ ] **Stale comment in `ghostties-release.yml`** — line 6 reads `# Key differences from upstream release-tag.yml:`, but that file was deleted in Wave 1. Comment only, no functional reference. Left untouched because the security work-stream owns that file. | build | quick

**Off-objective, parked here deliberately (do NOT carry into the docs thread):**

- [ ] **Public-repo hygiene** — `docs/SESSION_NOTES.md` (158KB of internal notes), `docs/handoffs/`, `docs/brainstorms/`, `docs/PR_DRAFTS.md`, `drafts/`, `todos/`, `BACKLOG.md` are all publicly readable. Wave D already untracked one file for the same reason. Untracking stops the bleeding but does not clear already-public history — see the private memory for prior art and the real fix. Deliberately NOT folded into a documentation branch. | security | needs-Sean
