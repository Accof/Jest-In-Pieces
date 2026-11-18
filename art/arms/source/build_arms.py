# Build rigged LEFT and RIGHT first-person arms from the Tripo left arm.
#   blender-as-module:  python3 build_arms.py
# Source:  /tmp/arm/arm_src.glb  (never modified)
# Output:  /tmp/arm/out/arms.blend, arm_L.glb, arm_R.glb
#
# Model space of the source (glTF, Y up): the arm lies along +X, hand at +X,
# a LEFT hand with the palm toward +n1 = (0, .87, .49), thumb on the -Z side.
# Everything is computed in that space, then converted to Blender (x, -z, y)
# and scaled to metres (S: the hand, wrist to middle fingertip, ~19 cm).
import bpy, bmesh, json, math
import numpy as np
from mathutils import Vector, Matrix

SRC = '/tmp/arm/arm_src.glb'
OUT = '/tmp/arm/out'
S = 0.56
WRIST_X = 0.10
WRIST_C = np.array([0.10, 0.23, -0.005])
ELBOW_C = np.array([-0.44, 0.43, 0.03])
PALM_N = np.array([0.0, 0.87, 0.49]); PALM_N /= np.linalg.norm(PALM_N)
TRACKS = json.load(open('/tmp/arm/tracks.json'))
import os; os.makedirs(OUT, exist_ok=True)


def to_bl(p):           # model -> Blender, metres
    return Vector((p[0] * S, -p[2] * S, p[1] * S))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = src
src.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o)
me = src.data
# weld the UV-seam duplicates (UVs live on the loops, so the seams survive), drop the debris
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
bm.faces.ensure_lookup_table()
seen = set(); debris = []
for f in bm.faces:
    if f in seen: continue
    stack = [f]; group = []; seen.add(f)
    while stack:
        g = stack.pop(); group.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen: seen.add(h); stack.append(h)
    if len(group) < 500: debris += group
bmesh.ops.delete(bm, geom=debris, context='FACES')
bm.to_mesh(me); bm.free()
print('mesh after clean', len(me.vertices), 'verts', len(me.polygons), 'faces')

# model-space vertex positions
N = len(me.vertices)
co = np.zeros(N * 3); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
V = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)          # Blender -> model

# ---- digit chains ------------------------------------------------------------------------
def smooth_poly(pts, k=3):
    pts = np.array(pts); out = pts.copy()
    for i in range(len(pts)):
        a, b = max(0, i - k), min(len(pts), i + k + 1); out[i] = pts[a:b].mean(0)
    return out

chains = {}
for name in ['index', 'middle', 'ring', 'little', 'thumb']:
    t = smooth_poly(TRACKS[name])
    d_end = t[-1] - t[-4]; d_end /= np.linalg.norm(d_end)
    # extend to the real tip: the farthest vertex along the end direction within the finger's tube
    rel = V - t[-1]; along = rel @ d_end; lat = np.linalg.norm(rel - np.outer(along, d_end), axis=1)
    cand = (along > 0) & (lat < 0.03)
    tip = t[-1] + d_end * (along[cand].max() if cand.any() else 0.0)
    web = t[0]
    d0 = t[min(4, len(t) - 1)] - t[0]; d0 /= np.linalg.norm(d0)
    if name != 'thumb':
        L = np.linalg.norm(tip - web) + 0.0
        # arc length along the track, then the tip
        F = L / 0.88                                      # MCP to tip
        mcp = web - d0 * 0.12 * F
        poly = np.vstack([mcp, t, tip])
        seg = np.linalg.norm(np.diff(poly, axis=0), axis=1); arc = np.concatenate([[0], np.cumsum(seg)])
        F = arc[-1]
        cut = [0.0, F / 2.08, F * (1 + 0.63) / 2.08, F]  # proximal : middle : distal = 1 : .63 : .45
    else:
        # thumb: metacarpal from the CMC (at the wrist, on the thumb side) to where it leaves the hand
        sl = V[np.abs(V[:, 0] - 0.17) < 0.008]; cen = sl.mean(0)
        to_th = web - cen; to_th[0] = 0; to_th /= np.linalg.norm(to_th)
        ext = (sl - cen) @ to_th
        cmc = cen + to_th * ext.max() * 0.45
        mcp = web
        poly = np.vstack([cmc, t, tip])
        seg = np.linalg.norm(np.diff(poly, axis=0), axis=1); arc = np.concatenate([[0], np.cumsum(seg)])
        meta = np.linalg.norm(mcp - cmc); F = arc[-1]
        cut = [0.0, meta, meta + (F - meta) * 0.56, F]
    joints = [np.array([np.interp(c, arc, poly[:, k]) for k in range(3)]) for c in cut]
    chains[name] = dict(poly=poly, arc=arc, cut=cut, joints=joints, web_s=np.interp(0, [0], [0]))
    # where the web is along the chain (arc length of the track's first point)
    chains[name]['web_s'] = arc[1]
    print(name, 'joints', [np.round(j, 3).tolist() for j in joints])

