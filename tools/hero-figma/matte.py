#!/usr/bin/env python3
"""Rebuilds the transparent hero frames from two Figma Motion renders of the same timeline, one over black and one over
white. export_video only writes opaque MP4, so alpha comes from difference matting: over black a pixel is c*a, over
white it is c*a + (1 - a), so a = 1 - (white - black) and c = black / a. The renders arrive as time segments (one long
2x / 60 fps job fails server side); each segment's last frame repeats the next one's first, so it's dropped on join.
Colour is scaled down premultiplied (black is already c*a), so edges don't fringe.
usage: matte.py <out-dir> <height> <black-seg1.mp4,...> <white-seg1.mp4,...> [first-index keep-last]
With first-index (and keep-last 0/1) it mattes the given segments only, numbering from first-index, so encode.sh can
run one process per segment."""
import os
import subprocess
import sys

import numpy as np
from PIL import Image

out, height = sys.argv[1], int(sys.argv[2])
blacks, whites = sys.argv[3].split(","), sys.argv[4].split(",")
os.makedirs(out, exist_ok=True)


def probe(path):
    w, h, n = subprocess.run(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries",
                              "stream=width,height,nb_read_frames", "-of", "csv=p=0", path],
                             capture_output=True, text=True, check=True).stdout.strip().split(",")
    return int(w), int(h), int(n)


def frames(path, w, h):
    proc = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                            stdout=subprocess.PIPE)
    size = w * h * 3
    while chunk := proc.stdout.read(size):
        yield np.frombuffer(chunk, np.uint8).reshape(h, w, 3)
    proc.wait()


def shrink(channel, size):
    return np.asarray(Image.fromarray(channel, "F").resize(size, Image.LANCZOS))


index = int(sys.argv[5]) if len(sys.argv) > 5 else 0
keep_last = sys.argv[6] == "1" if len(sys.argv) > 6 else True
for seg, (bpath, wpath) in enumerate(zip(blacks, whites)):
    w, h, n = probe(bpath)
    if probe(wpath) != (w, h, n):
        sys.exit(f"{bpath}: black and white renders differ in size or length")
    keep = n if seg == len(blacks) - 1 and keep_last else n - 1
    size = (round(w * height / h / 2) * 2, height)
    for i, (b, wt) in enumerate(zip(frames(bpath, w, h), frames(wpath, w, h))):
        if i >= keep:
            break
        b = b.astype(np.float32) / 255
        wt = wt.astype(np.float32) / 255
        a = 1 - (wt - b).mean(axis=2)
        # The renders are lossy, so opaque pixels read 0.98-1.02 and empty canvas reads 0-0.01; pin both ends
        a = np.clip((a - 0.008) / (0.985 - 0.008), 0, 1).astype(np.float32)
        pre = np.clip(b, 0, None) * np.minimum(a / np.maximum(1 - (wt - b).mean(axis=2), 1e-3), 1)[..., None]
        sa = np.clip(shrink(a, size), 0, 1)
        rgb = np.dstack([shrink(np.ascontiguousarray(pre[..., c]), size) for c in range(3)])
        rgb = np.where(sa[..., None] > 1e-3, rgb / np.maximum(sa[..., None], 1e-3), 0)
        rgba = np.dstack([np.clip(rgb, 0, 1), sa])
        Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, f"f{index:04d}.png"))
        index += 1
    print(f"segment {seg + 1}: {keep} frames", flush=True)
print(f"{index} frames in {out}")
