/* annotatekit.com hero demo: someone annotates an iPhone app, Claude Code applies the notes.
   Drawn after a real session recorded in the Simulator, simplified to a wireframe app.
   Self-contained: builds its DOM inside #demo, styles live in demo.css (all .ak-*). */
(function () {
  "use strict";

  var mount = document.getElementById("demo");
  if (!mount) return;

  var ARROW_UP = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10.5V1.8M2.2 5.4 6 1.6l3.8 3.8"/></svg>';
  var CHEVRON_L = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7.8 2 3.8 6l4 4"/></svg>';
  var CLIP = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M8.6 5.6 5.4 8.8a2 2 0 0 1-2.9-2.9l4-4a1.3 1.3 0 0 1 1.9 1.9L4.6 7.6"/></svg>';
  var CROSS = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3 3l6 6M9 3 3 9"/></svg>';
  var UPDOWN = '<svg viewBox="0 0 6 8" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 2.8 3 1l2 1.8M1 5.2 3 7l2-1.8"/></svg>';
  var CHECK = '<svg class="ak-check" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 6.3 5 8.6 9.6 3.6"/></svg>';
  // The hand-drawn loop around the title, in screen points (228 x 494)
  var LOOP = "M88 63C72 53 30 53 16 62C4 70 8 87 36 91C62 94 90 88 92 76C94 66 82 60 66 60";

  function marker(cls, n) {
    return '<div class="ak-marker ' + cls + '"><span class="ak-num">' + n + '</span><i class="ak-spin"></i>' + CHECK + "</div>";
  }
  function sk(x, y, w, h, dark) {
    return '<i class="ak-sk' + (dark ? " ak-dark" : "") + '" style="left:' + x + "px;top:" + y + "px;width:" + w + "px;height:" + h + 'px"></i>';
  }
  function row(top, color) {
    return '<div class="ak-row" style="top:' + top + 'px"><i class="ak-ico" style="background:' + color + '"></i>' + sk(40, 15, 74, 7, true) + sk(158, 16, 30, 6) + "</div>";
  }
  function line(cls, glyph, html) {
    return '<div class="ak-line ' + cls + '"><span class="ak-g">' + glyph + "</span>" + html + "</div>";
  }

  mount.innerHTML =
    '<div class="ak-demo" aria-hidden="true"><div class="ak-stage">' +
      '<div class="ak-phone"><div class="ak-screen">' +
        '<div class="ak-content">' +
          '<span class="ak-time">9:41</span><span class="ak-sicons"><i></i><i></i></span>' +
          sk(16, 48, 74, 6) +
          '<div class="ak-title">Today</div>' +
          '<div class="ak-card" style="top:98px;height:96px">' +
            sk(14, 14, 46, 6) + sk(14, 30, 44, 12, true) + sk(76, 30, 54, 12, true) + sk(14, 47, 26, 5) + sk(76, 47, 26, 5) +
            '<div class="ak-chart"><i style="height:45%"></i><i style="height:70%"></i><i style="height:55%"></i><i style="height:85%"></i><i style="height:40%"></i><i style="height:65%"></i><i style="height:90%"></i></div>' +
          "</div>" +
          '<div class="ak-card" style="top:206px;height:76px">' + row(0, "#FF9F0A") + row(38, "#BF5AF2") + "</div>" +
          '<div class="ak-button"><i></i></div>' +
        "</div>" +
        '<div class="ak-dim"></div><div class="ak-glow"></div>' +
        '<svg class="ak-ink" viewBox="0 0 228 494"><path class="ak-loop" d="' + LOOP + '"/></svg>' +
        '<div class="ak-outline"></div>' +
        marker("ak-m1", 1) + marker("ak-m2", 2) +
        '<div class="ak-hint"><i class="ak-dot"></i><span class="ak-hint-text"></span><span class="ak-hint-meta"></span></div>' +
        '<div class="ak-bar"><span class="ak-circle ak-glass">' + CHEVRON_L + '</span><span class="ak-count ak-glass"></span><span class="ak-circle ak-glass ak-send">' + ARROW_UP + "</span></div>" +
        '<div class="ak-composer ak-glass"><div class="ak-field"><span class="ak-typed"></span><span class="ak-placeholder">Describe the change</span><span class="ak-caret"></span></div>' +
          '<div class="ak-tools"><span class="ak-circle">' + CLIP + '</span><span class="ak-chip">Fix' + UPDOWN + '</span><span class="ak-gap"></span>' +
          '<span class="ak-circle">' + CROSS + '</span><span class="ak-circle ak-ok">' + ARROW_UP + "</span></div></div>" +
        '<div class="ak-pill"><i class="ak-dot"></i>Annotate</div>' +
        '<div class="ak-finger"><div class="ak-finger-in"></div><div class="ak-ripple"></div></div>' +
        '<div class="ak-island"></div><div class="ak-homebar"></div>' +
      "</div></div>" +
      '<div class="ak-term"><div class="ak-term-head"><i></i><i></i><i></i><span class="ak-term-title">Claude Code</span></div><div class="ak-term-body">' +
        line("", '<span class="ak-dim-t">&gt;</span>', "Apply my annotations as they come in") +
        line("ak-dim-t", '<span class="ak-live">⏺</span>', "Listening for notes from the app…") +
        line("ak-later ak-t-recv", '<span class="ak-c-blue">⏺</span>', '<span class="ak-b">2 pins</span> on 1 screen · iPhone 17 Pro') +
        line("ak-later ak-t-edit", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">Edit</span> TodayView.swift') +
        line("ak-later ak-t-edit2 ak-dim-t", "", "⎿  Updated 2 lines") +
        line("ak-later ak-t-r1", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">annotation_resolve</span> 1 <span class="ak-str">"title → .largeTitle"</span>') +
        line("ak-later ak-t-r2", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">annotation_resolve</span> 2 <span class="ak-str">"button → accent"</span>') +
        line("ak-later ak-t-work ak-c-orange", '<span class="ak-star">✻</span>', "Working…") +
      "</div></div>" +
    "</div></div>";

  var root = mount.firstChild;
  function $(sel) { return root.querySelector(sel); }
  var el = {
    stage: $(".ak-stage"), screen: $(".ak-screen"), content: $(".ak-content"),
    loop: $(".ak-loop"), ink: $(".ak-ink"), outline: $(".ak-outline"),
    m1: $(".ak-m1"), m2: $(".ak-m2"),
    hint: $(".ak-hint"), hintText: $(".ak-hint-text"), hintMeta: $(".ak-hint-meta"),
    bar: $(".ak-bar"), count: $(".ak-count"),
    composer: $(".ak-composer"), typed: $(".ak-typed"),
    pill: $(".ak-pill"), finger: $(".ak-finger"),
    recv: $(".ak-t-recv"), edit: $(".ak-t-edit"), edit2: $(".ak-t-edit2"),
    r1: $(".ak-t-r1"), r2: $(".ak-t-r2"), work: $(".ak-t-work")
  };
  var loopLen = el.loop.getTotalLength();

  // ---------- Scaling: the stage has a fixed size and is scaled to the column ----------

  // Phones stack the terminal under the phone. From 1000px the demo fills the fixed preview pane:
  // the phone-only stage (260 x 526) is centered and scaled above a terminal docked full width
  // along the bottom at real pixel size, like an IDE's built-in terminal.
  var narrowQuery = window.matchMedia("(max-width: 479px)");
  var dockedQuery = window.matchMedia("(min-width: 1000px)");
  var term = $(".ak-term");
  function layout() {
    var narrow = narrowQuery.matches, docked = dockedQuery.matches;
    root.classList.toggle("ak-narrow", narrow);
    root.classList.toggle("ak-docked", docked);
    var home = docked ? root : el.stage;
    if (term.parentNode !== home) home.appendChild(term);
    if (docked) {
      var aw = root.clientWidth, ah = root.clientHeight - term.offsetHeight;
      if (!aw || ah <= 0) return;
      var s = Math.min(aw / 300, ah / 566);
      root.style.setProperty("--ak-scale", String(s));
      root.style.setProperty("--ak-x", (aw - 260 * s) / 2 + "px");
      root.style.setProperty("--ak-y", (ah - 526 * s) / 2 + "px");
      return;
    }
    var w = root.clientWidth || mount.clientWidth;
    if (w) root.style.setProperty("--ak-scale", String(w / (narrow ? 340 : 560)));
  }
  layout();
  if ("ResizeObserver" in window) new ResizeObserver(layout).observe(root);
  else window.addEventListener("resize", layout);
  if (narrowQuery.addEventListener) {
    narrowQuery.addEventListener("change", layout);
    dockedQuery.addEventListener("change", layout);
  }

  // ---------- One timeline clock: virtual time that only advances while playing ----------

  var vt = 0, last = 0, raf = 0, playing = false;
  var waits = [], frames = [];
  var CANCEL = {};

  function tick(ts) {
    var dt = last ? Math.min(ts - last, 50) : 16;
    last = ts;
    vt += dt;
    frames.slice().forEach(function (f) { f(vt); });
    for (var i = waits.length - 1; i >= 0; i--) {
      if (waits[i].t <= vt) waits.splice(i, 1)[0].resolve();
    }
    raf = requestAnimationFrame(tick);
  }
  function play() {
    if (playing) return;
    playing = true;
    last = 0;
    root.classList.remove("ak-paused");
    raf = requestAnimationFrame(tick);
  }
  function pause() {
    if (!playing) return;
    playing = false;
    cancelAnimationFrame(raf);
    raf = 0;
    root.classList.add("ak-paused");
  }
  // Story beats are authored in ms and played slightly faster than written (one knob for pacing).
  var PACE = 0.86;
  function wait(ms) {
    return new Promise(function (resolve, reject) {
      waits.push({ t: vt + ms * PACE, resolve: resolve, reject: reject });
    });
  }
  function tween(ms, fn) {
    return new Promise(function (resolve, reject) {
      var start = vt;
      var f = function (now) {
        var p = Math.min((now - start) / ms, 1);
        fn(p);
        if (p >= 1) { frames.splice(frames.indexOf(f), 1); resolve(); }
      };
      f.reject = reject;
      frames.push(f);
      fn(0);
    });
  }
  function cancelAll() {
    waits.splice(0).forEach(function (w) { w.reject(CANCEL); });
    frames.splice(0).forEach(function (f) { if (f.reject) f.reject(CANCEL); });
    stopTimer();
  }

  // ---------- Small scene helpers ----------

  function on(node, yes) { node.classList.toggle("ak-on", yes !== false); }
  function cls(node, name, yes) { node.classList.toggle(name, yes !== false); }

  function fingerTo(x, y) { el.finger.style.transform = "translate(" + x + "px," + y + "px)"; }
  async function moveFinger(x, y, ms) {
    fingerTo(x, y);
    await wait(ms || 480);
  }
  // Move the finger without animating it (it is invisible at that moment).
  function fingerJump(x, y) {
    cls(el.finger, "ak-drag");
    fingerTo(x, y);
    void el.finger.offsetWidth;
    cls(el.finger, "ak-drag", false);
  }
  async function tap() {
    cls(el.finger, "ak-down");
    await wait(120);
    cls(el.finger, "ak-down", false);
    cls(el.finger, "ak-tap", false);
    void el.finger.offsetWidth;
    cls(el.finger, "ak-tap");
    await wait(140);
  }

  // The hint line above the bar narrates, like the real overlay: a status dot, the text, and a
  // muted detail that can count up the seconds since the send.
  var timer = null;
  function stopTimer() {
    if (timer) { frames.splice(frames.indexOf(timer), 1); timer = null; }
  }
  function hint(text, meta, opts) {
    opts = opts || {};
    el.hintText.textContent = text;
    el.hintMeta.textContent = meta || "";
    cls(el.hint, "ak-nodot", !!opts.noDot);
    on(el.hint);
  }
  function countFrom(start) {
    stopTimer();
    timer = function (now) { el.hintMeta.textContent = Math.max(1, Math.floor((now - start) / 1000)) + "s"; };
    frames.push(timer);
  }

  async function type(text) {
    for (var i = 1; i <= text.length; i++) {
      el.typed.textContent = text.slice(0, i);
      if (i === 1) cls(el.composer, "ak-ready");
      await wait(text[i - 1] === " " ? 44 : 26);
    }
  }

  // The composer card rises, the note types itself, the finger taps ↑ on the card and it leaves.
  async function comment(text, countAfter) {
    on(el.finger, false);
    on(el.hint, false);
    el.typed.textContent = "";
    cls(el.composer, "ak-ready", false);
    on(el.bar, false);
    on(el.composer);
    await wait(320);
    await type(text);
    await wait(180);
    fingerJump(180, 492);
    on(el.finger);
    await moveFinger(197, 453, 340);
    await tap();
    on(el.composer, false);
    el.count.textContent = countAfter;
    cls(el.bar, "ak-can-send");
    await wait(120);
    on(el.bar);
    hint("Claude connected");
  }

  function drawLoop(p) { el.loop.style.strokeDashoffset = String(loopLen * (1 - p)); }

  // ---------- States ----------

  function resetScene() {
    root.classList.add("ak-instant");
    stopTimer();
    [root].concat(Array.prototype.slice.call(root.querySelectorAll("*"))).forEach(function (n) {
      ["ak-on", "ak-annot", "ak-working", "ak-changed", "ak-can-send", "ak-busy", "ak-done", "ak-ready",
       "ak-down", "ak-tap", "ak-drag", "ak-press", "ak-hidden", "ak-gone", "ak-nodot"].forEach(function (c) {
        if (n.classList) n.classList.remove(c);
      });
    });
    el.loop.style.strokeDasharray = String(loopLen);
    drawLoop(0);
    el.ink.style.opacity = "";
    el.typed.textContent = "";
    el.count.textContent = "No notes yet";
    fingerTo(180, 492);
    void root.offsetWidth;
    root.classList.remove("ak-instant");
  }

  // The reduced-motion frame: annotated screen, both notes resolved, the terminal fully printed.
  function renderStatic() {
    resetScene();
    root.classList.add("ak-static");
    cls(el.screen, "ak-annot");
    cls(el.pill, "ak-hidden");
    drawLoop(1);
    on(el.outline); on(el.m1); on(el.m2);
    cls(el.m1, "ak-done"); cls(el.m2, "ak-done");
    on(el.bar);
    el.count.textContent = "2 notes sent";
    hint("Claude is done", "2 notes");
    [el.recv, el.edit, el.edit2, el.r1, el.r2].forEach(function (n) { on(n); });
  }

  // ---------- The story ----------

  async function story() {
    await wait(700);

    // Tap Annotate: the screen freezes, dims and glows; the hint says how to mark things up
    fingerJump(140, 500);
    on(el.finger);
    await moveFinger(114, 460, 450);
    cls(el.pill, "ak-press");
    await tap();
    cls(el.pill, "ak-press", false);
    cls(el.pill, "ak-hidden");
    cls(el.screen, "ak-annot");
    await wait(120);
    on(el.bar);
    hint("Draw, tap or hold to annotate", "", { noDot: true });
    await wait(900);
    hint("Claude connected");
    await wait(300);

    // Draw a loop around the title, then say what should change
    var start = el.loop.getPointAtLength(0);
    await moveFinger(start.x, start.y, 420);
    cls(el.finger, "ak-down");
    cls(el.finger, "ak-drag");
    await tween(720, function (p) {
      var e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      drawLoop(e);
      var pt = el.loop.getPointAtLength(loopLen * e);
      fingerTo(pt.x, pt.y);
    });
    cls(el.finger, "ak-drag", false);
    cls(el.finger, "ak-down", false);
    on(el.m1);
    await wait(120);
    await comment("Make the title bigger", "1 note");
    await wait(200);

    // Tap the button: it gets a white outline and marker 2
    await moveFinger(114, 316, 420);
    await tap();
    on(el.outline); on(el.m2);
    await wait(120);
    await comment("Use the accent color", "2 notes");
    await wait(260);

    // Send: markers spin, the hint counts, the terminal picks it up
    await moveFinger(195, 457, 380);
    await tap();
    on(el.finger, false);
    cls(el.bar, "ak-can-send", false);
    el.count.textContent = "2 notes sent";
    cls(el.m1, "ak-busy"); cls(el.m2, "ak-busy");
    var sent = vt;
    hint("Claude received your notes", "1s");
    countFrom(sent);
    await wait(500);
    on(el.recv);
    await wait(700);

    // Working: the glow turns green and each pin resolves to a green check
    cls(el.screen, "ak-working");
    hint("Editing TodayView.swift", el.hintMeta.textContent);
    on(el.work);
    await wait(350);
    on(el.edit);
    await wait(200);
    on(el.edit2);
    await wait(500);
    on(el.r1);
    cls(el.m1, "ak-done");
    await wait(600);
    on(el.r2);
    cls(el.m2, "ak-done");
    await wait(350);
    stopTimer();
    cls(el.work, "ak-gone");
    cls(el.screen, "ak-working", false);
    hint("Claude is done", "2 notes");
    await wait(1300);

    // Leave annotate mode: the app shows the bigger title and the accent button
    fingerJump(60, 500);
    on(el.finger);
    await moveFinger(33, 457, 380);
    await tap();
    on(el.finger, false);
    cls(el.screen, "ak-annot", false);
    el.ink.style.opacity = "0";
    on(el.outline, false); on(el.m1, false); on(el.m2, false); on(el.bar, false); on(el.hint, false);
    cls(el.pill, "ak-hidden", false);
    await wait(300);
    cls(el.screen, "ak-changed");
    await wait(2000);

    // Fade back to the start
    cls(el.content, "ak-fade");
    [el.recv, el.edit, el.edit2, el.r1, el.r2].forEach(function (n) { cls(n, "ak-gone"); });
    await wait(300 / PACE);
    resetScene();
    cls(el.content, "ak-fade");
    void el.content.offsetWidth;
    cls(el.content, "ak-fade", false);
    await wait(300 / PACE);
  }

  var running = false;
  async function run() {
    if (running) return;
    running = true;
    resetScene();
    try {
      for (;;) await story();
    } catch (e) {
      if (e !== CANCEL) throw e;
    } finally {
      running = false;
    }
  }

  // ---------- Play / pause wiring ----------

  var reduceQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  var inView = false;

  function update() {
    if (reduceQuery.matches) return;
    if (inView && !document.hidden) { play(); run(); }
    else pause();
  }

  function applyMotionPreference() {
    if (reduceQuery.matches) {
      pause();
      cancelAll();
      renderStatic();
    } else {
      root.classList.remove("ak-static");
      update();
    }
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[entries.length - 1].isIntersecting;
      update();
    }, { threshold: 0.15 }).observe(mount);
  } else {
    inView = true;
  }
  document.addEventListener("visibilitychange", update);
  if (reduceQuery.addEventListener) reduceQuery.addEventListener("change", applyMotionPreference);

  resetScene();
  applyMotionPreference();
})();
