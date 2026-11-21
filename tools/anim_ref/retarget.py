"""Retarget the Mixamo reference clips onto the soldiers' skeleton.

Input: /tmp/anim_ref_dump.json, written by tools/anim_ref/dump_ref.gd (every
bone's skeleton-space transform per frame, at 30 fps, plus the rest pose).
Output: art/anim_ref/soldier_clips.json, read by scripts/clown/soldier_clips.gd.

Retargeting is by skeleton-space rotation from the rest pose: for each of our
bones, D(t) = G_mixamo(t) * G_mixamo_rest^-1 (both rigs rest in a T-pose facing
+Z with the left side at +X, so a bone's change from rest carries straight
over); at run time our bone's skeleton-space rotation becomes D(t) * G_ours_rest.
Arms are left out: our soldiers' arms are on two-bone IK to the rifle.

Hip offsets are scaled by hip height (ours 0.97 m, Mixamo's 1.043 m). Root
motion is taken out: a cycle keeps its sway and surge but not its travel
(the travel per cycle is kept as the stride length, so the game can drive the
cycle from the soldier's real speed and the planted foot stays planted).
"""
import json, numpy as np
from scipy.spatial.transform import Rotation as R

SRC = '/tmp/anim_ref_dump.json'
OUT = 'art/anim_ref/soldier_clips.json'
P = 'mixamorig_'
SCALE = 0.97 / 1.0427
MAP = {
    'Hips': 'Hips', 'Spine': 'Spine1', 'Chest': 'Spine2', 'Neck': 'Neck', 'Head': 'Head',
    'LeftShoulder': 'LeftShoulder', 'RightShoulder': 'RightShoulder',
    'LeftUpperLeg': 'LeftUpLeg', 'LeftLowerLeg': 'LeftLeg', 'LeftFoot': 'LeftFoot', 'LeftToes': 'LeftToeBase',
    'RightUpperLeg': 'RightUpLeg', 'RightLowerLeg': 'RightLeg', 'RightFoot': 'RightFoot', 'RightToes': 'RightToeBase',
}
UPPER = ['Hips', 'Spine', 'Chest', 'Neck', 'Head', 'LeftShoulder', 'RightShoulder']

d = json.load(open(SRC))


def rest_globals(v):
    names = v['bones']; rest = v['rest']; G = {}
    for n in names:
        p, ox, oy, oz, qx, qy, qz, qw = rest[n]
        lr, lp = R.from_quat([qx, qy, qz, qw]), np.array([ox, oy, oz])
        if p < 0:
            G[n] = (lr, lp)
        else:
            pr, pp = G[names[p]]
            G[n] = (pr * lr, pp + pr.apply(lp))
    return G


def load(name):
    v = d[name]
    G = rest_globals(v)
    F = v['frames']
    n = len(F)
    deltas = {}
    for ours, mx in MAP.items():
        rq = G[P + mx][0]
        qs = R.from_quat([F[i][P + mx][7:11] for i in range(n)])
        deltas[ours] = qs * rq.inv()
    hips = np.array([F[i][P + 'Hips'][0:3] for i in range(n)])
    off = (hips - G[P + 'Hips'][1]) * SCALE
    feet = {s: np.array([F[i][P + s + 'Foot'][0:3] for i in range(n)]) * SCALE for s in ['Left', 'Right']}
    yaw = np.unwrap([np.arctan2(*(deltas['Hips'][i].apply([0, 0, 1])[[0, 2]])) for i in range(n)])
    return {'deltas': deltas, 'off': off, 'feet': feet, 'n': n, 'yaw': np.array(yaw)}


def mirror_rot(r):
    q = r.as_quat()                                   # x y z w; mirror across the YZ plane
    return R.from_quat(np.stack([q[:, 0], -q[:, 1], -q[:, 2], q[:, 3]], axis=1))


def mirror(c):
    m = {'deltas': {}, 'off': c['off'] * np.array([-1, 1, 1]), 'n': c['n'],
         'feet': {'Left': c['feet']['Right'] * np.array([-1, 1, 1]), 'Right': c['feet']['Left'] * np.array([-1, 1, 1])}}
    for b, r in c['deltas'].items():
        mb = b.replace('Left', 'Tmp').replace('Right', 'Left').replace('Tmp', 'Right')
        m['deltas'][mb] = mirror_rot(r)
    for k in c:
        if k not in m:
            m[k] = c[k]
    if 'yaw' in c:
        m['yaw'] = -c['yaw']
    return m


def rotate(c, i0):
    c = dict(c)
    c['deltas'] = {b: R.from_quat(np.roll(r.as_quat(), -i0, axis=0)) for b, r in c['deltas'].items()}
    c['off'] = np.roll(c['off'], -i0, axis=0)
    c['feet'] = {s: np.roll(f, -i0, axis=0) for s, f in c['feet'].items()}
    return c


