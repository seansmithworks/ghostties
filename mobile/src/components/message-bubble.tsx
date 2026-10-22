import { StyleSheet, Text, View } from 'react-native';

import type { LocalMessage } from '@/api/types';
import { Radius, Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/**
 * Agent replies read as plain text on the canvas, like terminal output; the
 * user's own lines sit in a quiet ink-tinted bubble on the right. No accent.
 * `status` and `system` messages are one centred secondary line.
 */
export function MessageBubble({ message }: { message: LocalMessage }) {
  const theme = useTheme();
  if (message.author_kind === 'system' || message.kind === 'status') {
    return <Text style={[Type.rowSubtitle, styles.system, { color: theme.inkSecondary }]}>{message.body}</Text>;
  }
  const mine = message.author_kind === 'user';
  return (
    <View
      style={[
        styles.bubble,
        mine ? { alignSelf: 'flex-end', backgroundColor: theme.rowFill, borderColor: theme.border } : styles.agent,
        message.pending && { opacity: 0.5 },
      ]}>
      {message.kind === 'answer' && (
        <Text style={[Type.caption, { color: theme.inkSecondary, marginBottom: 2 }]}>ANSWERED</Text>
      )}
      <Text selectable style={[Type.body, { color: theme.ink }]}>
        {message.body}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  bubble: {
    maxWidth: '85%',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    borderRadius: Radius.card,
    borderCurve: 'continuous',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'transparent',
  },
  agent: { alignSelf: 'flex-start', paddingHorizontal: 0 },
  system: { alignSelf: 'center', textAlign: 'center' },
});
