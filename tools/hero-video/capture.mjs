// Renders the annotatekit.com hero (hand-drawn grid, phone, Claude terminal) as a 16:9 frame sequence, light mode.
// It loads the real site/index.html and keeps only the hero, so the markup, styles and grid.js are the site's own;
// the sheet fills a 960 x 540 viewport drawn at 2x (1920 x 1080). The phone is the hero reel's own transparent frame
// sequence (tools/hero-figma/out/frames, 60 fps), shown one frame at a time, and every time-based thing on the page
// (the terminal's cues and slide, the lines' fades, the grid's boil, the live dot and spinner) is pinned to that
// frame's time, so the capture is frame-exact at 60 fps however long each frame takes to draw.
// usage: node capture.mjs [first-frame] [frame-count]   (writes out/frames/f0000.png ...)
import { createServer } from "node:http";
import { createReadStream, statSync, mkdirSync, readdirSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import puppeteer from "puppeteer-core";

const ROOT = resolve(import.meta.dirname, "../..");
const PHONE = "tools/hero-figma/out/frames";
const OUT = join(import.meta.dirname, "out/frames");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = 60, W = 960, H = 540, SCALE = 2;
// The site's cue times (site/index.html): the board splits for the terminal from 6.8 to 14.8
const SPLIT = [6.8, 14.8];

const total = readdirSync(join(ROOT, PHONE)).filter((f) => f.endsWith(".png")).length;
const first = Number(process.argv[2] ?? 0), count = Number(process.argv[3] ?? total - first);
mkdirSync(OUT, { recursive: true });

// A static server with Range support (the site's video needs it; here it only serves files)
const types = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".svg": "image/svg+xml", ".woff2": "font/woff2" };
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^\/+/, "");
  const file = join(ROOT, path);
  if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  try { statSync(file); } catch { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  createReadStream(file).pipe(res);
}).listen(0, "::1");
await new Promise((r) => server.once("listening", r));
const base = `http://[::1]:${server.address().port}`;   // not "localhost", so the page skips its local-only toolbar

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  // sRGB output regardless of the display this runs on, so the colours are the site's own
  args: ["--force-color-profile=srgb", "--hide-scrollbars", "--disable-lcd-text"],
});
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: SCALE });
await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: "light" }, { name: "prefers-reduced-motion", value: "no-preference" }]);
await page.goto(`${base}/site/index.html`, { waitUntil: "networkidle0" });

await page.evaluate(async (phoneBase) => {
  await document.fonts.ready;
  const hero = document.querySelector(".hero-media");
  // Only the hero, filling the frame edge to edge
  document.body.replaceChildren(hero);
  const css = document.createElement("style");
  css.textContent = `
    html, body { margin: 0; overflow: hidden; background: var(--bg); }
    .hero-media { width: 100vw; height: 100vh; aspect-ratio: auto; margin: 0; border-radius: 0; }
    .hero-phone img { display: block; width: 100%; height: 100%; }`;
  document.head.appendChild(css);
  const video = hero.querySelector(".hero-phone video");
  const img = new Image();
  video.replaceWith(img);
  window.__phone = { img, base: phoneBase };
  // grid.js and edge.js retrace on resize; give them a beat
  await new Promise((r) => setTimeout(r, 600));
}, `${base}/${PHONE}`);

await page.evaluate((split) => {
  const board = document.querySelector(".hero-media");
  const lines = [...document.querySelectorAll(".hero-term [data-at]")];
  const born = new Map();
  window.__step = async (i, fps) => {
    const t = i / fps;
    const { img, base } = window.__phone;
    img.src = `${base}/f${String(i).padStart(4, "0")}.png`;
    await img.decode();
    lines.forEach((l) => {
      const until = l.dataset.until ? parseFloat(l.dataset.until) : Infinity;
      l.classList.toggle("is-on", t >= parseFloat(l.dataset.at) && t < until);
    });
    board.classList.toggle("is-split", t >= split[0] && t < split[1]);
    getComputedStyle(board).transform;   // flush, so class changes start their transitions now
    for (const a of document.getAnimations()) {
      a.pause();
      if (a instanceof CSSTransition) {
        if (!born.has(a)) born.set(a, t);
        a.currentTime = (t - born.get(a)) * 1000;
      } else {
        a.currentTime = t * 1000;
      }
    }
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  };
}, SPLIT);

const cdp = await page.createCDPSession();
const started = Date.now();
// Frames before `first` still have to be stepped, so the transitions they start carry into later frames
for (let i = 0; i < first + count; i++) {
  await page.evaluate((i, fps) => window.__step(i, fps), i, FPS);
  if (i < first) continue;
  // The clip's scale is in device pixels per CSS pixel, so the 960 x 540 page comes back at 1920 x 1080
  const { data } = await cdp.send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false, clip: { x: 0, y: 0, width: W, height: H, scale: SCALE } });
  await writeFile(join(OUT, `f${String(i).padStart(4, "0")}.png`), Buffer.from(data, "base64"));
  if (i % 60 === 0) console.log(`frame ${i}/${first + count - 1}  ${((Date.now() - started) / 1000).toFixed(0)}s`);
}
await browser.close();
server.close();
console.log(`wrote ${count} frames to ${OUT}`);
