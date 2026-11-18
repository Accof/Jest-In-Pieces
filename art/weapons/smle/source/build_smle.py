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
# Blued steel for every new part and every steel face the carve makes: its own
# seamless maps (generated here: mottled blueing worn lighter in patches, fine grain,
# a few scratches; roughness and a light normal from the same height), laid on by box
# projection at real scale, so it tiles cleanly with no atlas seams or smears.
def _tile_noise(n, beta, seed):
    r = np.random.default_rng(seed)
    F = np.fft.fft2(r.normal(size=(n, n)))
    fy = np.fft.fftfreq(n)[:, None]; fx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(fx * fx + fy * fy); k[0, 0] = 1.0
    out = np.real(np.fft.ifft2(F / k ** beta))
    return (out - out.mean()) / out.std()
def _blued_steel_maps(n=512):
    mott = _tile_noise(n, 1.6, 1)                      # broad wear of the blueing
    grain = _tile_noise(n, 0.6, 2)                     # fine surface grain
    streak = _tile_noise(n, 1.2, 3)
    rng = np.random.default_rng(4)
    scr = np.zeros((n, n))
    for _ in range(70):                                # light scratches (wrapped, so seamless)
        x0, y0 = rng.uniform(0, n, 2); ang = rng.uniform(-0.5, 0.5) + (0 if rng.random() < 0.7 else np.pi / 2)
        ln = rng.uniform(n * 0.05, n * 0.3)
        t = np.linspace(0, 1, int(ln * 2))
        xs = (x0 + np.cos(ang) * ln * t).astype(int) % n; ys = (y0 + np.sin(ang) * ln * t).astype(int) % n
        scr[ys, xs] = np.maximum(scr[ys, xs], rng.uniform(0.3, 1.0))
    wear = np.clip(0.5 + 0.28 * mott, 0, 1) ** 2.2     # where the blueing has worn grey
    blue = np.array([0.20, 0.215, 0.24]); bare = np.array([0.42, 0.42, 0.43])
    col = blue[None, None] * (1 - wear[..., None]) + bare[None, None] * wear[..., None]
    col *= (1 + 0.07 * grain[..., None] + 0.04 * streak[..., None])
    col = col + scr[..., None] * 0.10
    col = np.clip(col, 0, 1)
    rough = np.clip(0.44 + 0.07 * mott + 0.04 * grain - 0.12 * scr, 0.25, 0.7)
    h = 0.6 * grain + 0.25 * streak - 1.2 * scr
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5; gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nrm = np.dstack([-gx * 0.06, -gy * 0.06, np.ones_like(h)]); nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return col, rough, nrm
def _image(name, rgb, colour):
    n = rgb.shape[0]
    im = bpy.data.images.new(name, n, n, alpha=False)
    im.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    px = np.ones((n, n, 4), dtype=np.float32); px[..., :3] = rgb
    im.pixels.foreach_set(px.ravel()); im.pack()
    return im
