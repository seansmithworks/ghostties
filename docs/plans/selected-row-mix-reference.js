#!/usr/bin/env node
// Reference model for the selected-row mix (docs/plans/selected-row-mix-contract.md):
// row motion 04 Hand-off + project switch P1 Cross-fade + new tab N4 Outline first,
// Switch = 300ms, New tab = 600ms, every curve ease-in-out, size channels with a
// slight overshoot (Sean, 2026-10-19).
//
// Source of every number: the r9 engine and r8 04's VARIANT
// (.mild2wild/2026-10-16-connected-tab/r9/_build/engine.tpl.html, r8/04-hand-off/index.html,
// git-excluded). The board's Mix section runs in TIMING.mode "total": each event's
// internal offsets scale by ONE factor, total / the variant's own length:
//   row switch (same project)   k = 300 / 220   (04's dur)          kRow
//   project switch              k = 300 / 240   (P1's dur)          kSw; the row hand-off inside it runs on kSw too
//   new tab                     k = 600 / 440   (N4's dur)          kNew; the row hand-off and P1's card cross-fade inside it run on kNew
// Changes from the engine, each stated in the contract:
//   - size channels (new row height, a folded group's open) use bezier(0.77, 0, 0.175, OVERSHOOT_Y2)
//   - Reduce Motion fades out over 100ms everywhere (the engine's card used 120)
//   - a group opening for a new tab finishes even if a project switch lands mid-way
//   - Reduce Motion never resets an in-flight new row's content to 0
//
// Run: node docs/plans/selected-row-mix-reference.js   (prints the JSON the Swift tests embed)

function bezier(p1x, p1y, p2x, p2y) {
  const cx = 3 * p1x,
    bx = 3 * (p2x - p1x) - cx,
    ax = 1 - cx - bx,
    cy = 3 * p1y,
    by = 3 * (p2y - p1y) - cy,
    ay = 1 - cy - by;
  const sx = (t) => ((ax * t + bx) * t + cx) * t,
    sy = (t) => ((ay * t + by) * t + cy) * t,
    dx = (t) => (3 * ax * t + 2 * bx) * t + cx;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const e = sx(t) - x;
      if (Math.abs(e) < 1e-7) break;
      const d = dx(t);
      if (Math.abs(d) < 1e-6) break;
      t -= e / d;
    }
    return sy(t);
  };
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;

const OVERSHOOT_Y2 = 1.2;
const ease = bezier(0.77, 0, 0.175, 1); // opacity channels, and every Reduce Motion fade
const easeOvershoot = bezier(0.77, 0, 0.175, OVERSHOOT_Y2); // size channels

const SWITCH_MS = 300,
  NEWTAB_MS = 600,
  RM_IN = 120,
  RM_OUT = 100,
  REST_OUTLINE = 0.4;
// The variants' own (unscaled) numbers.
const ROW04 = { dur: 220, fromTint: [0, 160], toTint: [60, 220] };
const P1 = { dur: 240 };
const N4 = { dur: 440, height: [0, 260], content: [240, 440], open: [0, 260] };
const K = {
  row: SWITCH_MS / ROW04.dur,
  sw: SWITCH_MS / P1.dur,
  nt: NEWTAB_MS / N4.dur,
};

// One channel = one track: holds `from` until `a`, then runs to `to` by `b` on `curve`.
// A new event that touches a channel replaces its track, starting from the channel's
// value at that instant: never from 0, never queued behind the old one.
class Channel {
  constructor(v, size = false) {
    this.size = size;
    this.tr = { from: v, to: v, a: 0, b: 0, curve: ease };
  }
  value(t) {
    const { from, to, a, b, curve } = this.tr;
    const p = b <= a ? (t >= a ? 1 : 0) : clamp01((t - a) / (b - a));
    const v = lerp(from, to, curve(p));
    return this.size ? v : clamp01(v);
  }
  run(t, to, a, b, curve) {
    this.tr = {
      from: this.value(t),
      to,
      a: t + a,
      b: t + b,
      curve: curve || (this.size ? easeOvershoot : ease),
    };
  }
  snap(t, to) {
    this.tr = { from: to, to, a: t, b: t, curve: ease };
  }
  finish(t) {
    this.snap(t, this.tr.to);
  }
  get end() {
    return this.tr.b;
  }
}

