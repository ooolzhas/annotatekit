#!/usr/bin/env python3
"""Rebuilds transparent frames from two renders of the same scene, one over black and one over white.
The Rive CLI's screenshots are always opaque, so alpha is recovered by difference matting:
over black the pixel is c*a, over white it is c*a + (1-a), so a = 1 - (white - black) and c = black / a.
usage: matte.py <black-dir> <white-dir> <out-dir>"""
import os
import sys

import numpy as np
from PIL import Image

black, white, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
for name in sorted(os.listdir(black)):
    if not name.endswith(".png"):
        continue
    b = np.asarray(Image.open(os.path.join(black, name)).convert("RGB"), dtype=np.float32) / 255
    w = np.asarray(Image.open(os.path.join(white, name)).convert("RGB"), dtype=np.float32) / 255
    a = np.clip(1 - (w - b).mean(axis=2), 0, 1)
    rgb = np.where(a[..., None] > 1e-3, b / np.maximum(a[..., None], 1e-3), 0)
    rgba = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, name))
