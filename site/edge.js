// The blueprint's edge boils like the page's hand-drawn marks. Three traced takes of the sheet's own
// outline (its real size, radius and corner shape: squircle where the browser draws one, round where
// it doesn't) are nudged in and out by about a pixel along slow waves, then used as the sheet's mask;
// CSS cuts between them every 200ms. Wavelengths are in pixels, so the wobble reads the same at any
// size, and the takes are retraced whenever the sheet resizes. Without this the sheet is a plain
// rounded rect; with reduced motion it keeps one still take.
(function () {
  var board = document.querySelector(".hero-media");
  if (!board) return;

  var STEP = 4;        // px between outline points
  var REACH = 1.1;     // px: the most the edge moves in or out
  var traced = "";

  function rand(seed) {
    return function () { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  }

  // The sheet's outline, inset by REACH so the outward wobble stays inside the box, as dense points.
  function outline(w, h, r, n) {
    var pts = [], i = REACH, x0 = i, y0 = i, x1 = w - i, y1 = h - i;
    r = Math.max(0, Math.min(r - i, (x1 - x0) / 2, (y1 - y0) / 2));
    // One quarter of a corner as a superellipse of exponent n (2 = circle, 4 = CSS squircle), from
    // the side edge (t = 0) round to the top or bottom edge; corners met from that edge run reversed.
    var quarter = [];
    for (var k = 0; k <= 24; k++) {
      var t = (k / 24) * Math.PI / 2;
      quarter.push([Math.pow(Math.cos(t), 2 / n), Math.pow(Math.sin(t), 2 / n)]);
    }
    function corner(cx, cy, sx, sy, reverse) {
      var q = reverse ? quarter.slice().reverse() : quarter;
      q.forEach(function (p) { pts.push([cx + sx * r * p[0], cy + sy * r * p[1]]); });
    }
    function line(ax, ay, bx, by) {
      var len = Math.hypot(bx - ax, by - ay), m = Math.max(1, Math.round(len / STEP));
      for (var k = 1; k < m; k++) pts.push([ax + (bx - ax) * k / m, ay + (by - ay) * k / m]);
    }
    // Clockwise from the top-left corner.
    corner(x0 + r, y0 + r, -1, -1, false);
    line(x0 + r, y0, x1 - r, y0);
    corner(x1 - r, y0 + r, 1, -1, true);
    line(x1, y0 + r, x1, y1 - r);
    corner(x1 - r, y1 - r, 1, 1, false);
    line(x1 - r, y1, x0 + r, y1);
    corner(x0 + r, y1 - r, -1, 1, true);
    line(x0, y1 - r, x0, y0 + r);
    return pts;
  }

  // Waves along the perimeter: whole cycles per lap, so the outline closes without a seam. The shared
  // waves give the sheet its hand-cut shape; each take adds its own small tremor on top.
  function waves(perimeter, random, list) {
    return list.map(function (wv) {
      return { k: Math.max(1, Math.round(perimeter / wv[0])), a: wv[1], p: random() * 6.283 };
    });
  }

  function take(pts, cum, perimeter, shape, tremor) {
    var all = shape.concat(tremor), d = "";
    for (var i = 0; i < pts.length; i++) {
      var prev = pts[(i - 1 + pts.length) % pts.length], next = pts[(i + 1) % pts.length];
      var tx = next[0] - prev[0], ty = next[1] - prev[1], tl = Math.hypot(tx, ty) || 1;
      var nx = ty / tl, ny = -tx / tl;   // outward for a clockwise outline
      var off = 0, u = cum[i] / perimeter * 6.283;
      all.forEach(function (wv) { off += wv.a * Math.sin(wv.k * u + wv.p); });
      off = Math.max(-REACH, Math.min(REACH, off));
      d += (i ? "L" : "M") + (pts[i][0] + nx * off).toFixed(1) + " " + (pts[i][1] + ny * off).toFixed(1);
    }
    return d + "Z";
  }

  function trace() {
    var w = board.clientWidth, h = board.clientHeight;
    if (!w || !h) return;
    var cs = getComputedStyle(board);
    var n = /superellipse\(2\)|squircle/.test(cs.getPropertyValue("corner-shape")) ? 4 : 2;
    var r = parseFloat(cs.borderTopLeftRadius) || 0;
    var key = [w, h, r, n].join(" ");
    if (key === traced) return;
    traced = key;

    var pts = outline(w, h, r, n), cum = [0];
    for (var i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
    var perimeter = cum[cum.length - 1] + Math.hypot(pts[0][0] - pts[pts.length - 1][0], pts[0][1] - pts[pts.length - 1][1]);
    var random = rand(20261101);
    var shape = waves(perimeter, random, [[260, 0.45], [97, 0.3]]);
    for (var t = 0; t < 3; t++) {
      var tremor = waves(perimeter, random, [[61, 0.22], [29, 0.14]]);
      var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + " " + h +
        '" preserveAspectRatio="none"><path d="' + take(pts, cum, perimeter, shape, tremor) + '"/></svg>';
      board.style.setProperty("--edge-" + t, 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")');
    }
    board.classList.add("has-edge");
  }

  // ResizeObserver catches layout changes; the window event covers pages that aren't rendering
  // (a background tab still resizes). Retracing an unchanged size is skipped.
  trace();
  if ("ResizeObserver" in window) new ResizeObserver(trace).observe(board);
  window.addEventListener("resize", trace);
})();