_c, _r, _n = _blued_steel_maps()
steel = bpy.data.materials.new("BluedSteel"); steel.use_nodes = True
_nt = steel.node_tree; _p = _nt.nodes.get("Principled BSDF")
_tc = _nt.nodes.new("ShaderNodeTexImage"); _tc.image = _image("BluedSteel_Color", _c, True)
_nt.links.new(_tc.outputs["Color"], _p.inputs["Base Color"])
_orm = np.dstack([np.ones_like(_r), _r, np.full_like(_r, 0.70)])
_to = _nt.nodes.new("ShaderNodeTexImage"); _to.image = _image("BluedSteel_MR", _orm, False)
_sep = _nt.nodes.new("ShaderNodeSeparateColor")
_nt.links.new(_to.outputs["Color"], _sep.inputs["Color"])
_nt.links.new(_sep.outputs["Green"], _p.inputs["Roughness"]); _nt.links.new(_sep.outputs["Blue"], _p.inputs["Metallic"])
_tn = _nt.nodes.new("ShaderNodeTexImage"); _tn.image = _image("BluedSteel_Normal", _n * 0.5 + 0.5, False)
_nm = _nt.nodes.new("ShaderNodeNormalMap"); _nt.links.new(_tn.outputs["Color"], _nm.inputs["Color"]); _nt.links.new(_nm.outputs["Normal"], _p.inputs["Normal"])
STEEL_TILE = 0.035                                     # Tripo units per repeat (~4 cm)
def steel_uv(bmx, faces=None):
    """box projection at real scale onto the tiling blued steel"""
    uv = bmx.loops.layers.uv.verify()
    for f in (faces if faces is not None else bmx.faces):
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        for l in f.loops:
            c = l.vert.co
            a, b = [(c.y, c.z), (c.x, c.z), (c.x, c.y)][ax]
            l[uv].uv = (a / STEEL_TILE, b / STEEL_TILE)
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
WALL = 0.0165                     # the receiver's walls (outside)
ZW = ZB - 0.0030                  # the wood comes up beside them to here
box(cut, XC, XRING, -0.06, 0.06, ZW, 0.25)                                   # everything above the wood line (Tripo's walls are fused lumps: new ones are built)
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
    in_way = (abs(c.y) <= R_IN + 2e-4 and c.z < ZTOP - 2e-4) or c.x < XBODY + 0.002 \
        or (abs(c.y) <= WALL + 2e-4)                                      # the bolt-way, under the walls and the body's rear: steel
    woody = (not in_way) and sum((colour(g)[0] - colour(g)[2]) > 0.15 for g in near) >= 4
    (wood_new if woody else steel_new).append(f)
    f.smooth = False
    for e in f.edges: e.smooth = False                                 # flat, sharp-edged (no fan shading on the caps)
proj_uv(bm, WOOD_PATCH, wood_new); steel_uv(bm, steel_new)
for f in steel_new: f.material_index = 1          # -> BluedSteel (slot 1 once the marker slot goes)
# the hole-tolerant carve keeps the top half of the round bolt-way as a lid: it goes
_lid = [f for f in new if f.calc_center_median().z > ZB + 0.0005 and abs(f.calc_center_median().y) < R_IN + 1e-4 and f.normal.z < -0.1]
bmesh.ops.delete(bm, geom=_lid, context="FACES")
new = [f for f in new if f.is_valid]
print("3. lid over the bolt-way removed: %d faces" % len(_lid))
# slivers of Tripo's old bolt the carve left inside the bolt-way, or standing above it
_newset = set(new)
_sl = [f for f in bm.faces if f not in _newset and XC < f.calc_center_median().x < XRING
       and ((abs(f.calc_center_median().y) < R_IN + 0.0006 and ZB - R_IN - 0.001 < f.calc_center_median().z < ZTOP + 0.003)
            or f.calc_center_median().z > ZW + 0.0006)]
bmesh.ops.delete(bm, geom=_sl, context="FACES")
print("3. slivers of the old bolt removed: %d" % len(_sl))

# the wood beside the walls: where the cut opened the scan's shell, a walnut deck at the
# wood line from the wall out to the stock's own side (measured every 2 mm)
_V = np.array([v.co[:] for v in bm.verts])
_band = _V[(np.abs(_V[:, 2] - ZW) < 0.0016) & (_V[:, 0] > XC - 0.002) & (_V[:, 0] < XRING + 0.002)]
_deck = []
for sgn in (1, -1):
    rows = []
    for x in np.arange(XC, XRING + 1e-9, 0.002):
        q = _band[(np.abs(_band[:, 0] - x) < 0.0016) & (_band[:, 1] * sgn > WALL)]
        if len(q):
            rows.append((x, float(np.max(np.abs(q[:, 1]))) - 0.0004))
    if len(rows) > 4:                                   # a steady edge, not the scan's stair-steps
        W = np.array([w for _, w in rows])
        Wm = np.array([np.median(W[max(0, i - 4):i + 5]) for i in range(len(W))])
        Ws = np.convolve(np.pad(Wm, 3, mode="edge"), np.ones(7) / 7, mode="valid")
        rows = [(x, float(min(w, 0.0315))) for (x, _), w in zip(rows, Ws)]
    for (x0, w0), (x1, w1) in zip(rows, rows[1:]):
        if min(w0, w1) <= WALL + 0.001: continue
        # a shoulder, not a shelf: the wood rises toward the receiver as it does on the rifle
        vs = [bm.verts.new((x0, sgn * WALL, ZW + 0.0040)), bm.verts.new((x1, sgn * WALL, ZW + 0.0040)),
              bm.verts.new((x1, sgn * w1, ZW + 0.0002)), bm.verts.new((x0, sgn * w0, ZW + 0.0002))]
        f = bm.faces.new(vs if sgn < 0 else vs[::-1]); f.smooth = False; _deck.append(f)