class Timeline {
  constructor({ active = null, activeGroup = null, collapsed = [] } = {}) {
    this.active = active;
    this.activeGroup = activeGroup;
    this.collapsed = new Set(collapsed);
    this.rows = new Map();
    this.groups = new Map();
    this.inserting = null;
    if (active) {
      const r = this.row_(active);
      r.outline.snap(0, REST_OUTLINE);
      r.tint.snap(0, 1);
    }
    if (activeGroup != null) this.group_(activeGroup).card.snap(0, 1);
  }
  row_(id) {
    if (!this.rows.has(id))
      this.rows.set(id, {
        outline: new Channel(0),
        tint: new Channel(0),
        height: new Channel(1, true),
        content: new Channel(1),
      });
    return this.rows.get(id);
  }
  group_(id) {
    if (!this.groups.has(id))
      this.groups.set(id, {
        card: new Channel(0),
        open: new Channel(this.collapsed.has(id) ? 0 : 1, true),
      });
    return this.groups.get(id);
  }
  all_() {
    return [...this.rows.values(), ...this.groups.values()].flatMap((o) =>
      Object.values(o),
    );
  }

  // The hand-off: the old row's outline and tint out, the new row's in, on factor k.
  handOff_(from, to, t, k) {
    if (from != null && from !== to) {
      const f = this.row_(from);
      f.outline.run(t, 0, 0, ROW04.dur * k);
      f.tint.run(t, 0, ROW04.fromTint[0] * k, ROW04.fromTint[1] * k);
    }
    const n = this.row_(to);
    n.outline.run(t, REST_OUTLINE, 0, ROW04.dur * k);
    n.tint.run(t, 1, ROW04.toTint[0] * k, ROW04.toTint[1] * k);
  }
  // P1: every other group's card out, the target's in, in place, on factor k.
  crossFade_(target, t, k) {
    this.group_(target);
    for (const [id, g] of this.groups)
      g.card.run(t, id === target ? 1 : 0, 0, P1.dur * k);
  }
  rmFade_(from, to, target, t) {
    if (from != null && from !== to) {
      const f = this.row_(from);
      f.outline.run(t, 0, 0, RM_OUT, ease);
      f.tint.run(t, 0, 0, RM_OUT, ease);
    }
    const n = this.row_(to);
    n.outline.run(t, REST_OUTLINE, 0, RM_IN, ease);
    n.tint.run(t, 1, 0, RM_IN, ease);
    if (target !== this.activeGroup) {
      this.group_(target);
      for (const [id, g] of this.groups)
        g.card.run(
          t,
          id === target ? 1 : 0,
          0,
          id === target ? RM_IN : RM_OUT,
          ease,
        );
    }
    // Nothing moves: an opening group and a growing row jump to their size; content fades on from where it is.
    for (const g of this.groups.values()) g.open.finish(t);
    if (this.inserting) {
      const r = this.row_(this.inserting);
      r.height.finish(t);
      r.content.run(t, 1, 0, RM_IN, ease);
    }
  }

  select(id, group, { via = "click", reduceMotion = false, at: t }) {
    if (id === this.active) return;
    const from = this.active,
      sameGroup = group === this.activeGroup;
    if (reduceMotion) {
      this.rmFade_(from, id, group, t);
    } else if (via === "key") {
      // Keys snap: everything in flight lands, then the new selection is at rest at once.
      for (const c of this.all_()) c.finish(t);
      this.row_(id);
      this.group_(group);
      for (const [rid, r] of this.rows) {
        r.outline.snap(t, rid === id ? REST_OUTLINE : 0);
        r.tint.snap(t, rid === id ? 1 : 0);
      }
      for (const [gid, g] of this.groups) g.card.snap(t, gid === group ? 1 : 0);
    } else {
      const k = sameGroup ? K.row : K.sw;
      if (!sameGroup) this.crossFade_(group, t, K.sw);
      this.handOff_(from, id, t, k);
    }
    this.active = id;
    this.activeGroup = group;
  }

