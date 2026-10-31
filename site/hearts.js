// Hovering "love" in the footer releases small hearts that rise like balloons: buoyancy lifts each one
// against air drag, so it eases off the word and settles into a slow, steady climb; a gentle per-heart
// breeze pushes it sideways with inertia, and it leans into that drift. It grows to twice its size as it
// rises, then blurs and fades out. One every ~220ms while the pointer stays; a tap releases a burst
// (touch has no hover). One rAF loop moves every live heart and stops when none are left.
// Nothing runs with reduced motion.
(function () {
  var love = document.querySelector(".footer .love");
  if (!love || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  // A slight top-left to bottom-right gradient, defined once in a hidden SVG so every heart can use it
  // even after the heart that would otherwise define it has floated away and been removed.
  var defs = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  defs.setAttribute("width", "0"); defs.setAttribute("height", "0"); defs.setAttribute("aria-hidden", "true");
  defs.style.position = "absolute";
  defs.innerHTML = '<defs><linearGradient id="love-heart-fill" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF5C7C"/><stop offset="1" stop-color="#E8194A"/></linearGradient></defs>';
  document.body.appendChild(defs);

  var HEART = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="url(#love-heart-fill)" d="M12 21.2l-1.3-1.2C5.6 15.4 2.2 12.3 2.2 8.5 2.2 5.4 4.6 3 7.7 3c1.7 0 3.4.8 4.3 2.1C13 3.8 14.6 3 16.3 3c3.1 0 5.5 2.4 5.5 5.5 0 3.8-3.4 6.9-8.5 11.5L12 21.2z"/></svg>';
  var LIFT = 21;      // buoyancy, px/s² upward
  var DRAG = 1.4;     // 1/s: vertical speed settles at LIFT / DRAG ≈ 15 px/s
  var INERTIA = 1.2;  // 1/s: how quickly sideways speed follows the breeze
  var LEAN = 1.4;     // degrees of tilt per px/s of sideways speed
  var hearts = [], timer = 0, raf = 0, last = 0;

  function rand(a, b) { return a + Math.random() * (b - a); }
  function smooth(t) { return t * t * (3 - 2 * t); }

  function bubble() {
    var el = document.createElement("span");
    el.className = "love-heart";
    el.innerHTML = HEART;
    // Drawn at its largest (twice the base size) and scaled down, so the browser never enlarges a small
    // bitmap: scaling a layer up from its first raster is what made growing hearts look pixelated.
    var size = rand(7, 12) * 2;
    el.style.width = el.style.height = size + "px";
    el.style.left = rand(15, 85) + "%";
    love.appendChild(el);
    hearts.push({
      el: el, age: 0, life: rand(3, 4),
      x: 0, y: 0, vx: rand(-4, 4), vy: rand(-8, -2), angle: 0,
      // the breeze: two slow sine waves with their own phase and strength
      w1: rand(0.25, 0.45), w2: rand(0.6, 0.9), p1: rand(0, 6.28), p2: rand(0, 6.28), gust: rand(10, 18)
    });
    if (!raf) { last = performance.now(); raf = requestAnimationFrame(step); }
  }

  function step(now) {
    var dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    hearts = hearts.filter(function (h) {
      h.age += dt;
      var t = h.age / h.life;
      if (t >= 1) { h.el.remove(); return false; }

      h.vy += (-LIFT - DRAG * h.vy) * dt;  // buoyancy up, drag against the motion
      var breeze = h.gust * (0.65 * Math.sin(6.28 * h.w1 * h.age + h.p1) + 0.35 * Math.sin(6.28 * h.w2 * h.age + h.p2));
      h.vx += (breeze - h.vx) * (1 - Math.exp(-INERTIA * dt));
      h.x += h.vx * dt;
      h.y += h.vy * dt;
      var lean = Math.max(-14, Math.min(14, h.vx * LEAN));
      h.angle += (lean - h.angle) * (1 - Math.exp(-3 * dt));

      var pop = smooth(Math.min(1, h.age / 0.3));                 // pops in over 0.3s
      var scale = (0.6 + 0.4 * pop) * (1 + smooth(t)) / 2;         // then grows to twice its size (drawn at 2x)
      var out = smooth(Math.max(0, (t - 0.65) / 0.35));             // last 35%: blur and fade
      h.el.style.transform = "translate(calc(-50% + " + h.x.toFixed(2) + "px), " + h.y.toFixed(2) + "px) rotate(" + h.angle.toFixed(2) + "deg) scale(" + scale.toFixed(3) + ")";
      h.el.style.opacity = (pop * (1 - out)).toFixed(3);
      h.el.style.filter = out > 0 ? "blur(" + (2.5 * out).toFixed(2) + "px)" : "";
      return true;
    });
    raf = hearts.length ? requestAnimationFrame(step) : 0;
  }

  function start() {
    if (timer) return;
    bubble();
    timer = setInterval(bubble, 220);
  }
  function stop() {
    clearInterval(timer);
    timer = 0;
  }

  love.addEventListener("pointerenter", function (e) { if (e.pointerType !== "touch") start(); });
  love.addEventListener("pointerleave", stop);
  love.addEventListener("pointerdown", function (e) {
    if (e.pointerType !== "touch") return;
    for (var i = 0; i < 6; i++) setTimeout(bubble, i * 90);
  });
})();
