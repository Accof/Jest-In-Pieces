"""Builds the SMLE Mk III for the game from Tripo model 2 (the untouched source GLB).
Run: python3 build_smle.py <model2.glb> <outdir>   (Blender 5 as a Python module)
Steps are numbered; each prints what it did."""
import bpy, bmesh, math, sys, numpy as np
from mathutils import Vector, Matrix
SRC, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
gun = [o for o in bpy.data.objects if o.type == "MESH"][0]
gun.name = "Body"; gun.data.name = "Body"
mat = gun.data.materials[0]
img = [i for i in bpy.data.images if i.name == "Color"][0]
W, H = img.size
PX = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[:, :, :3]

# 1. apply the import transform; Tripo units, +X muzzle, -Y the rifle's right, +Z up
gun.data.transform(gun.matrix_world); gun.matrix_world = Matrix()
ZB = 0.166            # the bore axis (level): the nose cap's and handguard's middle
SCALE = 1.132 / 0.980 # an SMLE Mk III is 1132 mm long

bm = bmesh.new(); bm.from_mesh(gun.data)
_nv = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
print("1. welded %d -> %d vertices" % (_nv, len(bm.verts)))
uvl = bm.loops.layers.uv.active
def colour(f):
    c = np.zeros(3)
    for l in f.loops:
        u, v = l[uvl].uv
        c += PX[min(H - 1, max(0, int(v * H))), min(W - 1, max(0, int(u * W)))]
    return c / len(f.loops)
def is_steel(f):
    c = colour(f)
    return (c[0] - c[2]) < 0.06            # wood is clearly redder than it is blue

# 2. the band's two knobs (Tripo's guess at a handle, one each side) are pressed
# flat into the receiver's rear; the real knob goes back where the right one was
KNOB = Vector((-0.204, 0.0, 0.140))
_flat = 0
for v in bm.verts:
    if abs(v.co.y) > 0.0295 and Vector((v.co.x - KNOB.x, 0, v.co.z - KNOB.z)).length < 0.018 and v.co.z < ZB - 0.008:
        v.co.y = math.copysign(0.0295, v.co.y); _flat += 1
print("2. knobs pressed flat: %d vertices" % _flat)