# ---- projection of every vertex onto every chain -----------------------------------------
def project(poly, arc, pts):
    best_d = np.full(len(pts), 1e9); best_s = np.zeros(len(pts))
    for i in range(len(poly) - 1):
        a, b = poly[i], poly[i + 1]; ab = b - a; l2 = ab @ ab
        t = np.clip(((pts - a) @ ab) / l2, 0, 1)
        q = a + np.outer(t, ab); d = np.linalg.norm(pts - q, axis=1)
        m = d < best_d; best_d[m] = d[m]; best_s[m] = arc[i] + t[m] * math.sqrt(l2)
    return best_d, best_s

proj = {n: project(c['poly'], c['arc'], V) for n, c in chains.items()}
names = ['thumb', 'index', 'middle', 'ring', 'little']
D = np.stack([proj[n][0] for n in names], 1)
Sarc = np.stack([proj[n][1] for n in names], 1)
nearest = D.argmin(1)

# a vertex belongs to a digit's free part if it is past that digit's web
web = np.array([chains[n]['web_s'] for n in names])
beyond = Sarc[np.arange(N), nearest] > web[nearest] + 0.004
free = beyond & (D[np.arange(N), nearest] < 0.045) & (V[:, 0] > 0.2)

# ---- the strands between fingertips: faces joining two different free digits ----------
bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
# how far a vertex sits from its own digit's axis compared with the next digit's: a finger's
# own surface is ~0.6 at most; strands and their stubs sit out in the gap (near 1)
Ds = np.sort(D, 1); gap_ratio = Ds[:, 0] / np.maximum(Ds[:, 1], 1e-6)
strand = []
for f in bm.faces:
    ids = [v.index for v in f.verts]
    if not all(free[i] for i in ids):
        continue
    if len({int(nearest[i]) for i in ids}) > 1 or min(gap_ratio[i] for i in ids) > 0.8:
        strand.append(f)
print('strand faces between digits:', len(strand))
bmesh.ops.delete(bm, geom=strand, context='FACES')
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context='VERTS')
# anything left hanging on its own (bits of strand), then patch the small holes they leave
bm.faces.ensure_lookup_table(); seen = set(); bits = []
for f in bm.faces:
    if f in seen: continue
    stack = [f]; group = []; seen.add(f)
    while stack:
        g = stack.pop(); group.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen: seen.add(h); stack.append(h)
    if len(group) < 200: bits += group
bmesh.ops.delete(bm, geom=bits, context='FACES')
holes = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=40)
bmesh.ops.triangulate(bm, faces=holes['faces'])
print('stray bits removed', len(bits), 'holes filled', len(holes['faces']), 'boundary edges left', sum(1 for e in bm.edges if e.is_boundary))
bm.to_mesh(me); bm.free()

# recompute after the deletion
N = len(me.vertices)
co = np.zeros(N * 3); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
V = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)
proj = {n: project(c['poly'], c['arc'], V) for n, c in chains.items()}
D = np.stack([proj[n][0] for n in names], 1)
Sarc = np.stack([proj[n][1] for n in names], 1)
nearest = D.argmin(1)

# relabel free digit parts by connectivity: each connected free region takes its majority digit
bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
beyond = Sarc[np.arange(N), nearest] > web[nearest] + 0.004
free = beyond & (D[np.arange(N), nearest] < 0.045) & (V[:, 0] > 0.2)
label = nearest.copy(); seen = np.zeros(N, bool)
for v0 in range(N):
    if not free[v0] or seen[v0]: continue
    stack = [v0]; comp = []; seen[v0] = True
    while stack:
        i = stack.pop(); comp.append(i)
        for e in bm.verts[i].link_edges:
            j = e.other_vert(bm.verts[i]).index
            if free[j] and not seen[j]: seen[j] = True; stack.append(j)
    maj = np.bincount(nearest[comp], minlength=5).argmax()
    label[comp] = maj
bm.free()

# ---- weights --------------------------------------------------------------------------------
W = {}
def add(name, w):
    W[name] = W.get(name, 0) + w