  newTab(id, group, { reduceMotion = false, at: t }) {
    // A new tab while another is still growing: the earlier one lands at once (the engine's settleInsert).
    if (this.inserting) {
      const p = this.row_(this.inserting);
      p.height.finish(t);
      p.content.finish(t);
    }
    const from = this.active,
      wasCollapsed = this.collapsed.has(group);
    const g = this.group_(group), // created while still folded: its open starts at 0
      n = this.row_(id);
    this.collapsed.delete(group); // only the target unfolds
    this.inserting = id;
    if (reduceMotion) {
      n.height.snap(t, 1);
      n.content.snap(t, 0);
      if (wasCollapsed) g.open.snap(t, 1);
      this.rmFade_(from, id, group, t);
    } else {
      n.height.snap(t, 0);
      n.content.snap(t, 0);
      if (wasCollapsed) g.open.run(t, 1, N4.open[0] * K.nt, N4.open[1] * K.nt);
      const settled = [...this.groups].every(
        ([gid, x]) => x.card.value(t) === (gid === group ? 1 : 0),
      );
      if (!settled) this.crossFade_(group, t, K.nt);
      n.height.run(t, 1, N4.height[0] * K.nt, N4.height[1] * K.nt);
      n.content.run(t, 1, N4.content[0] * K.nt, N4.content[1] * K.nt);
      this.handOff_(from, id, t, K.nt);
    }
    this.active = id;
    this.activeGroup = group;
  }

  row(id, t) {
    const r = this.rows.get(id);
    if (!r) return { outline: 0, tint: 0, height: 1, content: 1 };
    return {
      outline: r.outline.value(t),
      tint: r.tint.value(t),
      height: r.height.value(t),
      content: r.content.value(t),
    };
  }
  group(id, t) {
    const g = this.groups.get(id);
    if (!g)
      return {
        card: id === this.activeGroup ? 1 : 0,
        open: this.collapsed.has(id) ? 0 : 1,
      };
    return { card: g.card.value(t), open: g.open.value(t) };
  }
  get settledAt() {
    return Math.max(0, ...this.all_().map((c) => c.end));
  }
}

module.exports = {
  bezier,
  ease,
  easeOvershoot,
  OVERSHOOT_Y2,
  K,
  Timeline,
  SWITCH_MS,
  NEWTAB_MS,
  RM_IN,
  RM_OUT,
  REST_OUTLINE,
};

