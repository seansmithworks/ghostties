import type { ReactNode } from 'react';
import { Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { MaxContentWidth, Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/** A tab's scrolling page on the chrome, with a large left-aligned title. */
export function Screen({ title, children }: { title: string; children: ReactNode }) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      style={{ backgroundColor: theme.chrome }}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + Spacing.lg + WebTabBarInset, paddingBottom: insets.bottom + Spacing.xxl },
      ]}>
      <View style={styles.column}>
        <Text accessibilityRole="header" style={[Type.title, { color: theme.ink }]}>
          {title}
        </Text>
        {children}
      </View>
    </ScrollView>
  );
}

/** On web the tab bar floats over the top of the page instead of the bottom. */
const WebTabBarInset = Platform.OS === 'web' ? 64 : 0;

const styles = StyleSheet.create({
  content: { paddingHorizontal: Spacing.lg },
  column: { width: '100%', maxWidth: MaxContentWidth, alignSelf: 'center' },
});