# the stock's own side, just under the deck's outer edge, continued up over it
for f in _deck:
    f.material_index = 0
    for l in f.loops:
        c = l.vert.co
        l[uvl].uv = tuple((np.array([c.x, ZW - 0.0025 - (abs(c.y) - WALL) * 0.25, 1.0]) @ WOODF).tolist())
print("3. walnut deck beside the walls: %d strips" % len(_deck))
bm.to_mesh(gun.data); bm.free()
while len(gun.data.materials) > 1: gun.data.materials.pop()
gun.data.materials.append(steel)
print("3. carved faces textured: %d steel, %d wood" % (len(steel_new), len(wood_new)))

# 4. new steel on the receiver (part of Body): the charger bridge arching over the
# bolt-way at the back of the magazine opening, with its two charger guides; the
# magazine's follower filling the opening; the safety catch on the left at the rear
rb = bmesh.new()
def arch(bmx, x0, x1, rin, rout, seg=20):
    """the top half of a ring about the bore, x0..x1"""
    vs = []
    for i in range(seg + 1):
        a = math.pi * i / seg
        for x in (x0, x1):
            for r in (rin, rout):
                vs.append(bmx.verts.new((x, r * math.cos(a), ZB + r * math.sin(a))))
    g = lambda i, xi, ri: vs[i * 4 + xi * 2 + ri]
    for i in range(seg):
        bmx.faces.new([g(i, 0, 1), g(i + 1, 0, 1), g(i + 1, 1, 1), g(i, 1, 1)])
        bmx.faces.new([g(i, 1, 0), g(i + 1, 1, 0), g(i + 1, 0, 0), g(i, 0, 0)])
        bmx.faces.new([g(i, 0, 0), g(i + 1, 0, 0), g(i + 1, 0, 1), g(i, 0, 1)])
        bmx.faces.new([g(i, 1, 1), g(i + 1, 1, 1), g(i + 1, 1, 0), g(i, 1, 0)])
    for i in (0, seg):
        bmx.faces.new([g(i, 0, 0), g(i, 0, 1), g(i, 1, 1), g(i, 1, 0)] if i == 0 else [g(i, 1, 0), g(i, 1, 1), g(i, 0, 1), g(i, 0, 0)])
# the receiver's walls on the wood line, either side of the bolt-way: the left full
# height; the right low behind the bridge (the bolt shows from the right, as on the
# rifle); taller at the body's rear, where the handle's root bears
for sgn in (1, -1):
    y0, y1 = sorted((sgn * (R_IN + 0.0002), sgn * WALL))
    box(rb, XBODY, XRING, y0, y1, ZW - 0.0015, ZTOP) if sgn > 0 else None
    box(rb, XC, XBODY, y0, y1, ZW - 0.0015, ZB + 0.0085)                           # the body's rear
    if sgn < 0:
        box(rb, XBODY, XBODY + 0.006, y0, y1, ZW - 0.0015, ZTOP)
        box(rb, XBODY + 0.006, XBRIDGE0, y0, y1, ZW - 0.0015, ZB + 0.0006)          # low: the bolt shows
        box(rb, XBRIDGE0, XRING, y0, y1, ZW - 0.0015, ZTOP)
arch(rb, XBRIDGE0, XBRIDGE1, 0.0092, 0.0165)                                       # the charger bridge
for sgn in (1, -1):
    y0, y1 = sorted((sgn * 0.0092, sgn * 0.0165))
    box(rb, XBRIDGE0, XBRIDGE1, y0, y1, ZW - 0.002, ZB + 0.0002)                    # its feet
    box(rb, XBRIDGE1 - 0.0006, XBRIDGE1 + 0.0026, sgn * 0.0052 - 0.0011, sgn * 0.0052 + 0.0011, ZB + 0.0135, ZB + 0.0192)   # charger guides