def affine(faces, key):
    R = np.array([key(l.vert.co) + [1.0] for f in faces for l in f.loops]); U = np.array([l[uvl].uv[:] for f in faces for l in f.loops])
    # one UV island: the points near the uv that most others are near
    D = np.linalg.norm(U[:, None, :] - U[None, ::max(1, len(U) // 300), :], axis=2)
    seed = U[int(np.argmax((D < 0.03).sum(1)))]
    keep = np.linalg.norm(U - seed, axis=1) < 0.04
    for _ in range(6):
        if keep.sum() < 6: break
        F, *_ = np.linalg.lstsq(R[keep], U[keep], rcond=None)
        res = np.linalg.norm(R @ F - U, axis=1)
        keep = keep & (res < max(0.002, np.percentile(res[keep], 85)))
    return F, float(np.median(res[keep]))

# steel: the receiver's own plain right wall (below the old bolt), fitted x z -> uv
_sf = [f for f in bm.faces if -0.232 < f.calc_center_median().x < -0.208 and f.calc_center_median().y < -0.02
       and 0.100 < f.calc_center_median().z < 0.128 and f.normal.y < -0.6 and (colour(f)[0] - colour(f)[2]) < 0.08]
STEELF, _se = affine(_sf, lambda c: [c.x, c.z])
print("steel from the receiver rear's right side: %d faces, fit residual %.4f" % (len(_sf), _se))
_wf = [f for f in bm.faces if -0.30 < f.calc_center_median().x < -0.10 and f.calc_center_median().y < -0.02
       and 0.13 < f.calc_center_median().z < 0.155 and f.normal.y < -0.6 and (colour(f)[0] - colour(f)[2]) > 0.18]
WOODF, _we = affine(_wf, lambda c: [c.x, c.z])
print("wood from the stock's right side: %d faces, fit residual %.4f" % (len(_wf), _we))
# texture patches found by scanning the colour map for plain areas wholly inside
# the model's UV layout (centre u, v and size): dark worn blued steel, and walnut
STEEL_PATCH = (0.6318, 0.0500, 0.022)
WOOD_PATCH = (0.7041, 0.4014, 0.036)
def proj_uv(bmx, patch, faces=None):
    """box-project each face onto the patch: its two in-plane coordinates, the set's
    extent stretched evenly (not wrapped: a wrap smears the triangles across it)"""
    uv = bmx.loops.layers.uv.verify()
    faces = list(faces if faces is not None else bmx.faces)
    pu, pv, ps = patch
    def ab(f, c):
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        return [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
    if not faces: return
    axis = lambda f: max(range(3), key=lambda i: abs(f.normal[i]))
    groups = {}
    for f in faces: groups.setdefault(axis(f), []).append(f)
    span = 1e-6
    los = {}
    for g, fs in groups.items():           # each projection direction measured on its own
        A = np.array([ab(f, l.vert.co) for f in fs for l in f.loops])
        los[g] = A.min(0); span = max(span, (A.max(0) - A.min(0)).max())
    k = ps * 0.9 / span
    for f in faces:
        lo = los[axis(f)]
        for l in f.loops:
            a, b = ab(f, l.vert.co)
            l[uv].uv = (pu - ps * 0.45 + (a - lo[0]) * k, pv - ps * 0.45 + (b - lo[1]) * k)
steel_uv = lambda bmx, faces=None: proj_uv(bmx, STEEL_PATCH, faces)
bm.to_mesh(gun.data); bm.free()

# geometry helpers (Tripo units)
def cyl(bmx, x0, x1, r, y=0.0, z=ZB, seg=24, r1=None):
    m = Matrix.Translation(((x0 + x1) / 2, y, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    bmesh.ops.create_cone(bmx, cap_ends=True, segments=seg, radius1=r, radius2=r if r1 is None else r1, depth=abs(x1 - x0), matrix=m)
def tube(bmx, x0, x1, rin, rout, y=0.0, z=ZB, seg=28):
    vs = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for x in (x0, x1):
            for r in (rin, rout):
                vs.append(bmx.verts.new((x, y + r * math.cos(a), z + r * math.sin(a))))
    g = lambda i, xi, ri: vs[(i % seg) * 4 + xi * 2 + ri]
    for i in range(seg):
        bmx.faces.new([g(i, 0, 1), g(i + 1, 0, 1), g(i + 1, 1, 1), g(i, 1, 1)])      # outside
        bmx.faces.new([g(i, 1, 0), g(i + 1, 1, 0), g(i + 1, 0, 0), g(i, 0, 0)])      # bore
        bmx.faces.new([g(i, 0, 0), g(i + 1, 0, 0), g(i + 1, 0, 1), g(i, 0, 1)])      # rear face
        bmx.faces.new([g(i, 1, 1), g(i + 1, 1, 1), g(i + 1, 1, 0), g(i, 1, 0)])      # front face
def box(bmx, x0, x1, y0, y1, z0, z1):
    m = Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)) @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1))
    bmesh.ops.create_cube(bmx, size=1.0, matrix=m)
def ball(bmx, c, r):
    bmesh.ops.create_uvsphere(bmx, u_segments=28, v_segments=16, radius=r, matrix=Matrix.Translation(c))
def sweep(bmx, pts, r0, r1, seg=14):
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = t.cross(Vector((1, 0, 0)))
        if a.length < 1e-6: a = t.cross(Vector((0, 0, 1)))
        a.normalize(); b = t.cross(a).normalized()
        r = r0 + (r1 - r0) * i / (len(pts) - 1)
        rings.append([bmx.verts.new(p + (a * math.cos(2 * math.pi * k / seg) + b * math.sin(2 * math.pi * k / seg)) * r) for k in range(seg)])
    for ra, rb in zip(rings, rings[1:]):
        for k in range(seg):
            bmx.faces.new([ra[k], ra[(k + 1) % seg], rb[(k + 1) % seg], rb[k]])
    bmx.faces.new(rings[0][::-1]); bmx.faces.new(rings[-1])
def bez(p, n):
    p = [Vector(q) for q in p]
    return [((1 - t) ** 3) * p[0] + 3 * ((1 - t) ** 2) * t * p[1] + 3 * (1 - t) * t * t * p[2] + t ** 3 * p[3] for t in (i / (n - 1) for i in range(n))]


# 3. the receiver, carved into Tripo's own (exact booleans): the top cleared to just
# above the bolt line from the rear of the body to the front ring (that takes Tripo's
# fused bolt, the band's top and its lump of a bridge); a round-bottomed bolt-way
# along the bore from behind the body into the front ring; the right side of the
# body's rear cut away for the handle (the resistance shoulder). The cut faces take
# the receiver's steel.
XBODY, XBRIDGE0, XBRIDGE1, XRING = -0.205, -0.165, -0.152, -0.107
XR = -0.262
R_IN = 0.0083
ZTOP = ZB + 0.0040
cut = bmesh.new()
XC = -0.240                       # the back of the receiver's rear (nothing above the wrist behind it)
box(cut, XC, XRING, -0.06, 0.06, ZTOP, 0.25)                                 # the top
cyl(cut, XC, XRING + 0.0035, R_IN, seg=32)                                   # the bolt-way
box(cut, XC, XRING, -R_IN, R_IN, ZB, ZTOP + 0.001)
box(cut, XBRIDGE0 + 0.0005, XRING, -R_IN, R_IN, ZB - 0.0175, ZB)             # the magazine opening in front of the bridge
steel_uv(cut)
cme = bpy.data.meshes.new("_cut"); cut.to_mesh(cme); cut.free()
cob = bpy.data.objects.new("_cut", cme); bpy.context.scene.collection.objects.link(cob)
cme.materials.append(bpy.data.materials.new("_cutface"))       # marks the faces the carve makes
mod = gun.modifiers.new("carve", "BOOLEAN"); mod.operation = "DIFFERENCE"; mod.solver = "EXACT"; mod.object = cob; mod.use_hole_tolerant = True; mod.material_mode = "TRANSFER"   # the scan is not watertight
bpy.context.view_layer.objects.active = gun
_f0 = len(gun.data.polygons)
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cob)
print("3. receiver carved: faces %d -> %d" % (_f0, len(gun.data.polygons)))

# the carved faces: each takes the steel of the receiver or the stock's wood, by
# what it was cut through (the nearest original face)
bm = bmesh.new(); bm.from_mesh(gun.data)
uvl = bm.loops.layers.uv.active
new = [f for f in bm.faces if f.material_index == 1]
old = [f for f in bm.faces if f.material_index == 0]
from mathutils import kdtree
kd = kdtree.KDTree(len(old))
for i, f in enumerate(old): kd.insert(f.calc_center_median(), i)
kd.balance()
nw = ns = 0
wood_new, steel_new = [], []
new = [f for f in new if f.is_valid]
old = [f for f in old if f.is_valid]
for f in new:
    f.material_index = 0
    near = [old[i] for _, i, _ in kd.find_n(f.calc_center_median(), 6)]
    c = f.calc_center_median()
    in_way = (abs(c.y) <= R_IN + 2e-4 and c.z < ZTOP - 2e-4) or c.x < XBODY + 0.002   # the bolt-way and the body's rear: steel
    woody = (not in_way) and sum((colour(g)[0] - colour(g)[2]) > 0.15 for g in near) >= 4
    (wood_new if woody else steel_new).append(f)
    f.smooth = False
    for e in f.edges: e.smooth = False                                 # flat, sharp-edged (no fan shading on the caps)
proj_uv(bm, WOOD_PATCH, wood_new); proj_uv(bm, STEEL_PATCH, steel_new)
# the hole-tolerant carve keeps the top half of the round bolt-way as a lid: it goes
_lid = [f for f in new if f.calc_center_median().z > ZB + 0.0005 and abs(f.calc_center_median().y) < R_IN + 1e-4 and f.normal.z < -0.1]
bmesh.ops.delete(bm, geom=_lid, context="FACES")
new = [f for f in new if f.is_valid]
print("3. lid over the bolt-way removed: %d faces" % len(_lid))
# slivers of Tripo's old bolt the carve left inside the bolt-way, or standing above it
_newset = set(new)
_sl = [f for f in bm.faces if f not in _newset and XC < f.calc_center_median().x < XRING
       and ((abs(f.calc_center_median().y) < R_IN + 0.0006 and ZB - R_IN - 0.001 < f.calc_center_median().z < ZTOP + 0.003)
            or f.calc_center_median().z > ZTOP + 0.0006)]
bmesh.ops.delete(bm, geom=_sl, context="FACES")
print("3. slivers of the old bolt removed: %d" % len(_sl))

bm.to_mesh(gun.data); bm.free()
while len(gun.data.materials) > 1: gun.data.materials.pop()
print("3. carved faces textured: %d steel, %d wood" % (len(steel_new), len(wood_new)))

# 4. new steel on the receiver (part of Body): the charger bridge arching over the
# bolt-way at the back of the magazine opening, with its two charger guides; the
# magazine's follower filling the opening; the safety catch on the left at the rear
rb = bmesh.new()
for sgn in (1, -1):
    y0, y1 = sorted((sgn * (R_IN + 0.0003), sgn * 0.0165))
    box(rb, XBRIDGE0, XBRIDGE1, y0, y1, ZTOP - 0.004, ZB + 0.0170)               # pillars
    box(rb, XBRIDGE1 - 0.0008, XBRIDGE1 + 0.0032, sgn * 0.0050 - 0.0012, sgn * 0.0050 + 0.0012, ZB + 0.0110, ZB + 0.0195)   # guides
box(rb, XBRIDGE0, XBRIDGE1, -0.0165, 0.0165, ZB + 0.0115, ZB + 0.0175)          # the arch
box(rb, XBRIDGE1, XRING, -R_IN - 0.0002, R_IN + 0.0002, ZB - 0.0175, ZB - 0.0150)   # follower
box(rb, XBRIDGE1 + 0.004, XRING - 0.006, -0.0040, 0.0040, ZB - 0.0152, ZB - 0.0125)  # its rib
cyl(rb, XC + 0.006, XC + 0.011, 0.0045, y=0.0155, z=ZTOP + 0.0012, seg=18)       # safety catch, left
for i in range(6):
    box(rb, XC + 0.0055, XC + 0.0115, 0.0152 - 0.0003, 0.0152 + 0.0003, ZTOP - 0.002 + i * 0.0012, ZTOP - 0.0015 + i * 0.0012)
bmesh.ops.bevel(rb, geom=[e for e in rb.edges], offset=0.0004, segments=1, affect="EDGES", clamp_overlap=True)
steel_uv(rb)
_rm = bpy.data.meshes.new("_recv"); rb.to_mesh(_rm); rb.free()
_ro = bpy.data.objects.new("_recv", _rm); bpy.context.scene.collection.objects.link(_ro); _rm.materials.append(mat)
bpy.ops.object.select_all(action="DESELECT"); gun.select_set(True); _ro.select_set(True); bpy.context.view_layer.objects.active = gun
bpy.ops.object.join()
print("4. charger bridge, follower and safety catch added")

# 5. the bolt (from the close-ups and the locking diagram): the body with the guide
# rib on the right and the locking lug on the left; the bolt head with its
# extractor; the handle's root collar at the rear; the handle curving out and down
# on the right to the round knob. Behind it the cocking piece with its knurled head.
# Bolt (slides) > BoltTurn (turns about the bore) and CockingPiece (slides only).
# The handle's root sits just behind the body's rear (Tripo's band, kept as that
# rear): it bears on the band's rear face when closed (the resistance shoulder).
XROOT = -0.2405                     # the root's front face, just behind the band
BOLT_ORIGIN = Vector((XROOT, 0.0, ZB))
BOLT_TRAVEL = 0.072                 # the head goes back past the bridge (Tripo units; ~83 mm)
HANDLE_LIFT = 60.0
KNOB_C = Vector((XROOT - 0.0065, -0.040, ZB - 0.030))
bt = bmesh.new()
cyl(bt, XROOT, XRING - 0.0105, 0.0076, seg=28)                               # the body
cyl(bt, XRING - 0.0105, XRING - 0.0004, 0.0073, seg=28)                      # the head
box(bt, XRING - 0.0125, XRING - 0.0004, -0.0084, -0.0058, ZB - 0.0012, ZB + 0.0038)   # extractor
box(bt, XROOT + 0.006, -0.152, -0.0090, -0.0064, ZB - 0.0016, ZB + 0.0016)  # guide rib (right)
box(bt, -0.182, -0.173, 0.0064, 0.0090, ZB - 0.0016, ZB + 0.0016)            # locking lug (left)
cyl(bt, XROOT - 0.0095, XROOT, 0.0088, seg=28)                               # the handle's root
_hx = XROOT - 0.0048
path = bez([(_hx, -0.0062, ZB - 0.0010), (_hx - 0.0004, -0.0250, ZB - 0.0015), (_hx - 0.0018, -0.0335, ZB - 0.0115), KNOB_C + Vector((0, 0.0025, 0.0055))], 16)
sweep(bt, path, 0.0040, 0.0031)
ball(bt, KNOB_C, 0.0085)
steel_uv(bt)
cp = bmesh.new()
_c0 = XROOT - 0.0095
cyl(cp, _c0 - 0.0225, _c0, 0.0062, seg=24)                                   # cocking piece
box(cp, _c0 - 0.0230, _c0 - 0.0145, -0.0045, 0.0045, ZB, ZB + 0.0110)        # its head
for i in range(5):                                                           # knurling
    box(cp, _c0 - 0.0230 + i * 0.0017, _c0 - 0.0221 + i * 0.0017, -0.0049, 0.0049, ZB + 0.0035, ZB + 0.0116)
steel_uv(cp)
def part(name, b, parent):
    me = bpy.data.meshes.new(name); b.to_mesh(me); b.free()
    me.transform(Matrix.Translation(-BOLT_ORIGIN))
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat)
    o.parent = parent
    return o
