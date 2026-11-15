"""Generates the trench and bunker textures into art/level/.
Run:  python3 tools/gen_level_textures.py   (needs numpy + Pillow)

Every tiling texture is seamless. Each gets an albedo PNG and, where the
surface has relief, a matching _n.png normal map. Mud also gets _r.png
(roughness) so puddles shine."""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'art', 'level')
os.makedirs(OUT, exist_ok=True)
S = 512


# --- noise --------------------------------------------------------------------
def fbm(size, octaves, seed, aspect=(1, 1)):
    """Tileable value noise. `aspect` stretches it (grain along x: aspect=(1, 8))."""
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


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def mix(a, b, m):
    return a * (1 - m[..., None]) + np.asarray(b, float)[None, None, :] * m[..., None]


def blur(a, n=1):
    for _ in range(n):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def save(name, rgb, height=None, strength=3.0, rough=None, alpha=None):
    rgb = np.clip(rgb, 0, 1)
    if alpha is not None:
        img = np.dstack([rgb, np.clip(alpha, 0, 1)])
        Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
    else:
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


yy, xx = np.mgrid[0:S, 0:S]


# --- weathered horizontal boards (trench revetment, bunker wainscot, ceilings) --
def boards(seed, board_px=64, base=(0.30, 0.22, 0.15), vertical=False):
    rng = np.random.default_rng(seed)
    X, Y = (yy, xx) if vertical else (xx, yy)
    row = Y // board_px
    nrows = S // board_px
    tint = rng.uniform(0.75, 1.15, nrows)[row]
    shift = rng.integers(0, S, nrows)[row]
    grain = fbm(S, (4, 8, 16, 32, 64), seed, aspect=(1, 10) if not vertical else (10, 1))
    knots = fbm(S, (8, 16), seed + 1)
    col = np.zeros((S, S, 3)) + np.array(base)
    col *= (0.7 + 0.55 * grain)[..., None] * tint[..., None]
    col *= (0.85 + 0.3 * knots)[..., None]
    inrow = (Y % board_px) / board_px
    gap = (inrow < 0.045) | (inrow > 0.965)
    seam = ((X + shift) % S) < 3          # one butt joint per board
    edge = sstep(0.0, 0.12, inrow) * sstep(1.0, 0.88, inrow)
    h = 0.55 + 0.35 * edge + 0.1 * grain
    h[gap | seam] = 0.0
    col[gap | seam] *= 0.18
    # a pair of nails near each board's joint
    starts = rng.integers(0, S, nrows)
    for r in range(nrows):
        for k in (10, -10):
            cx = (starts[r] * 0 + rng.integers(0, S)) % S if False else (int(np.random.default_rng(seed + r).integers(0, S)) + k) % S
            cy = r * board_px + board_px // 2
            nail = ((X - cx) ** 2 + (Y - cy) ** 2) < 5
            col[nail] = (0.12, 0.1, 0.09)
    grime = fbm(S, (2, 4, 8), seed + 2)
    col *= (0.75 + 0.35 * grime)[..., None]
    return col, h


col, h = boards(1)
save('planks', col, h, 3.0)
col, h = boards(2, 32, (0.24, 0.18, 0.13))
save('planks_dark', col * 0.85, h, 3.0)

