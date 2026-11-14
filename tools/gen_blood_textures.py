"""Generates the blood splatter decal textures and pool noise into art/blood/.
Run:  python3 tools/gen_blood_textures.py   (needs numpy + Pillow)"""
import os, math
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'art', 'blood')
os.makedirs(OUT, exist_ok=True)
S = 512

def fbm(size, octaves, rng):
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for g in octaves:
        grid = rng.random((g, g))
        xs = np.arange(size) * g / size
        x0 = np.floor(xs).astype(int); fx = xs - x0; x1 = (x0 + 1) % g
        fx = fx * fx * (3 - 2 * fx)
        a = grid[x0][:, x0]; b = grid[x0][:, x1]; c = grid[x1][:, x0]; d = grid[x1][:, x1]
        FX = fx[None, :]; FY = fx[:, None]
        out += ((a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY) * amp
        tot += amp; amp *= 0.5
    return out / tot

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def blur(a, n=2):
    for _ in range(n):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a

class Canvas:
    def __init__(self): self.h = np.zeros((S, S))
    def dot(self, x, y, r, strength=1.0):
        """x, y, r in 0..1 texture units. y = 0 is the bottom of the image."""
        px, py, pr = x * S, (1 - y) * S, max(r * S, 0.8)
        x0, x1 = int(max(0, px - pr - 2)), int(min(S, px + pr + 3))
        y0, y1 = int(max(0, py - pr - 2)), int(min(S, py + pr + 3))
        if x0 >= x1 or y0 >= y1: return
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.sqrt((xx - px) ** 2 + (yy - py) ** 2) / pr
        self.h[y0:y1, x0:x1] = np.maximum(self.h[y0:y1, x0:x1], np.clip(1.25 * (1 - d), 0, 1) * strength)
    def tear(self, x, y, ang, length, r_head, r_tail=None):
        """Teardrop: thin tail at (x, y), fat head `length` away along `ang`."""
        r_tail = r_head * 0.25 if r_tail is None else r_tail
        n = max(3, int(length / max(r_head, 0.002) * 2.5))
        for i in range(n + 1):
            t = i / n
            self.dot(x + math.cos(ang) * length * t, y + math.sin(ang) * length * t, r_tail + (r_head - r_tail) * t ** 1.5)

def impact(rng):
    c = Canvas(); cx, cy = 0.5 + rng.uniform(-.03, .03), 0.5 + rng.uniform(-.03, .03)
    R = rng.uniform(0.13, 0.19)
    for k in range(26):                                   # lumpy core
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0, R * 0.8)
        c.dot(cx + math.cos(a) * d, cy + math.sin(a) * d, rng.uniform(R * 0.35, R * 0.75))
    for k in range(rng.integers(9, 17)):                  # radiating spikes
        a = rng.uniform(0, 2 * math.pi); L = rng.uniform(0.08, 0.26)
        c.tear(cx + math.cos(a) * (R * 0.6 + L), cy + math.sin(a) * (R * 0.6 + L), a + math.pi, L, rng.uniform(0.012, 0.028), 0.003)
    for k in range(rng.integers(50, 110)):                # satellite droplets
        a = rng.uniform(0, 2 * math.pi); d = R + abs(rng.normal(0.0, 0.13))
        if d > 0.46: continue
        r = rng.uniform(0.0025, 0.013) * (1.2 - d)
        c.tear(cx + math.cos(a) * d, cy + math.sin(a) * d, a, r * rng.uniform(0.5, 3.0), r)
    return c.h

def spray(rng):
    c = Canvas(); ox, oy = 0.5, 0.06
    for k in range(rng.integers(170, 300)):
        a = math.pi / 2 + rng.normal(0, 0.22); t = rng.beta(1.6, 2.2) * 0.86 + 0.03
        r = rng.uniform(0.002, 0.016) * (1.15 - t) * (3.0 if rng.random() < 0.06 else 1.0)
        x, y = ox + math.cos(a) * t, oy + math.sin(a) * t
        if not (0.03 < x < 0.97 and 0.03 < y < 0.97): continue
        c.tear(x, y, a + math.pi, r * rng.uniform(1.5, 6.0), r)
    for k in range(10):
        c.dot(ox + rng.normal(0, 0.03), oy + abs(rng.normal(0, 0.04)) + 0.02, rng.uniform(0.012, 0.03))
    return c.h

