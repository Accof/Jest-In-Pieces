"""Tileable surface textures for the anatomy (generated, no photographs).

    python3 art/anatomy/source/make_textures.py art/anatomy/tex

For each surface: <name>_albedo.png (colour) and <name>_hr.png (R: height, for
bump; G: roughness). Seamless in both directions (noise made in the frequency
domain, cells measured round the wrap), so the game can project them in three
directions onto meshes that have no UVs (shaders/anatomy.gdshader).
  bone       warm ivory, yellow-grey staining, pores, fine cracks, darker hollows
  cartilage  bluish pearl, faint fibres, smoother
  brain      pink-grey, mottled, a fine net of small vessels, damp
  lung       reddish grey, a pattern of small lobules, dark specks, blotches
  heart      dark red muscle with fat in pale streaks, satin
  liver      dark red-brown, fine grain, a glossy capsule
  gut        pink-grey to red, small vessels, wet
  colon      greyer, with fatty tags
  kidney     dark red-brown, smooth
  marrow     the cut end of a long bone: spongy, red-brown in yellow
"""
import os
import sys

import numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(1918)


def fnoise(beta, lo=1.0, hi=None):
    """Seamless noise with a 1/f^beta spectrum between frequencies lo and hi."""
    f = np.fft.fftfreq(N) * N
    fx, fy = np.meshgrid(f, f)
    r = np.hypot(fx, fy)
    r[0, 0] = 1
    amp = r ** (-beta)
    amp[r < lo] = 0
    if hi:
        amp[r > hi] = 0
    ph = np.exp(2j * np.pi * rng.random((N, N)))
    n = np.real(np.fft.ifft2(amp * ph))
    n -= n.min()
    return n / max(n.max(), 1e-9)


