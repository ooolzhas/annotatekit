#!/bin/zsh
# Records the reel and encodes it for the site: out/demo.mov (HEVC with alpha: Safari and every iOS browser),
# out/demo.webm (VP9 with alpha: everything else) and out/demo-poster.png (the finished state, for first paint and
# reduced motion), plus out/demo-preview.mp4 (opaque, for review only). Needs Google Chrome, node, ffmpeg and python3
# with Pillow. Copy demo.mov, demo.webm and demo-poster.png into site/.
set -euo pipefail
cd "$(dirname "$0")"
FPS=${FPS:-60}; H=1632; POSTER_T=${POSTER_T:-21}
[[ -d node_modules ]] || npm i --silent
[[ -n ${SKIP_RECORD:-} ]] || node record.mjs $FPS   # SKIP_RECORD=1 re-encodes the frames already in out/
swiftc -O hevc_alpha.swift -o out/hevc_alpha 2>/dev/null
out/hevc_alpha out/frames $FPS $H out/demo.mov
# BT.709 for the RGB → YUV matrix and the tags (the HEVC file is tagged the same way). ffmpeg takes the tags from the
# frames, so setparams stamps them there; the output flags alone leave primaries and transfer unknown.
BT709=(-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv)
TAG="setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
ffmpeg -y -hide_banner -loglevel error -framerate $FPS -i out/frames/f%04d.png \
  -vf "scale=-2:${H}:flags=lanczos:out_color_matrix=bt709:out_range=tv,$TAG,format=yuva420p" \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -auto-alt-ref 0 -row-mt 1 $BT709 -an out/demo.webm
# A review copy that plays anywhere: the frames flattened onto the site's #fafaf9 (in RGB, so the only YUV step is the
# BT.709 one), H.264, same matrix and tags
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0xfafaf9:s=1092x1940:r=$FPS" -framerate $FPS -i out/frames/f%04d.png \
  -filter_complex "[0]format=rgb24[bg];[1]format=rgba[fg];[bg][fg]overlay=format=rgb:shortest=1,scale=-2:${H}:flags=lanczos:out_color_matrix=bt709:out_range=tv,$TAG,format=yuv420p" \
  -c:v libx264 -crf 16 -preset slow $BT709 -movflags +faststart -an out/demo-preview.mp4
python3 - $FPS $POSTER_T $H <<'PY'
import sys
from PIL import Image
fps, t, h = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
im = Image.open(f"out/frames/f{round(t * fps):04d}.png")
im = im.resize((round(im.width * h / im.height / 2) * 2, h), Image.LANCZOS)
im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save("out/demo-poster.png", optimize=True)
PY
ls -la out/demo.mov out/demo.webm out/demo-poster.png out/demo-preview.mp4
