import {
  drawablyButton,
  drawablyCheckbox,
  drawablyToggle,
  drawablyInput,
  drawablyDivider,
  drawablyCard,
  drawablyBadge,
  drawablyList,
  drawablyUnderline,
  drawablyHighlight,
  drawablyCircle,
  drawablyArrow,
  roughRoundedRect,
  roughLine,
  roughArrow,
  roughCircle,
} from "./vendor/drawably/dist/index.js";

const STORAGE_PREFIX = "ghostties-avenues-2026-09-05:";

function storageGet(key) {
  try {
    return localStorage.getItem(STORAGE_PREFIX + key);
  } catch (e) {
    return null;
  }
}

function storageSet(key, value) {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, value);
  } catch (e) {
    /* ignore */
  }
}

// ---------- generic helpers ----------

function el(tag, opts = {}) {
  const node = document.createElement(tag);
  if (opts.className) node.className = opts.className;
  if (opts.text !== undefined) node.textContent = opts.text;
  if (opts.attrs) {
    for (const [k, v] of Object.entries(opts.attrs)) node.setAttribute(k, v);
  }
  return node;
}

function svg(width, height) {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  s.setAttribute("viewBox", `0 0 ${width} ${height}`);
  s.setAttribute("width", String(width));
  s.setAttribute("height", String(height));
  return s;
}

function svgPath(d, cls) {
  const p = document.createElementNS("http://www.w3.org/2000/svg", "path");
  p.setAttribute("d", d);
  p.setAttribute("class", cls);
  return p;
}

function svgText(x, y, text, cls) {
  const t = document.createElementNS("http://www.w3.org/2000/svg", "text");
  t.setAttribute("x", String(x));
  t.setAttribute("y", String(y));
  t.setAttribute("class", cls);
  t.textContent = text;
  return t;
}

const ROUGH = { roughness: 1 };

function ghostGlyphSVG(state) {
  // one path: dome + three-scallop bottom
  const PATH =
    "M2 15 L2 7.2 C2 3.8 4.7 1 8 1 C11.3 1 14 3.8 14 7.2 L14 15 L11.5 12.6 L9 15 L7 13 L5 15 L2 15 Z";
  const s = svg(16, 16);
  s.classList.add("ghost-glyph");
  const p = svgPath(PATH, "");
  if (state === "solid") {
    p.setAttribute("fill", "var(--ink)");
    p.setAttribute("stroke", "none");
  } else if (state === "outline") {
    p.setAttribute("fill", "none");
    p.setAttribute("stroke", "var(--ink)");
    p.setAttribute("stroke-width", "1.5");
  } else if (state === "accent") {
    p.setAttribute("fill", "var(--accent)");
    p.setAttribute("stroke", "none");
  } else if (state === "faded") {
    p.setAttribute("fill", "var(--ink)");
    p.setAttribute("stroke", "none");
    p.setAttribute("opacity", "0.3");
  }
  s.appendChild(p);
  return s;
}

// A "window" sketch: a drawablyCard containing an optional title and a list
// of rows (dot + label), separated by drawablyDivider.
function windowSketch(container, { title, rows, seed }) {
  const win = el("div", { className: "sketch-window" });
  container.appendChild(win);
  if (title) {
    win.appendChild(el("div", { className: "sketch-title", text: title }));
  }
  rows.forEach((row, i) => {
    if (i > 0) {
      const hr = el("hr");
      win.appendChild(hr);
      drawablyDivider(hr, { seed: seed + i });
    }
    const rowEl = el("div", { className: "sketch-row" });
    if (row.ghost) {
      rowEl.appendChild(ghostGlyphSVG(row.ghost));
    }
    rowEl.appendChild(document.createTextNode(row.label));
    win.appendChild(rowEl);
  });
  drawablyCard(win, { seed });
  return win;
}

// ---------- top-of-page badges + underline ----------

drawablyUnderline(document.getElementById("what-next-underline"), { seed: 1 });
drawablyBadge(document.getElementById("legend-mild"), {
  variant: "outline",
  seed: 2,
});
drawablyBadge(document.getElementById("legend-medium"), {
  variant: "outline",
  seed: 3,
});
drawablyBadge(document.getElementById("legend-wild"), {
  variant: "scribble",
  seed: 4,
  stroke: "var(--accent)",
  fill: "var(--accent)",
});

