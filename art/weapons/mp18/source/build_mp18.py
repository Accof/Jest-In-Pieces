# Build the MP 18 used in the game from the untouched Tripo GLB.
# Blender 5.x (bpy as a Python module):
#   python3 build_mp18.py mp18_tripo_original.glb <out_dir>
# then copy <out_dir>/mp18.glb to art/weapons/mp18/.
#
# 1. align: the Tripo export lies turned ~133 deg about Z with the bore 3 deg nose-up;
#    turned so the bore runs along +X (muzzle +X, +Y the gun's left, +Z up), bore on y = 0
# 2. weld, drop debris
# 3. stock: the butt was a thin stub (half the depth of a real one); deepened
#    progressively toward the butt plate (top line kept) and 6% longer
# 4. drum: cut off where its neck leaves the magazine housing (a plane across the
#    housing's axis), both ends capped, its own object with the pivot on the cut,
#    so it can be drawn out of the housing sideways
# 5. scaled to metres (0.715 m per Tripo unit: 0.815 m overall, as the real gun)
# 6. charging handle: the Tripo stand-in block cut away; a long slot cut in the receiver's
#    right wall and the MP 18's bent hook handle riding in it
# 7. a stick magazine (20 rounds) for the same housing; the drum stays as an upgrade
import bpy, bmesh, sys, os, math, subprocess
import numpy as np
from mathutils import Vector, Matrix

SRC = sys.argv[-2]
OUT = sys.argv[-1]
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)
SCALE = 0.715
ALIGN = (Matrix.Translation((0, 0.0269, 0)) @ Matrix.Rotation(math.radians(3.03), 4, "Y")
         @ Matrix.Rotation(math.radians(-9.30), 4, "Z") @ Matrix.Rotation(math.radians(132.8), 4, "Z"))
# in aligned Tripo units
BUTT_X = -0.36          # behind this the butt is reshaped
BUTT_DEEPEN = 0.75      # extra depth at the butt plate (x 1.75)
BUTT_LONGER = 1.06
CUT_P = Vector((0.071, 0.172, 0.162)) - Vector((-0.49, 0.87, 0.0)).normalized() * 0.015   # on the housing's axis, at its mouth
CUT_N = Vector((-0.49, 0.87, 0.0)).normalized()  # the housing's axis, out toward the drum
BORE_Z = 0.1757
MUZZLE_X = 0.5916

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
gun = [o for o in bpy.data.objects if o.type == "MESH"][0]
gun.name = "Body"
bpy.ops.object.select_all(action="DESELECT"); gun.select_set(True); bpy.context.view_layer.objects.active = gun
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
gun.data.transform(ALIGN)
mat = gun.data.materials[0]