bolt = bpy.data.objects.new("Bolt", None); bpy.context.scene.collection.objects.link(bolt); bolt.location = BOLT_ORIGIN
bolt.empty_display_size = 0.01
turn = part("BoltTurn", bt, bolt)
cock = part("CockingPiece", cp, bolt)
print("5. bolt: travel %.3f (%.0f mm), handle lift %.0f deg, knob at %s" % (BOLT_TRAVEL, BOLT_TRAVEL * SCALE * 1000, HANDLE_LIFT, tuple(round(c, 4) for c in KNOB_C)))

# 6. iron sights. Front: Tripo's blade stands at the nose cap (tip 0.2056) but its
# protector ears are below it; new ears rise past it. Rear: Tripo's lump of a rear
# sight is cut down and a Mk III battle sight built: a leaf between two protector
# wings, the U notch at its rear, the notch's bottom on the line through the blade's
# tip parallel to the bore.
ZS = 0.2056                          # the sight line (Tripo units)
XFRONT = 0.4575                      # the blade
XNOTCH = 0.0465                      # the rear notch
cut = bmesh.new()
box(cut, 0.012, 0.070, -0.022, 0.022, ZS - 0.0105, 0.30)
steel_uv(cut)
cme = bpy.data.meshes.new("_cut2"); cut.to_mesh(cme); cut.free()
cob = bpy.data.objects.new("_cut2", cme); bpy.context.scene.collection.objects.link(cob)
cme.materials.append(bpy.data.materials.new("_cutface2"))
mod = gun.modifiers.new("sight", "BOOLEAN"); mod.operation = "DIFFERENCE"; mod.solver = "EXACT"; mod.object = cob
mod.use_hole_tolerant = True; mod.material_mode = "TRANSFER"
bpy.context.view_layer.objects.active = gun
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cob)
bm = bmesh.new(); bm.from_mesh(gun.data)
new = [f for f in bm.faces if f.material_index == 1]
_lid = [f for f in new if f.normal.z < -0.5 and f.calc_center_median().z > ZS - 0.0105 + 0.0005]
bmesh.ops.delete(bm, geom=_lid, context="FACES")
new = [f for f in new if f.is_valid]
for f in new:
    f.material_index = 0; f.smooth = False
