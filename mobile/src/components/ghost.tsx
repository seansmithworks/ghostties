import { memo } from 'react';
import { View } from 'react-native';

import { GHOST_GRIDS, type GhostCharacter } from '@/constants/ghosts';
import { useTheme } from '@/hooks/use-theme';

type Run = { row: number; col: number; length: number };

/** Each grid row collapsed to its filled runs, so a ghost is ~20 views, not ~108. */
const RUNS = Object.fromEntries(
  Object.entries(GHOST_GRIDS).map(([name, grid]) => {
    const runs: Run[] = [];
    grid.forEach((line, row) => {
      let col = 0;
      while (col < line.length) {
        if (line[col] !== 'X') {
          col++;
          continue;
        }
        const start = col;
        while (line[col] === 'X') col++;
        runs.push({ row, col: start, length: col - start });
      }
    });
    return [name, runs];
  }),
) as Record<GhostCharacter, Run[]>;

/** The Mac app's 12×12 pixel ghost, drawn crisp at any multiple of 12. */
export const Ghost = memo(function Ghost({
  character,
  size = 24,
  color,
}: {
  character: string | null | undefined;
  size?: number;
  color?: string;
}) {
  const theme = useTheme();
  const runs = (character && RUNS[character as GhostCharacter]) || RUNS.blinky;
  const cell = size / 12;
  const fill = color ?? theme.ink;
  return (
    <View style={{ width: size, height: size }} accessible={false}>
      {runs.map((r) => (
        <View
          key={`${r.row}-${r.col}`}
          style={{
            position: 'absolute',
            left: r.col * cell,
            top: r.row * cell,
            width: r.length * cell,
            height: cell,
            backgroundColor: fill,
          }}
        />
      ))}
    </View>
  );
});
