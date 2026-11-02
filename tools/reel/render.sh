#!/bin/zsh
# Renders the hero reel: gen.py -> Rive scene -> PNG frames (Rive CLI, native renderer) -> alpha videos.
# Needs: rive (brew install rive-app/tap/rive-cli), ffmpeg, python3 with Pillow.
# Usage: ./render.sh [outdir]   (default: ./out). Writes demo.mov (HEVC alpha, Safari), demo.webm (VP9 alpha), poster.png.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-out}"; PROJ="$OUT/project"; FRAMES="$OUT/frames"; FPS=30
mkdir -p "$PROJ" "$FRAMES"
[[ -f "$PROJ/rive.yaml" ]] || (cd "$OUT" && rive create project >/dev/null)
cp /System/Library/Fonts/SFNS.ttf "$PROJ/font.ttf"      # embedded in the scene only, never shipped
DUR=$(python3 -c "import gen;print(gen.DURATION)")
N=$(python3 -c "print(round($DUR*$FPS))")
export PROJ
for pass in black white; do
  [[ $pass == black ]] && BGC=FF000000 || BGC=FFFFFFFF
  python3 gen.py "$PROJ/scene.rml" $BGC >/dev/null
  export FRAMES="$OUT/frames-$pass"; mkdir -p "$FRAMES"; find "$FRAMES" -name "*.png" -delete
  seq 0 $((N-1)) | xargs -P 6 -n 1 ./frame.sh
done
python3 matte.py "$OUT/frames-black" "$OUT/frames-white" "$OUT/frames"
echo "rendered $N frames (transparent) in $OUT/frames"

# Encode. Safari and iOS play only HEVC with alpha (.mov); everything else plays VP9 with alpha (.webm).
swiftc -O hevc_alpha.swift -o "$OUT/hevc_alpha" 2>/dev/null
"$OUT/hevc_alpha" "$OUT/frames" $FPS 1632 "$OUT/demo.mov"
ffmpeg -y -hide_banner -loglevel error -framerate $FPS -i "$OUT/frames/f%04d.png" -vf "scale=-2:1632:flags=lanczos,format=yuva420p" \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -auto-alt-ref 0 -row-mt 1 -an "$OUT/demo.webm"
# Poster (reduced motion and first paint): the finished state, palette-quantised PNG with alpha.
POSTER_T=${POSTER_T:-16.0}
python3 - "$OUT" "$FPS" "$POSTER_T" <<'PY'
import sys
from PIL import Image
out, fps, t = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
im = Image.open(f"{out}/frames/f{round(t * fps):04d}.png").resize((938, 1632), Image.LANCZOS)
im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(f"{out}/demo-poster.png", optimize=True)
PY
echo "wrote $OUT/demo.mov $OUT/demo.webm $OUT/demo-poster.png: copy them into site/"
