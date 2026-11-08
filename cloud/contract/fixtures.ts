// Sample rows for stubs and previews. One workspace: a chief of staff, a
// general manager on ghostties with two workers, one open decision.
import type { Agent, Ask, Conversation, Desk, Message, Project, Task, Workspace } from "./index";

const ws = "00000000-0000-4000-8000-000000000001";
const t = (minutesAgo: number) => new Date(Date.now() - minutesAgo * 60_000).toISOString();

export const workspace: Workspace = { id: ws, name: "Personal", owner_id: "user-sean", created_at: t(10_000) };

export const desks: Desk[] = [
  { id: "desk-mbp", workspace_id: ws, name: "Sean's MacBook Pro", kind: "mac", app_version: "1.4.0", last_seen_at: t(0), created_at: t(10_000) },
];

export const projects: Project[] = [
  { id: "proj-ghostties", workspace_id: ws, name: "ghostties", ghost_character: "blinky", repo_url: "https://github.com/seansmithworks/ghostties", desktop_project_id: null, last_active_at: t(2), created_at: t(9_000) },
];

export const agents: Agent[] = [
  { id: "agent-cos", workspace_id: ws, role: "chief_of_staff", name: "Chief of Staff", project_id: null, parent_agent_id: null, desk_id: "desk-mbp", status: "idle", summary: "Morning brief ready", branch: null, ghost_character: null, last_activity_at: t(5), created_at: t(10_000) },
  { id: "agent-gm", workspace_id: ws, role: "general_manager", name: "GM · ghostties", project_id: "proj-ghostties", parent_agent_id: "agent-cos", desk_id: "desk-mbp", status: "needs_input", summary: "Waiting on merge call for #260", branch: null, ghost_character: "blinky", last_activity_at: t(3), created_at: t(9_000) },
  { id: "agent-w1", workspace_id: ws, role: "worker", name: "hover-reveal", project_id: "proj-ghostties", parent_agent_id: "agent-gm", desk_id: "desk-mbp", status: "busy", summary: "Running sidebar tests", branch: "fix/hover-reveal-state", ghost_character: "inky", last_activity_at: t(0), created_at: t(120) },
  { id: "agent-w2", workspace_id: ws, role: "worker", name: "browser-close", project_id: "proj-ghostties", parent_agent_id: "agent-gm", desk_id: "desk-mbp", status: "needs_permission", summary: "Wants to run xcodebuild test", branch: "fix/browser-close-confirm", ghost_character: "clyde", last_activity_at: t(1), created_at: t(90) },
];

export const conversations: Conversation[] = [
  { id: "conv-1", workspace_id: ws, agent_id: "agent-gm", title: "Today on ghostties", created_by: "user-sean", last_message_at: t(3), created_at: t(30) },
];

export const messages: Message[] = [
  { id: "msg-1", workspace_id: ws, conversation_id: "conv-1", author_kind: "user", author_user_id: "user-sean", author_agent_id: null, kind: "text", body: "Where are we on the hover reveal?", payload: {}, client_id: null, created_at: t(30) },
  { id: "msg-2", workspace_id: ws, conversation_id: "conv-1", author_kind: "agent", author_user_id: null, author_agent_id: "agent-gm", kind: "text", body: "Tests are green on fix/hover-reveal-state. #260 is ready to merge.", payload: {}, client_id: null, created_at: t(4) },
  { id: "msg-3", workspace_id: ws, conversation_id: "conv-1", author_kind: "agent", author_user_id: null, author_agent_id: "agent-gm", kind: "ask", body: "Merge #260?", payload: { ask_id: "ask-1" }, client_id: null, created_at: t(3) },
];

export const asks: Ask[] = [
  { id: "ask-1", workspace_id: ws, agent_id: "agent-gm", conversation_id: "conv-1", kind: "decision", prompt: "Merge #260?", options: [{ id: "merge", label: "Merge it", detail: "Squash-merges and deletes the branch." }, { id: "hold", label: "Hold", detail: "Leaves it open for another look." }], recommended_option_id: "merge", status: "open", answer: null, answered_by: null, answered_at: null, created_at: t(3) },
];

export const tasks: Task[] = [
  { id: "task-1", workspace_id: ws, project_id: "proj-ghostties", agent_id: "agent-w1", title: "Hover reveal is a sidebar mode", lane: "review", priority: "high", branch: "fix/hover-reveal-state", body: "", source: null, source_id: null, created_at: t(200), updated_at: t(4) },
  { id: "task-2", workspace_id: ws, project_id: "proj-ghostties", agent_id: null, title: "Cloud backend prep", lane: "running", priority: "medium", branch: null, body: "", source: null, source_id: null, created_at: t(20), updated_at: t(1) },
];
