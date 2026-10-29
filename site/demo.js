/* annotatekit.com hero demo: someone annotates an iPhone app, Claude Code applies the notes.
   Self-contained: builds its DOM inside #demo, styles live in demo.css (all .ak-*). */
(function () {
  "use strict";

  var mount = document.getElementById("demo");
  if (!mount) return;

  var SCREEN_W = 228;
  var ARROW_UP = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10.5V1.8M2.2 5.4 6 1.6l3.8 3.8"/></svg>';
  var CHEVRON_L = '<svg viewBox="0 0 12 12" fill="none" stroke="#1C1C1E" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7.8 2 3.8 6l4 4"/></svg>';
  var CHECK = '<svg viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10.3 8.8 13 14 7.4"/></svg>';
  var LOOP = "M78 62C62 55 22 56 10 68C2 78 14 90 40 91C64 92 86 86 85 74C84 64 70 59 56 60";

  function marker(cls, n) {
    return '<div class="ak-marker ' + cls + '"><i class="ak-spin"></i><b class="ak-fill-blue"></b><b class="ak-fill-green"></b><span>' + n + "</span>" + CHECK + "</div>";
  }
  function line(cls, glyph, html) {
    return '<div class="ak-line ' + cls + '"><span class="ak-g">' + glyph + "</span>" + html + "</div>";
  }

  mount.innerHTML =
    '<div class="ak-demo" aria-hidden="true"><div class="ak-stage">' +
      '<div class="ak-phone"><div class="ak-screen">' +
        '<div class="ak-content">' +
          '<div class="ak-app">' +
            '<div class="ak-status"><span class="ak-time">9:41</span><span class="ak-sicons"><span class="ak-sig"><i></i><i></i><i></i><i></i></span><span class="ak-batt"></span></span></div>' +
            '<div class="ak-caption">WEDNESDAY, OCT 29</div>' +
            '<div class="ak-title">Today</div>' +
            '<div class="ak-card ak-stats"><div class="ak-label">Activity</div>' +
              '<div class="ak-nums"><div><div class="ak-num-big">8,412</div><div class="ak-num-unit">steps</div></div>' +
              '<div><div class="ak-num-big">7h 20m</div><div class="ak-num-unit">sleep</div></div></div>' +
              '<div class="ak-bars"><i style="transform:scaleY(.45)"></i><i style="transform:scaleY(.7)"></i><i style="transform:scaleY(.55)"></i><i style="transform:scaleY(.85)"></i><i style="transform:scaleY(.4)"></i><i style="transform:scaleY(.65)"></i><i style="transform:scaleY(.9)"></i></div>' +
            "</div>" +
            '<div class="ak-card ak-list">' +
              '<div class="ak-row"><span class="ak-ico ak-ico-o"></span>Morning run<span class="ak-row-detail">5.2 km</span><span class="ak-chev"></span></div>' +
              '<div class="ak-row"><span class="ak-ico ak-ico-p"></span>Read<span class="ak-row-detail">20 min</span><span class="ak-chev"></span></div>' +
            "</div>" +
            '<div class="ak-button"><span class="ak-btn-before">Start workout</span><span class="ak-btn-after">Start workout</span></div>' +
          "</div>" +
          '<div class="ak-dim"></div>' +
          '<div class="ak-glow ak-glow-blue"><i></i></div><div class="ak-glow ak-glow-green"><i></i></div>' +
          '<svg class="ak-ink" viewBox="0 0 228 494"><path class="ak-loop" d="' + LOOP + '"/></svg>' +
          '<div class="ak-outline"></div>' +
          marker("ak-m1", 1) + marker("ak-m2", 2) +
          '<div class="ak-hint">Draw, tap or hold</div>' +
          '<div class="ak-bar"><span class="ak-circle ak-glass">' + CHEVRON_L + '</span><span class="ak-count ak-glass">No notes</span><span class="ak-circle ak-glass ak-send-bar"><b></b>' + ARROW_UP + "</span></div>" +
          '<div class="ak-composer ak-glass"><div class="ak-field"><span class="ak-typed"></span><span class="ak-placeholder">Describe the change</span><span class="ak-caret"></span></div>' +
            '<span class="ak-chip">Fix<svg viewBox="0 0 8 8" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M1.5 3 4 5.5 6.5 3"/></svg></span>' +
            '<span class="ak-send-card">' + ARROW_UP + "</span></div>" +
          '<div class="ak-pill"><div class="ak-pill-body"><i class="ak-dot"></i><svg class="ak-pill-check" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 6.3 5 8.6 9.6 3.6"/></svg><span class="ak-pill-text">Annotate</span></div></div>' +
          '<div class="ak-finger"><div class="ak-finger-in"></div><div class="ak-ripple"></div></div>' +
        "</div>" +
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
    stage: $(".ak-stage"), screen: $(".ak-content"), termBody: $(".ak-term-body"), title: $(".ak-title"),
    loop: $(".ak-loop"), ink: $(".ak-ink"), outline: $(".ak-outline"),
    m1: $(".ak-m1"), m2: $(".ak-m2"), hint: $(".ak-hint"),
    bar: $(".ak-bar"), count: $(".ak-count"),
    composer: $(".ak-composer"), typed: $(".ak-typed"),
    pill: $(".ak-pill"), pillText: $(".ak-pill-text"),
    finger: $(".ak-finger"),
    recv: $(".ak-t-recv"), edit: $(".ak-t-edit"), edit2: $(".ak-t-edit2"),
    r1: $(".ak-t-r1"), r2: $(".ak-t-r2"), work: $(".ak-t-work")
  };
  var loopLen = el.loop.getTotalLength();

  // ---------- Scaling: the stage has a fixed size and is scaled to the column ----------

  var narrowQuery = window.matchMedia("(max-width: 479px)");
  function layout() {
    var narrow = narrowQuery.matches;
    root.classList.toggle("ak-narrow", narrow);
    var w = root.clientWidth || mount.clientWidth;
    if (w) root.style.setProperty("--ak-scale", String(w / (narrow ? 340 : 560)));
  }
  layout();
  if ("ResizeObserver" in window) new ResizeObserver(layout).observe(root);
  else window.addEventListener("resize", layout);
  if (narrowQuery.addEventListener) narrowQuery.addEventListener("change", layout);

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
    frames.splice(0).forEach(function (f) { f.reject(CANCEL); });
  }

  // ---------- Small scene helpers ----------

  function on(node, yes) { node.classList.toggle("ak-on", yes !== false); }
  function cls(node, name, yes) { node.classList.toggle(name, yes !== false); }

  var finger = { x: 0, y: 0 };
  function fingerTo(x, y) {
    finger.x = x; finger.y = y;
    el.finger.style.transform = "translate(" + x + "px," + y + "px)";
  }
  async function moveFinger(x, y, ms) {
    fingerTo(x, y);
    await wait(ms || 480);
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

  // The pill is placed by transform: bottom-right while idle, centered above the bar while narrating.
  var pillSpot = "idle";
  function placePill() {
    var w = el.pill.offsetWidth;
    var x = pillSpot === "idle" ? SCREEN_W - 14 - w : (SCREEN_W - w) / 2;
    var y = pillSpot === "idle" ? 446 : 414;
    el.pill.style.transform = "translate(" + x + "px," + y + "px)";
    return { x: x + w / 2, y: y + 12 };
  }
  async function pillSay(text, opts) {
    opts = opts || {};
    cls(el.pill, "ak-swap");
    await wait(140);
    el.pillText.textContent = text;
    cls(el.pill, "ak-applied", !!opts.applied);
    placePill();
    cls(el.pill, "ak-swap", false);
  }

  // Move the finger without animating it (it is invisible at that moment).
  function fingerJump(x, y) {
    cls(el.finger, "ak-drag");
    fingerTo(x, y);
    void el.finger.offsetWidth;
    cls(el.finger, "ak-drag", false);
  }

  // The composer card slides up, the note types itself, the finger taps ↑ and the card leaves.
  async function comment(text, countAfter) {
    on(el.finger, false);
    el.typed.textContent = "";
    on(el.bar, false);
    on(el.composer);
    await wait(300);
    await type(text);
    await wait(160);
    fingerJump(178, 492);
    on(el.finger);
    await moveFinger(197, 455, 340);
    await tap();
    on(el.composer, false);
    el.count.textContent = countAfter;
    cls(el.bar, "ak-can-send");
    await wait(120);
    on(el.bar);
  }

  async function type(text) {
    for (var i = 1; i <= text.length; i++) {
      el.typed.textContent = text.slice(0, i);
      await wait(text[i - 1] === " " ? 44 : 26);
    }
  }

  function drawLoop(p) {
    el.loop.style.strokeDashoffset = String(loopLen * (1 - p));
  }

  // ---------- States ----------

  function removeGhosts() {
    Array.prototype.forEach.call(root.querySelectorAll(".ak-ghost"), function (n) { n.remove(); });
  }

  function resetScene() {
    root.classList.add("ak-instant");
    [root].concat(Array.prototype.slice.call(root.querySelectorAll("*"))).forEach(function (n) {
      if (n.closest && n.closest(".ak-ghost")) return;
      ["ak-on", "ak-annot", "ak-working", "ak-changed", "ak-can-send", "ak-busy", "ak-done",
       "ak-down", "ak-tap", "ak-drag", "ak-press", "ak-swap", "ak-applied", "ak-hidden", "ak-gone"].forEach(function (c) {
        if (n.classList) n.classList.remove(c);
      });
    });
    el.loop.style.strokeDasharray = String(loopLen);
    drawLoop(0);
    el.ink.style.opacity = "";
    el.title.style.transition = "";
    el.title.style.transform = "";
    el.typed.textContent = "";
    el.count.textContent = "No notes";
    el.pillText.textContent = "Annotate";
    pillSpot = "idle";
    placePill();
    fingerTo(178, 492);
    void root.offsetWidth;
    root.classList.remove("ak-instant");
  }

  // The reduced-motion frame: annotated screen, both notes resolved, the terminal fully printed.
  function renderStatic() {
    resetScene();
    root.classList.add("ak-static");
    cls(el.screen, "ak-annot");
    drawLoop(1);
    on(el.outline); on(el.m1); on(el.m2);
    cls(el.m1, "ak-done"); cls(el.m2, "ak-done");
    on(el.bar); cls(el.bar, "ak-can-send");
    el.count.textContent = "2 notes";
    el.pillText.textContent = "All changes applied";
    cls(el.pill, "ak-applied");
    pillSpot = "narrate";
    placePill();
    [el.recv, el.edit, el.edit2, el.r1, el.r2].forEach(function (n) { on(n); });
  }

  // ---------- The story ----------

  async function story() {
    await wait(600);

    // 1-2. Tap the Annotate pill: the screen freezes, dims and glows
    var pillAt = placePill();
    fingerJump(pillAt.x + 26, pillAt.y + 44);
    on(el.finger);
    await moveFinger(pillAt.x, pillAt.y, 450);
    cls(el.pill, "ak-press");
    await tap();
    cls(el.pill, "ak-press", false);
    cls(el.pill, "ak-hidden");
    cls(el.screen, "ak-annot");
    await wait(120);
    on(el.bar); on(el.hint);
    await wait(380);

    // 3. Draw a loop around the title, then say what should change
    var start = el.loop.getPointAtLength(0);
    await moveFinger(start.x, start.y, 420);
    cls(el.finger, "ak-down");
    cls(el.finger, "ak-drag");
    on(el.hint, false);
    await tween(700, function (p) {
      var e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      drawLoop(e);
      var pt = el.loop.getPointAtLength(loopLen * e);
      fingerTo(pt.x, pt.y);
    });
    cls(el.finger, "ak-drag", false);
    cls(el.finger, "ak-down", false);
    on(el.m1);
    await wait(100);
    await comment("Make the title bigger", "1 note");
    await wait(160);

    // 4. Tap the button, then comment on it
    await moveFinger(118, 356, 400);
    await tap();
    on(el.outline); on(el.m2);
    await wait(100);
    await comment("Use the accent color", "2 notes");
    await wait(260);

    // 5-6. Send: the pill narrates, the terminal streams, the markers resolve
    await moveFinger(201, 465, 360);
    await tap();
    on(el.finger, false);
    el.pillText.textContent = "Sending…";
    pillSpot = "narrate";
    el.pill.style.transition = "none";
    placePill();
    void el.pill.offsetWidth;
    el.pill.style.transition = "";
    cls(el.pill, "ak-hidden", false);
    await wait(500);
    await pillSay("Claude received your notes");
    on(el.recv);
    await wait(550);
    await pillSay("Claude is working…");
    cls(el.screen, "ak-working");
    cls(el.m1, "ak-busy"); cls(el.m2, "ak-busy");
    on(el.work);
    await wait(300);
    on(el.edit);
    await wait(180);
    on(el.edit2);
    await wait(420);
    on(el.r1);
    cls(el.m1, "ak-done");
    await wait(500);
    on(el.r2);
    cls(el.m2, "ak-done");
    await wait(300);
    cls(el.work, "ak-gone");
    cls(el.screen, "ak-working", false);
    await pillSay("All changes applied", { applied: true });
    await wait(850);

    // 7. Annotate mode closes, the app shows the change
    cls(el.screen, "ak-annot", false);
    el.ink.style.opacity = "0";
    on(el.outline, false); on(el.m1, false); on(el.m2, false); on(el.bar, false);
    cls(el.pill, "ak-swap");
    await wait(140);
    el.pillText.textContent = "Annotate";
    cls(el.pill, "ak-applied", false);
    pillSpot = "idle";
    placePill();
    cls(el.pill, "ak-swap", false);
    await wait(300);
    cls(el.screen, "ak-changed");
    await wait(1600);

    // Soft crossfade back to the start: a frozen copy of the last frame fades out over the reset scene
    var ghosts = [el.screen, el.termBody].map(function (n) {
      var g = n.cloneNode(true);
      g.classList.add("ak-ghost");
      n.parentNode.insertBefore(g, n.nextSibling);
      return g;
    });
    // The title shrinks back in place instead of crossfading two sizes of the same word
    ghosts[0].querySelector(".ak-title").style.visibility = "hidden";
    resetScene();
    el.title.style.transition = "none";
    el.title.style.transform = "scale(1.42)";
    void el.title.offsetWidth;
    el.title.style.transition = "transform .7s cubic-bezier(.32, .72, 0, 1)";
    el.title.style.transform = "";
    ghosts.forEach(function (g) { g.style.opacity = "0"; });
    await wait(720 / PACE);
    el.title.style.transition = "";
    removeGhosts();
  }

  var running = false;
  async function run() {
    if (running) return;
    running = true;
    removeGhosts();
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
      removeGhosts();
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