def cycle(name, mirror_it=False):
    c = load(name)
    n = c['n']
    # the last frame repeats the first: drop it
    for k in ['off']:
        c[k] = c[k][:-1]
    c['deltas'] = {b: r[:-1] for b, r in c['deltas'].items()}
    c['feet'] = {s: f[:-1] for s, f in c['feet'].items()}
    n -= 1
    c['n'] = n
    T = n / 30.0
    travel = (load(name)['off'][-1] - load(name)['off'][0])
    v = travel / T
    t = np.arange(n) / 30.0
    off = c['off'] - np.outer(t, [v[0], 0, v[2]])
    off[:, [0, 2]] -= off[:, [0, 2]].mean(0)
    c['off'] = off
    # start the cycle where the left foot is set down (lowest and stopped)
    fl = c['feet']['Left'] + np.outer(t, [0, 0, 0])
    world = c['feet']['Left']
    vy = np.diff(np.concatenate([world[:, 1], world[:1, 1]]))
    low = world[:, 1] < world[:, 1].min() + 0.012
    i0 = 0
    for i in range(n):
        if low[i] and not low[i - 1]:
            i0 = i
            break
    c = rotate(c, i0)
    c['stride'] = float(np.linalg.norm(travel[[0, 2]]))
    c['dir'] = (travel / max(np.linalg.norm(travel), 1e-6)).tolist()
    c['loop'] = True
    if mirror_it:
        c = mirror(c)
        c['dir'] = [-c['dir'][0], c['dir'][1], c['dir'][2]]
    return c


def oneshot(name, start=0, end=None, keep_xz=False, additive=False):
    c = load(name)
    s = slice(start, end)
    c['deltas'] = {b: r[s] for b, r in c['deltas'].items()}
    c['off'] = c['off'][s].copy()
    c['n'] = len(c['off'])
    if not keep_xz:
        c['off'][:, [0, 2]] = 0.0
    else:
        t = np.arange(c['n'])
        tr = np.polyfit(t, c['off'][:, [0, 2]], 1)
        c['off'][:, [0, 2]] -= np.outer(t, tr[0]) + tr[1]
    if additive:
        # relative to its own first frame, for the upper body: layered over whatever pose he is in
        base = {b: r[0] for b, r in c['deltas'].items()}
        c['deltas'] = {b: r * base[b].inv() for b, r in c['deltas'].items() if b in UPPER}
        c['off'] = c['off'] - c['off'][0]
    c['loop'] = False
    c['additive'] = additive
    return c


def turn(name, mirror_it=False):
    """A turn on the spot: the hips' yaw is what the game's own turning does,
    so it is taken out of every bone (the feet then stay put on the ground
    while the root turns) and kept as the curve to drive the clip by."""
    c = load(name)
    yaw = c['yaw'] - c['yaw'][0]
    # smooth (the hips wobble about the turn): a short moving average
    k = 5
    ys = np.convolve(np.pad(yaw, (k, k), mode='edge'), np.ones(2 * k + 1) / (2 * k + 1), mode='same')[k:-k]
    ys = np.maximum.accumulate(ys * np.sign(ys[-1])) * np.sign(ys[-1])  # monotonic
    n = c['n']
    for b in list(c['deltas']):
        c['deltas'][b] = R.from_rotvec(np.outer(-ys, [0, 1, 0])) * c['deltas'][b]
    off = R.from_rotvec(np.outer(-ys, [0, 1, 0])).apply(c['off'])
    off[:, [0, 2]] -= off[0, [0, 2]]
    c['off'] = off
    c['turn'] = ys.tolist()
    c['loop'] = False
    if mirror_it:
        c = mirror(c)
        c['turn'] = [-x for x in ys.tolist()]
    return c


def pack(c):
    out = {'fps': 30, 'frames': int(c['n']), 'loop': bool(c.get('loop', False)), 'additive': bool(c.get('additive', False)),
           'bones': {}, 'off': [round(float(x), 4) for x in np.asarray(c['off']).reshape(-1)]}
    for b, r in c['deltas'].items():
        q = r.as_quat()
        q[q[:, 3] < 0] *= -1                          # keep w positive (shorter way round)
        out['bones'][b] = [round(float(x), 4) for x in q.reshape(-1)]
    for k in ['stride', 'dir', 'turn']:
        if k in c:
            v = c[k]
            out[k] = [round(float(x), 4) for x in v] if isinstance(v, list) else round(float(v), 4)
    return out


def hip_start_drop(name, thresh):
    c = load(name)
    h = c['off'][:, 1]
    for i in range(len(h)):
        if h[i] < h[0] - thresh:
            return max(0, i - 6)
    return 0


clips = {
    'kneel': pack(oneshot('Crouch_Idle.fbx', keep_xz=True) | {'loop': True}),
    'crouch_walk': pack(cycle('Walk_Crouching_Forward.fbx')),
    'crouch_run': pack(cycle('Crouched_Run.fbx')),
    'strafe_left': pack(cycle('Strafe.fbx')),
    'raise': pack(oneshot('Rifle_Down_To_Aim.fbx')),
    'recoil': pack(oneshot('Firing_Rifle_1.fbx', additive=True)),
    'turn_right': pack(turn('Turning_Right_90_Degrees.fbx')),
    'turn_left': pack(turn('Turning_Right_90_Degrees.fbx', mirror_it=True)),
    'crouch_turn_right': pack(turn('Rifle_Crouch_Turn.fbx')),
    'crouch_turn_left': pack(turn('Rifle_Crouch_Turn.fbx', mirror_it=True)),
    'kneel_hit': pack(oneshot('Hit_Reaction.fbx', additive=True)),
    'cower': pack(oneshot('Rifle_Shielding_Face.fbx', start=hip_start_drop('Rifle_Shielding_Face.fbx', 0.03))),
}
json.dump(clips, open(OUT, 'w'), separators=(',', ':'))
for k, v in clips.items():
    print('%-18s %3d frames%s%s%s' % (k, v['frames'], ' loop' if v['loop'] else '', ' stride %.2f m' % v['stride'] if 'stride' in v else '',
          ' turn %.0f deg' % np.degrees(v['turn'][-1]) if 'turn' in v else ''))
import os
print('size', os.path.getsize(OUT))