document.querySelectorAll(".stat-card[data-card]").forEach((cardEl, i) => {
  drawablyCard(cardEl, { seed: 10 + i });
});

drawablyList(document.getElementById("findings-list"), {
  marker: "dash",
  seed: 20,
});

drawablyCard(document.getElementById("recommendation-card"), {
  seed: 30,
  stroke: "var(--accent)",
});

document.querySelectorAll(".avenue-card[data-card]").forEach((cardEl, i) => {
  drawablyCard(cardEl, { seed: 40 + i });
});

document.querySelectorAll("[data-dial-badge]").forEach((badgeEl, i) => {
  const isWild = badgeEl.classList.contains("badge-wild");
  drawablyBadge(badgeEl, {
    variant: isWild ? "scribble" : "outline",
    seed: 60 + i,
    ...(isWild ? { stroke: "var(--accent)", fill: "var(--accent)" } : {}),
  });
});

drawablyArrow(
  document.getElementById("recommendation-card"),
  document.getElementById("card-1"),
  { seed: 70 },
);

// ---------- Part two: header, intro, ghost row, list, recommendation ----------

drawablyUnderline(document.getElementById("jump-part-one"), { seed: 80 });
drawablyUnderline(document.getElementById("jump-part-two"), { seed: 81 });

drawablyHighlight(document.getElementById("agent-forward-highlight"), {
  seed: 82,
  fill: "var(--accent)",
});

function sleepingGhostSVG() {
  const s = ghostGlyphSVG("outline");
  const dash1 = svgPath("M5.5 8 L7 8", "");
  dash1.setAttribute("stroke", "var(--ink)");
  dash1.setAttribute("stroke-width", "1.5");
  dash1.setAttribute("stroke-linecap", "round");
  const dash2 = svgPath("M9 8 L10.5 8", "");
  dash2.setAttribute("stroke", "var(--ink)");
  dash2.setAttribute("stroke-width", "1.5");
  dash2.setAttribute("stroke-linecap", "round");
  s.appendChild(dash1);
  s.appendChild(dash2);
  return s;
}

const ghostRow = document.getElementById("part2-ghost-row");
[
  { ghost: "solid", name: "Frank", role: "front end" },
  { ghost: "outline", name: "Bob", role: "back end" },
  { ghost: "outline", name: "Vinnie", role: "visionary" },
  { ghost: "faded", name: "Charlie", role: "chief of staff" },
].forEach((agent) => {
  const cell = el("div", { className: "part2-ghost" });
  cell.appendChild(ghostGlyphSVG(agent.ghost));
  cell.appendChild(
    el("div", {
      className: "part2-ghost-label",
      text: `${agent.name} · ${agent.role}`,
    }),
  );
  ghostRow.appendChild(cell);
});

drawablyArrow(document.getElementById("part2-next-word"), ghostRow, {
  seed: 83,
});

drawablyList(document.getElementById("part2-exists-list"), {
  marker: "dash",
  seed: 84,
});

drawablyCard(document.getElementById("part2-recommendation-card"), {
  seed: 85,
  stroke: "var(--accent)",
});

drawablyArrow(
  document.getElementById("part2-recommendation-card"),
  document.getElementById("card-14"),
  { seed: 86 },
);

// ---------- per-card sketches ----------