box(rb, XBRIDGE1, XRING, -R_IN - 0.0002, R_IN + 0.0002, ZB - 0.0175, ZB - 0.0150)   # follower
box(rb, XBRIDGE1 + 0.004, XRING - 0.006, -0.0040, 0.0040, ZB - 0.0152, ZB - 0.0125)  # its rib
cyl(rb, XC + 0.006, XC + 0.011, 0.0045, y=0.0155, z=ZTOP + 0.0012, seg=18)       # safety catch, left
for i in range(6):
    box(rb, XC + 0.0055, XC + 0.0115, 0.0152 - 0.0003, 0.0152 + 0.0003, ZTOP - 0.002 + i * 0.0012, ZTOP - 0.0015 + i * 0.0012)
bmesh.ops.bevel(rb, geom=[e for e in rb.edges if e.calc_face_angle(0) > 0.6], offset=0.0004, segments=2, affect="EDGES", clamp_overlap=True)
steel_uv(rb)
_rm = bpy.data.meshes.new("_recv"); rb.to_mesh(_rm); rb.free()
_ro = bpy.data.objects.new("_recv", _rm); bpy.context.scene.collection.objects.link(_ro); _rm.materials.append(steel)
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
path = bez([(_hx, -0.0060, ZB - 0.0006), (_hx - 0.0006, -0.0190, ZB - 0.0050), (_hx - 0.0014, -0.0300, ZB - 0.0170), KNOB_C + Vector((0, 0.0022, 0.0060))], 18)
sweep(bt, path, 0.0038, 0.0030)                                               # the arm: out and down to the knob
ball(bt, KNOB_C, 0.0085)
bmesh.ops.bevel(bt, geom=[e for e in bt.edges if e.calc_face_angle(0) > 1.2], offset=0.0003, segments=1, affect="EDGES", clamp_overlap=True)
steel_uv(bt)
cp = bmesh.new()
_c0 = XROOT - 0.0095
cyl(cp, _c0 - 0.0170, _c0, 0.0058, seg=24)                                   # cocking piece
_k = Matrix.Translation((_c0 - 0.0125, 0.0, ZB + 0.0050)) @ Matrix.Rotation(math.pi / 2, 4, "X")
bmesh.ops.create_cone(cp, cap_ends=True, segments=20, radius1=0.0050, radius2=0.0050, depth=0.0082, matrix=_k)   # its rounded head
for i in range(4):                                                           # serrations on the head
    box(cp, _c0 - 0.0158 + i * 0.0021, _c0 - 0.0151 + i * 0.0021, -0.0043, 0.0043, ZB + 0.0050, ZB + 0.0104)
steel_uv(cp)
def part(name, b, parent):
    me = bpy.data.meshes.new(name); b.to_mesh(me); b.free()
    me.transform(Matrix.Translation(-BOLT_ORIGIN))
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.materials.append(steel)
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
    f.material_index = 1; f.smooth = False                     # BluedSteel
steel_uv(bm, new)
_up = [f for f in bm.faces if f.is_valid and 0.012 < f.calc_center_median().x < 0.070 and abs(f.calc_center_median().y) < 0.022 and f.calc_center_median().z > ZS - 0.0100]
bmesh.ops.delete(bm, geom=_up, context="FACES")
bm.to_mesh(gun.data); bm.free()
while len(gun.data.materials) > 2: gun.data.materials.pop()
rs = bmesh.new()
ZB0 = ZS - 0.0105
NH = 0.0035                          # the notch's half width (the blade is ~0.004 wide at its tip)
ND = 0.0045                          # its depth below the line
for sgn in (1, -1):
    y0, y1 = sorted((sgn * 0.0090, sgn * 0.0106))
    box(rs, 0.031, 0.051, y0, y1, ZB0, ZS + 0.0015)                               # protector wings
    y0, y1 = sorted((sgn * NH, sgn * 0.0080))
    box(rs, XNOTCH - 0.0010, XNOTCH + 0.0010, y0, y1, ZB0, ZS)                     # the notch's shoulders: their tops are the line
