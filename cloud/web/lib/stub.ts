import type {
  Agent,
  Ask,
  Conversation,
  ConversationRead,
  Desk,
  Message,
  Project,
  Task,
  Workspace,
} from "@ghostties/contract";

// Stub rows typed by @ghostties/contract, so `lib/data.ts` can swap them for
// Supabase queries without touching a component. Richer than the contract's
// own fixtures (three projects, a full org tree, two open asks), and on a
// fixed clock so prerendered pages are deterministic.

export const STUB_NOW = "2026-10-22T16:00:00Z";
const ago = (minutes: number) =>
  new Date(Date.parse(STUB_NOW) - minutes * 60_000).toISOString();

const ws = "00000000-0000-4000-8000-000000000001";
const user = "user-sean";
const created_at = ago(60 * 24 * 30);

export const workspace: Workspace = {
  id: ws,
  name: "Sean",
  owner_id: user,
  created_at,
};

export const desks: Desk[] = [
  desk("desk-mbp", "MacBook Pro", "mac", "1.4.0", 0),
  desk("desk-cloud", "Cloud runner", "cloud", null, 1),
  desk("desk-studio", "Mac Studio", "mac", "1.3.2", 60 * 26),
];

export const projects: Project[] = [
  project("proj-switch", "switchboard", "inky", 1),
  project("proj-atlas", "atlas-api", "clyde", 6),
  project("proj-field", "fieldwork", "pinky", 48),
];

export const agents: Agent[] = [
  agent(
    "agent-cos",
    "chief_of_staff",
    "Chief of staff",
    null,
    null,
    "desk-cloud",
    "needs_input",
    "Two decisions waiting, three desks running.",
    null,
    "blinky",
    2,
  ),
  agent(
    "agent-gm-switch",
    "general_manager",
    "switchboard GM",
    "proj-switch",
    "agent-cos",
    "desk-mbp",
    "busy",
    "Rate limiter in review, reconnect race running.",
    null,
    "inky",
    4,
  ),
  agent(
    "agent-gm-atlas",
    "general_manager",
    "atlas-api GM",
    "proj-atlas",
    "agent-cos",
    "desk-mbp",
    "needs_permission",
    "Auth migration wants to apply 0042 locally.",
    null,
    "clyde",
    6,
  ),
  agent(
    "agent-gm-field",
    "general_manager",
    "fieldwork GM",
    "proj-field",
    "agent-cos",
    "desk-cloud",
    "idle",
    "Offline sync shipped. Nothing queued.",
    null,
    "pinky",
    48,
  ),
  agent(
    "agent-w-reconnect",
    "worker",
    "reconnect race",
    "proj-switch",
    "agent-gm-switch",
    "desk-mbp",
    "busy",
    "Reproducing the race under load.",
    "fix/reconnect-race",
    "wisp",
    1,
  ),
  agent(
    "agent-w-ratelimit",
    "worker",
    "rate limiter",
    "proj-switch",
    "agent-gm-switch",
    "desk-mbp",
    "busy",
    "Token bucket tests passing, writing docs.",
    "feat/rate-limiter",
    "ember",
    3,
  ),
  agent(
    "agent-w-auth",
    "worker",
    "auth migration",
    "proj-atlas",
    "agent-gm-atlas",
    "desk-mbp",
    "needs_permission",
    "Waiting to run migration 0042.",
    "feat/sessions-to-jwt",
    "hex",
    6,
  ),
  agent(
    "agent-w-sync",
    "worker",
    "offline sync",
    "proj-field",
    "agent-gm-field",
    "desk-cloud",
    "ended",
    "Merged.",
    "feat/offline-sync",
    "mist",
    52,
  ),
];

export const conversations: Conversation[] = agents
  .filter((a) => a.role !== "worker")
  .map((a) => ({
    id: `conv-${a.id}`,
    workspace_id: ws,
    agent_id: a.id,
    title: a.name,
    created_by: user,
    last_message_at: a.last_activity_at,
    created_at,
  }));

/** Read markers: the fieldwork GM is read, the others have new messages. */
export const reads: ConversationRead[] = [
  {
    conversation_id: "conv-agent-gm-field",
    user_id: user,
    last_read_at: ago(40),
  },
  { conversation_id: "conv-agent-cos", user_id: user, last_read_at: ago(12) },
];

