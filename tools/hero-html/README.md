# Hero reel (HTML source → video)

The phone demo on annotatekit.com is a video recorded from this page: the Figma storyboard ("Frame 1046") as live
layers, animated with AnnotateKit's own motion. Nothing here ships; only `site/demo.mov`, `site/demo.webm` and
`site/demo-poster.png` do.

- `figma/f1..f8.svg`: the 8 frames, exported as SVG by the Figma MCP. Text is outlined (SF Pro) and icons are the SF
  Symbols outlines, so nothing is redrawn and no font is needed.
- `build.py` cuts the layers the animation needs into `page/reel-layers.js`, on one 546 x 890 stage (the 418 x 890 phone
  plus 64pt each side where the glass card overhangs it). Pins are split into disc and glyph per state, so a state change
  can crossfade the disc and scale the glyph the way the overlay does. Figma's glass doesn't survive SVG export, so
  `page/reel.css` draws it with `backdrop-filter`, calibrated against Figma's own render.
- `page/reel.js` is the timeline. Its motion values (the `M` table) are the overlay's springs and durations from
  `Sources/AnnotateKit` (spring response/damping, snappy 0.3 chrome, spring 0.45/0.35 pin pops, smooth 0.45 hint swaps,
  easeInOut 0.8 glow palette, …), solved as real springs; the pacing (`T`) follows the original Simulator recording.
  Open `page/index.html?preview` on any static server to watch it; `reelSeek(t)` shows any moment.
- `./encode.sh` records it (`record.mjs`: headless Chrome, the timeline and CSS animations seeked to each frame, 2x,
  transparent background, a 546 x 970 frame so the phone's shadow fits) and encodes `out/demo.mov` (HEVC with alpha,
  through `hevc_alpha.swift`, for WebKit), `out/demo.webm` (VP9 with alpha) and `out/demo-poster.png`. Copy them into
  `site/`, then retime the terminal's `data-at` cues and the `is-split` window in `site/index.html` from `T`.

Needs Google Chrome, node, ffmpeg, Xcode's swiftc and python3 with Pillow.
