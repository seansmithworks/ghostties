# Onboarding revamp: handoff (2026-10-11)

Cloud session: https://claude.ai/code/session_012mQBiQU7LsssB5GutgHuNu
Branch `design/onboarding-revamp` · draft PR #209 (green, no review comments, docs only).

## Files
- `first-run.html` — plan: today's first run, story (promote / set up / teach), research, Mild/Wild/Wilder concepts, decisions. Artifact: https://claude.ai/artifact/9Pw394mnedTgKssVFJi955
- `flows.html` — lo-fi clickable wireframes, Concept × Scenario switchers. Artifact: https://claude.ai/artifact/Sy82criJYsuU8NatVdV4Z2
- `gt-cli.html` — gt / ghostties-mcp audit. Verdict: keep, stop promoting, later bundle MCP in the .app. Artifact: https://claude.ai/artifact/XoT1MHu4tdCbQFjKpYa4Lb

## Decisions
- Project-first default; one-time Projects / Tasks choice in onboarding.
- Assume Claude Code or Codex is installed, but verify in onboarding (PATH via login shell + sign-in check; show install command if missing).
- Ghost art on hold; prototypes stay lo-fi.

## Beta 27 bugs (unfixed)
1. "Install gt" button only works from a repo checkout — `macos/Sources/Features/Ghostties/OnboardingSheet.swift:176`.
2. Claude Code hooks never auto-registered (`HookInstaller` only seeds the script) → "needs you" silent until manual JSON paste. Codex is auto-registered.
3. Onboarding sheet only shown in project-first mode (`WorkspaceSidebarView.swift`).
- Keep the demo-capture suppression flag (af54036).

## Next
1. Recover the newer robot-ghost preview (likely `docs/design/web-redesign/robot-ghosts/preview.html`, local only, maybe deleted in storage cleanup):
   `grep -l "robot" ~/.claude/projects/*/*.jsonl | xargs ls -lt | head` → find the Write of `preview.html`; else `mdfind -name preview.html | grep -i robot`, `~/.Trash`, `git fsck --lost-found`, Time Machine. Commit it here if found.
2. Pick a concept (Mild recommended for beta 27).
3. Fix bugs 1–3 on a new branch from `main`; verify with the `verify` skill.

Open: on-device onboarding funnel counting — yes or no.

The `.pen` source (`onboarding-20-concepts.pen`) lives in iCloud at `~/Library/Mobile Documents/com~apple~CloudDocs/Ghostties/onboarding/`, gitignored and kept out of the public repo.

## Round 2: pre-installed demo project (2026-10-20)

Built around concept #11. Source: `onboarding-round2-demo-project.pen` (same iCloud folder, gitignored). PNGs in `round2-demo-project/`.

Decisions (locked by Sean):
1. One demo project (`switchboard`, tagged Example), five sessions in mixed states.
2. All sessions static except one scripted live agent ("Validate OAuth scopes") that progresses and reaches "needs you", the hero moment.
3. Funnel counted on-device only, nothing sent.

Frames:
- A1 first launch · A2 explore while the live agent works · A3 the agent needs you · A4 open it and answer · A5 it finishes · A6 bridge to your own project · A7 own project on top, example collapses · A8 offer to remove the example once (recommended; alternative auto-archive after 7 days, rejected as silent)
- B1 mild (glyph only) · B2 question forward · B3 bolder (one-time coach mark + terracotta)
- C funnel: `onb.demo_shown`, `onb.needs_you_shown`, `onb.needs_you_opened`, `onb.needs_you_answered`, `onb.demo_finished`, `onb.add_project_clicked`, `onb.own_project_added`, `onb.demo_dismissed` / `onb.demo_kept`

Recommended "needs you": **B2** (A3 uses it). It is the row users keep forever, so the demo teaches the real signal and what to do about it, with no onboarding-only chrome and no break from the ink-only pattern D.

Open questions:
1. B2 as-is, or B3's coach mark for the first time only?
2. A8: one-time Remove/Keep prompt, or keep the example until removed by hand?
3. Should the funnel counts be visible to the user in Settings, or stored only?
