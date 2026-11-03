#!/usr/bin/env python3
"""Makes the reel's never-changing pixels bit-identical in every frame. Each Figma segment is its own lossy render,
so the bezel, its shadow and the status bar carry slightly different noise per segment, which flickers at segment
joins and at the loop point. A pixel counts as static only if it stays within NOISE levels of frame 0 (every
channel, alpha included) in *every* frame of the video; those pixels are set to frame 0's value. Anything that ever
moves keeps its rendered values, so a change smaller than NOISE (the app's white cards are only 8 levels off its
background) is never pasted back from frame 0. The launcher is left alone so its halo keeps its motion.
usage: stabilize.py <frames-dir>"""
import glob
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image

NOISE = 12
frames = sorted(glob.glob(f"{sys.argv[1]}/f*.png"))


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


ref = load(frames[0])


def deviation(paths):
    dev = np.zeros(ref.shape[:2], np.int16)
    for p in paths:
        np.maximum(dev, np.abs(load(p) - ref).max(axis=2), out=dev)
    return dev


static = None


def init(mask):
    # Workers are spawned (macOS), so the mask arrives here rather than as a module global
    global static
    static = mask


def snap(path):
    x = load(path)
    x[static] = ref[static]
    Image.fromarray(x.astype(np.uint8), "RGBA").save(path)


if __name__ == "__main__":
    h, w = ref.shape[:2]
    pt = w / 546   # the canvas is 546 pt wide
    with Pool() as pool:
        chunks = [frames[i::16] for i in range(16)]
        dev = np.max(pool.map(deviation, chunks), axis=0)
    mask = dev <= NOISE
    # The launcher pill and its halo: screen (141..261, 796..840) pt, plus the screen's (72, 48) offset and a margin
    mask[int((48 + 786) * pt):int((48 + 850) * pt), int((72 + 125) * pt):int((72 + 277) * pt)] = False
    with Pool(initializer=init, initargs=(mask,)) as pool:
        pool.map(snap, frames[1:], chunksize=8)
    print(f"stabilized {len(frames) - 1} frames: {mask.mean() * 100:.1f}% of pixels are static and now match frame 0")
