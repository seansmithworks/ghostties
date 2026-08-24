/*
 * Ghostties v3 — ambient ghost field.
 *
 * Ported from the physics prototype (scratchpad/physics/index.html).
 * Required adaptations from that handoff, all applied below:
 *   1. Every selector namespaced `gx-` (bare `.ghost` collides with site markup).
 *   2. `pointer-events: none` on the field by default — pure ambient, never
 *      blocks clicks on page content. Only "coin-in" (see GXField.coinIn)
 *      arms per-ghost pointer-events.
 *   3. Viewport-sized `position: fixed; inset: 0` is correct here (full-bleed
 *      by design). Resize handling is debounced so it doesn't thrash.
 *   4. Mobile budget: ~5 ghosts / ~40 particles via matchMedia, vs. the full
 *      roster/particle count on desktop.
 *
 * Pacing (drift speeds, chase steering, herd force, bob frequency) is carried
 * over unchanged from the tuned prototype — do not speed it up.
 *
 * `prefers-reduced-motion: reduce` renders the ghosts static: no RAF loop, no
 * drift, no particles, no drag/chase/hover interactivity.
 */
(function () {
  "use strict";

  var FIELD_ID = "gx-field";
  var reduceMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;
  var isMobile = window.matchMedia("(max-width: 640px)").matches;

  // ── Ghost data (real Ghostties characters, 12×12 grids) ──────────────────
  var GHOSTS_DATA = [
    {
      name: "blinky",
      role: "Orchestrator",
      boss: true,
      color: "#ff3b3b",
      rgb: "255,59,59",
      glow: "rgba(255,59,59,0.9)",
      persp: 120,
      rx: -18,
      ry: 26,
      eyeRows: [3, 4],
      pixels: [
        "...XXXXXX...",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        ".XX..XX..XX.",
        ".XX..XX..XX.",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XX.XX..XX.XX",
        "X...X..X...X",
      ],
      tier: "S",
      overall: 91,
      spd: 88,
      cra: 91,
      wit: 95,
      hrt: 90,
    },
    {
      name: "pinky",
      role: "Design",
      color: "#ff8ec8",
      rgb: "255,142,200",
      glow: "rgba(255,142,200,0.8)",
      persp: 160,
      rx: -9,
      ry: -22,
      eyeRows: [3, 4],
      pixels: [
        "....XXXX....",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        ".X..XXXX..X.",
        ".X..XXXX..X.",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXX..XX..XXX",
        "X..........X",
      ],
      tier: "A",
      overall: 88,
      spd: 82,
      cra: 96,
      wit: 89,
      hrt: 87,
    },
    {
      name: "inky",
      role: "Engineering",
      color: "#3ee8ff",
      rgb: "62,232,255",
      glow: "rgba(62,232,255,0.8)",
      persp: 110,
      rx: -20,
      ry: 30,
      eyeRows: [3, 4],
      pixels: [
        "...XXXXXX...",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        ".XXX....XXX.",
        ".XXX....XXX.",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "X.XX.XX.XX.X",
        "X..X....X..X",
      ],
      tier: "A",
      overall: 89,
      spd: 87,
      cra: 93,
      wit: 92,
      hrt: 84,
    },
    {
      name: "clyde",
      role: "Data",
      color: "#ff9f3b",
      rgb: "255,159,59",
      glow: "rgba(255,159,59,0.8)",
      persp: 145,
      rx: -12,
      ry: -20,
      eyeRows: [3, 4],
      pixels: [
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        "XXXXXXXXXXXX",
        "XX..XXXX..XX",
        "XX..XXXX..XX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXX.XXXX.XXX",
        "X....XX....X",
      ],
      tier: "A",
      overall: 87,
      spd: 79,
      cra: 88,
      wit: 94,
      hrt: 86,
    },
    {
      name: "specter",
      role: "Security",
      color: "#c34bff",
      rgb: "195,75,255",
      glow: "rgba(195,75,255,0.8)",
      persp: 130,
      rx: -16,
      ry: 22,
      eyeRows: [3, 4],
      pixels: [
        "...XXXXXX...",
        ".XXXXXXXXXX.",
        "XXXXXXXXXXXX",
        "XX..XXXX..XX",
        "X...XXXX...X",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XX..XXXX..XX",
        "X....XX....X",
      ],
      tier: "S",
      overall: 90,
      spd: 90,
      cra: 92,
      wit: 89,
      hrt: 91,
    },
    {
      name: "wisp",
      role: "Content",
      color: "#c8ff3b",
      rgb: "200,255,59",
      glow: "rgba(200,255,59,0.7)",
      persp: 170,
      rx: -8,
      ry: -28,
      eyeRows: [3, 4],
      pixels: [
        "....XXXX....",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        "XXX..XX..XXX",
        "XXX..XX..XXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        ".XXXXXXXXXX.",
        ".XXXXXXXXXX.",
        "..XX.XX.XX..",
        "...X....X...",
      ],
      tier: "A",
      overall: 88,
      spd: 85,
      cra: 93,
      wit: 87,
      hrt: 89,
    },
    {
      name: "phantom",
      role: "Research",
      color: "#6b4bff",
      rgb: "107,75,255",
      glow: "rgba(107,75,255,0.85)",
      persp: 115,
      rx: -22,
      ry: 18,
      eyeRows: [3, 4],
      pixels: [
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        "XXXXXXXXXXXX",
        "XXX..X..XXXX",
        "XXX..X..XXXX",
        "XXXXXXXXXXXX",
        "XXXX....XXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "X.XXX..XXX.X",
        "X..X....X..X",
      ],
      tier: "A",
      overall: 87,
      spd: 76,
      cra: 89,
      wit: 96,
      hrt: 85,
    },
    {
      name: "ember",
      role: "Growth",
      color: "#ff6b3b",
      rgb: "255,107,59",
      glow: "rgba(255,107,59,0.8)",
      persp: 150,
      rx: -10,
      ry: -24,
      eyeRows: [3, 4],
      pixels: [
        "....XXXX....",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        ".XX..XX..XX.",
        ".XX..XX..XX.",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        ".XXXXXXXXXX.",
        ".XX.XXXX.XX.",
        "..X..XX..X..",
        ".....XX.....",
      ],
      tier: "A",
      overall: 88,
      spd: 92,
      cra: 84,
      wit: 86,
      hrt: 91,
    },
    {
      name: "chill",
      role: "Support",
      color: "#3bffe8",
      rgb: "59,255,232",
      glow: "rgba(59,255,232,0.75)",
      persp: 140,
      rx: -14,
      ry: 26,
      eyeRows: [4, 5],
      pixels: [
        "....XXXX....",
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        "XXXXXXXXXXXX",
        "XXX..XX..XXX",
        "XXX..XX..XXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        "XXXXXXXXXXXX",
        ".XXXXXXXXXX.",
        "..XXXXXXXX..",
        "....XXXX....",
      ],
      tier: "B",
      overall: 86,
      spd: 80,
      cra: 87,
      wit: 85,
      hrt: 95,
    },
  ];

  // Mobile budget: 5 ghosts instead of the full roster.
  var ROSTER = isMobile ? GHOSTS_DATA.slice(0, 5) : GHOSTS_DATA;
  var PARTICLE_COUNT = isMobile ? 40 : 110;

  var PX = 5;
  var _uid = 0;

  // ── Coin (single physical object, drifts with the field, grabbable
  //    before arming) ──────────────────────────────────────────────────
  var COIN_PX = 5;
  // 16x16 right-facing pixel bust (Sean's likeness, low-fi). Three glyphs:
  // "o" coin face (gold), "#" relief/shading (a shade darker, reads as
  // depth against the gold), "+" the single lens glint. COIN_PX 5 renders
  // the 16x16 grid at 80px — see docs/design/web-redesign/coin-plate/Quarter.dc.html.
  var COIN_GRID = [
    "......oooo......",
    "....oooooooo....",
    "...oooooooooo...",
    "..oooo######oo..",
    ".oooo#######ooo.",
    ".ooo#########oo.",
    "ooo#########+ooo",
    "ooo########ooooo",
    "ooo########ooooo",
    "ooo##########ooo",
    ".ooo#########oo.",
    ".ooo######ooooo.",
    "..oo######oooo..",
    "...oo#######o...",
    "....o#######....",
    "......oooo......",
  ];
  var COIN_FACE_FILL = "#e8b545";
  var COIN_RELIEF_FILL = "#c9932e";
  var COIN_GLINT_FILL = "#fff6d8";

  function buildCoinSVG() {
    var rows = COIN_GRID.length,
      cols = COIN_GRID[0].length;
    var W = cols * COIN_PX,
      H = rows * COIN_PX;
    var gid = "gxc" + _uid++;
    var face = "",
      relief = "",
      glint = "",
      shine = "";
    COIN_GRID.forEach(function (row, r) {
      row.split("").forEach(function (cell, c) {
        if (cell === ".") return;
        var x = c * COIN_PX,
          y = r * COIN_PX;
        var rect =
          '<rect x="' +
          x +
          '" y="' +
          y +
          '" width="' +
          COIN_PX +
          '" height="' +
          COIN_PX +
          '"/>';
        if (cell === "o") face += rect;
        else if (cell === "#") relief += rect;
        else if (cell === "+") glint += rect;
        // Lens shine only over the top rows, and only on face pixels — the
        // grid keeps rows 0-2 as plain rim ("o" only), so this never lands
        // on the relief shading or the glint pixel.
        if (r < 3 && cell === "o") shine += rect;
      });
    });
    return (
      '<svg xmlns="http://www.w3.org/2000/svg" width="' +
      W +
      '" height="' +
      H +
      '" viewBox="0 0 ' +
      W +
      " " +
      H +
      '" style="image-rendering:pixelated;display:block;overflow:visible">' +
      '<defs><linearGradient id="' +
      gid +
      '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0%" stop-color="#fff6d8" stop-opacity="0.85"/>' +
      '<stop offset="55%" stop-color="#fff6d8" stop-opacity="0.1"/>' +
      '<stop offset="100%" stop-color="#fff6d8" stop-opacity="0"/>' +
      "</linearGradient></defs>" +
      '<g fill="' +
      COIN_FACE_FILL +
      '">' +
      face +
      "</g>" +
      '<g fill="' +
      COIN_RELIEF_FILL +
      '">' +
      relief +
      "</g>" +
      '<g fill="' +
      COIN_GLINT_FILL +
      '">' +
      glint +
      "</g>" +
      '<g fill="url(#' +
      gid +
      ')">' +
      shine +
      "</g>" +
      "</svg>"
    );
  }

  function buildSVG(ghost) {
    var pixels = ghost.pixels,
      eyeRows = ghost.eyeRows || [],
      color = ghost.color;
    var rows = pixels.length,
      cols = pixels[0].length;
    var W = cols * PX,
      H = rows * PX;
    var gid = "gxg" + _uid++;
    var glassRows = Math.ceil(rows * 0.42);
    var LEG_ROW = rows - 2;

    var body = "",
      glass = "",
      blink = "",
      tailRects = "";

    pixels.forEach(function (row, r) {
      if (r >= LEG_ROW) {
        for (var c = 0; c < cols; c++) {
          var isOn = row[c] === "X";
          tailRects +=
            '<rect x="' +
            c * PX +
            '" y="' +
            r * PX +
            '" width="' +
            PX +
            '" height="' +
            PX +
            '" fill="' +
            color +
            '" opacity="' +
            (isOn ? 1 : 0) +
            '" data-gx-tc="' +
            (isOn ? 1 : 0) +
            "," +
            c +
            "," +
            r +
            '"/>';
        }
      } else {
        row.split("").forEach(function (cell, c) {
          var x = c * PX,
            y = r * PX;
          if (cell === "X") {
            body +=
              '<rect x="' +
              x +
              '" y="' +
              y +
              '" width="' +
              PX +
              '" height="' +
              PX +
              '"/>';
            if (r < glassRows)
              glass +=
                '<rect x="' +
                x +
                '" y="' +
                y +
                '" width="' +
                PX +
                '" height="' +
                PX +
                '"/>';
          } else if (eyeRows.indexOf(r) !== -1) {
            blink +=
              '<rect x="' +
              x +
              '" y="' +
              y +
              '" width="' +
              PX +
              '" height="' +
              PX +
              '"/>';
          }
        });
      }
    });

    return (
      '<svg xmlns="http://www.w3.org/2000/svg" width="' +
      W +
      '" height="' +
      H +
      '" viewBox="0 0 ' +
      W +
      " " +
      H +
      '" style="overflow:visible">' +
      '<defs><linearGradient id="' +
      gid +
      '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0%" stop-color="white" stop-opacity="0.68"/>' +
      '<stop offset="65%" stop-color="white" stop-opacity="0.05"/>' +
      '<stop offset="100%" stop-color="white" stop-opacity="0"/>' +
      "</linearGradient></defs>" +
      '<g fill="' +
      color +
      '">' +
      body +
      "</g>" +
      '<g class="gx-blink-cover" fill="' +
      color +
      '">' +
      blink +
      "</g>" +
      "<g>" +
      tailRects +
      "</g>" +
      '<g class="gx-glass" fill="url(#' +
      gid +
      ')">' +
      glass +
      "</g>" +
      "</svg>"
    );
  }

  function buildPortraitSVG(ghost, px) {
    px = px || 9;
    var pixels = ghost.pixels,
      color = ghost.color;
    var rows = pixels.length,
      cols = pixels[0].length;
    var W = cols * px,
      H = rows * px;
    var gid = "gxp" + _uid++;
    var glassRows = Math.ceil(rows * 0.42);
    var body = "",
      glass = "";
    pixels.forEach(function (row, r) {
      row.split("").forEach(function (cell, c) {
        if (cell !== "X") return;
        var x = c * px,
          y = r * px;
        body +=
          '<rect x="' +
          x +
          '" y="' +
          y +
          '" width="' +
          px +
          '" height="' +
          px +
          '"/>';
        if (r < glassRows)
          glass +=
            '<rect x="' +
            x +
            '" y="' +
            y +
            '" width="' +
            px +
            '" height="' +
            px +
            '"/>';
      });
    });
    return (
      '<svg xmlns="http://www.w3.org/2000/svg" width="' +
      W +
      '" height="' +
      H +
      '" viewBox="0 0 ' +
      W +
      " " +
      H +
      '" style="image-rendering:pixelated;display:block">' +
      '<defs><linearGradient id="' +
      gid +
      '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0%" stop-color="white" stop-opacity="0.55"/>' +
      '<stop offset="65%" stop-color="white" stop-opacity="0.04"/>' +
      '<stop offset="100%" stop-color="white" stop-opacity="0"/>' +
      "</linearGradient></defs>" +
      '<g fill="' +
      color +
      '">' +
      body +
      "</g>" +
      '<g fill="url(#' +
      gid +
      ')" opacity="0.85">' +
      glass +
      "</g>" +
      "</svg>"
    );
  }

  function init() {
    var field = document.getElementById(FIELD_ID);
    if (!field) return;

    var armed = false;

    if (reduceMotion) {
      // Static, no drift, no interactivity — placed once and left alone.
      var VWs = window.innerWidth,
        VHs = window.innerHeight;
      ROSTER.forEach(function (cfg) {
        var W = 12 * PX,
          H = 12 * PX;
        var el = document.createElement("div");
        el.className = "gx-ghost" + (cfg.boss ? " gx-boss" : "");
        el.style.setProperty("--glow", cfg.glow);
        el.innerHTML = buildSVG(cfg);
        var x = 60 + Math.random() * Math.max(1, VWs - W - 120);
        var y = 60 + Math.random() * Math.max(1, VHs - H - 120);
        el.style.transform = "translate(" + x + "px," + y + "px)";
        field.appendChild(el);
      });
      window.GXField = {
        coinIn: function () {},
        coinOut: function () {},
        toggleCoin: function () {},
        isArmed: function () {
          return false;
        },
      };
      return;
    }

    var canvas = document.createElement("canvas");
    canvas.className = "gx-fx";
    field.appendChild(canvas);
    var ctx = canvas.getContext("2d");
    var FXW, FXH;
    function resizeCanvas() {
      FXW = canvas.width = window.innerWidth;
      FXH = canvas.height = window.innerHeight;
    }
    resizeCanvas();

    var VW = window.innerWidth,
      VH = window.innerHeight;

    // Debounced resize — required adaptation #3.
    var resizeTimer = null;
    window.addEventListener("resize", function () {
      if (resizeTimer) clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        VW = window.innerWidth;
        VH = window.innerHeight;
        resizeCanvas();
      }, 150);
    });

    var mX = -9999,
      mY = -9999;
    document.addEventListener("mousemove", function (e) {
      mX = e.clientX;
      mY = e.clientY;
    });

    var AMBIENT = [];
    for (var i = 0; i < PARTICLE_COUNT; i++) {
      AMBIENT.push({
        x: Math.random() * VW,
        y: Math.random() * VH,
        vx: (Math.random() - 0.5) * 0.22,
        vy: (Math.random() - 0.5) * 0.22,
        r: 0.7 + Math.random() * 1.3,
        a: 0.07 + Math.random() * 0.2,
      });
    }

    var BURSTS = [],
      RIPPLES = [];

    function emitBurst(x, y, rgb, count, speed) {
      speed = speed || 3;
      for (var i = 0; i < count; i++) {
        var ang = Math.random() * Math.PI * 2,
          s = 0.5 + Math.random() * speed;
        BURSTS.push({
          x: x,
          y: y,
          vx: Math.cos(ang) * s,
          vy: Math.sin(ang) * s,
          r: 0.8 + Math.random() * 2,
          a: 0.75 + Math.random() * 0.25,
          rgb: rgb,
          life: 1,
        });
      }
    }

    function emitRipple(x, y) {
      RIPPLES.push({ x: x, y: y, r: 0, a: 0.5 });
      emitBurst(x, y, "255,255,255", 22, 2.8);
    }

    function emitTrail(x, y, rgb) {
      BURSTS.push({
        x: x + (Math.random() - 0.5) * 5,
        y: y + (Math.random() - 0.5) * 5,
        vx: (Math.random() - 0.5) * 0.4,
        vy: (Math.random() - 0.5) * 0.4,
        r: 1 + Math.random(),
        a: 0.5,
        rgb: rgb,
        life: 0.85,
      });
    }

    function updateParticles() {
      AMBIENT.forEach(function (p) {
        var dx = p.x - mX,
          dy = p.y - mY,
          d2 = dx * dx + dy * dy;
        if (d2 < 7000) {
          var d = Math.sqrt(d2),
            f = ((7000 - d2) / 7000) * 0.45;
          p.vx += (dx / d) * f;
          p.vy += (dy / d) * f;
        }
        p.vx *= 0.965;
        p.vy *= 0.965;
        if (p.vx * p.vx + p.vy * p.vy > 4.84) {
          p.vx *= 0.88;
          p.vy *= 0.88;
        }
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0) p.x += FXW;
        if (p.x > FXW) p.x -= FXW;
        if (p.y < 0) p.y += FXH;
        if (p.y > FXH) p.y -= FXH;
      });
      for (var i = BURSTS.length - 1; i >= 0; i--) {
        var p = BURSTS[i];
        p.x += p.vx;
        p.y += p.vy;
        p.vx *= 0.93;
        p.vy *= 0.93;
        p.life -= 0.023;
        if (p.life <= 0) {
          BURSTS.splice(i, 1);
          continue;
        }
        p.a = p.life * 0.85;
      }
      for (var j = RIPPLES.length - 1; j >= 0; j--) {
        RIPPLES[j].r += 2.8;
        RIPPLES[j].a -= 0.014;
        if (RIPPLES[j].a <= 0) RIPPLES.splice(j, 1);
      }
    }

    function drawParticles() {
      ctx.clearRect(0, 0, FXW, FXH);
      AMBIENT.forEach(function (p) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(255,255,255," + p.a.toFixed(2) + ")";
        ctx.fill();
      });
      BURSTS.forEach(function (p) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(" + p.rgb + "," + p.a.toFixed(2) + ")";
        ctx.fill();
      });
      RIPPLES.forEach(function (r) {
        ctx.beginPath();
        ctx.arc(r.x, r.y, r.r, 0, Math.PI * 2);
        ctx.strokeStyle = "rgba(255,255,255," + r.a.toFixed(2) + ")";
        ctx.lineWidth = 1;
        ctx.stroke();
      });
    }

    // Ripple on empty-field click — only while armed (coin-in).
    document.addEventListener("click", function (e) {
      if (!armed) return;
      if (e.target.closest(".gx-ghost")) return;
      emitRipple(e.clientX, e.clientY);
    });

    var ghosts = ROSTER.map(function (cfg) {
      var W = 12 * PX,
        H = 12 * PX;
      var el = document.createElement("div");
      el.className = "gx-ghost" + (cfg.boss ? " gx-boss" : "");
      el.style.setProperty("--glow", cfg.glow);
      el.style.setProperty("--persp", cfg.persp + "px");
      el.style.setProperty("--rx", cfg.rx + "deg");
      el.style.setProperty("--ry", cfg.ry + "deg");
      el.innerHTML =
        buildSVG(cfg) +
        '<div class="gx-label">' +
        '<div class="gx-label-top">' +
        '<div class="gx-label-rating">' +
        '<span class="gx-rating-num">' +
        cfg.overall +
        "</span>" +
        '<span class="gx-rating-tier">' +
        cfg.tier +
        "</span>" +
        "</div>" +
        '<div class="gx-label-id">' +
        '<span class="gx-name">' +
        cfg.name +
        "</span>" +
        '<span class="gx-role">' +
        cfg.role +
        "</span>" +
        "</div>" +
        "</div>" +
        '<div class="gx-portrait">' +
        buildPortraitSVG(cfg) +
        "</div>" +
        '<div class="gx-stats">' +
        '<div class="gx-stat"><span class="gx-stat-val">' +
        cfg.spd +
        '</span><span class="gx-stat-key">SPD</span></div>' +
        '<div class="gx-stat"><span class="gx-stat-val">' +
        cfg.cra +
        '</span><span class="gx-stat-key">CRA</span></div>' +
        '<div class="gx-stat"><span class="gx-stat-val">' +
        cfg.wit +
        '</span><span class="gx-stat-key">WIT</span></div>' +
        '<div class="gx-stat"><span class="gx-stat-val">' +
        cfg.hrt +
        '</span><span class="gx-stat-key">HRT</span></div>' +
        "</div>" +
        "</div>";
      field.appendChild(el);

      var tailCells = Array.prototype.map.call(
        el.querySelectorAll("[data-gx-tc]"),
        function (rect) {
          var parts = rect.getAttribute("data-gx-tc").split(",").map(Number);
          return { el: rect, baseOn: !!parts[0], col: parts[1], row: parts[2] };
        },
      );

      var speed = cfg.boss
        ? 0.12 + Math.random() * 0.18
        : 0.22 + Math.random() * 0.4;
      var angle = Math.random() * Math.PI * 2;

      return {
        cfg: cfg,
        el: el,
        tailCells: tailCells,
        w: W,
        h: H,
        r: Math.min(W, H) * 0.45,
        x: 100 + Math.random() * Math.max(1, VW - W - 200),
        y: 100 + Math.random() * Math.max(1, VH - H - 200),
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        bobPhase: Math.random() * Math.PI * 2,
        t: 0,
        bumping: false,
        isBlinking: false,
        blinkTimer: 1200 + Math.random() * 4000,
        chasing: null,
        chaseTimer: 0,
        tiltVX: 0,
        tiltVY: 0,
      };
    });

    // ── Coin token — one physical object, drifts under the ghosts' own
    // pacing (< 0.6px/frame), stays grabbable (pointer-events: auto) the
    // whole time, including before coin-in, unlike every ghost. Dragging
    // it onto the plate's slot is what arms the field; released elsewhere
    // it keeps drifting with the drop velocity, same throw feel as ghosts.
    //
    // Appended to <body>, not `field`: #gx-field is a low-z-index (0)
    // stacking context so page content (z-index 1+) always paints over
    // everything inside it, which is correct for ghosts (ambient
    // background) but would leave the coin permanently ungrabbable
    // wherever it drifts under a heading, button, or the product frame.
    // The coin needs its own stacking context above page content to stay
    // reachable everywhere, per spec.
    var COIN_W = COIN_GRID[0].length * COIN_PX;
    var COIN_H = COIN_GRID.length * COIN_PX;
    var coinEl = document.createElement("div");
    coinEl.className = "gx-coin-token";
    coinEl.setAttribute("aria-hidden", "true");
    coinEl.innerHTML = buildCoinSVG();
    document.body.appendChild(coinEl);

    var coin = {
      el: coinEl,
      w: COIN_W,
      h: COIN_H,
      x: 100 + Math.random() * Math.max(1, VW - COIN_W - 200),
      y: 100 + Math.random() * Math.max(1, VH - COIN_H - 200),
      vx: (Math.random() - 0.5) * 0.5,
      vy: (Math.random() - 0.5) * 0.5,
      bobPhase: Math.random() * Math.PI * 2,
      t: 0,
      state: "drifting", // drifting | dragging | inserting | inSlot | ejecting
      animTimer: null,
    };

    function slotTargetPoint() {
      var slotEl = document.querySelector(".gx-coin-slot");
      var plateEl = document.getElementById("gx-coin-btn");
      var r =
        (slotEl || plateEl) && (slotEl || plateEl).getBoundingClientRect();
      if (!r) return { x: VW - 60, y: 20 };
      return {
        x: r.left + r.width / 2 - coin.w / 2,
        y: r.top + r.height / 2 - coin.h / 2,
      };
    }

    // How much the token grows as it arrives at the slot — a coin being
    // picked up and dropped in, not shrunk away. Scale is computed per
    // insert/eject against the slot's actual rendered size (it can change
    // with viewport width), clamped so a narrow/tall slot rect can't
    // produce an absurd scale.
    var COIN_FILL_SCALE_MIN = 1.5;
    var COIN_FILL_SCALE_MAX = 3;
    function coinFillScale() {
      var slotEl = document.querySelector(".gx-coin-slot");
      if (!slotEl) return COIN_FILL_SCALE_MIN;
      var r = slotEl.getBoundingClientRect();
      if (!r.width || !r.height) return COIN_FILL_SCALE_MIN;
      var scale = Math.min(r.width / coin.w, r.height / coin.h);
      return Math.max(
        COIN_FILL_SCALE_MIN,
        Math.min(COIN_FILL_SCALE_MAX, scale),
      );
    }

    function coinInsert() {
      if (coin.state === "inserting" || coin.state === "inSlot") return;
      coin.state = "inserting";
      coin.el.classList.remove("gx-coin-dragging");
      var target = slotTargetPoint();
      var fillScale = coinFillScale();
      if (coin.animTimer) clearTimeout(coin.animTimer);
      // Grow into the slot first (coin arriving, picked up and brought
      // closer), then fade only right at the end so the handoff to the
      // plate's own internal .gx-coin-piece fall animation reads as one
      // continuous move instead of two disconnected events.
      coin.el.style.transition = "transform 220ms cubic-bezier(.25,1,.5,1)";
      coin.el.style.transform =
        "translate(" +
        target.x +
        "px," +
        target.y +
        "px) scale(" +
        fillScale +
        ")";
      coin.animTimer = setTimeout(function () {
        coin.el.style.transition = "opacity 90ms linear";
        coin.el.style.opacity = "0";
        coin.animTimer = setTimeout(function () {
          coin.el.style.display = "none";
          coin.el.style.transition = "";
          coin.el.style.opacity = "1";
          coin.state = "inSlot";
        }, 90);
      }, 220);
    }

    function coinEject() {
      if (coin.state === "ejecting" || coin.state === "drifting") return;
      var target = slotTargetPoint();
      var fillScale = coinFillScale();
      coin.x = target.x;
      coin.y = target.y;
      coin.state = "ejecting";
      if (coin.animTimer) clearTimeout(coin.animTimer);
      coin.el.style.transition = "none";
      coin.el.style.display = "";
      coin.el.style.transform =
        "translate(" +
        target.x +
        "px," +
        target.y +
        "px) scale(" +
        fillScale +
        ")";
      coin.el.style.opacity = "0";
      // Force reflow so the animate-in transition below actually starts
      // from the state just set, instead of the browser coalescing it.
      void coin.el.offsetWidth;
      coin.animTimer = setTimeout(function () {
        coin.el.style.transition =
          "transform 260ms cubic-bezier(.25,1,.5,1), opacity 260ms cubic-bezier(.25,1,.5,1)";
        coin.el.style.transform =
          "translate(" + target.x + "px," + target.y + "px) scale(1)";
        coin.el.style.opacity = "1";
        coin.animTimer = setTimeout(function () {
          coin.el.style.transition = "";
          coin.state = "drifting";
          var ang = Math.random() * Math.PI * 2;
          coin.vx = Math.cos(ang) * 0.4;
          coin.vy = Math.sin(ang) * 0.4 - 0.3;
        }, 260);
      }, 16);
    }

    var coinDrag = {
      active: false,
      offX: 0,
      offY: 0,
      lastX: 0,
      lastY: 0,
      vx: 0,
      vy: 0,
    };

    function coinSlotHitTest(clientX, clientY) {
      var slotEl = document.querySelector(".gx-coin-slot");
      var plateEl = document.getElementById("gx-coin-btn");
      var target = plateEl || slotEl;
      if (!target) return false;
      var r = target.getBoundingClientRect();
      var pad = 40;
      return (
        clientX >= r.left - pad &&
        clientX <= r.right + pad &&
        clientY >= r.top - pad &&
        clientY <= r.bottom + pad
      );
    }

    // A drifting coin can park directly over the install buttons (the
    // full-bleed field has no reserved gutter). Deciding whether the coin
    // or the control beneath it should get the click can only be done
    // *before* a gesture starts — by the time a pointerdown fires the
    // browser has already resolved its hit-test target, so flipping
    // pointer-events mid-gesture just breaks both the coin and the
    // control's click event (it fires on their nearest common ancestor
    // instead of either one). Instead, keep the coin's own
    // pointer-events continuously correct for wherever it currently is:
    // every frame (see updateCoinHitTest(), called from tick()), test the
    // coin's box against a cache of the page's real interactive controls'
    // rects and set pointer-events: none when it overlaps one, "" (auto,
    // the CSS default) otherwise. The cache is rebuilt on resize/scroll
    // since those controls live in normal flow, not fixed position.
    var CONTROL_SELECTOR =
      ".install-row a, .install-row button, #still-ghostty a, " +
      ".install-grid a, .footer-links a, .footer-icons a";
    var controlRects = [];
    function refreshControlRects() {
      controlRects = Array.prototype.map.call(
        document.querySelectorAll(CONTROL_SELECTOR),
        function (el) {
          return el.getBoundingClientRect();
        },
      );
    }
    refreshControlRects();
    window.addEventListener("resize", refreshControlRects);
    window.addEventListener("scroll", refreshControlRects, { passive: true });

    var coinYielding = false;
    function updateCoinHitTest() {
      var cx1 = coin.x,
        cy1 = coin.y,
        cx2 = coin.x + coin.w,
        cy2 = coin.y + coin.h;
      var overlap = false;
      for (var i = 0; i < controlRects.length; i++) {
        var r = controlRects[i];
        if (cx1 < r.right && cx2 > r.left && cy1 < r.bottom && cy2 > r.top) {
          overlap = true;
          break;
        }
      }
      if (overlap !== coinYielding) {
        coinYielding = overlap;
        coinEl.style.pointerEvents = overlap ? "none" : "";
      }
    }

    coinEl.addEventListener("pointerdown", function (e) {
      if (coin.state !== "drifting") return;
      if (coinYielding) return;
      coin.state = "dragging";
      coinDrag.active = true;
      coinDrag.offX = coin.x - e.clientX;
      coinDrag.offY = coin.y - e.clientY;
      coinDrag.lastX = e.clientX;
      coinDrag.lastY = e.clientY;
      coinDrag.vx = coinDrag.vy = 0;
      coinEl.classList.add("gx-coin-dragging");
      try {
        coinEl.setPointerCapture(e.pointerId);
      } catch (err) {}
      e.preventDefault();
    });

    coinEl.addEventListener("pointermove", function (e) {
      if (!coinDrag.active) return;
      coinDrag.vx = e.clientX - coinDrag.lastX;
      coinDrag.vy = e.clientY - coinDrag.lastY;
      coinDrag.lastX = e.clientX;
      coinDrag.lastY = e.clientY;
      coin.x = e.clientX + coinDrag.offX;
      coin.y = e.clientY + coinDrag.offY;
    });

    function coinDragEnd(e) {
      if (!coinDrag.active) return;
      coinDrag.active = false;
      coinEl.classList.remove("gx-coin-dragging");
      try {
        coinEl.releasePointerCapture(e.pointerId);
      } catch (err) {}
      // A "c" press or plate click mid-drag can already have moved the
      // coin to "inserting"/"inSlot" (armed) via coinIn() by the time this
      // release fires. Only a drag still in progress gets to decide the
      // coin's post-release state here — otherwise this stomps the armed
      // state and coinEject() (which bails out on "drifting") can never
      // bring the coin back.
      if (coin.state !== "dragging") return;
      if (coinSlotHitTest(e.clientX, e.clientY)) {
        coinIn();
        return;
      }
      coin.vx = coinDrag.vx * 0.35;
      coin.vy = coinDrag.vy * 0.35;
      var spd = Math.hypot(coin.vx, coin.vy);
      if (spd > 3) {
        coin.vx = (coin.vx / spd) * 3;
        coin.vy = (coin.vy / spd) * 3;
      }
      coin.state = "drifting";
    }

    coinEl.addEventListener("pointerup", coinDragEnd);
    coinEl.addEventListener("pointercancel", function (e) {
      if (!coinDrag.active) return;
      coinDrag.active = false;
      coinEl.classList.remove("gx-coin-dragging");
      if (coin.state !== "dragging") return;
      coin.state = "drifting";
    });

    var dragging = null,
      dOffX = 0,
      dOffY = 0;
    var lastMX = 0,
      lastMY = 0,
      throwVX = 0,
      throwVY = 0;
    var mdX = 0,
      mdY = 0,
      mdT = 0;

    ghosts.forEach(function (g) {
      g.el.addEventListener("mousedown", function (e) {
        if (!armed) return;
        dragging = g;
        dOffX = g.x - e.clientX;
        dOffY = g.y - e.clientY;
        lastMX = mdX = e.clientX;
        lastMY = mdY = e.clientY;
        mdT = e.timeStamp;
        throwVX = throwVY = 0;
        g.el.classList.add("gx-dragging");
        e.preventDefault();
      });

      var svgEl = g.el.querySelector("svg");
      g.el.addEventListener("mousemove", function (e) {
        if (!armed || g === dragging) return;
        var rect = g.el.getBoundingClientRect();
        var dx = (e.clientX - (rect.left + rect.width / 2)) / (rect.width / 2);
        var dy = (e.clientY - (rect.top + rect.height / 2)) / (rect.height / 2);
        var rx = (-dy * 28).toFixed(1);
        var ry = (dx * 32).toFixed(1);
        svgEl.style.transition = "transform 0.08s ease, filter 0.45s ease";
        svgEl.style.imageRendering = "auto";
        svgEl.style.transform =
          "perspective(" +
          g.cfg.persp +
          "px) rotateX(" +
          rx +
          "deg) rotateY(" +
          ry +
          "deg) scale(1.8) translateZ(14px)";
      });

      g.el.addEventListener("mouseleave", function () {
        svgEl.style.transition = "";
        svgEl.style.transform = "";
        svgEl.style.imageRendering = "";
      });
    });

    document.addEventListener("mousemove", function (e) {
      throwVX = e.clientX - lastMX;
      throwVY = e.clientY - lastMY;
      lastMX = e.clientX;
      lastMY = e.clientY;
      if (dragging && armed) {
        dragging.x = e.clientX + dOffX;
        dragging.y = e.clientY + dOffY;
        var dragSvg = dragging.el.querySelector("svg");
        dragging.tiltVX = dragging.tiltVX * 0.55 + throwVX * 0.45;
        dragging.tiltVY = dragging.tiltVY * 0.55 + throwVY * 0.45;
        var rx = Math.max(-30, Math.min(30, -dragging.tiltVY * 1.8));
        var ry = Math.max(-35, Math.min(35, dragging.tiltVX * 1.8));
        var rz = Math.max(-15, Math.min(15, dragging.tiltVX * 0.6));
        dragSvg.style.transition = "transform 0.08s ease-out, filter 0.2s ease";
        dragSvg.style.transform =
          "perspective(180px) rotateX(" +
          rx.toFixed(1) +
          "deg) rotateY(" +
          ry.toFixed(1) +
          "deg) rotateZ(" +
          rz.toFixed(1) +
          "deg) scale(1.35) translateZ(10px)";
      }
    });

    document.addEventListener("mouseup", function (e) {
      if (!dragging) return;
      var dx = e.clientX - mdX,
        dy = e.clientY - mdY;
      if (Math.hypot(dx, dy) < 8 && e.timeStamp - mdT < 280) {
        triggerHighFive(dragging);
        dragging.vx *= 0.3;
        dragging.vy *= 0.3;
      } else {
        dragging.vx = throwVX * 0.9;
        dragging.vy = throwVY * 0.9;
      }
      var dragSvg = dragging.el.querySelector("svg");
      dragSvg.style.transition = "";
      dragSvg.style.transform = "";
      dragging.tiltVX = 0;
      dragging.tiltVY = 0;
      dragging.el.classList.remove("gx-dragging");
      dragging = null;
    });

    function triggerBlink(g) {
      var el = g.el.querySelector(".gx-blink-cover");
      if (!el || g.isBlinking) return;
      g.isBlinking = true;
      el.style.opacity = "1";
      setTimeout(function () {
        el.style.opacity = "0";
        g.isBlinking = false;
      }, 95);
    }

    function triggerHighFive(g) {
      g.vy = -5.5 - Math.random() * 2;
      for (var i = 0; i < 4; i++)
        (function (i) {
          setTimeout(function () {
            triggerBlink(g);
          }, i * 110);
        })(i);
      g.el.classList.add("gx-highfive");
      setTimeout(function () {
        g.el.classList.remove("gx-highfive");
      }, 420);
      emitBurst(g.x + g.w / 2, g.y + g.h / 2, g.cfg.rgb, 22, 4);
      ghosts.forEach(function (other) {
        if (other === g) return;
        var dx = other.x - g.x,
          dy = other.y - g.y,
          d = Math.hypot(dx, dy);
        if (d < 220 && d > 1) {
          var s = ((220 - d) / 220) * 2.8;
          other.vx += (dx / d) * s;
          other.vy += (dy / d) * s;
        }
      });
    }

    function startChase(chaser, target) {
      chaser.chasing = target;
      chaser.chaseTimer = 5500;
      chaser.el.classList.add("gx-chasing");
    }

    function stopChase(g) {
      g.chasing = null;
      g.chaseTimer = 0;
      g.el.classList.remove("gx-chasing");
      var spd = Math.hypot(g.vx, g.vy);
      if (spd > 0.9) {
        g.vx = (g.vx / spd) * 0.9;
        g.vy = (g.vy / spd) * 0.9;
      }
    }

    var lastT = 0;
    var boss = ghosts.filter(function (g) {
      return g.cfg.boss;
    })[0];

    function tick(now) {
      var dt = lastT ? Math.min(now - lastT, 50) : 16;
      lastT = now;
      updateParticles();
      drawParticles();

      if (coin.state === "drifting") {
        coin.t++;
        coin.x += coin.vx;
        coin.y += coin.vy;
        if (coin.x < 0) {
          coin.x = 0;
          coin.vx = Math.abs(coin.vx);
        }
        if (coin.x + coin.w > VW) {
          coin.x = VW - coin.w;
          coin.vx = -Math.abs(coin.vx);
        }
        if (coin.y < 0) {
          coin.y = 0;
          coin.vy = Math.abs(coin.vy);
        }
        if (coin.y + coin.h > VH) {
          coin.y = VH - coin.h;
          coin.vy = -Math.abs(coin.vy);
        }
        var coinBob = Math.sin(coin.t * 0.03 + coin.bobPhase) * 4;
        var coinSpin = (Math.sin(coin.t * 0.015 + coin.bobPhase) * 10).toFixed(
          1,
        );
        coin.el.style.transform =
          "translate(" +
          coin.x +
          "px," +
          (coin.y + coinBob) +
          "px) rotate(" +
          coinSpin +
          "deg)";
      } else if (coin.state === "dragging") {
        coin.t++;
        var coinBobD = Math.sin(coin.t * 0.08 + coin.bobPhase) * 2;
        coin.el.style.transform =
          "translate(" + coin.x + "px," + (coin.y + coinBobD) + "px)";
      }
      updateCoinHitTest();

      ghosts.forEach(function (g) {
        g.t++;
        if (g === dragging) {
          var bobD = Math.sin(g.t * 0.08 + g.bobPhase) * 3;
          g.el.style.transform =
            "translate(" + g.x + "px," + (g.y + bobD) + "px)";
          return;
        }

        if (g.chasing && g.chaseTimer > 0) {
          g.chaseTimer -= dt;
          if (g.chaseTimer <= 0) {
            stopChase(g);
          } else {
            var tx = g.chasing.x + g.chasing.w / 2 - (g.x + g.w / 2);
            var ty = g.chasing.y + g.chasing.h / 2 - (g.y + g.h / 2);
            var td = Math.hypot(tx, ty);
            if (td > 10) {
              g.vx += (tx / td) * 0.022;
              g.vy += (ty / td) * 0.022;
              var spdC = Math.hypot(g.vx, g.vy);
              if (spdC > 1.3) {
                g.vx = (g.vx / spdC) * 1.3;
                g.vy = (g.vy / spdC) * 1.3;
              }
              if (g.t % 3 === 0)
                emitTrail(g.x + g.w / 2, g.y + g.h / 2, g.cfg.rgb);
            }
          }
        }

        if (!g.cfg.boss && boss && boss !== dragging && !g.chasing) {
          var dxB = boss.x + boss.w / 2 - (g.x + g.w / 2);
          var dyB = boss.y + boss.h / 2 - (g.y + g.h / 2);
          var dB = Math.hypot(dxB, dyB);
          if (dB < 280 && dB > 55) {
            g.vx += (dxB / dB) * 0.004;
            g.vy += (dyB / dB) * 0.004;
          }
        }

        g.x += g.vx;
        g.y += g.vy;
        if (g.x < 0) {
          g.x = 0;
          g.vx = Math.abs(g.vx);
        }
        if (g.x + g.w > VW) {
          g.x = VW - g.w;
          g.vx = -Math.abs(g.vx);
        }
        if (g.y < 0) {
          g.y = 0;
          g.vy = Math.abs(g.vy);
        }
        if (g.y + g.h > VH) {
          g.y = VH - g.h;
          g.vy = -Math.abs(g.vy);
        }

        var bob = Math.sin(g.t * 0.024 + g.bobPhase) * 5;
        g.el.style.transform = "translate(" + g.x + "px," + (g.y + bob) + "px)";

        var spd = Math.hypot(g.vx, g.vy);
        var waveSpeed = 0.0025 + spd * 0.0008;
        g.tailCells.forEach(function (tc) {
          var phase =
            now * waveSpeed + tc.col * 0.65 + tc.row * 0.4 + g.bobPhase;
          var wave = Math.sin(phase);
          var vertY = wave * 2;
          var op;
          if (tc.baseOn) {
            op = 0.45 + (wave * 0.5 + 0.5) * 0.55;
          } else {
            var v = wave * 0.5 + 0.5;
            op = v > 0.72 ? (v - 0.72) * 3.57 * 0.48 : 0;
          }
          tc.el.style.opacity = op.toFixed(2);
          tc.el.style.transform = "translateY(" + vertY.toFixed(1) + "px)";
        });

        g.blinkTimer -= dt;
        if (g.blinkTimer <= 0) {
          triggerBlink(g);
          g.blinkTimer = g.chasing
            ? 350 + Math.random() * 1000
            : 1800 + Math.random() * 5000;
        }
      });

      for (var i = 0; i < ghosts.length; i++) {
        for (var j = i + 1; j < ghosts.length; j++) {
          var a = ghosts[i],
            b = ghosts[j];
          if (a === dragging || b === dragging) continue;
          var cx1 = a.x + a.w / 2,
            cy1 = a.y + a.h / 2;
          var cx2 = b.x + b.w / 2,
            cy2 = b.y + b.h / 2;
          var dx = cx2 - cx1,
            dy = cy2 - cy1,
            d2 = dx * dx + dy * dy;
          var minD = a.r + b.r;
          if (d2 < minD * minD && d2 > 0.01) {
            var d = Math.sqrt(d2),
              nx = dx / d,
              ny = dy / d;
            var push = (minD - d) * 0.5;
            a.x -= nx * push;
            a.y -= ny * push;
            b.x += nx * push;
            b.y += ny * push;
            var rvx = a.vx - b.vx,
              rvy = a.vy - b.vy,
              dot = rvx * nx + rvy * ny;
            if (dot > 0) {
              a.vx -= dot * nx;
              a.vy -= dot * ny;
              b.vx += dot * nx;
              b.vy += dot * ny;
              var bx = (cx1 + cx2) / 2,
                by = (cy1 + cy2) / 2;
              emitBurst(bx, by, a.cfg.rgb, 10, 2.5);
              emitBurst(bx, by, b.cfg.rgb, 10, 2.5);
              [a, b].forEach(function (g) {
                if (g.bumping) return;
                g.bumping = true;
                g.el.classList.add("gx-bump");
                var blinkEl = g.el.querySelector(".gx-blink-cover");
                if (blinkEl) {
                  g.isBlinking = true;
                  blinkEl.style.opacity = "1";
                  setTimeout(function () {
                    blinkEl.style.opacity = "0";
                    g.isBlinking = false;
                  }, 220);
                }
                setTimeout(function () {
                  g.el.classList.remove("gx-bump");
                  g.bumping = false;
                }, 240);
              });
              if (Math.random() < 0.18 && !a.chasing && !b.chasing) {
                var sA = Math.hypot(a.vx, a.vy),
                  sB = Math.hypot(b.vx, b.vy);
                if (sA >= sB) startChase(a, b);
                else startChase(b, a);
              }
            }
          }
        }
      }

      requestAnimationFrame(tick);
    }

    requestAnimationFrame(tick);

    // ── Coin-in gating ────────────────────────────────────────────────────
    // Before coin-in, the field is pure drift: no drag, no hover card, no
    // click-to-high-five, no click ripple. Coin-in arms per-ghost
    // pointer-events (see .gx-armed .gx-ghost in v3.css) and this `armed`
    // flag, which every user-driven handler above checks. `armed` is the
    // one source of truth; the coin's own position/visibility (drifting
    // vs. in the slot) is driven from here too — coinInsert()/coinEject()
    // run regardless of whether coin-in was reached by drag-drop, the "c"
    // key, or the plate itself, so the visuals never disagree between
    // paths. The plate's own choreography (label/credit/panel) listens
    // for "gx-armchange" instead of running inline here, for the same
    // reason.
    function coinIn() {
      if (armed) return;
      armed = true;
      coinInsert();
      field.classList.add("gx-armed");
      document.body.classList.add("gx-coin-in");
      document.dispatchEvent(
        new CustomEvent("gx-armchange", { detail: { armed: true } }),
      );
    }

    function coinOut() {
      if (!armed) return;
      armed = false;
      if (dragging) {
        dragging.el.classList.remove("gx-dragging");
        dragging = null;
      }
      field.classList.remove("gx-armed");
      document.body.classList.remove("gx-coin-in");
      coinEject();
      document.dispatchEvent(
        new CustomEvent("gx-armchange", { detail: { armed: false } }),
      );
    }

    function toggleCoin() {
      if (armed) coinOut();
      else coinIn();
    }

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") coinOut();
    });

    window.GXField = {
      coinIn: coinIn,
      coinOut: coinOut,
      toggleCoin: toggleCoin,
      isArmed: function () {
        return armed;
      },
    };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
