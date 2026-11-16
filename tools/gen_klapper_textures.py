"""Placeholder textures for Der Klappersoldat (procedural, not final art).

- klapper_body.jpg: the WitzSoldat's uniform atlas turned field grey: cream
  cloth becomes weathered grey-green wool, the clown reds are kept but faded
  (piping and harlequin patches), leather darkened, with grime and oil stains.
- klapper_helmet.jpg: the WitzSoldat's painted helmet stripped to rusted steel.
- klapper_face.png / klapper_face_cracked.png: the porcelain clown face,
  front-projected (u = left-right, v = top-bottom of the face), with the eye
  sockets and the fixed grin painted on, and a heavily cracked version.
Run from the project root: python3 tools/gen_klapper_textures.py
"""
import colorsys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

rng = np.random.default_rng(1916)


def noise(h, w, scale, octaves=4):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        small = rng.random((s, s)).astype(np.float32)
        big = np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255
        out += big * amp
        tot += amp
        amp *= 0.5
    return out / tot


# --- uniform -----------------------------------------------------------------
src = np.asarray(Image.open("art/witzsoldat/witzsoldat_soldier_segmented_basecolor.jpg").convert("RGB")).astype(np.float32) / 255
h, w, _ = src.shape
r, g, b = src[..., 0], src[..., 1], src[..., 2]
mx = src.max(-1); mn = src.min(-1)
val = mx
sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
hue = np.zeros_like(mx)
d = np.maximum(mx - mn, 1e-5)
hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
lum = 0.3 * r + 0.59 * g + 0.11 * b
red = ((hue < 0.04) | (hue > 0.93)) & (sat > 0.55) & (val > 0.28)
leather = (~red) & (hue > 0.03) & (hue < 0.14) & (sat > 0.28) & (val < 0.62)
cloth = ~(red | leather)
field = np.array([0.29, 0.32, 0.26])                     # feldgrau
grey = field[None, None, :] * (0.35 + 1.05 * lum[..., None])
faded_red = np.stack([0.3 * (0.4 + val), 0.1 * (0.4 + val), 0.08 * (0.4 + val)], -1)
dark_leather = src * 0.62
out = np.where(cloth[..., None], grey, np.where(red[..., None], faded_red, dark_leather))
grime = noise(h, w, 6)
out *= (0.72 + 0.4 * grime)[..., None]
oil = noise(h, w, 18) > 0.74                             # oil and soot stains
out = np.where(oil[..., None], out * 0.55, out)
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save("art/klapper/klapper_body.jpg", quality=90)

# --- helmet ------------------------------------------------------------------
hs = np.asarray(Image.open("art/witzsoldat/witzsoldat_helmet_soldier_segmented_basecolor.jpg").convert("RGB")).astype(np.float32) / 255
hh, hw, _ = hs.shape
hl = (0.3 * hs[..., 0] + 0.59 * hs[..., 1] + 0.11 * hs[..., 2])
steel = np.array([0.30, 0.31, 0.30]) * (0.6 + 0.6 * hl[..., None])
rust_n = noise(hh, hw, 10)
rust = np.array([0.36, 0.16, 0.07]) * (0.5 + 0.8 * noise(hh, hw, 40))[..., None]
k = np.clip((rust_n - 0.45) * 3.0, 0, 1)[..., None]
helm = steel * (1 - k) + rust * k
Image.fromarray((np.clip(helm, 0, 1) * 255).astype(np.uint8)).save("art/klapper/klapper_helmet.jpg", quality=90)

# --- porcelain face ------------------------------------------------------------
S = 512
def face(cracks):
    base = np.ones((S, S, 3), np.float32) * np.array([0.7, 0.66, 0.58])
    base *= (0.86 + 0.18 * noise(S, S, 8))[..., None]
    img = Image.fromarray((base * 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    cx = S / 2
    # theatrical red diamonds through the eyes, faded
    for sx in (-1, 1):
        ex, ey = cx + sx * 92, 205
        dr.polygon([(ex, ey - 100), (ex + 22, ey), (ex, ey + 80), (ex - 22, ey)], fill=(128, 52, 46))
        dr.ellipse([ex - 40, ey - 30, ex + 40, ey + 30], fill=(24, 18, 16))           # socket
        dr.ellipse([ex - 70, 300, ex + 10 if sx < 0 else ex + 70, 350] if False else [ex - 46, 300, ex + 46, 346], fill=(170, 70, 64))  # rouge
    # the fixed grin: a wide dark slot, rows of small teeth
    top, bot = 360, 410
    dr.chord([cx - 150, top - 50, cx + 150, bot + 30], 10, 170, fill=(18, 12, 10))
    for i in range(-7, 8):
        x = cx + i * 18
        dr.rectangle([x - 7, top + 2, x + 7, top + 22], fill=(214, 204, 180))
        dr.rectangle([x - 7, bot - 18, x + 7, bot - 2], fill=(206, 196, 172))
    # dark lines of the jaw hinge, down from the corners of the mouth
    for sx in (-1, 1):
        dr.line([(cx + sx * 150, top + 10), (cx + sx * 136, 500)], fill=(60, 50, 44), width=3)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    dr = ImageDraw.Draw(img)
    # crazing and cracks
    lines = 34 if cracks else 9
    for n in range(lines):
        x, y = rng.uniform(40, S - 40), rng.uniform(30, S - 60)
        a = rng.uniform(0, math.tau)
        pts = [(x, y)]
        for k in range(rng.integers(5, 14 if cracks else 8)):
            a += rng.normal(0, 0.6)
            x += math.cos(a) * rng.uniform(8, 26); y += math.sin(a) * rng.uniform(8, 26)
            pts.append((x, y))
        dr.line(pts, fill=(40, 32, 28), width=3 if cracks and n < 10 else 1)
    # grime round the edges
    arr = np.asarray(img).astype(np.float32) / 255
    yy, xx = np.mgrid[0:S, 0:S] / S - 0.5
    edge = np.clip((np.sqrt(xx ** 2 + yy ** 2) - 0.32) * 4.0, 0, 1)
    arr *= (1 - 0.55 * edge * noise(S, S, 12))[..., None]
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))

face(False).save("art/klapper/klapper_face.png")
face(True).save("art/klapper/klapper_face_cracked.png")
print("klapper textures written")