bm = bmesh.new(); bm.from_mesh(gun.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
bm.verts.ensure_lookup_table()
seen = set(); kill = []
for v in bm.verts:
    if v.index in seen: continue
    st = [v]; isl = []
    while st:
        x = st.pop()
        if x.index in seen: continue
        seen.add(x.index); isl.append(x); st.extend(e.other_vert(x) for e in x.link_edges)
    if len(isl) < 60: kill += isl
bmesh.ops.delete(bm, geom=kill, context="VERTS")
print("debris verts removed", len(kill))

# 3. the butt: its top line per slice, then deepen below it toward the plate
P = np.array([v.co for v in bm.verts])
butt = P[:, 0] < BUTT_X
xs = np.arange(P[butt, 0].min() - 0.01, BUTT_X + 0.011, 0.01)
tops = []
for x0 in xs:
    k = butt & (np.abs(P[:, 0] - x0) < 0.008)
    tops.append(P[k, 2].max() if k.any() else np.nan)
tops = np.array(tops); ok = ~np.isnan(tops)
xend = P[butt, 0].min()
n = 0
for v in bm.verts:
    x = v.co.x
    if x >= BUTT_X: continue
    t = min(1.0, (BUTT_X - x) / (BUTT_X - xend))
    top = float(np.interp(x, xs[ok], tops[ok]))
    if v.co.z < top:
        v.co.z = top - (top - v.co.z) * (1.0 + BUTT_DEEPEN * t * t)
    v.co.x = BUTT_X + (x - BUTT_X) * BUTT_LONGER
    n += 1
print("butt verts reshaped", n)

# 4. the drum: slice the housing/neck exactly on the plane first (a clean ring both sides)
near = [f for f in bm.faces if f.calc_center_median().y > 0.10 and (f.calc_center_median() - CUT_P).length < 0.12]
geom = list({v for f in near for v in f.verts}) + list({e for f in near for e in f.edges}) + near
bmesh.ops.bisect_plane(bm, geom=geom, plane_co=CUT_P, plane_no=CUT_N, dist=0.0001)
drum_faces = [f for f in bm.faces if f.calc_center_median().y > 0.12 and (f.calc_center_median() - CUT_P).dot(CUT_N) > 0.0]
print("drum faces", len(drum_faces))
uvl = bm.loops.layers.uv.active
nb = bmesh.new(); nuv = nb.loops.layers.uv.new("UVMap"); vmap = {}
for f in drum_faces:
    vs = []
    for v in f.verts:
        if v not in vmap: vmap[v] = nb.verts.new(v.co)
        vs.append(vmap[v])
    try:
        nf = nb.faces.new(vs)
    except ValueError:
        continue
    for la, lb in zip(f.loops, nf.loops): lb[nuv].uv = la[uvl].uv
bmesh.ops.delete(bm, geom=drum_faces, context="FACES")
dark = bpy.data.materials.new("BluedSteelDark")
dark.use_nodes = True
_b = dark.node_tree.nodes.get("Principled BSDF")
_b.inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
_b.inputs["Metallic"].default_value = 0.9
_b.inputs["Roughness"].default_value = 0.5
def cap(b, near, mat_index):
    edges = [e for e in b.edges if e.is_boundary and (e.verts[0].co - CUT_P).length < near and abs((e.verts[0].co - CUT_P).dot(CUT_N)) < 0.002]
    if edges:
        r = bmesh.ops.holes_fill(b, edges=edges, sides=400)
        t = bmesh.ops.triangulate(b, faces=r["faces"])
        for f in t["faces"]:
            f.material_index = mat_index
        return len(t["faces"])
    return 0
print("housing mouth capped:", cap(bm, 0.08, 1), "faces;", "drum neck capped:", cap(nb, 0.08, 1), "faces")
bm.to_mesh(gun.data); bm.free()
dme = bpy.data.meshes.new("Drum"); nb.to_mesh(dme); nb.free()
drum = bpy.data.objects.new("Drum", dme); bpy.context.scene.collection.objects.link(drum)
dme.materials.append(mat)
dme.materials.append(dark)
gun.data.materials.append(dark)
for o in (gun, drum):
    o.data.validate(verbose=False)

# 5. metres; pivots
S = Matrix.Scale(SCALE, 4)
gun.data.transform(S); drum.data.transform(S)
cut = CUT_P * SCALE
drum.data.transform(Matrix.Translation(-cut)); drum.location = cut

# 6. the charging handle (metres). The Tripo model had a block on the front right of
# the receiver standing in for one; it is cut away (the hole closed with the
# receiver's own texture) and the real thing built: a long slot along the right
# wall of the receiver just above the wood (exact plane slices, a dark channel
# behind it), and the MP 18's handle, a flat bar out of the slot that bends down
# into a hook, standing clear of the wood. At rest at the back (cocked, open bolt).
bm = bmesh.new(); bm.from_mesh(gun.data)
uvl = bm.loops.layers.uv.active
block = [f for f in bm.faces if 0.035 < f.calc_center_median().x < 0.085 and f.calc_center_median().y < -0.0465 and 0.100 < f.calc_center_median().z < 0.150]
bmesh.ops.delete(bm, geom=block, context="FACES")
edges = [e for e in bm.edges if e.is_boundary and 0.03 < e.verts[0].co.x < 0.09 and e.verts[0].co.y < -0.035 and 0.095 < e.verts[0].co.z < 0.155]
patch = bmesh.ops.holes_fill(bm, edges=edges, sides=600)["faces"] if edges else []
if patch:
    # a curved skin over the hole: poke a centre, subdivide, then wrap the new points onto
    # the receiver tube (axis along x through y 0, z 0.1256) at the rim's mean radius
    rim = {v.index for f in patch for v in f.verts}
    res = bmesh.ops.poke(bm, faces=patch)
    patch = res["faces"]; centre = res["verts"]
    AX = Vector((0, 0, 0.1256))
    rv = [v for f in patch for v in f.verts if v not in centre]
    R = sum(Vector((0, v.co.y, v.co.z - AX.z)).length for v in rv) / len(rv)
    for c in centre:
        r = Vector((0, c.co.y, c.co.z - AX.z))
        c.co = Vector((c.co.x, 0, AX.z)) + r.normalized() * R
    for f in patch: f.smooth = True
    bm.faces.index_update(); _pidx = {f.index for f in patch}
    pl = bm.faces.layers.int.new("patch")
    bm.faces.ensure_lookup_table()
    for i in _pidx: bm.faces[i][pl] = 1
    patch = [bm.faces[i] for i in _pidx]
    uvl = bm.loops.layers.uv.active
# one steel spot of the receiver's own texture, just behind the old block, for the whole patch
probe = Vector((0.015, -0.040, 0.142))
_img = [i for i in bpy.data.images if i.name == "Color"][0]
_W, _H = _img.size
_px = np.array(_img.pixels[:], dtype=np.float32).reshape(_H, _W, 4)
def _grey(uv):
    c = _px[min(_H - 1, int(uv.y * _H)), min(_W - 1, int(uv.x * _W)), :3]
    return c.max() - c.min() < 0.06 and 0.12 < c.mean() < 0.5
cands = sorted((f for f in bm.faces if f not in patch and f.calc_center_median().y < -0.03), key=lambda f: (f.calc_center_median() - probe).length)
src_f = next(f for f in cands if _grey(f.loops[0][uvl].uv))
steel_uv = src_f.loops[0][uvl].uv.copy()
print("patch steel from the face at", tuple(round(c, 3) for c in src_f.calc_center_median()))
# the patch gets the steel texture laid on by an affine fit (x, z -> u, v) from the
# receiver faces just behind it on the same UV island, so its grain carries on
near = [f for f in bm.faces if f not in patch and -0.005 < f.calc_center_median().x < 0.035 and f.calc_center_median().y < -0.03 and 0.105 < f.calc_center_median().z < 0.15]
near = [f for f in near if (f.loops[0][uvl].uv - steel_uv).length < 0.08]
A = np.array([[l.vert.co.x, l.vert.co.z, 1.0] for f in near for l in f.loops]); B = np.array([[l[uvl].uv.x, l[uvl].uv.y] for f in near for l in f.loops])
fit_ok = len(near) >= 6
if fit_ok:
    M, *_ = np.linalg.lstsq(A, B, rcond=None)
    err = np.abs(A @ M - B).max(); fit_ok = err < 0.02
    print("patch UV fit from", len(near), "faces, max error", round(float(err), 4))
for f in patch:
    for l in f.loops:
        if fit_ok:
            u, v = np.array([l.vert.co.x - 0.05, l.vert.co.z, 1.0]) @ M   # read the plain steel 5 cm behind
            l[uvl].uv = (float(u), float(v))
        else:
            l[uvl].uv = steel_uv
print("Tripo handle block removed:", len(block), "faces; patched with", len(patch), "faces")
SLOT_X = (-0.155, -0.030)
SLOT_Z = (0.1315, 0.1385)
SLOT_FLOOR = -0.031          # y of the channel's floor (inside the wall)
SLOT_LIP = -0.0405           # y the channel's walls come out to (just past the surface)
def region():
    return [f for f in bm.faces if f.calc_center_median().y < -0.025 and SLOT_X[0] - 0.01 < f.calc_center_median().x < SLOT_X[1] + 0.01
            and SLOT_Z[0] - 0.006 < f.calc_center_median().z < SLOT_Z[1] + 0.006]
for co, no in (((SLOT_X[0], 0, 0), (1, 0, 0)), ((SLOT_X[1], 0, 0), (1, 0, 0)), ((0, 0, SLOT_Z[0]), (0, 0, 1)), ((0, 0, SLOT_Z[1]), (0, 0, 1))):
    fs = region()
    geom = list({v for f in fs for v in f.verts}) + list({e for f in fs for e in f.edges}) + fs
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=0.00002)
hole = [f for f in bm.faces if f.calc_center_median().y < -0.025 and SLOT_X[0] < f.calc_center_median().x < SLOT_X[1] and SLOT_Z[0] < f.calc_center_median().z < SLOT_Z[1]]
bmesh.ops.delete(bm, geom=hole, context="FACES")
print("slot: receiver faces removed", len(hole))
x0, x1 = SLOT_X; z0, z1 = SLOT_Z; yf, yl = SLOT_FLOOR, SLOT_LIP
chan = []
for pts, want in ((((x0, yf, z0), (x1, yf, z0), (x1, yf, z1), (x0, yf, z1)), (0, -1, 0)),
                  (((x0, yf, z1), (x1, yf, z1), (x1, yl, z1), (x0, yl, z1)), (0, 0, -1)),
                  (((x0, yl, z0), (x1, yl, z0), (x1, yf, z0), (x0, yf, z0)), (0, 0, 1)),
                  (((x0, yl, z0), (x0, yf, z0), (x0, yf, z1), (x0, yl, z1)), (1, 0, 0)),
                  (((x1, yf, z0), (x1, yl, z0), (x1, yl, z1), (x1, yf, z1)), (-1, 0, 0))):
    f = bm.faces.new([bm.verts.new(p) for p in pts]); f.material_index = 1; f.smooth = False
    f.normal_update()
    if f.normal.dot(Vector(want)) < 0: f.normal_flip()
