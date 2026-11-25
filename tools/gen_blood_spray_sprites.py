#!/usr/bin/env python3
"""Sprites for the blood spray (the blood overhaul's Phase C, 25 Nov 2026).

art/blood/fx_liquid_sheet.png  4x4 sheet, 128 px cells, 512 px. Liquid in flight,
    drawn along +Y (the head of a drop at the top, its tail below): frames 0-7
    single drops and small clusters, 8-15 strings and ropes with beads. RGB
    is white; the alpha is the liquid's thickness (the shader colours by it:
    bright red where thin, near black where deep).
art/blood/fx_haze.png  128 px soft puff for the hanging mist: a radial cloud
    with a little noise, alpha only.

Run from the project root; writes the two PNGs (re-import in Godot).
"""
import os, numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "blood")
CELL = 128
rng = np.random.default_rng(7)


def field(size):
    return np.zeros((size, size), np.float32)


def blob(f, cx, cy, rx, ry, power=1.0):
    """Add an elliptical dome of thickness (1 at the centre) to f."""
    h, w = f.shape
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d2 = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
    dome = np.clip(1.0 - d2, 0.0, 1.0) ** (0.6 * power)
    np.maximum(f, dome, out=f)


def drop(f, cx, cy, r, tail=0.0, ang=0.0):
    """A teardrop: a round head and, if tail > 0, a thinning tail below it (-Y is behind)."""
    blob(f, cx, cy, r, r * 1.05)
    if tail > 0:
        n = int(tail * r * 3)
        for i in range(n):
            t = i / max(n - 1, 1)
            rr = r * (1.0 - t) * 0.85 + 0.6
            blob(f, cx + np.sin(ang) * t * tail * r * 3, cy + np.cos(ang) * t * tail * r * 3, rr, rr, 1.2 + t)


def string(f, cx, top, length, width, beads, wander=0.35):
    """A rope of liquid from `top` downward: a thin thread with beads along it."""
    x = cx
    y = top
    n = int(length)
    seed = rng.random() * 10
    for i in range(n):
        t = i / max(n - 1, 1)
        x += np.sin(seed + t * 9.0) * wander + rng.normal(0, 0.15)
        w = width * 1.7 * (0.55 + 0.45 * np.sin(t * np.pi)) * (0.6 + 0.4 * rng.random())
        blob(f, x, y + i, max(w, 1.4), max(w, 1.4), 1.3)
    for b in range(beads):
        t = rng.uniform(0.1, 0.95)
        bx = cx + np.sin(seed + t * 9.0) * wander * n * 0.1
        r = width * rng.uniform(2.2, 3.4)
        blob(f, bx + rng.normal(0, 1.0), top + t * n, r, r * 1.15)


def frame_drop(k):
    f = field(CELL)
    c = CELL / 2
    if k == 0:
        drop(f, c, c * 0.8, 14, tail=1.2)
    elif k == 1:
        drop(f, c, c * 0.75, 11, tail=2.0)
    elif k == 2:
        drop(f, c, c, 16, tail=0.4)
    elif k == 3:
        drop(f, c, c * 0.7, 9, tail=2.6)
        blob(f, c + 6, c * 1.55, 3, 3)
    elif k == 4:                                   # cluster
        for _ in range(5):
            drop(f, c + rng.normal(0, 14), c + rng.normal(0, 16), rng.uniform(4, 9), tail=rng.uniform(0.3, 1.2))
    elif k == 5:
        for _ in range(8):
            drop(f, c + rng.normal(0, 16), c + rng.normal(0, 18), rng.uniform(2.5, 6), tail=rng.uniform(0.2, 0.9))
    elif k == 6:                                   # a drop breaking in two
        drop(f, c - 5, c * 0.75, 10, tail=0.6)
        drop(f, c + 7, c * 1.25, 7, tail=1.4)
        string(f, c + 1, c * 0.95, 22, 1.4, 0, wander=0.2)
    else:
        drop(f, c, c * 0.85, 7, tail=3.2)
        for _ in range(3):
            blob(f, c + rng.normal(0, 10), c * 1.4 + rng.normal(0, 10), 2.5, 2.5)
    return f


def frame_string(k):
    f = field(CELL)
    c = CELL / 2
    top = 10
    if k == 0:
        string(f, c, top, 108, 2.2, 4)
    elif k == 1:
        string(f, c, top, 104, 1.6, 6, wander=0.6)
    elif k == 2:
        string(f, c - 10, top, 100, 2.0, 3)
        string(f, c + 12, top + 8, 86, 1.3, 2, wander=0.5)
    elif k == 3:                                   # a rope that breaks into drops
        string(f, c, top, 60, 2.4, 3)
        for i in range(4):
            drop(f, c + rng.normal(0, 5), top + 68 + i * 13, rng.uniform(3, 5.5), tail=0.5)
    elif k == 4:
        string(f, c, top, 110, 3.2, 5, wander=0.25)
    elif k == 5:                                   # thick head, long thin tail
        drop(f, c, top + 14, 13, tail=0.0)
        string(f, c, top + 22, 90, 1.5, 3, wander=0.4)
    elif k == 6:
        string(f, c, top, 70, 1.2, 8, wander=0.8)
    else:
        string(f, c - 4, top, 108, 1.8, 2, wander=0.3)
        string(f, c + 6, top + 20, 70, 1.1, 2, wander=0.7)
    return f


def sheet():
    img = np.zeros((CELL * 4, CELL * 4, 4), np.float32)
    for i in range(16):
        f = frame_drop(i) if i < 8 else frame_string(i - 8)
        # soften the edge a little so the quads do not alias
        a = np.clip(f, 0, 1)
        r, cidx = divmod(i, 4)
        cell = img[r * CELL:(r + 1) * CELL, cidx * CELL:(cidx + 1) * CELL]
        cell[..., :3] = 1.0
        cell[..., 3] = a
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "fx_liquid_sheet.png"))


def haze():
    s = 128
    y, x = np.mgrid[0:s, 0:s].astype(np.float32)
    d = np.sqrt((x - s / 2) ** 2 + (y - s / 2) ** 2) / (s / 2)
    base = np.clip(1.0 - d, 0, 1) ** 1.6
    # a few soft lobes so it is a cloud, not a disc
    n = field(s)
    for _ in range(9):
        blob(n, s / 2 + rng.normal(0, 18), s / 2 + rng.normal(0, 18), rng.uniform(16, 30), rng.uniform(16, 30), 0.8)
    a = np.clip(base * (0.55 + 0.6 * n), 0, 1)
    img = np.zeros((s, s, 4), np.float32)
    img[..., :3] = 1.0
    img[..., 3] = a
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "fx_haze.png"))


if __name__ == "__main__":
    sheet()
    haze()
    print("wrote fx_liquid_sheet.png, fx_haze.png")
