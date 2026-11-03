/* The hero reel: the Figma storyboard ("Frame 1046") as live layers, animated with AnnotateKit's own motion. Every vector
   is cut from Figma's SVG export into reel-layers.js (build.py) on one 546 x 890 stage (the 418 x 890 phone plus 64pt each
   side, where the glass card overhangs it). Text whose copy changes (the launcher's title, the review bar's count, the
   hint line and its counter, pin 3's number) is live SF Pro set the way the overlay sets it, and the overlay's edge glow
   and frost are drawn live from the code (turning rings, swaying blobs). What's on screen at each beat is the
   storyboard's; how it moves is the code's (M, and the springs solved as real springs); the pacing (T) is the original
   recording's. The row numbers in comments are reel-truth.md's. record.mjs seeks this page frame by frame (reelSeek) to
   make site/demo.mov and demo.webm. Times are seconds. */
(function () {
  "use strict";

  var host = document.querySelector(".hero-phone");
  var SVG = window.REEL_SVG, GLASS = window.REEL_GLASS, TYPED = window.REEL_TYPED;
  if (!host || !SVG) return;

  // ---------- Motion, from the overlay's source ----------
  // SwiftUI spring(duration d, bounce b): response d, damping ratio 1 - b; .snappy is bounce 0.15, .smooth bounce 0.
  var M = {
    mode: { spring: 0.3, bounce: 0.15 },          // OverlayRoot.modeAnimation: snappy 0.3 (chrome, launcher, card swaps)
    backdrop: { ease: 0.3 },                      // OverlayRoot.backdropFade: easeInOut 0.3 (dim, glow, frost, marks)
    palette: { ease: 0.8 },                       // OverlayRoot.paletteChange: easeInOut 0.8 (glow blue <-> green)
    badge: { spring: 0.45, bounce: 0.35 },        // OverlayRoot.badgeAppearance: pin pops in from scale 0.3
    glyph: { spring: 0.25, bounce: 0.15 },        // PinBadge.changeAnimation: snappy 0.25 (glyph scale 0.5 + fade, fill)
    hint: { spring: 0.45, bounce: 0 },            // ReviewHintLine.changeAnimation: smooth 0.45 (HintSwap)
    tick: { spring: 0.3, bounce: 0.15 },          // ReviewHintLine.tickAnimation: snappy 0.3 (the counter's digit roll)
    count: { spring: 0.2, bounce: 0.15 },         // the bar's count and Send follow the saved notes, snappy 0.2
    status: { spring: 0.25, bounce: 0.15 },       // LauncherButton.statusAnimation: snappy 0.25 (title + width)
    frostTop: { spring: 0.25, bounce: 0.15 },     // the frost's top follows the chrome's, snappy 0.25
    indicator: { spring: 0.5, bounce: 0.2 },      // LauncherButton.indicatorAnimation: the dot slides in, the pill widens
    indicatorFade: { ease: 0.5 },                 // LauncherButton.indicatorFade: easeInOut 0.5
    app: { ease: 0.4 },                           // the app's own hot-reload change (not AnnotateKit; 0.4 s in the original)
    // the finger drawing the loop: fast off the mark, easing as it closes (0.47 s, closed by 0.33 s in the original)
    ink: { dur: 0.47, curve: function (u) { return 1 - Math.pow(1 - u, 3); } },
  };
  var ENTRANCE = 48, HIDDEN_SCALE = 0.8, BADGE_FROM = 0.3, GLYPH_FROM = 0.5, HINT_Y = 8, HINT_BLUR = 4;
  var PRESS = 0.25;      // finger down to release, for every button press
  var DOT_SLIDE = 16;    // LauncherButton: the dot comes from one dot plus its gap to the right, and the pill widens by as much

  var T = {
    reveal: 0.1,          // the launcher appears (row 1) …
    dot: 0.7,             // … and 600 ms later its status dot slides in (row 2)
    press: 1.4,           // finger on the launcher
    enter: 1.65,          // release: overlay in, launcher out, chrome up
    ink0: 2.45,           // the loop is drawn round the title …
    pin1: 3.0,            // … and its pin pops: "1 note", Send turns on
    pin2: 3.95,           // a tap on the tall bar: selection at once, pin pops, "2 notes"
    pin3: 4.55,           // a tap on the button: selection, "+" pin, the toolbar becomes the comment card
    type0: 5.6, type1: 6.7,
    sendCard: 7.3,        // send on the card: the card becomes the toolbar again ("Claude is connected"), "+" → "3"
    sendAll: 8.6,         // send on the toolbar: every pin spins at once, "Sending notes 3/3 0s"
    working: 9.67,        // the next status poll, just after the 1s tick: "Claude is working… 1s" (KF6), glow to green
    check: [12.3, 14.1, 15.9],
    applied: 17.67,       // the agent's "Changes applied, reinstalling 9s" (KF7) just after the 9s tick, glow to blue
    exit: 18.45,          // back: overlay out, launcher back with "Done · 3 changes"
    reload: 19.1,         // the app picks up the edits, 0.65 s after the exit starts (row 28)
    idle: 23.67,          // finalHold: 6 s after the done stage, "Done" → "Annotate" (row 29)
  };
  var INTRO_HOLD = 3.0;   // the gestures hint holds 3 s, then gives way to the connection line (row 10)
  var LOOP = 25.5;        // then a hard cut back to frame 0, as the original loops (row 31)
  window.REEL_LOOP = LOOP;

  // ---------- Stage geometry (stage points: the phone frame's plus 64 in x) ----------
  var CX = 273;                                                   // the screen's centre line
  var PIN = { 1: [235, 166], 2: [434, 348], 3: [201, 616] };       // pin centres
  var LAUNCHER = { y: 804, h: 44, bare: 104, annotate: 120, done: 184 };   // 44 high; 16 + (dot 8 + 8) + title + 16
  var BAR = { y: 796, h: 52, capsuleX: 166, capsuleW: 214 };
  var HINT_TOP = 760, CARD_TOP = 686;
  var SCREEN = { x: 72, y: 8, w: 402, h: 874, r: 62 };
  var BLUE = "0, 136, 255", GREEN = "52, 199, 89";                 // systemBlue #0088FF, systemGreen #34C759

  // ---------- Layers ----------
  var stage = document.createElement("div");
  stage.className = "reel";
  stage.setAttribute("aria-hidden", "true");
  var el = {};
  function div(cls, parent, css, html) {
    var d = document.createElement(cls === "span" ? "span" : "div");
    if (cls !== "span") d.className = cls;
    if (css) d.style.cssText = css;
    if (html != null) d.innerHTML = html;
    (parent || stage).appendChild(d);
    return d;
  }
  function glassPieces(parent, css, scale) {
    ["reel-glass", "reel-glass-rim"].forEach(function (cls) { div(cls, parent, css + "--k:" + scale + ";"); });
  }
  function svgLayer(name, parent) {
    var layer = div("reel-layer reel-" + name, parent);
    var k = /^card/.test(name) ? 1.5 : 1;   // the card is the component's 1.5x variant
    (GLASS[name] || []).forEach(function (g) {
      glassPieces(layer, "left:" + g.x + "px;top:" + g.y + "px;width:" + g.w + "px;height:" + g.h + "px;border-radius:" + g.r + "px;", k);
    });
    layer._press = div("reel-svg", layer, null, SVG[name]);   // a press dims the button's label, not its glass
    el[name] = layer;
    return layer;
  }
  function named(name, node) { el[name] = node; return node; }

  ["bezel", "base", "body", "bodyFinal"].forEach(function (n) { svgLayer(n); });

  // The overlay (ActiveOverlay): the dim, then the edge glow and the frost, as the app draws them (rows 8, 9). Each
  // palette is a whole glow and a whole frost; the two crossfade (row 24), added (plus-lighter) inside their own group
  // so two instances at p and 1 - p are exactly the blend, with no bump halfway.
  var active = named("active", div("reel-layer"));
  svgLayer("dim", active);
  var screen = div("reel-screen", active, "left:" + SCREEN.x + "px;top:" + SCREEN.y + "px;width:" + SCREEN.w + "px;height:" +
    SCREEN.h + "px;border-radius:" + SCREEN.r + "px;");
  var glowGroup = div("reel-mix", screen), frostGroup = div("reel-mix", screen);

  // ScreenGlow: two conic rings of uneven colour, each masked to a soft band along the rounded edge, turning in
  // opposite directions (OverlayRoot.swift:663-686; FluidLayers.swift:101-118)
  var RINGS = [
    { stops: [[0.3, 0], [0, 0.18], [0.28, 0.37], [0, 0.55], [0.3, 0.72], [0, 0.88], [0.3, 1]], period: 9, clockwise: false, band: 140 },
    { stops: [[0.7, 0], [0.25, 0.13], [0.55, 0.27], [0.18, 0.41], [0.75, 0.56], [0.35, 0.7], [0.2, 0.85], [0.7, 1]], period: 14, clockwise: true, band: 62 },
  ];
  // EdgeBandMask: white at the edge fading inward. A band just outside the screen, clipped to it, so only its shadow
  // lands inside; the shadow blur is the band width, as in the app's CGContext (blur ≈ 2σ in both)
  function bandMask(width) {
    var k = 2, c = document.createElement("canvas");
    c.width = SCREEN.w * k; c.height = SCREEN.h * k;
    var g = c.getContext("2d");
    function rounded(x, y, w, h, r) { g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
    g.scale(k, k);
    g.beginPath(); rounded(0, 0, SCREEN.w, SCREEN.h, SCREEN.r); g.clip();
    g.shadowColor = "#fff"; g.shadowBlur = width * k; g.fillStyle = "#fff";
    g.beginPath(); rounded(-width, -width, SCREEN.w + 2 * width, SCREEN.h + 2 * width, SCREEN.r + width); rounded(0, 0, SCREEN.w, SCREEN.h, SCREEN.r);
    g.fill("evenodd");
    return "url(" + c.toDataURL() + ")";
  }
  var MASKS = RINGS.map(function (r) { return bandMask(r.band); });
  var DIAGONAL = Math.ceil(Math.hypot(SCREEN.w, SCREEN.h));
  var glows = [];
  function glow(name, rgb, t0) {
    var node = named(name, div("reel-layer", glowGroup));
    glows.push({ t0: t0, rings: RINGS.map(function (r, i) {
      var box = div("reel-ring-box", node, "-webkit-mask-image:" + MASKS[i] + ";mask-image:" + MASKS[i] + ";");
      var stops = r.stops.map(function (s) { return "rgba(" + rgb + "," + s[0] + ") " + s[1] + "turn"; }).join(",");
      // the conic sweep starts at 3 o'clock, as CAGradientLayer's does with its end point at (1, 0.5)
      return { ring: r, node: div("reel-ring", box, "left:" + (SCREEN.w - DIAGONAL) / 2 + "px;top:" + (SCREEN.h - DIAGONAL) / 2 +
        "px;width:" + DIAGONAL + "px;height:" + DIAGONAL + "px;background:conic-gradient(from 90deg," + stops + ");") };
    }) });
  }
  // BottomFrost: an even wash plus three blobs swaying on sines, the whole fading to clear toward its top, from the
  // chrome's top down to the screen's bottom (OverlayRoot.swift:358-386, 411-420; FluidLayers.swift:122-241)
  var BLOBS = [
    { x: 0.2, y: 0.85, w: 0.95, h: 1.1, sway: 0.18, period: 11, phase: 0, opacity: 0.42 },
    { x: 0.65, y: 0.95, w: 0.8, h: 0.9, sway: 0.22, period: 8, phase: 2, opacity: 0.28 },
    { x: 0.9, y: 0.75, w: 0.7, h: 1.0, sway: 0.16, period: 14, phase: 4, opacity: 0.3 },
  ];
  var frosts = [];
  function frost(name, rgb, t0) {
    var node = named(name, div("reel-layer", frostGroup));
    var body = div("reel-frost", node);
    div("reel-frost-wash", body, "background:linear-gradient(rgba(" + rgb + ",0),rgba(" + rgb + ",0.28));");
    frosts.push({ t0: t0, body: body, blobs: BLOBS.map(function (b) {
      return { blob: b, node: div("reel-frost-blob", body, "background:radial-gradient(closest-side,rgba(" + rgb + "," + b.opacity + "),rgba(" + rgb + ",0));") };
    }) });
  }
  // one instance per palette stint; an incoming instance starts its turn and sway from zero (row 24)
  glow("glowBlue", BLUE, T.enter); glow("glowGreen", GREEN, T.working); glow("glowBlue2", BLUE, T.applied);
  frost("frostBlue", BLUE, T.enter); frost("frostGreen", GREEN, T.working); frost("frostBlue2", BLUE, T.applied);
  named("frostTop", div("reel-layer"));   // holds the frost's top as a track; never drawn

  ["loop", "sel2", "sel3",
    "pin1s2disc", "pin1s6disc", "pin1s7disc", "pin2s2disc", "pin2s6disc", "pin2s7disc", "pin3s3disc", "pin3s6disc", "pin3s7disc",
    "pin1s2glyph", "pin1s6glyph", "pin1s7glyph", "pin2s2glyph", "pin2s6glyph", "pin2s7glyph", "pin3s3glyph"].forEach(function (n) { svgLayer(n); });
  // pin 3's number once its card is sent (PinBadge: BadgeNumber, SF Pro Semibold 15)
  div("reel-pin-number", named("pin3num", div("reel-layer")), "left:" + (PIN[3][0] - 14) + "px;top:" + (PIN[3][1] - 14) + "px;", "3");
  ["pin3s6glyph", "pin3s7glyph"].forEach(function (n) { svgLayer(n); });

  // The hint line (ReviewHintLine): dot, headline, detail and elapsed in one centred row; a new headline is a new row
  // that swaps in (HintSwap), while the elapsed rolls its digits in place.
  var hint = named("hint", div("reel-layer"));
  var S = T.sendAll;   // the elapsed counts whole seconds since Send and never resets (row 21)
  var LINES = [
    { name: "draw", text: "Draw, tap or hold to annotate" },
    { name: "connected", text: "Claude is connected", dot: true },
    { name: "sending", text: "Sending notes", detail: "3/3", dot: true, from: T.sendAll, to: T.working },
    { name: "working", text: "Claude is working...", dot: true, from: T.working, to: T.applied },
    { name: "applied", text: "Changes applied, reinstalling", dot: true, from: T.applied, to: T.exit + 0.1 },   // gone before 10s
  ];
  LINES.forEach(function (l) {
    var row = named("hint_" + l.name, div("reel-hint-line", hint, "top:" + HINT_TOP + "px;"));
    if (l.dot) row.appendChild(statusDot("reel-hint-dot"));
    div("span", row, null, l.text);
    if (l.detail) div("span", row, "margin-left:4px;opacity:.5", l.detail);
    if (l.from == null) return;
    var elapsed = div("span", row, "margin-left:4px;opacity:.5"), digits = div("reel-digits", elapsed);
    div("span", elapsed, null, "s");
    l.values = [];
    for (var v = Math.floor(l.from - S + 1e-6); S + v < l.to; v++) {
      l.values.push(v);
      named("hint_" + l.name + "_" + v, div("reel-digit", digits, null, String(v)));
    }
  });
  // StatusIndicator: an 8pt green dot over its 16pt halo (25%), whose sharp circle hands over to a blurred one as it swells
  function statusDot(cls) {
    var d = document.createElement("span");
    d.className = cls;
    d.innerHTML = '<i class="reel-dot-halo"><i class="reel-halo-sharp"></i><i class="reel-halo-soft"></i></i><i class="reel-dot"></i>';
    return d;
  }

  // The review bar: back, the count capsule (its title live), send on and off
  var BAR_PARTS = ["barBack", "barCapsule", "barSendOff", "barSendOn"];
  BAR_PARTS.forEach(function (n) { svgLayer(n); });
  var count = div("reel-count", el.barCapsule, "left:" + BAR.capsuleX + "px;top:" + BAR.y + "px;width:" + BAR.capsuleW + "px;height:" + BAR.h + "px;");
  ["No notes yet", "1 note", "2 notes", "3 notes"].forEach(function (c, i) { named("count" + i, div("span", count, null, c)); });

  // The launcher (LauncherButton): one glass capsule; the dot and the title ride its left edge as its width changes
  var launcher = named("launcher", div("reel-layer"));
  var row = named("launcherRow", div("reel-launcher", launcher, "top:" + LAUNCHER.y + "px;height:" + LAUNCHER.h + "px;"));
  glassPieces(row, "left:0;top:0;width:100%;height:100%;border-radius:" + LAUNCHER.h / 2 + "px;", 1);
  var label = named("launcherLabel", div("reel-launcher-label", row));
  named("launcherDot", label.appendChild(statusDot("reel-launcher-dot")));
  var titles = named("launcherTitles", div("reel-launcher-titles", label));   // above the dot, so the dot comes from behind it
  named("titleAnnotate", div("reel-launcher-title", titles, null, "Annotate"));
  named("titleDone", div("reel-launcher-title", titles, null, "Done · 3 changes"));

  ["card3", "card4", "card4send", "typed"].forEach(function (n) { svgLayer(n); });
  host.appendChild(stage);
  // the loop's stroke grows along its own path, the way the finger made it (row 11)
  var loopPath = el.loop.querySelector("path[stroke]");
  loopPath.setAttribute("pathLength", "1");
  loopPath.style.strokeDasharray = "1 1";

  // ---------- Curves ----------
  function bezier(x1, y1, x2, y2) {   // CSS cubic-bezier, solved for x by bisection
    function c(a, b, t) { return 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t; }
    return function (x) {
      if (x <= 0) return 0; if (x >= 1) return 1;
      var lo = 0, hi = 1, t = x;
      for (var i = 0; i < 20; i++) { var v = c(x1, x2, t) - x; if (Math.abs(v) < 1e-5) break; if (v > 0) hi = t; else lo = t; t = (lo + hi) / 2; }
      return c(y1, y2, t);
    };
  }
  var EASE_IN_OUT = bezier(0.42, 0, 0.58, 1);
  // Progress (0 → 1, may overshoot) `dt` seconds into a motion. Springs are the damped oscillator itself (mass 1,
  // stiffness (2π/d)², damping 4πζ/d, from rest), not a curve fitted to one.
  function progress(m, dt) {
    if (dt < 0) return 0;
    if (!m) return 1;   // instant
    if (m.curve) return m.curve(Math.min(1, dt / m.dur));
    if (m.ease) return EASE_IN_OUT(dt / m.ease);
    var w = 2 * Math.PI / m.spring, z = 1 - m.bounce;
    if (z >= 1) return 1 - (1 + w * dt) * Math.exp(-w * dt);
    var wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * dt) * (Math.cos(wd * dt) + (z * w / wd) * Math.sin(wd * dt));
  }

  // ---------- Tracks ----------
  // A track is a property's starting value plus changes [t, to, motion]; each change runs from the previous target.
  // Changes at the same time apply in the order they were added, so an instant reset can precede a spring.
  var REST = { opacity: 1, vis: 1, press: 0, x: 0, y: 0, scale: 1, blur: 0, draw: 0, reveal: 0, w: LAUNCHER.annotate, top: HINT_TOP };
  var tracks = {};
  function to(name, prop, t, value, motion, from) {
    var k = name + "|" + prop;
    var tr = tracks[k] || (tracks[k] = { node: el[name], prop: prop, from: from != null ? from : REST[prop], keys: [] });
    tr.keys.push([t, value, motion]);
  }
  function value(tr, t) {
    var v = tr.from, prev = tr.from;
    for (var i = 0; i < tr.keys.length; i++) {
      var k = tr.keys[i];
      if (t < k[0]) break;
      v = prev + (k[1] - prev) * progress(k[2], t - k[0]);
      prev = k[1];
    }
    return v;
  }
  function set(name, prop, t, v, from) { to(name, prop, t, v, null, from); }
  function show(name, t, motion) { to(name, "opacity", t, 1, motion, 0); }
  function hide(name, t, motion) { to(name, "opacity", t, 0, motion); }
  function always(name) { set(name, "opacity", 0, 1, 1); }
  function origin(name, x, y) { el[name].style.transformOrigin = x + "px " + y + "px"; }
  function press(name, t) { set(name, "press", t - PRESS, 1, 0); set(name, "press", t, 0); }   // label opacity 0.6 while held (rows 4, 27)

  // the overlay's chrome enters from 48pt below; swapped out it shrinks to 0.8 and fades; on exit it sinks
  // (OverlayRoot.swapTransition / chrome transition, snappy 0.3; rows 7, 17, 26)
  function chromeIn(name, t) {
    set(name, "y", t, ENTRANCE, ENTRANCE); to(name, "y", t, 0, M.mode);
    set(name, "scale", t, 1); to(name, "opacity", t, 1, M.mode, 0);
  }
  function chromeSwapOut(name, t) { hide(name, t, M.mode); to(name, "scale", t, HIDDEN_SCALE, M.mode); }
  function chromeExit(name, t) { hide(name, t, M.mode); to(name, "y", t, ENTRANCE, M.mode); }
  // the hint line's headline swap (HintSwap, row 20): in from 8pt below and blurred, out 8pt up, smooth 0.45
  function hintSwap(from, toLine, t) {
    hide(from, t, M.hint); to(from, "y", t, -HINT_Y, M.hint); to(from, "blur", t, HINT_BLUR, M.hint);
    show(toLine, t, M.hint); set(toLine, "y", t, HINT_Y, HINT_Y); to(toLine, "y", t, 0, M.hint);
    set(toLine, "blur", t, HINT_BLUR, HINT_BLUR); to(toLine, "blur", t, 0, M.hint);
  }
  // a pin pops in from its centre (badgeAppearance, row 12)
  function pinPop(names, n, t) {
    names.forEach(function (name) { show(name, t, M.badge); to(name, "scale", t, 1, M.badge, BADGE_FROM); origin(name, PIN[n][0], PIN[n][1]); });
  }
  // a pin's face changes (PinBadge, row 14): the new glyph scales up from 0.5 as the old one shrinks to 0.5, both fading;
  // the new fill fades in over the old, which goes once it's covered (no see-through disc halfway)
  function glyphSwap(a, b, n, t) {
    hide(a, t, M.glyph); to(a, "scale", t, GLYPH_FROM, M.glyph);
    show(b, t, M.glyph); to(b, "scale", t, 1, M.glyph, GLYPH_FROM);
    origin(a, PIN[n][0], PIN[n][1]); origin(b, PIN[n][0], PIN[n][1]);
  }
  function discSwap(a, b, t) { show(b, t, M.glyph); hide(a, t + 0.5, null); }

  // ---------- The story ----------
  ["bezel", "base", "body", "dim"].forEach(always);

  // launcher: appears (scale 0.8 + fade, snappy 0.3, row 1); 600 ms on, the dot slides out from behind the title while
  // the pill widens 16pt (spring 0.5/0.2) and fades in (easeInOut 0.5, row 2); pressed (row 4); leaves (row 6)
  origin("launcher", CX, LAUNCHER.y + LAUNCHER.h / 2);
  set("launcher", "opacity", 0, 0, 0); set("launcher", "scale", 0, HIDDEN_SCALE, HIDDEN_SCALE);
  to("launcher", "opacity", T.reveal, 1, M.mode); to("launcher", "scale", T.reveal, 1, M.mode);
  set("launcherRow", "w", 0, LAUNCHER.bare, LAUNCHER.bare); to("launcherRow", "w", T.dot, LAUNCHER.annotate, M.indicator);
  set("launcherDot", "x", 0, DOT_SLIDE, DOT_SLIDE); to("launcherDot", "x", T.dot, 0, M.indicator);
  set("launcherDot", "opacity", 0, 0, 0); to("launcherDot", "opacity", T.dot, 1, M.indicatorFade);
  set("launcherTitles", "x", 0, 0, 0); to("launcherTitles", "x", T.dot, DOT_SLIDE, M.indicator);
  always("titleAnnotate"); set("titleDone", "opacity", 0, 0, 0);
  press("launcherLabel", T.enter);
  hide("launcher", T.enter, M.mode); to("launcher", "scale", T.enter, HIDDEN_SCALE, M.mode);

  // overlay in (easeInOut 0.3, row 5): dim + glow + frost; the hint and the bar rise 48pt together (snappy 0.3, row 7)
  show("active", T.enter, M.backdrop);
  always("glowBlue"); always("frostBlue");
  ["glowGreen", "glowBlue2", "frostGreen", "frostBlue2"].forEach(function (n) { set(n, "opacity", 0, 0, 0); });
  set("frostTop", "top", 0, HINT_TOP, HINT_TOP);
  ["hint"].concat(BAR_PARTS).forEach(function (n) { chromeIn(n, T.enter); });
  origin("hint", CX, HINT_TOP + 10);
  BAR_PARTS.forEach(function (n) { origin(n, CX, BAR.y + BAR.h / 2); });
  always("hint_draw"); LINES.slice(1).forEach(function (l) { set("hint_" + l.name, "opacity", 0, 0, 0); });
  // Send is off with nothing to send (OverlayModel.canSend: count > 0, row 16)
  set("barSendOn", "vis", 0, 0, 0);
  always("count0"); [1, 2, 3].forEach(function (i) { set("count" + i, "opacity", 0, 0, 0); });
  // the gestures hint holds 3 s, then the connection line swaps in (row 10; the card hides it by then)
  hintSwap("hint_draw", "hint_connected", T.enter + INTRO_HOLD);

  // the loop is drawn as one growing stroke and its pin pops; the bar is tapped: selection at once, pin pops. The
  // storyboard has no card for these two, so each pin is saved as it lands: the count and Send follow (snappy 0.2)
  show("loop", T.ink0, null); to("loop", "draw", T.ink0, 1, M.ink, 0);
  pinPop(["pin1s2disc", "pin1s2glyph"], 1, T.pin1);
  hide("count0", T.pin1, M.count); show("count1", T.pin1, M.count);
  to("barSendOn", "vis", T.pin1, 1, M.count); to("barSendOff", "vis", T.pin1, 0, M.count, 1);
  show("sel2", T.pin2, null); pinPop(["pin2s2disc", "pin2s2glyph"], 2, T.pin2);
  hide("count1", T.pin2, M.count); show("count2", T.pin2, M.count);

  // the button is tapped: selection, "+" pin, and the toolbar becomes the card (card in from 48pt; bar out to 0.8,
  // row 17); the frost's top rises to the card's (snappy 0.25)
  show("sel3", T.pin3, null); pinPop(["pin3s3disc", "pin3s3glyph"], 3, T.pin3);
  ["hint"].concat(BAR_PARTS).forEach(function (n) { chromeSwapOut(n, T.pin3); });
  to("frostTop", "top", T.pin3, CARD_TOP, M.frostTop);
  ["card3", "card4", "card4send", "typed"].forEach(function (n) { origin(n, CX, 767); });
  chromeIn("card3", T.pin3);
  // typing: the placeholder goes with the first key, and the card's send turns blue with it, instantly (row 19, 16)
  hide("card3", T.type0, null); ["card4", "card4send", "typed"].forEach(function (n) { show(n, T.type0, null); });
  var n = TYPED.length - 1;
  for (var i = 1; i <= n; i++) set("typed", "reveal", T.type0 + (T.type1 - T.type0) * Math.pow(i / n, 0.95), TYPED[i], 0);

  // send on the card: the note is saved ("3 notes"); the card shrinks away, the bar and its hint rise in; pin 3 gets
  // its number
  press("card4send", T.sendCard);
  ["card4", "card4send", "typed"].forEach(function (c) { chromeSwapOut(c, T.sendCard); });
  ["hint"].concat(BAR_PARTS).forEach(function (nm) { chromeIn(nm, T.sendCard); });
  to("frostTop", "top", T.sendCard, HINT_TOP, M.frostTop);
  set("count2", "opacity", T.sendCard, 0); set("count3", "opacity", T.sendCard, 1);
  glyphSwap("pin3s3glyph", "pin3num", 3, T.sendCard);

  // send on the bar: Send goes off, "Sending notes 3/3", and every pin swaps to a spinner in the same update (row 22)
  press("barSendOn", T.sendAll);
  to("barSendOn", "vis", T.sendAll, 0, M.count); to("barSendOff", "vis", T.sendAll, 1, M.count);
  hintSwap("hint_connected", "hint_sending", T.sendAll);
  [["pin1s2disc", "pin1s2glyph"], ["pin2s2disc", "pin2s2glyph"], ["pin3s3disc", "pin3num"]].forEach(function (p, k) {
    var pin = k + 1;
    discSwap(p[0], "pin" + pin + "s6disc", T.sendAll); glyphSwap(p[1], "pin" + pin + "s6glyph", pin, T.sendAll);
  });
  // next poll: "Claude is working…", and the glow and frost crossfade to green (easeInOut 0.8, row 24)
  hintSwap("hint_sending", "hint_working", T.working);
  hide("glowBlue", T.working, M.palette); show("glowGreen", T.working, M.palette);
  hide("frostBlue", T.working, M.palette); show("frostGreen", T.working, M.palette);
  // each pin resolves when the agent says so: spinner → check, disc to green (snappy 0.25)
  T.check.forEach(function (t, k) {
    var pin = k + 1;
    discSwap("pin" + pin + "s6disc", "pin" + pin + "s7disc", t); glyphSwap("pin" + pin + "s6glyph", "pin" + pin + "s7glyph", pin, t);
  });
  // the agent's own status, "Changes applied, reinstalling": glow back to blue (KF7)
  hintSwap("hint_working", "hint_applied", T.applied);
  hide("glowGreen", T.applied, M.palette); show("glowBlue2", T.applied, M.palette);
  hide("frostGreen", T.applied, M.palette); show("frostBlue2", T.applied, M.palette);
  // the elapsed ticks on whole seconds after Send through every stage, rolling each digit that changes (numericText,
  // snappy 0.3, row 21)
  LINES.forEach(function (l) {
    (l.values || []).forEach(function (v, k) {
      var name = "hint_" + l.name + "_" + v, at = S + v, next = at + 1;
      if (k === 0) always(name);
      else { show(name, at, M.tick); set(name, "y", at, HINT_Y, HINT_Y); to(name, "y", at, 0, M.tick); set(name, "blur", at, HINT_BLUR, HINT_BLUR); to(name, "blur", at, 0, M.tick); }
      if (k < l.values.length - 1) { hide(name, next, M.tick); to(name, "y", next, -HINT_Y, M.tick); to(name, "blur", next, HINT_BLUR, M.tick); }
    });
  });

  // back: pressed (row 27), then the overlay with its marks fades (easeInOut 0.3), the chrome sinks 48pt, and the
  // launcher returns showing "Done · 3 changes" (scale 0.8 → 1 + fade, snappy 0.3, row 26)
  press("barBack", T.exit);
  ["active", "loop", "sel2", "sel3", "pin1s7disc", "pin1s7glyph", "pin2s7disc", "pin2s7glyph", "pin3s7disc", "pin3s7glyph"]
    .forEach(function (nm) { hide(nm, T.exit, M.backdrop); });
  ["hint"].concat(BAR_PARTS).forEach(function (nm) { chromeExit(nm, T.exit); });
  set("launcherRow", "w", T.exit, LAUNCHER.done); set("titleAnnotate", "opacity", T.exit, 0); set("titleDone", "opacity", T.exit, 1);
  set("launcher", "scale", T.exit, HIDDEN_SCALE); show("launcher", T.exit, M.mode); to("launcher", "scale", T.exit, 1, M.mode);
  // the app reloads with the edits
  hide("body", T.reload, M.app); show("bodyFinal", T.reload, M.app);
  // finalHold ends: the same capsule's title crossfades and its width changes (snappy 0.25); dot and titles ride its
  // left edge, and the old title isn't clipped (row 30)
  to("launcherRow", "w", T.idle, LAUNCHER.annotate, M.status);
  hide("titleDone", T.idle, M.status); show("titleAnnotate", T.idle, M.status);

  // ---------- Render ----------
  var TYPED_X = 54;
  var list = Object.keys(tracks).map(function (k) { return tracks[k]; });
  list.forEach(function (tr) { tr.keys.sort(function (a, b) { return a[0] - b[0]; }); });   // stable: same-time keys keep their order
  var frostTopTrack = tracks["frostTop|top"];
  function render(t) {
    var state = new Map();
    list.forEach(function (tr) {
      var s = state.get(tr.node) || {};
      s[tr.prop] = value(tr, t);
      state.set(tr.node, s);
    });
    state.forEach(function (s, node) {
      if (node === el.frostTop) return;
      var op = (s.opacity != null ? s.opacity : 1) * (s.vis != null ? s.vis : 1);
      var pressed = s.press ? 1 - 0.4 * s.press : 1;   // ChromeButtonStyle.pressedOpacity 0.6, on the label
      if (node._press) node._press.style.opacity = pressed; else op *= pressed;
      node.style.opacity = Math.max(0, Math.min(1, op)).toFixed(3);
      node.style.visibility = op <= 0.001 ? "hidden" : "visible";
      var tf = "";
      if (s.x) tf += "translateX(" + s.x.toFixed(2) + "px) ";
      if (s.y) tf += "translateY(" + s.y.toFixed(2) + "px) ";
      if (s.scale != null && s.scale !== 1) tf += "scale(" + s.scale.toFixed(4) + ")";
      node.style.transform = tf;
      node.style.filter = s.blur > 0.01 ? "blur(" + s.blur.toFixed(2) + "px)" : "";
      if (s.draw != null) loopPath.style.strokeDashoffset = (1 - Math.max(0, Math.min(1, s.draw))).toFixed(4);
      if (s.reveal != null) node.style.clipPath = "inset(0 " + (546 - TYPED_X - s.reveal - 1).toFixed(2) + "px 0 0)";
      if (s.w != null) { node.style.width = s.w.toFixed(2) + "px"; node.style.left = (CX - s.w / 2).toFixed(2) + "px"; }
    });
    // the glow's rings turn and the frost's blobs sway on their own clocks, from when each instance came in (rows 8, 9)
    glows.forEach(function (g) {
      var lt = Math.max(0, t - g.t0);
      g.rings.forEach(function (r) {
        r.node.style.transform = "rotate(" + ((r.ring.clockwise ? 1 : -1) * 360 * (lt % r.ring.period) / r.ring.period).toFixed(3) + "deg)";
      });
    });
    var top = value(frostTopTrack, t) - SCREEN.y, height = SCREEN.h - top;
    frosts.forEach(function (f) {
      var lt = Math.max(0, t - f.t0);
      f.body.style.top = top.toFixed(2) + "px"; f.body.style.height = height.toFixed(2) + "px";
      f.blobs.forEach(function (b) {
        var w = SCREEN.w * b.blob.w, h = height * b.blob.h;
        var cx = SCREEN.w * (b.blob.x + b.blob.sway * Math.sin(2 * Math.PI * lt / b.blob.period + b.blob.phase)), cy = height * b.blob.y;
        var st = b.node.style;
        st.left = (cx - w / 2).toFixed(2) + "px"; st.top = (cy - h / 2).toFixed(2) + "px";
        st.width = w.toFixed(2) + "px"; st.height = h.toFixed(2) + "px";
      });
    });
  }
  // layers with no track stay hidden; the drawing-only nodes inside the overlay ride their instance's track
  Object.keys(el).forEach(function (name) {
    if (!list.some(function (tr) { return tr.node === el[name]; })) el[name].style.visibility = "hidden";
  });

  function fit() { stage.style.setProperty("--s", host.clientHeight / 890); }
  fit();
  if ("ResizeObserver" in window) new ResizeObserver(fit).observe(host);

  window.reelSeek = function (t) { render(t); };
  render(0);
  var clock = 0, last = null;
  function frame(now) {
    requestAnimationFrame(frame);
    var dt = last == null ? 0 : Math.min(now - last, 100) / 1000;
    last = now;
    if (window.reelPaused) return;
    clock += dt;
    render(clock % LOOP);
  }
  requestAnimationFrame(frame);
})();
