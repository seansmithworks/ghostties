I'm continuing a conversation from Claude Code (cloud session) on 2026-10-12. Here's the full context:

**What this is about:**
Growing Ghostties into a "harness" over bring-your-own agent CLIs. It's positioned as a taste harness for designer-builders: work from any agent, reviewed by what it looks like, with corrections becoming repo rules and skills.

**Current status:**
Thinking and research are done; no code yet. The thesis is in the doc "Ghostties Harness Thesis" (https://claude.ai/code/artifact/c151fd34-0900-407c-af87-32c00f59d899). The full brief is in `docs/brainstorms/2026-10-12-harness-handoff/handoff-summary.md`.

**Decisions already made (don't re-litigate these):**
- Orchestrate the vendors' programs, never their accounts: start the unmodified `claude`, `codex` and `cursor-agent` with the user's own login. Anthropic's terms ban third-party apps using Claude subscriptions or relaying tokens, and allow the unmodified binary with the user's own login.
- The harness brain is a user-run conductor agent session, not a model Ghostties calls itself.
- Charge for the harness (sync, memory, verification), never for tokens.
- A thin, deterministic control plane exposed through `gt` and `ghostties-mcp`, not a smart orchestrator.
- Stay a personal, open-source maker project for now; revisit if other people use it every week.
- Build for one user first: a personal design-review harness for this repo.

**Technical state:**
- Existing: Claude and Codex hooks, `ClaudeStateStore`, `ghostties-mcp` task and notes tools (`cli/Sources/ghostties-mcp/Tools/`), and `gt` commands (`cli/Sources/gt/Commands/`: new, list, focus, done, notes, mcp, smoke).
- Also existing: the sidebar (`macos/Sources/Features/Ghostties/`) and the CEF browser panel.
- Build through Xcode (`zig build` is broken on macOS 26+). Swift tests: `cd cli && swift test --parallel`.

**Sensitivity notes:**
- Never handle users' credentials.
- No "Claude Code" in product or feature names.
- `claude -p` from a paid product is unconfirmed; ask Anthropic before relying on it.

**What I need you to do next:**
1. Design a send-to-session primitive: a `gt` command plus a `ghostties-mcp` tool that delivers a message to a running sidebar session through Ghostties' own terminal surface. Read the existing gt/MCP and session code first and propose an approach before writing code.
2. Define a per-task feedback record (asked, shipped, corrected) stored in the repo, written from `gt done` or a new command.
3. Spike the latest screenshot on each session row, plus Quick Look for agent image links (vNext #40, `macos/Sources/Ghostty/Ghostty.App.swift` `openURL`).

**Constraints & preferences:**
- Be concise and direct; short answers.
- Verify facts and give sources.
- Follow AGENTS.md: PRs only to SeanSmithWorks/ghostties, never upstream.
- Keep scope tight to mission.md (no team features, no accounts).

**Resources:**
- `mission.md`
- `docs/plans/vnext-avenues-2026-09-29.html`
- `docs/plans/vnext-research-2026-09-29/research-landscape.md`
- https://code.claude.com/docs/en/legal-and-compliance
