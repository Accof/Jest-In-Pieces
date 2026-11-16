"""Machine-oil splats for the Klappersoldat, made from the blood splats.

Same shapes, alpha and normal maps as the blood (art/blood); the colour is
turned into near-black oil with a faint brown and a hint of oily sheen.
Run from the project root: python3 tools/gen_oil_textures.py
"""
import glob, os
import numpy as np
from PIL import Image

os.makedirs("art/oil", exist_ok=True)
rng = np.random.default_rng(7)
for path in sorted(glob.glob("art/blood/splat_*_[0-9].png")):
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    lum = im[..., 0] / 255.0                      # blood keeps its depth in red
    h, w = lum.shape
    # slow wobble across the splat for a thin-film tint (brown <-> green-blue)
    yy, xx = np.mgrid[0:h, 0:w] / max(h, w)
    ph = rng.uniform(0, 6.28)
    film = 0.5 + 0.5 * np.sin(xx * 9.0 + yy * 6.0 + ph + np.sin(yy * 13.0) * 1.5)
    base = np.stack([0.11 + 0.03 * film, 0.095 + 0.02 * film, 0.07 + 0.035 * (1 - film)], -1)
    rgb = base * (0.45 + 2.6 * lum[..., None])
    out = np.concatenate([np.clip(rgb, 0, 1) * 255.0, im[..., 3:4]], -1).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(path.replace("art/blood", "art/oil"))
    print("wrote", path.replace("art/blood", "art/oil"))
