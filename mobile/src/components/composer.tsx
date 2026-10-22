import { useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { Radius, Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

export function Composer({
  placeholder,
  disabled,
  onSend,
}: {
  placeholder: string;
  disabled?: boolean;
  onSend: (body: string) => void;
}) {
  const theme = useTheme();
  const [text, setText] = useState('');
  const canSend = !disabled && text.trim().length > 0;
  const send = () => {
    if (!canSend) return;
    onSend(text.trim());
    setText('');
  };

  return (
    <View style={[styles.bar, { backgroundColor: theme.canvas, borderColor: theme.border }]}>
      <TextInput
        value={text}
        onChangeText={setText}
        editable={!disabled}
        placeholder={placeholder}
        placeholderTextColor={theme.inkSecondary}
        multiline
        style={[Type.body, styles.input, { color: theme.ink }]}
        accessibilityLabel="Message"
        submitBehavior="submit"
        onSubmitEditing={send}
      />
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Send"
        accessibilityState={{ disabled: !canSend }}
        onPress={send}
        disabled={!canSend}
        hitSlop={8}
        style={[styles.send, { backgroundColor: canSend ? theme.ink : theme.rowFill }]}>
        <Text style={{ color: canSend ? theme.canvas : theme.inkSecondary, fontSize: 17, fontWeight: '600' }}>↑</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: Spacing.sm,
    padding: Spacing.sm,
    paddingLeft: Spacing.lg,
    borderRadius: Radius.card * 2,
    borderCurve: 'continuous',
    borderWidth: StyleSheet.hairlineWidth,
  },
  input: { flex: 1, maxHeight: 140, paddingVertical: Spacing.sm },
  send: {
    width: 36,
    height: 36,
    borderRadius: Radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
