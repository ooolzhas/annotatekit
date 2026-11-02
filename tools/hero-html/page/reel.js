/* The hero reel: the Figma storyboard ("Frame 1046") as live layers, animated with AnnotateKit's own motion. Every vector
   is cut from Figma's SVG export into reel-layers.js (build.py) on one 546 x 890 stage (the 418 x 890 phone plus 64pt each
   side, where the glass card overhangs it). The motion follows the overlay's source, not the keyframes: springs and
   durations are the ones in Sources/AnnotateKit (see the table at T), and the pacing follows the original Simulator
   recording. record.mjs seeks this page frame by frame (reelSeek) to make site/demo.mov and demo.webm. Times are seconds. */
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
    count: { spring: 0.2, bounce: 0.15 },         // review bar count text: snappy 0.2
    status: { spring: 0.25, bounce: 0.15 },       // LauncherButton.statusAnimation: snappy 0.25 (title + width)
    app: { ease: 0.2 },                           // the app's own hot-reload change (not AnnotateKit)
    ink: { ease: 0.55 },                          // the finger drawing the loop (ink follows it exactly)
  };
  var ENTRANCE = 48, HIDDEN_SCALE = 0.8, BADGE_FROM = 0.3, GLYPH_FROM = 0.5, HINT_Y = 8, HINT_BLUR = 4;

  var T = {
    reveal: 0.3,          // launcher's first appearance
    press: 1.4,           // finger on the launcher (button opacity 0.6 while held)
    enter: 1.65,          // release: overlay in, launcher out, chrome up
    ink0: 2.45,           // the loop is drawn round the title …
    pin1: 3.0,            // … and its pin pops
    pin2: 3.95,           // a tap on the tall bar: selection at once, pin pops, "2 notes"
    pin3: 4.85,           // a tap on the button: selection, "+" pin, the toolbar becomes the comment card
    type0: 5.6, type1: 6.7,
    sendCard: 7.3,        // send on the card: the card becomes the toolbar again ("Claude is connected")
    sendAll: 8.6,         // send on the toolbar: pins spin
    working: 9.6,         // the next status poll: "Claude is working", glow to green
    check: [11.3, 11.7, 12.1],
    applied: 12.4,        // "Changes applied", glow back to blue
    exit: 13.9,           // back: overlay out, launcher back with "Done · 3 changes"
    reload: 14.5,         // the app picks up the edits
    idle: 16.6,           // final stage over: "Done" → "Annotate"
    reset: 17.5,          // loop: back to the unedited app with no launcher
  };
  var LOOP = 18.1;
  window.REEL_LOOP = LOOP;

  // ---------- Layers, bottom to top ----------
  var ORDER = [
    "bezel", "base", "body", "bodyFinal",
    "overlay2", "overlay3", "overlay5", "overlay6", "overlay7",
    "scrim3", "scrim5", "scrim6", "scrim7",
    "loop", "sel2", "sel3",
    "pin1s2disc", "pin1s6disc", "pin1s7disc", "pin2s2disc", "pin2s6disc", "pin2s7disc", "pin3s3disc", "pin3s6disc", "pin3s7disc",
    "pin1s2glyph", "pin1s6glyph", "pin1s7glyph", "pin2s2glyph", "pin2s6glyph", "pin2s7glyph", "pin3s3glyph", "pin3s6glyph", "pin3s7glyph",
    "hint2", "hint5", "hint6", "hint7",
    "toolbar2", "count2", "toolbar5", "toolbar6",
    "pillAnnotate", "pillDone",
    "card3", "card4", "typed",
  ];
  var PIN = { 1: [235, 166], 2: [434, 348], 3: [201, 616] };   // pin centres on the stage
  var CARD = { card3: 1, card4: 1, typed: 1 };
  var CHROME = { hint2: 1, hint5: 1, hint6: 1, hint7: 1, toolbar2: 1, count2: 1, toolbar5: 1, toolbar6: 1 };

  var stage = document.createElement("div");
  stage.className = "reel";
  stage.setAttribute("aria-hidden", "true");
  var el = {};
  function glass(g, scale) {
    var base = "left:" + g.x + "px;top:" + g.y + "px;width:" + g.w + "px;height:" + g.h + "px;border-radius:" + g.r + "px;--k:" + scale + ";";
    return ["reel-glass", "reel-glass-rim"].map(function (cls) {
      var d = document.createElement("div");
      d.className = cls;
      d.style.cssText = base;
      return d;
    });
  }
  ORDER.forEach(function (name) {
    var layer = document.createElement("div");
    layer.className = "reel-layer reel-" + name;
    (GLASS[name] || []).forEach(function (g) { glass(g, CARD[name] ? 1.5 : 1).forEach(function (p) { layer.appendChild(p); }); });
    var holder = document.createElement("div");
    holder.className = "reel-svg";
    holder.innerHTML = SVG[name];
    layer.appendChild(holder);
    el[name] = layer;
    stage.appendChild(layer);
  });
  host.appendChild(stage);

  // ---------- Curves ----------
  function bezier(x1, y1, x2, y2) {   // CSS cubic-bezier, solved for x by Newton then bisection
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
    if (dt <= 0) return 0;
    if (!m) return 1;   // instant
    if (m.ease) return EASE_IN_OUT(dt / m.ease);
    var w = 2 * Math.PI / m.spring, z = 1 - m.bounce;
    if (z >= 1) return 1 - (1 + w * dt) * Math.exp(-w * dt);
    var wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * dt) * (Math.cos(wd * dt) + (z * w / wd) * Math.sin(wd * dt));
  }

  // ---------- Tracks ----------
  // A track is a property's starting value plus changes [t, to, motion]; each change runs from the previous target.
  var tracks = {};
  function track(name, prop, from) { var k = name + "|" + prop; tracks[k] = tracks[k] || { node: el[name], prop: prop, from: from, keys: [] }; return tracks[k]; }
  function to(name, prop, t, value, motion, from) {
    var tr = track(name, prop, from);
    tr.keys.push([t, value, motion]);
  }
  function value(tr, t) {
    var v = tr.from, prev = tr.from;
    tr.keys.sort(function (a, b) { return a[0] - b[0]; });
    for (var i = 0; i < tr.keys.length; i++) {
      var k = tr.keys[i];
      if (t < k[0]) break;
      v = prev + (k[1] - prev) * progress(k[2], t - k[0]);
      prev = k[1];
    }
    return v;
  }
  function show(name, t, motion) { to(name, "opacity", t, 1, motion, 0); }
  function hide(name, t, motion) { to(name, "opacity", t, 0, motion, 0); }
  function always(name) { track(name, "opacity", 1); }
  function origin(name, x, y) { el[name].style.transformOrigin = x + "px " + y + "px"; }

  // the overlay's chrome enters from 48pt below; when swapped out it shrinks to 0.8 and fades (OverlayRoot.swapTransition)
  function chromeIn(name, t) { show(name, t, M.mode); to(name, "y", t, 0, M.mode, ENTRANCE); }
  function chromeSwapOut(name, t) { hide(name, t, M.mode); to(name, "scale", t, HIDDEN_SCALE, M.mode, 1); }
  function chromeExit(name, t) { hide(name, t, M.mode); to(name, "y", t, ENTRANCE, M.mode, 0); }
  // the hint line's headline swap (HintSwap): in from 8pt below and blurred, out 8pt up, smooth 0.45
  function hintIn(name, t) { show(name, t, M.hint); to(name, "y", t, 0, M.hint, HINT_Y); to(name, "blur", t, 0, M.hint, HINT_BLUR); }
  function hintOut(name, t) { hide(name, t, M.hint); to(name, "y", t, -HINT_Y, M.hint, 0); to(name, "blur", t, HINT_BLUR, M.hint, 0); }
  // a pin pops in from its centre (badgeAppearance), then changes face: disc crossfades, glyph scales 0.5 + fades
  function pinPop(n, state, t) {
    ["disc", "glyph"].forEach(function (p) {
      var name = "pin" + n + "s" + state + p;
      show(name, t, M.badge); to(name, "scale", t, 1, M.badge, BADGE_FROM); origin(name, PIN[n][0], PIN[n][1]);
    });
  }
  function pinFace(n, from, toState, t) {
    var a = "pin" + n + "s" + from, b = "pin" + n + "s" + toState;
    hide(a + "disc", t, M.glyph); show(b + "disc", t, M.glyph);
    hide(a + "glyph", t, M.glyph); to(a + "glyph", "scale", t, GLYPH_FROM, M.glyph, 1);
    show(b + "glyph", t, M.glyph); to(b + "glyph", "scale", t, 1, M.glyph, GLYPH_FROM);
    [a + "glyph", b + "glyph"].forEach(function (g) { origin(g, PIN[n][0], PIN[n][1]); });
  }

  // ---------- The story ----------
  always("bezel"); always("base"); always("body");
  // launcher: first reveal (scale 0.8 + fade, snappy 0.3), pressed (opacity 0.6, instant), leaves as the overlay comes in
  origin("pillAnnotate", 273, 826); origin("pillDone", 273, 826);
  show("pillAnnotate", T.reveal, M.mode); to("pillAnnotate", "scale", T.reveal, 1, M.mode, HIDDEN_SCALE);
  to("pillAnnotate", "press", T.press, 1, null, 0); to("pillAnnotate", "press", T.enter, 0, null);
  hide("pillAnnotate", T.enter, M.mode); to("pillAnnotate", "scale", T.enter, HIDDEN_SCALE, M.mode);

  // overlay in (easeInOut 0.3): dim + glow + frost; chrome rises 48pt (snappy 0.3)
  show("overlay2", T.enter, M.backdrop);
  chromeIn("toolbar2", T.enter); chromeIn("hint2", T.enter);

  // the loop is drawn, its pin pops; the bar is tapped: selection at once, pin pops, count appears
  show("loop", T.ink0, null); to("loop", "sweep", T.ink0, 1, M.ink, 0);
  pinPop(1, 2, T.pin1);
  show("sel2", T.pin2, null); pinPop(2, 2, T.pin2);
  show("count2", T.pin2, M.count);

  // the button is tapped: selection, "+" pin, and the toolbar becomes the card (card in from 48pt; bar out to 0.8)
  show("sel3", T.pin3, null); pinPop(3, 3, T.pin3);
  origin("toolbar2", 273, 822); origin("count2", 273, 822); origin("hint2", 273, 790);
  ["toolbar2", "count2", "hint2"].forEach(function (n) { chromeSwapOut(n, T.pin3); });
  hide("overlay2", T.pin3, M.backdrop); show("overlay3", T.pin3, M.backdrop); show("scrim3", T.pin3, M.backdrop);
  origin("card3", 273, 767); origin("card4", 273, 767); origin("typed", 273, 767);
  chromeIn("card3", T.pin3);
  // typing: the field's placeholder goes with the first key; the send button turns blue with it
  show("card4", T.type0, null); hide("card3", T.type0, null); chromeIn("card4", T.pin3); chromeIn("typed", T.pin3);
  to("card4", "opacity", T.pin3, 0, null);   // card4 is only the typed state
  show("typed", T.type0, null);
  var n = TYPED.length - 1;
  for (var i = 1; i <= n; i++) to("typed", "reveal", T.type0 + (T.type1 - T.type0) * Math.pow(i / n, 0.95), TYPED[i], null, 0);

  // send on the card: the card shrinks away (0.8 + fade), the toolbar and "Claude is connected" rise in
  ["card4", "typed"].forEach(function (c) { chromeSwapOut(c, T.sendCard); });
  hide("overlay3", T.sendCard, M.backdrop); hide("scrim3", T.sendCard, M.backdrop);
  show("overlay5", T.sendCard, M.backdrop); show("scrim5", T.sendCard, M.backdrop);
  chromeIn("toolbar5", T.sendCard); chromeIn("hint5", T.sendCard);

  // send on the toolbar: every pin's glyph swaps to a spinner (snappy 0.25); the bar's send greys out
  pinFace(1, 2, 6, T.sendAll); pinFace(2, 2, 6, T.sendAll); pinFace(3, 3, 6, T.sendAll);
  hide("toolbar5", T.sendAll, M.count); show("toolbar6", T.sendAll, M.count);
  // next poll: "Claude is working", and the glow and frost crossfade to green (easeInOut 0.8)
  hintOut("hint5", T.working); hintIn("hint6", T.working);
  hide("overlay5", T.working, M.palette); show("overlay6", T.working, M.palette);
  hide("scrim5", T.working, M.palette); show("scrim6", T.working, M.palette);
  // each pin resolves: spinner → check, disc to green (snappy 0.25)
  pinFace(1, 6, 7, T.check[0]); pinFace(2, 6, 7, T.check[1]); pinFace(3, 6, 7, T.check[2]);
  // done: "Changes applied", glow back to blue
  hintOut("hint6", T.applied); hintIn("hint7", T.applied);
  hide("overlay6", T.applied, M.palette); show("overlay7", T.applied, M.palette);
  hide("scrim6", T.applied, M.palette); show("scrim7", T.applied, M.palette);

  // back: the overlay and its marks fade (easeInOut 0.3), the chrome sinks 48pt, the launcher returns with "Done"
  ["overlay7", "scrim7", "loop", "sel2", "sel3", "pin1s7disc", "pin1s7glyph", "pin2s7disc", "pin2s7glyph", "pin3s7disc", "pin3s7glyph"]
    .forEach(function (n) { hide(n, T.exit, M.backdrop); });
  ["toolbar6", "hint7"].forEach(function (n) { to(n, "scale", T.exit, 1, null); chromeExit(n, T.exit); });
  show("pillDone", T.exit, M.mode); to("pillDone", "scale", T.exit, 1, M.mode, HIDDEN_SCALE);
  // the app reloads with the edits
  hide("body", T.reload, M.app); show("bodyFinal", T.reload, M.app);
  // the final stage ends: the launcher's title and width go back to "Annotate" (snappy 0.25)
  hide("pillDone", T.idle, M.status); to("pillDone", "scale", T.idle, 0.92, M.status);
  show("pillAnnotate", T.idle, M.status); to("pillAnnotate", "scale", T.idle, 1, M.status);
  // loop: the reel starts over on the unedited app with the launcher not yet shown
  hide("pillAnnotate", T.reset, M.mode); to("pillAnnotate", "scale", T.reset, HIDDEN_SCALE, M.mode);
  show("body", T.reset, M.backdrop); hide("bodyFinal", T.reset, M.backdrop);

  // ---------- Render ----------
  var TYPED_X = 54;
  var list = Object.keys(tracks).map(function (k) { return tracks[k]; });
  function render(t) {
    var state = new Map();
    list.forEach(function (tr) {
      var s = state.get(tr.node) || {};
      s[tr.prop] = value(tr, t);
      state.set(tr.node, s);
    });
    state.forEach(function (s, node) {
      var op = s.opacity != null ? s.opacity : 1;
      if (s.press) op *= 1 - 0.4 * s.press;   // ChromeButtonStyle.pressedOpacity 0.6
      node.style.opacity = Math.max(0, Math.min(1, op)).toFixed(3);
      node.style.visibility = op <= 0.001 ? "hidden" : "visible";
      var tf = "";
      if (s.y != null) tf += "translateY(" + s.y.toFixed(2) + "px) ";
      if (s.scale != null) tf += "scale(" + s.scale.toFixed(4) + ")";
      node.style.transform = tf;
      node.style.filter = s.blur ? "blur(" + s.blur.toFixed(2) + "px)" : "";
      if (s.sweep != null) node.style.setProperty("--sweep", (Math.max(0, Math.min(1, s.sweep)) * 360).toFixed(1) + "deg");
      if (s.reveal != null) node.style.clipPath = "inset(0 " + (546 - TYPED_X - s.reveal - 1).toFixed(2) + "px 0 0)";
    });
  }
  // layers with no track stay hidden
  ORDER.forEach(function (name) { if (!list.some(function (tr) { return tr.node === el[name]; })) el[name].style.visibility = "hidden"; });

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