const sketches = {
  1: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    win.appendChild(
      el("div", { className: "sketch-title", text: "Status is guessing" }),
    );
    win.appendChild(
      el("div", {
        className: "sketch-row",
        text: "Turn on real Claude Code status",
      }),
    );
    const toggleWrap = el("span", { className: "sketch-row" });
    const toggleInput = el("input", { attrs: { type: "checkbox" } });
    toggleWrap.appendChild(toggleInput);
    win.appendChild(toggleWrap);
    drawablyToggle(toggleWrap, { seed: 101 });
    const hr1 = el("hr");
    win.appendChild(hr1);
    drawablyDivider(hr1, { seed: 102 });
    const link = el("span", { text: "How it works", className: "sketch-row" });
    win.appendChild(link);
    drawablyUnderline(link, { seed: 103 });
    const hr2 = el("hr");
    win.appendChild(hr2);
    drawablyDivider(hr2, { seed: 104 });
    ["ghostties", "brukas"].forEach((label, i) => {
      const rowEl = el("div", { className: "sketch-row" });
      const dotWrap = el("span", { text: "●" });
      rowEl.appendChild(dotWrap);
      rowEl.appendChild(document.createTextNode(label));
      win.appendChild(rowEl);
      drawablyCircle(dotWrap, { seed: 105 + i });
    });
    drawablyCard(win, { seed: 100 });
  },

  2: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const ul = el("ul");
    [
      "push Tab-space",
      "⌘N and look at variant C",
      "npm publish 0.2.0",
      "set HOMEBREW_TAP_TOKEN",
      "tag v0.1.0-beta.25",
    ].forEach((item) => {
      const li = el("li", { text: item });
      ul.appendChild(li);
    });
    win.appendChild(ul);
    drawablyList(ul, { marker: "check", seed: 110 });
    drawablyCard(win, { seed: 111 });
  },

  3: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const layout = el("div", { className: "sketch-row" });
    layout.style.alignItems = "flex-start";
    const nav = el("div");
    nav.style.fontSize = "11px";
    nav.style.lineHeight = "1.8";
    ["Status", "gt", "MCP", "Shortcuts"].forEach((item) => {
      nav.appendChild(el("div", { text: item }));
    });
    layout.appendChild(nav);
    win.appendChild(layout);
    win.appendChild(
      el("div", { className: "sketch-title", text: "Real Claude Code status" }),
    );
    const codeSvg = svg(200, 40);
    codeSvg.appendChild(
      svgPath(
        roughRoundedRect(2, 2, 196, 36, 4, { seed: 120, ...ROUGH }),
        "rough-path",
      ),
    );
    win.appendChild(codeSvg);
    const btn = el("button", { text: "Copy" });
    win.appendChild(btn);
    drawablyButton(btn, { variant: "outline", seed: 121 });
    drawablyCard(win, { seed: 122 });
  },

  4: (container) => {
    const s = svg(340, 200);
    s.appendChild(
      svgPath(
        roughRoundedRect(4, 4, 332, 192, 8, { seed: 130, ...ROUGH }),
        "rough-path",
      ),
    );
    // sidebar rows
    const dotStates = ["solid", "outline", "accent", "faded"];
    dotStates.forEach((state, i) => {
      const y = 20 + i * 24;
      if (state === "solid") {
        s.appendChild(
          svgPath(
            roughCircle(20, y, 5, { seed: 131 + i, ...ROUGH }),
            "rough-fill",
          ),
        );
      } else if (state === "accent") {
        const c = svgPath(
          roughCircle(20, y, 5, { seed: 131 + i, ...ROUGH }),
          "rough-fill",
        );
        c.setAttribute("fill", "var(--accent)");
        s.appendChild(c);
      } else {
        const c = svgPath(
          roughCircle(20, y, 5, { seed: 131 + i, ...ROUGH }),
          "rough-path",
        );
        if (state === "faded") c.setAttribute("opacity", "0.3");
        s.appendChild(c);
      }
      s.appendChild(svgText(34, y + 4, `row ${i + 1}`, "svg-label"));
    });
    // play triangle
    const tri = "M150 80 L150 120 L182 100 Z";
    s.appendChild(svgPath(tri, "rough-fill"));
    s.appendChild(svgText(300, 186, "0:14", "svg-label"));
    container.appendChild(s);
  },

  5: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    win.appendChild(
      el("div", { className: "sketch-title", text: "TOO MANY TERMINALS." }),
    );
    const row = el("div", { className: "sketch-row" });
    ["brew", "npx", "dmg"].forEach((label, i) => {
      const btn = el("button", { text: label });
      row.appendChild(btn);
      drawablyButton(btn, { variant: "outline", seed: 140 + i });
    });
    win.appendChild(row);
    const circleRow = el("div", { className: "sketch-row" });
    const versionSpan = el("span", { text: "v0.1.0" });
    circleRow.appendChild(versionSpan);
    win.appendChild(circleRow);
    drawablyCircle(versionSpan, { seed: 143 });
    drawablyCard(win, { seed: 144 });
  },

  6: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const grid = el("div");
    grid.style.display = "grid";
    grid.style.gridTemplateColumns = "1fr 1fr";
    grid.style.gap = "6px";
    win.appendChild(grid);
    [
      ["Orchestrator", "coordinate"],
      ["Reviewer", "critique"],
      ["Planner", "scope"],
      ["Explore", "research"],
    ].forEach(([name, subtitle], i) => {
      const c = el("div");
      c.style.padding = "6px 8px";
      c.appendChild(el("div", { text: name, className: "sketch-title" }));
      c.appendChild(el("div", { text: subtitle, className: "sketch-row" }));
      grid.appendChild(c);
      drawablyCard(c, { seed: 150 + i });
    });
    const btnRow = el("div", { className: "sketch-row" });
    const btn = el("button", { text: "New session" });
    btnRow.appendChild(btn);
    win.appendChild(btnRow);
    drawablyButton(btn, { variant: "solid", seed: 154 });
    drawablyCard(win, { seed: 155 });
  },

  7: (container) => {
    const s = svg(340, 200);
    s.appendChild(
      svgPath(
        roughLine(10, 20, 330, 20, { seed: 160, ...ROUGH }),
        "rough-path",
      ),
    );
    s.appendChild(svgPath(ghostGhostPath(), "rough-path")).setAttribute(
      "transform",
      "translate(16,10)",
    );
    s.appendChild(
      svgPath(
        roughRoundedRect(60, 30, 220, 120, 6, { seed: 161, ...ROUGH }),
        "rough-path",
      ),
    );
    const projects = ["ghostties", "brukas", "career-ops"];
    projects.forEach((name, i) => {
      const y = 55 + i * 30;
      const isNeedsYou = i === 2;
      const dot = svgPath(
        roughCircle(80, y, 5, { seed: 162 + i, ...ROUGH }),
        isNeedsYou ? "rough-fill" : "rough-path",
      );
      if (isNeedsYou) dot.setAttribute("fill", "var(--accent)");
      s.appendChild(dot);
      s.appendChild(
        svgText(
          96,
          y + 4,
          isNeedsYou ? `${name} — needs you` : name,
          "svg-label",
        ),
      );
    });
    container.appendChild(s);
  },

  8: (container) => {
    windowSketch(container, {
      title: null,
      rows: [
        { ghost: "solid", label: "ghostties" },
        { ghost: "outline", label: "brukas" },
        { ghost: "accent", label: "career-ops" },
        { ghost: "faded", label: "seansmithdesign" },
      ],
      seed: 170,
    });
  },

  9: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    win.appendChild(
      el("div", {
        className: "sketch-title",
        text: "How a Chromium downgrade killed my terminal",
      }),
    );
    const para = el("div");
    para.style.fontSize = "11px";
    para.style.opacity = "0.6";
    para.style.lineHeight = "1.4";
    para.textContent =
      "Bisected across four builds. No crash report, no catchable signal, dead in half a second.";
    win.appendChild(para);
    const link = el("div", { text: "read →" });
    win.appendChild(link);
    drawablyUnderline(link, { seed: 180 });
    drawablyCard(win, { seed: 181 });
  },

  10: (container) => {
    windowSketch(container, {
      title: "session-10",
      rows: [
        { label: "3 of 5 todos" },
        { label: "$1.42 · 48k tokens" },
        { label: "last tool: Edit · 12s ago" },
      ],
      seed: 190,
    });
    const btnRow = document.querySelector(`[data-sketch="10"] .sketch-window`);
    const btn = el("button", { text: "Focus" });
    btnRow.appendChild(btn);
    drawablyButton(btn, { variant: "outline", seed: 195 });
  },

  11: (container) => {
    const wrap = el("div");
    wrap.style.display = "flex";
    wrap.style.flexDirection = "column";
    wrap.style.gap = "8px";
    container.appendChild(wrap);

    const term = el("div", { className: "sketch-window" });
    wrap.appendChild(term);
    term.style.fontFamily = "monospace";
    term.appendChild(el("div", { text: "$ gt list" }));
    term.appendChild(el("div", { text: "• ship the release notes" }));
    term.appendChild(el("div", { text: "• fix composer tab space" }));
    term.appendChild(el("div", { text: "• record hero film" }));
    drawablyCard(term, { seed: 200 });

    const mini = el("div", { className: "sketch-window" });
    mini.id = "avenue-11-mini";
    mini.appendChild(
      el("div", { text: "see it in Ghostties", className: "sketch-row" }),
    );
    wrap.appendChild(mini);
    drawablyCard(mini, { seed: 201 });

    drawablyArrow(term, mini, { seed: 202 });
  },

  12: (container) => {
    const s = svg(200, 220);
    s.appendChild(
      svgPath(
        roughRoundedRect(30, 6, 140, 208, 18, { seed: 210, ...ROUGH }),
        "rough-path",
      ),
    );
    const rows = [
      { ghost: "outline", label: "ghostties" },
      { ghost: "outline", label: "brukas" },
      { ghost: "accent", label: "career-ops" },
      { ghost: "faded", label: "seansmithdesign" },
    ];
    rows.forEach((row, i) => {
      const y = 40 + i * 34;
      const ghost = ghostGlyphSVG(row.ghost);
      const use = document.createElementNS("http://www.w3.org/2000/svg", "g");
      use.setAttribute("transform", `translate(44, ${y - 12})`);
      use.appendChild(ghost.firstChild);
      s.appendChild(use);
      s.appendChild(svgText(64, y + 4, row.label, "svg-label"));
    });
    s.appendChild(svgText(70, 200, "07:12", "svg-label"));
    container.appendChild(s);
  },

  13: (container) => {
    const wrap = el("div");
    wrap.style.display = "flex";
    wrap.style.flexDirection = "column";
    wrap.style.gap = "24px";
    container.appendChild(wrap);

    const box1 = el("div", { className: "sketch-window" });
    box1.appendChild(el("div", { text: "Ghostty (upstream, untouched)" }));
    wrap.appendChild(box1);
    drawablyCard(box1, { seed: 220 });

    const box2 = el("div", { className: "sketch-window" });
    box2.appendChild(el("div", { text: "Ghostties app (sidebar + tasks)" }));
    wrap.appendChild(box2);
    drawablyCard(box2, { seed: 221 });

    const label = el("div", { text: "libghostty" });
    label.style.fontSize = "11px";
    label.style.opacity = "0.7";
    label.style.textAlign = "center";
    wrap.insertBefore(label, box2);

    drawablyArrow(box1, box2, { seed: 222 });
  },

  14: (container) => {
    windowSketch(container, {
      title: "ghostties",
      rows: [
        { ghost: "solid", label: "Frank · composer field" },
        { ghost: "outline", label: "Bob · release pipeline" },
        { ghost: "outline", label: "Vinnie · avenues doc" },
        { ghost: "faded", label: "Charlie · inbox triage" },
      ],
      seed: 700,
    });
  },

  15: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const tabRow = el("div", { className: "sketch-row" });
    ["Projects", "Sessions", "Staff"].forEach((label, i) => {
      const t = el("span", {
        text: label,
        className: i === 2 ? "sketch-tab-active" : "sketch-tab",
      });
      tabRow.appendChild(t);
    });
    win.appendChild(tabRow);
    const hr = el("hr");
    win.appendChild(hr);
    drawablyDivider(hr, { seed: 751 });
    [
      { name: "explore", tier: "haiku" },
      { name: "implementer", tier: "sonnet", note: "2 running" },
      { name: "planner", tier: "opus" },
      { name: "reviewer", tier: "opus" },
      { name: "strategist", tier: "fable" },
    ].forEach((agent, i) => {
      const rowEl = el("div", { className: "sketch-row" });
      rowEl.appendChild(ghostGlyphSVG(i === 1 ? "solid" : "outline"));
      rowEl.appendChild(document.createTextNode(agent.name));
      const chip = el("span", { text: agent.tier, className: "sketch-chip" });
      rowEl.appendChild(chip);
      if (agent.note) {
        rowEl.appendChild(
          el("span", { text: agent.note, className: "sketch-chip-accent" }),
        );
      }
      win.appendChild(rowEl);
    });
    drawablyCard(win, { seed: 750 });
  },

  16: (container) => {
    windowSketch(container, {
      title: null,
      rows: [{ ghost: "outline", label: "Frank · composer field" }],
      seed: 800,
    });
    const win = document.querySelector('[data-sketch="16"] .sketch-window');
    const needsRow = el("div", { className: "sketch-row" });
    needsRow.appendChild(ghostGlyphSVG("accent"));
    needsRow.appendChild(document.createTextNode("Bob · release pipeline"));
    win.appendChild(needsRow);
    const subtitle = el("div", {
      className: "sketch-subtitle",
      text: 'waiting: allow "npm publish"?',
    });
    win.appendChild(subtitle);
    const btn = el("button", { text: "Open" });
    win.appendChild(btn);
    drawablyButton(btn, { variant: "outline", seed: 806 });
  },

  17: (container) => {
    const wrap = el("div", { className: "sketch-row-wrap" });
    container.appendChild(wrap);
    const row = el("div", { className: "sketch-window" });
    row.id = "avenue-17-row";
    const rowLine = el("div", { className: "sketch-row" });
    rowLine.appendChild(ghostGlyphSVG("solid"));
    rowLine.appendChild(document.createTextNode("Frank · auth flow"));
    row.appendChild(rowLine);
    wrap.appendChild(row);
    drawablyCard(row, { seed: 850 });

    const popover = el("div", { className: "sketch-window" });
    popover.id = "avenue-17-popover";
    popover.appendChild(
      el("div", { text: "Hand to:", className: "sketch-title" }),
    );
    const bobLine = el("div", { className: "sketch-row" });
    bobLine.id = "avenue-17-bob";
    bobLine.appendChild(ghostGlyphSVG("outline"));
    bobLine.appendChild(document.createTextNode("Bob"));
    popover.appendChild(bobLine);
    ["Vinnie", "Charlie"].forEach((name, i) => {
      const l = el("div", { className: "sketch-row" });
      l.appendChild(ghostGlyphSVG(i === 1 ? "faded" : "outline"));
      l.appendChild(document.createTextNode(name));
      popover.appendChild(l);
    });
    wrap.appendChild(popover);
    drawablyCard(popover, { seed: 851 });

    drawablyArrow(row, document.getElementById("avenue-17-bob"), {
      seed: 852,
    });
  },

  18: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const title = el("div", { className: "sketch-row" });
    title.appendChild(ghostGlyphSVG("outline"));
    title.appendChild(document.createTextNode("Bob · back end"));
    title.classList.add("sketch-title");
    win.appendChild(title);
    ["model sonnet", "effort medium", "tools 6", "skills 4"].forEach((line) => {
      win.appendChild(el("div", { className: "sketch-row", text: line }));
    });
    win.appendChild(el("div", { className: "sketch-title", text: "Memory" }));
    [
      "fixed the CEF guard",
      "wrote the release notes",
      "reviewed PR #163",
    ].forEach((line) => {
      const p = el("div", { className: "sketch-subtitle", text: line });
      win.appendChild(p);
    });
    win.appendChild(
      el("div", { className: "sketch-row", text: "$4.10 this week" }),
    );
    drawablyCard(win, { seed: 900 });
  },

  19: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const row1 = el("div", { className: "sketch-row" });
    row1.appendChild(sleepingGhostSVG());
    row1.appendChild(
      document.createTextNode("Charlie · morning briefing · next 07:30"),
    );
    win.appendChild(row1);
    const hr = el("hr");
    win.appendChild(hr);
    drawablyDivider(hr, { seed: 951 });
    const row2 = el("div", { className: "sketch-row" });
    row2.appendChild(sleepingGhostSVG());
    row2.appendChild(document.createTextNode("Reviewer · on PR · idle"));
    win.appendChild(row2);
    const hr2 = el("hr");
    win.appendChild(hr2);
    drawablyDivider(hr2, { seed: 952 });
    const row3 = el("div", { className: "sketch-row" });
    row3.appendChild(ghostGlyphSVG("solid"));
    row3.appendChild(document.createTextNode("Charlie · running · 07:31"));
    win.appendChild(row3);
    drawablyCard(win, { seed: 950 });
  },

  20: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const top = el("div", { className: "sketch-row" });
    top.appendChild(ghostGlyphSVG("solid"));
    top.appendChild(document.createTextNode("Vinnie · orchestrator"));
    win.appendChild(top);
    [
      { label: "Frank · card 3", ghost: "solid" },
      { label: "Bob · card 4", ghost: "outline" },
      { label: "Frank · card 5", ghost: "solid" },
    ].forEach((row) => {
      const r = el("div", { className: "sketch-row sketch-indent-1" });
      r.appendChild(ghostGlyphSVG(row.ghost));
      r.appendChild(document.createTextNode(row.label));
      win.appendChild(r);
      if (row.label === "Bob · card 4") {
        const waiting = el("div", {
          className: "sketch-row sketch-indent-2",
        });
        waiting.appendChild(ghostGlyphSVG("outline"));
        waiting.appendChild(
          document.createTextNode("Reviewer · waiting on Bob"),
        );
        win.appendChild(waiting);
      }
    });
    drawablyCard(win, { seed: 1000 });
  },

  21: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    [
      { name: "Frank", badge: "local" },
      { name: "Vinnie", badge: "cloud" },
      { name: "Bob", badge: "codex" },
    ].forEach((agent, i) => {
      const row = el("div", { className: "sketch-row" });
      row.appendChild(ghostGlyphSVG("outline"));
      row.appendChild(document.createTextNode(agent.name));
      if (agent.badge === "cloud") {
        const s = svg(24, 16);
        s.appendChild(
          svgPath(
            roughRoundedRect(2, 4, 20, 10, 5, { seed: 1050 + i, ...ROUGH }),
            "rough-path",
          ),
        );
        s.appendChild(
          svgPath(
            roughCircle(9, 4, 4, { seed: 1051 + i, ...ROUGH }),
            "rough-path",
          ),
        );
        row.appendChild(s);
      } else {
        row.appendChild(
          el("span", { text: agent.badge, className: "sketch-chip" }),
        );
      }
      win.appendChild(row);
    });
    drawablyCard(win, { seed: 1055 });
  },

  22: (container) => {
    const win = el("div", { className: "sketch-window" });
    container.appendChild(win);
    const title = el("div", { className: "sketch-row" });
    title.appendChild(ghostGlyphSVG("outline"));
    title.appendChild(document.createTextNode("Reviewer Rita"));
    title.classList.add("sketch-title");
    win.appendChild(title);
    win.appendChild(
      el("div", { className: "sketch-subtitle", text: "by @someone" }),
    );
    const badge = el("span", { text: "import" });
    win.appendChild(badge);
    drawablyBadge(badge, {
      variant: "scribble",
      seed: 1100,
      stroke: "var(--accent)",
      fill: "var(--accent)",
    });
    const dropSvg = svg(300, 60);
    dropSvg.appendChild(
      svgPath(
        roughRoundedRect(2, 2, 296, 56, 6, { seed: 1101, ...ROUGH }),
        "rough-path-dashed",
      ),
    );
    dropSvg.appendChild(svgText(20, 34, "drop an agent bundle", "svg-label"));
    win.appendChild(dropSvg);
    drawablyCard(win, { seed: 1102 });
  },

  23: (container) => {
    const wrap = el("div", { className: "sketch-taglines" });
    container.appendChild(wrap);
    [
      "One window. Your whole staff.",
      "A home for your agents.",
      "Ghostties — where your agents live.",
    ].forEach((line, i) => {
      const span = el("span", { text: line, className: "sketch-tagline" });
      wrap.appendChild(span);
      drawablyCircle(span, { seed: 1150 + i });
    });
  },
};

