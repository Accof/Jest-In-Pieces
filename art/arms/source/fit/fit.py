# Fit one hand to the gun: hand offset (model space) that keeps the palm out, then each
import os
# finger's three curls so every segment rests on the surface. Usage: SIDE=R fit.py sdf.npz
import sys, json, itertools, numpy as np
sys.path.insert(0, '/tmp/fit'); from handfk2 import *
SDF = load_sdf(sys.argv[1]); TOL = 0.0015
hand = f'hand.{SIDE}'; H0 = B[hand]['G']
palm = (H0 @ LOCAL[hand])[:3].T
best = None
for dx, dy, dz in ([(0, 0, 0)] if os.environ.get("NOSHIFT") else itertools.product(*(np.arange(-0.02, 0.0201, 0.004),) * 3)):
    s = SDF(palm + [dx, dy, dz]); pen = max(0, -s.min()); gap = max(0, np.percentile(s, 2))
    key = (pen > TOL, pen if pen > TOL else gap)
    if best is None or key < best[0]: best = (key, (dx, dy, dz), pen, gap)
shift = np.array(best[1]); print("hand shift", shift.round(3), "palm deepest %.1f mm, nearest %.1f mm" % (best[2] * 1000, best[3] * 1000))
SH = np.eye(4); SH[:3, 3] = shift; root = SH @ H0
res = {}
import os
for f in (('middle', 'ring', 'little') if os.environ.get('TARGET') else ('index', 'middle', 'ring', 'little')):
    cands = []; worst = []
    for c1 in range(-10, 101, 5):
        for c2 in range(0, 111, 5):
            for k in (0.5, 0.7, 0.9):
                c3 = round(c2 * k); pose = {f'{f}_01': (c1, 0, 0), f'{f}_02': (c2, 0, 0), f'{f}_03': (c3, 0, 0)}
                m = [SDF(v).min() for v in seg_verts(chain_G(f, pose, root)).values()]
                if max(0, -min(m)) > TOL:
                    worst.append((max(0, -min(m)), (c1, c2, c3), m)); continue
                cands.append((sum(max(0, x - 0.003) ** 2 for x in m), (c1, c2, c3), m))
    cands.sort(key=lambda c: c[0])
    if not cands:
        worst.sort(key=lambda c: c[0]); cands = worst; print(f"   {f}: no clean pose, least deep:")
    g, c, m = cands[0]; res[f] = c
    print(f"{f:7s} {c}  segment gaps (mm) {[round(x * 1000, 1) for x in m]}")
cands = []
for x1 in range(-30, 61, 6):
    for z1 in range(-40, 41, 8):
        for c2 in range(-10, 61, 10):
            for c3 in range(0, 61, 15):
                pose = {'thumb_01': (x1, 0, z1), 'thumb_02': (c2, 0, 0), 'thumb_03': (c3, 0, 0)}
                m = [SDF(v).min() for v in seg_verts(chain_G('thumb', pose, root)).values()]
                if max(0, -min(m)) > TOL: continue
                cands.append((sum(max(0, x - 0.003) ** 2 for x in m[1:]), (x1, z1, c2, c3), m))
cands.sort(key=lambda c: c[0]); g, c, m = cands[0]; res['thumb'] = c
print(f"thumb   {c}  segment gaps (mm) {[round(x * 1000, 1) for x in m]}")
json.dump(dict(shift=shift.tolist(), **res), open(f'/tmp/fit/fit_{SIDE}.json', 'w'))
import os
if os.environ.get('TARGET'):
    tgt = np.array([float(x) for x in os.environ['TARGET'].split(',')])
    L3 = LOCAL[f'index_03.{SIDE}']; tipmask = L3[1] > 0.6 * L3[1].max(); pad_local = L3[:, tipmask].mean(1)
    cands = []
    for spread in range(-50, 51, 5):
        for c1 in range(-40, 81, 5):
            for c2 in range(0, 101, 5):
                for c3 in range(0, 81, 10):
                    pose = {'index_01': (c1, 0, spread), 'index_02': (c2, 0, 0), 'index_03': (c3, 0, 0)}
                    Gs = chain_G('index', pose, root)
                    m = [SDF(v).min() for v in seg_verts(Gs).values()]
                    pen = max(0, -min(m))
                    pad = (Gs[f'index_03.{SIDE}'] @ pad_local)[:3]
                    cands.append((pen > 0.005, np.linalg.norm(pad - tgt) + pen * 1.5, (c1, spread, c2, c3), pen, pad))
    cands.sort(key=lambda c: (c[0], c[1]))
    _, d, c, pen, pad = cands[0]; res['index'] = c
    print(f"index to target: {c} pad {pad.round(3)} {d*1000:.1f} mm from target, deepest {pen*1000:.1f} mm")
    json.dump(dict(shift=shift.tolist(), **res), open(f'/tmp/fit/fit_{SIDE}.json', 'w'))
