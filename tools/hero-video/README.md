# Hero video (16:9)

A 1920 × 1080, 60 fps, light-mode render of the annotatekit.com hero, for launch posts. It contains the hand-drawn
grid, the phone and the Claude terminal, the same as the site, at a 16:9 aspect.

1. Render the phone's frames first. `tools/hero-figma/encode.sh` leaves them in `tools/hero-figma/out/frames`
   (see that README).
2. `npm install`, then `node capture.mjs` (needs Google Chrome). It loads the real `site/index.html`, keeps only
   the hero, and fills a 960 × 540 viewport drawn at 2×. Every frame is pinned to its own time: the phone frame,
   the terminal's cues and slide, the line fades, the grid's boil and the live dot. So the capture is frame-exact at
   60 fps, however long each frame takes to draw. It writes `out/frames/f0000.png …` in sRGB. The sheet is full
   bleed: there's no hand-drawn edge and no edge fade, and the grid sits half a cell off center (`--grid-shift-x`,
   read by `site/grid.js`), so no line runs along the frame's edge.
3. `./encode.sh` writes `out/annotatekit-hero-1080p60.mp4`: H.264 High 4.2, 4:2:0, tagged BT.709 with limited
   range, a 2 s closed GOP and faststart.

The cue times come from `site/index.html` (`data-at`), and the terminal's in/out window is `SPLIT` in
`capture.mjs`. Keep that in step with the page's `is-split` window.