function ghostGhostPath() {
  return "M2 15 L2 7.2 C2 3.8 4.7 1 8 1 C11.3 1 14 3.8 14 7.2 L14 15 L11.5 12.6 L9 15 L7 13 L5 15 L2 15 Z";
}

document.querySelectorAll("[data-sketch]").forEach((container) => {
  const n = container.getAttribute("data-sketch");
  const build = sketches[n];
  if (build) build(container);
});

// ---------- checkbox / input attach + persistence ----------

const pickRows = Array.from(document.querySelectorAll("[data-pick-row]"));

pickRows.forEach((row) => {
  const avenue = row.getAttribute("data-avenue");
  const checkboxWrap = row.querySelector("[data-checkbox-wrap]");
  const inputWrap = row.querySelector("[data-input-wrap]");
  const checkboxInput = checkboxWrap.querySelector("input");
  const textInput = inputWrap.querySelector("input");

  drawablyCheckbox(checkboxWrap, { seed: 300 + Number(avenue) });
  drawablyInput(inputWrap, { seed: 400 + Number(avenue) });

  const savedChecked = storageGet(`picked:${avenue}`);
  if (savedChecked === "true") checkboxInput.checked = true;

  const savedNote = storageGet(`note:${avenue}`);
  if (savedNote) textInput.value = savedNote;

  checkboxInput.addEventListener("change", () => {
    storageSet(`picked:${avenue}`, checkboxInput.checked ? "true" : "false");
    updatePicksCount();
  });

  textInput.addEventListener("input", () => {
    storageSet(`note:${avenue}`, textInput.value);
  });
});

