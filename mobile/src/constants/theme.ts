/**
 * Ghostties design tokens for mobile, carried over from the Mac app's
 * `DESIGN.md` frontmatter and `ChromeTheme`. Same two-layer model: `chrome` is
 * the screen behind everything, `canvas` is the card that holds content.
 *
 * Keep these values in step with `DESIGN.md`. A new colour is a reuse of one of
 * these, never a new token, same rule as the Mac app.
 */

import { Platform } from 'react-native';

export type Scheme = 'light' | 'dark';

export type Palette = {
  chrome: string;
  canvas: string;
  ink: string;
  inkSecondary: string;
  border: string;
  /** Ink at the Mac app's `.row` step: active and pressed rows. */
  rowFill: string;
  /** The terminal card's shadow colour. */
  shadow: string;
  destructive: string;
  success: string;
  /** Brand accent. Reserved for the waiting state, as on the Mac. Unused until mobile shows one. */
  terracotta: string;
};

export const Colors: Record<Scheme, Palette> = {
  light: {
    chrome: '#F0E9E6',
    canvas: '#FAF7F3',
    ink: '#1A1A1A',
    inkSecondary: '#5E5E5E',
    border: '#E5E5E3',
    rowFill: 'rgba(0,0,0,0.04)',
    shadow: '#0F0F0F',
    destructive: '#DC3545',
    success: '#2D7D46',
    terracotta: '#C97350',
  },
  dark: {
    chrome: '#242424',
    canvas: '#141413',
    ink: '#F0EFED',
    inkSecondary: '#A6A6A6',
    border: '#2A2A2A',
    rowFill: 'rgba(255,255,255,0.06)',
    shadow: '#FFFFFF',
    destructive: '#DC3545',
    success: '#2D7D46',
    terracotta: '#C97350',
  },
};

/** 4pt base, the Mac app's spacing scale. */
export const Spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
} as const;

/** The terminal card's continuous corner. */
export const Radius = { card: 12, pill: 999 } as const;

/**
 * Type scale. Mobile is a surface that floats free of the sidebar, so it takes
 * the Mac app's centered-modal scale (15 / 13 / 11) rather than 11pt sidebar
 * density, with one body step up for reading agent replies.
 */
export const Type = {
  title: { fontSize: 22, fontWeight: '600' },
  body: { fontSize: 15, fontWeight: '400', lineHeight: 21 },
  rowTitle: { fontSize: 15, fontWeight: '500' },
  rowSubtitle: { fontSize: 13, fontWeight: '400' },
  caption: { fontSize: 11, fontWeight: '500', letterSpacing: 0.4 },
} as const;

export const Fonts = {
  /** SF Mono on iOS. Status glyphs and anything machine-shaped. */
  mono: Platform.select({ ios: 'ui-monospace', default: 'monospace' }),
};

export const MaxContentWidth = 720;
