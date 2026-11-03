// Run through the Figma MCP `use_figma` tool (Plugin API) in file SkaGTdRhMla8Swyl5qtbqA. Makes the four export
// segments of the hero reel: one 2x / 60 fps export_video job fails server side above ~700 frames, so the 22s
// timeline is exported as 0-8, 8-12, 12-16 and 16-23.7s. Each segment is a clone of the reel frame whose keyframes are
// shifted to start at its offset; a cubic-bezier key cut by the offset is resampled on the 60fps grid, so every frame
// lands on the same value as in the full timeline. Set BG to black or white, then export each returned id.
const SRC = "40:2";               // "Hero reel v8 (seamless loop)", 546 x 970 pt, phone at (64, 40)
const BG = { r: 0, g: 0, b: 0 };  // then { r: 1, g: 1, b: 1 } for the white pass
const SEGMENTS = [[0, 8], [8, 4], [12, 4], [16, 6]];

const src = await figma.getNodeByIdAsync(SRC);
function bezY(e, u) {
  const { x1, y1, x2, y2 } = e.easingFunctionCubicBezier;
  let lo = 0, hi = 1, s = u;
  for (let i = 0; i < 40; i++) {
    s = (lo + hi) / 2;
    const x = 3 * (1 - s) ** 2 * s * x1 + 3 * (1 - s) * s * s * x2 + s ** 3;
    if (x < u) lo = s; else hi = s;
  }
  return 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s * s * y2 + s ** 3;
}
const lerp = (a, b, p) => {
  if (a.type === "FLOAT") return { type: "FLOAT", value: a.value + (b.value - a.value) * p };
  const o = {};
  for (const k of Object.keys(a.value)) o[k] = a.value[k] + (b.value[k] - a.value[k]) * p;
  return { type: a.type, value: o };
};
function at(kfs, t) {
  if (t <= kfs[0].timelinePosition) return kfs[0].value;
  for (let i = 1; i < kfs.length; i++) {
    const k0 = kfs[i - 1], k1 = kfs[i];
    if (t < k1.timelinePosition) {
      const e = k1.easing || { type: "LINEAR" };
      const u = (t - k0.timelinePosition) / (k1.timelinePosition - k0.timelinePosition);
      if (e.type === "HOLD") return k0.value;
      if (e.type === "CUSTOM_CUBIC_BEZIER") return lerp(k0.value, k1.value, bezY(e, u));
      return lerp(k0.value, k1.value, u);
    }
  }
  return kfs[kfs.length - 1].value;
}
const strip = (k) => { const o = { timelinePosition: k.timelinePosition, value: k.value }; if (k.easing) o.easing = k.easing; return o; };
function shift(kfs, off) {
  kfs = kfs.map(strip);
  const out = [{ timelinePosition: 0, value: at(kfs, off) }];
  for (let i = 0; i < kfs.length; i++) {
    const k = kfs[i];
    if (k.timelinePosition <= off + 1e-9) continue;
    const prev = kfs[i - 1];
    const cut = prev && prev.timelinePosition < off - 1e-9 && k.easing && k.easing.type === "CUSTOM_CUBIC_BEZIER";
    if (cut) for (let t = Math.ceil((off + 1e-9) * 60) / 60; t < k.timelinePosition - 1e-9; t += 1 / 60)
      out.push({ timelinePosition: +(t - off).toFixed(6), value: at(kfs, t), easing: { type: "LINEAR" } });
    const o = { ...k, timelinePosition: +(k.timelinePosition - off).toFixed(6) };
    if (cut) o.easing = { type: "LINEAR" };
    out.push(o);
  }
  return out;
}
const made = [];
for (const [i, [off, dur]] of SEGMENTS.entries()) {
  const c = src.clone();
  figma.currentPage.appendChild(c);
  c.x = src.x + 600 * (i + 1); c.y = src.y; c.name = `export seg ${i + 1} (${off}-${off + dur}s)`;
  c.fills = [{ type: "SOLID", color: BG }];
  if (off > 0) await (async function walk(node) {
    if (node !== c) {
      const tr = node.manualKeyframeTracks;
      if (tr && Object.keys(tr).length) {
        const nt = {};
        for (const [f, v] of Object.entries(tr)) {
          if (f === "effects") { nt[f] = {}; for (const [j, fields] of Object.entries(v)) { nt[f][j] = {}; for (const [ff, tk] of Object.entries(fields)) nt[f][j][ff] = { keyframes: shift(tk.keyframes, off) }; } }
          else if (f === "fills" || f === "strokes") { nt[f] = {}; for (const [j, tk] of Object.entries(v)) nt[f][j] = { keyframes: shift(tk.keyframes, off) }; }
          else nt[f] = { keyframes: shift(v.keyframes, off) };
        }
        node.manualKeyframeTracks = nt;
      }
    }
    if ("children" in node) for (const ch of node.children) await walk(ch);
  })(c);
  c.children[0].setTimelineDuration(c.children[0].timelines[0].id, dur);
  made.push(c.id);
}
return made;