export const messages: Message[] = [
  msg("conv-agent-cos", "user", "Morning. What needs me today?", 40),
  msg(
    "conv-agent-cos",
    "agent",
    "Three desks are running. switchboard has the rate limiter in review and the reconnect race still reproducing. atlas-api is blocked on you: the auth migration wants to apply 0042 to the local database. fieldwork shipped offline sync last night and has nothing queued.",
    39,
  ),
  msg(
    "conv-agent-cos",
    "user",
    "Approve the migration if tests pass. Anything else?",
    12,
  ),
  msg(
    "conv-agent-cos",
    "agent",
    "Tests passed (atlas-api/auth 0.418s), so I passed your approval on, but the desk still wants a direct yes for psql. One more: should fieldwork pick up photo export, or stay idle until the beta feedback lands?",
    2,
  ),
  msg(
    "conv-agent-gm-switch",
    "agent",
    "Rate limiter is up for review. Reconnect race reproduces 1 in 40 runs under load; narrowing it to the heartbeat timer.",
    4,
  ),
  msg(
    "conv-agent-gm-atlas",
    "agent",
    "auth migration is ready to apply migration 0042 to the local database.",
    7,
  ),
  msg("conv-agent-gm-atlas", "system", "Approval requested", 6, "status"),
  msg(
    "conv-agent-gm-field",
    "agent",
    "Offline sync merged. No open work on fieldwork.",
    48,
  ),
];

export const asks: Ask[] = [
  ask(
    "ask-migration",
    "agent-gm-atlas",
    "conv-agent-gm-atlas",
    "permission",
    "Run psql -f migrations/0042_sessions_to_jwt.sql?",
    [
      {
        id: "yes",
        label: "Yes",
        detail: "Applies 0042 to the local database.",
      },
      { id: "always", label: "Yes, always for psql" },
      { id: "no", label: "No", detail: "Tell the agent what to do instead." },
    ],
    "yes",
    6,
  ),
  ask(
    "ask-fieldwork",
    "agent-cos",
    "conv-agent-cos",
    "decision",
    "Should fieldwork pick up photo export?",
    [
      { id: "start", label: "Start photo export" },
      { id: "wait", label: "Wait for beta feedback" },
    ],
    "wait",
    2,
  ),
];

export const tasks: Task[] = [
  task("proj-switch", "agent-w-reconnect", "reconnect race", "running", 1),
  task("proj-switch", "agent-w-ratelimit", "rate limiter", "review", 3),
  task("proj-switch", null, "flaky ci", "done", 300),
  task("proj-switch", null, "deps bump", "backlog", 900),
  task("proj-atlas", "agent-w-auth", "auth migration", "needs-you", 6),
  task("proj-field", "agent-w-sync", "offline sync", "done", 52),
  task("proj-field", null, "photo export", "inbox", 200),
];

// MARK: - Row builders

function desk(
  id: string,
  name: string,
  kind: Desk["kind"],
  app_version: string | null,
  seen: number,
): Desk {
  return {
    id,
    workspace_id: ws,
    name,
    kind,
    app_version,
    last_seen_at: ago(seen),
    created_at,
  };
}

function project(
  id: string,
  name: string,
  ghost: string,
  active: number,
): Project {
  return {
    id,
    workspace_id: ws,
    name,
    ghost_character: ghost,
    repo_url: `https://github.com/seansmithworks/${name}`,
    desktop_project_id: null,
    last_active_at: ago(active),
    created_at,
  };
}

function agent(
  id: string,
  role: Agent["role"],
  name: string,
  project_id: string | null,
  parent_agent_id: string | null,
  desk_id: string | null,
  status: Agent["status"],
  summary: string,
  branch: string | null,
  ghost: string,
  active: number,
): Agent {
  return {
    id,
    workspace_id: ws,
    role,
    name,
    project_id,
    parent_agent_id,
    desk_id,
    status,
    summary,
    branch,
    ghost_character: ghost,
    last_activity_at: ago(active),
    created_at,
  };
}

function msg(
  conversation_id: string,
  author_kind: Message["author_kind"],
  body: string,
  minutesAgo: number,
  kind: Message["kind"] = "text",
): Message {
  const agentId =
    conversations.find((c) => c.id === conversation_id)?.agent_id ?? null;
  return {
    id: `${conversation_id}-${minutesAgo}-${author_kind}`,
    workspace_id: ws,
    conversation_id,
    author_kind,
    author_user_id: author_kind === "user" ? user : null,
    author_agent_id: author_kind === "agent" ? agentId : null,
    kind,
    body,
    payload: {},
    client_id: null,
    created_at: ago(minutesAgo),
  };
}

function ask(
  id: string,
  agent_id: string,
  conversation_id: string,
  kind: Ask["kind"],
  prompt: string,
  options: Ask["options"],
  recommended_option_id: string,
  minutesAgo: number,
): Ask {
  return {
    id,
    workspace_id: ws,
    agent_id,
    conversation_id,
    kind,
    prompt,
    options,
    recommended_option_id,
    status: "open",
    answer: null,
    answered_by: null,
    answered_at: null,
    created_at: ago(minutesAgo),
  };
}

function task(
  project_id: string,
  agent_id: string | null,
  title: string,
  lane: Task["lane"],
  minutesAgo: number,
): Task {
  return {
    id: `task-${title.replace(/\s+/g, "-")}`,
    workspace_id: ws,
    project_id,
    agent_id,
    title,
    lane,
    priority: "none",
    branch: null,
    body: "",
    source: null,
    source_id: null,
    created_at,
    updated_at: ago(minutesAgo),
  };
}
