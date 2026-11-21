"""Measure the same things on the Mixamo reference clips and on our soldier.
ref dump: /tmp/anim_ref_dump.json (tools/anim_ref/dump_ref.gd); ours: /tmp/anim_ours.json
(scenes/test_anim_ref.tscn). Units: metres, degrees, seconds."""
import json, sys, numpy as np
from scipy.spatial.transform import Rotation as R

P = 'mixamorig_'


def P3(f, b):
    return np.array(f[P + b][0:3])


def ang(a, b, c):
    u = a - b; v = c - b
    return np.degrees(np.arccos(np.clip(u @ v / np.linalg.norm(u) / np.linalg.norm(v), -1, 1)))


def yaw_of(f, b):
    x, y, z, w = f[P + b][7:11]
    fw = R.from_quat([x, y, z, w]).apply([0, 0, 1])
    return np.degrees(np.arctan2(fw[0], fw[2]))


def measure(F, move=np.zeros(3), hip_rest=1.043):
    n = len(F); t = np.arange(n) / 30.0
    hips = np.array([P3(f, 'Hips') for f in F])
    o = {}
    o['hip_h'] = hips[:, 1] / hip_rest                       # hip height, fraction of standing
    tr = np.polyfit(t, hips, 1)
    res = hips - (np.outer(t, tr[0]) + tr[1])
    o['hip_osc'] = res.max(0) - res.min(0)                    # x side-sway, y bob, z surge
    tor = np.array([P3(f, 'Spine2') - P3(f, 'Hips') for f in F])
    o['lean'] = np.degrees(np.arctan2(tor[:, 2], tor[:, 1]))
    o['side_lean'] = np.degrees(np.arctan2(tor[:, 0], tor[:, 1]))
    o['hip_yaw'] = np.array([yaw_of(f, 'Hips') for f in F])
    o['chest_yaw'] = np.array([yaw_of(f, 'Spine2') for f in F])
    for s in ['Left', 'Right']:
        hp = np.array([P3(f, s + 'UpLeg') for f in F]); kn = np.array([P3(f, s + 'Leg') for f in F]); an = np.array([P3(f, s + 'Foot') for f in F])
        o[s + 'knee'] = np.array([180 - ang(hp[i], kn[i], an[i]) for i in range(n)])
        th = kn - hp
        o[s + 'hip'] = np.degrees(np.arctan2(th[:, 2], -th[:, 1]))
        ft = an + np.outer(t, move)                             # in the world
        if ('world_' + s + 'Foot') in F[0]:
            ft = np.array([f['world_' + s + 'Foot'] for f in F])
        o[s + 'footy'] = an[:, 1] - an[:, 1].min()
        v = np.linalg.norm(np.diff(ft[:, [0, 2]], axis=0), axis=1) * 30
        low = (an[1:, 1] - an[:, 1].min()) < 0.02
        o[s + 'slide'] = v[low].mean() if low.any() else float('nan')
        o[s + 'lift'] = an[:, 1].max() - an[:, 1].min()
    # step timing: frames where a foot is planted
    return o


def r(a):
    return '%5.0f..%-4.0f' % (np.min(a), np.max(a))


def show(tag, o, speed):
    print('  %-6s hips %.2f..%.2f of standing; sway %.3f bob %.3f surge %.3f | lean %s side %s | yaw hips %s chest %s' % (
        tag, o['hip_h'].min(), o['hip_h'].max(), o['hip_osc'][0], o['hip_osc'][1], o['hip_osc'][2], r(o['lean']), r(o['side_lean']), r(o['hip_yaw']), r(o['chest_yaw'])))
    for s in ['Left', 'Right']:
        print('         %-5s knee %s hip %s foot lift %.2f, planted foot slides %.2f m/s (body %.2f)' % (s, r(o[s + 'knee']), r(o[s + 'hip']), o[s + 'lift'], o[s + 'slide'], speed))


ref = json.load(open('/tmp/anim_ref_dump.json'))
ours = json.load(open(sys.argv[1] if len(sys.argv) > 1 else '/tmp/anim_ours.json'))
pairs = [
    ('Crouch_Idle.fbx', 'crouch_idle', None),
    ('Walk_Crouching_Forward.fbx', 'crouch_walk', None),
    ('Crouched_Run.fbx', 'crouch_run', None),
    ('Strafe.fbx', 'strafe_left', None),
    ('Firing_Rifle_1.fbx', 'aim', None),
    ('Turning_Right_90_Degrees.fbx', 'turn_right', None),
    ('Turning_Right_90_Degrees.fbx', 'turn_slow', None),
    ('Rifle_Walk_1.fbx', 'walk_slow', None), ('Rifle_Walk_1.fbx', 'walk', None), ('Rifle_Run_1.fbx', 'run', None), ('Backwards_Rifle_Walk.fbx', 'walk_back', None),
    (None, 'stand', None), (None, 'strafe_right', None), (None, 'diag_fl', None), (None, 'diag_br', None),
]
for rn, on, _ in pairs:
    print('==', rn or '(no reference)', '<->', on)
    if rn:
        F = ref[rn]['frames']
        disp = (np.array(F[-1][P + 'Hips'][0:3]) - np.array(F[0][P + 'Hips'][0:3])) / ref[rn]['length']
        show('ref', measure(F), np.linalg.norm(disp[[0, 2]]))
    if on in ours:
        st = ours[on]
        mv = {'crouch_walk': [0, 0, 1.8], 'crouch_run': [0, 0, 2.7], 'walk_slow': [0, 0, 1.4], 'walk': [0, 0, 3.0], 'run': [0, 0, 5.4], 'strafe_left': [1, 0, 0], 'strafe_right': [-1, 0, 0], 'walk_back': [0, 0, -1.2], 'diag_fl': [1.4, 0, 1.4], 'diag_br': [-1.0, 0, -1.0]}.get(on, [0, 0, 0])
        show('ours', measure(st['frames'], np.array(mv), 0.97), np.linalg.norm(mv))


def phase_rules(F, tag):
    """Which way the hips sway and the pelvis turns, relative to the legs:
    + sway = hips over the planted (lower) foot; + yaw = pelvis turned toward the leg in front."""
    n = len(F)
    hips = np.array([P3(f, 'Hips') for f in F]); lf = np.array([P3(f, 'LeftFoot') for f in F]); rf = np.array([P3(f, 'RightFoot') for f in F])
    lk = np.array([P3(f, 'LeftLeg') for f in F]); rk = np.array([P3(f, 'RightLeg') for f in F])
    t = np.arange(n)
    hx = hips[:, 0] - np.polyval(np.polyfit(t, hips[:, 0], 1), t)
    planted_left = (lf[:, 1] < rf[:, 1]).astype(float) * 2 - 1        # +1 left foot lower
    sway = np.corrcoef(hx, planted_left)[0, 1]                         # left is +x
    yaw = np.array([yaw_of(f, 'Hips') for f in F]); yaw = yaw - yaw.mean()
    left_ahead = (lk[:, 2] - rk[:, 2])
    turn = np.corrcoef(-yaw, left_ahead)[0, 1]   # pelvis yawing right (-) as the left knee comes forward
    print('  %-6s sway-to-stance-foot corr %+.2f   pelvis-turns-away-from-forward-knee corr %+.2f' % (tag, sway, turn))


print('== phase rules')
for rn in ['Walk_Crouching_Forward.fbx', 'Crouched_Run.fbx']:
    phase_rules(ref[rn]['frames'], rn[:10])
for on in ['walk', 'run', 'crouch_walk']:
    if on in ours:
        phase_rules(ours[on]['frames'], on)
