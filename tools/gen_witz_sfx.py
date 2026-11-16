"""Placeholder sounds for the WitzSoldat's bolt-action rifle (synthesised).

Writes art/witzsoldat/sfx/: shot_0-2 (the report: a hard crack, a low boom
and a tail rolling off the walls), bolt_open (handle up, bolt back), bolt_close
(bolt forward, handle down), casing_0-1 (brass tinkling on concrete).
Run from the project root: python3 tools/gen_witz_sfx.py
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100
OUT = "art/witzsoldat/sfx"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1915)


def save(name, x, gain=0.9):
    x = x / (np.abs(x).max() + 1e-9) * gain
    with wave.open(f"{OUT}/{name}.wav", "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def band(n, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    out = lfilter(b, a, rng.normal(0, 1, n))
    return out / (np.abs(out).max() + 1e-9)


def low(x, f):
    b, a = butter(2, f / (SR / 2))
    return lfilter(b, a, x)


def ring(n, freqs, decays, amps):
    t = np.arange(n) / SR
    return sum(a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / d) for f, d, a in zip(freqs, decays, amps))


def click(n, lo=1500, hi=9000, d=0.004):
    t = np.arange(n) / SR
    return band(n, lo, hi) * np.exp(-t / d)


for k in range(3):
    n = int(SR * 2.2)
    t = np.arange(n) / SR
    crack = band(n, 1200, 12000) * np.exp(-t / 0.006) * 1.6
    boom = low(rng.normal(0, 1, n), 260) * np.exp(-t / 0.09) * 9
    boom += np.sin(2 * np.pi * (70 - 30 * t) * t) * np.exp(-t / 0.12) * 0.9
    tail = low(band(n, 120, 2400), 1400) * np.exp(-t / (0.55 + 0.1 * k)) * 0.35
    echo = np.zeros(n)
    for d, g in [(0.045, 0.35), (0.11, 0.22), (0.19, 0.14), (0.31, 0.08)]:
        i = int(SR * (d + rng.uniform(-0.01, 0.01)))
        echo[i:] += (crack + boom)[: n - i] * g
    x = crack + boom + tail + low(echo, 2500)
    x = np.tanh(x * 1.4)
    save(f"shot_{k}", x, 0.95)

# handle up (a scrape and a knock), then the bolt drawn back (a slide, a stop)
n = int(SR * 0.42)
x = np.zeros(n)
x[: int(SR * 0.05)] += band(int(SR * 0.05), 800, 6000) * np.linspace(0.4, 1, int(SR * 0.05)) * 0.3
x += np.roll(click(n, 1000, 7000, 0.006) + ring(n, [1900, 3400], [0.02, 0.01], [0.3, 0.2]), int(SR * 0.05))
s = int(SR * 0.12)
slide = band(s, 1500, 8000) * np.hanning(s) * 0.35
x[int(SR * 0.16): int(SR * 0.16) + s] += slide
x += np.roll(click(n, 800, 6000, 0.008) * 1.2 + ring(n, [1200, 2600, 4100], [0.03, 0.02, 0.01], [0.5, 0.3, 0.2]), int(SR * 0.28))
save("bolt_open", x, 0.7)

# bolt shoved home (a slide, a solid knock), then the handle down (a click)
n = int(SR * 0.4)
x = np.zeros(n)
s = int(SR * 0.09)
x[: s] += band(s, 1500, 8000) * np.hanning(s) * 0.35
x += np.roll(click(n, 600, 5000, 0.01) * 1.4 + ring(n, [900, 2100, 3700], [0.04, 0.02, 0.01], [0.6, 0.35, 0.2]), int(SR * 0.09))
x += np.roll(click(n, 2000, 9000, 0.003) + ring(n, [2800, 5200], [0.015, 0.008], [0.3, 0.15]), int(SR * 0.22))
save("bolt_close", x, 0.7)

for k in range(2):
    n = int(SR * 0.9)
    x = np.zeros(n)
    at = 0.0
    for j in range(4 + k):
        m = int(SR * 0.12)
        hit = ring(m, [5200 + 300 * k, 7900, 11200], [0.05, 0.03, 0.02], [1.0, 0.6, 0.3]) + click(m, 3000, 12000, 0.002)
        i = int(SR * at)
        x[i:i + m] += hit[: max(0, min(m, n - i))] * (0.85 ** j)
        at += rng.uniform(0.07, 0.16) * (0.75 ** j)
    save(f"casing_{k}", x, 0.4)
print("ok")
