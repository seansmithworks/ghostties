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
