# Vercel design roles — decoded (2026-09-29)

Source for all posting text: Greenhouse boards API, pulled 2026-09-29 ([API](https://boards-api.greenhouse.io/v1/boards/vercel/jobs?content=true)). Posted dates = Greenhouse `first_published`. No posting names a hiring manager; all three "report into Design."

**Headline correction to the brief:** the "Design Engineer" role is **not** vercel.com / Geist / marketing. It is the **AI Gateway** design engineer. Retarget accordingly.

**Shared tell across all three:** every posting says "people and agents." Company line: "Vercel is the agentic infrastructure company, freeing people and agents to ship what's next." All three require using coding agents yourself.

---

## 1. Product Designer, Marketplace
[Posting](https://vercel.com/careers/product-designer-marketplace-6160974004) · Hybrid SF (fully remote if outside commuting distance of SF/NY/London/Berlin) · **Senior or Staff**, "calibrate level based on experience" · **$172k–$258k SF base** + equity · posted 2026-08-27.

**Owns:** "product design for Vercel Marketplace and Vercel Connect … design both sides of the ecosystem: builders choosing and managing services, and partners creating and operating integrations across the Vercel dashboard, CLI, API-driven agent flows, v0, and partner tools."

**What they shipped in 2026:**
- Jul 14 — AgentMail on Marketplace ([changelog](https://vercel.com/changelog/agentmail-vercel-marketplace)).
- Aug 6 — CLI install "now also installs that provider's agent skills from skills.sh"; new `vercel integration discover` ([changelog](https://vercel.com/changelog/vercel-marketplace-agent-skills)).
- Aug 25 — Vercel Connect GA: short-lived, task-scoped tokens, 100+ connectors, one-time consent flow. "Credentials that used to sit in environments long after the work finished now expire on their own." ([blog](https://vercel.com/blog/the-end-of-credential-sprawl-for-agents)).

**Must have (verbatim):**
- "Your portfolio makes your contribution, decisions, shipped outcomes, and impact after launch easy to understand."
- "You have independently owned ambiguous, technically complex product work from problem framing through launch and iteration."
- "You reason about systems while maintaining a high bar for interaction and visual craft."
- "You use qualitative and quantitative evidence, define success measures, and change direction when evidence challenges the hypothesis."
- "You make complex products feel clear and trustworthy, including edge cases, recovery, language, and accessibility."
- "You work directly with Product and Engineering, read APIs or code when useful, and explain tradeoffs clearly."
- "You independently use coding agents to prototype interactions, inspect implementation, and learn unfamiliar systems. Curiosity and agency with these tools are required."
- "Production engineering experience is not required."

**Nice to have (verbatim):**
- "Have designed a marketplace, integrations platform, partner ecosystem, or other multi-sided product."
- "Understand OAuth, permissions, secrets, billing, developer tooling, or infrastructure products."
- "Have shipped AI or agent experiences, especially workflows that move between human approval and autonomous action."
- "Have an engineering background or experience contributing production web code."

**Roadmap tells:**
- "defining how integrations and agent access should work next". Agents are becoming first-class Marketplace customers, not just humans in a dashboard.
- "API-driven agent flows, v0, and partner tools". Provisioning moves out of the dashboard into wherever the agent is working.
- "workflows that move between human approval and autonomous action". The open design problem is the consent/approval moment (Connect's consent flow is v1).

**Fit for Sean:**
- Matches: (1) Ghostties is literally a human-approval surface for autonomous agents (the "needs you" state, status engine); (2) coding-agent prototyping is his daily practice, and "production engineering experience is not required"; (3) systems + craft is stated verbatim as the bar.
- Gaps: (1) no multi-sided/partner product or billing work shown; (2) "quantitative evidence … success measures" (ghostties.org has no analytics).
- **Artifact that lands hardest:** the Ghostties status-engine case study. A shipped agent-state UI where he found the "blue ghost" lying (`.idle` needed a signal the agent never sent), inverted the model, and made "needs you" trustworthy. This is the approval-vs-autonomy handoff they list as a bonus, shown as a before/after.

**Bridge idea — "Agent asks, human grants" in Ghostties.** When a Claude Code session in Ghostties needs a service (a database, email, auth), it doesn't silently paste a key into `.env`. It raises a consent card in that session's sidebar row: provider, scope, environment, cost tier, expiry. One keystroke approves, and it runs `vercel integration add` with a Connect-scoped token. The row then shows the grant as a live, expiring chip, and revoke is one click. That is Marketplace + Connect designed from the agent's side, and it is exactly the "human approval and autonomous action" seam. It needs no partner access; it drives the public CLI.

---

## 2. Senior Product Designer, Growth
[Posting](https://vercel.com/careers/senior-product-designer-growth-6131210004) · Hybrid SF/NYC (remote if outside office radius) · **Senior** · **$172k–$258k SF base** + equity · posted 2026-07-30 (open two months, so a harder fill).

**Owns:** "help define Growth Design at Vercel and shape the complete self-serve journey: signup, onboarding, first project and deployment, adoption, conversion, expansion, and retention. The work spans people, agents, and the handoffs between them."

**What the surface looks like in 2026:**
- Feb 26 — dashboard redesign became default ([changelog](https://vercel.com/changelog/dashboard-navigation-redesign-rollout)).
- Aug 28 — "create eve agents directly from the Vercel dashboard", scaffolded, private repo, deployed as a new project ([changelog](https://vercel.com/changelog/build-and-deploy-eve-agents-from-the-vercel-dashboard)). This is a new first-project path.
- A sibling PM Dashboard posting (2026-09-24) says the dashboard shifts "from what is a project listing page today to a personalized, agent-powered surface that proactively helps users ship and discover value" ([Greenhouse 6205772004](https://job-boards.greenhouse.io/vercel/jobs/6205772004)).

**Must have (verbatim):**
- "Your portfolio demonstrates strong product design fundamentals and measurable outcomes. It shows how you identified opportunities, understood a funnel, chose what to measure, tested ideas, and improved a shipped product."
- "You have owned ambiguous, complex work from problem framing through launch and iteration. You create clarity and make progress without waiting for a complete brief."
- "You can form useful hypotheses, choose success and guardrail measures, and interpret quantitative and qualitative evidence with Data partners."
- "You build interactive prototypes independently using modern AI tools. You are comfortable prompting, working near code, and learning whatever helps you validate an idea."
- "You design clear, trustworthy experiences across skill levels and abilities. You care about interaction details, edge cases, language, accessibility, and recovery."
- "…You know when to use or evolve a system and when a one-off is the fastest responsible way to learn."

**Nice to have (verbatim):**
- "Have shipped AI or agent experiences."
- "Have an engineering background or experience contributing production web code."
- "Have designed developer tools, infrastructure, or other technical products, or are already familiar with Vercel."

**Roadmap tells:**
- "for people and agents" and "the handoffs between them". Agents are signing up and deploying. The agent-to-human handoff is where activation happens (e.g. an agent deploys, the human claims/upgrades).
- "Figma, v0, Cursor, and Claude Code" named as prototyping tools. Claude Code fluency is on-brief.

**Fit for Sean:**
- Matches: (1) onboarding is a stated strength and Ghostties has a real onboarding sheet + npm/Homebrew install path; (2) "Claude Code" is named, and he ships with it daily; (3) shipped agent experiences (bonus line) and familiarity with Vercel.
- Gaps: (1) **this is the posting's #1 must-have and his biggest hole:** "measurable outcomes … chose what to measure". ghostties.org has no analytics (per project memory), so there are no funnel numbers to show; (2) no documented experiment/A-B history.
- **Artifact that lands hardest:** a shipped Ghostties activation funnel with numbers: install → first launch → first agent session → day-7 return. It needs a stated hypothesis, one change shipped, and the measured delta. Without numbers, this role reads as a stretch.

**Bridge idea — "Time to first agent" loop.** Instrument Ghostties end-to-end (ghostties.org visit → installer run → first launch → first agent session started → session reaches "done"), using Vercel Web Analytics on the site plus privacy-respecting, opt-in app pings. Then run one real experiment on the weakest step. The obvious candidate is the onboarding sheet: default to launching a first agent session with a pre-filled composer line, versus today's flow. Write it up as hypothesis → metric → guardrail → result. This fills the exact gap in Growth's own language.

---

## 3. Design Engineer (AI Gateway)
[Posting](https://vercel.com/careers/design-engineer-us-6129441004) · **Remote – United States** (office anchor days if near SF/NY/London/Berlin) · level not stated · **$208k–$312k SF base** + equity · posted 2026-09-15 (newest).

**Owns:** "You will be the Design Engineer for AI Gateway, owning product design and frontend implementation." AI Gateway "gives developers one place to connect applications and agents to hundreds of models with one API key … routing and fallbacks, unifies billing and observability." Embedded with a PM + engineers, "room to pursue design-led improvements across Vercel."

**What they shipped in 2026:** a dedicated Logs page (Jul 31), listing every request "with cost, token counts, duration, and the model, provider, and region" ([changelog](https://vercel.com/changelog/ai-gateway-logs)).

**Must have (verbatim):**
- "Your work shows what you personally identified, designed, built, shipped, and learned after launch."
- "You build production-quality web applications with React and TypeScript and can contribute confidently in a large, existing codebase."
- "You bring strong visual and interaction craft and have made technical or data-rich products understandable without removing the control advanced users need."
- "You can move between graphical interfaces, CLI workflows, API behavior, and implementation details, treating accessibility, performance, failure recovery, and instrumentation as part of the design."
- "You use customer research and product data to make decisions…"
- "You use coding agents in your daily work, but you can explain, test, debug, and take responsibility for the code they help produce."
- "There is no required path into this role … We care about the quality of what you have shipped and the judgment behind it."

**Nice to have (verbatim):**
- "Have experience with developer tools, infrastructure products, model marketplaces, or observability experiences."
- "Have worked with AI models, providers, inference platforms, guardrails, or AI application tooling."
- "Have experience with APIs, command-line tools, structured product content, or agent-facing interfaces."
- "Have built an application or agent with Vercel's AI SDK or AI Gateway."

**Roadmap tells:**
- "the model ecosystem changes every week" and "patterns that extend across new providers, modalities, and workloads". They want a catalog/config system, not one-off pages.
- "diagnose a failed request" and "budgets, credentials, and security controls". The next surfaces are failure diagnosis, spend governance and privacy controls, all enterprise-leaning.

**Fit for Sean:**
- Matches: (1) a CLI/terminal-native designer, which is rare, and the posting explicitly values CLI and API as design surfaces; (2) "no required path," judged on shipped work (Ghostties is shipped, with releases); (3) coding-agent daily practice.
- Gaps: (1) **the hard one:** "production-quality web applications with React and TypeScript … large, existing codebase". His shipped app is Swift/Zig, and his React work is sites, not a large app; (2) no AI SDK/Gateway build yet (a cheap bonus to close).
- **Artifact that lands hardest:** a shipped React/TS, data-rich surface on Vercel that makes AI request data legible. Concretely, a per-session cost/model/failure view built on AI SDK + Gateway (see bridge).

**Bridge idea — "Session ledger."** Build a small Next.js + AI SDK app routed through AI Gateway, deployed on Vercel. Better still, route Ghostties' own agent traffic through it, *assuming* Claude Code can target the Gateway's Anthropic-compatible endpoint (inferred, verify first). It shows each agent session as a row: model, provider, fallback taken, tokens, cost, latency. A failed request expands into a plain-language diagnosis ("provider 429 → fell back to X, +$0.02"). Add the same data as a sidebar chip and `--json` CLI output. That covers GUI + CLI + API in one piece, and it earns the "built with AI SDK or AI Gateway" bonus outright.

---

## Other open design roles at Vercel (Greenhouse, 2026-09-29)

| Role | Location | Base (SF) | Posted | Note |
|---|---|---|---|---|
| [Senior Brand Designer](https://job-boards.greenhouse.io/vercel/jobs/5579560004) | Hybrid SF/NYC | $156k–$234k | 2025-07-08 | Open 14+ months |
| [Presentation Designer](https://job-boards.greenhouse.io/vercel/jobs/6128387004) | Hybrid SF/NYC | $152k–$209k | 2026-07-30 | Decks + presentation systems; not a fit |

5 of 91 roles are design; none on v0/agents. **Watch:** [PM, Software Factory](https://job-boards.greenhouse.io/vercel/jobs/6210353004), posted today, is a "new product area that puts AI agents on every stage of the development loop … while keeping people on the judgment calls. Human time and human attention has become the bottleneck." That is Ghostties' thesis almost word for word. A design role will likely follow (inferred).

## Recommendation
Rank for Sean: **Marketplace first** (production engineering "not required," with an approval/autonomy bonus that Ghostties directly demonstrates). **Design Engineer second** (highest comp and remote-US, but the React/TS large-codebase bar is a real gap). **Growth third**, unless he ships the measured funnel first. Name Software Factory in any cover note.
