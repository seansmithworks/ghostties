import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { Agent, Ask, AskAnswer } from '@/api/types';
import { Card } from '@/components/card';
import { Ghost } from '@/components/ghost';
import { Radius, Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { age } from '@/utils/time';

const KIND_LABEL: Record<Ask['kind'], string> = {
  question: 'Question',
  permission: 'Permission',
  decision: 'Decision',
};

/**
 * One agent waiting on the user. Options answer in place, the recommended one
 * filled; a free-text question hands off to the conversation with `onReply`.
 */
export function AskCard({
  ask,
  agent,
  onAnswer,
  onReply,
}: {
  ask: Ask;
  agent?: Agent;
  onAnswer: (answer: AskAnswer) => void;
  onReply?: () => void;
}) {
  const theme = useTheme();
  const primaryId = ask.recommended_option_id ?? ask.options[0]?.id;
  const recommended = ask.options.find((o) => o.id === primaryId);

  return (
    <Card style={styles.card}>
      <View style={styles.header}>
        {agent && <Ghost character={agent.ghost_character} size={16} />}
        <Text style={[Type.rowSubtitle, styles.meta, { color: theme.inkSecondary }]} numberOfLines={1}>
          {agent?.name ?? 'Agent'} · {KIND_LABEL[ask.kind]} · {age(ask.created_at)}
        </Text>
      </View>
      <Text style={[Type.rowTitle, { color: theme.ink }]}>{ask.prompt}</Text>
      {recommended?.detail && (
        <Text style={[Type.rowSubtitle, { color: theme.inkSecondary }]}>
          {recommended.label}: {recommended.detail}
        </Text>
      )}
      <View style={styles.actions}>
        {ask.options.length > 0
          ? ask.options.map((option) => (
              <ActionButton
                key={option.id}
                label={option.label}
                hint={option.detail}
                primary={option.id === primaryId}
                onPress={() => onAnswer({ option_id: option.id })}
              />
            ))
          : onReply && <ActionButton label="Reply" primary onPress={onReply} />}
      </View>
    </Card>
  );
}

function ActionButton({
  label,
  hint,
  primary,
  onPress,
}: {
  label: string;
  hint?: string;
  primary?: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityHint={hint}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        primary
          ? { backgroundColor: theme.ink }
          : { borderWidth: StyleSheet.hairlineWidth * 2, borderColor: theme.border },
        pressed && { opacity: 0.7 },
      ]}>
      <Text style={[Type.rowSubtitle, { fontWeight: '600', color: primary ? theme.canvas : theme.ink }]}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { padding: Spacing.lg, gap: Spacing.sm },
  header: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  meta: { flex: 1 },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.sm, marginTop: Spacing.xs },
  button: {
    minHeight: 44,
    paddingHorizontal: Spacing.lg,
    borderRadius: Radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
