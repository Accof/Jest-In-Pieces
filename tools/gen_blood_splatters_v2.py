#!/usr/bin/env python3
"""Blood splatter library v2 (24 Nov 2026, the blood overhaul's Phase A).

Generates art/blood/splat2/: six kinds of splatter decal as colour (RGBA),
normal and ORM maps at 1024 x 1024, built against Andrew's five reference
photographs rather than drawn as shapes:

  mist      a gunshot's forward spatter: thousands of fine specks on a
            power-law size spread, in a directional fan from an origin low in
            the texture (the texture's up is the travel direction), no mass
  impact    medium-velocity impact: a soft irregular central mass, a halo of
            drops with tails pointing away from it, two to five drips running
            down from it with beads at their ends
  castoff   blood flung from a swung club or a thrown limb: an arc of drops
            thinning along it, each elongated along the arc
  dripfield drops that landed on a wall from above and ran: dozens of drops
            with vertical runs of varied length
  heavy     a body's worth against a wall: a lumpy mass, a heavy halo, long
            drips, side splashes (the big hits, headshots at the muzzle)
  streak    a glancing smear along the surface, dragged specks at the ends
  small     single droplet landings (round, elongated, with a tail)
  dripmask  (one texture) time-of-arrival ramp for the animated runs of Phase D

Everything is rendered at 2048 as a thickness field (metres of blood, in
arbitrary units), broken at the edges by noise so nothing is a clean disc,
coloured by thickness (thin edges bright arterial red, thick centres dark),
then box-filtered to 1024. Normal from the thickness field; ORM with low
roughness where the blood is thick and wet.

Usage: python3 tools/gen_blood_splatters_v2.py [out_dir] [--seed N] [--sheet path]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

R = 2048                 # working resolution
OUT = 1024
OUT_AUX = 512            # normal and ORM maps: half size, the detail is in the colour's alpha
KINDS = {"mist": 6, "impact": 6, "castoff": 4, "dripfield": 4, "heavy": 4, "streak": 4, "small": 8}

rng = np.random.default_rng(1917)


# --- helpers ---------------------------------------------------------------------------
def value_noise(shape, scale, seed, octaves=3):
    g = np.random.default_rng(seed)
    out = np.zeros(shape, dtype=np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        s = max(2, int(scale / (2 ** o)))
        gy, gx = shape[0] // s + 2, shape[1] // s + 2
        grid = g.random((gy, gx)).astype(np.float32)
        ys = np.arange(shape[0]) / s
        xs = np.arange(shape[1]) / s
        y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
        fy = (ys - y0).astype(np.float32); fx = (xs - x0).astype(np.float32)
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        a = grid[y0[:, None], x0[None, :]]; b = grid[y0[:, None], x0[None, :] + 1]
        c = grid[y0[:, None] + 1, x0[None, :]]; d = grid[y0[:, None] + 1, x0[None, :] + 1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy[:, None]) + (c * (1 - fx) + d * fx) * fy[:, None])
        tot += amp
        amp *= 0.5
    return out / tot


class Canvas:
    """A thickness field; stamps add blood."""

    def __init__(self):
        self.t = np.zeros((R, R), dtype=np.float32)
        yy, xx = np.mgrid[0:R, 0:R]
        self._yy = yy
        self._xx = xx

    def drop(self, x, y, r, elong=1.0, angle=0.0, thick=1.0, tail=0.0, tail_w=0.45):
        """A droplet: an irregular ellipse of radius r (elongated along `angle`
        by `elong`), optionally with a tail of length `tail` (pixels) trailing
        opposite the direction of travel (the tail points back toward where
        the blood came from, i.e. the drop's elongation axis)."""
        rr = max(r, 0.6)
        ext = int(rr * max(elong, 1.0) * 1.8 + tail + 3)
        x0, x1 = int(max(0, x - ext)), int(min(R, x + ext + 1))
        y0, y1 = int(max(0, y - ext)), int(min(R, y + ext + 1))
        if x1 <= x0 or y1 <= y0:
            return
        xs = self._xx[y0:y1, x0:x1] - x
        ys = self._yy[y0:y1, x0:x1] - y
        ca, sa = math.cos(angle), math.sin(angle)
        u = xs * ca + ys * sa          # along the travel axis
        v = -xs * sa + ys * ca         # across
        # the body: an ellipse, its edge roughened a little by the position
        d = np.sqrt((u / (rr * elong)) ** 2 + (v / rr) ** 2)
        rough = 1.0 + 0.12 * np.sin(u * 0.9 + v * 1.7) * np.sin(v * 0.6 - u * 1.1)
        body = np.clip(1.0 - (d * rough - 0.75) / 0.35, 0.0, 1.0)
        # a domed thickness: thicker at the middle
        body = body * (0.55 + 0.45 * np.clip(1.0 - d, 0.0, 1.0))
        if tail > 0.5:
            # the tail: a tapering ribbon behind the drop (u < 0), width tail_w*r at
            # the drop shrinking to a point over `tail`
            s = np.clip(-u / tail, 0.0, 1.0)
            w = rr * tail_w * (1.0 - s) ** 0.8 + 0.5
            on = (u < 0.0) & (u > -tail)
            tb = np.where(on, np.clip(1.0 - (np.abs(v) - w * 0.7) / (w * 0.5 + 0.5), 0.0, 1.0), 0.0)
            body = np.maximum(body, tb * (0.5 + 0.5 * (1.0 - s)) * 0.7)
        self.t[y0:y1, x0:x1] = np.maximum(self.t[y0:y1, x0:x1], (body * thick).astype(np.float32))

    def run(self, x, y, length, width, thick=1.0, bead=1.3, wobble=6.0):
        """A drip running down from (x, y): a ribbon of `length`, width tapering
        from `width` to about half, a bead at the end."""
        if length < 3:
            return
        n = int(length / 2) + 2
        ys = np.linspace(0, length, n)
        ph = rng.random() * 6.28
        ph2 = rng.random() * 6.28
        # a slow wander, growing down the run, and a slower, smaller one
        xs = x + wobble * np.sin(ys * 0.011 + ph) * (ys / length) ** 0.7 + wobble * 0.35 * np.sin(ys * 0.027 + ph2)
        self.drop(x, y, width * 1.25, 1.1, math.pi / 2, thick)     # the drop it ran from
        for i in range(n):
            s = ys[i] / length
            w = width * (1.0 - 0.5 * s) * (0.92 + 0.16 * math.sin(ys[i] * 0.07 + ph2)) * (0.9 + 0.2 * math.sin(ys[i] * 0.021 + ph))
            self.drop(xs[i], y + ys[i], max(w, 1.2), 1.0, 0.0, thick * (0.95 - 0.3 * s))
        self.drop(xs[-1], y + length, width * bead * (1.0 - 0.3 * (length / 900.0)), 1.15, math.pi / 2, thick)

    def mass(self, x, y, radius, lumps=0.35, thick=1.0, seed=0):
        """An irregular central mass: a blob whose outline is a sum of harmonics
        and noise, with a thick domed interior."""
        g = np.random.default_rng(seed)
        ext = int(radius * 1.8 + 4)
        x0, x1 = int(max(0, x - ext)), int(min(R, x + ext + 1))
        y0, y1 = int(max(0, y - ext)), int(min(R, y + ext + 1))
        xs = self._xx[y0:y1, x0:x1] - x
        ys = self._yy[y0:y1, x0:x1] - y
        ang = np.arctan2(ys, xs)
        rad = np.sqrt(xs * xs + ys * ys)
        rr = np.ones_like(ang)
        for h, amp in ((2, 0.18), (3, 0.14), (5, 0.1), (7, 0.07), (11, 0.05)):
            rr += amp * lumps / 0.35 * np.sin(h * ang + g.random() * 6.28)
        noise = value_noise((y1 - y0, x1 - x0), 40, seed + 7, 3)
        rr = rr * radius * (0.85 + 0.3 * noise)
        d = rad / np.maximum(rr, 1.0)
        body = np.clip(1.0 - (d - 0.9) / 0.12, 0.0, 1.0)
        dome = 0.6 + 0.4 * np.clip(1.0 - d, 0.0, 1.0) ** 0.6
        body = body * dome * (0.85 + 0.3 * value_noise((y1 - y0, x1 - x0), 90, seed + 3, 2))
        self.t[y0:y1, x0:x1] = np.maximum(self.t[y0:y1, x0:x1], (body * thick).astype(np.float32))

    def wash(self, x, y, radius, strength=0.22, elong=1.0, angle=0.0, seed=0):
        """A translucent haze of blood too fine to resolve: a soft, noisy cloud
        of low thickness (the references' pink wash round every mass)."""
        ext = int(radius * max(elong, 1.0) * 1.6 + 4)
        x0, x1 = int(max(0, x - ext)), int(min(R, x + ext + 1))
        y0, y1 = int(max(0, y - ext)), int(min(R, y + ext + 1))
        if x1 <= x0 or y1 <= y0:
            return
        xs = self._xx[y0:y1, x0:x1] - x
        ys = self._yy[y0:y1, x0:x1] - y
        ca, sa = math.cos(angle), math.sin(angle)
        u = xs * ca + ys * sa
        v = -xs * sa + ys * ca
        d = np.sqrt((u / (radius * elong)) ** 2 + (v / radius) ** 2)
        n = value_noise((y1 - y0, x1 - x0), 70, seed + 21, 3)
        n2 = value_noise((y1 - y0, x1 - x0), 14, seed + 33, 2)
        fall = np.exp(-d * d * 1.6)
        haze = fall * (0.35 + 0.65 * n) * (0.6 + 0.6 * n2) * strength
        self.t[y0:y1, x0:x1] = np.maximum(self.t[y0:y1, x0:x1], haze.astype(np.float32))

    def splotches(self, n, x, y, radius, r_lo, r_hi, thick=0.8, seed=0):
        """Irregular mid-sized splotches (torn, not round) scattered round a centre."""
        for k in range(n):
            a = rng.random() * 6.28
            d = abs(rng.normal(0, radius))
            r = rng.uniform(r_lo, r_hi)
            self.mass(x + math.cos(a) * d, y + math.sin(a) * d, r, 0.6, thick * rng.uniform(0.6, 1.0), seed=seed + k)

    def specks(self, n, origin, spread_angle, direction, dist_mean, dist_sd, r_min, r_max, alpha, tails=True, thick=0.9, far_small=True):
        """n specks flung from `origin` in a fan around `direction` (radians,
        0 = +x, the texture's up is -y): sizes on a power law (many tiny, few
        large), distances Rayleigh-like, the far ones smaller and elongated
        along their flight with a tail pointing back at the origin."""
        ox, oy = origin
        u = rng.random(n)
        sizes = r_min * (1.0 - u * (1.0 - (r_min / r_max) ** (alpha - 1.0))) ** (-1.0 / (alpha - 1.0))
        sizes = np.clip(sizes, r_min, r_max)
        angs = direction + rng.normal(0.0, spread_angle, n)
        dists = np.abs(rng.normal(dist_mean, dist_sd, n)) + rng.random(n) * dist_sd * 0.5
        # far specks are the fast small ones
        if far_small:
            order = np.argsort(dists)
            sizes = np.sort(sizes)[::-1][np.argsort(order)]
            sizes = sizes * (0.6 + 0.8 * rng.random(n))
        for i in range(n):
            x = ox + math.cos(angs[i]) * dists[i]
            y = oy + math.sin(angs[i]) * dists[i]
            if x < 2 or x >= R - 2 or y < 2 or y >= R - 2:
                continue
            r = float(sizes[i])
            # elongation grows with distance (speed) for the bigger drops
            far = min(dists[i] / (dist_mean + 2 * dist_sd), 1.0)
            el = 1.0 + (0.3 + 1.6 * far) * (1.0 if r > 1.5 else 0.3) * rng.random()
            tail = (r * (0.8 + 4.0 * far) * rng.random()) if (tails and r > 1.8 and rng.random() < 0.55) else 0.0
            self.drop(x, y, r, el, angs[i], thick * (0.7 + 0.3 * rng.random()), tail)


def finish(c: Canvas, name: str, out_dir: str, edge_break=0.08, wet=1.0, seed=0):
    """Thickness field -> colour, normal, ORM at OUT, written as PNG."""
    t = c.t
    # break the edges: the coverage threshold wanders with fine noise so the
    # outlines are torn and the thinnest specks fall apart into dust
    n = value_noise((R, R), 6, seed + 11, 2)
    cov = np.clip((t - edge_break * (0.4 + n)) / 0.12, 0.0, 1.0)
    thick = np.clip(t, 0.0, 1.0)
    # colour by thickness: thin edges bright arterial red, thick dark, with a
    # little hue noise (browner, bluer) across the splat
    hue = value_noise((R, R), 160, seed + 5, 2)
    # (24 Nov, Andrew on the first in-game look: "too big, wrong colour, too
    # bright") darker throughout: the thin edges a deep red, not pink
    # (second correction) real blood's albedo is low: thin edges ~0.2 linear
    # (a saturated red under light, salmon only when lit hard), thick near-black
    thin = np.array([0.21, 0.012, 0.010], dtype=np.float32)
    deep = np.array([0.045, 0.003, 0.004], dtype=np.float32)
    k = (thick ** 0.7)[..., None]
    rgb = thin * (1.0 - k) + deep * k
    rgb = rgb * (0.9 + 0.2 * hue[..., None])
    rgb[..., 1] *= 1.0 + 0.5 * (hue - 0.5)
    # the colour map is linear here; store sRGB
    srgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(np.clip(rgb, 0, 1), 1 / 2.4) - 0.055)
    a = cov * np.clip(0.45 + 1.0 * thick ** 0.5, 0.0, 1.0)     # drops opaque, the haze faint
    rgba = np.concatenate([np.clip(srgb, 0, 1), a[..., None]], axis=-1)
    col = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((OUT, OUT), Image.BOX)
    col.save(os.path.join(out_dir, f"splat_{name}.png"))
    # normal from the thickness (a small dome per drop)
    h = Image.fromarray((thick * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    hh = np.asarray(h).astype(np.float32) / 255.0 * 0.9
    gy, gx = np.gradient(hh)
    nx = -gx * 1.5; ny = gy * 1.5; nz = np.ones_like(hh)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    Image.fromarray((nrm * 255).astype(np.uint8), "RGB").resize((OUT_AUX, OUT_AUX), Image.BOX).save(os.path.join(out_dir, f"splat_{name}_n.png"))
    # ORM: occlusion 1, roughness low where thick and wet, metallic 0
    rough = 0.72 - 0.25 * wet * thick ** 0.5      # wet, not lacquered: a thick mass under a lamp went pale with its own highlight
    orm = np.stack([np.ones_like(rough), rough, np.zeros_like(rough)], -1)
    Image.fromarray((np.clip(orm, 0, 1) * 255).astype(np.uint8), "RGB").resize((OUT_AUX, OUT_AUX), Image.BOX).save(os.path.join(out_dir, f"splat_{name}_orm.png"))


# --- the kinds -------------------------------------------------------------------------
UP = -math.pi / 2   # the travel direction in the texture: up


def gen_mist(i):
    c = Canvas()
    ox = R * 0.5 + rng.normal(0, R * 0.04)
    oy = R * 0.8
    n = int(rng.integers(14000, 24000))
    # the haze first: a wide fan of blood too fine to resolve
    c.wash(ox, oy - R * 0.22, R * 0.3, 0.08, 1.3, UP, seed=i)
    # the fan: a dense core along the travel line, a wide base, and the fast
    # fine specks far out; sizes many tiny, few medium; the fan is broad
    c.specks(int(n * 0.55), (ox, oy), 0.55, UP, R * 0.36, R * 0.2, 0.8, 9.0, 2.15, tails=True, thick=1.0)
    c.specks(int(n * 0.3), (ox, oy), 0.8, UP, R * 0.22, R * 0.14, 0.8, 5.0, 2.3, tails=False, thick=0.9)
    c.specks(int(n * 0.15), (ox, oy), 1.2, UP, R * 0.12, R * 0.12, 0.8, 3.0, 2.3, tails=False, thick=0.8)
    # mid-sized torn splotches in the core, and larger drops with tails
    c.splotches(int(rng.integers(10, 22)), ox, oy - R * 0.2, R * 0.13, 8, 30, 0.95, seed=700 + i * 20)
    for _ in range(int(rng.integers(50, 110))):
        a = UP + rng.normal(0, 0.5)
        d = abs(rng.normal(R * 0.22, R * 0.14)) + R * 0.05
        c.drop(ox + math.cos(a) * d, oy + math.sin(a) * d, rng.uniform(4, 15), 1.9, a, 0.95, rng.uniform(10, 70))
    return c, 0.05


def fingers(c: Canvas, cx, cy, rad, count, w_lo, w_hi, len_lo, len_hi):
    """Splash fingers from a mass: tapered, slightly curving, a bulb at the end,
    thinner and more broken toward the tip."""
    for _ in range(count):
        a = rng.uniform(0, 6.28)
        ln = rng.uniform(len_lo, len_hi) * rad
        w = rng.uniform(w_lo, w_hi)
        curve = rng.normal(0, 0.25)
        steps = int(ln / 2.5)
        for s_ in range(steps):
            f = s_ / steps
            aa = a + curve * f * f
            d = rad * 0.75 + f * ln
            ww = w * (1.0 - 0.75 * f) ** 1.1 + 0.7
            c.drop(cx + math.cos(aa) * d, cy + math.sin(aa) * d, ww, 1.0, aa, (0.95 - 0.35 * f) * (1.0 if f < 0.75 else rng.uniform(0.3, 1.0)))
        aa = a + curve
        c.drop(cx + math.cos(aa) * (rad * 0.75 + ln), cy + math.sin(aa) * (rad * 0.75 + ln), w * rng.uniform(1.2, 2.0), 1.4, aa, 0.95)
        # a couple of drops thrown further along the finger's line
        for _k in range(int(rng.integers(0, 3))):
            dd = rad * 0.75 + ln * rng.uniform(1.1, 1.7)
            c.drop(cx + math.cos(aa) * dd, cy + math.sin(aa) * dd, w * rng.uniform(0.5, 1.1), 1.8, aa, 0.9, w * rng.uniform(2, 6))


def gen_impact(i):
    c = Canvas()
    cx, cy = R * 0.5 + rng.normal(0, 40), R * 0.42 + rng.normal(0, 40)
    rad = rng.uniform(110, 190)
    c.wash(cx, cy, rad * 2.2, 0.18, 1.0, 0.0, seed=i + 40)
    c.mass(cx, cy, rad, 0.4, 1.0, seed=100 + i)
    # the burst leans one way (the blood came in at an angle): fingers and
    # long thin spines mostly on that side
    lean = rng.random() * 6.28
    fingers(c, cx, cy, rad, int(rng.integers(5, 10)), 7, 16, 0.5, 1.8)
    for _ in range(int(rng.integers(8, 20))):
        a = lean + rng.normal(0, 0.7)
        ln = rng.uniform(rad * 1.2, rad * 3.2)
        steps = int(ln / 3)
        for s_ in range(steps):
            f = s_ / steps
            if rng.random() < 0.55 + 0.4 * (1 - f):
                c.drop(cx + math.cos(a) * (rad * 0.8 + f * ln), cy + math.sin(a) * (rad * 0.8 + f * ln), 1.4 * (1.0 - 0.5 * f) + 0.6, 1.4, a, 0.85)
    c.splotches(int(rng.integers(4, 10)), cx + math.cos(lean) * rad * 1.3, cy + math.sin(lean) * rad * 1.3, rad * 0.9, 5, 18, 0.9, seed=800 + i * 20)
    # the halo: specks in every direction, tails pointing outward, dense near
    for a0 in np.linspace(0, 6.28, 10, endpoint=False):
        c.specks(int(rng.integers(500, 900)), (cx, cy), 0.4, a0 + rng.random() * 0.6, rad * 1.5, rad * 1.0, 0.8, 7.0, 2.2, tails=True, thick=1.0)
    c.specks(int(rng.integers(600, 1200)), (cx, cy), 3.2, 0.0, rad * 2.6, rad * 1.2, 0.7, 3.0, 2.4, tails=False, thick=0.9, far_small=False)
    # drips from the bottom of the mass
    for _ in range(int(rng.integers(2, 6))):
        x = cx + rng.uniform(-rad * 0.7, rad * 0.7)
        y = cy + rad * rng.uniform(0.5, 0.85)
        c.run(x, y, rng.uniform(80, 560), rng.uniform(6, 13), 0.95, 1.4, wobble=4.0)
    return c, 0.07


def gen_castoff(i):
    c = Canvas()
    # an arc: centre off the texture, radius large, a span of 70-130 degrees
    rad = rng.uniform(R * 0.45, R * 0.8)
    a0 = rng.uniform(0, 6.28)
    span = math.radians(rng.uniform(70, 130))
    cx = R * 0.5 - math.cos(a0 + span * 0.5) * rad * 0.75
    cy = R * 0.5 - math.sin(a0 + span * 0.5) * rad * 0.75
    n = int(rng.integers(200, 360))
    # the arc is not even: the swing threw blood in bursts, with gaps
    ph = rng.random() * 6.28
    for k in range(n):
        f = k / n
        dens = 0.55 + 0.45 * math.sin(f * 9.0 + ph) * math.sin(f * 23.0 + ph * 2)
        if rng.random() > dens:
            continue
        a = a0 + f * span + rng.normal(0, 0.014)
        d = rad * (1.0 + rng.normal(0, 0.035))
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        tangent = a + math.pi / 2
        r = (26.0 * (1.0 - f) ** 1.2 + 1.5) * rng.uniform(0.25, 1.3)
        c.drop(x, y, r, 1.3 + 1.4 * f, tangent, 0.98, r * rng.uniform(1.5, 4.5) * (0.4 + f), 0.45)
        # satellites and the fine spray thrown off the arc
        for _ in range(int(rng.integers(1, 8))):
            c.drop(x + rng.normal(0, 40), y + rng.normal(0, 40), rng.uniform(0.7, 4.0), 1.4, tangent, 0.85)
    # a second swing, or the back-swing, crossing it
    if rng.random() < 0.8:
        a1 = a0 + rng.uniform(-0.9, 0.9)
        span2 = math.radians(rng.uniform(60, 110))
        rad2 = rad * rng.uniform(0.7, 1.2)
        cx2 = cx + rng.normal(0, R * 0.12); cy2 = cy + rng.normal(0, R * 0.12)
        for k in range(int(n * 0.5)):
            f = k / (n * 0.5)
            a = a1 + f * span2 + rng.normal(0, 0.014)
            x, y = cx2 + math.cos(a) * rad2 * (1.0 + rng.normal(0, 0.03)), cy2 + math.sin(a) * rad2 * (1.0 + rng.normal(0, 0.03))
            r = (16.0 * (1.0 - f) + 1.5) * rng.uniform(0.4, 1.3)
            c.drop(x, y, r, 1.4 + 1.2 * f, a + math.pi / 2, 0.9, r * rng.uniform(1.0, 4.0) * (0.4 + f), 0.45)
    # a thinner second arc, inside, from the same swing
    if rng.random() < 0.7:
        rad2 = rad * rng.uniform(0.86, 0.94)
        for k in range(int(n * 0.6)):
            f = k / (n * 0.6)
            a = a0 + f * span * rng.uniform(0.8, 1.0) + rng.normal(0, 0.02)
            x, y = cx + math.cos(a) * rad2, cy + math.sin(a) * rad2
            c.drop(x, y, (6.0 * (1.0 - f) + 0.8) * rng.uniform(0.5, 1.2), 1.6, a + math.pi / 2, 0.8, rng.uniform(0, 14), 0.5)
    return c, 0.07


def gen_dripfield(i):
    c = Canvas()
    n = int(rng.integers(26, 60))
    fx, fy = R * 0.5 + rng.normal(0, R * 0.08), R * 0.32 + rng.normal(0, R * 0.05)
    c.wash(fx, fy, R * 0.3, 0.16, 1.1, 0.0, seed=i + 60)
    for _ in range(n):
        x = np.clip(fx + rng.normal(0, R * 0.17), R * 0.06, R * 0.94)
        y = np.clip(fy + rng.normal(0, R * 0.12), R * 0.06, R * 0.6)
        r = rng.uniform(12, 40)
        c.drop(x, y, r, 1.15, math.pi / 2, 1.0)
        for _k in range(int(rng.integers(2, 9))):
            c.drop(x + rng.normal(0, r * 2.2), y + rng.normal(0, r * 2.2), rng.uniform(0.8, r * 0.25), 1.3, rng.random() * 6.28, 0.85)
        if rng.random() < 0.8:
            c.run(x, y + r * 0.4, rng.uniform(30, 700) * (r / 14.0) ** 0.6, r * 0.5, 1.0, 1.25, wobble=4.0)
    # fine specks between
    c.specks(int(rng.integers(300, 900)), (R * 0.5, R * 0.3), 3.0, 0.0, R * 0.25, R * 0.15, 0.6, 3.0, 2.4, tails=False, thick=0.5, far_small=False)
    return c, 0.08


def gen_heavy(i):
    c = Canvas()
    cx, cy = R * 0.5 + rng.normal(0, 50), R * 0.36 + rng.normal(0, 30)
    rad = rng.uniform(240, 340)
    c.wash(cx, cy, rad * 2.6, 0.26, 1.0, 0.0, seed=i + 80)
    c.wash(cx, cy + rad * 0.9, rad * 1.6, 0.2, 0.7, math.pi / 2, seed=i + 90)
    c.mass(cx, cy, rad, 0.5, 1.0, seed=300 + i)
    c.mass(cx, cy, rad * 0.55, 0.5, 1.0, seed=360 + i)        # the thick centre
    # a second, offset mass: the hit was not one neat blob
    c.mass(cx + rng.normal(0, rad * 0.5), cy + rng.normal(0, rad * 0.4), rad * rng.uniform(0.4, 0.7), 0.5, 0.9, seed=330 + i)
    fingers(c, cx, cy, rad, int(rng.integers(7, 14)), 9, 22, 0.4, 1.4)
    for a0 in np.linspace(0, 6.28, 12, endpoint=False):
        c.specks(int(rng.integers(500, 900)), (cx, cy), 0.4, a0 + rng.random(), rad * 1.4, rad * 0.9, 0.8, 8.0, 2.2, tails=True, thick=1.0)
    c.specks(int(rng.integers(1500, 3000)), (cx, cy), 3.2, 0.0, rad * 2.2, rad * 1.0, 0.7, 3.5, 2.4, tails=False, thick=0.9, far_small=False)
    # the run-down: many drips of all lengths from the mass's lower edge
    for _ in range(int(rng.integers(7, 15))):
        x = cx + rng.uniform(-rad * 0.9, rad * 0.9)
        y = cy + rad * rng.uniform(0.5, 0.9)
        c.run(x, y, rng.uniform(80, 1000), rng.uniform(9, 24), 1.0, 1.3, wobble=6.0)
    return c, 0.08


def gen_streak(i):
    """A glancing hit: the blood hit at a shallow angle and was dragged along
    the surface (the texture's up): a dense head where it landed, pulled out
    into parallel streaks that thin and break, specks thrown on ahead."""
    c = Canvas()
    cx = R * 0.5 + rng.normal(0, 30)
    head_y = R * 0.62 + rng.normal(0, 40)
    ln = rng.uniform(R * 0.35, R * 0.6)        # how far it was dragged (upward)
    hw = rng.uniform(55, 110)                  # the head's half-width
    c.mass(cx, head_y, hw * 1.1, 0.45, 1.0, seed=500 + i)
    # the streaks: several ribbons leaving the head, each its own length
    for k in range(int(rng.integers(5, 11))):
        x = cx + rng.uniform(-hw * 0.9, hw * 0.9)
        l = ln * rng.uniform(0.35, 1.0)
        w = rng.uniform(5, 18) * (1.0 - abs(x - cx) / (hw * 1.4))
        ph = rng.random() * 6.28
        steps = int(l / 2.5)
        for s_ in range(steps):
            f = s_ / steps
            xx = x + 6 * math.sin(f * 7 + ph) * f + rng.normal(0, 0.4)
            ww = w * (1.0 - 0.7 * f) ** 1.3 + 0.6
            on = 1.0 if (f < 0.5 or rng.random() < 0.75 - 0.4 * f) else 0.0
            c.drop(xx, head_y - f * l, ww, 1.0, 0.0, (0.95 - 0.5 * f) * on)
        c.drop(x + 6 * math.sin(7 + ph), head_y - l, w * 1.2, 2.2, UP, 0.8, w * rng.uniform(2, 6))
    # specks thrown on ahead of the smear, and a few back behind the head
    c.specks(int(rng.integers(600, 1200)), (cx, head_y), 0.22, UP, ln * 0.7, ln * 0.35, 0.7, 5.0, 2.3, tails=True, thick=0.8)
    c.specks(int(rng.integers(100, 300)), (cx, head_y), 0.5, -UP, hw * 1.5, hw, 0.7, 3.0, 2.3, tails=False, thick=0.6)
    return c, 0.07


def gen_small(i):
    c = Canvas()
    cx, cy = R * 0.5, R * 0.5
    kind = i % 4
    if kind == 0:        # round drop
        c.drop(cx, cy, rng.uniform(90, 160), 1.05, rng.random() * 6.28, 1.0)
    elif kind == 1:      # elongated
        c.drop(cx, cy, rng.uniform(70, 120), rng.uniform(1.6, 2.4), UP, 1.0)
    elif kind == 2:      # with a tail
        c.drop(cx, cy + 120, rng.uniform(70, 120), 1.5, UP, 1.0, rng.uniform(250, 500), 0.4)
    else:                # a cluster of three or four
        for _ in range(int(rng.integers(3, 6))):
            c.drop(cx + rng.normal(0, 150), cy + rng.normal(0, 150), rng.uniform(30, 90), rng.uniform(1.0, 1.8), rng.random() * 6.28, 0.95)
    c.specks(int(rng.integers(20, 80)), (cx, cy), 3.0, 0.0, 200, 120, 2.0, 12.0, 2.3, tails=True, thick=0.8, far_small=False)
    return c, 0.07


def gen_dripmask(out_dir):
    """Phase D's animated runs: R = time of arrival (0 at the top of each run,
    1 at its end), G = the run's shape (coverage), B = the bead's growth.
    Eight runs across a 512 x 1024 texture; the shader shows G where R < t."""
    W, H = 512, 1024
    rmap = np.ones((H, W), dtype=np.float32)
    gmap = np.zeros((H, W), dtype=np.float32)
    bmap = np.zeros((H, W), dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    g = np.random.default_rng(5)
    for k in range(8):
        x = W * (k + 0.5) / 8 + g.normal(0, 8)
        length = g.uniform(H * 0.35, H * 0.95)
        width = g.uniform(5, 11)
        ph = g.random() * 6.28
        for yi in range(int(length)):
            s = yi / length
            xc = x + 7 * math.sin(yi * 0.03 + ph) * s + 3 * math.sin(yi * 0.11 + ph * 3)
            w = width * (1.0 - 0.5 * s)
            d = np.abs(xx[yi] - xc)
            cov = np.clip(1.0 - (d - w * 0.6) / (w * 0.5), 0, 1)
            gmap[yi] = np.maximum(gmap[yi], cov)
            rmap[yi] = np.where(cov > 0.05, np.minimum(rmap[yi], s ** 1.2), rmap[yi])
        # the bead
        bx = x + 7 * math.sin(length * 0.03 + ph)
        d = np.sqrt((xx - bx) ** 2 + (yy - length) ** 2)
        bead = np.clip(1.0 - (d - width * 1.4) / (width * 0.8), 0, 1)
        bmap = np.maximum(bmap, bead)
        gmap = np.maximum(gmap, bead)
        rmap = np.where(bead > 0.05, np.minimum(rmap, 1.0), rmap)
    img = np.stack([rmap, gmap, bmap], -1)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(out_dir, "drip_mask.png"))


GENS = {"mist": gen_mist, "impact": gen_impact, "castoff": gen_castoff, "dripfield": gen_dripfield, "heavy": gen_heavy, "streak": gen_streak, "small": gen_small}


def main():
    out_dir = "art/blood/splat2"
    sheet = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--seed":
            global rng
            rng = np.random.default_rng(int(args[i + 1])); i += 2
        elif args[i] == "--sheet":
            sheet = args[i + 1]; i += 2
        else:
            out_dir = args[i]; i += 1
    os.makedirs(out_dir, exist_ok=True)
    tiles = []
    for kind, n in KINDS.items():
        for k in range(n):
            c, eb = GENS[kind](k)
            name = f"{kind}_{k}"
            finish(c, name, out_dir, edge_break=eb, seed=hash(name) % 1000)
            print("wrote", name)
            if sheet:
                im = Image.open(os.path.join(out_dir, f"splat_{name}.png")).resize((256, 256))
                bg = Image.new("RGBA", (256, 256), (215, 210, 200, 255))
                bg.alpha_composite(im)
                tiles.append(bg)
    gen_dripmask(out_dir)
    print("wrote drip_mask")
    if sheet:
        cols = 8
        rows = (len(tiles) + cols - 1) // cols
        s = Image.new("RGBA", (256 * cols, 256 * rows), (30, 30, 30, 255))
        for i, t in enumerate(tiles):
            s.paste(t, ((i % cols) * 256, (i // cols) * 256))
        s.save(sheet)


if __name__ == "__main__":
    main()
