import type { Change, GhosttiesClient } from './client';
import type { Agent, Ask, AskAnswer, Conversation, Desk, Message, Project } from './types';

const ws = 'ws-personal';
const me = 'user-sean';
const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();
const now = () => new Date().toISOString();
const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value));
let seq = 0;
const nextId = (prefix: string) => `${prefix}-${Date.now().toString(36)}-${seq++}`;

const DESKS: Desk[] = [
  { id: 'desk-mbp', workspace_id: ws, name: "Sean's MacBook Pro", kind: 'mac', app_version: '1.4.0', last_seen_at: ago(0), created_at: ago(10_000) },
  { id: 'desk-studio', workspace_id: ws, name: 'Studio Mac mini', kind: 'mac', app_version: '1.3.2', last_seen_at: ago(60 * 20), created_at: ago(10_000) },
];

const PROJECTS: Project[] = [
  { id: 'proj-ghostties', workspace_id: ws, name: 'ghostties', ghost_character: 'inky', repo_url: 'https://github.com/seansmithworks/ghostties', desktop_project_id: null, last_active_at: ago(1), created_at: ago(9_000) },
  { id: 'proj-site', workspace_id: ws, name: 'website', ghost_character: 'clyde', repo_url: null, desktop_project_id: null, last_active_at: ago(48), created_at: ago(9_000) },
  { id: 'proj-renders', workspace_id: ws, name: 'renders', ghost_character: 'wisp', repo_url: null, desktop_project_id: null, last_active_at: ago(60 * 20), created_at: ago(9_000) },
];

const agent = (a: Partial<Agent> & Pick<Agent, 'id' | 'role' | 'name' | 'status'>): Agent => ({
  workspace_id: ws,
  project_id: null,
  parent_agent_id: null,
  desk_id: 'desk-mbp',
  summary: null,
  branch: null,
  ghost_character: null,
  last_activity_at: ago(5),
  created_at: ago(10_000),
  ...a,
});

const AGENTS: Agent[] = [
  agent({ id: 'agent-cos', role: 'chief_of_staff', name: 'Chief of Staff', status: 'needs_input', summary: 'One decision waiting on you', ghost_character: 'blinky', last_activity_at: ago(2) }),
  agent({ id: 'agent-gm-gt', role: 'general_manager', name: 'GM · ghostties', project_id: 'proj-ghostties', parent_agent_id: 'agent-cos', status: 'busy', summary: 'Running Workspace tests on the composer branch', ghost_character: 'inky', last_activity_at: ago(1) }),
  agent({ id: 'agent-gm-site', role: 'general_manager', name: 'GM · website', project_id: 'proj-site', parent_agent_id: 'agent-cos', status: 'idle', summary: 'Changelog page shipped', ghost_character: 'clyde', last_activity_at: ago(48) }),
  agent({ id: 'agent-gm-renders', role: 'general_manager', name: 'GM · renders', project_id: 'proj-renders', parent_agent_id: 'agent-cos', desk_id: 'desk-studio', status: 'offline', summary: null, ghost_character: 'wisp', last_activity_at: ago(60 * 20) }),
  agent({ id: 'agent-w1', role: 'worker', name: 'hover-reveal', project_id: 'proj-ghostties', parent_agent_id: 'agent-gm-gt', status: 'busy', branch: 'fix/hover-reveal-state', ghost_character: 'pinky', last_activity_at: ago(0) }),
  agent({ id: 'agent-w2', role: 'worker', name: 'browser-close', project_id: 'proj-ghostties', parent_agent_id: 'agent-gm-gt', status: 'needs_permission', branch: 'fix/browser-close-confirm', ghost_character: 'specter', last_activity_at: ago(1) }),
];

const CONVERSATIONS: Conversation[] = [
  { id: 'conv-cos', workspace_id: ws, agent_id: 'agent-cos', title: null, created_by: me, last_message_at: ago(2), created_at: ago(60) },
  { id: 'conv-gm-gt', workspace_id: ws, agent_id: 'agent-gm-gt', title: 'Today on ghostties', created_by: me, last_message_at: ago(1), created_at: ago(30) },
];

const message = (m: Partial<Message> & Pick<Message, 'id' | 'conversation_id' | 'author_kind' | 'body'>): Message => ({
  workspace_id: ws,
  author_user_id: m.author_kind === 'user' ? me : null,
  author_agent_id: null,
  kind: 'text',
  payload: {},
  client_id: null,
  created_at: now(),
  ...m,
});

const MESSAGES: Message[] = [
  message({ id: 'msg-1', conversation_id: 'conv-cos', author_kind: 'agent', author_agent_id: 'agent-cos', body: 'Morning. The hover-reveal fix merged overnight, the cloud schema has a first draft, and the website GM is idle.', created_at: ago(30) }),
  message({ id: 'msg-2', conversation_id: 'conv-cos', author_kind: 'user', body: 'Anything blocked on me?', created_at: ago(28) }),
  message({ id: 'msg-3', conversation_id: 'conv-cos', author_kind: 'agent', author_agent_id: 'agent-cos', kind: 'ask', body: 'Ship the hover-reveal fix to beta tonight?', payload: { ask_id: 'ask-1' }, created_at: ago(2) }),
  message({ id: 'msg-4', conversation_id: 'conv-gm-gt', author_kind: 'user', body: 'Where are the composer tests at?', created_at: ago(10) }),
  message({ id: 'msg-5', conversation_id: 'conv-gm-gt', author_kind: 'agent', author_agent_id: 'agent-gm-gt', body: 'Running now, 212 of 340 done. browser-close wants to run xcodebuild test and is waiting on you.', created_at: ago(1) }),
];

