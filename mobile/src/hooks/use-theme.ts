import { useColorScheme } from 'react-native';

import { Colors, type Scheme } from '@/constants/theme';

export function useScheme(): Scheme {
  return useColorScheme() === 'dark' ? 'dark' : 'light';
}

export function useTheme() {
  return Colors[useScheme()];
}
