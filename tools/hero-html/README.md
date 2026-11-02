# Hero demo (HTML)

The phone demo on annotatekit.com is the Figma storyboard ("Frame 1046", 8 frames) played as live layers in the page.

- `figma/f1..f8.svg` are the frames exported as SVG by the Figma MCP (`download_assets`, format svg). Text is
  outlined (SF Pro) and icons are SF Symbols outlines, so nothing is redrawn and no font ships.
- `python3 build.py` cuts the layers the animation needs out of those frames into `site/reel-layers.js`, all in one
  546 x 890 stage (the 418 x 890 phone plus 64pt each side where the glass card overhangs it). Figma's glass doesn't
  survive SVG export, so its rounded rects are listed separately and `site/reel.css` draws them with
  `backdrop-filter`, tuned against Figma's own render of the frames.
- `site/reel.js` stacks the layers, runs the timeline (the `T` table) and drives the terminal beside the phone from
  the same clock, so its cues (`data-at` in `site/index.html`) can't drift. `reelSeek(t)` in the console shows any
  moment; `window.reelPaused = true` stops the clock.

To change the design: re-export the frames from Figma into `figma/`, run `build.py`, check the frames with
`reelSeek` against Figma's render.