b_j = 0.010     # half-width of the blend at a finger joint (model units, ~5.6 mm)
hand_side = smoothstep(WRIST_X - 0.03, WRIST_X + 0.03, V[:, 0])
add('forearm', 1.0 - hand_side)
hand_w = hand_side.copy()
for k, n in enumerate(names):
    c = chains[n]; d = D[:, k]; s = Sarc[:, k]; cut = c['cut']
    mine = (label == k)
    if n == 'thumb':
        # thenar: the metacarpal pulls the flesh round it inside the palm too, falling off with distance
        reach = (1.0 - smoothstep(0.03, 0.055, d)) * (V[:, 0] > WRIST_X)
        # but never steal a finger's own vertices
        reach = np.where(free & (label != k), 0.0, reach)
        reach = np.where(mine & free, 1.0, reach)
        meta = reach * (1.0 - smoothstep(cut[1] - b_j, cut[1] + b_j, s))
        prox = reach * smoothstep(cut[1] - b_j, cut[1] + b_j, s) * (1.0 - smoothstep(cut[2] - b_j, cut[2] + b_j, s))
        dist = reach * smoothstep(cut[2] - b_j, cut[2] + b_j, s)
        reach_tot = meta + prox + dist
        add('thumb_01', meta * hand_side); add('thumb_02', prox * hand_side); add('thumb_03', dist * hand_side)
        hand_w = hand_w - reach_tot * hand_side
    else:
        # the knuckle: the proximal bone takes over from the hand across the MCP
        lateral = (1.0 - smoothstep(0.035, 0.05, d))
        own = np.where(free, (label == k).astype(float), lateral * (nearest == k))
        start = smoothstep(cut[0] - 0.012, cut[0] + 0.022, s)
        f1 = own * start * (1.0 - smoothstep(cut[1] - b_j, cut[1] + b_j, s))
        f2 = own * start * smoothstep(cut[1] - b_j, cut[1] + b_j, s) * (1.0 - smoothstep(cut[2] - b_j, cut[2] + b_j, s))
        f3 = own * start * smoothstep(cut[2] - b_j, cut[2] + b_j, s)
        tot = f1 + f2 + f3
        add(f'{n}_01', f1 * hand_side); add(f'{n}_02', f2 * hand_side); add(f'{n}_03', f3 * hand_side)
        hand_w = hand_w - tot * hand_side
add('hand', np.clip(hand_w, 0.0, None))
tot = sum(W.values()); tot[tot < 1e-6] = 1.0
for k in W: W[k] = W[k] / tot

# ---- build an armature + a skinned mesh for one side --------------------------------------------
BONES = [('forearm', None), ('hand', 'forearm'),
         ('thumb_01', 'hand'), ('thumb_02', 'thumb_01'), ('thumb_03', 'thumb_02')]
for n in ['index', 'middle', 'ring', 'little']:
    BONES += [(f'{n}_01', 'hand'), (f'{n}_02', f'{n}_01'), (f'{n}_03', f'{n}_02')]

def bone_points(mirror):
    m = np.array([1, 1, -1.0]) if mirror else np.ones(3)
    pts = {'forearm': (ELBOW_C, WRIST_C), 'hand': (WRIST_C, chains['middle']['joints'][0])}
    for n in names:
        j = chains[n]['joints']
        for i in range(3):
            pts[f'{n}_0{i + 1}'] = (j[i], j[i + 1])
    return {k: (a * m, b * m) for k, (a, b) in pts.items()}, m

def build_side(side):
    mirror = side == 'R'
    pts, m = bone_points(mirror)
    palm = PALM_N * m
    palm_centre = (np.mean([chains[n]['joints'][0] for n in ['index', 'middle', 'ring', 'little']], 0) + WRIST_C) * 0.5 * m
    arm_data = bpy.data.armatures.new(f'ArmRig_{side}')
    rig = bpy.data.objects.new(f'ArmRig_{side}', arm_data)
    bpy.context.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    for name, parent in BONES:
        a, b = pts[name]
        e = eb.new(f'{name}.{side}')
        e.head = to_bl(a); e.tail = to_bl(b)
        if name.startswith('thumb'):
            # the thumb curls across toward the palm centre
            mid = (a + b) * 0.5; up = palm_centre - mid
            dvec = (b - a) / np.linalg.norm(b - a); up = up - dvec * (up @ dvec)
            e.align_roll(to_bl(up / np.linalg.norm(up)) / S)
        else:
            e.align_roll(to_bl(palm) / S)                 # local +Z toward the palm: +X rotation curls
        if parent:
            e.parent = eb[f'{parent}.{side}']
            e.use_connect = (name not in ('thumb_01',) and not name.endswith('_01') and name != 'hand') or name == 'hand'
    bpy.ops.object.mode_set(mode='OBJECT')
    # the mesh
    ob = src.copy(); ob.data = src.data.copy(); ob.name = f'Arm_{side}'; ob.data.name = f'Arm_{side}'
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for v in bm.verts:
        mv = Vector((v.co.x, v.co.z, -v.co.y)) * S         # Blender -> model -> scale
        if mirror: mv.z = -mv.z
        v.co = Vector((mv.x, -mv.z, mv.y))
    if mirror:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)       # mirrored: put the winding (and normals) back outward
    bm.to_mesh(ob.data); bm.free()
    if ob.data.has_custom_normals:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in ob.data.polygons: p.use_smooth = True
    for name in W:
        vg = ob.vertex_groups.new(name=f'{name}.{side}')
        w = W[name]
        for i in np.nonzero(w > 0.002)[0]:
            vg.add([int(i)], float(w[i]), 'REPLACE')
    mod = ob.modifiers.new('Armature', 'ARMATURE'); mod.object = rig
    ob.parent = rig
    return rig, ob

rigL, armL = build_side('L')
rigR, armR = build_side('R')
bpy.data.objects.remove(src)
rigR.location.y = -0.0          # both at the origin; posed and placed in Godot
bpy.ops.wm.save_as_mainfile(filepath=f'{OUT}/arms.blend')
print('BONES', [b.name for b in rigL.data.bones])
