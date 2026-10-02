# Vercel — company and platform, as of 2026-09-29

## TL;DR

1. Vercel now calls itself "agentic infrastructure." Agents trigger more than 50% of its deploys, up from under 3% six months earlier. Of 6M deploys a day, roughly half come from coding agents. These are vendor-stated numbers ([digitalapplied](https://www.digitalapplied.com/blog/vercel-ship-2026-agents-half-of-deployments-enterprise-stack), [startupfortune](https://startupfortune.com/guillermo-rauch-says-ai-agents-now-trigger-more-than-half-of-all-vercel-deployments/)).
2. Ship 2026 (London/Berlin/NYC, June) launched the **Agent Stack**: AI SDK 7, eve (an agent framework), Vercel Connect, Services, and a public beta of Vercel Agent. **Ship SF is Oct 15** and **Next.js Conf is Oct 22**, both upcoming.
3. v0 has become headless: its API went GA Aug 13, 2026, and is positioned as "infrastructure for agents" rather than a UI builder ([InfoQ](https://www.infoq.com/news/2026/08/vercel-v0-api/)).
4. Agents can read deploy state from a terminal today through the CLI (`vercel logs`, `--format=json`) and the official remote MCP (`mcp.vercel.com`). Both are **pull-only**. Nothing pushes live state to a local surface.
5. Existing menu-bar tools are hobby-scale (9 to 31 stars) and all **poll** with a personal token. Only one of them (DeployBar) covers multiple providers. I found no Vercel TUI.
6. Every peer (Netlify, Cloudflare, Railway, Render, Fly) has an official MCP. Each one handles deploy *events* differently, so there is no common event model.
7. Design leadership may be changing. Both named leaders (Head of Product Design, VP Design) have LinkedIn headlines pointing to other companies. **Verify before tailoring an application.**
8. An open role, **Product Designer, Marketplace**, is scoped to "developers *and agents*" discovering and connecting services across the dashboard, CLI, API and v0. That overlaps directly with a Ghostties-shaped project.

## Product map

| Product | What | For | Maturity |
|---|---|---|---|
| Deployments (preview, promote, Instant Rollback) | Git-driven deploys with a URL per commit | All | Mature ([docs](https://vercel.com/docs/deployments)) |
| Rolling Releases | Staged % rollout with monitoring; `vercel rolling-release` CLI | Pro/Ent | GA ([changelog](https://vercel.com/changelog/rolling-releases-are-now-generally-available)) |
| Skew Protection | Pins clients to the deployment that served their HTML | Pro/Ent | GA ([changelog](https://vercel.com/changelog/skew-protection-is-now-generally-available)) |
| "Vercel CI" | No product by this name found. CI/CD is git-integrated deploys | n/a | Unverified ([search: Vercel CI/CD page](https://vercel.com/i/ci-cd-pipeline)) |
| Sub-second artifact deploys | CLI instant path for ≤10 files / 5 MB. Pitched at agents | CLI/agents | New, Sep 17, 2026 ([nandann](https://www.nandann.com/blog/vercel-sub-second-static-artifact-deployments)) |
| Fluid compute + Active CPU | Concurrent functions, billed only for active CPU | All | Default ([blog](https://vercel.com/blog/introducing-active-cpu-pricing-for-fluid-compute)) |
| Vercel Services / Dockerfile + registry | Microservices and OCI images as first-class | Ent/backend | GA Jul 1 / June ([recap](https://vercel.com/blog/vercel-ship-2026-recap)) |
| Next.js | React framework. 16.2 current, 16.3 referenced | Web devs | Mature ([16.2](https://nextjs.org/blog/next-16-2-turbopack)) |
| Turbopack | Bundler. 16.2 claims about 87% faster dev startup | Next.js | Default, still getting heavy fixes ([robotostudio](https://robotostudio.com/blog/nextjs-16-2-for-dummies)) |
| v0 | Chat app builder, now with sandbox runtime, Git panel, DB integrations, token billing, and a GA API | Builders, agents | Mature, now headless ([InfoQ](https://www.infoq.com/news/2026/08/vercel-v0-api/)) |
| AI SDK 7 | Agent toolkit for multi-turn work, tools, files, sandboxes. 16M+ weekly downloads | TS devs | GA June 2026 ([recap](https://vercel.com/blog/vercel-ship-2026-recap)) |
| AI Gateway | One key for many models, no markup, user-scoped budgets (Sep) | Teams shipping AI | GA. About 20T tokens/mo claimed ([pricing](https://vercel.com/docs/ai-gateway/pricing), [releasebot](https://releasebot.io/updates/vercel)) |
| Vercel Agent | Code review, investigations, dashboard chat, Slack @Vercel with approval-gated actions | Pro/Ent | Public beta, usage-priced ([docs](https://vercel.com/docs/agent), [Slack](https://vercel.com/blog/introducing-vercel-for-slack)) |
| Vercel Sandbox | Ephemeral microVMs for untrusted or AI code. 19 regions, persistent Drives | Agent builders | GA, expanding ([releasebot](https://releasebot.io/updates/vercel/sandbox)) |
| Workflows / Workflow SDK | Durable execution, open source and portable | Backend/agents | GA Apr 16, 2026 ([docs](https://vercel.com/docs/workflows)) |
| eve | Open-source agent framework where "an agent is a directory," with HITL approvals and OTel. Runs 100+ internal agents | Agent builders | New, June 2026 ([blog](https://vercel.com/blog/introducing-eve)) |
| Vercel Connect | Short-lived credentials for agents calling external systems | Agent builders | GA June 2026 ([recap](https://vercel.com/blog/vercel-ship-2026-recap)) |
| Marketplace | Native integrations with unified billing, plus an "AI Agents & Services" category (CodeRabbit, Braintrust, BrowserUse…). Provider bills through the Partner API; **rev-share % is not public** | Devs, partners | Mature ([blog](https://vercel.com/blog/ai-agents-and-services-on-the-vercel-marketplace), [billing docs](https://vercel.com/docs/integrations/create-integration/billing)) |
| BotID / WAF / verified bots | Invisible bot check (Kasada). Verified bots via IP, rDNS and **Web Bot Auth** signatures. Directory at bots.fyi | Site owners | GA ([changelog](https://vercel.com/changelog/vercels-bot-verification-now-supports-web-bot-auth), [docs](https://vercel.com/docs/botid/verified-bots)) |
| Vercel MCP | Remote OAuth MCP for docs, projects, deploys, build and runtime logs, analytics. Can now deploy and purchase | Coding agents | **Beta** ([docs](https://vercel.com/docs/agent-resources/vercel-mcp)) |
| vercel-plugin / Skills | Skills and knowledge graph that make any coding agent "a Vercel expert" | Coding agents | Live ([GitHub](https://github.com/vercel/vercel-plugin)) |
| Enterprise: Passport, Security Dashboard, BYOC AWS | Internal-app auth, security view, bring your own cloud | Ent | Beta ([recap](https://vercel.com/blog/vercel-ship-2026-recap)) |

## Strategy signals (newest first)

- **Oct 22, 2026 (upcoming)**: Next.js Conf, SF and online. No Next.js 17 announced yet ([nextjs.org/conf](https://nextjs.org/conf)).
- **Oct 15, 2026 (upcoming)**: Ship SF at the Palace of Fine Arts, with agent-heavy sessions (eve, Notion, SpaceXAI, Anthropic speakers) ([vercel.com/ship](https://vercel.com/ship)).
- **Sep 27**: Fireworks Ember-1 added to AI Gateway. Also in September: user-scoped Gateway budgets and AWS PrivateLink GA ([releasebot](https://releasebot.io/updates/vercel)).
- **Sep 17**: sub-second CLI deploys, explicitly pitched as "for developers and AI agents" ([nandann](https://www.nandann.com/blog/vercel-sub-second-static-artifact-deployments)).
- **Sep 5**: a third-party count of the July 2026 incidents covers five subsystems in 16 days, including a Log Drains gap on Jul 23. Dashboard log retention is short: 1h on Hobby, 1d on Pro, 3d on Enterprise ([bex.co](https://bex.co/blog/2026/09/05/vercel-incident-cluster-auth-log-drains)).
- **Aug 13**: v0 API GA. v0 is repositioned as an agent-callable app builder ([InfoQ](https://www.infoq.com/news/2026/08/vercel-v0-api/)).
- **Jul 2026**: Vercel MCP supports the 2026-07-28 MCP spec ([docs related links](https://vercel.com/docs/agent-resources/vercel-mcp)). Vercel Agent expanded from code review into investigations and approved actions ([docs](https://vercel.com/docs/agent)).
- **Jul 6**: Rauch argues models and agents should be decoupled and that Vercel should be the multi-model, open-protocol infrastructure layer ("like AWS") as labs start competing with platforms ([TechCrunch](https://techcrunch.com/2026/07/06/vercel-ceo-guillermo-rauch-on-the-fight-to-split-off-models-from-agents/)).
- **Jun 17–30**: Ship 2026. Claims agents cause >50% of deploys, agent-deployed projects are 20x more likely to call inference, and "we are deploying software that can think" ([recap](https://vercel.com/blog/vercel-ship-2026-recap)).
- **Apr 19**: security incident. An employee's third-party AI tool (Context.ai) was compromised through OAuth, exposing some customers' non-sensitive env vars ([Vercel KB](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident), [HN](https://news.ycombinator.com/item?id=47824463)). This matters for any product asking for Vercel tokens.
- **Apr 16**: Workflows GA ([docs](https://vercel.com/docs/workflows)).
- **Apr 13**: $340M ARR run-rate as of Feb 2026, a $9.3B valuation, and "ready" for an IPO. Rauch: 30% of apps on Vercel came from agents ([TechCrunch](https://techcrunch.com/2026/04/13/vercel-ceo-guillermo-rauch-signals-ipo-readiness-as-ai-agents-fuel-revenue-surge/)).
- **Apr 9**: the "Agentic Infrastructure" manifesto (Tom Occhino) describes three layers: surfaces agents deploy to, a platform for running agents, and infrastructure that is itself agentic ([blog](https://vercel.com/blog/agentic-infrastructure)).
- **Mar 2026**: agents can discover and install Marketplace integrations from the CLI with `--format=json` (per [skills.sh vercel-cli](https://www.skills.sh/vercel/vercel/vercel-cli); the exact date is inferred from a secondary source).
- **Feb 2026**: `vercel logs` rebuilt for agents, with historical queries and git-scoped defaults ([changelog](https://vercel.com/changelog/vercel-logs-cli-command-now-optimized-for-agents-with-historical-log)).
- **Ongoing, the agent-readable web**: Vercel serves `llms.txt` and `.md` mirrors of its docs and publishes a guide to making sites agent-readable ([KB](https://vercel.com/kb/guide/make-your-documentation-readable-by-ai-agents)). It shipped `x402-mcp` for pay-per-call MCP tools ([blog](https://vercel.com/blog/introducing-x402-mcp-open-protocol-payments-for-mcp-tools)). It co-advances Web Bot Auth at the IETF ([changelog](https://vercel.com/changelog/vercels-bot-verification-now-supports-web-bot-auth)).

**Public complaints.** The top complaint is pricing: surprise bills and a $20/user Pro seat ([MassiveGRID](https://massivegrid.com/blog/why-developers-are-leaving-vercel/)). About 55% of 156 Reddit mentions are positive ([reddgrow](https://reddgrow.ai/directory/cloud-hosting/vercel)). Log retention and drain reliability are the next complaint ([bex.co](https://bex.co/blog/2026/09/05/vercel-incident-cluster-auth-log-drains)), followed by trust after the April breach. I found no strong recent thread on local dev or CLI UX specifically (not found, not proven absent).

## Deploy visibility from the terminal and from agents

Official options:
- **CLI**: `vercel logs` (historical, git-scoped), `vercel inspect`, `vercel rolling-release`, `--format=json` on some commands, and `--non-interactive` for agents ([CLI docs](https://vercel.com/docs/cli), [logs changelog](https://vercel.com/changelog/vercel-logs-cli-command-now-optimized-for-agents-with-historical-log)). JSON output is uneven. The long-running request for a global JSON output mode is still an open discussion ([GH #6704](https://github.com/vercel/vercel/discussions/6704)).
- **Vercel MCP** has tools for listing deployments, `list_deployment_events` (build output), and `get_runtime_logs`. It has an allow-list of 14 approved clients: Claude Code, Codex, Cursor, Raycast, OpenCode, Pi… ([docs](https://vercel.com/docs/agent-resources/vercel-mcp), [runtime logs](https://vercel.com/changelog/agents-can-now-access-runtime-logs-with-vercels-mcp-server)). Inferred from the tool list: there is no subscription or streaming notification of deploy state.
- **Webhooks** fire `deployment.created`, `.ready` and `.error` with HMAC signatures, but need a public receiver ([hookdeck skill](https://github.com/hookdeck/webhook-skills/tree/main/skills/vercel-webhooks)).
- **Slack**: status messages, plus @Vercel Agent with approval-gated actions ([Slack marketplace](https://vercel.com/marketplace/slack), [KB](https://vercel.com/kb/guide/run-and-track-deploys-from-slack)). **GitHub**: PR comments with preview URLs ([docs](https://vercel.com/docs/git/vercel-for-github)). **Toolbar**: comment threads, also reachable through `vercel comments` ([CLI docs](https://vercel.com/docs/cli)).

Third-party tools:

| Tool | Surface | Providers | State source | Signal |
|---|---|---|---|---|
| [vercel-deployment-menu-bar](https://github.com/andrewk17/vercel-deployment-menu-bar) | macOS menu bar, Swift | Vercel | Polls with a token | 31 stars, 14 commits |
| [DeployBar](https://github.com/snapre/DeployBar) | macOS menu bar, Swift 6 | 11 (Vercel, Netlify, CF, Railway, Render, Fly, GH…) | Polls, faster while live | 9 stars. Closest to "open, multi-provider" |
| [Deploy Status for Vercel](https://apps.apple.com/us/app/deploy-status-for-vercel/id6755970752?mt=12) | App Store menu bar | Vercel | Traffic-light icon | Paid/closed |
| [vercel-menubar-status-app](https://github.com/agustind/vercel-menubar-status-app) | Menu bar (tinyjs) | Vercel | Traffic light | Hobby |
| [Raycast: Vercel](https://www.raycast.com/vercel/vercast) | Launcher | Vercel | On-demand | Official-listed. Also v0 and AI Gateway extensions |
| [vercel-webhooks-events skill](https://tonsofskills.com/skills/vercel-webhooks-events/) | Agent skill | Vercel | Webhook receiver scaffold | Community |
| TUI | none found | — | — | **Gap** (search came back empty) |

Every one of these tools asks for a long-lived personal token. After the April OAuth breach, that is a trust cost, and Vercel Connect's short-lived credentials are the direction Vercel itself is moving (inferred).

## Peers

| Platform | Official MCP | CLI JSON | Deploy events |
|---|---|---|---|
| Vercel | Yes, remote OAuth, beta ([docs](https://vercel.com/docs/agent-resources/vercel-mcp)) | Partial (`--format=json`, `--json` on some commands) | Webhooks for deployment.* |
| Netlify | Yes, remote ([GitHub](https://github.com/netlify/netlify-mcp)) | Yes (inferred, `--json` on most commands) | Outgoing webhooks with JWS signature ([docs](https://docs.netlify.com/deploy/deploy-notifications/)). Agent Runners have no callbacks, so you poll ([KB](https://www.netlify.com/knowledge-base/how-to-run-ai-agent-tasks-remotely-with-netlify-agent-runner/)) |
| Cloudflare | Yes, multiple remote servers incl. Observability ([mcpservers](https://mcpservers.org/servers/cloudflare/mcp-server-cloudflare)) | Partial (inferred for wrangler) | Workers Builds Event Subscriptions go to a Queue, not a direct webhook ([docs](https://developers.cloudflare.com/workers/ci-cd/builds/event-subscriptions)) |
| Railway | Yes, `mcp.railway.com` ([GitHub](https://github.com/railwayapp/railway-mcp-server)) | Yes (inferred) | Project webhooks on every state transition ([docs](https://docs.railway.com/observability/webhooks)) |
| Render | Yes, GA Aug 2025 ([changelog](https://render.com/changelog/render-mcp-server-is-now-generally-available)) | Yes (inferred, `-o json`) | build/deploy started/ended webhooks, **Pro+ only** ([docs](https://render.com/docs/webhooks)) |
| Fly.io | `fly mcp` (experimental, wraps flyctl) ([docs](https://fly.io/docs/flyctl/mcp/)) | Yes, `--json`, streaming deploy JSON ([blog](https://fly.io/blog/flyctl-meets-json/)) | **None.** Poll `fly status` or the Machines API ([community](https://community.fly.io/t/deploy-notifications-webhooks/9058)) |

The takeaway: MCP is table stakes everywhere. How each platform delivers *events* is fragmented five ways (webhook, signed webhook, queue, Pro-gated webhook, none). A normalized local event model is open ground.

## Design org

- **Hannah Hearth**, Head of Product Design (Senior Director). Previously Director at Webflow and HashiCorp. She marked 90 days in the role on Mar 16, 2026 ([her site](https://www.hannahhearth.com/), [TheOrg](https://theorg.com/org/vercel/org-chart/hannah-hearth)). Her LinkedIn headline now reads "Anthropic" ([LinkedIn](https://www.linkedin.com/in/hannah-hearth-771a0a22/)). **Unverified whether she left.** She talks publicly about portfolios and design careers in the AI era ([Dive Club](https://www.dive.club/deep-dives/hannah-hearth)).
- **Manuel Muñoz Solera**, VP Design since Aug 2024, previously at GitHub and Microsoft ([X](https://x.com/mamuso/status/1819190853963075996)). His LinkedIn headline now reads "Designer at SpaceXAI" ([LinkedIn](https://www.linkedin.com/in/mamuso/)). **Unverified whether he left.**
- Vercel's "design engineer" era came from Glenn Hitchcock (design director, 2022–24) with Rauno Freiberg and Emil Kowalski ([glenn.me](https://glenn.me/vercel)). Emil and, reportedly, Rauno are now at Linear ([brainy.ink](https://brainy.ink/paper/design-engineering-role)). Rauno's move is inferred from that single source.
- Vercel frames design engineering as the design team owning the polish engineering backlogs drop: no dropped frames, cross-browser consistency, a11y, Geist font, docs playgrounds ([blog](https://vercel.com/blog/design-engineering-at-vercel)). **Geist** is the public system, with a Figma kit and the Geist Sans/Mono fonts ([Geist](https://vercel.com/geist/introduction)).
- Open roles: Senior Product Designer ($156–234K), **Product Designer, Marketplace** ($172–258K, owns Marketplace and Connect, "developers and agents," "prototype with coding agents"), Senior PD Growth, and Design Engineer, Product ([Marketplace role](https://vercel.com/careers/product-designer-marketplace-6160974004), [Senior PD](https://jobs.generalcatalyst.com/companies/vercel/jobs/64936345-senior-product-designer), [DE](https://vercel.com/careers/design-engineer-product-uk-us-5056771004)).

## Gaps I'd bet on

1. **Live deploy state pushed to where the agent runs.** The MCP and CLI are pull-only, webhooks need a public receiver, and every menu-bar app polls. Meanwhile agents cause >50% of deploys ([MCP docs](https://vercel.com/docs/agent-resources/vercel-mcp), [DeployBar](https://github.com/snapre/DeployBar), [digitalapplied](https://www.digitalapplied.com/blog/vercel-ship-2026-agents-half-of-deployments-enterprise-stack)). A terminal workspace that shows "this session's deploy is building / ready / failed" beside the agent is unclaimed.
2. **Linking a deploy back to the agent session that caused it.** Vercel counts agent-triggered deploys, but its Agent surfaces live in the dashboard and Slack ([Vercel Agent docs](https://vercel.com/docs/agent)). Nothing local ties a preview URL to the thread and prompt that produced it. This is inferred from the absence of any such tool in the inventory above.
3. **One normalized event model across providers.** Five peers use five event mechanisms (see Peers). The only multi-provider tool has 9 stars. An open schema and adapter layer with Vercel as the reference implementation fits the "open, Vercel as star" brief.
4. **Approval-gated agent actions surfaced locally.** eve and Vercel Agent both build in human-in-the-loop approvals, but they surface in Slack and the dashboard ([eve](https://vercel.com/blog/introducing-eve), [Slack Agent](https://vercel.com/blog/introducing-vercel-for-slack)). A native macOS approval queue across parallel agent sessions is the missing surface.
5. **Marketplace and Connect discovery from the terminal, for agents.** The CLI can already install integrations as JSON, and Vercel is hiring a designer specifically for "developers and agents" across CLI, API and v0 ([role](https://vercel.com/careers/product-designer-marketplace-6160974004)). A shipped Ghostties prototype of that flow doubles as the application portfolio piece.

## Sources

Inline above. Primary sources used: vercel.com/blog (ship-2026-recap, agentic-infrastructure, introducing-eve, introducing-vercel-for-slack, x402-mcp, design-engineering-at-vercel, ai-agents-and-services-on-the-vercel-marketplace), vercel.com/changelog, vercel.com/docs (agent-resources/vercel-mcp, agent, workflows, cli, botid, integrations billing), vercel.com/careers, TechCrunch (Apr 13 and Jul 6, 2026), InfoQ (Aug 2026), bex.co (Sep 5, 2026), peer docs as linked.
