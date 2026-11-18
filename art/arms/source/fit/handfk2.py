import numpy as np, os
from scipy.spatial.transform import Rotation as Rot
from scipy.interpolate import RegularGridInterpolator as RGI
SIDE = os.environ.get('SIDE', 'R')
def v3(s): return [float(x) for x in s[s.index('(')+1:s.rindex(')')].split(',')]
B = {}
for l in open('/tmp/hand_bones.txt'):
    t = l.split(); n = t[0]
    q = [float(x) for x in t[2:6]]; o = np.array([float(x) for x in t[6:9]])
    bx, by, bz, org = [np.array(v3(x)) for x in t[9:13]]
    G = np.eye(4); G[:3, 0] = bx; G[:3, 1] = by; G[:3, 2] = bz; G[:3, 3] = org
    B[n] = dict(q=q, o=o, G=G)
h = [l.split() for l in open('/tmp/hand_verts.txt')]
VB = np.array([x[0] for x in h]); VP = np.array([[float(y) for y in x[1:]] for x in h])
LOCAL = {}
for n in B:
    k = VB == n
    if k.sum() > 20: LOCAL[n] = np.linalg.inv(B[n]['G']) @ np.c_[VP[k], np.ones(k.sum())].T
def load_sdf(path):
    d = np.load(path); return RGI((d['xs'], d['ys'], d['zs']), d['sdf'], bounds_error=False, fill_value=0.3)
def local_mat(n, deg):
    b = B[n]; R = Rot.from_quat(b['q']) * Rot.from_euler('YXZ', [deg[1], deg[0], deg[2]], degrees=True)
    L = np.eye(4); L[:3, :3] = R.as_matrix(); L[:3, 3] = b['o']; return L
def chain_G(prefix, pose, root):
    G = root; out = {}
    for j in ('01', '02', '03'):
        n = f'{prefix}_{j}.{SIDE}'; G = G @ local_mat(n, pose.get(f'{prefix}_{j}', (0, 0, 0))); out[n] = G
    return out
def seg_verts(Gs): return {n: (Gs[n] @ LOCAL[n])[:3].T for n in Gs if n in LOCAL}
