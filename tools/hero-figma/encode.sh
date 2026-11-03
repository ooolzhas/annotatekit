#!/bin/zsh
# Turns the Figma Motion renders in in/ (black-1.mp4 … black-4.mp4 and white-1.mp4 … white-4.mp4, see README) into
# the site's hero: out/demo.mov (HEVC with alpha: Safari and every iOS browser), out/demo.webm (VP9 with alpha:
# everything else), out/demo-poster.png (the final frame, for first paint and reduced motion) and out/demo-preview.mp4
# (flattened onto #fafaf9, for review only). Needs ffmpeg, swiftc and python3 with numpy and Pillow.
# Copy demo.mov, demo.webm and demo-poster.png into site/.
set -euo pipefail
cd "$(dirname "$0")"
FPS=60; H=1632
mkdir -p out
count() { ffprobe -v error -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$1"; }
if [[ -z ${SKIP_MATTE:-} ]]; then
  # One process per segment; each but the last drops its final frame, which repeats the next segment's first
  rm -rf out/frames; segs=(in/black-*.mp4); start=0
  for i in {1..${#segs}}; do
    last=$(( i == ${#segs} ))
    python3 matte.py out/frames $H in/black-$i.mp4 in/white-$i.mp4 $start $last &
    start=$(( start + $(count in/black-$i.mp4) - 1 + last ))
  done
  wait
fi
swiftc -O hevc_alpha.swift -o out/hevc_alpha 2>/dev/null
out/hevc_alpha out/frames $FPS $H out/demo.mov
# BT.709 for the RGB → YUV matrix and the tags (the HEVC file is tagged the same way). ffmpeg takes the tags from the
# frames, so setparams stamps them there; the output flags alone leave primaries and transfer unknown.
BT709=(-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv)
TAG="setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
ffmpeg -y -hide_banner -loglevel error -framerate $FPS -i out/frames/f%04d.png \
  -vf "scale=out_color_matrix=bt709:out_range=tv,$TAG,format=yuva420p" \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -auto-alt-ref 0 -row-mt 1 $BT709 -an out/demo.webm
W=$(python3 -c "from PIL import Image; print(Image.open('out/frames/f0000.png').width)")
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0xfafaf9:s=${W}x${H}:r=$FPS" -framerate $FPS -i out/frames/f%04d.png \
  -filter_complex "[0]format=rgb24[bg];[1]format=rgba[fg];[bg][fg]overlay=format=rgb:shortest=1,scale=out_color_matrix=bt709:out_range=tv,$TAG,format=yuv420p" \
  -c:v libx264 -crf 16 -preset slow $BT709 -movflags +faststart -an out/demo-preview.mp4
# The poster is the loop's last frame: the finished app with the launcher back to "Annotate". Kept lossless: a 256-colour
# palette drops the app's faint placeholders and bands the bezel shadow (~200 KB against the video's few MB)
python3 - <<'PY'
import glob
from PIL import Image
Image.open(sorted(glob.glob("out/frames/f*.png"))[-1]).save("out/demo-poster.png", optimize=True)
PY
ls -la out/demo.mov out/demo.webm out/demo-poster.png out/demo-preview.mp4
