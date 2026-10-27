# Ghostties as a harness: thesis, policy limits, positioning

What the harness idea is, what provider policies rule out, where the market gap is, and what to build first.
Source: Claude Code (cloud session) • Session: 2026-10-11 to 2026-10-12

---

## 1. Background & Context

- Sean is weighing whether to grow Ghostties (a macOS fork of Ghostty with an agent sidebar) into a "harness": a layer above bring-your-own agents that can see every session, route and redirect work, summarize, verify, and remember across projects and repos. A free core terminal, with a possible paid harness tier later.
- Ghostties today is a personal project, open source and a portfolio piece, not a startup. `mission.md` names Sean as the primary user ("If it works for him, it graduates").
- What already exists in the repo:
  - Claude and Codex status hooks, and `ClaudeStateStore`
  - `ghostties-mcp` with task and notes tools (`CreateTask`, `ListTasks`, `UpdateTaskStatus`, `WriteSessionNotes`, …)
  - the `gt` CLI (`new`, `list`, `focus`, `done`, `notes`, `mcp`, `smoke`)
  - the sidebar, composer, menu bar, MCP source settings, and the embedded CEF browser
- Prior research in the repo: `docs/plans/vnext-avenues-2026-09-29.html` (the prod trail #24, the open deploy-event format #28, the morning glance #31, Quick Look media preview #40) and `docs/plans/vnext-research-2026-09-29/research-landscape.md`.
- Input video: Austin Marchese, "Stop Prompting Claude. Start Harness Engineering." (sponsored by Anthropic). Its framework:
  - Output = (Model + Prompt) × (Base Harness + Domain Harness)
  - Makers / takers / shapers (attributed to McKinsey)
  - 4 layers: foundation, choose a domain, build, interface
  - 8 building blocks: rules, skills, MCP, context, hooks, sub-agents, interface, feedback
  - Rules: "don't reinvent" and "keep it simple"
  - Example: a knowledge-base harness (two skills, `KB sync` and `KB answer`, plus a one-page local web UI with feedback)
  - His own tool has a pencil icon for editing the tool in place
  - The "Karpathy curve" (no source given)

## 2. Key Decisions & Rationale

- **Core principle: orchestrate the vendors' programs, never their accounts.** Ghostties starts the real, unmodified `claude`, `codex` and `cursor-agent`, each signed in with the user's own account. It watches them, sends them messages, verifies results and keeps memory. It never touches credentials and never calls a model on a user's subscription.
  - Why: Anthropic's legal page bans third-party apps from offering Claude.ai login or routing requests through Free/Pro/Max credentials. It also bans collecting or relaying tokens. It explicitly allows "an end user signing in to the unmodified Claude Code binary with their own Claude subscription."
  - Rejected: Agent SDK products running on subscriptions; a harness that holds or proxies tokens.
- **The harness brain is one of the user's own agents** (a "conductor" `claude` session with the Ghostties MCP), not a model Ghostties calls itself. An API key is optional, for a dedicated router.
- **Charge for the harness, never for tokens.** Paid value would be sync, memory, verification and harness packs. Reselling usage is banned.
- **Don't build a smart orchestrator.** Build a thin, deterministic control plane: observe, send a message to a session, open a task, check a result. Expose it through `gt`/MCP.
- **Positioning: a "taste harness" for designer-builders.** Work from any agent, reviewed by what it looks like.
  1. A screenshot or preview on each session row
  2. Mark it up in place and send it back to that session
  3. A taste ledger: corrections saved as rules and skills in the repo, used by every agent
  4. Design-system and Figma context
  - Why: the other quadrants are taken. App builders (Lovable, v0, Replit, Bolt) and vendor cockpits (Claude agent view, Codex app, Cursor 3, Copilot app) are single-vendor. Multi-agent cockpits (cmux, Conductor, Superset, Warp, Emdash) review code and status. Feedback is the building block Ghostties lacks.
  - Memory across projects is a weaker edge, because Anthropic reportedly now shares context across projects (a sponsor claim, unverified).
- **Business vs. maker: stay a maker for now.** The taste angle doubles as a portfolio thesis and a cheap test of demand.
  - Why: Conductor raised a $22M Series A, cmux has about 27.5k stars and a paid Founders Edition, vendors bundle cockpits free, and Ghostties is solo and macOS-only.
  - Revisit when other people use it every week, or ask for sync. The 50-weekly-outside-users threshold was Claude's suggestion, not research.
- **Build for one user first** (the video's own key insight): a personal design-review harness for this repo, used for two weeks, then turn the reused parts into features.

## 3. Action Items

**HIGH**
### Send-to-session primitive
A `gt` command and a `ghostties-mcp` tool that send a message to a running session, using allowed paths only (no token handling). This is the first steering capability.

### Feedback record per task
Per task: what was asked, what shipped, what was corrected, stored in the repo (next to the tasks directory). It's the seed of the taste ledger.

**MEDIUM**
### Latest screenshot on session rows
Show each session's latest output image or preview on its row. Pair it with Quick Look for agent images (vNext #40: OSC 8 link → `QLPreviewPanel`, branching in `macos/Sources/Ghostty/Ghostty.App.swift` `openURL`).

### Personal design-review harness
Rules, skills and hooks for reviewing Ghostties' own UI (the existing `verify` skill takes screenshots). Use it for two weeks.

**LOW**
### Cap on concurrent agents
Default limit so heavy use doesn't read as beyond "ordinary, individual usage."

### Shared event schema across agents
Normalize Claude, Codex and Cursor events, aligned with vNext #28.

## 4. Technical Context

- Repo rules: AGENTS.md is canonical. PRs go to `SeanSmithWorks/ghostties` only, never upstream. `zig build` is broken on macOS 26+, so build through Xcode.
- Build: `xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Release -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- Swift package tests: `cd cli && swift test --parallel`
- Relevant code:
  - `cli/Sources/ghostties-mcp/Tools/`
  - `cli/Sources/gt/Commands/`
  - `macos/Sources/Features/Ghostties/` (`ClaudeStateStore.swift`, `HookInstaller.swift`, `CodexHookRegistrar.swift`, `NeedsYouZoneView.swift`, `BrowserPanelView.swift`, `MCPSourceSettingsStore.swift`)
- Hook coverage: Claude yes (manual paste), Codex yes (auto-registered), Gemini none.

## 5. Sensitivity & Guardrails

- Never handle, store or proxy users' Claude/ChatGPT/Cursor credentials.
- Never use "Claude Code" in a product or feature name; a plain-text mention like "runs Claude Code" is fine.
- `claude -p` driven from a paid product is a grey area. Ask Anthropic sales before building on it.
- Watch for prompt injection between sessions: one agent's output summarized into another's instructions. Needs scoped permissions, an audit log and a kill switch.

## 6. Open Questions

- Is `claude -p` from a paid product allowed?
- OpenAI "Sign in with ChatGPT" for third-party apps: reported at DevDay in early Oct 2026 as a limited preview with about 16 partners and per-app weekly caps. OpenAI's own docs weren't readable from the cloud session. Worth applying?
- Cursor: no third-party subscription program found.
- A May 2026 reversal of Anthropic's ban was claimed by one blog (BetterClaw). Unconfirmed; the current Anthropic page shows no reversal.
- The video's sponsor claims (Chat and Cowork merged, shared context across projects): unverified.
- "Karpathy curve": unsourced.

## 7. Resources & Links

- Doc: Ghostties Harness Thesis — https://claude.ai/code/artifact/c151fd34-0900-407c-af87-32c00f59d899 (private until shared)
- Anthropic legal and compliance (read directly): https://code.claude.com/docs/en/legal-and-compliance
- The Register, Feb 2026: https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546
- The Star, Oct 4 2026 (OpenAI sign-in): https://www.thestar.com.my/tech/tech-news/2026/10/04/openai-expands-chatgpt-with-apps-and-third-party-sign-in
- Figma canvas open to agents: https://www.figma.com/blog/the-figma-canvas-is-now-open-to-agents/
- Argos visual testing for agents: https://argos-ci.com/blog/visual-testing-ai-coding-agents
- Video: https://youtu.be/bIYWxYm5cOY
- Repo docs: `mission.md`, `docs/plans/vnext-avenues-2026-09-29.html`, `docs/plans/vnext-research-2026-09-29/research-landscape.md`

## 8. Next Steps

1. Design and implement the send-to-session primitive in `gt` and `ghostties-mcp`. Decide how it delivers to a live session: through Ghostties' terminal surface, not by touching a vendor's credentials.
2. Define the feedback-record format (a file per task in the repo) and write it from `gt done` or a new command.
3. Spike a screenshot on the session row, plus Quick Look (#40).
4. Set up the personal design-review harness and use it daily for two weeks.
