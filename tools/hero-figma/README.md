# Hero reel (Figma Motion)

The annotatekit.com hero is the Figma storyboard animated in Figma Motion with AnnotateKit's own motion. The source is
the frame **"Hero reel v7 (short working, 2x timer)"** (`38:2`) in Figma file `SkaGTdRhMla8Swyl5qtbqA`:
- 546 × 970 pt, with the 418 × 890 phone at (64, 40)
- 20.68 s loop, 60 fps. The "working" stage runs 6.05 s, and its counter shows 2 s per real second (ticks every 0.5 s, snappy 0.15)

Its motion follows `reel-truth.md` (code curves, storyboard copy, original pacing):
- Springs are exact damped-harmonic solves sampled as linear keys on the 60 fps grid.
- Figma's own spring easing isn't used: it takes only `bounce` and settles early.

## Re-render
1. **Make the segments.** In the Figma MCP, run `segments.js` through `use_figma` with `BG` set to black. It returns
   four segment frames (0–8, 8–12, 12–16 and 16–20.68 s). A single 2x / 60 fps `export_video` job fails server side
   above ~700 frames.
2. **Export the black pass.** `export_video` each segment with `fps: 60`, `quality: "high"` and
   `constraint: {type: "SCALE", value: 2}`. Save them as `in/black-1.mp4` … `in/black-4.mp4`.
3. **Export the white pass.** Set the segments' fill to white (or re-run with white `BG`), export again, and save as
   `in/white-1.mp4` … `in/white-4.mp4`.
4. **Encode.** Run `./encode.sh`. It writes `out/demo.mov`, `out/demo.webm`, `out/demo-poster.png` and
   `out/demo-preview.mp4`.
5. **Ship.** Copy the first three into `site/`.

`export_video` only writes opaque MP4, so `matte.py` recovers alpha by difference matting the black and white passes:
a = 1 − (white − black), c = black / a. Alpha covers the bezel shadow and the glass card that overhangs the phone.
The glass refracts whatever it sits on, so on the site it reads as translucent over the grid.

## Encode settings
- **`demo.mov`:** HEVC with alpha through AVAssetWriter (`hevc_alpha.swift`; ffmpeg's VideoToolbox wrapper drops
  alpha). For Safari and every iOS browser.
- **`demo.webm`:** VP9 `yuva420p`. For everything else.
- **Both:** 1632 px tall, 60 fps, tagged BT.709.
- **Poster:** the last frame (the finished app, launcher back to "Annotate").

## Site cues
The terminal beside the phone prints on these reel seconds (`site/index.html`, `data-at` and `is-split`):
- 7.6: Send
- 8.32: received / working
- 10.4, 11.12 and 11.82: pin ✓
- 13.65: applied
- 15.13: overlay out
- 15.8: hot reload

The terminal is in from 6.8 to 14.8. Re-read these if the timeline changes.
