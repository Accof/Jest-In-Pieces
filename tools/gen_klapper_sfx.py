"""Placeholder sounds for Der Klappersoldat, synthesised (not final audio).

Old clockwork and industrial machinery, not sci-fi: ticks, ratchets,
grinding gear trains, squeaking joints, iron footfalls, bell-metal clangs,
bullet pings, electrical crackle, a spring running down.
Run from the project root: python3 tools/gen_klapper_sfx.py
"""
import wave
import numpy as np

SR = 44100
rng = np.random.default_rng(42)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.002, decay=0.1):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-5), 0, 1)
    return a * np.exp(-x / decay)


def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.normal(0, 1, n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[(f < lo) | (f > hi)] = 0
    out = np.fft.irfft(spec, n)
    return out / (np.abs(out).max() + 1e-9)


def ring(n, freqs, decays, amps):
    x = np.arange(n) / SR
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6)) * np.exp(-x / d)
    return out


def click(n, f=3500, d=0.004):
    return bandnoise(n, f * 0.6, f * 1.6) * env(n, 0.0003, d)


def place(buf, snd, at):
    i = int(at * SR)
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[: j - i]


def save(name, x, gain=0.9):
    x = x / (np.abs(x).max() + 1e-9) * gain
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(f"art/klapper/sfx/{name}.wav", "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())


n = int(SR * 0.08)
save("tick", click(n, 4200, 0.003) + 0.4 * ring(n, [2900, 5100], [0.01, 0.006], [0.5, 0.3]), 0.5)
save("tock", click(n, 2600, 0.004) + 0.4 * ring(n, [1900, 3700], [0.012, 0.007], [0.5, 0.3]), 0.5)

for k in range(3):
    n = int(SR * 0.45)
    thud = np.sin(2 * np.pi * (70 + 15 * k) * t(0.45)) * env(n, 0.002, 0.05)
    clank = ring(n, [380 + 40 * k, 1130, 2250, 3400], [0.09, 0.06, 0.04, 0.02], [0.5, 0.35, 0.25, 0.15])
    grit = bandnoise(n, 500, 4000) * env(n, 0.001, 0.02) * 0.6
    save(f"step_{k}", thud * 1.2 + clank * env(n, 0.001, 0.12) + grit, 0.7)

n = int(SR * 0.45)
ratchet = (np.sin(2 * np.pi * 34 * t(0.45)) > 0.6).astype(float)
g = bandnoise(n, 300, 2500) * (0.35 + ratchet) * np.hanning(n) + 0.3 * np.sign(np.sin(2 * np.pi * 34 * t(0.45))) * bandnoise(n, 80, 400) * np.hanning(n)
save("grind", g, 0.8)

n = int(SR * 0.26)
x = t(0.26)
f = 1700 + 900 * x / 0.26 + 120 * np.sin(2 * np.pi * 23 * x)
save("squeak", np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(n) * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * x)), 0.35)

n = int(SR * 0.4)
r = np.zeros(n)
for k in range(14):
    place(r, click(int(SR * 0.03), rng.uniform(1800, 5200), 0.003) * rng.uniform(0.3, 1.0), rng.uniform(0, 0.36))
save("rattle", r, 0.6)

n = int(SR * 0.9)
w = np.zeros(n)
at, gap = 0.0, 0.11
while at < 0.82:
    place(w, click(int(SR * 0.05), 3000, 0.006) + 0.3 * ring(int(SR * 0.05), [1500], [0.02], [1]), at)
    at += gap; gap = max(gap * 0.86, 0.03)
w += 0.25 * bandnoise(n, 120, 600) * np.linspace(0.2, 1, n) * np.hanning(n)
save("windup", w, 0.7)

n = int(SR * 1.0)
strike = 1.4 * np.sin(2 * np.pi * 55 * t(1.0)) * env(n, 0.001, 0.07) + ring(n, [210, 523, 1187, 2011, 3150], [0.5, 0.35, 0.22, 0.12, 0.07], [0.6, 0.5, 0.35, 0.25, 0.15]) + bandnoise(n, 800, 7000) * env(n, 0.0005, 0.03)
save("strike", strike, 0.95)

