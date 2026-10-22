import { ghostGrids, type GhostName } from "@/lib/ghosts";

/** One of the Mac app's 24 pixel ghosts, drawn in `currentColor`. */
export function Ghost({ name, size = 16 }: { name: string; size?: number }) {
  const grid = ghostGrids[name as GhostName] ?? ghostGrids.blinky;
  const cells: string[] = [];
  grid.forEach((row, y) =>
    [...row].forEach((c, x) => {
      if (c === "X") cells.push(`M${x} ${y}h1v1h-1z`);
    }),
  );
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 12 12"
      fill="currentColor"
      shapeRendering="crispEdges"
      aria-hidden="true"
    >
      <path d={cells.join("")} />
    </svg>
  );
}