def drip(rng):
    c = Canvas()
    for k in range(rng.integers(3, 8)):
        x, y = 0.5 + rng.normal(0, 0.13), 0.5 + rng.normal(0, 0.13); r = rng.uniform(0.03, 0.085)
        if not (0.12 < x < 0.88 and 0.12 < y < 0.88): continue
        c.dot(x, y, r)
        for j in range(rng.integers(3, 9)):               # crown of tiny spines
            a = rng.uniform(0, 2 * math.pi)
            c.tear(x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.8, a, r * rng.uniform(0.3, 0.8), r * 0.09, r * 0.12)
        for j in range(rng.integers(2, 7)):
            a = rng.uniform(0, 2 * math.pi); d = r * rng.uniform(1.3, 2.4)
            c.dot(x + math.cos(a) * d, y + math.sin(a) * d, rng.uniform(0.003, 0.009))
    return c.h

def streak(rng):
    c = Canvas()
    for k in range(rng.integers(3, 7)):
        x = 0.5 + rng.normal(0, 0.12); y0 = rng.uniform(0.06, 0.3); L = rng.uniform(0.3, 0.6)
        if not 0.1 < x < 0.9: continue
        c.tear(x, y0, math.pi / 2 + rng.normal(0, 0.05), L, rng.uniform(0.018, 0.04), 0.004)
    for k in range(rng.integers(25, 60)):
        x, y = 0.5 + rng.normal(0, 0.15), rng.uniform(0.05, 0.95); r = rng.uniform(0.002, 0.008)
        if not 0.05 < x < 0.95: continue
        c.tear(x, y, math.pi / 2, r * rng.uniform(2, 7), r)
    return c.h

def finish(h, rng, name):
    n = fbm(S, (8, 16, 32, 64), rng)
    h = blur(h, 2)
    h = np.clip(h + (n - 0.5) * 0.10 * (h > 0.02), 0, 1)
    yy, xx = np.mgrid[0:S, 0:S]
    border = sstep(0, 14, np.minimum(np.minimum(xx, S - 1 - xx), np.minimum(yy, S - 1 - yy)))
    h *= border
    alpha = sstep(0.10, 0.20, h)
    thick = sstep(0.18, 0.85, h)
    thin_c = np.array([0.30, 0.022, 0.022]); deep_c = np.array([0.105, 0.004, 0.010])
    col = thin_c[None, None, :] * (1 - thick[..., None]) + deep_c[None, None, :] * thick[..., None]
    ring = alpha * (1 - sstep(0.20, 0.34, h))             # darker dried rim
    col = col * (1 - 0.45 * ring[..., None])
    col *= (0.9 + 0.2 * n)[..., None]
    a = alpha * (0.86 + 0.14 * thick)
    rgba = np.dstack([col, a])
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
    hs = blur(np.minimum(h, 0.7), 3)                      # raised, rounded liquid surface
    gx = (np.roll(hs, -1, 1) - np.roll(hs, 1, 1)) * 0.5 * S / 64.0
    gy = (np.roll(hs, -1, 0) - np.roll(hs, 1, 0)) * 0.5 * S / 64.0
    k = 2.2
    nx, ny, nz = -gx * k, gy * k, np.ones_like(hs)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5])
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, name + '_n.png'))

seed = 100
for kind, fn, count in (('impact', impact, 3), ('spray', spray, 3), ('drip', drip, 2), ('streak', streak, 2)):
    for i in range(count):
        rng = np.random.default_rng(seed); seed += 1
        finish(fn(rng), rng, 'splat_%s_%d' % (kind, i))
# wet-look ORM (occlusion 1, roughness 0.12, metallic 0) shared by every splat
Image.fromarray(np.tile(np.array([[[255, 31, 0]]], np.uint8), (8, 8, 1)), 'RGB').save(os.path.join(OUT, 'splat_orm.png'))
# tileable noise used by the pool shader
rng = np.random.default_rng(7)
nz = fbm(256, (4, 8, 16, 32), rng)
nz = (nz - nz.min()) / (nz.max() - nz.min())
Image.fromarray((nz * 255).astype(np.uint8), 'L').save(os.path.join(OUT, 'pool_noise.png'))
# contact sheet for a quick look
tiles = [f for f in sorted(os.listdir(OUT)) if f.startswith('splat_') and not f.endswith('_n.png') and 'orm' not in f]
sheet = Image.new('RGB', (5 * 256, 2 * 256), (150, 148, 140))
for i, f in enumerate(tiles):
    im = Image.open(os.path.join(OUT, f)).resize((256, 256), Image.LANCZOS)
    sheet.paste(im, ((i % 5) * 256, (i // 5) * 256), im)
sheet.save('/tmp/blood_sheet.png')
print(len(tiles), 'splats written')
