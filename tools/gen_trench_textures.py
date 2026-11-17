"""Generates the Drowned Trenches textures into art/trench/.
Run:  python3 tools/gen_trench_textures.py   (needs numpy + Pillow)

Mud is the defining material, so there are four kinds, each with albedo,
normal (_n) and roughness (_r), all seamless:
  mud_churned  thick churned mud: clods and ridges, boot holes, water in the
               hollows, glossy between the clods (the ground up top)
  mud_sludge   trench-floor sludge: very dark, smooth and saturated, ruts and
               footprints, bits of debris pressed in
  soil_wall    a cut wall: damp soil strata, rain streaks running down, roots,
               slumped crumbs; v runs down the wall (2 m per tile)
  ground_firm  firmer ground: compact, cracked, a few dead stalks and stones
Plus corrugated iron (iron), woven hurdles (wattle), wet planks (planks_wet)
and a tiling noise (noise) the shaders use for puddles and variation."""
import os, math
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'art', 'trench')
os.makedirs(OUT, exist_ok=True)


def fbm(size, octaves, seed, aspect=(1, 1)):
    """Tileable value noise; `aspect` stretches it."""
    r = np.random.default_rng(seed)
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for g in octaves:
        gx, gy = max(1, g // aspect[0]), max(1, g // aspect[1])
        grid = r.random((gy, gx))
        xs = np.arange(size) * gx / size; ys = np.arange(size) * gy / size
        x0 = np.floor(xs).astype(int); fx = xs - x0; x1 = (x0 + 1) % gx
        y0 = np.floor(ys).astype(int); fy = ys - y0; y1 = (y0 + 1) % gy
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        a = grid[y0][:, x0]; b = grid[y0][:, x1]; c = grid[y1][:, x0]; d = grid[y1][:, x1]
        FX = fx[None, :]; FY = fy[:, None]
        out += ((a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY) * amp
        tot += amp; amp *= 0.55
    return out / tot


def worley(size, cells, seed, warp=0.0):
    """Tileable cellular noise: (distance to the nearest point, to the second), 0..~1.
    `warp` (in cells) bends the cells with noise so they are not tiles."""
    r = np.random.default_rng(seed)
    pts = r.random((cells, cells, 2))
    yy, xx = np.mgrid[0:size, 0:size] * (cells / size)
    if warp:
        xx = xx + (fbm(size, (3, 6, 12, 24), seed + 100) - 0.5) * 2 * warp
        yy = yy + (fbm(size, (3, 6, 12, 24), seed + 200) - 0.5) * 2 * warp
    cx = np.floor(xx).astype(int); cy = np.floor(yy).astype(int)
    d1 = np.full((size, size), 9.0); d2 = np.full((size, size), 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx = (cx + ox) % cells; ny = (cy + oy) % cells
            px = cx + ox + pts[ny, nx, 0]; py = cy + oy + pts[ny, nx, 1]
            dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
            d2 = np.where(dd < d1, d1, np.minimum(d2, dd))
            d1 = np.minimum(d1, dd)
    return d1, d2


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def mix(a, b, m):
    b = np.asarray(b, float)
    if b.ndim == 1:
        b = b[None, None, :]
    return a * (1 - m[..., None]) + b * m[..., None]


def blur(a, n=1):
    for _ in range(n):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def save(name, rgb, height=None, strength=3.0, rough=None, linear=False):
    """Colours are authored as linear albedo (real wet mud is about 0.08-0.15)
    and written sRGB-encoded, as Godot reads a source_color texture."""
    rgb = np.clip(rgb, 0, 1)
    if not linear:
        rgb = rgb ** (1 / 2.2)
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, name + '.png'))
    if height is not None:
        h = blur(height, 1)
        size = h.shape[0]
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength * size / 64.0
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength * size / 64.0
        nx, ny, nz = -gx, gy, np.ones_like(h)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        nrm = np.dstack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5])
        Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, name + '_n.png'))
    if rough is not None:
        Image.fromarray((np.clip(rough, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(os.path.join(OUT, name + '_r.png'))


def stamp_boots(h, n, seed, depth=0.35, scale=1.0):
    """Press boot prints into a height map: sole and heel, in walking pairs."""
    size = h.shape[0]
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    mask = np.zeros_like(h)
    for i in range(n):
        x0, y0 = r.random(2) * size
        ang = r.uniform(0, math.pi * 2)
        for step in range(r.integers(2, 5)):
            side = 1 if step % 2 else -1
            cx = x0 + math.cos(ang) * step * 120 * scale + math.cos(ang + math.pi / 2) * side * 22 * scale
            cy = y0 + math.sin(ang) * step * 120 * scale + math.sin(ang + math.pi / 2) * side * 22 * scale
            a = ang + r.normal(0, 0.15)
            dx = (xx - cx + size / 2) % size - size / 2
            dy = (yy - cy + size / 2) % size - size / 2
            u = dx * math.cos(a) + dy * math.sin(a)
            v = -dx * math.sin(a) + dy * math.cos(a)
            sole = ((u + 18 * scale) / (46 * scale)) ** 2 + (v / (17 * scale)) ** 2 < 1
            heel = ((u - 44 * scale) / (16 * scale)) ** 2 + (v / (14 * scale)) ** 2 < 1
            m = (sole | heel).astype(float)
            mask = np.maximum(mask, m * r.uniform(0.5, 1.0))
    mask = blur(mask, 3)
    return h - mask * depth, mask


S = 1024
yy, xx = np.mgrid[0:S, 0:S]

# --- thick churned mud -------------------------------------------------------------
d1, d2 = worley(S, 18, 11, warp=0.9)
e1, e2 = worley(S, 40, 16, warp=1.2)
clods = sstep(0.0, 0.7, d2 - d1) * 0.6 + sstep(0.0, 0.6, e2 - e1) * 0.4    # raised clods, creases between
clods = blur(clods, 2) * sstep(0.2, 0.55, fbm(S, (3, 6, 12), 17)) + clods * 0.35
n1 = fbm(S, (4, 8, 16, 32, 64, 128, 256), 12)
n2 = fbm(S, (3, 6, 12, 24), 13)
ridges = np.abs(fbm(S, (6, 12, 24), 14) - 0.5) * 2
h = clods * 0.55 + n1 * 0.5 + (1 - ridges) * 0.15
h, boots = stamp_boots(h, 7, 15, 0.45)
hollow = sstep(0.5, 0.36, blur(h, 6)) * sstep(0.35, 0.6, n2)   # water in the low places
col = np.zeros((S, S, 3)) + np.array([0.135, 0.105, 0.078])
col *= (0.62 + 0.55 * n1)[..., None]
col = mix(col, (0.17, 0.125, 0.085), sstep(0.55, 0.8, clods) * 0.45)    # drier crowns on the clods
col = mix(col, (0.09, 0.085, 0.08), sstep(0.45, 0.75, n2) * 0.25)       # greyer patches
col *= (1.0 - 0.22 * (1 - clods))[..., None]                            # wet dark creases
col = mix(col, (0.11, 0.1, 0.09), hollow * 0.85)                        # muddy water, opaque
h = h - hollow * 0.3
rough = 0.82 - 0.45 * (1 - clods) * 0.6 - 0.62 * hollow + 0.12 * sstep(0.6, 0.85, clods)
save('mud_churned', col, blur(h, 3), 4.0, np.clip(rough, 0.06, 0.95))

# --- trench-floor sludge -----------------------------------------------------------
n1 = fbm(S, (2, 4, 8, 16, 32, 64), 21)
n2 = fbm(S, (8, 16, 32, 64, 128), 22)
ruts = np.sin(yy / S * math.pi * 2 * 5 + fbm(S, (2, 4, 8), 23) * 6) * 0.5 + 0.5
ruts = sstep(0.75, 1.0, ruts) * sstep(0.3, 0.6, fbm(S, (2, 4), 24))
h = n1 * 0.35 + n2 * 0.12 - ruts * 0.25
h, boots = stamp_boots(h, 10, 25, 0.5)
crust = sstep(0.62, 0.72, fbm(S, (6, 12, 24, 48), 26))
deb = (np.random.default_rng(27).random((S, S)) > 0.9993).astype(float)
deb = np.clip(blur(deb, 2) * 40, 0, 1)                          # pebbles, splinters pressed in
col = np.zeros((S, S, 3)) + np.array([0.105, 0.082, 0.062])
col *= (0.7 + 0.5 * n1 + 0.2 * n2)[..., None]
col = mix(col, (0.12, 0.095, 0.07), crust * 0.6)
col = mix(col, (0.045, 0.04, 0.036), boots * 0.6)
col = mix(col, (0.2, 0.18, 0.15), deb * 0.7)
pool = sstep(0.4, 0.3, blur(h, 8))
col = mix(col, (0.085, 0.08, 0.072), pool * 0.7)
rough = 0.35 + 0.45 * crust - 0.25 * pool - 0.1 * boots + 0.1 * n2
save('mud_sludge', col, h + deb * 0.2, 5.0, np.clip(rough, 0.05, 0.9))

# --- the cut wall: soil strata -----------------------------------------------------
# v runs down the wall: 1024 px = 2 m. Topsoil, a dark band, clay, a greyer band.
v = yy / S
warp = fbm(S, (3, 6, 12, 24), 31, aspect=(1, 1)) * 0.25
band = (v + warp) % 1.0
layers = [(0.00, (0.13, 0.1, 0.07)), (0.16, (0.11, 0.085, 0.062)), (0.3, (0.165, 0.128, 0.087)),
          (0.5, (0.145, 0.117, 0.086)), (0.66, (0.185, 0.145, 0.098)), (0.82, (0.125, 0.1, 0.076))]
col = np.zeros((S, S, 3))
for i, (start, c) in enumerate(layers):
    end = layers[i + 1][0] if i + 1 < len(layers) else 1.0
    m = sstep(start - 0.02, start + 0.02, band) * (1 - sstep(end - 0.02, end + 0.02, band))
    col += m[..., None] * np.array(c)[None, None, :]
grain = fbm(S, (16, 32, 64, 128, 256), 32)
streaks = fbm(S, (8, 16, 32, 64), 33, aspect=(1, 16))               # running down the wall
streaks = sstep(0.55, 0.75, streaks)
crumbs, _ = worley(S, 40, 34)
crumbs = sstep(0.25, 0.0, crumbs)
roots = np.zeros((S, S))
r = np.random.default_rng(35)
for i in range(14):
    x = r.uniform(0, S); y = r.uniform(0, S * 0.12); a = r.uniform(0.6, 2.5)
    for k in range(r.integers(15, 50)):
        a += r.normal(0, 0.18)
        x = (x + math.cos(a) * 2) % S; y = (y + abs(math.sin(a)) * 2) % S
        roots[int(y), int(x)] = 1
roots = np.clip(blur(roots, 1) * 1.5, 0, 0.6)
col *= (0.7 + 0.5 * grain)[..., None]
col = mix(col, col * 0.55, streaks)
col = mix(col, (0.05, 0.035, 0.025), roots * 0.8)
col *= (1 - 0.05 * crumbs)[..., None]
ledges = sstep(0.0, 0.03, np.abs(np.sin((band) * math.pi * 6)) - 0.97 + 0.03) * 0.0
rills = fbm(S, (16, 32, 64), 37, aspect=(1, 20))
h = grain * 0.25 + roots * 0.3 - streaks * 0.15 + rills * 0.35 + fbm(S, (3, 6, 12), 36, aspect=(4, 1)) * 0.5
rough = 0.85 - streaks * 0.5 - 0.1 * grain
save('soil_wall', col, h, 5.0, np.clip(rough, 0.15, 0.95))

# --- firmer ground ---------------------------------------------------------------
n1 = fbm(S, (4, 8, 16, 32, 64, 128), 41)
cr1, cr2 = worley(S, 14, 42)
cracks = sstep(0.06, 0.0, cr2 - cr1) * sstep(0.45, 0.65, fbm(S, (3, 6), 43))
stones = (np.random.default_rng(44).random((S, S)) > 0.9985).astype(float)
stones = np.clip(blur(stones, 3) * 14, 0, 1)
stalks = np.zeros((S, S))
r = np.random.default_rng(45)
for i in range(160):
    x = r.uniform(0, S); y = r.uniform(0, S); a = r.uniform(0, math.pi * 2); L = r.integers(10, 40)
    for k in range(L):
        stalks[int(y) % S, int(x) % S] = 1
        x += math.cos(a); y += math.sin(a)
stalks = np.clip(blur(stalks, 1) * 2.5, 0, 1)
col = np.zeros((S, S, 3)) + np.array([0.19, 0.165, 0.13])
col *= (0.65 + 0.55 * n1)[..., None]
col = mix(col, (0.08, 0.065, 0.05), cracks * 0.8)
col = mix(col, (0.32, 0.3, 0.27), stones * 0.8)
col = mix(col, (0.26, 0.22, 0.12), stalks * 0.7)
h = n1 * 0.4 - cracks * 0.4 + stones * 0.5 + stalks * 0.1
h, boots = stamp_boots(h, 4, 46, 0.2)
col = mix(col, (0.11, 0.09, 0.07), boots * 0.5)
damp = sstep(0.5, 0.7, fbm(S, (3, 6, 12), 47))
col *= (1 - 0.3 * damp)[..., None]
rough = 0.92 - 0.3 * damp - 0.2 * boots
save('ground_firm', col, h, 4.0, np.clip(rough, 0.3, 0.97))

# --- corrugated iron, rusting (512) ------------------------------------------------
S2 = 512
yy2, xx2 = np.mgrid[0:S2, 0:S2]
corr = np.sin(xx2 / S2 * math.pi * 2 * 16) * 0.5 + 0.5
rust = fbm(S2, (4, 8, 16, 32, 64), 51)
runs = sstep(0.5, 0.75, fbm(S2, (8, 16, 32), 52, aspect=(1, 12)))
col = np.zeros((S2, S2, 3)) + np.array([0.21, 0.205, 0.19])
col = mix(col, (0.22, 0.13, 0.075), sstep(0.35, 0.7, rust) * 0.85)
col = mix(col, (0.15, 0.085, 0.05), runs * 0.6)
col = mix(col, (0.1, 0.085, 0.07), sstep(0.55, 0.8, fbm(S2, (6, 12, 24), 53)) * 0.5)   # grime
col = mix(col, (0.12, 0.09, 0.06), sstep(0.8, 1.0, yy2 / S2) * 0.8)    # mud splashed up the bottom
col *= (0.75 + 0.35 * corr)[..., None]
save('iron', col, corr * 0.8 + rust * 0.1, 6.0, np.clip(0.55 + 0.35 * sstep(0.35, 0.65, rust) - runs * 0.2, 0, 1))

# --- woven hurdles (wattle revetment) ------------------------------------------------
rod = 28
row = yy2 // rod
phase = ((xx2 // 64) + row) % 2
roll = np.sin((yy2 % rod) / rod * math.pi)
over = np.where(phase == 0, 1.0, 0.6)
stake = (xx2 % 64) < 8
bark = fbm(S2, (16, 32, 64, 128), 61, aspect=(8, 1))
col = np.zeros((S2, S2, 3)) + np.array([0.2, 0.15, 0.1])
col *= (0.6 + 0.6 * bark)[..., None] * (0.45 + 0.55 * roll * over)[..., None]
col[stake] = col[stake] * 0.6 + np.array([0.05, 0.04, 0.03])
col = mix(col, (0.08, 0.06, 0.045), sstep(0.7, 1.0, yy2 / S2) * 0.7)
save('wattle', col, roll * over * 0.8 + bark * 0.1, 5.0, np.full((S2, S2), 0.8))

# --- wet planks (revetment boards, fire steps, signs) ---------------------------------
board = 64
row = yy2 // board
grain = fbm(S2, (8, 16, 32, 64, 128), 71, aspect=(12, 1))
tint = np.random.default_rng(72).uniform(0.7, 1.2, S2 // board + 1)[row]
col = np.zeros((S2, S2, 3)) + np.array([0.2, 0.15, 0.1])
col *= (0.6 + 0.6 * grain)[..., None] * tint[..., None]
seam = (yy2 % board) < 4
col[seam] *= 0.3
wetd = sstep(0.4, 0.8, fbm(S2, (3, 6, 12), 73)) + sstep(0.6, 1.0, yy2 / S2)
col *= (1 - 0.4 * np.clip(wetd, 0, 1))[..., None]
save('planks_wet', col, np.where(seam, 0.0, 0.6 + 0.3 * grain), 5.0, np.clip(0.75 - 0.4 * np.clip(wetd, 0, 1), 0.2, 1))

# --- one board: grain along it, no seams (the boxes make the seams) -------------------
grain = fbm(S2, (8, 16, 32, 64, 128), 74, aspect=(12, 1))
col = np.zeros((S2, S2, 3)) + np.array([0.15, 0.115, 0.08])
col *= (0.6 + 0.6 * grain)[..., None]
wetd = sstep(0.4, 0.8, fbm(S2, (3, 6, 12), 75))
col *= (1 - 0.35 * wetd)[..., None]
col = mix(col, (0.07, 0.055, 0.04), sstep(0.62, 0.8, fbm(S2, (6, 12, 24), 76)) * 0.6)   # mud smeared on
save('board', col, grain * 0.5, 2.5, np.clip(0.78 - 0.35 * wetd, 0.25, 1))

# --- burlap: a sodden sandbag's cloth (512) ---------------------------------------------
weave = (np.sin(xx2 * 1.6) * 0.5 + 0.5) * (np.sin(yy2 * 1.6) * 0.5 + 0.5)
dirt = fbm(S2, (4, 8, 16, 32, 64), 81)
stain = sstep(0.45, 0.75, fbm(S2, (3, 6, 12), 82))
col = np.zeros((S2, S2, 3)) + np.array([0.2, 0.165, 0.115])
col *= (0.78 + 0.25 * weave)[..., None] * (0.7 + 0.5 * dirt)[..., None]
col = mix(col, (0.08, 0.06, 0.045), stain * 0.75)                    # soaked and muddy
save('burlap', col, weave * 0.5 + dirt * 0.3, 4.0, np.clip(0.85 - stain * 0.35, 0, 1))

# --- timber: posts and beams, rough-sawn, wet ---------------------------------------
grain = fbm(S2, (8, 16, 32, 64, 128, 256), 91, aspect=(1, 14))
knots, _ = worley(S2, 6, 92)
col = np.zeros((S2, S2, 3)) + np.array([0.15, 0.115, 0.08])
col *= (0.6 + 0.6 * grain)[..., None]
col = mix(col, (0.06, 0.045, 0.03), sstep(0.08, 0.0, knots) * 0.8)
col = mix(col, col * 0.55, sstep(0.5, 0.8, fbm(S2, (3, 6), 93)))
save('timber', col, grain * 0.6, 4.0, np.full((S2, S2), 0.72))

# --- a strange sign daubed on timber: a grinning mask in a diamond, dripping (RGBA) ---
S4 = 256
yy4, xx4 = np.mgrid[0:S4, 0:S4] / S4
paint = np.zeros((S4, S4))
d = np.abs(xx4 - 0.5) + np.abs(yy4 - 0.47)
paint = np.maximum(paint, sstep(0.035, 0.0, np.abs(d - 0.36)))                 # the diamond
grin_y = 0.55 + 0.12 * np.cos((xx4 - 0.5) * 5.0)
paint = np.maximum(paint, sstep(0.025, 0.0, np.abs(yy4 - grin_y)) * (np.abs(xx4 - 0.5) < 0.2))   # the grin
for ex in (0.4, 0.6):
    paint = np.maximum(paint, sstep(0.045, 0.02, np.sqrt((xx4 - ex) ** 2 + ((yy4 - 0.4) * 1.6) ** 2)))  # the eyes
r = np.random.default_rng(101)
for k in range(9):                                                              # runs of paint
    x = r.uniform(0.25, 0.75); y0 = r.uniform(0.5, 0.7); L = r.uniform(0.05, 0.25)
    paint = np.maximum(paint, (np.abs(xx4 - x) < 0.006) * (yy4 > y0) * (yy4 < y0 + L) * 0.9)
paint *= sstep(0.25, 0.6, fbm(S4, (8, 16, 32, 64), 102))                        # faded, flaking
col = np.zeros((S4, S4, 3)) + np.array([0.35, 0.025, 0.02])
img = np.dstack([np.clip(col, 0, 1) ** (1 / 2.2), np.clip(paint, 0, 1)])
Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'symbol.png'))

# --- a faded circus bill, pasted up and peeling (RGBA, 256x384) ------------------------
W5, H5 = 256, 384
yy5, xx5 = np.mgrid[0:H5, 0:W5]
u = xx5 / W5; v = yy5 / H5
paper = np.zeros((H5, W5, 3)) + np.array([0.55, 0.5, 0.38])
stripes = (np.floor(u * 8 + v * 0.0) % 2 == 0) * (v < 0.25)
paper = mix(paper, (0.45, 0.08, 0.06), stripes * 0.8)
face = ((u - 0.5) ** 2 / 0.06 + (v - 0.55) ** 2 / 0.05) < 1
paper = mix(paper, (0.8, 0.77, 0.7), face * 0.9)
for ex in (0.42, 0.58):
    eye = ((u - ex) ** 2 + (v - 0.5) ** 2) < 0.0012
    paper = mix(paper, (0.05, 0.04, 0.04), eye * 1.0)
nose = ((u - 0.5) ** 2 + (v - 0.57) ** 2) < 0.0016
paper = mix(paper, (0.6, 0.05, 0.05), nose * 1.0)
grin = (np.abs(v - (0.63 + 0.06 * np.cos((u - 0.5) * 9))) < 0.008) * (np.abs(u - 0.5) < 0.14)
paper = mix(paper, (0.25, 0.03, 0.03), grin * 1.0)
banner = (v > 0.82) * (v < 0.92)
paper = mix(paper, (0.45, 0.08, 0.06), banner * 0.75)
age = fbm(H5, (4, 8, 16, 32), 111)[:, :W5] if H5 >= W5 else fbm(W5, (4, 8, 16, 32), 111)[:H5]
paper = mix(paper, (0.25, 0.2, 0.13), sstep(0.5, 0.8, age) * 0.7)                # damp stains
paper *= 0.75
torn = sstep(0.62, 0.66, fbm(H5, (6, 12, 24), 112)[:, :W5] + 0.25 * np.maximum(0, v - 0.75) * 4)
alpha = 1 - torn
img = np.dstack([np.clip(paper, 0, 1) ** (1 / 2.2), alpha])
Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'circus_bill.png'))

# --- tiling noise for the shaders (R: broad, G: medium, B: fine) ----------------------
S3 = 256
noise = np.dstack([fbm(S3, (2, 4, 8), 81), fbm(S3, (6, 12, 24), 82), fbm(S3, (24, 48, 96), 83)])
save('noise', noise, linear=True)
print('done')
