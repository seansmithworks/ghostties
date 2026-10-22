import { useEffect, useState } from 'react';
import { AccessibilityInfo, Text } from 'react-native';

import type { AgentStatus } from '@/api/types';
import { Fonts } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

export const STATUS_LABEL: Record<AgentStatus, string> = {
  busy: 'Working',
  idle: 'Idle',
  needs_input: 'Needs you',
  needs_permission: 'Needs permission',
  ended: 'Ended',
  offline: 'Offline',
};

/**
 * The Mac sidebar's status slot ("type is the icon", DESIGN.md §4): one
 * monospaced glyph. Braille spinner while working, `?` in full ink when it
 * needs you (the only emphasis), `✓` idle, empty when ended or offline.
 * Reduce Motion swaps the spinner for a static `…`.
 */
export function StatusGlyph({ status, size = 15 }: { status: AgentStatus; size?: number }) {
  const theme = useTheme();
  const reduceMotion = useReduceMotion();
  const frame = useSpinner(status === 'busy' && !reduceMotion);

  let glyph = '';
  let color = theme.inkSecondary;
  switch (status) {
    case 'busy':
      glyph = reduceMotion ? '…' : SPINNER[frame];
      break;
    case 'needs_input':
    case 'needs_permission':
      glyph = '?';
      color = theme.ink;
      break;
    case 'idle':
      glyph = '✓';
      break;
  }

  return (
    <Text
      accessibilityLabel={STATUS_LABEL[status]}
      style={{
        fontFamily: Fonts.mono,
        fontSize: size,
        fontWeight: status === 'needs_input' || status === 'needs_permission' ? '700' : '400',
        color,
        width: size,
        textAlign: 'center',
      }}>
      {glyph}
    </Text>
  );
}

function useSpinner(running: boolean) {
  const [frame, setFrame] = useState(0);
  useEffect(() => {
    if (!running) return;
    const id = setInterval(() => setFrame((f) => (f + 1) % SPINNER.length), 80);
    return () => clearInterval(id);
  }, [running]);
  return frame;
}

function useReduceMotion() {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduce);
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduce);
    return () => sub.remove();
  }, []);
  return reduce;
}
