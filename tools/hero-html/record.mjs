// Records the hero reel (page/index.html) frame by frame: the timeline is seeked to each frame's time, not played,
// so every frame is exact whatever the machine's speed. Frames are 2x PNGs with a transparent background (the glass
// card's overhang shows the page through it on the site). Uses the installed Google Chrome, headless.
// usage: npm i && node record.mjs [fps=30]   -> out/frames/f0000.png …
import { mkdir, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";
import puppeteer from "puppeteer-core";

const FPS = Number(process.argv[2] || 30);
const HERE = new URL(".", import.meta.url).pathname;
const OUT = join(HERE, "out", "frames");
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };

const server = createServer(async (req, res) => {
  const path = join(HERE, "page", decodeURIComponent(new URL(req.url, "http://x").pathname.replace(/\/$/, "/index.html")));
  let body;
  try { body = await readFile(path); } catch { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": TYPES[extname(path)] || "application/octet-stream" });
  res.end(body);
}).listen(0);
const url = `http://127.0.0.1:${server.address().port}/index.html?record`;

await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });
const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  args: ["--force-color-profile=srgb", "--hide-scrollbars"],
});
const page = await browser.newPage();
await page.setViewport({ width: 546, height: 970, deviceScaleFactor: 2 });   // the stage plus 40pt above and below
await page.goto(url, { waitUntil: "load" });
const loop = await page.evaluate(() => window.REEL_LOOP);
const n = Math.round(loop * FPS);
for (let i = 0; i < n; i++) {
  const t = i / FPS;
  // the timeline and any CSS animations (the pins' spinners) both go to t
  await page.evaluate((t) => {
    window.reelSeek(t);
    document.getAnimations().forEach((a) => { a.pause(); a.currentTime = t * 1000; });
  }, t);
  await page.screenshot({ path: join(OUT, `f${String(i).padStart(4, "0")}.png`), omitBackground: true });
  if (i % 60 === 0) console.error(`frame ${i}/${n}`);
}
await browser.close();
server.close();
console.log(`recorded ${n} frames at ${FPS} fps (${loop}s) into ${OUT}`);
