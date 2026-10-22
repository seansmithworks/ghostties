import { Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, KeyboardAvoidingView, Platform, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useAgent, useAgents, useClient, useConversations, useMessages, useOpenAsks } from '@/api/hooks';
import type { LocalMessage } from '@/api/types';
import { AskCard } from '@/components/ask-card';
import { Composer } from '@/components/composer';
import { Ghost } from '@/components/ghost';
import { MessageBubble } from '@/components/message-bubble';
import { STATUS_LABEL, StatusGlyph } from '@/components/status-glyph';
import { MaxContentWidth, Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { uuid } from '@/utils/uuid';

/**
 * A conversation with a chief of staff or general manager. No terminal: words
 * and asks only. Opens the conversation named in the route, else the agent's
 * latest; the first message to an agent with none starts one.
 */
export default function AgentConversation() {
  const params = useLocalSearchParams<{ id: string; conversation?: string }>();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const client = useClient();
  const { agent } = useAgent(params.id);
  const { data: agents } = useAgents();
  const { data: conversations } = useConversations();
  const { data: openAsks } = useOpenAsks();

  const [started, setStarted] = useState<string>();
  const conversationId =
    params.conversation ??
    started ??
    conversations
      .filter((c) => c.agent_id === params.id)
      .sort((a, b) => (b.last_message_at ?? '').localeCompare(a.last_message_at ?? ''))[0]?.id;

  const { data: messages } = useMessages(conversationId);
  const [pending, setPending] = useState<LocalMessage[]>([]);
  const shown = useMemo(() => {
    const echoed = new Set(messages.map((m) => m.client_id).filter(Boolean));
    return [...messages, ...pending.filter((p) => !echoed.has(p.client_id))];
  }, [messages, pending]);

  const list = useRef<FlatList<LocalMessage>>(null);
  useEffect(() => {
    if (shown.length) list.current?.scrollToEnd({ animated: true });
  }, [shown.length]);

  const offline = agent?.status === 'offline' || agent?.status === 'ended';

  const send = async (body: string) => {
    if (!agent) return;
    const clientId = uuid();
    setPending((p) => [...p, localMessage(conversationId ?? '', body, clientId)]);
    if (conversationId) {
      await client.sendMessage(conversationId, body, clientId);
    } else {
      const conversation = await client.startConversation(agent.id, body, clientId);
      setStarted(conversation.id);
    }
  };

  const renderItem = ({ item }: { item: LocalMessage }) => {
    const askId = item.kind === 'ask' ? (item.payload as { ask_id?: string } | null)?.ask_id : undefined;
    const ask = askId ? openAsks.find((a) => a.id === askId) : undefined;
    if (ask) {
      return (
        <AskCard
          ask={ask}
          agent={agents.find((a) => a.id === ask.agent_id)}
          onAnswer={(answer) => client.answerAsk(ask.id, answer)}
        />
      );
    }
    return <MessageBubble message={item} />;
  };

  return (
    <KeyboardAvoidingView
      style={{ flex: 1, backgroundColor: theme.canvas }}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}>
      <Stack.Screen
        options={{
          headerStyle: { backgroundColor: theme.canvas },
          headerTitle: () =>
            agent ? (
              <View
                style={styles.title}
                accessible
                accessibilityRole="header"
                accessibilityLabel={`${agent.name}, ${STATUS_LABEL[agent.status]}`}>
                <Ghost character={agent.ghost_character} size={18} />
                <Text style={[Type.rowTitle, { color: theme.ink }]}>{agent.name}</Text>
                <StatusGlyph status={agent.status} size={13} />
              </View>
            ) : null,
        }}
      />
      <FlatList
        ref={list}
        data={shown}
        keyExtractor={(m) => m.client_id ?? m.id}
        renderItem={renderItem}
        contentContainerStyle={styles.messages}
        style={styles.column}
        keyboardDismissMode="interactive"
        ListEmptyComponent={
          agent ? (
            <Text style={[Type.rowSubtitle, styles.empty, { color: theme.inkSecondary }]}>
              {agent.summary ?? `Start a conversation with ${agent.name}.`}
            </Text>
          ) : undefined
        }
      />
      <View style={[styles.column, styles.composer, { paddingBottom: insets.bottom + Spacing.sm }]}>
        <Composer
          disabled={offline || !agent}
          placeholder={offline ? `${agent?.name} is offline` : `Message ${agent?.name ?? ''}`}
          onSend={send}
        />
      </View>
    </KeyboardAvoidingView>
  );
}

function localMessage(conversationId: string, body: string, clientId: string): LocalMessage {
  return {
    id: clientId,
    workspace_id: '',
    conversation_id: conversationId,
    author_kind: 'user',
    author_user_id: null,
    author_agent_id: null,
    kind: 'text',
    body,
    payload: {},
    client_id: clientId,
    created_at: new Date().toISOString(),
    pending: true,
  };
}

const styles = StyleSheet.create({
  title: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  column: { width: '100%', maxWidth: MaxContentWidth, alignSelf: 'center' },
  messages: { padding: Spacing.lg, gap: Spacing.md, flexGrow: 1 },
  composer: { paddingHorizontal: Spacing.md, paddingTop: Spacing.sm },
  empty: { textAlign: 'center', marginTop: Spacing.xxl },
});