bm.to_mesh(gun.data); bm.free()

# the handle: a flat bar (6 x 3.5 mm) swept along its centre line, out of the slot
# and bending down into a hook; origin on the slot's centre line
def bezier(ps, n):
    out = []
    for i in range(n + 1):
        t = i / n; q = [Vector(p) for p in ps]
        while len(q) > 1: q = [q[k].lerp(q[k + 1], t) for k in range(len(q) - 1)]
        out.append(q[0])
    return out
path = [Vector((0, SLOT_FLOOR, 0)), Vector((0, -0.044, 0))] + bezier([(0, -0.044, 0), (0.0, -0.054, 0.0), (0.002, -0.056, -0.016), (0.011, -0.0555, -0.029)], 12)[1:]
hb = bmesh.new()
W, T = 0.0055, 0.0035
rings = []
for i, p in enumerate(path):
    tan = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
    side = Vector((1, 0, 0)); side = (side - tan * side.dot(tan)).normalized()
    nrm = tan.cross(side).normalized()
    w = W * (1.25 if i == len(path) - 1 else 1.0)          # the end of the hook a touch wider, as on the real one
    rings.append([hb.verts.new(p + side * sx * w / 2 + nrm * sy * T / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
for a_, b_ in zip(rings[:-1], rings[1:]):
    for k in range(4):
        hb.faces.new((a_[k], a_[(k + 1) % 4], b_[(k + 1) % 4], b_[k]))
hb.faces.new(list(reversed(rings[0]))); hb.faces.new(rings[-1])
bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
hme = bpy.data.meshes.new("Handle"); hb.to_mesh(hme); hb.free()
handle = bpy.data.objects.new("Handle", hme); bpy.context.scene.collection.objects.link(handle)
steel = bpy.data.materials.new("HandleSteel"); steel.use_nodes = True
_h = steel.node_tree.nodes.get("Principled BSDF")
_h.inputs["Base Color"].default_value = (0.13, 0.13, 0.14, 1)
_h.inputs["Metallic"].default_value = 0.9
_h.inputs["Roughness"].default_value = 0.45
hme.materials.append(steel)
handle.location = Vector((x0 + 0.006, 0.0, (z0 + z1) / 2))
print("handle at", tuple(round(c, 4) for c in handle.location), "travel", round(x1 - x0 - 0.012, 4), "grab point (hook bend, from origin)", tuple(round(c, 4) for c in path[len(path) // 2 + 1]))

# 7. a 20-round stick magazine for the same housing (the drum becomes an upgrade):
# a slim steel box along the housing's axis, a floor plate on its outer end, two
# pressed ribs; its node sits on the same cut as the drum's
# the housing's real axis, measured: slice the body square to the cut's normal every
# 4 mm into the housing, take each slice's middle, and fit a line through them (it
# tips down and back ~6 deg from the cut's normal, which was set level)
_mids = []
for _d in [-0.004 * i for i in range(1, 13)]:
    _b = bmesh.new(); _b.from_mesh(gun.data); _p = cut + CUT_N * _d
    _r = bmesh.ops.bisect_plane(_b, geom=_b.verts[:] + _b.edges[:] + _b.faces[:], plane_co=_p, plane_no=CUT_N, dist=1e-5)
    _pts = [v.co.copy() for v in _r["geom_cut"] if isinstance(v, bmesh.types.BMVert) and (v.co - _p).length < 0.034]
    _u = CUT_N.cross(Vector((0, 0, 1))).normalized()
    _a = [(q - _p).dot(_u) for q in _pts]; _z = [(q - _p).z for q in _pts]
    _mids.append(_p + _u * (min(_a) + max(_a)) / 2 + Vector((0, 0, (min(_z) + max(_z)) / 2)))
    _b.free()
_M = np.array([m[:] for m in _mids]); _c0 = _M.mean(0)
_ax = np.linalg.svd(_M - _c0)[2][0]
if _ax @ np.array(CUT_N[:]) < 0: _ax = -_ax
mag_dir = Vector(_ax.tolist()).normalized()
mag_c = Vector((_c0 + _ax * ((np.array(cut[:]) - _c0) @ _ax)).tolist()) - cut   # the axis where it meets the cut, from the pivot
print("housing axis", tuple(round(c, 4) for c in mag_dir), "%.1f deg off the cut normal" % math.degrees(mag_dir.angle(CUT_N)))
mag_w = mag_dir.cross(Vector((0, 0, 1))).normalized()            # across, along the gun
mag_t = mag_w.cross(mag_dir).normalized()                       # square to both, up-ish
mb = bmesh.new()
def box(length, w, t, s0):
    m = Matrix((mag_dir, mag_w, mag_t)).transposed().to_4x4()
    m.translation = mag_c + mag_dir * (s0 + length / 2)
    bmesh.ops.create_cube(mb, size=1.0, matrix=m @ Matrix.Diagonal((length, w, t, 1)))
# sized to the housing's mouth (about 49 x 36 mm outside): it fills the opening
box(0.200, 0.040, 0.026, -0.03)                 # the body, its inner end 3 cm inside the housing
box(0.006, 0.045, 0.031, 0.168)                 # floor plate
for r in (0.05, 0.12):
    box(0.004, 0.0415, 0.0275, r)               # ribs
# the gun's own steel: each face of the magazine takes the texture of the housing
# face it would sit against (UVs from an affine fit, position -> uv, over the
# housing's faces that look the same way), read off the housing's length
_uvl = bm.loops.layers.uv.active if False else None
gb = bmesh.new(); gb.from_mesh(gun.data); guv = gb.loops.layers.uv.active
fits = {}
for key, dirv in (("t", mag_t), ("b", -mag_t), ("f", mag_w), ("r", -mag_w)):
    rows, uvs = [], []
    for f in gb.faces:
        c = f.calc_center_median() - cut
        sd = c.dot(mag_dir)
        if -0.05 < sd < -0.004 and (c - mag_dir * sd).length < 0.034 and f.normal.dot(dirv) > 0.7:
            for l in f.loops:
                q = l.vert.co - cut
                rows.append([q.dot(mag_dir), q.dot(mag_w), q.dot(mag_t), 1.0]); uvs.append(l[guv].uv[:])
    if len(rows) >= 12:
        # the faces span UV seams: keep the biggest single island (the points whose
        # uv sits near the median uv), then trim to the points the fit explains
        R, U = np.array(rows), np.array(uvs)
        keep = np.linalg.norm(U - np.median(U, 0), axis=1) < 0.03
        for _ in range(6):
            if keep.sum() < 9: break
            F, *_ = np.linalg.lstsq(R[keep], U[keep], rcond=None)
            res = np.linalg.norm(R @ F - U, axis=1)
            keep = keep & (res < max(0.002, np.percentile(res[keep], 80)))
        if keep.sum() >= 9:
            fits[key] = (F, float(np.linalg.norm(R[keep] @ F - U[keep], axis=1).max()), dirv)
gb.free()
print("magazine texture fits", {k: (round(v[1], 4)) for k, v in fits.items()})
muv = mb.loops.layers.uv.new("UVMap")
# laid on from the receiver's plain steel (the affine fit M, x z -> uv, from the
# patch): along the magazine reads along the receiver behind the old handle block,
# round it reads up the receiver wall, each face from its own stretch so the
# grain does not repeat side to side
for f in mb.faces:
    nrm = f.normal
    side = int(max(range(4), key=lambda i: nrm.dot((mag_t, -mag_t, mag_w, -mag_w)[i])))
    for l in f.loops:
        q = l.vert.co - mag_c
        sd = q.dot(mag_dir)
        cr = q.dot(mag_w) if side < 2 else q.dot(mag_t)
        x = -0.045 + (sd + 0.03) * 0.35 + 0.012 * side
        z = 0.128 + cr * 0.8
        l[muv].uv = tuple((np.array([x, z, 1.0]) @ M).tolist())
mme = bpy.data.meshes.new("StickMag"); mb.to_mesh(mme); mb.free()
stick = bpy.data.objects.new("StickMag", mme); bpy.context.scene.collection.objects.link(stick)
mme.materials.append(mat)
stick.location = cut
print("stick magazine on the housing at", tuple(round(c, 4) for c in cut), "axis (glTF)", (round(mag_dir.x, 4), round(mag_dir.z, 4), round(-mag_dir.y, 4)), "centre offset (glTF)", (round(mag_c.x, 4), round(mag_c.z, 4), round(-mag_c.y, 4)))

for o in (gun, drum, handle, stick):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40), keep_sharp_edges=True)
# the patch faces take the receiver tube's own normal (radial from its axis), so the fill
# reads as part of the tube and not as a faceted cap
me = gun.data
if "patch" in me.attributes:
    pa = [d.value for d in me.attributes["patch"].data]
    cn = [Vector(c.vector) for c in me.corner_normals]
    for p in me.polygons:
        if pa[p.index]:
            for li in p.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                cn[li] = Vector((0, co.y, co.z - 0.1256)).normalized()
    me.normals_split_custom_set(cn)
    me.attributes.remove(me.attributes["patch"])
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/mp18.blend")
V = np.array([gun.matrix_world @ v.co for v in gun.data.vertices])
print("body bounds (m)", V.min(0).round(3), V.max(0).round(3))
print("bore z %.4f m, muzzle x %.4f m, drum pivot %s, drum out along %s" % (BORE_Z * SCALE, MUZZLE_X * SCALE, tuple(round(c, 4) for c in cut), tuple(round(c, 3) for c in CUT_N)))
for img in bpy.data.images:
    if img.size[0] > 2048: img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT + "/mp18.glb", export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90, export_yup=True, export_apply=True)
subprocess.run([sys.executable, os.path.join(HERE, "glb_fix_images.py"), OUT + "/mp18.glb"], check=True)
