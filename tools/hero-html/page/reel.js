/* The hero reel: the Figma storyboard ("Frame 1046") as live layers, animated with AnnotateKit's own motion. Every vector
   is cut from Figma's SVG export into reel-layers.js (build.py) on one 546 x 890 stage (the 418 x 890 phone plus 64pt each
   side, where the glass card overhangs it). Text whose copy changes (the launcher's title, the review bar's count, the
   hint line and its counter, pin 3's number) is live SF Pro set the way the overlay sets it. The motion follows the
   overlay's source, not the keyframes: springs and durations are the ones in Sources/AnnotateKit (see M and T), and the
   pacing follows the original Simulator recording. record.mjs seeks this page frame by frame (reelSeek) to make
   site/demo.mov and demo.webm. Times are seconds. */
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
    count: { spring: 0.2, bounce: 0.15 },         // OverlayRoot: the bar's count follows the pins, snappy 0.2
    status: { spring: 0.25, bounce: 0.15 },       // LauncherButton.statusAnimation / chrome state: snappy 0.25
    app: { ease: 0.2 },                           // the app's own hot-reload change (not AnnotateKit)
    ink: { ease: 0.55 },                          // the finger drawing the loop (ink follows it exactly)
  };
  var ENTRANCE = 48, HIDDEN_SCALE = 0.8, BADGE_FROM = 0.3, GLYPH_FROM = 0.5, HINT_Y = 8, HINT_BLUR = 4;
  var PRESS = 0.25;   // finger down to release, for every button press

  var T = {
    press: 1.4,           // finger on the launcher (button opacity 0.6 while held)
    enter: 1.65,          // release: overlay in, launcher out, chrome up
    ink0: 2.45,           // the loop is drawn round the title …
    pin1: 3.0,            // … and its pin pops: "1 note", Send turns on
    pin2: 3.95,           // a tap on the tall bar: selection at once, pin pops, "2 notes"
    pin3: 4.85,           // a tap on the button: selection, "+" pin, the toolbar becomes the comment card
    type0: 5.6, type1: 6.7,
    sendCard: 7.3,        // send on the card: the card becomes the toolbar again ("Claude is connected"), "+" → "3"
    sendAll: 8.6,         // send on the toolbar: "Sending notes 3/3", the pins start spinning one by one
    working: 9.6,         // the next status poll: "Claude is working…", glow and frost to green
    check: [11.3, 11.7, 12.1],
    applied: 12.4,        // the agent's "Changes applied, reinstalling", glow back to blue
    exit: 13.9,           // back: overlay out, launcher back with "Done · 3 changes"
    reload: 14.5,         // the app picks up the edits
    idle: 16.6,           // final stage over: "Done" → "Annotate"
  };
  var STAGGER = 0.1;      // the pins start spinning one after another, as the original recording shows
  // The launcher is up at both ends, so the loop's only cut is the app going back to its unedited state. 18 s is a
  // whole number of the halo's 2 s breath, so the dot doesn't jump at the seam either.
  var LOOP = 18;
  window.REEL_LOOP = LOOP;

  // ---------- Stage geometry (stage points: the phone frame's plus 64 in x) ----------
  var CX = 273;                                                   // the screen's centre line
  var PIN = { 1: [235, 166], 2: [434, 348], 3: [201, 616] };       // pin centres
  var LAUNCHER = { y: 804, h: 44, annotate: 120, done: 184 };      // LauncherButton: 44 high, 16 + dot 8 + 8 + title + 16
  var BAR = { y: 796, h: 52, capsuleX: 166, capsuleW: 214 };
  var HINT_TOP = 760;

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
    div("reel-svg", layer, null, SVG[name]);
    el[name] = layer;
    return layer;
  }
  function named(name, node) { el[name] = node; return node; }

  ["bezel", "base", "body", "bodyFinal"].forEach(function (n) { svgLayer(n); });
  // Each palette instance is a whole overlay (dim, glow, frost). Added (plus-lighter) inside their own group, two of
  // them at opacities p and 1 - p are exactly the blend between them, so a palette change can't brighten or thin the
  // dim halfway, the way two stacked translucent layers do.
  var overlays = div("reel-mix"), scrims = div("reel-mix");
  ["overlay2", "overlay3", "overlay5", "overlay6", "overlay7"].forEach(function (n) { svgLayer(n, overlays); });
  ["scrim3", "scrim5", "scrim6", "scrim7"].forEach(function (n) { svgLayer(n, scrims); });
  ["loop", "sel2", "sel3",
    "pin1s2disc", "pin1s6disc", "pin1s7disc", "pin2s2disc", "pin2s6disc", "pin2s7disc", "pin3s3disc", "pin3s6disc", "pin3s7disc",
    "pin1s2glyph", "pin1s6glyph", "pin1s7glyph", "pin2s2glyph", "pin2s6glyph", "pin2s7glyph", "pin3s3glyph"].forEach(function (n) { svgLayer(n); });
  // pin 3's number once its card is sent (PinBadge: BadgeNumber, SF Pro Semibold 15)
  div("reel-pin-number", named("pin3num", div("reel-layer")), "left:" + (PIN[3][0] - 14) + "px;top:" + (PIN[3][1] - 14) + "px;", "3");
  ["pin3s6glyph", "pin3s7glyph"].forEach(function (n) { svgLayer(n); });

  // The hint line (ReviewHintLine): dot, headline, detail and elapsed in one centred row; a new headline is a new row
  // that swaps in (HintSwap), while the elapsed rolls its digits in place.
  var hint = named("hint", div("reel-layer"));
  var S = T.sendAll;   // the elapsed counts whole seconds since Send (TimelineView anchored to it)
  var LINES = [
    { name: "draw", text: "Draw, tap or hold to annotate" },
    { name: "connected", text: "Claude is connected", dot: true },
    { name: "sending", text: "Sending notes", detail: "3/3", dot: true, from: T.sendAll, to: T.working },
    { name: "working", text: "Claude is working...", dot: true, from: T.working, to: T.applied },
    { name: "applied", text: "Changes applied, reinstalling", dot: true, from: T.applied, to: T.exit + 0.5 },
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
  function statusDot(cls) {   // StatusIndicator: an 8pt green dot (#34C759) in a 16pt breathing halo
    var d = document.createElement("span");
    d.className = cls;
    d.innerHTML = '<i class="reel-dot-halo"></i><i class="reel-dot"></i>';
    return d;
  }

  // The review bar: back, the count capsule (its title live, snappy 0.2 as pins change), send on and off
  var BAR_PARTS = ["barBack", "barCapsule", "barSendOff", "barSendOn"];
  BAR_PARTS.forEach(function (n) { svgLayer(n); });
  var count = div("reel-count", el.barCapsule, "left:" + BAR.capsuleX + "px;top:" + BAR.y + "px;width:" + BAR.capsuleW + "px;height:" + BAR.h + "px;");
  var COUNTS = ["No notes yet", "1 note", "2 notes", "3 notes"];
  COUNTS.forEach(function (c, i) { named("count" + i, div("span", count, null, c)); });

  // The launcher (LauncherButton): one glass capsule whose title and width change together (snappy 0.25)
  var launcher = named("launcher", div("reel-layer"));
  var row = named("launcherRow", div("reel-launcher", launcher, "top:" + LAUNCHER.y + "px;height:" + LAUNCHER.h + "px;"));
  glassPieces(row, "left:0;top:0;width:100%;height:100%;border-radius:" + LAUNCHER.h / 2 + "px;", 1);
  row.appendChild(statusDot("reel-launcher-dot"));
  var titles = div("reel-launcher-titles", row);   // the capsule clips its title while it narrows
  named("titleAnnotate", div("reel-launcher-title", titles, null, "Annotate"));
  named("titleDone", div("reel-launcher-title", titles, null, "Done · 3 changes"));

  ["card3", "card4", "card4send", "typed"].forEach(function (n) { svgLayer(n); });
  host.appendChild(stage);
  // the loop's stroke is drawn on along its own path, the way the finger made it
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
  // Progress (0 → 1, may overshoot) `dt` seconds into a motion.
  function progress(m, dt) {
    if (dt < 0) return 0;
    if (!m) return 1;   // instant
    if (m.ease) return EASE_IN_OUT(dt / m.ease);
    var w = 2 * Math.PI / m.spring, z = 1 - m.bounce;
    if (z >= 1) return 1 - (1 + w * dt) * Math.exp(-w * dt);
    var wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * dt) * (Math.cos(wd * dt) + (z * w / wd) * Math.sin(wd * dt));
  }

  // ---------- Tracks ----------
  // A track is a property's starting value plus changes [t, to, motion]; each change runs from the previous target.
  // Changes at the same time apply in the order they were added, so an instant reset can precede a spring.
  var REST = { opacity: 1, vis: 1, press: 0, y: 0, scale: 1, blur: 0, draw: 0, reveal: 0, w: LAUNCHER.annotate };
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
  function press(name, t) { set(name, "press", t - PRESS, 1, 0); set(name, "press", t, 0); }   // ChromeButtonStyle: 0.6 while held

  // the overlay's chrome enters from 48pt below; swapped out it shrinks to 0.8 and fades; on exit it sinks
  // (OverlayRoot.swapTransition / chrome transition, snappy 0.3)
  function chromeIn(name, t) {
    set(name, "y", t, ENTRANCE, ENTRANCE); to(name, "y", t, 0, M.mode);
    set(name, "scale", t, 1); to(name, "opacity", t, 1, M.mode, 0);
  }
  function chromeSwapOut(name, t) { hide(name, t, M.mode); to(name, "scale", t, HIDDEN_SCALE, M.mode); }
  function chromeExit(name, t) { hide(name, t, M.mode); to(name, "y", t, ENTRANCE, M.mode); }
  // the hint line's headline swap (HintSwap): in from 8pt below and blurred, out 8pt up, smooth 0.45
  function hintSwap(from, toLine, t) {
    hide(from, t, M.hint); to(from, "y", t, -HINT_Y, M.hint); to(from, "blur", t, HINT_BLUR, M.hint);
    show(toLine, t, M.hint); set(toLine, "y", t, HINT_Y, HINT_Y); to(toLine, "y", t, 0, M.hint);
    set(toLine, "blur", t, HINT_BLUR, HINT_BLUR); to(toLine, "blur", t, 0, M.hint);
  }
  // a pin pops in from its centre (badgeAppearance)
  function pinPop(names, n, t) {
    names.forEach(function (name) { show(name, t, M.badge); to(name, "scale", t, 1, M.badge, BADGE_FROM); origin(name, PIN[n][0], PIN[n][1]); });
  }
  // a pin's face changes (PinBadge): the new glyph scales up from 0.5 as the old one shrinks to 0.5, both fading;
  // the new fill fades in over the old, which goes once it's covered (no see-through disc halfway)
  function glyphSwap(a, b, n, t) {
    hide(a, t, M.glyph); to(a, "scale", t, GLYPH_FROM, M.glyph);
    show(b, t, M.glyph); to(b, "scale", t, 1, M.glyph, GLYPH_FROM);
    origin(a, PIN[n][0], PIN[n][1]); origin(b, PIN[n][0], PIN[n][1]);
  }
  function discSwap(a, b, t) { show(b, t, M.glyph); hide(a, t + 0.5, null); }

  // ---------- The story ----------
  ["bezel", "base", "body"].forEach(always);

  // launcher: up from the first frame (and the last), pressed (opacity 0.6), leaves as the overlay comes in
  origin("launcher", CX, LAUNCHER.y + LAUNCHER.h / 2);
  always("launcher"); always("titleAnnotate"); set("titleDone", "opacity", 0, 0, 0);
  press("launcher", T.enter);
  hide("launcher", T.enter, M.mode); to("launcher", "scale", T.enter, HIDDEN_SCALE, M.mode);

  // overlay in (easeInOut 0.3): dim + glow + frost; the hint and the bar rise 48pt (snappy 0.3)
  show("overlay2", T.enter, M.backdrop);
  ["hint"].concat(BAR_PARTS).forEach(function (n) { chromeIn(n, T.enter); });
  origin("hint", CX, HINT_TOP + 10);
  BAR_PARTS.forEach(function (n) { origin(n, CX, BAR.y + BAR.h / 2); });
  always("hint_draw"); LINES.slice(1).forEach(function (l) { set("hint_" + l.name, "opacity", 0, 0, 0); });
  // Send is off with nothing to send (OverlayModel.canSend: count > 0)
  set("barSendOn", "vis", 0, 0, 0);
  always("count0"); [1, 2, 3].forEach(function (i) { set("count" + i, "opacity", 0, 0, 0); });

  // the loop is drawn, its pin pops; the bar is tapped: selection at once, pin pops. Each pin is one state change:
  // the count and Send follow it (snappy 0.2)
  show("loop", T.ink0, null); to("loop", "draw", T.ink0, 1, M.ink, 0);
  pinPop(["pin1s2disc", "pin1s2glyph"], 1, T.pin1);
  hide("count0", T.pin1, M.count); show("count1", T.pin1, M.count);
  to("barSendOn", "vis", T.pin1, 1, M.count); to("barSendOff", "vis", T.pin1, 0, M.count, 1);
  show("sel2", T.pin2, null); pinPop(["pin2s2disc", "pin2s2glyph"], 2, T.pin2);
  hide("count1", T.pin2, M.count); show("count2", T.pin2, M.count);

  // the button is tapped: selection, "+" pin, and the toolbar becomes the card (card in from 48pt; bar out to 0.8)
  show("sel3", T.pin3, null); pinPop(["pin3s3disc", "pin3s3glyph"], 3, T.pin3);
  ["hint"].concat(BAR_PARTS).forEach(function (n) { chromeSwapOut(n, T.pin3); });
  hide("overlay2", T.pin3, M.backdrop); show("overlay3", T.pin3, M.backdrop); show("scrim3", T.pin3, M.backdrop);
  ["card3", "card4", "card4send", "typed"].forEach(function (n) { origin(n, CX, 767); });
  chromeIn("card3", T.pin3);
  // typing: the field's placeholder goes with the first key, and the card's send turns blue with it
  hide("card3", T.type0, null); ["card4", "card4send", "typed"].forEach(function (n) { show(n, T.type0, null); });
  var n = TYPED.length - 1;
  for (var i = 1; i <= n; i++) set("typed", "reveal", T.type0 + (T.type1 - T.type0) * Math.pow(i / n, 0.95), TYPED[i], 0);

  // send on the card: the card shrinks away (0.8 + fade), the bar and "Claude is connected" rise in; pin 3 gets its number
  press("card4send", T.sendCard);
  ["card4", "card4send", "typed"].forEach(function (c) { chromeSwapOut(c, T.sendCard); });
  hide("overlay3", T.sendCard, M.backdrop); hide("scrim3", T.sendCard, M.backdrop);
  show("overlay5", T.sendCard, M.backdrop); show("scrim5", T.sendCard, M.backdrop);
  ["hint"].concat(BAR_PARTS).forEach(function (nm) { chromeIn(nm, T.sendCard); });
  set("hint_draw", "opacity", T.sendCard, 0); set("hint_connected", "opacity", T.sendCard, 1);
  set("count2", "opacity", T.sendCard, 0); set("count3", "opacity", T.sendCard, 1);
  glyphSwap("pin3s3glyph", "pin3num", 3, T.sendCard);

  // send on the bar: Send goes off, "Sending notes 3/3", and each pin's number swaps to a spinner, one after another
  press("barSendOn", T.sendAll);
  to("barSendOn", "vis", T.sendAll, 0, M.status); to("barSendOff", "vis", T.sendAll, 1, M.status);
  hintSwap("hint_connected", "hint_sending", T.sendAll);
  [["pin1s2disc", "pin1s2glyph"], ["pin2s2disc", "pin2s2glyph"], ["pin3s3disc", "pin3num"]].forEach(function (p, k) {
    var t = T.sendAll + k * STAGGER, pin = k + 1;
    discSwap(p[0], "pin" + pin + "s6disc", t); glyphSwap(p[1], "pin" + pin + "s6glyph", pin, t);
  });
  // next poll: "Claude is working…", and the glow and frost crossfade to green (easeInOut 0.8), all at once
  hintSwap("hint_sending", "hint_working", T.working);
  hide("overlay5", T.working, M.palette); show("overlay6", T.working, M.palette);
  hide("scrim5", T.working, M.palette); show("scrim6", T.working, M.palette);
  // each pin resolves: spinner → check, disc to green (snappy 0.25)
  T.check.forEach(function (t, k) {
    var pin = k + 1;
    discSwap("pin" + pin + "s6disc", "pin" + pin + "s7disc", t); glyphSwap("pin" + pin + "s6glyph", "pin" + pin + "s7glyph", pin, t);
  });
  // the agent's own status, "Changes applied, reinstalling": glow back to blue
  hintSwap("hint_working", "hint_applied", T.applied);
  hide("overlay6", T.applied, M.palette); show("overlay7", T.applied, M.palette);
  hide("scrim6", T.applied, M.palette); show("scrim7", T.applied, M.palette);
  // the elapsed counts on through every stage, rolling each digit that changes (numericText, snappy 0.3)
  LINES.forEach(function (l) {
    (l.values || []).forEach(function (v, k) {
      var name = "hint_" + l.name + "_" + v, at = S + v, next = at + 1;
      if (k === 0) always(name);
      else { show(name, at, M.tick); set(name, "y", at, HINT_Y, HINT_Y); to(name, "y", at, 0, M.tick); set(name, "blur", at, HINT_BLUR, HINT_BLUR); to(name, "blur", at, 0, M.tick); }
      if (k < l.values.length - 1) { hide(name, next, M.tick); to(name, "y", next, -HINT_Y, M.tick); to(name, "blur", next, HINT_BLUR, M.tick); }
    });
  });

  // back: pressed, then the overlay and its marks fade (easeInOut 0.3), the chrome sinks 48pt, and the launcher
  // returns showing "Done · 3 changes" (scale 0.8 → 1 + fade, snappy 0.3)
  press("barBack", T.exit);
  ["overlay7", "scrim7", "loop", "sel2", "sel3", "pin1s7disc", "pin1s7glyph", "pin2s7disc", "pin2s7glyph", "pin3s7disc", "pin3s7glyph"]
    .forEach(function (nm) { hide(nm, T.exit, M.backdrop); });
  ["hint"].concat(BAR_PARTS).forEach(function (nm) { chromeExit(nm, T.exit); });
  set("launcherRow", "w", T.exit, LAUNCHER.done); set("titleAnnotate", "opacity", T.exit, 0); set("titleDone", "opacity", T.exit, 1);
  set("launcher", "scale", T.exit, HIDDEN_SCALE); show("launcher", T.exit, M.mode); to("launcher", "scale", T.exit, 1, M.mode);
  // the app reloads with the edits
  hide("body", T.reload, M.app); show("bodyFinal", T.reload, M.app);
  // the final stage ends: the same capsule's title and width go back to "Annotate" (snappy 0.25)
  // (the original recording shows the titles blur as they replace each other, ~0.2 s)
  to("launcherRow", "w", T.idle, LAUNCHER.annotate, M.status);
  hide("titleDone", T.idle, M.status); to("titleDone", "blur", T.idle, HINT_BLUR, M.status);
  show("titleAnnotate", T.idle, M.status); set("titleAnnotate", "blur", T.idle, HINT_BLUR); to("titleAnnotate", "blur", T.idle, 0, M.status);

  // ---------- Render ----------
  var TYPED_X = 54;
  var list = Object.keys(tracks).map(function (k) { return tracks[k]; });
  list.forEach(function (tr) { tr.keys.sort(function (a, b) { return a[0] - b[0]; }); });   // stable: same-time keys keep their order
  function render(t) {
    var state = new Map();
    list.forEach(function (tr) {
      var s = state.get(tr.node) || {};
      s[tr.prop] = value(tr, t);
      state.set(tr.node, s);
    });
    state.forEach(function (s, node) {
      var op = (s.opacity != null ? s.opacity : 1) * (s.vis != null ? s.vis : 1);
      if (s.press) op *= 1 - 0.4 * s.press;   // ChromeButtonStyle.pressedOpacity 0.6
      node.style.opacity = Math.max(0, Math.min(1, op)).toFixed(3);
      node.style.visibility = op <= 0.001 ? "hidden" : "visible";
      var tf = "";
      if (s.y) tf += "translateY(" + s.y.toFixed(2) + "px) ";
      if (s.scale != null && s.scale !== 1) tf += "scale(" + s.scale.toFixed(4) + ")";
      node.style.transform = tf;
      node.style.filter = s.blur > 0.01 ? "blur(" + s.blur.toFixed(2) + "px)" : "";
      if (s.draw != null) loopPath.style.strokeDashoffset = (1 - Math.max(0, Math.min(1, s.draw))).toFixed(4);
      if (s.reveal != null) node.style.clipPath = "inset(0 " + (546 - TYPED_X - s.reveal - 1).toFixed(2) + "px 0 0)";
      if (s.w != null) { node.style.width = s.w.toFixed(2) + "px"; node.style.left = (CX - s.w / 2).toFixed(2) + "px"; }
    });
  }
  // layers with no track stay hidden
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
