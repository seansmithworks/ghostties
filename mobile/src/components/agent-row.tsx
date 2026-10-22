import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { Agent } from '@/api/types';
import { Ghost } from '@/components/ghost';
import { STATUS_LABEL, StatusGlyph } from '@/components/status-glyph';
import { Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { age } from '@/utils/time';

/** A sidebar-style row: ghost, name, what it is doing, age, status glyph. */
export function AgentRow({ agent, subtitle, last }: { agent: Agent; subtitle?: string; last?: boolean }) {
  const theme = useTheme();
  const dimmed = agent.status === 'offline' || agent.status === 'ended';
  const detail = subtitle ?? agent.summary ?? STATUS_LABEL[agent.status];
  return (
    <Pressable
        onPress={() => router.push({ pathname: '/agent/[id]', params: { id: agent.id } })}
        accessibilityRole="button"
        accessibilityLabel={`${agent.name}, ${STATUS_LABEL[agent.status]}, ${detail}`}
        style={({ pressed }) => [
          styles.row,
          pressed && { backgroundColor: theme.rowFill },
          !last && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.border },
        ]}>
        <View style={{ opacity: dimmed ? 0.4 : 1 }}>
          <Ghost character={agent.ghost_character} size={24} />
        </View>
        <View style={styles.text}>
          <Text style={[Type.rowTitle, { color: theme.ink }]} numberOfLines={1}>
            {agent.name}
          </Text>
          <Text style={[Type.rowSubtitle, { color: theme.inkSecondary }]} numberOfLines={1}>
            {detail}
          </Text>
        </View>
        {agent.last_activity_at && (
          <Text style={[Type.rowSubtitle, { color: theme.inkSecondary }]}>{age(agent.last_activity_at)}</Text>
        )}
        <StatusGlyph status={agent.status} />
      </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    minHeight: 60,
  },
  text: { flex: 1, gap: 2 },
});