steel_uv(bm, new)
_up = [f for f in bm.faces if f.is_valid and 0.012 < f.calc_center_median().x < 0.070 and abs(f.calc_center_median().y) < 0.022 and f.calc_center_median().z > ZS - 0.0100]
bmesh.ops.delete(bm, geom=_up, context="FACES")
bm.to_mesh(gun.data); bm.free()
while len(gun.data.materials) > 1: gun.data.materials.pop()
rs = bmesh.new()
ZB0 = ZS - 0.0105
NH = 0.0035                          # the notch's half width (the blade is ~0.004 wide at its tip)
ND = 0.0045                          # its depth below the line
for sgn in (1, -1):
    y0, y1 = sorted((sgn * 0.0088, sgn * 0.0112))
    box(rs, 0.030, 0.052, y0, y1, ZB0, ZS + 0.0025)                               # protector wings
    y0, y1 = sorted((sgn * NH, sgn * 0.0080))
    box(rs, XNOTCH - 0.0010, XNOTCH + 0.0010, y0, y1, ZB0, ZS)                     # the notch's shoulders: their tops are the line
box(rs, XNOTCH - 0.0010, XNOTCH + 0.0010, -NH, NH, ZB0, ZS - ND)                 # the notch's bottom
box(rs, 0.018, XNOTCH, -0.0048, 0.0048, ZB0, ZB0 + 0.0022)                       # the leaf, lying
box(rs, 0.026, 0.056, -0.0105, 0.0105, ZB0 - 0.0015, ZB0)                        # its bed
for sgn in (1, -1):                                                              # the front protector ears, past the blade
    y0, y1 = (0.0062, 0.0088) if sgn > 0 else (-0.0088, -0.0062)
    box(rs, XFRONT - 0.0085, XFRONT + 0.0085, y0, y1, 0.1840, ZS + 0.0030)