function updatePicksCount() {
  const count = pickRows.filter((row) => {
    const avenue = row.getAttribute("data-avenue");
    return storageGet(`picked:${avenue}`) === "true";
  }).length;
  document.getElementById("picks-count").textContent = `${count} picked`;
}

updatePicksCount();

// ---------- copy picks ----------

const copyBtn = document.getElementById("copy-picks-btn");
const copyBtnSketch = drawablyButton(copyBtn, { variant: "solid", seed: 500 });

// ---------- Part three: header, intro, captures, rig facts, table, defects ----------

drawablyUnderline(document.getElementById("jump-part-three"), { seed: 1200 });
drawablyUnderline(document.getElementById("visual-pass-underline"), {
  seed: 1201,
});

drawablyCard(document.getElementById("part3-intro-card"), { seed: 1202 });

document
  .querySelectorAll("#part3-findings-list .capture-card[data-card]")
  .forEach((cardEl, i) => {
    drawablyCard(cardEl, { seed: 1210 + i });
  });

drawablyList(document.getElementById("part3-findings-list"), {
  marker: "dash",
  seed: 1230,
});

drawablyCard(document.getElementById("part3-rig-facts"), { seed: 1231 });

drawablyCard(document.getElementById("part3-moved-table-card"), {
  seed: 1232,
});

drawablyCard(document.getElementById("part3-recommendation-card"), {
  seed: 1233,
  stroke: "var(--accent)",
});

drawablyArrow(
  document.getElementById("part3-recommendation-card"),
  document.getElementById("part3-moved-table-card"),
  { seed: 1234 },
);

drawablyList(document.getElementById("part3-defects-list"), {
  marker: "dash",
  seed: 1235,
});

copyBtn.addEventListener("click", async () => {
  const lines = ["Ghostties — picks (5 Sep 2026)"];
  pickRows.forEach((row) => {
    const avenue = row.getAttribute("data-avenue");
    const title = row.getAttribute("data-title");
    if (storageGet(`picked:${avenue}`) === "true") {
      const note = storageGet(`note:${avenue}`);
      const suffix = note ? ` — ${note}` : "";
      lines.push(`- ${avenue}. ${title}${suffix}`);
    }
  });
  const text = lines.join("\n");
  try {
    await navigator.clipboard.writeText(text);
  } catch (e) {
    /* clipboard may be unavailable; ignore */
  }
  copyBtnSketch.setState("success");
  setTimeout(() => copyBtnSketch.setState("idle"), 2000);
});
