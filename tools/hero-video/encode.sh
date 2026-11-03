#!/bin/zsh
# Encodes out/frames (from capture.mjs) as out/annotatekit-hero-1080p60.mp4, for social uploads (X and the like):
# H.264 High at level 4.2 (1080p60), 4:2:0, BT.709 matrix, limited range and tags, a 2 s closed GOP and faststart.
# Platforms re-encode what they're given, so this starts them from a clean, correctly tagged, high-bitrate source.
set -euo pipefail
cd "$(dirname "$0")"
FPS=60
# The frames are sRGB; scale's out_color_matrix does the one RGB -> YUV step with BT.709, and setparams stamps the
# tags on the frames (the output flags alone leave primaries and transfer unknown)
TAG="setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
ffmpeg -y -hide_banner -loglevel error -framerate $FPS -i out/frames/f%04d.png \
  -vf "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,$TAG" \
  -c:v libx264 -profile:v high -level 4.2 -preset slower -crf 12 -tune animation \
  -g 120 -keyint_min 120 -sc_threshold 0 -bf 2 \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -movflags +faststart -an out/annotatekit-hero-1080p60.mp4
ffprobe -v error -show_entries stream=codec_name,profile,level,width,height,r_frame_rate,pix_fmt,color_space,color_transfer,color_primaries,color_range,bit_rate,nb_frames:format=duration,size -of default=nw=1 out/annotatekit-hero-1080p60.mp4