bmesh.ops.bevel(rs, geom=[e for e in rs.edges], offset=0.0003, segments=1, affect="EDGES", clamp_overlap=True)
steel_uv(rs)
_rm = bpy.data.meshes.new("_sights"); rs.to_mesh(_rm); rs.free()
_ro = bpy.data.objects.new("_sights", _rm); bpy.context.scene.collection.objects.link(_ro); _rm.materials.append(mat)
bpy.ops.object.select_all(action="DESELECT"); gun.select_set(True); _ro.select_set(True); bpy.context.view_layer.objects.active = gun
bpy.ops.object.join()
print("6. sights: rear notch at x %.4f, blade at x %.4f, the line %.4f above the bore (Tripo units)" % (XNOTCH, XFRONT, ZS - ZB))

# 7. markers the game reads (empties, Tripo units here): the muzzle, the rear notch
# and the blade's tip on the sight line, where cases leave the ejection opening, the
# charger guide on the bridge, and the magazine's mouth
def marker(name, p, parent=None):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.location = Vector(p); e.empty_display_size = 0.005
    if parent: e.parent = parent; e.location = Vector(p) - parent.location
    return e
marker("Muzzle", (0.4905, 0.0005, 0.1519))
marker("SightRear", (XNOTCH, 0.0, ZS))
marker("SightFront", (XFRONT, 0.0, ZS))
marker("Ejection", (-0.135, -0.0095, ZB + 0.006))
marker("ChargerGuide", (XBRIDGE1 + 0.0015, 0.0, ZB + 0.0195))
marker("MagMouth", ((XBRIDGE1 + XRING) / 2, 0.0, ZB - 0.0130))
marker("Knob", KNOB_C, bolt)

