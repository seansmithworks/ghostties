# Ghostties competitive landscape, 2026-09-29

## TL;DR

- Ghostties' base position is already taken. **cmux** is a Ghostty-based, native Swift/AppKit macOS terminal with an agent sidebar (branch, PR status, ports, "needs attention" rings). It has 27.5k stars, plus cloud VMs and an iOS app in beta. Treat it as the incumbent, not as a peer.
- The platform owners shipped their own cockpits in 2026: Claude Code's `claude agents` (May), the Claude Desktop redesign (Apr) plus Sessions Hub (Sep), the Codex app (Feb), Cursor 3's Agents Window (Apr), the GitHub Copilot app (May), and Devin Desktop (Jun). **iTerm2 3.7 (Sep)** now ships Claude Code working/waiting/idle status built into the terminal.
- Every major player now covers per-session status plus PR/CI status. Claude's agent view colors PR labels by check state, and Superset rows show checks. That is table stakes.
- **Deploy visibility is still fragmented.** Conductor and Superset show a *preview URL per PR*. Vercel's own agent tooling is pull-based: the MCP, plugin `/status`, and Agent investigations in the dashboard or Slack. Production state lives in single-purpose menu bar apps that know nothing about which agent shipped what.
- The open ground is **joining things**: session → commit → deploy → prod health, across Claude, Codex and Gemini, shown as a quiet native glance. Nobody attributes a production deploy to the agent session that caused it.
- The biggest threat is Anthropic. It owns the hooks, the session files, a desktop app, and a "Ready for review" state that already has PR color.

## Landscape