def cells(count, jitter=1.0):
    """Seamless Voronoi: distance to nearest and second-nearest point (0..1 of a cell)."""
    pts = rng.random((count, 2)) * N
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    d1 = np.full((N, N), 1e9, np.float32)
    d2 = np.full((N, N), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(x - px)
        dy = np.abs(y - py)
        dx = np.minimum(dx, N - dx)
        dy = np.minimum(dy, N - dy)
        d = np.hypot(dx, dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        d1 = np.where(closer, d, d1)
    size = N / np.sqrt(count)
    return d1 / size, d2 / size


def ridged(beta, lo, hi=None):
    """Thin lines (vessels, cracks): where a noise crosses its middle."""
    n = fnoise(beta, lo, hi)
    return 1.0 - np.abs(n - 0.5) * 2.0


def save(folder, name, albedo, height, rough):
    a = np.clip(albedo, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8), "RGB").save(os.path.join(folder, name + "_albedo.png"))
    hr = np.stack([np.clip(height, 0, 1), np.clip(rough, 0, 1), np.zeros_like(height)], -1)
    Image.fromarray((hr * 255).astype(np.uint8), "RGB").save(os.path.join(folder, name + "_hr.png"))


def mix(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


def col(*c):
    return np.array(c, np.float32)


def main(folder):
    os.makedirs(folder, exist_ok=True)
    big = fnoise(1.6, 1, 12)
    mid = fnoise(1.2, 6, 60)
    fine = fnoise(0.6, 40)

    # bone: ivory, stained, porous, crazed
    pores_d, _ = cells(2600)
    pores = np.clip(1.0 - pores_d * 3.2, 0, 1) ** 2 * (fine > 0.45)
    crack = np.clip((ridged(1.4, 3, 40) - 0.965) * 30, 0, 1) * (big > 0.35)
    stain = np.clip((big - 0.45) * 2.5, 0, 1)
    hollow = np.clip((0.5 - mid) * 2, 0, 1)
    c = mix(np.broadcast_to(col(0.80, 0.74, 0.61), (N, N, 3)), col(0.67, 0.60, 0.44), stain)
    c = mix(c, col(0.56, 0.50, 0.40), hollow * 0.5)
    c = c * (0.92 + 0.12 * fine[..., None])
    c = mix(c, col(0.36, 0.30, 0.22), np.clip(pores * 0.8 + crack * 0.9, 0, 1))
    h = 0.55 + 0.2 * mid + 0.1 * fine - 0.35 * pores - 0.4 * crack
    rough = 0.62 + 0.18 * fine + 0.12 * stain - 0.1 * hollow
    save(folder, "bone", c, h, rough)

    # cartilage: pearly, faintly fibrous
    fib = fnoise(1.0, 2, 80)
    fib = 0.5 + 0.5 * np.sin(np.linspace(0, 60 * np.pi, N)[None, :] + fib * 8)
    c = mix(np.broadcast_to(col(0.74, 0.74, 0.70), (N, N, 3)), col(0.62, 0.64, 0.66), mid * 0.7)
    c = c * (0.94 + 0.08 * fib[..., None])
    save(folder, "cartilage", c, 0.5 + 0.15 * fib + 0.1 * mid, 0.35 + 0.15 * fine)

    # brain: pink-grey, mottled, a net of small vessels
    vess = np.clip((ridged(1.3, 4, 90) - 0.93) * 14, 0, 1)
    vess2 = np.clip((ridged(1.1, 12, 160) - 0.95) * 18, 0, 1) * 0.6
    c = mix(np.broadcast_to(col(0.63, 0.50, 0.48), (N, N, 3)), col(0.50, 0.36, 0.36), mid)
    c = mix(c, col(0.72, 0.60, 0.56), np.clip((big - 0.55) * 2, 0, 1) * 0.5)
    c = c * (0.94 + 0.1 * fine[..., None])
    c = mix(c, col(0.42, 0.08, 0.08), np.clip(vess + vess2, 0, 1) * 0.85)
    wet = np.clip((fnoise(1.4, 3, 40) - 0.35) * 2.5, 0, 1)
    save(folder, "brain", c, 0.5 + 0.12 * mid + 0.15 * fine + 0.15 * vess, 0.48 - 0.25 * wet + 0.08 * fine)

    # lung: reddish grey, lobules, dark specks, blotches
    d1, d2 = cells(420)
    lob = np.clip(1.0 - (d2 - d1) * 6, 0, 1)
    specks = (fnoise(0.3, 120) > 0.82) * (big > 0.4)
    c = mix(np.broadcast_to(col(0.58, 0.40, 0.40), (N, N, 3)), col(0.42, 0.22, 0.28), np.clip((big - 0.4) * 2, 0, 1))
    c = c * (0.9 + 0.15 * mid[..., None])
    c = mix(c, col(0.30, 0.18, 0.20), lob * 0.55)
    c = mix(c, col(0.08, 0.07, 0.08), specks * 0.8)
    save(folder, "lung", c, 0.55 - 0.25 * lob + 0.15 * fine, 0.45 + 0.2 * fine - 0.1 * mid)

    # heart: dark red muscle, fat in pale streaks
    fat = np.clip((ridged(1.8, 1, 16) - 0.75) * 4, 0, 1) * np.clip((big - 0.25) * 2, 0, 1)
    fat_lobes, _ = cells(900)
    fat = np.clip(fat * (0.7 + 0.5 * (1 - fat_lobes)), 0, 1)
    c = mix(np.broadcast_to(col(0.36, 0.07, 0.07), (N, N, 3)), col(0.26, 0.04, 0.05), mid)
    c = c * (0.9 + 0.15 * fine[..., None])
    c = mix(c, col(0.70, 0.58, 0.34), fat)
    save(folder, "heart", c, 0.5 + 0.2 * fat + 0.1 * fine, 0.35 - 0.1 * fat + 0.15 * fine)

    # liver: dark red-brown, fine grain, glossy
    d1, d2 = cells(1500)
    grain = np.clip(1.0 - (d2 - d1) * 5, 0, 1)
    c = mix(np.broadcast_to(col(0.34, 0.10, 0.07), (N, N, 3)), col(0.25, 0.06, 0.05), mid)
    c = mix(c, col(0.42, 0.16, 0.10), np.clip((big - 0.55) * 2, 0, 1) * 0.6)
    c = c * (0.92 - 0.12 * grain[..., None] + 0.1 * fine[..., None])
    save(folder, "liver", c, 0.5 - 0.15 * grain + 0.1 * fine, 0.22 + 0.15 * fine + 0.1 * grain)

    # gut: pink-grey to red, small vessels, wet
    vess = np.clip((ridged(1.3, 6, 120) - 0.92) * 12, 0, 1)
    c = mix(np.broadcast_to(col(0.62, 0.42, 0.38), (N, N, 3)), col(0.52, 0.24, 0.24), np.clip((big - 0.35) * 2, 0, 1))
    c = c * (0.92 + 0.12 * mid[..., None])
    c = mix(c, col(0.40, 0.06, 0.07), vess * 0.8)
    wet = np.clip((fnoise(1.4, 3, 40) - 0.3) * 2.5, 0, 1)
    save(folder, "gut", c, 0.5 + 0.1 * mid + 0.1 * vess, 0.32 - 0.18 * wet + 0.08 * fine)

    # colon: greyer, fatty tags
    tags, _ = cells(260)
    tagm = np.clip(1.0 - tags * 2.6, 0, 1) * (mid > 0.5)
    c = mix(np.broadcast_to(col(0.54, 0.40, 0.34), (N, N, 3)), col(0.44, 0.28, 0.25), mid)
    c = c * (0.92 + 0.1 * fine[..., None])
    c = mix(c, col(0.72, 0.62, 0.40), tagm * 0.8)
    save(folder, "colon", c, 0.5 + 0.25 * tagm + 0.1 * mid, 0.36 - 0.1 * tagm + 0.1 * fine)

    # kidney: dark red-brown, smooth
    c = mix(np.broadcast_to(col(0.38, 0.12, 0.10), (N, N, 3)), col(0.30, 0.08, 0.07), mid)
    c = c * (0.93 + 0.1 * fine[..., None])
    save(folder, "kidney", c, 0.5 + 0.1 * mid + 0.05 * fine, 0.3 + 0.12 * fine)

    # muscle: dark red, in fibres, a sheen of fascia here and there
    fib = fnoise(1.0, 2, 60)
    fibres = 0.5 + 0.5 * np.sin(np.linspace(0, 90 * np.pi, N)[None, :] + fib * 10 + fnoise(1.5, 1, 8) * 6)
    fascia = np.clip((fnoise(1.6, 1, 10) - 0.6) * 3, 0, 1)
    c = mix(np.broadcast_to(col(0.40, 0.07, 0.07), (N, N, 3)), col(0.28, 0.04, 0.05), mid)
    c = c * (0.82 + 0.25 * fibres[..., None])
    c = mix(c, col(0.62, 0.50, 0.48), fascia * 0.45)
    save(folder, "muscle", c, 0.5 + 0.2 * fibres + 0.1 * fine, 0.45 - 0.2 * fascia + 0.1 * fine)

    # marrow: the cut end of a long bone, spongy, red-brown in yellow
    d1, d2 = cells(1800)
    sponge = np.clip((d2 - d1) * 4, 0, 1)
    c = mix(np.broadcast_to(col(0.52, 0.18, 0.12), (N, N, 3)), col(0.70, 0.58, 0.36), np.clip((big - 0.4) * 2, 0, 1) * 0.7)
    c = mix(c, col(0.78, 0.70, 0.56), sponge * 0.6)
    save(folder, "marrow", c, 0.3 + 0.5 * sponge, 0.45 - 0.15 * (1 - sponge))
    print("wrote", sorted(os.listdir(folder)))


if __name__ == "__main__":
    main(sys.argv[1])