if (require.main === module) {
  const R = (o) =>
    Object.fromEntries(Object.entries(o).map(([k, v]) => [k, +v.toFixed(6)]));
  const A1 = "a1",
    A2 = "a2",
    B1 = "b1",
    NEW = "n1";
  const fresh = (collapsed = ["C"]) =>
    new Timeline({ active: A1, activeGroup: "A", collapsed });
  const fr = (pct, total) => (pct * total) / 100;
  const out = { curve: {}, overshoot: {}, k: K };
  for (const x of [0.1, 0.25, 0.5, 0.75, 0.9]) {
    out.curve[x] = +ease(x).toFixed(6);
    out.overshoot[x] = +easeOvershoot(x).toFixed(6);
  }
  for (const x of [0.8, 0.85, 0.95])
    out.overshoot[x] = +easeOvershoot(x).toFixed(6);

  // 1. Row switch, same project, click @ 0.
  let tl = fresh();
  tl.select(A2, "A", { at: 0 });
  out.rowSwitch = { settledAt: tl.settledAt, at: {} };
  for (const p of [0, 25, 50, 75, 100]) {
    const t = fr(p, 300);
    out.rowSwitch.at[p] = {
      t,
      from: R(tl.row(A1, t)),
      to: R(tl.row(A2, t)),
      cardA: tl.group("A", t).card,
    };
  }

  // 2. Project switch A -> B, click @ 0.
  tl = fresh();
  tl.select(B1, "B", { at: 0 });
  out.projectSwitch = { settledAt: tl.settledAt, at: {} };
  for (const p of [0, 25, 50, 75, 100]) {
    const t = fr(p, 300);
    out.projectSwitch.at[p] = {
      t,
      from: R(tl.row(A1, t)),
      to: R(tl.row(B1, t)),
      A: R(tl.group("A", t)),
      B: R(tl.group("B", t)),
      C: R(tl.group("C", t)),
    };
  }
  out.projectSwitch.handOffEndsAt = ROW04.dur * K.sw;

  // 3. New tab into the active project A @ 0.
  tl = fresh();
  tl.newTab(NEW, "A", { at: 0 });
  out.newTabActive = { settledAt: tl.settledAt, at: {} };
  for (const p of [0, 25, 50, 75, 100]) {
    const t = fr(p, 600);
    out.newTabActive.at[p] = {
      t,
      from: R(tl.row(A1, t)),
      n: R(tl.row(NEW, t)),
      A: R(tl.group("A", t)),
    };
  }
  out.newTabActive.heightAt = {};
  for (const p of [80, 85, 90, 95, 100]) {
    const t = (p / 100) * N4.height[1] * K.nt;
    out.newTabActive.heightAt[p] = {
      t,
      height: +tl.row(NEW, t).height.toFixed(6),
    };
  }

  // 4. New tab into folded project C @ 0.
  tl = fresh();
  tl.newTab(NEW, "C", { at: 0 });
  out.newTabCollapsed = {
    settledAt: tl.settledAt,
    collapsedAfter: [...tl.collapsed],
    at: {},
  };
  for (const p of [0, 25, 50, 75, 100]) {
    const t = fr(p, 600);
    out.newTabCollapsed.at[p] = {
      t,
      from: R(tl.row(A1, t)),
      n: R(tl.row(NEW, t)),
      A: R(tl.group("A", t)),
      C: R(tl.group("C", t)),
      D: R(tl.group("D", t)),
    };
  }

  // 5. Retarget: A -> B @ 0, back to A @ 100 (the engine's "switch2" probe).
  tl = fresh();
  tl.select(B1, "B", { at: 0 });
  const before = {
    A: R(tl.group("A", 100)),
    B: R(tl.group("B", 100)),
    a1: R(tl.row(A1, 100)),
    b1: R(tl.row(B1, 100)),
  };
  tl.select(A1, "A", { at: 100 });
  out.retarget = { before, settledAt: tl.settledAt, at: {} };
  for (const t of [100, 175, 250, 325, 400])
    out.retarget.at[t] = {
      A: R(tl.group("A", t)),
      B: R(tl.group("B", t)),
      a1: R(tl.row(A1, t)),
      b1: R(tl.row(B1, t)),
    };

  // 6. Reduce Motion: project switch and new tab into folded C.
  tl = fresh();
  tl.select(B1, "B", { reduceMotion: true, at: 0 });
  out.rmSwitch = { settledAt: tl.settledAt, at: {} };
  for (const t of [0, 50, 60, 100, 120])
    out.rmSwitch.at[t] = {
      from: R(tl.row(A1, t)),
      to: R(tl.row(B1, t)),
      A: R(tl.group("A", t)),
      B: R(tl.group("B", t)),
    };
  tl = fresh();
  tl.newTab(NEW, "C", { reduceMotion: true, at: 0 });
  out.rmNewTab = { settledAt: tl.settledAt, at: {} };
  for (const t of [0, 60, 120])
    out.rmNewTab.at[t] = { n: R(tl.row(NEW, t)), C: R(tl.group("C", t)) };

  console.log(JSON.stringify(out, null, 1));
}
