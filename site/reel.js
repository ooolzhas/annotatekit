/* annotatekit.com hero demo: the Figma storyboard ("Frame 1046") played as live layers. reel-layers.js holds every
   vector cut straight from Figma's SVG export (tools/hero-html/build.py), positioned in one 546 x 890 "stage" (the
   418 x 890 phone plus 64pt each side, where the glass card overhangs it). This file stacks them, draws the glass
   with backdrop-filter (Figma's glass doesn't survive export), and runs one timeline that also drives the terminal
   beside the phone. Times are seconds into the loop. */
(function () {
  "use strict";

  var host = document.querySelector(".hero-phone");
  var SVG = window.REEL_SVG, GLASS = window.REEL_GLASS, TYPED = window.REEL_TYPED;
  if (!host || !SVG) return;

  var LOOP = 15.2;

  // ---------- Layers, bottom to top ----------

  var ORDER = [
    "bezel", "base", "body", "bodyFinal",
    "overlay2", "overlay3", "overlay5", "overlay6", "overlay7",
    "scrim3", "scrim5", "scrim6", "scrim7",
    "loop", "sel2", "pin1", "pin2", "sel3", "marks5", "marks6", "marks7",
    "hint2", "hint5", "hint6", "hint7",
    "toolbar2", "toolbar5", "toolbar6",
    "pillAnnotate", "pillDone",
    "card3", "card4", "typed",
  ];
  // Groups that move as one (the card) get a shared wrapper; everything else sits on the stage directly.
  var CARD = { card3: 1, card4: 1, typed: 1 };

  var stage = document.createElement("div");
  stage.className = "reel";
  stage.setAttribute("aria-hidden", "true");
  var cardWrap = document.createElement("div");
  cardWrap.className = "reel-card";
  var el = {};

  // Figma's Liquid Glass recipe, per shape: a blurred backdrop, its four fills (two of them blended) and its three
  // inner shadows. The card is the same component at 1.5x, so its shadow lengths scale with it.
  function glass(g, scale) {
    var parts = [];
    var base = "left:" + g.x + "px;top:" + g.y + "px;width:" + g.w + "px;height:" + g.h + "px;border-radius:" + g.r + "px;";
    ["reel-glass", "reel-glass-rim"].forEach(function (cls) {
      var d = document.createElement("div");
      d.className = cls;
      d.style.cssText = base + "--k:" + scale + ";";
      parts.push(d);
    });
    return parts;
  }

  ORDER.forEach(function (name) {
    var layer = document.createElement("div");
    layer.className = "reel-layer reel-" + name;
    (GLASS[name] || []).forEach(function (g) {
      glass(g, CARD[name] ? 1.5 : 1).forEach(function (p) { layer.appendChild(p); });
    });
    var holder = document.createElement("div");
    holder.className = "reel-svg";
    holder.innerHTML = SVG[name];
    layer.appendChild(holder);
    el[name] = layer;
    (CARD[name] ? cardWrap : stage).appendChild(layer);
  });
  stage.appendChild(cardWrap);
  host.appendChild(stage);

  // ---------- Timeline ----------

  // Each track is [element, property, [[t, value, ease], ...]]; the ease shapes the segment leaving that key.
  var EASE = {
    hold: null,
    lin: function (x) { return x; },
    out: function (x) { return 1 - Math.pow(1 - x, 3); },
    io: function (x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; },
    back: function (x) { var c = 1.4; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); },
  };
  var tracks = [];
  function track(name, prop, keys) { tracks.push([name, prop, keys]); }
  function fade(name, on, off, d) {   // visible from `on` to `off` (or the loop's end), fading over d
    d = d || 0.3;
    var k = on < 0 ? [[0, 1, "hold"]] : [[0, 0, "hold"], [on, 0, "io"], [on + d, 1, "hold"]];
    if (off != null) k.push([off, 1, "io"], [off + d, 0, "hold"]);
    track(name, "opacity", k);
  }
  function pop(name, t, ox, oy) {      // scale in from its own centre with a little overshoot
    fade(name, t, null, 0.15);
    track(name, "scale", [[0, 0.4, "hold"], [t, 0.4, "back"], [t + 0.35, 1, "hold"]]);
    el[name].style.transformOrigin = ox + "px " + oy + "px";
  }

  var T = {
    press: 0.9, enter: 1.1, loop0: 1.6, loop1: 2.4, sel2: 2.9, toolbar: 3.3, sel3: 4.3, cardIn: 4.5,
    type0: 5.5, type1: 6.9, cardOut: 7.4, sent: 7.6, sendAll: 8.8, applied: 11.4, dismiss: 12.8, reset: 14.6,
  };
  var OVER = T.dismiss;   // everything of the overlay leaves together

  // the app; the edited body crossfades in as the overlay leaves
  fade("bezel", -1); fade("base", -1);
  track("body", "opacity", [[0, 1, "hold"], [OVER + 0.1, 1, "io"], [OVER + 0.5, 0, "hold"], [T.reset, 0, "io"], [T.reset + 0.4, 1, "hold"]]);
  track("bodyFinal", "opacity", [[0, 0, "hold"], [OVER + 0.1, 0, "io"], [OVER + 0.5, 1, "hold"], [T.reset, 1, "io"], [T.reset + 0.4, 0, "hold"]]);
  // the Annotate pill: pressed, gone as the overlay comes in, back for the next loop; Done replaces it at the end
  track("pillAnnotate", "opacity", [[0, 1, "hold"], [T.enter, 1, "io"], [T.enter + 0.2, 0, "hold"], [T.reset + 0.2, 0, "io"], [T.reset + 0.5, 1, "hold"]]);
  track("pillAnnotate", "scale", [[0, 1, "hold"], [T.press, 1, "out"], [T.press + 0.12, 0.93, "out"], [T.press + 0.35, 1, "hold"]]);
  el.pillAnnotate.style.transformOrigin = "273px 826px";
  fade("pillDone", OVER + 0.35, T.reset, 0.3);

  // the overlay's states: dim + glow, then card, connected, working (green), applied
  fade("overlay2", T.enter, T.cardIn - 0.1, 0.4);
  fade("overlay3", T.cardIn - 0.1, T.sent, 0.3);
  fade("overlay5", T.sent, T.sendAll, 0.3);
  fade("overlay6", T.sendAll, T.applied, 0.5);
  fade("overlay7", T.applied, OVER, 0.5);
  fade("scrim3", T.cardIn - 0.1, T.sent, 0.3);
  fade("scrim5", T.sent, T.sendAll, 0.3);
  fade("scrim6", T.sendAll, T.applied, 0.5);
  fade("scrim7", T.applied, OVER, 0.3);

  // marks: the loop is drawn round the title, then the bar and the button are picked
  fade("loop", T.loop0, T.sent, 0.05);
  track("loop", "sweep", [[0, 0, "hold"], [T.loop0, 0, "io"], [T.loop1, 1, "hold"]]);
  pop("pin1", T.loop1, 235, 166);
  pop("sel2", T.sel2, 419.5, 360);
  pop("pin2", T.sel2 + 0.12, 434, 348);
  pop("sel3", T.sel3, 273, 624);
  ["pin1", "sel2", "pin2", "sel3"].forEach(function (n) { track(n, "opacity", [[T.sent, 1, "io"], [T.sent + 0.3, 0, "hold"]]); });
  track("loop", "opacity", [[T.sent, 1, "io"], [T.sent + 0.3, 0, "hold"]]);
  fade("marks5", T.sent, T.sendAll, 0.3);
  fade("marks6", T.sendAll, T.applied, 0.3);
  fade("marks7", T.applied, OVER, 0.3);

  // hint and toolbar
  fade("hint2", T.toolbar, T.cardIn - 0.2, 0.3);
  fade("toolbar2", T.toolbar, T.cardIn - 0.2, 0.3);
  track("toolbar2", "y", [[0, 24, "hold"], [T.toolbar, 24, "out"], [T.toolbar + 0.45, 0, "hold"]]);
  fade("hint5", T.sent + 0.3, T.sendAll, 0.3);
  fade("toolbar5", T.sent + 0.3, T.sendAll, 0.3);
  fade("hint6", T.sendAll, T.applied, 0.3);
  fade("toolbar6", T.sendAll, OVER, 0.3);
  fade("hint7", T.applied, OVER, 0.3);

  // the glass card jumps up out of the phone's bottom edge, overshoots, settles; drops away on send
  track("card", "y", [[0, 300, "hold"], [T.cardIn, 300, "out"], [T.cardIn + 0.38, -18, "io"], [T.cardIn + 0.7, 0, "hold"],
                      [T.cardOut, 0, "io"], [T.cardOut + 0.45, 320, "hold"]]);
  track("card", "opacity", [[0, 0, "hold"], [T.cardIn, 0, "out"], [T.cardIn + 0.15, 1, "hold"], [T.cardOut + 0.25, 1, "io"], [T.cardOut + 0.45, 0, "hold"]]);
  fade("card3", -1, T.type0, 0.08);
  fade("card4", T.type0, null, 0.08);
  fade("typed", T.type0, null, 0.01);
  var n = TYPED.length - 1;
  var typeKeys = [[0, 0, "hold"]];
  for (var i = 1; i <= n; i++) typeKeys.push([T.type0 + (T.type1 - T.type0) * Math.pow(i / n, 0.9), TYPED[i], "hold"]);
  track("typed", "reveal", typeKeys);

  function value(keys, t) {
    if (t <= keys[0][0]) return keys[0][1];
    for (var i = 0; i < keys.length - 1; i++) {
      var a = keys[i], b = keys[i + 1];
      if (t < b[0]) {
        var e = EASE[a[2]];
        if (!e) return a[1];
        return a[1] + (b[1] - a[1]) * e((t - a[0]) / (b[0] - a[0]));
      }
    }
    return keys[keys.length - 1][1];
  }
  // merge keys per element/property (several helpers may key the same one) and sort them
  var merged = {};
  tracks.forEach(function (tr) {
    var k = tr[0] + "|" + tr[1];
    merged[k] = (merged[k] || []).concat(tr[2]);
  });
  var plan = Object.keys(merged).map(function (k) {
    var p = k.split("|"), keys = merged[k].slice().sort(function (a, b) { return a[0] - b[0]; });
    return { node: p[0] === "card" ? cardWrap : el[p[0]], prop: p[1], keys: keys };
  });

  var TYPED_X = 54;   // the note's left edge on the stage
  function render(t) {
    var state = new Map();
    plan.forEach(function (p) {
      var s = state.get(p.node) || {};
      s[p.prop] = value(p.keys, t);
      state.set(p.node, s);
    });
    state.forEach(function (s, node) {
      if (s.opacity != null) node.style.opacity = s.opacity.toFixed(3);
      var tf = "";
      if (s.y != null) tf += "translateY(" + s.y.toFixed(2) + "px) ";
      if (s.scale != null) tf += "scale(" + s.scale.toFixed(4) + ")";
      if (tf) node.style.transform = tf;
      if (s.sweep != null) node.style.setProperty("--sweep", (s.sweep * 360).toFixed(1) + "deg");
      if (s.reveal != null) node.style.clipPath = "inset(0 " + (546 - TYPED_X - s.reveal - 1).toFixed(2) + "px 0 0)";
    });
  }

  // ---------- Scale, clock, terminal ----------

  function fit() { stage.style.setProperty("--s", host.clientHeight / 890); }
  fit();
  if ("ResizeObserver" in window) new ResizeObserver(fit).observe(host);

  var board = document.querySelector(".hero-media");
  var lines = Array.prototype.slice.call(document.querySelectorAll(".hero-term [data-at]"));
  var SPLIT = [7.9, 12.3];
  function terminal(t) {
    lines.forEach(function (l) {
      var until = l.dataset.until ? parseFloat(l.dataset.until) : Infinity;
      l.classList.toggle("is-on", t >= parseFloat(l.dataset.at) && t < until);
    });
    if (board) board.classList.toggle("is-split", t >= SPLIT[0] && t < SPLIT[1]);
  }

  window.reelSeek = function (t) { render(t); terminal(t); };   // for checking frames by hand
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    render(13.6);   // the finished app, with "Done"
    terminal(Infinity);
    if (board) board.classList.add("is-split");
    return;
  }
  // The clock only runs while the demo is on screen (and the tab is visible: rAF stops on its own), so a visitor who
  // scrolls back finds it where they left it.
  var clock = 0, last = null, visible = true;
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (e) { visible = e[0].isIntersecting; }).observe(host);
  }
  function frame(now) {
    requestAnimationFrame(frame);
    var dt = last == null ? 0 : Math.min(now - last, 100) / 1000;
    last = now;
    if (!visible || window.reelPaused) return;
    clock += dt;
    var t = clock % LOOP;
    render(t);
    terminal(t);
  }
  render(0);
  requestAnimationFrame(frame);
})();
