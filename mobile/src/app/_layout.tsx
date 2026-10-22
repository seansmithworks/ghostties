import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { ClientProvider } from '@/api/hooks';
import { Colors } from '@/constants/theme';
import { useScheme } from '@/hooks/use-theme';

export default function RootLayout() {
  const scheme = useScheme();
  const palette = Colors[scheme];
  const base = scheme === 'dark' ? DarkTheme : DefaultTheme;
  const navTheme = {
    ...base,
    colors: {
      ...base.colors,
      background: palette.chrome,
      card: palette.chrome,
      text: palette.ink,
      border: palette.border,
      primary: palette.ink,
    },
  };

  return (
    <ClientProvider>
      <ThemeProvider value={navTheme}>
        <StatusBar style="auto" />
        <Stack screenOptions={{ headerShadowVisible: false, headerBackButtonDisplayMode: 'minimal' }}>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="agent/[id]" options={{ title: '' }} />
        </Stack>
      </ThemeProvider>
    </ClientProvider>
  );
}