const ask = (a: Partial<Ask> & Pick<Ask, 'id' | 'agent_id' | 'conversation_id' | 'kind' | 'prompt'>): Ask => ({
  workspace_id: ws,
  options: [],
  recommended_option_id: null,
  status: 'open',
  answer: null,
  answered_by: null,
  answered_at: null,
  created_at: ago(5),
  ...a,
});

const ASKS: Ask[] = [
  ask({
    id: 'ask-1', agent_id: 'agent-cos', conversation_id: 'conv-cos', kind: 'decision', created_at: ago(2),
    prompt: 'Ship the hover-reveal fix to beta tonight?',
    options: [
      { id: 'ship', label: 'Ship tonight', detail: 'Goes out with the 6pm beta appcast.' },
      { id: 'hold', label: 'Hold', detail: 'Waits for tomorrow’s build.' },
    ],
    recommended_option_id: 'ship',
  }),
  ask({
    id: 'ask-2', agent_id: 'agent-w2', conversation_id: 'conv-gm-gt', kind: 'permission', created_at: ago(1),
    prompt: 'Run `xcodebuild test` on fix/browser-close-confirm?',
    options: [
      { id: 'allow', label: 'Allow' },
      { id: 'deny', label: 'Deny' },
    ],
    recommended_option_id: 'allow',
  }),
  ask({
    id: 'ask-3', agent_id: 'agent-gm-gt', conversation_id: 'conv-gm-gt', kind: 'question', created_at: ago(15),
    prompt: 'Which theme should the onboarding screenshots use?',
  }),
];

/** In-memory backend with canned replies, so every screen works with no server. */
export class StubClient implements GhosttiesClient {
  private desks = clone(DESKS);
  private projects = clone(PROJECTS);
  private agents = clone(AGENTS);
  private conversations = clone(CONVERSATIONS);
  private messages = clone(MESSAGES);
  private asks = clone(ASKS);
  private listeners = new Set<(change: Change) => void>();

  async listAgents() {
    return [...this.agents];
  }
  async listProjects() {
    return [...this.projects];
  }
  async listDesks() {
    return [...this.desks];
  }
  async listConversations() {
    return [...this.conversations];
  }
  async listMessages(conversationId: string) {
    return this.messages.filter((m) => m.conversation_id === conversationId);
  }
  async listOpenAsks() {
    return this.asks.filter((a) => a.status === 'open');
  }

  async sendMessage(conversationId: string, body: string, clientId: string) {
    const existing = this.messages.find((m) => m.conversation_id === conversationId && m.client_id === clientId);
    if (existing) return existing;
    const sent = message({ id: nextId('msg'), conversation_id: conversationId, author_kind: 'user', body, client_id: clientId });
    this.messages.push(sent);
    this.touchConversation(conversationId);
    this.emit({ table: 'messages', conversationId });

    const conversation = this.conversations.find((c) => c.id === conversationId);
    const to = this.agents.find((a) => a.id === conversation?.agent_id);
    if (to && to.status !== 'offline' && to.status !== 'ended') this.replyLater(to, conversationId);
    return sent;
  }

  async startConversation(agentId: string, body: string, clientId: string) {
    const conversation: Conversation = {
      id: nextId('conv'),
      workspace_id: ws,
      agent_id: agentId,
      title: null,
      created_by: me,
      last_message_at: now(),
      created_at: now(),
    };
    this.conversations.push(conversation);
    this.emit({ table: 'conversations' });
    await this.sendMessage(conversation.id, body, clientId);
    return conversation;
  }

  async answerAsk(askId: string, answer: AskAnswer) {
    const target = this.asks.find((a) => a.id === askId);
    if (!target) throw new Error(`No ask ${askId}`);
    target.status = 'answered';
    target.answer = answer;
    target.answered_by = me;
    target.answered_at = now();

    const label = answer.option_id
      ? target.options.find((o) => o.id === answer.option_id)?.label ?? answer.option_id
      : answer.text;
    this.messages.push(
      message({ id: nextId('msg'), conversation_id: target.conversation_id, author_kind: 'user', kind: 'answer', body: label ?? '', payload: { ask_id: askId } }),
    );
    this.emit({ table: 'messages', conversationId: target.conversation_id });
    this.emit({ table: 'asks' });

    const stillWaiting = this.asks.some((a) => a.agent_id === target.agent_id && a.status === 'open');
    if (!stillWaiting) this.setStatus(target.agent_id, 'busy');
    return target;
  }

  subscribe(listener: (change: Change) => void) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private replyLater(to: Agent, conversationId: string) {
    this.setStatus(to.id, 'busy');
    setTimeout(() => {
      this.messages.push(
        message({ id: nextId('msg'), conversation_id: conversationId, author_kind: 'agent', author_agent_id: to.id, body: 'Got it. (Stub reply: the cloud backend is not connected yet.)' }),
      );
      this.touchConversation(conversationId);
      this.emit({ table: 'messages', conversationId });
      this.setStatus(to.id, 'idle');
    }, 1200);
  }

  private touchConversation(conversationId: string) {
    const conversation = this.conversations.find((c) => c.id === conversationId);
    if (conversation) conversation.last_message_at = now();
  }

  private setStatus(agentId: string, status: Agent['status']) {
    const target = this.agents.find((a) => a.id === agentId);
    if (!target) return;
    target.status = status;
    target.last_activity_at = now();
    this.emit({ table: 'agents' });
  }

  private emit(change: Change) {
    for (const listener of this.listeners) listener(change);
  }
}