| Name | What | Native? | Agents | Status model | Deploy visibility | Traction | Source |
|---|---|---|---|---|---|---|---|
| **cmux** (Manaflow) | Ghostty-based terminal with a vertical-tab agent sidebar | Yes, Swift + AppKit | Local, plus cloud VMs (Sep 2026) | Blue ring and lit tab from OSC 9/99/777 or `cmux notify` hooks. Shows latest notification text. | PR status/number and listening ports in the sidebar. No deploy state found. | 27.5k stars. GPL. Paid "Founders Edition". iOS app in TestFlight. | [repo](https://github.com/manaflow-ai/cmux), [cloud VM PR](https://github.com/manaflow-ai/cmux/pull/12604) |
| **Conductor** (Melty, YC S24) | Parallel Claude/Codex/Cursor agents in worktrees, with review and merge | Mac app (framework not verified) | Local, plus Conductor Cloud | Per-workspace, with checks and failing checks forwarded to Claude | **Deployments tab: Vercel and GitHub deployments per PR** (Jan 2026). "View deployment(s)" button. | $22M Series A (Mar 2026). Free, Pro $50/mo. Shipping near-daily (0.89.1 today). | [codepick](https://codepick.dev/en/guides/conductor-build-intro/), [0.29.2](https://www.conductor.build/changelog/0.29.2-vercel-deployments-simplified-thinking-levels), [changelog](https://www.conductor.build/changelog) |
| **Superset** | "Agentic IDE" for 100+ parallel CLI agents | Electron | Local worktrees, remote from iPhone | Working indicator, chime, dock badge. Rows show agent status, diff size, check progress. | PR hover shows checks. **"Open Preview" when the branch has a deploy preview.** | 14.7k stars. ELv2. SOC 2. iPhone app shipped Sep 28. | [repo](https://github.com/superset-sh/superset), [docs](https://docs.superset.sh/workspaces), [changelog](https://superset.sh/changelog) |
| **Emdash** (YC W26) | Open-source ADE, 20+ provider CLIs | Electron | Local plus SSH | Installs provider hooks for status | Create PRs, "inspect CI checks", merge. No deploy state found. | 5.9k stars | [repo](https://github.com/generalaction/emdash) |
| **Vibe Kanban** | Kanban board over local agents | Web UI | Local | Board columns | Dev server per workspace | Company (Bloop) shut down Apr 2026. Now community-maintained. | [virtuslab](https://virtuslab.com/blog/ai/vibe-kanban), [ai.engineer](https://ai.engineer/orgs/vibe-kanban) |
| **Nimbalyst** (was Crystal) | Kanban plus WYSIWYG workspace for Claude/Codex | Desktop (inferred Electron). iOS companion. | Local | Board | None found | Crystal deprecated Feb 2026 | [crystal repo](https://github.com/stravu/crystal), [nimbalyst](https://nimbalyst.com/crystal/) |
| **Terragon** | Cloud background Claude/Codex | Web | Cloud | n/a | n/a | **Shut down Jan 2026**, open-sourced | [repo](https://github.com/terragon-labs/terragon-oss) |
| **Sculptor** (Imbue) | Parallel Claude in Docker containers, with Pairing Mode | Mac (Apple Silicon) and Linux | Local containers | Per-agent | None found | Free beta, MIT | [imbue](https://imbue.com/sculptor/), [ryw](https://rywalker.com/research/sculptor) |
| **CodeLayer** (HumanLayer) | Keyboard-first IDE over Claude Code. "MultiClaude" parallel sessions. | Desktop (inferred) | Local plus remote workers | n/a | None found | Apache-2.0 | [repo](https://github.com/humanlayer/humanlayer/tree/main) |
| **claude-squad / ccmanager / agent-deck** | TUI session managers | Terminal | Local | ccmanager shows per-session state. claude-squad doesn't. | None | ccmanager ~1.25k stars | [ccmanager](https://github.com/kbwo/ccmanager), [claude-squad](https://github.com/smtg-ai/claude-squad), [agent-deck](https://github.com/asheshgoplani/agent-deck) |
| **Claude Code agent view** (`claude agents`) | First-party terminal dashboard of every background session | Terminal only | Local, with a supervisor daemon | **Pinned / Ready for review / Needs input / Working / Idle / Completed / Failed / Stopped.** Haiku-written one-line summary every 15s. | **PR label colored by check state** (yellow/green/purple). No deploys. | Research preview, May 2026 | [docs](https://code.claude.com/docs/en/agent-view) |
| **Claude Desktop (Code tab plus Cowork)** | Multi-session sidebar, worktrees, preview pane, Routines. Sessions Hub (Sep). | Desktop app (Electron, inferred) | Local plus Anthropic cloud | OS notification on finish. **PR monitoring with CI auto-fix and auto-merge.** | Dev-server preview. CI via `gh`. No hosting deploys. | Bundled with Pro/Max | [redesign](https://www.macrumors.com/2026/04/15/anthropic-rebuilds-claude-code-desktop-app/), [preview/CI](https://claude.com/blog/preview-review-and-merge-with-claude-code), [hub (secondary)](https://www.progressiverobot.com/2026/09/15/claude-desktop-sessions-hub-claude-code-management/) |
| **Claude Code Projects** | Parallel sessions per project, with a coordinator | Claude.ai / desktop | Local and cloud | Beta | n/a | Pro/Max beta, Sep 18 | [Register](https://www.theregister.com/ai-and-ml/2026/09/18/claude-code-revamps-projects-so-you-can-work-and-pay-in-parallel/5297532) |
| **Claude Cowork** | Non-coding desktop agent, scheduled tasks | Desktop | Local plus remote | n/a | n/a | GA Apr 9, 2026 | [vellum](https://www.vellum.ai/blog/official-claude-cowork-breakdown) |
| **Codex app / CLI / cloud** | "Command center": parallel threads, worktrees, automations into a review queue | macOS app | Local plus cloud (reusable cloud envs, Sep 29) | Task status filter in the "agent command center" | None found | Bundled with ChatGPT plans | [OpenAI](https://openai.com/index/introducing-the-codex-app/), [releasebot](https://releasebot.io/updates/openai/codex), [TechCrunch](https://techcrunch.com/2026/09/29/openai-gives-codex-reusable-cloud-environments-that-work-across-devices/) |
| **Cursor 3 Agents Window** | Many agents across local, worktree, cloud and SSH | Electron (VS Code fork) | Local plus cloud (can run in Vercel Sandbox) | Not documented in changelog | Cloud agents can publish to Vercel for a live URL | Cursor-only agents | [changelog](https://cursor.com/changelog/3-0), [Vercel sandbox](https://vercel.com/changelog/run-cursor-cloud-agents-vercel-sandbox) |
| **GitHub Copilot app / Agent HQ** | Desktop agent workspace. Mission control across vendors' agents. | Desktop, all OSes | Local worktrees plus cloud (Actions) | Session modes (Interactive/Plan/Autopilot). Session costs exposed. | PR-centric. Deploys only via GitHub deployments (inferred). | Tech preview, May 2026. Pro users on waitlist. | [changelog](https://github.blog/changelog/2026-05-14-github-copilot-app-is-now-available-in-technical-preview/), [Agent HQ](https://github.blog/news-insights/company-news/welcome-home-agents/) |
| **Warp + Oz** | Terminal with third-party agent support. Oz = cloud agent orchestration. | Native (Rust) | Local plus cloud | Vertical tabs with branch/PR metadata. Unified notification center across agents. | None found | 1M active users (Mar 2026) | [notifications](https://docs.warp.dev/agents/capabilities/agent-notifications/), [Oz](https://www.warp.dev/blog/oz-orchestration-platform-cloud-agents), [1M](https://www.warp.dev/newsroom/2026/3/22/warp-reaches-one-million-active-users-launches-oz-cloud-platform) |
| **Zed Parallel Agents** | Threads Sidebar grouped by project, including "Terminal Threads" | Native (Rust, GPUI) | Local | Per-thread monitoring | None found | Shipped Apr 22, 2026 | [blog](https://zed.dev/blog/parallel-agents) |
| **Devin Desktop** (was Windsurf) | Agent Command Center, a Kanban of local and cloud agents | Electron (VS Code fork) | Local plus cloud | Kanban columns | None found | $20–200/mo | [devin](https://devin.ai/blog/windsurf-is-now-devin-desktop) |
| **Factory Droids** | Desktop app for Droids | macOS and Windows | Local plus cloud | n/a | Markets "deployments" as a Droid task | $150M C (Apr), $120M C-2 at $4B (Jul) | [factory](https://factory.ai/news/factory-desktop), [funding](https://tech-insider.org/factory-ai-150-million-series-c-khosla-coding-droids-2026/) |
| **Amp** | Coding agent with shared threads | CLI / editor | Local | n/a | n/a | Spun out of Sourcegraph Dec 2025. Free tier ended. | [bitdoze](https://www.bitdoze.com/amp-code-free-ai-coding-agent/) |
| **Paperclip** | "Agent org chart": named Claude/Codex agents, budgets, heartbeats | Unknown | Team-oriented | Heartbeats | n/a | Unknown | [blog](https://paperclip.ing/blog/manage-multiple-claude-code-codex-sessions/) |
| **iTerm2 3.7** | Built-in Claude Code integration, Session Status tool | Native (ObjC/Swift) | Local | **working / waiting / idle** from hooks, sorted by priority. iOS companion. | None | Sep 2026 | [iTerm2](https://iterm2.com/claude-code-integration.html), [AlternativeTo](https://alternativeto.net/news/2026/9/iterm2-3-7-released-with-ios-companion-app-claude-code-integration-tab-groups-and-more/) |
| **Wave / Kitty / Tabby** | Wave has an AI chat block (an assistant, not an agent manager). Kitty only through DIY hook title-writers. Tabby: none found. | Mixed | n/a | None built in | None | n/a | [Wave](https://moltamp.com/blog/wave-terminal-ai-features-2026/), [Kitty](https://flurdy.com/docs/kitty-ai-tabs/) |

Upstream context: Ghostty 1.4 is due Sep 2026 with scriptability. Hashimoto predicts more people will use Ghostty through libghostty apps than through Ghostty itself by mid-2027 ([source](https://mitchellh.com/writing/libghostty-is-coming), [roadmap summary](https://gigazine.net/gsc_news/en/20260404-ghostty-ui/)). Expect more cmux-shaped entrants.

## Deploy inside the cockpit

**What exists:**
- **Conductor**: a per-PR Deployments tab listing Vercel and GitHub deployments, and a PR timeline that merges checks, deployments and comments ([0.29.2](https://www.conductor.build/changelog/0.29.2-vercel-deployments-simplified-thinking-levels), [search summary](https://www.conductor.build/changelog/page/2)). It is the deepest integration found, but it is scoped to a PR. It shows nothing about production after merge.
- **Superset**: an "Open Preview" button when a branch has a deploy preview, plus checks on hover. An open issue asks for check badges in the sidebar ([docs](https://docs.superset.sh/workspaces), [#7805](https://github.com/superset-sh/superset/issues/7805)).
- **Claude Desktop**: dev-server preview, plus CI monitoring with auto-fix and auto-merge via `gh`. CI only, no hosting provider ([blog](https://claude.com/blog/preview-review-and-merge-with-claude-code)).
- **Claude agent view** and **cmux**: PR status only ([agent view](https://code.claude.com/docs/en/agent-view), [cmux](https://github.com/manaflow-ai/cmux)).
- **Cursor cloud agents**: publish to Vercel for a live URL, and can run in Vercel Sandbox (the Sandbox route needs Enterprise) ([Vercel](https://vercel.com/changelog/run-cursor-cloud-agents-vercel-sandbox), [KB](https://vercel.com/kb/guide/cursor-vercel-sandbox)).
- **Netlify Agent Runners**: run Claude, Codex and Gemini *inside Netlify*, and every run gets a Deploy Preview. The agent comes to the host, not the host to your cockpit ([Netlify](https://www.netlify.com/knowledge-base/how-to-run-ai-agent-tasks-remotely-with-netlify-agent-runner/)).

**Vercel's own tooling** is built for the *agent* to pull state. None of it is an ambient surface for a person:
- The hosted MCP at mcp.vercel.com can list, inspect, promote, cancel and roll back deployments, and read build logs ([docs](https://vercel.com/docs/agent-resources/vercel-mcp), [summary](https://mcp-find-web.vercel.app/blog/vercel-mcp-server-deployment-guide)).
- The Vercel Plugin works across Claude Code, Codex, Cursor, Copilot, Grok and Kimi. It has 28 skills, a `deployment-expert` agent and `/vercel-plugin:status`. Its hooks only inject context at session start, so nothing watches or notifies ([plugin docs](https://vercel.com/docs/agent-resources/vercel-plugin)).
- The CLI supports `--json` across commands ([changelog](https://vercel.com/changelog/agent-runs-vercel-mcp-cli)).
- Vercel Agent does investigations and PR review in the dashboard, Slack and GitHub comments ([expanded agent](https://vercel.com/changelog/an-expanded-vercel-agent-chat-investigations-and-approved-actions-now-in-public-beta), [Slack](https://vercel.com/changelog/vercel-agent-investigations-now-available-in-slack), [code review](https://vercel.com/docs/agent/pr-review)).
- Sandbox went GA in Jan 2026 and runs up to 24h ([docs](https://vercel.com/docs/sandbox)). Open Agents is a reference background-agent app ([InfoQ](https://www.infoq.com/news/2026/04/vercel-open-agents/)).
- v0 now imports repos and creates branches and PRs ([blog](https://vercel.com/blog/introducing-the-new-v0)).
- "Agent Runs" are traces for *deployed* eve agents, not coding sessions ([changelog](https://vercel.com/changelog/agent-runs-vercel-mcp-cli)).
- Deployments list redesign, May 2026 ([changelog](https://vercel.com/changelog/redesigned-deployments-list)).

**GitHub** is PR-centric. Mission control tracks agent tasks through to the PR. The cloud agent validates in an Actions-powered environment ([mission control](https://github.blog/changelog/2025-10-28-a-mission-control-to-assign-steer-and-track-copilot-coding-agent-tasks/), [cloud agent](https://docs.github.com/copilot/concepts/agents/coding-agent/about-coding-agent)). No evidence found of hosting-deploy state in the Copilot app.

**Where a solo dev with 5 agents sees deploys today:** in the Vercel dashboard, in GitHub PR comments from the Vercel bot, or in a menu bar app. At least five exist: Deploy Status for Vercel, vercel-menubar-status, vercel-deployment-menu-bar, vercel-menu-bar, and DeployBar (Vercel plus Railway) ([App Store](https://apps.apple.com/us/app/deploy-status-for-vercel/id6755970752?mt=12), [DeployBar](https://github.com/snapre/DeployBar), [andrewk17](https://github.com/andrewk17/vercel-deployment-menu-bar)). **Yes, it's a gap.** The spread of hobby menu bar apps proves the demand for an ambient view. None of them know which agent session produced a deploy. The cockpits know the session but stop at the PR.

## Open ground

1. **Session-attributed production state.** Show "prod for `web/` is red, and it was shipped by the session 'fix auth' 40 min ago". Join the session to its branch, commit, deploy and prod status. *Evidence:* the menu bar apps show deploy status without attribution. Conductor and Superset attach previews to PRs but stop at merge. Claude agent view shows PR color, not deploys. Vercel Agent investigates in the dashboard or Slack, away from where the agent lives. *Nearest:* Conductor (per-PR Deployments tab).

2. **Failure to agent in one click.** When a prod or preview build fails, open (or resume) the originating session with the build log and the Vercel MCP already attached. *Evidence:* Claude's auto-fix covers GitHub CI only. Vercel Agent proposes fixes in its own UI and Slack, not in your local Claude or Codex session. Netlify requires running the agent on Netlify. *Nearest:* Claude Desktop CI auto-fix, and Vercel Agent investigations.

3. **The cross-provider morning glance.** One quiet native surface answers "what finished overnight, what's waiting, what's live" across Claude, Codex and Gemini sessions, PRs and deploys. *Evidence:* Claude agent view is Claude-only and terminal-only. Claude's Sessions Hub is Claude-only. The Codex automations review queue is Codex-only. Superset and Emdash are multi-provider but Electron IDEs, organized around worktrees rather than your day. cmux shows "needs attention" but has no digest or deploy state. *Nearest:* Superset (multi-agent rows plus iPhone app).

4. **Native macOS, hook-grade status for every provider.** Show real working / needs input / done / failed states from each CLI's hooks, not inferred from terminal output. *Evidence:* cmux status is a notification ring (binary). iTerm2 3.7 has three states and supports Claude only. Warp's notifications need per-agent plugins. The Electron tools do multi-provider hooks (Emdash) but aren't native terminals. *Nearest:* cmux (native) and Emdash (hooks). **This is the narrowest opening.** cmux could close it in a release.

5. **Personal agent identity: your staff, not your sessions.** Named, persistent agents read from `~/.claude/agents/*.md` and Codex equivalents, each with a ghost, tier, schedule, cost and history, for one person. *Evidence:* Paperclip does named agents and org charts, but for teams with governance. Conductor has shareable "loadouts" (config, not identity; [changelog](https://www.conductor.build/changelog)). Warp Oz and Copilot automations are team or cloud schedulers. Nobody renders a solo dev's agent definitions as a roster. *Nearest:* Paperclip.

6. **A calm cockpit that isn't an IDE.** A terminal plus status, with no diff viewer, kanban or editor. *Evidence:* Superset calls itself an "agentic IDE". Emdash is an "ADE". Conductor, Devin and Nimbalyst all converge on review surfaces and boards. cmux is the only terminal-first peer, and it is drifting toward cloud VMs and "cmux AI" ([repo](https://github.com/manaflow-ai/cmux)). This is a positioning opening more than a feature one. It is defensible only with design quality.

7. **Local plus cloud in one roster, across vendors.** Claude cloud sessions, Codex cloud tasks and local terminals shown side by side. *Evidence:* each vendor unifies only its own (Claude Sessions Hub, Cursor Agents Window, Copilot app). Superset's multi-agent support is local-only. *Caveat (inferred):* cross-vendor cloud-session APIs may not be public, so feasibility is unverified.

## Threat table

| Opening | Who could close it in one release | Likelihood (12 mo) | Why |
|---|---|---|---|
| 1. Session-attributed prod state | Conductor | **High** | It already has a Deployments tab and PR timeline, and ships weekly. Extending past merge is small. |
| | Superset | Medium | Preview button plus an open sidebar-badges issue |
| | Vercel (in Claude or Codex via plugin hooks) | Medium | The plugin already has hooks and `/status`, but it lives inside the agent's context, not in an ambient UI |
| 2. Failure → agent handoff | Anthropic (Claude Desktop) | **High** | CI auto-fix exists. Adding the Vercel connector is a small step. |
| | Vercel Agent | Medium | It would need to reach into local sessions, which it hasn't done so far |
| 3. Cross-provider morning glance | Superset | Medium-high | Multi-provider plus iPhone app (Sep 28) |
| | cmux | Medium | Native, with iOS in beta |
| | Anthropic / OpenAI | Low | Each is structurally single-vendor |
| 4. Native multi-provider hook status | cmux | **High** | Same stack as Ghostties, 27.5k stars, hooks CLI already exists |
| | iTerm2 | Medium | Claude integration shipped. Codex is a copy-paste away. |
| 5. Personal agent roster | Anthropic | Medium | Owns `~/.claude/agents` and has an agent-teams direction |
| | Paperclip | Low-medium | Aimed at teams |
| 6. Calm, non-IDE cockpit | cmux | Medium | Already occupies it. The risk is that it stays there. |
| 7. Cross-vendor local + cloud roster | GitHub Agent HQ | Medium | Multi-vendor by charter, but cloud and PR-centric |
| | Others | Low | Vendors won't render competitors |

**Bottom line (judgment):** 1 and 2 are the strongest bets because they need no vendor's cooperation. They sit on public Vercel, GitHub and Claude hook data, and a native glance surface is where they're missing. They are also the most exposed to Conductor and Anthropic, so speed matters. Opening 4 alone is not a moat against cmux.

## Sources

Primary URLs are cited inline above. Coverage came from WebSearch/WebFetch on 2026-09-29. **Not verified:** Conductor's native framework, Claude Desktop's framework, and the Codex app's exact state names. The Sessions Hub details come from a secondary source (progressiverobot.com). Superset's "Open Preview" behavior is from search summaries of its docs, not a direct fetch.
