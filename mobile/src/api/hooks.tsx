import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

import type { Change, GhosttiesClient } from './client';
import { StubClient } from './stub';
import type { Agent, Ask, Conversation, Desk, Message, Project } from './types';

const ClientContext = createContext<GhosttiesClient | null>(null);

export function ClientProvider({ client, children }: { client?: GhosttiesClient; children: ReactNode }) {
  const [value] = useState(() => client ?? new StubClient());
  return <ClientContext.Provider value={value}>{children}</ClientContext.Provider>;
}

export function useClient() {
  const client = useContext(ClientContext);
  if (!client) throw new Error('useClient outside ClientProvider');
  return client;
}

/**
 * Loads with `load`, then reloads whenever the client reports a change that
 * `matches` accepts. `key` names what `load` reads, so a new key reloads.
 */
function useLive<T>(
  key: string,
  load: (c: GhosttiesClient) => Promise<T>,
  matches: (change: Change) => boolean,
  initial: T,
) {
  const client = useClient();
  const [data, setData] = useState<T>(initial);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let live = true;
    const refresh = () =>
      load(client).then((next) => {
        if (!live) return;
        setData(next);
        setLoading(false);
      });
    refresh();
    const unsubscribe = client.subscribe((change) => {
      if (matches(change)) refresh();
    });
    return () => {
      live = false;
      unsubscribe();
    };
    // `load` and `matches` are new every render; `key` stands for what they read.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [client, key]);

  return { data, loading };
}

export function useAgents() {
  return useLive<Agent[]>('agents', (c) => c.listAgents(), (ch) => ch.table === 'agents', []);
}

export function useAgent(id: string) {
  const { data, ...rest } = useAgents();
  return { agent: data.find((a) => a.id === id), ...rest };
}

export function useProjects() {
  return useLive<Project[]>('projects', (c) => c.listProjects(), (ch) => ch.table === 'projects', []);
}

export function useDesks() {
  return useLive<Desk[]>('desks', (c) => c.listDesks(), (ch) => ch.table === 'desks', []);
}

export function useConversations() {
  return useLive<Conversation[]>('conversations', (c) => c.listConversations(), (ch) => ch.table === 'conversations', []);
}

/** Open asks, newest first. */
export function useOpenAsks() {
  return useLive<Ask[]>(
    'asks',
    async (c) => (await c.listOpenAsks()).sort((a, b) => b.created_at.localeCompare(a.created_at)),
    (ch) => ch.table === 'asks',
    [],
  );
}

export function useMessages(conversationId: string | undefined) {
  return useLive<Message[]>(
    `messages:${conversationId}`,
    async (c) =>
      conversationId
        ? (await c.listMessages(conversationId)).sort((a, b) => a.created_at.localeCompare(b.created_at))
        : [],
    (ch) => ch.table === 'messages' && ch.conversationId === conversationId,
    [],
  );
}
