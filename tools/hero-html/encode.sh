#!/bin/zsh
# Records the reel and encodes it for the site: out/demo.mov (HEVC with alpha: Safari and every iOS browser),
# out/demo.webm (VP9 with alpha: everything else) and out/demo-poster.png (the finished state, for first paint and
# reduced motion). Needs Google Chrome, node, ffmpeg and python3 with Pillow. Copy the three files into site/.
set -euo pipefail
cd "$(dirname "$0")"
FPS=30; H=1632; POSTER_T=${POSTER_T:-15.6}
[[ -d node_modules ]] || npm i --silent
node record.mjs $FPS
swiftc -O hevc_alpha.swift -o out/hevc_alpha 2>/dev/null
out/hevc_alpha out/frames $FPS $H out/demo.mov
ffmpeg -y -hide_banner -loglevel error -framerate $FPS -i out/frames/f%04d.png -vf "scale=-2:${H}:flags=lanczos,format=yuva420p" \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -auto-alt-ref 0 -row-mt 1 -an out/demo.webm
python3 - $FPS $POSTER_T $H <<'PY'
import sys
from PIL import Image
fps, t, h = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
im = Image.open(f"out/frames/f{round(t * fps):04d}.png")
im = im.resize((round(im.width * h / im.height / 2) * 2, h), Image.LANCZOS)
im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save("out/demo-poster.png", optimize=True)
PY
ls -la out/demo.mov out/demo.webm out/demo-poster.png
