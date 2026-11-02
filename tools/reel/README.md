# Hero reel

The phone video on annotatekit.com, rebuilt from the Figma storyboard ("Frame 1046") as a Rive scene and
rendered to transparent video. A screen recording can't do it: the glass comment card is wider than the
phone (it overhangs the bezel by 41.5pt each side), and the page shows through where it does.

```sh
brew install rive-app/tap/rive-cli ffmpeg   # once; Pillow and numpy for python3
./render.sh                                 # frames -> out/demo.mov, out/demo.webm, out/demo-poster.png (~3 min)
```

Copy the three files into `site/`. `site/index.html` picks `.mov` (HEVC with alpha) on WebKit and `.webm`
(VP9 with alpha) elsewhere.

- `gen.py` writes the Rive scene (`scene.rml`) and every keyframe. **The timeline is the `T` table at the top**:
  change a time there and re-render. The terminal's cue times in `site/index.html` (`data-at`, the `is-split`
  window in the inline script) are read from the same table, so move them together.
- The Rive CLI's screenshots are always opaque, so `render.sh` renders every frame twice (over black and over
  white) and `matte.py` recovers alpha from the difference.
- `hevc_alpha.swift` encodes the HEVC-with-alpha `.mov` through AVAssetWriter; ffmpeg's VideoToolbox wrapper
  drops the alpha plane.
- The scene embeds macOS's SF (`/System/Library/Fonts/SFNS.ttf`) only to draw the glyphs; the font is never shipped.
- `rive . --screenshot=f.png --advance=<seconds>s` on the generated project renders any single moment.
