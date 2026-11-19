"""Blood splatter decal library (19 Nov 2026 overhaul) -> art/blood/splat/ and art/oil/splat/.

Reference: a real impact splatter on the ground (a large ragged stain, directional
spray, hundreds of fine droplets, thin elongated marks, darker overlaps), close-up
blood (crimson to near-black, broken wet highlights, irregular roughness), and a
pool (organic lobes, darker centre, satellite drops).

Every variant writes three maps (drawn at 1024 and filtered down; colour at 512 px,
the softer normal and ORM maps, and oil's colour, at 256 px):
  <name>.png      colour + alpha. Thin fresh streaks brighter red, crimson, dark red,
                  near-black where thick; brownish oxidised patches; fine mottling.
  <name>_n.png    normal (OpenGL, +Y up): domed droplets, a faint clotted skin.
  <name>_orm.png  R occlusion, G roughness, B metallic (0: blood is a dielectric).
                  Thick + fresh: 0.2-0.4, broken by duller clotted patches; mid
                  0.4-0.65; thin smears 0.65-0.9; droplet crowns wet (small highlights).
Oil (the Klappersoldat) gets the same shapes in near-black machine oil.

Kinds (texture "up", +v, is the direction the blood was travelling):
  spray   directional exit spray: small source, a cone of elongated drops and streaks
  impact  heavy splash: big ragged stain, overlapping lobes, spikes, satellites
  small   a compact bullet splat with a few satellites
  streak  glancing smear: dragged along +v with striations
  drip    back-spatter: a few round drops with crowns
  death   broad death splatter: several concentrations, complex edges, many drops

Run: python3 tools/gen_blood_splatters.py  (numpy + Pillow). Deterministic (seeded).
"""
import os, math
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'art', 'blood', 'splat')
OUT_OIL = os.path.join(ROOT, 'art', 'oil', 'splat')
os.makedirs(OUT, exist_ok=True)
os.makedirs(OUT_OIL, exist_ok=True)
S = 1024            # drawn at this size
FINAL = 512         # written at this size

KINDS = (('spray', 6), ('impact', 5), ('small', 4), ('streak', 4), ('drip', 3), ('death', 4))


