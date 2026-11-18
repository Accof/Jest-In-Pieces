# Signed distance grid of chosen gun parts in a box. Usage: sdf2.py parts x0 x1 y0 y1 z0 z1 out.npz
import numpy as np, trimesh, sys
from scipy.spatial import cKDTree
sys.path.insert(0, '/tmp/fit'); from wind import winding
parts = sys.argv[1].split(','); x0, x1, y0, y1, z0, z1 = map(float, sys.argv[2:8]); out = sys.argv[8]
rows = [l.split() for l in open('/tmp/gun_tris.txt')]
T = np.array([[float(x) for x in r[1:]] for r in rows if r[0] in parts]).reshape(-1, 3, 3)
c = T.mean(1); m_ = (c[:, 0] > x0 - 0.05) & (c[:, 0] < x1 + 0.05) & (c[:, 1] > y0 - 0.05) & (c[:, 1] < y1 + 0.05); T = T[m_]
m = trimesh.Trimesh(vertices=T.reshape(-1, 3), faces=np.arange(len(T) * 3).reshape(-1, 3), process=False)
step = 0.004
xs = np.arange(x0, x1, step); ys = np.arange(y0, y1, step); zs = np.arange(z0, z1, step)
G = np.stack(np.meshgrid(xs, ys, zs, indexing='ij'), -1).reshape(-1, 3)
S, fi = trimesh.sample.sample_surface_even(m, 400000, radius=0.0007)
kd = cKDTree(S); dist, ix = kd.query(G, workers=-1); cp = S[ix]; nrm = m.face_normals[fi[ix]]
sgn = np.sign(np.einsum('ij,ij->i', G - cp, nrm)); sgn[sgn == 0] = 1
idx = np.random.default_rng(0).choice(np.where(dist < 0.03)[0], 1200, replace=False)
w = winding(T, G[idx]); agree = ((np.abs(w) > 0.5) == (sgn[idx] < 0)).mean()
if agree < 0.5: sgn = -sgn; agree = 1 - agree
print(f"{len(T)} tris, grid {len(G)}, sign agrees with winding {agree*100:.1f}%")
np.savez(out, xs=xs, ys=ys, zs=zs, sdf=(dist * sgn).reshape(len(xs), len(ys), len(zs)))
