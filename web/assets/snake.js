/*
 * ghostties.org — hero token-collector game
 *
 * Ported from the v2 herd-the-ghosts prototype (see git history for the
 * original), gutted and re-mechanic'd per the locked decision: the head is
 * a cursor, not a snake body; the collectibles are LLM tokens, not ghosts;
 * the robot sprites drift as ambient hazards; and the payoff is a
 * confetti-solitaire cascade when the context window fills.
 *
 * What survives the port unchanged from the original engine:
 *  - Grid derived from the mount's measured width, responsive COLS.
 *  - The head's tweened translate3d movement + wraparound.
 *  - Sound (lazy AudioContext, off by default), keyboard input, a11y
 *    live region, IntersectionObserver pause-when-offscreen, bfcache
 *    reinit, and the whole start/end game DOM lifecycle.
 *
 * What's gone: the eight-ghost herd/rescue/stray mechanic, the old
 * rounded-dome/wavy-skirt ghost drawing code (Pac-Man IP exposure, see
 * MEMORY.md), and the autopilot demo (think() + the "auto" flag) — the
 * page is a page until someone inserts a coin, and once they do, they are
 * the only thing moving the cursor.
 *
 * Ghost hazard art is NOT duplicated here. It's drawn through
 * window.GXField.buildGhostSVG(i, opts), the one place the sprite data
 * lives (assets/ghost-field.js). If that API isn't present — e.g. ghost-field.js
 * failed to load, or snake.js was somehow loaded first — this file
 * degrades to doing nothing rather than guessing at a shape.
 */
