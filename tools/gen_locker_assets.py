"""Placeholder art and sound for the joker lockers (synthesised, not final).

Writes art/locker/:
  joker_card.png   the little joker playing card on the locker door, and the
                   face of the cards that spill out of the dead clown
  card_back.png    the back of the cards
  locker_paint.png chipped olive-drab paint over steel, a little rust
  sfx/laugh_0-2    a clown laughing, muffled inside a steel locker
  sfx/rattle_0-1   the door jumping on its latch
  sfx/dent_0-2     bullets punching the thin sheet steel
  sfx/burst        the latch giving way and the door slamming open
  sfx/thump        the body hitting the floor
Run from the project root: python3 tools/gen_locker_assets.py
"""
import os
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.signal import lfilter, butter

OUT = "art/locker"
os.makedirs(OUT + "/sfx", exist_ok=True)
rng = np.random.default_rng(1916)
SR = 44100


# --- pictures ---------------------------------------------------------------------
def joker_card():
    w, h = 256, 360
    im = Image.new("RGB", (w, h), (226, 214, 186))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([4, 4, w - 5, h - 5], 18, outline=(30, 24, 20), width=4)
    d.rounded_rectangle([18, 18, w - 19, h - 19], 10, outline=(150, 20, 22), width=3)
    # corner "J"s
    for (x, y, flip) in [(26, 22, False), (w - 50, h - 70, True)]:
        d.line([(x + 14, y + 4), (x + 14, y + 34)], fill=(150, 20, 22), width=6)
        d.arc([x - 2, y + 18, x + 16, y + 40], 0, 180, fill=(150, 20, 22), width=6)
        d.line([(x + 6, y + 4), (x + 22, y + 4)], fill=(150, 20, 22), width=5)
    cx, cy = w // 2, h // 2 + 20
    # the cap: three floppy points, red and black, with bells
    pts = [(-70, -110), (0, -140), (70, -110)]
    for i, (px, py) in enumerate(pts):
        col = (150, 20, 22) if i != 1 else (24, 20, 20)
        d.polygon([(cx - 52 + i * 34, cy - 40), (cx + px, cy + py), (cx - 18 + i * 34, cy - 40)], fill=col)
        d.ellipse([cx + px - 9, cy + py - 9, cx + px + 9, cy + py + 9], fill=(200, 160, 50), outline=(80, 60, 20), width=2)
    d.rectangle([cx - 56, cy - 48, cx + 56, cy - 34], fill=(200, 160, 50))
    # the face
    d.ellipse([cx - 46, cy - 40, cx + 46, cy + 56], fill=(240, 236, 226), outline=(30, 24, 20), width=3)
    for sx in (-1, 1):
        ex = cx + sx * 18
        d.polygon([(ex - 10, cy - 2), (ex + 10, cy - 2), (ex, cy - 20)], fill=(24, 20, 20))   # diamond eyes
        d.polygon([(ex - 10, cy - 2), (ex + 10, cy - 2), (ex, cy + 14)], fill=(24, 20, 20))
        d.line([(ex, cy + 14), (ex, cy + 30)], fill=(30, 40, 120), width=3)                 # painted tears
    d.ellipse([cx - 8, cy + 6, cx + 8, cy + 22], fill=(190, 20, 24))
    d.chord([cx - 34, cy + 6, cx + 34, cy + 50], 0, 180, fill=(150, 20, 22), outline=(24, 20, 20), width=2)
    for k in range(-3, 4):
        d.line([(cx + k * 8, cy + 28), (cx + k * 8, cy + 36)], fill=(240, 236, 226), width=3)
    # ruff
    for k in range(9):
        a = np.pi * (0.15 + 0.7 * k / 8)
        x, y = cx + np.cos(a) * 56, cy + 62 + np.sin(a) * 6
        d.ellipse([x - 12, y - 10, x + 12, y + 10], fill=(150, 20, 22) if k % 2 else (24, 20, 20))
    # grime
    a = np.array(im).astype(np.float32)
    n = rng.normal(0, 1, (h // 8, w // 8))
    n = np.array(Image.fromarray(((n - n.min()) / (n.max() - n.min()) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255.0
    a *= (0.78 + 0.22 * n)[..., None]
    a[..., 2] *= 0.92
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(OUT + "/joker_card.png")


def card_back():
    w, h = 128, 180
    im = Image.new("RGB", (w, h), (226, 214, 186))
    d = ImageDraw.Draw(im)
    d.rectangle([8, 8, w - 9, h - 9], fill=(120, 22, 26))
    for y in range(8, h - 8, 12):
        for x in range(8, w - 8, 12):
            d.polygon([(x + 6, y), (x + 12, y + 6), (x + 6, y + 12), (x, y + 6)], outline=(200, 160, 120))
    d.rectangle([8, 8, w - 9, h - 9], outline=(226, 214, 186), width=3)
    im.save(OUT + "/card_back.png")


def locker_paint():
    w, h = 256, 512
    def blot(scale, seed):
        r = np.random.default_rng(seed).normal(0, 1, (h // scale + 1, w // scale + 1))
        img = Image.fromarray(((r - r.min()) / (r.max() - r.min()) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        return np.array(img).astype(np.float32) / 255.0
    base = np.zeros((h, w, 3), np.float32)
    olive = np.array([72, 74, 46], np.float32)
    n = blot(16, 1) * 0.6 + blot(4, 2) * 0.4
    base[:] = olive * (0.82 + 0.3 * n)[..., None]
    # chips through to grey primer and bare steel, worst at the edges and low down
    chip = blot(6, 3) * 0.6 + blot(2, 4) * 0.4
    yy = np.linspace(0, 1, h)[:, None]
    xx = np.abs(np.linspace(-1, 1, w))[None, :]
    wear = chip + 0.25 * yy + 0.3 * (xx > 0.9)
    steel = np.array([118, 116, 110], np.float32)
    base = np.where((wear > 1.02)[..., None], steel * (0.7 + 0.3 * blot(2, 5))[..., None], base)
    # rust runs down from the chips
    rust = np.array([96, 48, 24], np.float32)
    streak = np.array(Image.fromarray((np.clip(wear - 0.9, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1)).resize((w, h)))
    run = np.zeros((h, w), np.float32)
    s = streak.astype(np.float32) / 255.0
    for y in range(1, h):
        run[y] = np.maximum(s[y], run[y - 1] * 0.985)
    base = base * (1 - 0.55 * run[..., None]) + rust * 0.55 * run[..., None]
    # scratches
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for _ in range(40):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.uniform(-0.6, 0.6) + np.pi * 0.5 * rng.integers(0, 2)
        L = rng.uniform(6, 40)
        d.line([(x, y), (x + np.cos(a) * L, y + np.sin(a) * L)], fill=(130, 126, 112), width=1)
    im.save(OUT + "/locker_paint.png")


# --- sound ------------------------------------------------------------------------
def save(name, x, gain=0.9):
    x = x / (np.abs(x).max() + 1e-9) * gain
    with wave.open(f"{OUT}/sfx/{name}.wav", "w") as wv:
        wv.setnchannels(1); wv.setsampwidth(2); wv.setframerate(SR)
        wv.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def resonate(x, f, bw):
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    return lfilter([1 - r], [1, -2 * r * np.cos(th), r * r], x)


def lowpass(x, f, order=2):
    b, a = butter(order, f / (SR / 2))
    return lfilter(b, a, x)


def bandnoise(n, lo, hi):
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    out = lfilter(b, a, rng.normal(0, 1, n))
    return out / (np.abs(out).max() + 1e-9)


def ring(n, freqs, decays, amps):
    t = np.arange(n) / SR
    return sum(a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / d) for f, d, a in zip(freqs, decays, amps))


VOWELS = {"a": (760, 1250, 2550), "e": (520, 1850, 2600), "u": (380, 900, 2400), "i": (320, 2200, 2900)}


def syllable(f0_start, f0_end, dur, vowel, breath=0.05, wheeze=0.0):
    """One 'ha': a puff of breath, then a voiced vowel with a cracking pitch."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    f0 = np.linspace(f0_start, f0_end, n) * (1 + 0.03 * np.sin(2 * np.pi * 7 * t)) * (1 + rng.normal(0, 0.006, n))
    ph = np.cumsum(f0 / SR)
    src = (ph % 1.0) * 2 - 1                         # sawtooth-ish glottal source
    src = np.sign(src) * np.abs(src) ** 3
    voiced = sum(resonate(src, f, 90 + f * 0.06) * g for f, g in zip(VOWELS[vowel], (1.0, 0.55, 0.25)))
    nb = int(SR * breath)
    aspir = np.zeros(n)
    aspir[:nb] = bandnoise(nb, 600, 4000) * np.linspace(0.0, 1.0, nb) ** 0.5
    env = np.clip(t / 0.015, 0, 1) * np.clip((dur - t) / 0.06, 0, 1)
    vstart = np.clip((t - breath * 0.7) / 0.02, 0, 1)
    voiced = voiced / (np.abs(voiced).max() + 1e-9)
    out = voiced * vstart * env + aspir * 0.35 + bandnoise(n, 900, 5000) * wheeze * env
    return out


def muffle(x):
    """Inside a tall steel box: dull, boxy, a tinny ring off the sheet."""
    y = lowpass(x, 1600, 3)
    box = resonate(y, 210, 40) * 0.35 + resonate(y, 470, 60) * 0.2 + resonate(y, 1150, 120) * 0.08
    y = y + box
    d = int(SR * 0.011)
    y[d:] += 0.35 * y[:-d]                           # the slap back off the door
    return y


def laugh(pattern, gap, f0, fall, vowel, tail=0.5, wheeze=0.0):
    parts = []
    for k, dur in enumerate(pattern):
        a = f0 * (1 - fall * k / len(pattern)) * rng.uniform(0.96, 1.05)
        parts.append(syllable(a * 1.06, a * 0.9, dur, vowel, wheeze=wheeze) * (1 - 0.05 * k))
        parts.append(np.zeros(int(SR * gap * rng.uniform(0.8, 1.2))))
    x = np.concatenate(parts + [np.zeros(int(SR * tail))])
    return muffle(x)


joker_card()
card_back()
locker_paint()

# a high cackle running down
save("laugh_0", laugh([0.16] * 7 + [0.3], 0.05, 330, 0.35, "a", wheeze=0.08), 0.8)
# a quick giggle, breathy, rising at the end
g = laugh([0.09] * 9, 0.035, 300, -0.25, "i", wheeze=0.15)
save("laugh_1", g, 0.75)
# slow and low, a long wheeze to finish
low = laugh([0.28, 0.26, 0.24, 0.5], 0.12, 150, 0.2, "u", tail=0.2)
wz = muffle(bandnoise(int(SR * 0.9), 700, 3500) * np.hanning(int(SR * 0.9)) * 0.4)
save("laugh_2", np.concatenate([low, wz]), 0.8)

for k in range(2):
    n = int(SR * 0.6)
    x = np.zeros(n)
    for j in range(3 + k):
        at = int(SR * (0.02 + j * rng.uniform(0.06, 0.11)))
        m = int(SR * 0.25)
        hit = ring(m, [180 + 30 * k, 420, 980, 2300], [0.12, 0.08, 0.04, 0.02], [0.8, 0.5, 0.3, 0.15])
        hit += bandnoise(m, 300, 5000) * np.exp(-np.arange(m) / SR / 0.01) * 0.7
        x[at:at + m] += hit[: n - at] * (1 - 0.2 * j)
    save(f"rattle_{k}", x, 0.6)

for k in range(3):
    n = int(SR * 0.45)
    t = np.arange(n) / SR
    x = bandnoise(n, 1500, 9000) * np.exp(-t / 0.004) * 1.4
    x += ring(n, [160 + 25 * k, 380 + 40 * k, 870, 1900 + 200 * k], [0.18, 0.1, 0.05, 0.03], [1.0, 0.6, 0.35, 0.2])
    save(f"dent_{k}", x, 0.85)

n = int(SR * 1.6)
t = np.arange(n) / SR
x = np.sin(2 * np.pi * 55 * t) * np.exp(-t / 0.09) * 1.2                        # the door hitting its stop
x += bandnoise(n, 200, 6000) * np.exp(-t / 0.02)
x += ring(n, [140, 330, 610, 1250, 2700], [0.5, 0.35, 0.25, 0.12, 0.05], [1.0, 0.7, 0.5, 0.3, 0.15])
snap = np.zeros(n)
s = int(SR * 0.012)
snap[:s] = bandnoise(s, 2000, 9000)                                            # the latch letting go
x = np.concatenate([snap[: int(SR * 0.03)], x])[:n]
save("burst", x, 0.95)

n = int(SR * 0.7)
t = np.arange(n) / SR
x = np.sin(2 * np.pi * (70 - 25 * t) * t) * np.exp(-t / 0.12) + bandnoise(n, 80, 900) * np.exp(-t / 0.05) * 0.6
save("thump", x, 0.9)
print("ok")
