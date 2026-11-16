"""Placeholder sounds for the final-kill brutality report (synthesised).

A wheezy fairground calliope and a parade drum: drumroll, line (a drum
thump with a bell ping), stamp (the rank slammed down), crash (a cymbal),
fanfare (the calliope's ta-da, a little out of tune), coins (tickets).
Writes art/ui/sfx/. Run from the project root: python3 tools/gen_fanfare_sfx.py
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100
OUT = "art/ui/sfx"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1918)


def save(name, x, gain=0.9):
    x = x / (np.abs(x).max() + 1e-9) * gain
    with wave.open(f"{OUT}/{name}.wav", "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def band(n, lo, hi):
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    out = lfilter(b, a, rng.normal(0, 1, n))
    return out / (np.abs(out).max() + 1e-9)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def snare(dur=0.18, amp=1.0):
    x = t(dur)
    body = np.sin(2 * np.pi * 190 * x) * np.exp(-x / 0.03)
    rattle = band(len(x), 1500, 9000) * np.exp(-x / 0.06)
    return (body * 0.6 + rattle) * amp


def kick(dur=0.4):
    x = t(dur)
    return np.sin(2 * np.pi * (55 + 90 * np.exp(-x / 0.03)) * x) * np.exp(-x / 0.12)


def pipe(f, dur, amp=1.0, wheeze=0.06):
    """One calliope (steam whistle) note: breathy, a slow wobble, slightly sharp or flat."""
    x = t(dur)
    f = f * rng.uniform(0.985, 1.015)
    vib = 1 + 0.008 * np.sin(2 * np.pi * 5.5 * x)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    env = np.clip(x / 0.03, 0, 1) * np.clip((dur - x) / 0.06, 0, 1)
    return (tone + band(len(x), 800, 6000) * wheeze) * env * amp


def place(buf, snd, at):
    i = int(at * SR)
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[: j - i]


# drumroll: two seconds of snare, getting louder
n = int(SR * 2.2)
x = np.zeros(n)
k = 0.0
while k < 2.1:
    place(x, snare(0.12, 0.35 + 0.65 * k / 2.1), k)
    k += rng.uniform(0.045, 0.06)
save("drumroll", x, 0.7)

# a line of the report: a bass drum thump and a small bell
for i in range(3):
    m = int(SR * 0.6)
    y = np.zeros(m)
    place(y, kick(0.35) * 0.9, 0.0)
    xx = t(0.5)
    bell = sum(a * np.sin(2 * np.pi * f * (1 + 0.04 * i) * xx) * np.exp(-xx / d) for f, a, d in [(1320, 1, 0.25), (2650, 0.5, 0.12), (3960, 0.25, 0.08)])
    place(y, bell * 0.35, 0.01)
    save(f"line_{i}", y, 0.75)

# the rank stamped down: a big thump with a slap
y = np.zeros(int(SR * 0.8))
place(y, kick(0.6) * 1.2, 0.0)
place(y, band(int(SR * 0.08), 300, 4000) * np.exp(-t(0.08) / 0.02), 0.0)
save("stamp", y, 0.95)

# a cymbal crash
xx = t(2.5)
y = band(len(xx), 3000, 14000) * np.exp(-xx / 0.7) + band(len(xx), 600, 3000) * np.exp(-xx / 0.25) * 0.4
save("crash", y, 0.6)

# the fanfare: calliope ta-da-da-DAAA over an oom-pah, a touch out of tune
y = np.zeros(int(SR * 2.6))
notes = [(523, 0.0, 0.14), (659, 0.15, 0.14), (784, 0.30, 0.14), (1047, 0.45, 1.0)]
for f, at, d in notes:
    place(y, pipe(f, d + 0.05), at)
    place(y, pipe(f * 1.26, d + 0.05, 0.55), at)           # the third, sharp
for f, at in [(131, 0.0), (196, 0.3), (131, 0.45), (196, 0.75), (131, 1.05)]:
    place(y, pipe(f, 0.25, 0.7, 0.02), at)
place(y, snare(0.2, 0.8), 0.45)
place(y, kick(0.5), 0.45)
save("fanfare", y, 0.85)

# tickets: a till bell and coins
y = np.zeros(int(SR * 1.0))
xx = t(0.9)
place(y, sum(a * np.sin(2 * np.pi * f * xx) * np.exp(-xx / d) for f, a, d in [(2093, 1, 0.5), (4186, 0.4, 0.3), (3136, 0.3, 0.2)]), 0.0)
for i in range(7):
    xc = t(0.12)
    place(y, np.sin(2 * np.pi * rng.uniform(4000, 7000) * xc) * np.exp(-xc / 0.03) * 0.4, 0.12 + i * rng.uniform(0.04, 0.08))
save("coins", y, 0.7)
print("ok")
