import "server-only";
import {
  isDeskOnline,
  NEEDS_YOU_STATUSES,
  type Agent,
  type Desk,
} from "@ghostties/contract";
import * as stub from "./stub";

// The one seam between the UI and the backend. Every function returns rows
// typed by @ghostties/contract; today they read `lib/stub.ts`. When the
// backend is live, each body becomes a query through `lib/supabase/server.ts`
// (reads via `from(table).select()`, scoped by RLS) and no component changes.

export async function getWorkspace() {
  return stub.workspace;
}

export async function listAgents() {
  return stub.agents;
}

export async function getAgent(id: string) {
  return stub.agents.find((a) => a.id === id) ?? null;
}

export async function listDesks() {
  return stub.desks;
}

export async function listProjects() {
  return stub.projects;
}

export async function listTasks() {
  return stub.tasks;
}

export async function listOpenAsks() {
  return stub.asks.filter((a) => a.status === "open");
}

/** agent_id -> has unread, per the contract: last_message_at > last_read_at. */
export async function unreadByAgent() {
  return Object.fromEntries(
    stub.conversations.map((c) => {
      const read = stub.reads.find(
        (r) => r.conversation_id === c.id,
      )?.last_read_at;
      const unread = Boolean(
        c.last_message_at && (!read || c.last_message_at > read),
      );
      return [c.agent_id, unread];
    }),
  ) as Record<string, boolean>;
}

export async function getConversationForAgent(agentId: string) {
  const conversation = stub.conversations.find((c) => c.agent_id === agentId);
  if (!conversation) return null;
  return {
    conversation,
    messages: stub.messages.filter(
      (m) => m.conversation_id === conversation.id,
    ),
    asks: stub.asks.filter(
      (a) => a.conversation_id === conversation.id && a.status === "open",
    ),
  };
}

/** The clock pages render against. Fixed while on stub data. */
export function now() {
  return stub.STUB_NOW;
}

export function deskOnline(desk: Desk) {
  return isDeskOnline(desk, new Date(now()));
}

/** The roles you talk to directly: the chief of staff and each GM. */
export function isConversational(agent: Agent) {
  return agent.role !== "worker";
}

export function needsYou(agent: Agent) {
  return NEEDS_YOU_STATUSES.includes(agent.status);
}
