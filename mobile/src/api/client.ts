import type { Agent, Ask, AskAnswer, Conversation, Desk, Message, Project } from './types';

export type Unsubscribe = () => void;

/**
 * Everything the app needs from the backend, one method per contract RPC or
 * table read. `StubClient` implements it in memory today; a Supabase client
 * (`supabase.rpc` for writes, `postgres_changes` on `REALTIME_TABLES` for
 * `subscribe`) replaces it without touching a screen.
 */
export interface GhosttiesClient {
  listAgents(): Promise<Agent[]>;
  listProjects(): Promise<Project[]>;
  listDesks(): Promise<Desk[]>;
  listConversations(): Promise<Conversation[]>;
  listMessages(conversationId: string): Promise<Message[]>;
  /** Open asks only: the "needs you" list. */
  listOpenAsks(): Promise<Ask[]>;

  /** RPC `send_message`. Idempotent on (conversationId, clientId). */
  sendMessage(conversationId: string, body: string, clientId: string): Promise<Message>;
  /** RPC `start_conversation`: opens a conversation with an agent and sends the first message. */
  startConversation(agentId: string, body: string, clientId: string): Promise<Conversation>;
  /** RPC `answer_ask`. */
  answerAsk(askId: string, answer: AskAnswer): Promise<Ask>;

  /** Fires after a row in one of these tables changes. */
  subscribe(listener: (change: Change) => void): Unsubscribe;
}

export type Change =
  | { table: 'agents' | 'asks' | 'conversations' | 'projects' | 'desks' }
  | { table: 'messages'; conversationId: string };