for k in range(3):
    n = int(SR * 0.35)
    f0 = [2400, 3100, 3900][k]
    ping = ring(n, [f0, f0 * 1.49, f0 * 2.31], [0.07, 0.04, 0.025], [0.7, 0.35, 0.2]) + bandnoise(n, 2000, 9000) * env(n, 0.0003, 0.006) * 1.5
    save(f"ping_{k}", ping, 0.6)

def crackle(sec, rate):
    n = int(SR * sec)
    c = np.zeros(n)
    pos = 0.0
    while pos < sec - 0.02:
        place(c, click(int(SR * 0.015), rng.uniform(3000, 8000), rng.uniform(0.0008, 0.003)) * rng.uniform(0.2, 1.0), pos)
        pos += rng.exponential(1.0 / rate)
    c += 0.12 * bandnoise(n, 4000, 12000) * (rng.random(n) > 0.5)
    return c * np.linspace(1, 0.4, n)

save("spark", crackle(0.45, 90), 0.55)
save("crackle", crackle(1.6, 45), 0.45)

n = int(SR * 1.3)
fail = np.zeros(n)
place(fail, 1.2 * np.sin(2 * np.pi * 60 * t(0.3)) * env(int(SR * 0.3), 0.001, 0.06) + ring(int(SR * 0.3), [430, 1210], [0.1, 0.05], [0.6, 0.3]), 0.0)
x = t(0.9)
twang = np.sin(2 * np.pi * np.cumsum(420 * np.exp(-x * 1.8) + 80) / SR) * np.exp(-x / 0.4) * 0.6
place(fail, twang, 0.08)
place(fail, bandnoise(int(SR * 0.7), 300, 2200) * np.hanning(int(SR * 0.7)) * 0.5, 0.25)
save("failure", fail, 0.9)

n = int(SR * 2.8)
down = np.zeros(n)
at, gap = 0.0, 0.07
while at < 2.6:
    place(down, click(int(SR * 0.05), 3000 - at * 600, 0.004) * (1 - at / 2.8), at)
    at += gap; gap *= 1.16
x = t(2.8)
down += 0.35 * np.sin(2 * np.pi * np.cumsum(140 * np.exp(-x * 0.9) + 20) / SR) * np.exp(-x / 1.1)
save("winddown", down, 0.7)

n = int(SR * 0.5)
clat = ring(n, [260, 710, 1630, 2900], [0.12, 0.07, 0.04, 0.02], [0.6, 0.5, 0.3, 0.2]) * env(n, 0.001, 0.15) + bandnoise(n, 150, 3000) * env(n, 0.001, 0.03)
for k in range(5):
    place(clat, click(int(SR * 0.03), rng.uniform(2000, 5000), 0.003) * 0.4, rng.uniform(0.05, 0.35))
save("clatter", clat, 0.8)

n = int(SR * 0.25)
save("jaw", click(n, 1800, 0.01) + 0.5 * ring(n, [900, 2100], [0.03, 0.02], [0.6, 0.3]), 0.4)
# an electric arc: a hard buzz at mains-ish frequency with crackle, very short
n = int(SR * 0.22)
x = t(0.22)
buzz = np.sign(np.sin(2 * np.pi * 100 * x)) * 0.4 + np.sin(2 * np.pi * 300 * x) * 0.3
zap = (buzz * bandnoise(n, 1500, 9000) * 0.6 + bandnoise(n, 3000, 12000) * 0.5) * env(n, 0.001, 0.06)
for k in range(6):
    place(zap, click(int(SR * 0.01), rng.uniform(4000, 9000), 0.0015), rng.uniform(0, 0.18))
save("zap", zap, 0.7)

# a heavy metal body hitting the floor: a deep thump and a dull iron ring
n = int(SR * 0.7)
thud = 1.6 * np.sin(2 * np.pi * 48 * t(0.7)) * env(n, 0.002, 0.09) + 0.8 * np.sin(2 * np.pi * 85 * t(0.7)) * env(n, 0.002, 0.06)
thud += ring(n, [180, 410, 960], [0.18, 0.1, 0.05], [0.35, 0.25, 0.12]) * env(n, 0.001, 0.25)
thud += bandnoise(n, 100, 1500) * env(n, 0.001, 0.04) * 0.8
save("thud", thud, 0.95)
print("klapper sfx written")
