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
    // flag, which every user-driven handler above checks.
    function coinIn() {
      if (armed) return;
      armed = true;
      field.classList.add("gx-armed");
      field.setAttribute("aria-hidden", "false");
      document.body.classList.add("gx-coin-in");
    }

    function coinOut() {
      if (!armed) return;
      armed = false;
      if (dragging) {
        dragging.el.classList.remove("gx-dragging");
        dragging = null;
      }
      field.classList.remove("gx-armed");
      field.setAttribute("aria-hidden", "true");
      document.body.classList.remove("gx-coin-in");
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
