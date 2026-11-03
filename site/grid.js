// The blueprint's grid is drawn by hand, like the page's other marks. Three traced takes of the whole grid
// (minor lines every 24px, a major line every 5th, centered so a major line runs through the middle both ways)
// each wobble by under a pixel along slow waves and are inked with their own grain, then used as the grid's
// mask; CSS cuts between them every 200ms. Major lines are full strength in the mask and minor lines half, so
// the ink colour set in CSS gives the 10% / 5% pair. Takes are retraced when the sheet resizes. Without this
// the grid is the straight CSS fallback; with reduced motion it keeps one still take.
(function () {
  var board = document.querySelector(".hero-media");
  if (!board) return;

  var MINOR = 24, EVERY = 5;   // px between lines; every 5th is major
  var STEP = 10;               // px between points along a line
  var REACH = 0.9;             // px: the most a line strays from straight
  var traced = "";

  function rand(seed) {
    return function () { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  }

  // The marks' ink (index.html's #ink-N): a slight displacement roughens the edges, and two noise masks
  // eat small holes and long faint stretches out of the stroke.
  function ink(id, seed) {
    return '<filter id="' + id + '" filterUnits="userSpaceOnUse" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">' +
      '<feTurbulence type="fractalNoise" baseFrequency="0.4" numOctaves="2" seed="' + seed + '"/>' +
      '<feDisplacementMap in="SourceGraphic" scale="1.4" xChannelSelector="R" yChannelSelector="G" result="r"/>' +
      '<feTurbulence type="fractalNoise" baseFrequency="0.9" seed="' + (seed + 7) + '"/>' +
      '<feColorMatrix values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -2.8 0 0 0 2.6"/><feComposite in="r" operator="in" result="g"/>' +
      '<feTurbulence type="fractalNoise" baseFrequency="0.02" seed="' + (seed + 13) + '"/>' +
      '<feColorMatrix values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -1.2 0 0 0 1.5"/><feComposite in="g" operator="in"/></filter>';
  }

  // One line from a to b, nudged sideways by its waves: the shared ones give it its hand-drawn shape,
  // each take adds its own small tremor on top.
  function stroke(ax, ay, bx, by, waves) {
    var len = Math.hypot(bx - ax, by - ay), n = Math.max(1, Math.round(len / STEP));
    var nx = -(by - ay) / len, ny = (bx - ax) / len, d = "";
    for (var i = 0; i <= n; i++) {
      var s = (i / n) * len, off = 0;
      waves.forEach(function (wv) { off += wv.a * Math.sin(6.283 * s / wv.l + wv.p); });
      off = Math.max(-REACH, Math.min(REACH, off));
      var x = ax + (bx - ax) * i / n + nx * off, y = ay + (by - ay) * i / n + ny * off;
      d += (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
    }
    return d;
  }

  function trace() {
    var w = board.clientWidth, h = board.clientHeight;
    if (!w || !h) return;
    // --grid-shift-x (px, optional) moves the grid off center; a full-bleed render uses it so no line sits on
    // the frame's edge. The site leaves it unset.
    var shift = parseFloat(getComputedStyle(board).getPropertyValue("--grid-shift-x")) || 0;
    var key = w + " " + h + " " + shift;
    if (key === traced) return;
    traced = key;

    // Every line's own shape, shared by the three takes
    var lines = [], random = rand(20261103), cx = w / 2 + shift, cy = h / 2;
    function wavesOf(list) { return list.map(function (wv) { return { l: wv[0] * (0.8 + 0.4 * random()), a: wv[1], p: random() * 6.283 }; }); }
    for (var k = -Math.ceil(cx / MINOR); cx + k * MINOR <= w; k++) {
      var x = cx + k * MINOR;
      if (x >= 0) lines.push({ major: k % EVERY === 0, a: [x, -4], b: [x, h + 4], shape: wavesOf([[240, 0.45], [90, 0.3]]) });
    }
    for (k = -Math.ceil(cy / MINOR); cy + k * MINOR <= h; k++) {
      var y = cy + k * MINOR;
      if (y >= 0) lines.push({ major: k % EVERY === 0, a: [-4, y], b: [w + 4, y], shape: wavesOf([[240, 0.45], [90, 0.3]]) });
    }
    for (var t = 0; t < 3; t++) {
      var major = "", minor = "";
      lines.forEach(function (ln) {
        var d = stroke(ln.a[0], ln.a[1], ln.b[0], ln.b[1], ln.shape.concat(wavesOf([[50, 0.18], [23, 0.1]])));
        if (ln.major) major += d; else minor += d;
      });
      var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + " " + h + '">' +
        "<defs>" + ink("i", 51 + t * 6) + '</defs><g fill="none" stroke="#000" stroke-width="1" stroke-linecap="round" filter="url(#i)">' +
        '<path stroke-opacity="0.5" d="' + minor + '"/><path d="' + major + '"/></g></svg>';
      board.style.setProperty("--grid-" + t, 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")');
    }
    board.classList.add("has-grid");
  }

  // ResizeObserver catches layout changes; the window event covers pages that aren't rendering
  // (a background tab still resizes). Retracing an unchanged size is skipped.
  trace();
  if ("ResizeObserver" in window) new ResizeObserver(trace).observe(board);
  window.addEventListener("resize", trace);
})();
