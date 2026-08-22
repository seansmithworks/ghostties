/*
 * ghostties.org — hero snake game (v2, pass 2)
 *
 * Ported from docs/design/web-redesign/Snake.dc.html. Not classic Snake:
 * the head wraps on every edge (no lose state), loose ghosts drift the
 * field, walking into one joins your tail, and the tail's last ghost
 * periodically strays off and has to be re-collected. Idle mode runs an
 * autopilot demo with nobody touching a key; pressing "I" (or the Insert
 * Coin button) hands control to WASD/arrows.
 *
 * Deliberate deviations from the prototype (see task brief):
 *  - One shared ghost shape + visor face for all eight, site palette
 *    instead of arcade primaries.
 *  - Grid is derived from the mount's measured width and re-derived on
 *    resize, not hardcoded to a 1360px artboard.
 *  - Sound defaults off; AudioContext is built lazily on first real
 *    gesture, never eagerly.
 *  - Real focusable start control + keyboard/motion hygiene throughout.
 */
(function () {
  "use strict";

  var SVG_NS = "http://www.w3.org/2000/svg";

  // Same 4px lattice as the app icons and Ghosts.dc.html. Locked shape:
  // tall dome, four-point skirt, visor face.
  var DOME_TALL = "12,0,24,4 8,4,32,4 4,8,40,4 4,12,40,4 0,16,48,24";
  var SKIRT_FOUR =
    "0,40,8,4 12,40,8,4 28,40,8,4 40,40,8,4 0,44,4,4 16,44,4,4 28,44,4,4 44,44,4,4";
  var SHADE_FOUR = "0,36,48,4 0,40,8,4 12,40,8,4 28,40,8,4 40,40,8,4";
  var HI_TALL = "12,0,12,4 8,4,10,4 4,8,8,4";

  function toPath(s) {
    return s
      .split(" ")
      .filter(Boolean)
      .map(function (t) {
        var a = t.split(",").map(Number);
        return (
          "M" + a[0] + " " + a[1] + "h" + a[2] + "v" + a[3] + "h-" + a[2] + "Z"
        );
      })
      .join("");
  }

  var BODY_PATH = toPath(DOME_TALL + " " + SKIRT_FOUR);
  var SHADE_PATH = toPath(SHADE_FOUR);
  var HI_PATH = toPath(HI_TALL);
  var EYE_LIT = "#f4f7ff";

  // Eight game pieces, one shape, colours pulled from the site's own
  // accent families (amber / cyan / purple) rather than arcade primaries.
  var PALETTE = [
    "#ffd54f", // amber
    "#e8b34a", // amber, deeper
    "#7ce9f7", // cyan, light
    "#00c2d9", // cyan
    "#4dd0e1", // cyan, deep
    "#7c4dff", // purple
    "#b39cff", // purple, light
    "#9575cd", // purple, deep
  ];

  function buildGhostSVG(color) {
    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", "0 0 48 48");
    svg.setAttribute("shape-rendering", "crispEdges");

    var body = document.createElementNS(SVG_NS, "path");
    body.setAttribute("d", BODY_PATH);
    body.setAttribute("fill", color);
    svg.appendChild(body);

    var shade = document.createElementNS(SVG_NS, "path");
    shade.setAttribute("d", SHADE_PATH);
    shade.setAttribute("fill", "rgba(0,0,0,0.24)");
    svg.appendChild(shade);

    var hi = document.createElementNS(SVG_NS, "path");
    hi.setAttribute("d", HI_PATH);
    hi.setAttribute("fill", "rgba(255,255,255,0.2)");
    svg.appendChild(hi);

    var dark = document.createElementNS(SVG_NS, "rect");
    dark.setAttribute("x", "8");
    dark.setAttribute("y", "17");
    dark.setAttribute("width", "32");
    dark.setAttribute("height", "9");
    dark.setAttribute("fill", "rgba(5,5,12,0.72)");
    svg.appendChild(dark);

    var pupil = document.createElementNS(SVG_NS, "rect");
    pupil.setAttribute("class", "pupil");
    pupil.setAttribute("x", "21");
    pupil.setAttribute("y", "19");
    pupil.setAttribute("width", "7");
    pupil.setAttribute("height", "5");
    pupil.setAttribute("fill", EYE_LIT);
    svg.appendChild(pupil);

    var ring = document.createElementNS(SVG_NS, "rect");
    ring.setAttribute("class", "ring");
    ring.setAttribute("x", "1");
    ring.setAttribute("y", "1");
    ring.setAttribute("width", "46");
    ring.setAttribute("height", "46");
    ring.setAttribute("fill", "none");
    ring.setAttribute("stroke", "#ff8a70");
    ring.setAttribute("stroke-width", "2");
    ring.setAttribute("stroke-dasharray", "4 4");
    svg.appendChild(ring);

    return svg;
  }

  function init() {
    var wrap = document.querySelector(".snake-wrap");
    var mount = document.getElementById("snake-mount");
    var startBtn = document.getElementById("snake-start");
    var soundBtn = document.getElementById("snake-sound");
    if (!wrap || !mount || !startBtn || !soundBtn) return;

    var reducedMotion = window.matchMedia
      ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
      : false;

    // --- DOM scaffold ------------------------------------------------------
    mount.innerHTML = "";
    var frameEl = document.createElement("div");
    frameEl.className = "snake-frame";

    var hud = document.createElement("div");
    hud.className = "snake-hud";
    hud.innerHTML =
      '<span class="snake-stat"><span class="k">Herded</span><span class="v" data-herd>0/8</span></span>' +
      '<span class="snake-stat dim"><span class="k">Rescues</span><span class="v" data-res>0</span></span>' +
      '<span class="snake-stat" data-lost-cell><span class="k">Stray</span><span class="v" data-lost>0</span></span>';
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

    mount.appendChild(frameEl);

    var gs = [];
    for (var i = 0; i < 8; i++) {
      var svg = buildGhostSVG(PALETTE[i]);
      var ghEl = document.createElement("div");
      ghEl.className = "gh";
      ghEl.appendChild(svg);
      field.appendChild(ghEl);
      gs.push({
        el: ghEl,
        pupil: svg.querySelector(".pupil"),
        x: 0,
        y: 0,
        ix: 0,
        iy: 0,
        idlePhase: i * 0.79,
        cx: 0,
        cy: 0,
        rank: -1,
        lost: false,
      });
    }

    var herdEl = hud.querySelector("[data-herd]");
    var resEl = hud.querySelector("[data-res]");
    var lostEl = hud.querySelector("[data-lost]");
    var lostCell = hud.querySelector("[data-lost-cell]");

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
      COLS = computeCols(width);
      CELL = width / COLS;
      field.style.height = Math.round(ROWS * CELL) + "px";
      mount.style.setProperty("--cell", CELL + "px");

      // re-seed idle drift centers and home cells against the new field
      var fw = field.clientWidth || width;
      var fh = ROWS * CELL;
      var homeRows = [1, 2, 3, 4, 1, 3, 2, 4];
      for (var j = 0; j < gs.length; j++) {
        var g = gs[j];
        g.ix = fw * ((j + 0.5) / gs.length);
        g.iy = fh * (0.5 + 0.28 * Math.sin(j * 1.7 + 1));
        g.cx = Math.min(
          COLS - 1,
          Math.round(((j + 0.5) / gs.length) * (COLS - 1)),
        );
        g.cy = Math.min(ROWS - 1, homeRows[j] % ROWS);
      }
    }

    function px(c) {
      return c * CELL;
    }
    function py(r) {
      return r * CELL;
    }

    // --- game state ------------------------------------------------------
    var mode = "idle";
    var hx = 1,
      hy = 2,
      dir = [1, 0],
      next = [1, 0];
    var hpx = 0,
      hpy = 0;
    var trail = [[hx, hy]];
    var f = 0,
      t = 0,
      herded = 0,
      rescues = 0,
      strays = 0,
      lastDrop = 0;
    var auto = true;
    var soundOn = false;
    var ac = null;
    // Idle mode autoplays the herd loop (the ambient demo) unless the
    // visitor asked for reduced motion — then nothing moves until they
    // explicitly insert a coin.
    var simActive = !reducedMotion;

    layoutGrid();
    hpx = px(hx);
    hpy = py(hy);
    headEl.style.transform =
      "translate3d(" + hpx.toFixed(1) + "px," + hpy.toFixed(1) + "px,0)";
    for (var gi = 0; gi < gs.length; gi++) {
      gs[gi].x = gs[gi].ix;
      gs[gi].y = gs[gi].iy;
      gs[gi].el.style.transform =
        "translate3d(" +
        gs[gi].x.toFixed(1) +
        "px," +
        gs[gi].y.toFixed(1) +
        "px,0)";
    }

    var ro = window.ResizeObserver
      ? new ResizeObserver(function () {
          layoutGrid();
        })
      : null;
    if (ro) ro.observe(mount);
    else window.addEventListener("resize", layoutGrid);

    // --- sound -------------------------------------------------------------
    // Placeholder synthesised SFX (WebAudio square waves), same shapes as
    // the prototype. Real SFX are parked. AudioContext is only ever built
    // inside this function, which is only ever called from a real user
    // gesture handler (key/click), never eagerly.
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
      } else if (name === "stray") {
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
      } else if (name === "rescue") {
        play(784, 0, 0.06);
        play(1046, 0.06, 0.06);
        play(1568, 0.12, 0.2);
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
      if (tag === "input" || tag === "textarea" || tag === "select")
        return true;
      if (target.isContentEditable) return true;
      return false;
    }

    function startGame() {
      if (mode !== "idle") return;
      mode = "play";
      simActive = true; // reduced-motion users get their first motion here, explicitly
      wrap.classList.add("is-playing");
      startBtn.setAttribute("aria-hidden", "true");
      startBtn.tabIndex = -1;
      startBtn.style.opacity = "0";
      startBtn.style.pointerEvents = "none";
      flashEl.classList.remove("go");
      // force reflow so re-adding the class restarts the animation
      void flashEl.offsetWidth;
      flashEl.classList.add("go");
      sfx("coin");
    }

    startBtn.addEventListener("click", startGame);

    function onKeyDown(e) {
      if (isEditableTarget(e.target)) return;
      var k = e.key ? e.key.toLowerCase() : "";

      if (mode === "idle") {
        if (k !== "i") return; // never hijack scroll/typing before play starts
        e.preventDefault();
        startGame();
        return;
      }

      var d = MAP[k];
      if (!d) return;
      e.preventDefault(); // safe now — only once the game is actually running
      auto = false;
      if (d[0] !== -dir[0] || d[1] !== -dir[1]) next = d;
    }
    window.addEventListener("keydown", onKeyDown);

    // --- simulation ------------------------------------------------------
    function ranked() {
      return gs
        .filter(function (g) {
          return g.rank >= 0;
        })
        .sort(function (a, b) {
          return a.rank - b.rank;
        });
    }

    function think() {
      var targets = [];
      for (var i = 0; i < gs.length; i++)
        if (gs[i].rank < 0) targets.push(gs[i]);
      if (!targets.length) return;
      var best = targets[0],
        bd = Infinity;
      for (var j = 0; j < targets.length; j++) {
        var p = targets[j];
        var d = Math.abs(p.cx - hx) + Math.abs(p.cy - hy);
        if (d < bd) {
          bd = d;
          best = p;
        }
      }
      var dx = best.cx - hx,
        dy = best.cy - hy;
      var want =
        Math.abs(dx) > Math.abs(dy) ? [Math.sign(dx), 0] : [0, Math.sign(dy)];
      if (!want[0] && !want[1]) return;
      if (want[0] === -dir[0] && want[1] === -dir[1]) return;
      next = want;
    }

    function move() {
      dir = next;
      hx = (hx + dir[0] + COLS) % COLS;
      hy = (hy + dir[1] + ROWS) % ROWS;
      trail.unshift([hx, hy]);
      if (trail.length > 80) trail.pop();

      for (var i = 0; i < gs.length; i++) {
        var g = gs[i];
        if (g.rank >= 0) continue;
        if (g.cx === hx && g.cy === hy) {
          g.rank = herded;
          herded++;
          if (g.lost) {
            g.lost = false;
            rescues++;
            strays--;
            g.el.classList.remove("lost");
            sfx("rescue");
          } else {
            sfx("collect");
          }
        }
      }

      var line = ranked();
      for (var k = 0; k < line.length; k++) {
        var s = trail[Math.min(trail.length - 1, line[k].rank + 1)];
        line[k].cx = s[0];
        line[k].cy = s[1];
      }

      var strayEvery = 9;
      if (line.length >= 3 && t - lastDrop > strayEvery) {
        var tail = line[line.length - 1];
        tail.rank = -1;
        tail.lost = true;
        tail.el.classList.add("lost");
        herded--;
        strays++;
        lastDrop = t;
        ranked().forEach(function (g, idx) {
          g.rank = idx;
        });
        sfx("stray");
      }
    }

    // --- render loop -------------------------------------------------------
    var speed = 8.5;
    var raf = null;
    var running = false;

    function frame() {
      t += 1 / 60;

      if (!simActive) {
        // Nothing drifts and nothing auto-herds before an explicit start
        // (only reachable pre-start when reduced motion is requested).
        raf = requestAnimationFrame(frame);
        return;
      }

      // The herd loop runs in both modes — idle autoplays it as the
      // ambient demo; "play" only adds the HUD, keycaps and manual steering.
      var step = Math.max(1, Math.round(60 / speed));
      if (auto && f % step === 0) think();
      if (f % step === 0) move();
      f++;

      var tx = px(hx),
        ty = py(hy);
      if (Math.abs(tx - hpx) > CELL * 1.6) hpx = tx;
      else hpx += (tx - hpx) * 0.4;
      if (Math.abs(ty - hpy) > CELL * 1.6) hpy = ty;
      else hpy += (ty - hpy) * 0.4;
      headEl.style.transform =
        "translate3d(" + hpx.toFixed(1) + "px," + hpy.toFixed(1) + "px,0)";

      for (var i = 0; i < gs.length; i++) {
        var g = gs[i];
        var gx, gy;
        if (g.rank < 0) {
          // loose — floats ambiently until the head walks into it
          gx = g.ix + Math.sin(t * 0.52 + g.idlePhase) * (CELL * 0.35);
          gy = g.iy + Math.cos(t * 0.63 + g.idlePhase) * (CELL * 0.28);
          g.x = gx;
          g.y = gy;
        } else {
          // captured — follows its slot in the tail
          gx = px(g.cx);
          gy = py(g.cy);
          if (Math.abs(gx - g.x) > CELL * 1.6) g.x = gx;
          else g.x += (gx - g.x) * 0.4;
          if (Math.abs(gy - g.y) > CELL * 1.6) g.y = gy;
          else g.y += (gy - g.y) * 0.4;
        }
        g.el.style.transform =
          "translate3d(" + g.x.toFixed(1) + "px," + g.y.toFixed(1) + "px,0)";

        var lx = mode === "play" ? hpx : g.ix + Math.sin(t * 0.3) * (CELL * 2);
        var ly =
          mode === "play" ? hpy : g.iy + Math.cos(t * 0.24) * (CELL * 1.2);
        var ang = Math.atan2(ly - g.y, lx - g.x);
        g.pupil.setAttribute("x", 21 + Math.round((Math.cos(ang) * 5) / 2) * 2);
        g.pupil.setAttribute("y", 19 + Math.round((Math.sin(ang) * 3) / 2) * 2);
      }

      if (mode === "play") {
        herdEl.textContent = herded + "/" + gs.length;
        resEl.textContent = String(rescues);
        lostEl.textContent = String(strays);
        lostCell.classList.toggle("alert", strays > 0);
      }

      raf = requestAnimationFrame(frame);
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

    // Pause entirely when the hero scrolls out of view — this game must
    // not burn a core forever on a page nobody is looking at.
    var io =
      "IntersectionObserver" in window
        ? new IntersectionObserver(
            function (entries) {
              var visible = entries[0] && entries[0].isIntersecting;
              if (visible) startLoop();
              else stopLoop();
            },
            { threshold: 0.01 },
          )
        : null;
    if (io) io.observe(mount);
    else startLoop();

    function teardown() {
      stopLoop();
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("resize", layoutGrid);
      if (ro) ro.disconnect();
      if (io) io.disconnect();
      if (ac) ac.close();
    }
    window.addEventListener("pagehide", teardown);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