# --- noise -----------------------------------------------------------------
def value_noise(size, cells, rng):
    g = rng.random((cells + 1, cells + 1))
    g[-1, :] = g[0, :]; g[:, -1] = g[:, 0]
    t = np.linspace(0, cells, size, endpoint=False)
    i = t.astype(int); f = t - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i]; b = g[i][:, i + 1]; c = g[i + 1][:, i]; d = g[i + 1][:, i + 1]
    FX = f[None, :]; FY = f[:, None]
    return (a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY


def fbm(size, cells, rng, octaves=4, gain=0.5):
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += value_noise(size, cells * 2 ** o, rng) * amp
        tot += amp; amp *= gain
    return out / tot


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, n=1):
    for _ in range(n):
        a = (a * 2 + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 6.0
    return a


YY, XX = np.mgrid[0:S, 0:S]
U = (XX + 0.5) / S                    # 0..1 left to right
V = 1.0 - (YY + 0.5) / S              # 0..1 bottom to top (texture "up" is +v)


class Field:
    """Thickness of blood, 0..1+, built from stamps."""
    def __init__(self):
        self.h = np.zeros((S, S))
        self.drop = np.zeros((S, S))   # 1 on separate droplets (wet, domed crowns)

    def ellipse(self, x, y, r, ang=0.0, elong=1.0, strength=1.0, droplet=False, tail=0.0):
        """A drop at (x, y) (0..1), radius r, stretched `elong` times along `ang`;
        `tail` adds a tapering tail behind it (opposite `ang`) of that many radii."""
        ra = r * elong
        reach = ra * (1.0 + tail) + 2.0 / S
        x0, x1 = int(max(0, (x - reach) * S - 2)), int(min(S, (x + reach) * S + 3))
        y0, y1 = int(max(0, (1 - y - reach) * S - 2)), int(min(S, (1 - y + reach) * S + 3))
        if x0 >= x1 or y0 >= y1:
            return
        u = U[y0:y1, x0:x1] - x
        v = V[y0:y1, x0:x1] - y
        ca, sa = math.cos(ang), math.sin(ang)
        a = u * ca + v * sa            # along the travel
        b = -u * sa + v * ca           # across it
        d = np.sqrt((a / ra) ** 2 + (b / r) ** 2)
        prof = np.clip(1.0 - d, 0, 1)
        if tail > 0.0:
            # a tail tapering away behind the head (the drop came from there)
            t = np.clip(-a / (ra * tail + 1e-6), 0, 1)
            w = r * 0.55 * (1.0 - t) ** 1.5 + 0.6 / S
            tp = np.clip(1.0 - np.abs(b) / w, 0, 1) * (a < 0) * (t < 1)
            prof = np.maximum(prof, tp * 0.6)
        prof = np.sqrt(prof) * strength            # domed: liquid stands up off the floor
        self.h[y0:y1, x0:x1] = np.maximum(self.h[y0:y1, x0:x1], prof)
        if droplet:
            self.drop[y0:y1, x0:x1] = np.maximum(self.drop[y0:y1, x0:x1], (prof > 0.05) * 1.0)

    def stain(self, cx, cy, R, lobes, rng, aspect=1.0, ang=0.0, rag=0.32, strength=1.0):
        """A ragged stain: overlapping lobes, the edge cut by warped noise."""
        f = np.zeros((S, S))
        wu = (fbm(S, 5, rng, 4) - 0.5) * 0.09 * (R / 0.15)      # domain warp: lobes bend and bulge
        wv = (fbm(S, 5, rng, 4) - 0.5) * 0.09 * (R / 0.15)
        UW = U + wu; VW = V + wv
        for k in range(lobes):
            a = rng.uniform(0, 2 * math.pi)
            d = R * rng.uniform(0.0, 0.75)
            lx = cx + math.cos(a) * d * aspect * math.cos(ang) - math.sin(a) * d * math.sin(ang)
            ly = cy + math.cos(a) * d * aspect * math.sin(ang) + math.sin(a) * d * math.cos(ang)
            lr = R * rng.uniform(0.35, 0.75)
            uu = UW - lx; vv = VW - ly
            aa = (uu * math.cos(ang) + vv * math.sin(ang)) / aspect
            bb = -uu * math.sin(ang) + vv * math.cos(ang)
            f += np.exp(-(aa * aa + bb * bb) / (lr * lr)) * rng.uniform(0.7, 1.2)
        # warp the edge: big wobble plus fine teeth
        wob = fbm(S, 4, rng, 4) - 0.5
        teeth = fbm(S, 24, rng, 3) - 0.5
        scal = fbm(S, 60, rng, 2) - 0.5            # small scallops all round the edge
        g = f + wob * rag + teeth * rag * 0.7 + scal * rag * 0.35
        inside = sstep(0.44, 0.48, g)
        # uneven inside: thinner crimson patches and a few pinholes, not a flat slab
        body = np.clip(0.4 + 0.45 * f, 0, 1.3) * (0.55 + 0.75 * blur(fbm(S, 9, rng, 4), 3))
        holes = sstep(0.8, 0.86, fbm(S, 70, rng, 2)) * sstep(0.3, 0.8, inside)
        self.h = np.maximum(self.h, inside * np.clip(body, 0.18, 1.4) * strength * (1.0 - 0.45 * holes))

    def streak(self, x, y, ang, length, w0, w1, rng, wobble=0.012):
        n = max(8, int(length * S / 2.5))
        px, py = x, y
        for i in range(n + 1):
            t = i / n
            px = x + math.cos(ang) * length * t + math.sin(t * 9 + x * 40) * wobble * t
            py = y + math.sin(ang) * length * t
            self.ellipse(px, py, max(w0 + (w1 - w0) * t, 0.7 / S), ang, 1.0, 0.75)
        self.ellipse(px, py, w1 * rng.uniform(1.4, 2.4), ang, 1.3, 1.0, droplet=True)


def cone_drops(f, ox, oy, rng, n, spread, reach, rmin, rmax, ang=math.pi / 2, elong_k=3.5, tails=True):
    """Drops thrown from (ox, oy) in a cone about `ang`: many tiny, few big;
    stretched along their flight the further they went."""
    for k in range(n):
        a = ang + rng.normal(0, spread)
        t = rng.beta(1.3, 2.4) * reach
        r = rmin * (rmax / rmin) ** (rng.random() ** 3.2) * (1.15 - 0.6 * t / max(reach, 1e-3))
        x, y = ox + math.cos(a) * t, oy + math.sin(a) * t
        if not (0.03 < x < 0.97 and 0.03 < y < 0.97):
            continue
        el = 1.0 + elong_k * (t / reach) * rng.uniform(0.4, 1.2)
        f.ellipse(x, y, r, a, el, droplet=True, tail=(rng.uniform(0.5, 3.0) if tails and rng.random() < 0.45 else 0.0))


def mist(f, cx, cy, rng, n, rad, rmax=1.4 / 1024 * 2.2):
    for k in range(n):
        a = rng.uniform(0, 2 * math.pi); d = abs(rng.normal(0, rad))
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        if 0.02 < x < 0.98 and 0.02 < y < 0.98:
            f.ellipse(x, y, rng.uniform(0.8 / S, rmax), 0, 1.0, rng.uniform(0.5, 1.0), droplet=True)


# --- the kinds ---------------------------------------------------------------
def k_spray(rng):
    f = Field(); ox, oy = 0.5 + rng.uniform(-0.04, 0.04), rng.uniform(0.12, 0.2)
    f.stain(ox, oy + 0.03, rng.uniform(0.03, 0.05), rng.integers(3, 6), rng, aspect=rng.uniform(1.3, 2.0), ang=math.pi / 2, rag=0.5)
    spread = rng.uniform(0.18, 0.34)
    cone_drops(f, ox, oy, rng, rng.integers(250, 450), spread * 1.3, 0.26, 1.2 / S, 0.011, elong_k=1.5)   # the dense spatter cloud
    cone_drops(f, ox, oy + 0.03, rng, rng.integers(260, 520), spread, rng.uniform(0.62, 0.8), 1.0 / S, 0.017)
    for k in range(rng.integers(5, 12)):           # thin marks flung furthest
        a = math.pi / 2 + rng.normal(0, spread * 0.8)
        L = rng.uniform(0.12, 0.38); s = rng.uniform(0.05, 0.16)
        f.streak(ox + math.cos(a) * s, oy + math.sin(a) * s, a, L, rng.uniform(0.002, 0.005), rng.uniform(0.001, 0.003), rng, 0.004)
    mist(f, ox, oy + 0.15, rng, rng.integers(250, 500), 0.16)
    return f


def k_impact(rng):
    f = Field(); cx, cy = 0.5 + rng.uniform(-0.03, 0.03), 0.48 + rng.uniform(-0.03, 0.03)
    R = rng.uniform(0.15, 0.2)
    f.stain(cx, cy, R, rng.integers(6, 11), rng, aspect=rng.uniform(1.0, 1.35), ang=rng.uniform(0, math.pi), rag=0.38)
    f.stain(cx + rng.normal(0, 0.06), cy + rng.normal(0, 0.06), R * 0.55, 4, rng, rag=0.3, strength=1.25)   # a deeper overlap
    for k in range(rng.integers(10, 20)):          # spikes thrown outward
        a = rng.uniform(0, 2 * math.pi); L = rng.uniform(0.06, 0.2)
        s = R * rng.uniform(0.75, 1.0)
        f.streak(cx + math.cos(a) * s, cy + math.sin(a) * s, a, L, rng.uniform(0.006, 0.014), rng.uniform(0.002, 0.005), rng, 0.0)
    for k in range(rng.integers(120, 260)):        # satellites
        a = rng.uniform(0, 2 * math.pi); d = R * 0.9 + abs(rng.normal(0, 0.12))
        if d > 0.47:
            continue
        r = 1.0 / S * (14.0 / 1.0) ** (rng.random() ** 2.8) * (1.25 - d)
        f.ellipse(cx + math.cos(a) * d, cy + math.sin(a) * d, r, a, 1.0 + 3.0 * (d - R) * rng.random(), droplet=True,
                  tail=(rng.uniform(0.5, 2.0) if rng.random() < 0.35 else 0.0))
    mist(f, cx, cy, rng, rng.integers(200, 400), 0.22)
    return f


def k_small(rng):
    f = Field(); cx, cy = 0.5 + rng.uniform(-0.02, 0.02), 0.5 + rng.uniform(-0.02, 0.02)
    R = rng.uniform(0.1, 0.14)
    f.stain(cx, cy, R, rng.integers(3, 6), rng, aspect=rng.uniform(1.0, 1.5), ang=rng.uniform(0, math.pi), rag=0.42)
    for k in range(rng.integers(30, 80)):
        a = rng.uniform(0, 2 * math.pi); d = R * 0.9 + abs(rng.normal(0, 0.1))
        if d > 0.45:
            continue
        r = 1.0 / S * 10.0 ** (rng.random() ** 2.5)
        f.ellipse(cx + math.cos(a) * d, cy + math.sin(a) * d, r, a, 1.0 + 2.0 * rng.random(), droplet=True)
    mist(f, cx, cy, rng, rng.integers(60, 140), 0.16)
    return f


def k_streak(rng):
    f = Field(); x0 = 0.5 + rng.uniform(-0.05, 0.05)
    f.stain(x0, 0.3, rng.uniform(0.07, 0.1), 4, rng, aspect=rng.uniform(2.5, 3.5), ang=math.pi / 2, rag=0.35)
    # dragged smear: striations along +v
    stria = fbm(S, 3, rng, 3)
    cols = value_noise(S, 40, rng)
    band = sstep(0.0, 0.08, 0.17 - np.abs(U - x0 - (stria - 0.5) * 0.08)) * sstep(0.12, 0.2, V) * sstep(0.95, 0.55, V)
    strands = sstep(0.35, 0.65, cols[0][None, :].repeat(S, 0) * 0.7 + stria * 0.3)
    breaks = sstep(0.4, 0.6, fbm(S, 12, rng, 3))
    f.h = np.maximum(f.h, band * (0.05 + 0.5 * strands * breaks) * (1.0 - 0.7 * sstep(0.3, 0.95, V)))
    for k in range(rng.integers(3, 7)):
        f.streak(x0 + rng.normal(0, 0.08), rng.uniform(0.2, 0.4), math.pi / 2 + rng.normal(0, 0.05), rng.uniform(0.25, 0.5),
                 rng.uniform(0.006, 0.014), rng.uniform(0.002, 0.004), rng, 0.006)
    cone_drops(f, x0, 0.35, rng, rng.integers(60, 140), 0.25, 0.55, 1.0 / S, 0.008)
    return f


def k_drip(rng):
    f = Field()
    for k in range(rng.integers(3, 7)):
        x, y = 0.5 + rng.normal(0, 0.14), 0.5 + rng.normal(0, 0.14); r = rng.uniform(0.025, 0.07)
        if not (0.14 < x < 0.86 and 0.14 < y < 0.86):
            continue
        f.stain(x, y, r, 3, rng, rag=0.25)
        for j in range(rng.integers(5, 12)):       # crown
            a = rng.uniform(0, 2 * math.pi)
            f.ellipse(x + math.cos(a) * r * 1.05, y + math.sin(a) * r * 1.05, r * rng.uniform(0.08, 0.18), a, rng.uniform(1.5, 3.0), droplet=True)
        for j in range(rng.integers(4, 12)):
            a = rng.uniform(0, 2 * math.pi); d = r * rng.uniform(1.4, 3.0)
            f.ellipse(x + math.cos(a) * d, y + math.sin(a) * d, rng.uniform(1.0, 6.0) / S, a, 1.5, droplet=True)
    return f


def k_death(rng):
    f = Field(); cx, cy = 0.5, 0.45
    for k in range(rng.integers(3, 6)):            # several concentrations, unequal
        f.stain(cx + rng.normal(0, 0.11), cy + rng.normal(0, 0.11), rng.uniform(0.06, 0.15), rng.integers(4, 8), rng,
                aspect=rng.uniform(1.0, 1.7), ang=rng.uniform(0, math.pi), rag=0.5, strength=rng.uniform(0.55, 1.3))
    cone_drops(f, cx, cy, rng, rng.integers(300, 500), 1.6, 0.3, 1.2 / S, 0.012, elong_k=1.5)
    ang = math.pi / 2 + rng.normal(0, 0.3)
    cone_drops(f, cx, cy + 0.1, rng, rng.integers(250, 450), rng.uniform(0.35, 0.6), 0.42, 1.0 / S, 0.016, ang=ang)
    for k in range(rng.integers(8, 16)):
        a = ang + rng.normal(0, 0.5); s = rng.uniform(0.12, 0.22)
        f.streak(cx + math.cos(a) * s, cy + math.sin(a) * s, a, rng.uniform(0.08, 0.25), rng.uniform(0.004, 0.01), rng.uniform(0.0015, 0.004), rng, 0.003)
    mist(f, cx, cy, rng, rng.integers(300, 600), 0.25)
    return f


FN = dict(spray=k_spray, impact=k_impact, small=k_small, streak=k_streak, drip=k_drip, death=k_death)


# --- turning thickness into the three maps ------------------------------------
def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def down(a, k=2):
    """1024 -> 512 (k 2) or 256 (k 4) by box filtering (anti-aliased edges)."""
    n = S // k
    return a.reshape(n, k, n, k, *a.shape[2:]).mean(axis=(1, 3))


SMALL = S // 4      # normal, ORM and oil colour: 256 px (soft detail; decals share one uncompressed atlas)


def finish(f, rng, name):
    h = f.h
    # border: nothing touches the decal's edge
    edge = np.minimum(np.minimum(XX, S - 1 - XX), np.minimum(YY, S - 1 - YY))
    h = h * sstep(4, 28, edge)
    pores = fbm(S, 96, rng, 2)
    grain = fbm(S, 40, rng, 3)
    # the edge of a stain soaks into the floor: pitted, broken, with a fringe of specks
    rim = 1.0 - sstep(0.15, 0.55, h)
    h = h - rim * sstep(0.45, 0.75, pores) * 0.5 * (h > 0)
    halo = blur(sstep(0.2, 0.5, f.h), 10)
    specks = sstep(0.72, 0.8, pores * 0.6 + grain * 0.4) * sstep(0.02, 0.25, halo) * (1 - sstep(0.4, 0.6, halo))
    h = np.maximum(h, specks * 0.35)
    cover = sstep(0.05, 0.13, h)
    # thickness: soaked through the stain's middle, thin at its edges and in streaks
    thick = sstep(0.12, 1.05, blur(h, 6) * 0.65 + h * 0.35)
    big = fbm(S, 3, rng, 3)                 # broad variation: drying, oxidised
    mid = fbm(S, 10, rng, 3)                # mottling
    fine = fbm(S, 48, rng, 2)               # coagulated grain
    # colour (sRGB): fresh thin red -> crimson -> dark red -> near-black, brown patches
    fresh = np.array([0.46, 0.045, 0.045]); crimson = np.array([0.32, 0.022, 0.028])
    dark = np.array([0.16, 0.012, 0.015]); black = np.array([0.065, 0.008, 0.01]); brown = np.array([0.27, 0.085, 0.05])
    t = thick[..., None]
    col = np.where(t < 0.25, fresh + (crimson - fresh) * (t / 0.25),
          np.where(t < 0.75, crimson + (dark - crimson) * ((t - 0.25) / 0.5), dark + (black - dark) * np.clip((t - 0.75) / 0.5, 0, 0.6)))
    # in thick blood, patches of crimson and of near-black (light through it, clotted)
    patch = blur(fbm(S, 8, rng, 4), 4)[..., None]
    col = col + (crimson - col) * sstep(0.55, 0.75, patch) * 0.45 * t + (black - col) * sstep(0.62, 0.35, patch) * 0.4 * t
    hue = rng.uniform(-0.04, 0.04)          # this variant's own cast
    col = col * np.array([1.0 + hue, 1.0, 1.0 - hue])
    ox = sstep(0.55, 0.8, big)[..., None] * (1.0 - 0.6 * t)          # oxidised brownish patches, mostly where thinner
    col = col + (brown - col) * ox * 0.3
    col = col * (0.86 + 0.28 * mid[..., None]) * (0.93 + 0.14 * fine[..., None])
    # darker where it overlaps itself (a second layer on top of the first)
    over = sstep(1.05, 1.3, h)[..., None]
    col = col + (black - col) * over * 0.6
    alpha = cover * (0.72 + 0.27 * sstep(0.0, 0.5, thick)) * (0.9 + 0.1 * mid)
    # roughness: thick + fresh wet, broken by duller clots; thin smears matte; drop crowns wet
    wet = sstep(0.55, 0.7, blur(fbm(S, 7, rng, 5), 6)) * sstep(0.35, 0.8, thick)     # broken wet patches
    clot = sstep(0.6, 0.74, blur(fbm(S, 16, rng, 4), 4)) * sstep(0.3, 0.7, thick)    # matte coagulated islands
    rough = 0.84 - 0.46 * sstep(0.0, 0.4, thick) - 0.14 * sstep(0.4, 1.0, thick)    # 0.84 thin .. 0.24 thick
    rough = rough - 0.12 * wet + 0.26 * clot + (mid - 0.5) * 0.08
    crown = f.drop * sstep(0.3, 0.8, h)                 # the top of each droplet
    rough = rough - 0.35 * crown
    rough = rough + 0.12 * sstep(0.6, 0.9, big) * (1 - t[..., 0])   # dried-out regions
    rough = np.clip(rough, 0.16, 0.92)
    # surface relief: the domes of drops and pools, a faint clotted skin; subtle
    # the rim stands up where blood meets the floor (it catches the light); wet
    # patches carry a fine ripple that breaks a highlight into glints
    ripple = fbm(S, 36, rng, 3) - 0.5
    hs = blur(np.minimum(h, 1.0) ** 0.6, 1) + ripple * 0.09 * wet + (fine - 0.5) * 0.05 * thick + clot * 0.04
    gx = (np.roll(hs, -1, 1) - np.roll(hs, 1, 1)) * 0.5 * S / 128.0
    gy = (np.roll(hs, -1, 0) - np.roll(hs, 1, 0)) * 0.5 * S / 128.0
    k = 5.0
    nx, ny, nz = -gx * k, gy * k, np.ones_like(hs)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln])
    # write at 512
    lin = srgb_to_lin(col)
    a2 = down(alpha)
    c2 = lin_to_srgb(down(lin * alpha[..., None]) / np.maximum(a2[..., None], 1e-4))   # colour bleed-free at edges
    rgba = np.dstack([c2, a2])
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
    n2 = down(nrm, 4); n2 = n2 / np.linalg.norm(n2, axis=2, keepdims=True)
    Image.fromarray((np.clip(n2 * 0.5 + 0.5, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, name + '_n.png'))
    orm = np.dstack([0.92 + 0.08 * (1 - down(over[..., 0], 4)), down(rough, 4), np.zeros((SMALL, SMALL))])
    Image.fromarray((np.clip(orm, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, name + '_orm.png'))
    # oil: the same shape, near-black machine oil (thin film a little browner)
    oil_c = np.where(t < 0.4, np.array([0.11, 0.095, 0.07]), np.array([0.035, 0.032, 0.028])) * (0.9 + 0.2 * mid[..., None])
    a4 = down(alpha, 4)
    o2 = lin_to_srgb(down(srgb_to_lin(oil_c) * alpha[..., None], 4) / np.maximum(a4[..., None], 1e-4))
    Image.fromarray((np.clip(np.dstack([o2, a4]), 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT_OIL, name + '.png'))
    return rgba, down(rough)


if __name__ == '__main__':
    seed = 1918
    sheet = Image.new('RGB', (8 * 256, 4 * 256), (150, 146, 138))
    rsheet = Image.new('L', (8 * 256, 4 * 256), 0)
    i = 0
    for kind, count in KINDS:
        for v in range(count):
            rng = np.random.default_rng(seed); seed += 7
            rgba, rough = finish(FN[kind](rng), rng, 'splat_%s_%d' % (kind, v))
            im = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((256, 256), Image.LANCZOS)
            sheet.paste(im, ((i % 8) * 256, (i // 8) * 256), im)
            rr = Image.fromarray((rough * 255).astype(np.uint8), 'L').resize((256, 256), Image.LANCZOS)
            rsheet.paste(rr, ((i % 8) * 256, (i // 8) * 256))
            i += 1
            print(kind, v)
    sheet.save('/tmp/blood_sheet.png')
    rsheet.save('/tmp/blood_rough_sheet.png')
    print(i, 'splats written to', OUT)