# --- duckboard: slats across a walkway, mud showing through the gaps ----------
rng = np.random.default_rng(3)
slat = 46
pos = xx % slat
gap = pos < 9
grain = fbm(S, (8, 16, 32, 64), 3, aspect=(10, 1))
tint = rng.uniform(0.7, 1.15, S // slat + 1)[xx // slat]
col = np.zeros((S, S, 3)) + np.array([0.32, 0.25, 0.17])
col *= (0.7 + 0.5 * grain)[..., None] * tint[..., None]
wet = fbm(S, (4, 8, 16), 4)
col = mix(col, (0.12, 0.09, 0.06), np.clip((wet - 0.45) * 2.5, 0, 0.7))
col[gap] = (0.07, 0.05, 0.035)
h = np.where(gap, 0.0, 0.7 + 0.2 * grain)
save('duckboard', col, h, 4.0)

# --- mud: wet, churned, with shiny puddles -------------------------------------
n1 = fbm(S, (4, 8, 16, 32, 64, 128), 5); n2 = fbm(S, (2, 4, 8, 16), 6); n3 = fbm(S, (32, 64, 128), 7)
col = np.zeros((S, S, 3)) + np.array([0.19, 0.15, 0.11])
col *= (0.65 + 0.6 * n1)[..., None]
puddle = sstep(0.58, 0.64, n2)
col = mix(col, (0.15, 0.14, 0.13), puddle * 0.6)   # muddy water, not black: black reads as blood
col *= (0.85 + 0.3 * n3)[..., None]
h = n1 * 0.8 + n3 * 0.2 - puddle * 0.5
rough = 0.9 - 0.6 * puddle - 0.1 * n3
save('mud', col, h, 5.0, rough=rough)
# the same ground up top, drier and greyer
col2 = np.zeros((S, S, 3)) + np.array([0.21, 0.19, 0.16])
col2 *= (0.6 + 0.6 * n1)[..., None]
grass = sstep(0.62, 0.7, fbm(S, (8, 16, 32, 64), 8)) * 0.6
col2 = mix(col2, (0.16, 0.17, 0.10), grass)
save('ground', col2, h, 4.0, rough=0.92 - 0.3 * puddle)

# --- sandbags: staggered rows of rounded burlap bags ---------------------------
bag_w, bag_h = 128, 46
row = yy // bag_h
off = (row % 2) * (bag_w // 2)
u = ((xx + off) % bag_w) / bag_w
v = (yy % bag_h) / bag_h
shape = np.sqrt(np.clip(1 - ((u - 0.5) / 0.5) ** 6, 0, 1)) * np.sqrt(np.clip(1 - ((v - 0.5) / 0.5) ** 4, 0, 1))
weave = (np.sin(xx * 1.9) * np.sin(yy * 1.9)) * 0.5 + 0.5
dirt = fbm(S, (4, 8, 16, 32), 9)
bagtint = np.random.default_rng(9).uniform(0.8, 1.15, (S // bag_h + 1, S // bag_w + 2))[row, ((xx + off) // bag_w) % (S // bag_w)]
col = np.zeros((S, S, 3)) + np.array([0.40, 0.34, 0.24])
col *= (0.8 + 0.1 * weave)[..., None] * bagtint[..., None]
col = mix(col, (0.18, 0.14, 0.1), np.clip((0.55 - dirt) * 2.2, 0, 0.75))
col *= (0.35 + 0.65 * shape)[..., None]
tie = (np.abs(u - 0.06) < 0.012) | (np.abs(u - 0.94) < 0.012)
col[tie & (shape > 0.2)] *= 0.6
save('sandbags', col, shape * 0.9 + weave * 0.04, 5.0)

# --- harlequin: red and cream diamonds painted on boards, flaking --------------
wood, wh = boards(10, 64, (0.28, 0.21, 0.15), vertical=True)
dw, dh = 128, 256
du = ((xx % dw) - dw / 2) / (dw / 2); dv = ((yy % dh) - dh / 2) / (dh / 2)
inside = (np.abs(du) + np.abs(dv)) < 1.0
cell = ((xx // dw) + (yy // dh)) % 2
red = inside ^ (cell == 1)
paint = np.where(red[..., None], np.array([0.52, 0.07, 0.06]), np.array([0.74, 0.67, 0.53]))
peel_n = fbm(S, (8, 16, 32, 64), 11)
peel = sstep(0.62, 0.66, peel_n)
grime = fbm(S, (2, 4, 8, 16), 12)
col = paint * (0.75 + 0.3 * fbm(S, (16, 32, 64), 13))[..., None]
col = col * (1 - peel[..., None]) + wood * peel[..., None]
col = mix(col, (0.15, 0.11, 0.08), np.clip((0.5 - grime) * 1.6, 0, 0.6))
col *= np.where(wh <= 0.01, 0.25, 1.0)[..., None]
streak = sstep(0.55, 0.9, fbm(S, (4, 8, 16, 32), 14, aspect=(8, 1))) * 0.35
col = mix(col, (0.1, 0.07, 0.05), streak)
save('harlequin', col, wh * (1 - 0.3 * peel) + 0.15 * (1 - peel), 3.0)

# --- canvas: faded circus stripes, stained -------------------------------------
stripe = ((xx // 64) % 2) == 0
col = np.where(stripe[..., None], np.array([0.50, 0.10, 0.09]), np.array([0.70, 0.64, 0.52]))
weave = (np.sin(xx * 2.6) * 0.5 + 0.5) * (np.sin(yy * 2.6) * 0.5 + 0.5)
col = col * (0.82 + 0.12 * weave)[..., None]
stain = fbm(S, (2, 4, 8, 16, 32), 15)
col = mix(col, (0.2, 0.15, 0.1), np.clip((0.55 - stain) * 2.0, 0, 0.7))
col *= (0.8 + 0.3 * fbm(S, (4, 8), 16, aspect=(1, 6)))[..., None]   # hanging folds
save('canvas', col, fbm(S, (4, 8), 16, aspect=(1, 6)) * 0.6 + weave * 0.05, 3.0)

# --- concrete -----------------------------------------------------------------
n = fbm(S, (4, 8, 16, 32, 64, 128), 17)
col = np.zeros((S, S, 3)) + np.array([0.33, 0.32, 0.30])
col *= (0.65 + 0.55 * n)[..., None]
col = mix(col, (0.12, 0.1, 0.08), np.clip((0.5 - fbm(S, (2, 4, 8), 18)) * 1.8, 0, 0.6))
pits = sstep(0.7, 0.74, fbm(S, (32, 64, 128), 19))
col *= (1 - 0.35 * pits)[..., None]
save('concrete', col, n * 0.6 - pits * 0.2, 3.0)

# --- rusty metal ----------------------------------------------------------------
n = fbm(S, (8, 16, 32, 64), 20)
col = np.zeros((S, S, 3)) + np.array([0.16, 0.15, 0.14])
rust = np.clip((n - 0.45) * 2.5, 0, 1)
col = mix(col, (0.32, 0.14, 0.06), rust)
save('metal', col, n * 0.4, 2.0)

# timber: rough-sawn grain running up the texture, for posts, beams and frames
g = fbm(S, (8, 32, 128), 31, aspect=(1, 16))
knots = np.clip((fbm(S, (6, 12), 32) - 0.7) * 6, 0, 1)
col = np.zeros((S, S, 3)) + np.array([0.27, 0.19, 0.12])
col = col * (0.7 + 0.5 * g[..., None]) * (1 - 0.5 * knots[..., None])
save('timber', col, g * 0.7 - knots * 0.3, 3.0)

# --- sunburst: painted rays on a bunker floor (one per room, does not tile) -----
B = 1024
by, bx = np.mgrid[0:B, 0:B]
cx = cy = B / 2
ang = np.arctan2(by - cy, bx - cx)
rad = np.hypot(bx - cx, by - cy) / (B / 2)
ray = (np.floor((ang + math.pi) / (2 * math.pi) * 24) % 2) == 0
base = fbm(B, (4, 8, 16, 32, 64), 21)
col = np.where(ray[..., None], np.array([0.48, 0.08, 0.07]), np.array([0.66, 0.6, 0.48]))
col = col * (0.75 + 0.3 * base)[..., None]
wear = sstep(0.55, 0.7, fbm(B, (8, 16, 32, 64), 22)) + sstep(0.85, 1.0, rad) * 0.7
conc = np.zeros((B, B, 3)) + np.array([0.28, 0.27, 0.25])
col = col * (1 - np.clip(wear, 0, 1)[..., None]) + conc * np.clip(wear, 0, 1)[..., None]
col = mix(col, (0.1, 0.08, 0.06), np.clip((0.5 - fbm(B, (2, 4, 8), 23)) * 1.6, 0, 0.6))
hub = rad < 0.08
col[hub] = col[hub] * 0.3 + np.array([0.6, 0.55, 0.42]) * 0.7
Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(OUT, 'sunburst.png'))

# --- crate: vertical boards, frame, stencilled star ------------------------------
C = 512
cyy, cxx = np.mgrid[0:C, 0:C]
wood, wh = boards(24, 128, (0.33, 0.25, 0.16), vertical=True)
col = wood.copy()
frame = (cxx < 40) | (cxx > C - 40) | (cyy < 40) | (cyy > C - 40)
col[frame] *= 0.7
wh = wh.copy(); wh[frame] += 0.25
img = Image.new('L', (C, C), 0); d = ImageDraw.Draw(img)
pts = []
for i in range(10):
    a = -math.pi / 2 + i * math.pi / 5
    r = 150 if i % 2 == 0 else 62
    pts.append((C / 2 + r * math.cos(a), C / 2 + 10 + r * math.sin(a)))
d.polygon(pts, fill=255)
star = np.array(img.filter(ImageFilter.GaussianBlur(1.2))) / 255.0
star *= sstep(0.35, 0.45, fbm(C, (8, 16, 32), 25))          # worn stencil
col = mix(col, (0.72, 0.68, 0.58), star * 0.9)
col = mix(col, (0.12, 0.09, 0.07), np.clip((0.5 - fbm(C, (2, 4, 8), 26)) * 1.5, 0, 0.5))
save('crate', col, wh, 3.0)

# --- drum: circus pedestal, diamonds between brass bands (wraps a cylinder) -------
col = np.zeros((S, S, 3))
du = ((xx % 64) - 32) / 32; dv = ((yy % 128) - 64) / 64
inside = (np.abs(du) + np.abs(dv)) < 1.0
col[:] = np.where(inside[..., None], np.array([0.55, 0.08, 0.07]), np.array([0.72, 0.66, 0.52]))
band = (yy < 40) | (yy > S - 40)
col[band] = (0.45, 0.34, 0.14)
col *= (0.75 + 0.3 * fbm(S, (8, 16, 32), 27))[..., None]
col = mix(col, (0.12, 0.09, 0.06), np.clip((0.5 - fbm(S, (2, 4, 8), 28)) * 1.6, 0, 0.6))
save('drum', col, band * 0.5 + 0.2, 2.0)

# --- bunting pennant (alpha triangle) --------------------------------------------
P = 128
py, px = np.mgrid[0:P, 0:P]
tri = (py / P) < 1 - np.abs(px - P / 2) / (P / 2) * 0.0 - 0.0
tri = (np.abs(px - P / 2) / (P / 2)) < (1 - py / P)
col = np.zeros((P, P, 3)) + np.array([0.70, 0.64, 0.50])
dmd = ((np.abs(((px % 32) - 16) / 16) + np.abs(((py % 32) - 16) / 16)) < 1)
col[dmd] = (0.55, 0.08, 0.07)
col *= (0.7 + 0.35 * fbm(P, (4, 8, 16), 29))[..., None]
Image.fromarray(np.dstack([(np.clip(col, 0, 1) * 255).astype(np.uint8), (tri * 255).astype(np.uint8)]), 'RGBA').save(os.path.join(OUT, 'pennant.png'))

# --- camouflage netting (alpha) ----------------------------------------------------
mesh = ((xx % 32) < 3) | ((yy % 32) < 3)
scraps = sstep(0.55, 0.6, fbm(S, (8, 16, 32), 30))
alpha = np.clip(mesh * 1.0 + scraps, 0, 1)
col = np.zeros((S, S, 3)) + np.array([0.22, 0.2, 0.13])
col = mix(col, (0.3, 0.27, 0.17), scraps * fbm(S, (16, 32), 31))
col = mix(col, (0.12, 0.11, 0.07), mesh * 0.6)
save('camonet', col, alpha=alpha)

# --- circus poster: an original grinning clown on aged paper ----------------------
W, H = 512, 768
paper = np.zeros((H, W, 3)) + np.array([0.72, 0.64, 0.48])
pn = fbm(1024, (4, 8, 16, 32, 64), 32)[:H, :W]
paper *= (0.75 + 0.35 * pn)[..., None]
img = Image.fromarray((np.clip(paper, 0, 1) * 255).astype(np.uint8), 'RGB')
d = ImageDraw.Draw(img)
d.rectangle([18, 18, W - 18, H - 18], outline=(110, 25, 20), width=10)
d.ellipse([140, 120, 372, 540], fill=(222, 210, 190))                       # long pale face
rng_p = np.random.default_rng(35)
for sx in (-1, 1):                                                           # wild tufts at the sides
    for k in range(14):
        ang = math.radians(rng_p.uniform(-70, 60))
        L = rng_p.uniform(70, 140)
        bx, by = 256 + sx * 110, 300 + rng_p.uniform(-60, 40)
        tip = (bx + sx * L * math.cos(ang), by - L * math.sin(ang))
        d.polygon([(bx, by - 18), tip, (bx, by + 18)], fill=(150, 35, 25))
d.pieslice([140, 120, 372, 300], 180, 360, fill=(222, 210, 190))             # bald crown over the tufts
for sx in (-1, 1):
    ex = 256 + sx * 58
    d.polygon([(ex, 200), (ex + 12, 300), (ex, 400), (ex - 12, 300)], fill=(40, 45, 70))   # paint spikes through the eyes
    d.ellipse([ex - 26, 282, ex + 26, 318], fill=(25, 18, 20))                              # sunken eyes
    d.ellipse([ex - 6, 294, ex + 6, 306], fill=(225, 200, 90))
    d.line([(ex - 34, 262 - sx * 10), (ex + 30, 270 + sx * 10)], fill=(25, 18, 20), width=7)  # angry brows
d.ellipse([230, 340, 282, 392], fill=(185, 25, 20))                          # nose
d.chord([160, 360, 352, 500], 8, 172, fill=(160, 20, 18))                    # grin
d.chord([182, 380, 330, 478], 14, 166, fill=(232, 222, 196))                 # teeth
for i in range(9):
    x = 190 + i * 16
    d.line([(x, 420), (x, 468)], fill=(120, 20, 18), width=3)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf', 74)
    small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf', 34)
except Exception:
    font = small = ImageFont.load_default()
d.text((W / 2, 600), "WITZ", fill=(120, 22, 18), font=font, anchor='mm')
d.text((W / 2, 670), "CIRCUS OF THE FRONT", fill=(40, 30, 25), font=small, anchor='mm')
d.text((W / 2, 70), "LAST SHOW", fill=(40, 30, 25), font=small, anchor='mm')
arr = np.asarray(img).astype(float) / 255.0
stain = fbm(1024, (2, 4, 8, 16), 33)[:H, :W]
arr = mix(arr, (0.25, 0.18, 0.1), np.clip((0.5 - stain) * 1.5, 0, 0.6))
torn = (fbm(1024, (8, 16, 32), 34)[:H, :W] > 0.7) & ((np.mgrid[0:H, 0:W][0] > H - 80) | (np.mgrid[0:H, 0:W][1] > W - 60))
alpha = np.where(torn, 0.0, 1.0)
Image.fromarray((np.dstack([np.clip(arr, 0, 1), alpha]) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'poster.png'))

# =============================================================================
# Dieselpunk bunker set: cast concrete, wet floors, steel, faded circus paint.
# =============================================================================

# --- cast concrete wall: formwork board lines, tie holes, water streaks --------
n = fbm(S, (4, 8, 16, 32, 64, 128), 40)
streak = fbm(S, (4, 8, 16, 32), 41, aspect=(1, 16))           # runs down the wall
col = np.zeros((S, S, 3)) + np.array([0.40, 0.395, 0.38])
col *= (0.62 + 0.55 * n)[..., None]
col = mix(col, (0.16, 0.155, 0.14), np.clip((streak - 0.48) * 2.2, 0, 0.8))     # water stains
col = mix(col, (0.55, 0.54, 0.5), np.clip((fbm(S, (4, 8, 16), 58) - 0.6) * 2.5, 0, 0.5))  # efflorescence
col = mix(col, (0.24, 0.17, 0.10), np.clip((fbm(S, (3, 6, 12), 42) - 0.62) * 3, 0, 0.5))  # rust bleed
board = (yy % 256 < 2).astype(float) * 0.5                     # faint pour lines every metre
col *= (1 - 0.35 * board)[..., None]
ties = ((np.abs((xx % 256) - 128) < 5) & (np.abs((yy % 128) - 64) < 5)).astype(float)
col *= (1 - 0.6 * ties)[..., None]
pits = sstep(0.72, 0.76, fbm(S, (32, 64, 128), 43))
col *= (1 - 0.3 * pits)[..., None]
h = n * 0.5 - board * 0.35 - ties * 0.6 - pits * 0.25
save('wall_conc', col, h, 3.0, rough=0.85 + 0.1 * n - 0.25 * np.clip((streak - 0.55) * 3, 0, 1))

# --- the bottom of the wall: wetter, darker, splashed with mud ---------------------
col = np.zeros((S, S, 3)) + np.array([0.25, 0.235, 0.21])
col *= (0.65 + 0.5 * n)[..., None]
col = mix(col, (0.12, 0.10, 0.07), np.clip(fbm(S, (8, 16, 32, 64), 44) - 0.35, 0, 1) * 1.2)
col *= (1 - 0.35 * board)[..., None]
save('wall_low', col, h, 3.0, rough=0.6 + 0.3 * n)

# --- wet concrete floor: slab joints, cracks, puddles that shine ---------------------
n = fbm(S, (4, 8, 16, 32, 64, 128), 45)
col = np.zeros((S, S, 3)) + np.array([0.30, 0.29, 0.27])
col *= (0.65 + 0.5 * n)[..., None]
grime = fbm(S, (2, 4, 8, 16), 46)
col = mix(col, (0.13, 0.12, 0.10), np.clip((grime - 0.45) * 1.8, 0, 0.7))
joint = ((xx % 512 < 3) | (yy % 512 < 3)).astype(float)
crack_n = fbm(S, (8, 16, 32), 47)
crack = np.clip(1 - np.abs(crack_n - 0.5) * 60, 0, 1) * (fbm(S, (4, 8), 48) > 0.55)
col *= (1 - 0.5 * joint - 0.45 * crack)[..., None]
puddle = sstep(0.56, 0.62, fbm(S, (2, 4, 8, 16), 49))
col = mix(col, (0.16, 0.155, 0.15), puddle * 0.55)     # dark grey water, not black
h = n * 0.5 - joint * 0.5 - crack * 0.6 - puddle * 0.3
save('floor_conc', col, h, 3.0, rough=np.clip(0.88 - 0.8 * puddle - 0.1 * n, 0.04, 1))

# --- faded harlequin paint on concrete: tall diamonds, peeling, filthy ----------------
gx = xx / S * 2.0; gy = yy / S * 1.0           # two diamonds across, one tall diamond high
par = (np.floor(gx + gy) + np.floor(gx - gy)) % 2
base = np.zeros((S, S, 3)) + np.array([0.37, 0.355, 0.33])
base *= (0.7 + 0.45 * fbm(S, (4, 8, 16, 32, 64), 50))[..., None]
paint = np.where(par[..., None] > 0.5, np.array([0.34, 0.09, 0.07]), np.array([0.52, 0.47, 0.39]))
peel = sstep(0.6, 0.66, fbm(S, (4, 8, 16, 32, 64), 51))
col = mix(paint * (0.75 + 0.35 * fbm(S, (8, 16, 32), 52))[..., None], (0, 0, 0), np.zeros((S, S)))
col = col * (1 - peel[..., None]) + base * peel[..., None]
streak = fbm(S, (4, 8, 16, 32), 53, aspect=(1, 16))
col = mix(col, (0.12, 0.10, 0.08), np.clip((streak - 0.45) * 2.0, 0, 0.7))
col = mix(col, (0.2, 0.19, 0.17), np.full((S, S), 0.35)) * 0.8  # everything greyed by dust and soot
save('harlequin_faded', col, -peel * 0.4 + streak * 0.2, 3.0)

# --- riveted steel door, painted army green, flaking to rust ---------------------------
DW, DH = 256, 512
dy, dx = np.mgrid[0:DH, 0:DW]
dn = fbm(DH, (4, 8, 16, 32, 64), 54)[:, :DW]
col = np.zeros((DH, DW, 3)) + np.array([0.17, 0.2, 0.15])
col *= (0.75 + 0.4 * dn)[..., None]
rust = np.clip((fbm(DH, (4, 8, 16, 32), 55)[:, :DW] - 0.55) * 3, 0, 1)
col = mix(col, (0.28, 0.13, 0.06), rust)
frame = ((dx < 14) | (dx > DW - 15) | (dy < 14) | (dy > DH - 15)).astype(float)
panel = ((np.abs(dy - DH * 0.5) < 6) | (np.abs(dy - DH * 0.25) < 4) | (np.abs(dy - DH * 0.75) < 4)).astype(float)
riv = np.zeros((DH, DW))
for ry in list(range(7, DH, 32)):
    for rx in (7, DW - 8):
        riv[max(0, ry - 3):ry + 4, rx - 3:rx + 4] = 1
col *= (1 - 0.25 * frame - 0.3 * panel)[..., None]
col = mix(col, (0.3, 0.3, 0.28), riv * 0.6)
# a faded stencilled star: the one bit of circus left on it
cy, cx = DH * 0.37, DW * 0.5
pts = [(cx + (46 if k % 2 == 0 else 19) * math.cos(-math.pi / 2 + k * math.pi / 5),
        cy + (46 if k % 2 == 0 else 19) * math.sin(-math.pi / 2 + k * math.pi / 5)) for k in range(10)]
sim = Image.new('L', (DW, DH), 0); ImageDraw.Draw(sim).polygon(pts, fill=255)
star = np.asarray(sim).astype(float) / 255 * (fbm(DH, (16, 32, 64), 56)[:, :DW] > 0.38)
col = mix(col, (0.45, 0.4, 0.3), star * 0.55)
dh = dn * 0.3 + frame * 0.4 - panel * 0.3 + riv * 0.8
save('door', col, dh, 3.0)

# --- the sunburst floor again, faded into the concrete ---------------------------------
sb = np.asarray(Image.open(os.path.join(OUT, 'sunburst.png')).convert('RGB').resize((S, S))).astype(float) / 255
fl = np.asarray(Image.open(os.path.join(OUT, 'floor_conc.png')).convert('RGB')).astype(float) / 255
grey = sb.mean(axis=2, keepdims=True)
sb = sb * 0.55 + grey * 0.45
worn = np.clip(fbm(S, (4, 8, 16, 32), 57) * 1.6 - 0.35, 0, 1)
col = sb * 0.6 * (1 - worn[..., None]) + fl * (0.4 + 0.6 * worn[..., None])
save('sunburst_faded', col)

# contact sheet
names = ['planks', 'planks_dark', 'duckboard', 'mud', 'ground', 'sandbags', 'harlequin', 'canvas', 'concrete', 'metal', 'sunburst', 'crate', 'drum', 'pennant', 'camonet', 'poster', 'wall_conc', 'wall_low', 'floor_conc', 'harlequin_faded', 'door', 'sunburst_faded', 'timber']
sheet = Image.new('RGB', (8 * 200, 3 * 200), (40, 40, 40))
for i, n in enumerate(names):
    im = Image.open(os.path.join(OUT, n + '.png')).convert('RGBA').resize((200, 200))
    sheet.paste(im, ((i % 8) * 200, (i // 8) * 200), im)
sheet.save('/tmp/level_tex.png')
print('written:', len(os.listdir(OUT)), 'files')
