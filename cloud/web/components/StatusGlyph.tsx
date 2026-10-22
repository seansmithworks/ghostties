"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import type { AgentStatus } from "@ghostties/contract";
import styles from "./StatusGlyph.module.css";

const FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧";

const REDUCED = "(prefers-reduced-motion: reduce)";
const prefersReducedMotion = () => window.matchMedia(REDUCED).matches;
function subscribeReducedMotion(onChange: () => void) {
  const query = window.matchMedia(REDUCED);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

const LABEL: Record<AgentStatus, string> = {
  busy: "Working",
  idle: "Idle",
  needs_input: "Needs you",
  needs_permission: "Needs your approval",
  ended: "Ended",
  offline: "Offline",
};

/**
 * The Mac sidebar's "type is the icon" status slot (DESIGN.md §4): a braille
 * spinner while working, `?` when it needs you (the only emphasis), `✓` idle,
 * empty when ended or offline. Reduce Motion swaps the spinner for `…`.
 */
export function StatusGlyph({ status }: { status: AgentStatus }) {
  const spinning = status === "busy";
  const [frame, setFrame] = useState(0);
  const reduced = useSyncExternalStore(
    subscribeReducedMotion,
    prefersReducedMotion,
    () => false,
  );

  useEffect(() => {
    if (!spinning || reduced) return;
    const id = setInterval(() => setFrame((f) => (f + 1) % FRAMES.length), 80);
    return () => clearInterval(id);
  }, [spinning, reduced]);

  let glyph = "";
  if (spinning) glyph = reduced ? "…" : FRAMES[frame];
  else if (status === "needs_input" || status === "needs_permission")
    glyph = "?";
  else if (status === "idle") glyph = "✓";

  const emphasis = glyph === "?";
  return (
    <span
      className={`${styles.glyph} ${emphasis ? styles.emphasis : ""}`}
      role="img"
      aria-label={LABEL[status]}
      title={LABEL[status]}
    >
      {glyph}
    </span>
  );
}