# 8. metres: everything scaled about the origin (Tripo units -> m)
S = SCALE
for o in bpy.data.objects:
    if o.type == "MESH":
        o.data.transform(Matrix.Scale(S, 4))
    o.location = o.location * S
for o in (gun, turn, cock):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35), keep_sharp_edges=True)
V = np.array([v.co[:] for v in gun.data.vertices])
print("8. metres: length %.3f m; bore at %.4f m; bolt travel %.4f m; handle lift %.0f deg" % (V[:, 0].max() - V[:, 0].min(), ZB * S, BOLT_TRAVEL * S, HANDLE_LIFT))
print("   sight line %.4f m above the bore; sight radius %.3f m" % ((ZS - ZB) * S, (XFRONT - XNOTCH) * S))
print("   polygons: body %d, bolt %d, cocking piece %d" % (len(gun.data.polygons), len(turn.data.polygons), len(cock.data.polygons)))
import os, subprocess
os.makedirs(OUT, exist_ok=True)
for img in bpy.data.images:              # 2K is plenty for a first-person gun
    if img.size[0] > 2048: img.scale(2048, 2048)
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/smle.blend")
bpy.ops.export_scene.gltf(filepath=OUT + "/smle.glb", export_format="GLB", export_yup=True, export_apply=False, use_selection=False,
                          export_extras=False, export_animations=False)
print("8. exported", OUT + "/smle.glb")
HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(HERE, "glb_fix_images.py"), OUT + "/smle.glb"], check=True)
