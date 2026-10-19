#!/usr/bin/env node
// Reference values for the selected-row outline (docs/plans/selected-row-outline-contract.md).
// The curve, the clamps and the per-mode maths are copied from card 06 ("Drawn outline",
// .mild2wild/2026-10-16-connected-tab/r7/06-drawn-outline/index.html, VARIANT.select / VARIANT.rm)
// on the r7 engine (r7/_base/index.html: bezier, seg, lerp). Sean's "ease in and out" spec:
// every motion uses bezier(0.77, 0, 0.175, 1).
// Run: node docs/plans/selected-row-outline-reference.js  (prints JSON; the Swift tests embed it).
function bezier(p1x, p1y, p2x, p2y) {
  const cx = 3 * p1x, bx = 3 * (p2x - p1x) - cx, ax = 1 - cx - bx,
    cy = 3 * p1y, by = 3 * (p2y - p1y) - cy, ay = 1 - cy - by;
  const sx = (t) => ((ax * t + bx) * t + cx) * t, sy = (t) => ((ay * t + by) * t + cy) * t,
    dx = (t) => (3 * ax * t + 2 * bx) * t + cx;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const e = sx(t) - x;
      if (Math.abs(e) < 1e-5) break;
      const d = dx(t);
      if (Math.abs(d) < 1e-6) break;
      t -= e / d;
    }
    return sy(t);
  };
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const seg = (p, a, b) => clamp01((p - a) / (b - a));
const lerp = (a, b, t) => a + (b - a) * t;
const io = bezier(0.77, 0, 0.175, 1);
const TRACE = 260, REST_OP = 0.4, DRAW_OP = 0.6;
const HIDDEN = { prog: 0, op: 0, tint: 0 }, REST = { prog: 1, op: REST_OP, tint: 1 };

// VARIANT.select, arriving row: one 300ms anim, from the row's current state.
function click(ms, f = HIDDEN) {
  ms = Math.min(Math.max(ms, 0), 300);
  return {
    prog: lerp(f.prog, 1, io(seg(ms, 0, TRACE))),
    op: ms <= TRACE ? lerp(f.op, DRAW_OP, io(seg(ms, 0, 80))) : lerp(DRAW_OP, REST_OP, io(seg(ms, TRACE, 300))),
    tint: lerp(f.tint, 1, io(seg(ms, 80, TRACE))),
  };
}
// VARIANT.select, leaving row: 100ms, outline + tint together, drawn length untouched.
function leaving(ms, f) {
  const k = 1 - io(clamp01(ms / 100));
  return { prog: f.prog, op: f.op * k, tint: f.tint * k };
}
// VARIANT.rm: no trace; 120ms in / 100ms out.
function rmIn(ms, f = HIDDEN) {
  const e = io(clamp01(ms / 120));
  return { prog: 1, op: lerp(f.op, REST_OP, e), tint: lerp(f.tint, 1, e) };
}
function rmOut(ms, f = REST) {
  const e = io(clamp01(ms / 100));
  return { prog: 1, op: lerp(f.op, 0, e), tint: lerp(f.tint, 0, e) };
}

if (require.main === module) {
  const R = (o) => ({ prog: +o.prog.toFixed(6), op: +o.op.toFixed(6), tint: +o.tint.toFixed(6) });
  const mid = click(130); // "wherever they are": the frame 130ms into a click
  const out = {
    curve: [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1].map((x) => [x, +io(x).toFixed(6)]),
    mid130: R(mid),
    click: [0, 40, 80, 130, 200, 260, 300].map((ms) => [ms, R(click(ms))]),
    retarget: [0, 100, 260, 300].map((ms) => [ms, R(click(ms, { prog: 0.5, op: 0.5, tint: 0.25 }))]),
    leavingFromRest: [0, 25, 50, 75, 100].map((ms) => [ms, R(leaving(ms, REST))]),
    leavingFromMid: [0, 50, 100].map((ms) => [ms, R(leaving(ms, mid))]),
    rmIn: [0, 60, 120].map((ms) => [ms, R(rmIn(ms))]),
    rmOut: [0, 50, 100].map((ms) => [ms, R(rmOut(ms))]),
  };
  console.log(JSON.stringify(out, null, 1));
}
module.exports = { io, click, leaving, rmIn, rmOut };
