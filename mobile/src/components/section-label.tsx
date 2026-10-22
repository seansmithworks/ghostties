import { Text } from 'react-native';

import { Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

export function SectionLabel({ children }: { children: string }) {
  const theme = useTheme();
  return (
    <Text
      accessibilityRole="header"
      style={[
        Type.caption,
        {
          color: theme.inkSecondary,
          textTransform: 'uppercase',
          marginTop: Spacing.xl,
          marginBottom: Spacing.sm,
          marginHorizontal: Spacing.xs,
        },
      ]}>
      {children}
    </Text>
  );
}
