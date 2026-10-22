import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { useAgents, useClient, useConversations, useOpenAsks } from '@/api/hooks';
import { AskCard } from '@/components/ask-card';
import { Ghost } from '@/components/ghost';
import { Screen } from '@/components/screen';
import { Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/** The Mac sidebar's Needs You zone: every open ask across agents, newest first. */
export default function NeedsYouScreen() {
  const theme = useTheme();
  const client = useClient();
  const { data: asks, loading } = useOpenAsks();
  const { data: agents } = useAgents();
  const { data: conversations } = useConversations();

  const openConversation = (conversationId: string) => {
    const conversation = conversations.find((c) => c.id === conversationId);
    if (!conversation) return;
    router.push({ pathname: '/agent/[id]', params: { id: conversation.agent_id, conversation: conversation.id } });
  };

  return (
    <Screen title="Needs you">
      <View style={styles.list}>
        {asks.map((ask) => (
          <AskCard
            key={ask.id}
            ask={ask}
            agent={agents.find((a) => a.id === ask.agent_id)}
            onAnswer={(answer) => client.answerAsk(ask.id, answer)}
            onReply={() => openConversation(ask.conversation_id)}
          />
        ))}
      </View>
      {!loading && asks.length === 0 && (
        <View style={styles.empty}>
          <Ghost character="drift" size={48} color={theme.inkSecondary} />
          <Text style={[Type.rowTitle, { color: theme.ink }]}>Nothing needs you</Text>
          <Text style={[Type.rowSubtitle, { color: theme.inkSecondary, textAlign: 'center' }]}>
            When an agent asks a question or needs a permission, it shows up here.
          </Text>
        </View>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  list: { gap: Spacing.md, marginTop: Spacing.lg },
  empty: { alignItems: 'center', gap: Spacing.sm, paddingTop: Spacing.xxl * 2, paddingHorizontal: Spacing.xl },
});