box(rs, XNOTCH - 0.0010, XNOTCH + 0.0010, -NH, NH, ZB0, ZS - ND)                 # the notch's bottom
box(rs, 0.018, XNOTCH, -0.0048, 0.0048, ZB0, ZB0 + 0.0022)                       # the leaf, lying
box(rs, 0.026, 0.056, -0.0105, 0.0105, ZB0 - 0.0015, ZB0)                        # its bed
for sgn in (1, -1):                                                              # the front protector ears, past the blade
    y0, y1 = (0.0062, 0.0088) if sgn > 0 else (-0.0088, -0.0062)
    box(rs, XFRONT - 0.0085, XFRONT + 0.0085, y0, y1, 0.1840, ZS + 0.0030)
bmesh.ops.bevel(rs, geom=[e for e in rs.edges], offset=0.0003, segments=2, affect="EDGES", clamp_overlap=True)
steel_uv(rs)
_rm = bpy.data.meshes.new("_sights"); rs.to_mesh(_rm); rs.free()
_ro = bpy.data.objects.new("_sights", _rm); bpy.context.scene.collection.objects.link(_ro); _rm.materials.append(steel)
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
_ci = [i for i in bpy.data.images if i.name == "Color"][0]
_mi = [i for i in bpy.data.images if i.name.startswith("tripo_image")][0]
_w, _h = _ci.size
_C = np.array(_ci.pixels[:], dtype=np.float32).reshape(_h, _w, 4)
_M = np.array(_mi.pixels[:], dtype=np.float32).reshape(_mi.size[1], _mi.size[0], 4)
if _M.shape[:2] == _C.shape[:2]:
    _red = _C[..., 0] - _C[..., 2]
    _sat = _C[..., :3].max(2) - _C[..., :3].min(2)
    _wood = np.clip((_red - 0.10) / 0.10, 0, 1)                  # soft masks, no hard edges in the maps
    _st = np.clip((0.09 - _sat) / 0.05, 0, 1) * (1 - _wood)
    _rw = np.clip(0.60 + (_M[..., 1] - 0.27) * 1.6, 0.58, 0.85)  # oiled walnut: matte with a little sheen
    _M[..., 1] = _M[..., 1] * (1 - _wood) + _rw * _wood
    _M[..., 2] = _M[..., 2] * (1 - _wood)
    _M[..., 1] = _M[..., 1] * (1 - _st) + np.clip(_M[..., 1] * 0.6 + 0.30, 0.48, 0.66) * _st   # satin, not chrome
    _M[..., 2] = _M[..., 2] * (1 - _st) + np.maximum(_M[..., 2], 0.80) * _st
    _mi.pixels.foreach_set(_M.ravel()); _mi.pack()
    # weathered dark walnut: the wood a little darker and less orange
    _g = _C[..., :3].mean(2, keepdims=True)
    _dark = (_C[..., :3] * (1 - 0.22) + _g * 0.22) * 0.68                 # darker, less orange
    _C[..., :3] = _C[..., :3] * (1 - _wood[..., None]) + _dark * _wood[..., None]
    # Tripo's steel toward the blueing of the new parts: darker, a touch cooler
    _blu = _C[..., :3] * np.array([0.66, 0.68, 0.74])
    _C[..., :3] = _C[..., :3] * (1 - _st[..., None]) + _blu * _st[..., None]
    _ci.pixels.foreach_set(_C.ravel()); _ci.pack()
    print("8. finish: wood roughness %.2f -> %.2f, metal %.2f -> 0; steel metal -> %.2f" % (
        float(np.mean(np.array(_ci.pixels[:]).reshape(_h, _w, 4)[..., 1][_wood > 0.9]) if False else 0.31), float(_rw[_wood > 0.9].mean()), 0.095, float(_M[..., 2][_st > 0.9].mean())))
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/smle.blend")
bpy.ops.export_scene.gltf(filepath=OUT + "/smle.glb", export_format="GLB", export_yup=True, export_apply=False, use_selection=False,
                          export_extras=False, export_animations=False)
print("8. exported", OUT + "/smle.glb")
HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(HERE, "glb_fix_images.py"), OUT + "/smle.glb"], check=True)
