import { NativeTabs } from 'expo-router/native-tabs';

import { useOpenAsks } from '@/api/hooks';
import { useTheme } from '@/hooks/use-theme';

export default function TabsLayout() {
  const theme = useTheme();
  const { data: asks } = useOpenAsks();

  return (
    <NativeTabs
      backgroundColor={theme.chrome}
      indicatorColor={theme.rowFill}
      labelStyle={{ selected: { color: theme.ink } }}>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Label>Needs you</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'tray', selected: 'tray.fill' }} md="inbox" />
        <NativeTabs.Trigger.Badge hidden={asks.length === 0}>{String(asks.length)}</NativeTabs.Trigger.Badge>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="agents">
        <NativeTabs.Trigger.Label>Agents</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'person.2', selected: 'person.2.fill' }} md="group" />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