(function () {
  "use strict";

  // A real BPE/WordPiece token look: "▮" marks a leading space (SentencePiece
  // style), "##" marks a wordpiece continuation, plain fragments are BPE
  // merges. Isolated in one spot (buildToken, below) so the visual can be
  // swapped without touching game logic.
  var TOKEN_LABELS = [
    "▮ing",
    "▮the",
    "tion",
    "▮is",
    "##ed",
    "▮a",
    "▮to",
    "▮of",
    "▮an",
    "ate",
    "er",
    "▮or",
  ];

  function buildToken(label) {
    var el = document.createElement("div");
    el.className = "snake-token";
    var chip = document.createElement("span");
    chip.className = "snake-token-chip";
    chip.textContent = label;
    el.appendChild(chip);
    return el;
  }

  // Win condition: fill the context window. Tuned by feel for a 60-90s
  // round at the default herd/evict rates below.
  var TARGET_TOKENS = 40;
  // How many tokens a hazard touch knocks out of context.
  var EVICT_AMOUNT = 4;
  // How many tokens are live on the field at once.
  var TOKEN_POOL = 4;
  // How many robot sprites drift as hazards (indices into the ghost
  // roster via GXField — a subset, not the full roster, so a 5-row field doesn't
  // drown in obstacles).
  var HAZARD_COUNT = 4;

  function init() {
    var wrap = document.querySelector(".snake-wrap");
    var mount = document.getElementById("snake-mount");
    var startBtn = document.getElementById("snake-start");
    var soundBtn = document.getElementById("snake-sound");
    var heroSection = document.getElementById("hero");
    var statusEl = document.getElementById("snake-status");
    if (!wrap || !mount || !startBtn || !soundBtn) return;

    // Degrade gracefully if the sprite source isn't there — no ghost
    // hazards, no game. Nothing user-visible logged.
    var GX = window.GXField;
    if (!GX || typeof GX.buildGhostSVG !== "function") return;

    // A polite live region only speaks its latest value — setting it
    // twice in quick succession (e.g. an eviction landing right next
    // to the periodic pickup aggregate) silently drops whichever
    // message got overwritten before a screen reader read it.
    // Confirmed: the eviction message, the one that explains the
    // mechanic, dropped twice in one round (S4). Queue messages and
    // space them out instead of writing straight to the node.
    var announceQueue = [];
    var announceTimer = null;
    function drainAnnounce() {
      if (announceQueue.length === 0) {
        announceTimer = null;
        return;
      }
      var msg = announceQueue.shift();
      if (statusEl) {
        statusEl.textContent = "";
        requestAnimationFrame(function () {
          statusEl.textContent = msg;
        });
      }
      announceTimer = setTimeout(drainAnnounce, 900);
    }
    function announce(msg) {
      if (!statusEl) return;
      announceQueue.push(msg);
      // Cap the backlog so a burst of hits doesn't queue up minutes of
      // stale narration — keep the most recent few.
      if (announceQueue.length > 4) announceQueue.shift();
      if (!announceTimer) drainAnnounce();
    }

    var reducedMotion = window.matchMedia
      ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
      : false;
    // The section itself is hidden under reduced motion (see v3.css) —
    // same contract as the ambient ghost field and coin plate: an inert
    // control left visible-but-dead is worse than not mounting at all.
    if (reducedMotion) return;

    // --- DOM scaffold ------------------------------------------------------
    mount.innerHTML = "";
    var frameEl = document.createElement("div");
    frameEl.className = "snake-frame";

    var hud = document.createElement("div");
    hud.className = "snake-hud";
    hud.innerHTML =
      '<span class="snake-stat"><span class="k">Tokens</span><span class="v" data-tokens>0</span></span>' +
      '<span class="snake-stat snake-context-stat" data-context-cell>' +
      '<span class="k">Context</span>' +
      '<span class="snake-meter"><span class="snake-meter-fill" data-context-fill></span></span>' +
      "</span>" +
      // A real button, not a decorative span — Escape was previously
      // the only way out, advertised by an 8px HUD chip with no
      // pointer/touch path at all (B4).
      '<button type="button" class="snake-stat dim snake-exit-hint" ' +
      'data-exit><span class="k">Esc</span><span class="v">Exit</span></button>';
    frameEl.appendChild(hud);

    var field = document.createElement("div");
    field.className = "snake-field";
    frameEl.appendChild(field);

    var headEl = document.createElement("div");
    headEl.className = "snake-head";
    headEl.innerHTML = "<i></i>";
    field.appendChild(headEl);

    var flashEl = document.createElement("div");
    flashEl.className = "snake-flash";
    frameEl.appendChild(flashEl);

    // Touch decision (B4): arrow keys/WASD have no touch equivalent,
    // so a coarse-pointer device could Insert Coin and then have no
    // way to move or exit. Rather than dropping the game on touch,
    // give it a real control — a 4-button d-pad, shown only on
    // coarse-pointer devices, only while playing (see .has-touch in
    // v3.css).
    var isTouch =
      window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
    if (isTouch) wrap.classList.add("has-touch");
    var dpad = document.createElement("div");
    dpad.className = "snake-dpad";
    dpad.innerHTML =
      '<button type="button" class="snake-dpad-btn snake-dpad-up" ' +
      'aria-label="Move up">&#9650;</button>' +
      '<button type="button" class="snake-dpad-btn snake-dpad-left" ' +
      'aria-label="Move left">&#9664;</button>' +
      '<button type="button" class="snake-dpad-btn snake-dpad-right" ' +
      'aria-label="Move right">&#9654;</button>' +
      '<button type="button" class="snake-dpad-btn snake-dpad-down" ' +
      'aria-label="Move down">&#9660;</button>';
    frameEl.appendChild(dpad);
    var DPAD_DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
    ["up", "down", "left", "right"].forEach(function (name) {
      var btn = dpad.querySelector(".snake-dpad-" + name);
      btn.addEventListener("click", function () {
        if (mode !== "play") return;
        var d = DPAD_DIRS[name];
        if (d[0] !== -dir[0] || d[1] !== -dir[1]) next = d;
      });
    });

    var cascadeCanvas = document.createElement("canvas");
    cascadeCanvas.className = "snake-cascade";
    // Appended to <body>, not frameEl: the cascade escapes the game's
    // box and covers the page (see winGame()/B2), so it is fixed to
    // the viewport, not the field. Sized explicitly in
    // sizeCascadeCanvas() below — inset:0 alone does not stretch a
    // <canvas> bitmap, it only positions the box.
    document.body.appendChild(cascadeCanvas);
    var cascadeCtx = cascadeCanvas.getContext("2d");

    mount.appendChild(frameEl);

    var tokensEl = hud.querySelector("[data-tokens]");
    var fillEl = hud.querySelector("[data-context-fill]");
    var contextCell = hud.querySelector("[data-context-cell]");
    var exitBtn = hud.querySelector("[data-exit]");

    // --- responsive grid -----------------------------------------------
    var ROWS = 5;
    var COLS = 16;
    var CELL = 40;

    function computeCols(width) {
      if (width < 480) return 10;
      if (width < 900) return 16;
      return 22;
    }

    function layoutGrid() {
      var width = mount.clientWidth || 320;
      var prevCols = COLS;
      COLS = computeCols(width);
      CELL = width / COLS;
      field.style.height = Math.round(ROWS * CELL) + "px";
      mount.style.setProperty("--cell", CELL + "px");
      sizeCascadeCanvas();
      // A resize can shrink COLS mid-round (e.g. rotating a phone).
      // Hazards re-derive cx from the field fraction every layout
      // (positionEntities, below) so they're always in range, but the
      // head and tokens keep their old cell index — clamp both back
      // into the new grid or they render outside the field, clipped
      // by overflow:hidden and unreachable (B3).
      if (COLS !== prevCols) {
        hx = Math.min(hx, COLS - 1);
        tokens.forEach(function (tk) {
          tk.cx = Math.min(tk.cx, COLS - 1);
        });
      }
    }

    // Cascade canvas is fixed to the viewport (see DOM scaffold above),
    // so it is sized from window dimensions, not the field. Bitmap is
    // set from CSS size * devicePixelRatio and the context is scaled
    // back down, or a DPR-2 display renders the cascade at half res.
    var cascadeW = 0,
      cascadeH = 0;
    function sizeCascadeCanvas() {
      var dpr = window.devicePixelRatio || 1;
      cascadeW = window.innerWidth;
      cascadeH = window.innerHeight;
      cascadeCanvas.style.width = cascadeW + "px";
      cascadeCanvas.style.height = cascadeH + "px";
      cascadeCanvas.width = Math.round(cascadeW * dpr);
      cascadeCanvas.height = Math.round(cascadeH * dpr);
      if (cascadeCtx) cascadeCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function px(c) {
      return c * CELL;
    }
    function py(r) {
      return r * CELL;
    }

    // --- game state ------------------------------------------------------
    var fieldVisible = false;
    var mode = "idle"; // idle | play | win
    var hx = 1,
      hy = 2,
      dir = [1, 0],
      next = [1, 0];
    var hpx = 0,
      hpy = 0;
    var f = 0,
      t = 0;
    var tokensCollected = 0;
    var pickupsSinceAnnounce = 0;
    var soundOn = false;
    var ac = null;

    // hazards — same ambient sinusoidal drift as the old herd ghosts,
    // just no capture/rank state; walking into one always evicts.
    var hazards = [];
    for (var hi = 0; hi < HAZARD_COUNT; hi++) {
      var hazEl = document.createElement("div");
      hazEl.className = "gh";
      hazEl.innerHTML = GX.buildGhostSVG(hi % GX.ghostCount(), {});
      field.appendChild(hazEl);
      hazards.push({
        el: hazEl,
        x: 0,
        y: 0,
        ix: 0,
        iy: 0,
        idlePhase: hi * 0.79,
        cx: 0,
        cy: 0,
      });
    }

    // tokens — a small pool live on the field at once; collecting one
    // respawns a fresh one at a free cell.
    var tokens = [];

    function occupiedCells() {
      var set = {};
      set[hx + "," + hy] = true;
      hazards.forEach(function (h) {
        set[h.cx + "," + h.cy] = true;
      });
      tokens.forEach(function (tk) {
        set[tk.cx + "," + tk.cy] = true;
      });
      return set;
    }

    function randomFreeCell() {
      var occ = occupiedCells();
      for (var tries = 0; tries < 40; tries++) {
        var cx = Math.floor(Math.random() * COLS);
        var cy = Math.floor(Math.random() * ROWS);
        if (!occ[cx + "," + cy]) return [cx, cy];
      }
      return [Math.floor(Math.random() * COLS), Math.floor(Math.random() * ROWS)];
    }

    function spawnToken() {
      var cell = randomFreeCell();
      var label = TOKEN_LABELS[Math.floor(Math.random() * TOKEN_LABELS.length)];
      var el = buildToken(label);
      // Must be set here, not just in positionEntities() — that only runs
      // on layout/resize, so a token spawned mid-round (every pickup
      // triggers one) would otherwise sit untransformed at the field's
      // origin instead of its assigned cell.
      el.style.transform =
        "translate3d(" + px(cell[0]).toFixed(1) + "px," + py(cell[1]).toFixed(1) + "px,0)";
      field.appendChild(el);
      tokens.push({ el: el, cx: cell[0], cy: cell[1] });
    }

    // Single source for a hazard's collision cell, derived from its
    // actual rendered position (h.x/h.y) — both callers below used to
    // compute this independently (one from the wander center h.ix/h.iy,
    // one inline in frame()), and could disagree by up to the sprite's
    // full drift offset (S1): the sprite draws at h.x/h.y, so the
    // eviction hitbox now always matches what's on screen.
    function updateHazardCell(h) {
      h.cx = Math.min(COLS - 1, Math.max(0, Math.round(h.x / CELL)));
      h.cy = Math.min(ROWS - 1, Math.max(0, Math.round(h.y / CELL)));
    }

    function positionEntities() {
      var fw = field.clientWidth || CELL * COLS;
      var fh = ROWS * CELL;
      hazards.forEach(function (h, j) {
        h.ix = fw * ((j + 0.5) / hazards.length);
        h.iy = fh * (0.5 + 0.28 * Math.sin(j * 1.7 + 1));
        h.x = h.ix;
        h.y = h.iy;
        updateHazardCell(h);
        h.el.style.transform =
          "translate3d(" + h.x.toFixed(1) + "px," + h.y.toFixed(1) + "px,0)";
      });
      tokens.forEach(function (tk) {
        tk.el.style.transform =
          "translate3d(" + px(tk.cx).toFixed(1) + "px," + py(tk.cy).toFixed(1) + "px,0)";
      });
    }

    function layoutAndPosition() {
      layoutGrid();
      positionEntities();
    }

    layoutAndPosition();
    hpx = px(hx);
    hpy = py(hy);
    headEl.style.transform =
      "translate3d(" + hpx.toFixed(1) + "px," + hpy.toFixed(1) + "px,0)";

    var ro = window.ResizeObserver
      ? new ResizeObserver(function () {
          layoutAndPosition();
        })
      : null;
    if (ro) ro.observe(mount);
    else window.addEventListener("resize", layoutAndPosition);
    // Viewport height can change without the mount's width changing
    // (e.g. mobile URL-bar collapse), which ResizeObserver(mount)
    // won't catch — the cascade canvas needs its own listener.
    window.addEventListener("resize", sizeCascadeCanvas);

    // --- sound -------------------------------------------------------------
    function sfx(name) {
      if (!soundOn) return;
      if (!ac) {
        var AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        ac = new AC();
      }
      if (ac.state === "suspended") ac.resume();
      var now = ac.currentTime;
      function play(freq, t0, dur, type, peak) {
        var o = ac.createOscillator();
        var g = ac.createGain();
        o.type = type || "square";
        o.frequency.setValueAtTime(freq, now + t0);
        g.gain.setValueAtTime(0.0001, now + t0);
        g.gain.exponentialRampToValueAtTime(peak || 0.14, now + t0 + 0.008);
        g.gain.exponentialRampToValueAtTime(0.0001, now + t0 + dur);
        o.connect(g);
        g.connect(ac.destination);
        o.start(now + t0);
        o.stop(now + t0 + dur + 0.02);
      }
      if (name === "coin") {
        play(180, 0, 0.05, "square", 0.1);
        play(988, 0.06, 0.07);
        play(1319, 0.13, 0.34);
      } else if (name === "collect") {
        play(660, 0, 0.045, "square", 0.1);
        play(990, 0.045, 0.07, "square", 0.1);
      } else if (name === "evict") {
        // Same descending-sawtooth shape the old engine used for its
        // "stray" mechanic — losing something you'd collected.
        var o = ac.createOscillator();
        var g = ac.createGain();
        o.type = "sawtooth";
        o.frequency.setValueAtTime(520, now);
        o.frequency.exponentialRampToValueAtTime(150, now + 0.3);
        g.gain.setValueAtTime(0.09, now);
        g.gain.exponentialRampToValueAtTime(0.0001, now + 0.32);
        o.connect(g);
        g.connect(ac.destination);
        o.start(now);
        o.stop(now + 0.34);
      } else if (name === "win") {
        play(784, 0, 0.06);
        play(1046, 0.06, 0.06);
        play(1568, 0.12, 0.2);
        play(2093, 0.24, 0.3);
      }
    }

    soundBtn.addEventListener("click", function () {
      soundOn = !soundOn;
      soundBtn.setAttribute("aria-pressed", String(soundOn));
      soundBtn.textContent = soundOn ? "SOUND ON" : "SOUND OFF";
      if (soundOn && !ac) {
        var AC = window.AudioContext || window.webkitAudioContext;
        if (AC) ac = new AC();
      }
    });

    // --- input ---------------------------------------------------------
    var MAP = {
      w: [0, -1],
      arrowup: [0, -1],
      a: [-1, 0],
      arrowleft: [-1, 0],
      s: [0, 1],
      arrowdown: [0, 1],
      d: [1, 0],
      arrowright: [1, 0],
    };

    function isEditableTarget(target) {
      if (!target) return false;
      var tag = target.tagName ? target.tagName.toLowerCase() : "";
      if (tag === "input" || tag === "textarea" || tag === "select") return true;
      if (target.isContentEditable) return true;
      return false;
    }

    function resetRound() {
      hx = 1;
      hy = 2;
      dir = [1, 0];
      next = [1, 0];
      f = 0;
      tokensCollected = 0;
      pickupsSinceAnnounce = 0;
      hpx = px(hx);
      hpy = py(hy);
      headEl.style.transform =
        "translate3d(" + hpx.toFixed(1) + "px," + hpy.toFixed(1) + "px,0)";
      tokens.forEach(function (tk) {
        tk.el.remove();
      });
      tokens = [];
      for (var i = 0; i < TOKEN_POOL; i++) spawnToken();
      positionEntities();
      tokensEl.textContent = "0";
      fillEl.style.width = "0%";
      contextCell.classList.remove("alert");
      clearCascade();
    }

    function startGame() {
      if (mode !== "idle") return;
      mode = "play";
      // frame() only self-reschedules while mode === "play" (S6), so
      // the loop needs an explicit kick here — it won't still be
      // spinning from before if the section was idle-but-visible.
      startLoop();
      wrap.classList.add("is-playing");
      if (heroSection) heroSection.classList.add("is-playing");
      mount.setAttribute("aria-hidden", "false");
      frameEl.tabIndex = -1;
      frameEl.setAttribute("role", "application");
      frameEl.setAttribute(
        "aria-label",
        "Token collector game. Use arrow keys or WASD to collect tokens and fill the context window. Avoid the ghosts. Press Escape to exit.",
      );
      startBtn.setAttribute("aria-hidden", "true");
      startBtn.tabIndex = -1;
      resetRound();
      flashEl.classList.remove("go");
      void flashEl.offsetWidth;
      flashEl.classList.add("go");
      sfx("coin");
      frameEl.focus({ preventScroll: true });
      announce(
        "Game started. Collect tokens to fill the context window. Touching a ghost evicts tokens. Press Escape to exit.",
      );
    }

    function endGame() {
      if (mode === "idle") return;
      mode = "idle";
      wrap.classList.remove("is-playing");
      if (heroSection) heroSection.classList.remove("is-playing");
      mount.setAttribute("aria-hidden", "true");
      frameEl.removeAttribute("tabindex");
      frameEl.removeAttribute("role");
      frameEl.removeAttribute("aria-label");
      startBtn.removeAttribute("aria-hidden");
      startBtn.tabIndex = 0;
      startBtn.focus({ preventScroll: true });
      clearCascade();
      announce("Game stopped. Press Insert Coin to play again.");
    }

    startBtn.addEventListener("click", startGame);
    exitBtn.addEventListener("click", endGame);

    function onKeyDown(e) {
      if (isEditableTarget(e.target)) return;
      var k = e.key ? e.key.toLowerCase() : "";

      if (mode === "idle") {
        if (k !== "i") return;
        if (!fieldVisible) return;
        e.preventDefault();
        startGame();
        return;
      }

      if (k === "escape") {
        e.preventDefault();
        endGame();
        return;
      }

      if (mode === "win") return; // cascade is running — nothing else to do but exit

      var d = MAP[k];
      if (!d) return;
      if (!fieldVisible) return;
      // Arrow keys/WASD were captured window-wide off mode/fieldVisible
      // alone, with no focus check — confirmed swallowing ArrowDown on
      // the SOUND OFF button instead of scrolling the page (S3). Only
      // steer the game while focus is actually inside it.
      var active = document.activeElement;
      if (active !== frameEl && !frameEl.contains(active)) return;
      e.preventDefault();
      if (d[0] !== -dir[0] || d[1] !== -dir[1]) next = d;
    }
    window.addEventListener("keydown", onKeyDown);

    // --- simulation ------------------------------------------------------
    function move() {
      dir = next;
      hx = (hx + dir[0] + COLS) % COLS;
      hy = (hy + dir[1] + ROWS) % ROWS;

      for (var i = tokens.length - 1; i >= 0; i--) {
        var tk = tokens[i];
        if (tk.cx === hx && tk.cy === hy) {
          tk.el.remove();
          tokens.splice(i, 1);
          tokensCollected++;
          pickupsSinceAnnounce++;
          sfx("collect");
          spawnToken();
        }
      }

      for (var j = 0; j < hazards.length; j++) {
        var h = hazards[j];
        if (h.cx === hx && h.cy === hy) {
          var before = tokensCollected;
          tokensCollected = Math.max(0, tokensCollected - EVICT_AMOUNT);
          if (tokensCollected !== before) {
            sfx("evict");
            contextCell.classList.add("alert");
            setTimeout(function () {
              contextCell.classList.remove("alert");
            }, 320);
            announce(
              "Ghost hit. Lost " + (before - tokensCollected) + " tokens from context.",
            );
          }
        }
      }

      tokensEl.textContent = String(tokensCollected);
      var pct = Math.min(100, Math.round((tokensCollected / TARGET_TOKENS) * 100));
      fillEl.style.width = pct + "%";

      if (pickupsSinceAnnounce >= 5) {
        pickupsSinceAnnounce = 0;
        announce(tokensCollected + " tokens in context.");
      }

      if (tokensCollected >= TARGET_TOKENS) {
        winGame();
      }
    }

    // --- confetti-solitaire cascade --------------------------------------
    var cascadePieces = [];
    var cascadeRunning = false;
    var cascadeRaf = null;
    var CASCADE_COLORS = ["#ffd54f", "#00e5ff", "#7c4dff", "#7ce9f7", "#b39cff"];
    var GRAVITY = 0.32;
    var RESTITUTION = 0.62;

    function clearCascade() {
      cascadeRunning = false;
      if (cascadeRaf) {
        cancelAnimationFrame(cascadeRaf);
        cascadeRaf = null;
      }
      cascadePieces = [];
      if (cascadeCtx) {
        cascadeCtx.clearRect(0, 0, cascadeCanvas.width, cascadeCanvas.height);
      }
      cascadeCanvas.classList.remove("go");
    }

    function launchCascadePiece(delayMs) {
      setTimeout(function () {
        if (mode !== "win") return;
        // Cascade canvas is fixed to the viewport, so the meter's own
        // getBoundingClientRect() is already in the right coordinate
        // space — no subtracting the field's offset (B1).
        var rect = fillEl.getBoundingClientRect();
        var x0 = rect.left + rect.width / 2;
        var y0 = rect.top + rect.height / 2;
        // Wide horizontal spread scaled to viewport width so the
        // cascade erupts out of the meter and covers the full page
        // width (B2), not a single point at the meter's x position.
        var spread = (Math.random() - 0.5) * cascadeW * 0.9;
        cascadePieces.push({
          x: x0 + spread * 0.08,
          px: x0 + spread * 0.08,
          y: y0,
          py: y0,
          vx: spread / 46,
          vy: -6 - Math.random() * 9,
          size: 4 + Math.random() * 3,
          color: CASCADE_COLORS[Math.floor(Math.random() * CASCADE_COLORS.length)],
          settled: false,
        });
      }, delayMs);
    }

    function tickCascade() {
      if (!cascadeRunning) return;
      var w = cascadeW,
        h = cascadeH;
      var active = false;
      cascadePieces.forEach(function (p) {
        if (p.settled) return;
        active = true;
        p.vy += GRAVITY;
        p.px = p.x;
        p.py = p.y;
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0) {
          p.x = 0;
          p.vx *= -RESTITUTION;
        }
        if (p.x > w) {
          p.x = w;
          p.vx *= -RESTITUTION;
        }
        if (p.y > h - p.size) {
          p.y = h - p.size;
          p.vy *= -RESTITUTION;
          p.vx *= 0.85; // floor friction
          if (Math.abs(p.vy) < 0.6) p.settled = true;
        }
        // Stroke a segment from the last frame's position to this
        // one, not a single dot at the new position — per-frame vy
        // can exceed piece size, so a dot-per-frame renders as a
        // dotted smear instead of the solid overlapping arcs the
        // Solitaire cascade reads as (B2).
        cascadeCtx.strokeStyle = p.color;
        cascadeCtx.lineWidth = p.size;
        cascadeCtx.lineCap = "round";
        cascadeCtx.beginPath();
        cascadeCtx.moveTo(p.px, p.py);
        cascadeCtx.lineTo(p.x, p.y);
        cascadeCtx.stroke();
      });
      // Trail is never cleared — the screen fills up. Keep animating as
      // long as anything is still moving.
      if (active) cascadeRaf = requestAnimationFrame(tickCascade);
      else {
        cascadeRunning = false;
        cascadeRaf = null;
      }
    }

    function winGame() {
      if (mode === "win") return;
      mode = "win";
      sfx("win");
      cascadeCanvas.classList.add("go");
      cascadeRunning = true;
      cascadePieces = [];
      announce(
        "Context window full. " + TARGET_TOKENS + " tokens collected. Press Escape to exit.",
      );
      sizeCascadeCanvas();
      for (var i = 0; i < TARGET_TOKENS; i++) {
        launchCascadePiece(i * 40);
      }
      cascadeRaf = requestAnimationFrame(tickCascade);
    }

    // --- render loop -------------------------------------------------------
    var speed = 8.5;
    var raf = null;
    var running = false;

    function frame() {
      t += 1 / 60;

      if (mode === "play") {
        var step = Math.max(1, Math.round(60 / speed));
        if (f % step === 0) move();
        f++;
      }

      var tx = px(hx),
        ty = py(hy);
      if (Math.abs(tx - hpx) > CELL * 1.6) hpx = tx;
      else hpx += (tx - hpx) * 0.4;
      if (Math.abs(ty - hpy) > CELL * 1.6) hpy = ty;
      else hpy += (ty - hpy) * 0.4;
      headEl.style.transform =
        "translate3d(" + hpx.toFixed(1) + "px," + hpy.toFixed(1) + "px,0)";

      if (mode === "play") {
        hazards.forEach(function (h) {
          var gx = h.ix + Math.sin(t * 0.52 + h.idlePhase) * (CELL * 0.35);
          var gy = h.iy + Math.cos(t * 0.63 + h.idlePhase) * (CELL * 0.28);
          h.x = gx;
          h.y = gy;
          h.el.style.transform =
            "translate3d(" + h.x.toFixed(1) + "px," + h.y.toFixed(1) + "px,0)";
          // Nearest cell to the sprite's actual drawn position, not
          // its wander center (S1) — see updateHazardCell() above.
          updateHazardCell(h);
        });
      }

      // A 60fps loop only has work to do while a round is running —
      // hazard drift and the head's move-tween both only fire under
      // mode === "play". Left unconditional, this ran indefinitely
      // whenever the section was merely visible (attract-screen idle,
      // or after a win), a second full-rate loop next to the ambient
      // field's own (S6). Only self-reschedule during play; startGame()
      // calls startLoop() to restart the chain.
      if (mode === "play") {
        raf = requestAnimationFrame(frame);
      } else {
        running = false;
        raf = null;
      }
    }

    function startLoop() {
      if (running) return;
      running = true;
      raf = requestAnimationFrame(frame);
    }
    function stopLoop() {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    }

    var io =
      "IntersectionObserver" in window
        ? new IntersectionObserver(
            function (entries) {
              var visible = entries[0] && entries[0].isIntersecting;
              fieldVisible = !!visible;
              if (visible) startLoop();
              else stopLoop();
            },
            { threshold: 0.01 },
          )
        : null;
    if (io) io.observe(mount);
    else {
      fieldVisible = true;
      startLoop();
    }

    function teardown() {
      stopLoop();
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("resize", layoutAndPosition);
      window.removeEventListener("resize", sizeCascadeCanvas);
      if (announceTimer) {
        clearTimeout(announceTimer);
        announceTimer = null;
      }
      if (ro) ro.disconnect();
      if (io) io.disconnect();
      if (ac) {
        ac.close();
        ac = null;
      }
    }
    window.addEventListener("pagehide", teardown);

    function reinit() {
      window.addEventListener("keydown", onKeyDown);
      window.addEventListener("resize", sizeCascadeCanvas);
      if (ro) ro.observe(mount);
      else window.addEventListener("resize", layoutAndPosition);
      if (io) io.observe(mount);
      else {
        fieldVisible = true;
        startLoop();
      }
    }
    window.addEventListener("pageshow", function (e) {
      if (e.persisted) reinit();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
