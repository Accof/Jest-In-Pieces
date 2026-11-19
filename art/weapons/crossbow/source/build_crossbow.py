"""A WW1 trench-made heavy crossbow (the game's crossbow, in the old stake gun's slot).
Run: python3 build_crossbow.py <out.glb>   (Blender 5 as a Python module)

Built at real size in metres. glTF axes: +X the muzzle, +Y up, +Z the right
(Blender: +X muzzle, +Z up, -Y right). The bolt lies in the groove on the bore
line y = 0, its nock at the rolling nut (x = NUT_X), its point at the front.

Parts (separate nodes, so the game can move them):
  Tiller     walnut stock: butt, wrist, pistol grip, fore-end, prod block; steel
             rails either side of the bolt groove; brass furniture; sights
  ProdL/R    a leaf-spring prod (three steel leaves off a lorry spring), each arm
             pivoting at the prod block (the game bends them when spanned)
  Nut        brass rolling nut that holds the string (turns when loosed)
  Trigger    the long steel trigger lever under the stock
  Lever      the spanning lever: two side bars pivoting on the stock and a
             cross-handle; stowed forward along the fore-end, swung back over the
             top to drag the string onto the nut
  Stirrup    iron foot loop at the front
Markers: NockRest (string on the nut), StringFree (string loosed, at the prod),
TipL/TipR (string ends, children of ProdL/R), SightRear, SightFront, Muzzle,
LeverPivot, LeverHandle (child of Lever), BoltNock.
Materials (named for the game to dress): Wood, Steel, Brass, Iron, Cord.
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix

OUT = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
COL = bpy.context.scene.collection
MATS = {}
def mat(name, rgb, rough, metal):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        MATS[name] = m
    return MATS[name]
WOOD = mat("Wood", (0.30, 0.16, 0.08), 0.6, 0.0)
STEEL = mat("Steel", (0.20, 0.20, 0.21), 0.45, 0.8)
BRASS = mat("Brass", (0.55, 0.40, 0.17), 0.35, 0.9)
IRON = mat("Iron", (0.12, 0.11, 0.10), 0.6, 0.7)
CORD = mat("Cord", (0.42, 0.36, 0.26), 0.9, 0.0)

NUT_X = -0.115
PROD_X = 0.29
SPAN = 0.32          # half-span of the prod
RIGHT = Vector((0, -1, 0))

def obj(name, bm, material, parent=None, origin=Vector()):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    COL.objects.link(o)
    if parent:
        o.parent = parent
    return o

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name; o.data.name = name
    return o

def loft(sections, ring=16, cap=True):
    """sections: list of (x, cy, cz, half_w(y-dir/right), half_h(z), round 0..1)
    -> a closed lofted solid along X with rounded-rect cross sections."""
    bm = bmesh.new()
    rings = []
    for (x, cy, cz, hw, hh, rnd) in sections:
        vs = []
        for k in range(ring):
            a = 2 * math.pi * k / ring
            c, s = math.cos(a), math.sin(a)
            # superellipse: rnd 1 = ellipse, 0 = near box
            e = 2.0 / (1.0 + 3.0 * (1 - rnd)) if rnd < 1 else 1.0
            px = math.copysign(abs(c) ** e, c) * hw
            pz = math.copysign(abs(s) ** e, s) * hh
            vs.append(bm.verts.new((x, cy + px, cz + pz)))
        rings.append(vs)
    for i in range(len(rings) - 1):
        for k in range(ring):
            a, b = rings[i][k], rings[i][(k + 1) % ring]
            c, d = rings[i + 1][(k + 1) % ring], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return bm

def loft_path(points, hw, hh, ring=12, rnd=1.0):
    """A solid swept along a 3D polyline (Vector list), cross-section in the plane
    normal to the path: hw along `side` (horizontal), hh vertical."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        t = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1))
        side = t.cross(up)
        if side.length < 1e-4:
            side = Vector((0, 1, 0))
        side.normalize()
        upv = side.cross(t).normalized()
        w = hw(i / (len(points) - 1)) if callable(hw) else hw
        h = hh(i / (len(points) - 1)) if callable(hh) else hh
        vs = []
        for k in range(ring):
            a = 2 * math.pi * k / ring
            c, s = math.cos(a), math.sin(a)
            e = 2.0 / (1.0 + 3.0 * (1 - rnd)) if rnd < 1 else 1.0
            px = math.copysign(abs(c) ** e, c) * w
            pz = math.copysign(abs(s) ** e, s) * h
            vs.append(bm.verts.new(p + side * px + upv * pz))
        rings.append(vs)
    for i in range(len(rings) - 1):
        for k in range(ring):
            a, b = rings[i][k], rings[i][(k + 1) % ring]
            c, d = rings[i + 1][(k + 1) % ring], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return bm

def box(cx, cy, cz, sx, sy, sz, bevel=0.002):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, affect="EDGES")
    return bm

def cyl(p, axis, r, length, segs=16, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=length)
    q = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized())
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=q.to_matrix())
    bmesh.ops.translate(bm, vec=p, verts=bm.verts)
    return bm

def torus_arc(center, r_major, r_minor, a0, a1, plane="XZ", segs=24, ring=10):
    pts = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        if plane == "XZ":
            pts.append(Vector(center) + Vector((math.cos(a) * r_major, 0, math.sin(a) * r_major)))
        else:   # XY
            pts.append(Vector(center) + Vector((math.cos(a) * r_major, math.sin(a) * r_major, 0)))
    return loft_path(pts, r_minor, r_minor, ring)

# --- the tiller -----------------------------------------------------------------
# stations: x, centre y, centre z, half width, half height, roundness
tiller_secs = [
    (-0.455, 0, -0.085, 0.020, 0.052, 0.55),   # butt
    (-0.44, 0, -0.082, 0.022, 0.058, 0.5),
    (-0.38, 0, -0.072, 0.022, 0.050, 0.55),
    (-0.31, 0, -0.050, 0.019, 0.036, 0.7),     # comb
    (-0.25, 0, -0.030, 0.0165, 0.024, 0.8),    # wrist
    (-0.20, 0, -0.024, 0.017, 0.022, 0.75),
    (-0.13, 0, -0.024, 0.020, 0.024, 0.55),    # lock
    (-0.06, 0, -0.024, 0.020, 0.024, 0.5),
    (0.05, 0, -0.024, 0.019, 0.023, 0.55),     # fore-end
    (0.18, 0, -0.025, 0.018, 0.022, 0.6),
    (0.245, 0, -0.026, 0.022, 0.026, 0.5),
    (0.27, 0, -0.026, 0.030, 0.030, 0.35),     # prod block
    (0.33, 0, -0.026, 0.030, 0.030, 0.35),
    (0.36, 0, -0.026, 0.026, 0.026, 0.5),
]
parts = [obj("tiller_body", loft(tiller_secs, 20), WOOD)]
# pistol grip under the wrist, raked back
grip_pts = [Vector((-0.175, 0, -0.035)), Vector((-0.19, 0, -0.07)), Vector((-0.208, 0, -0.105)), Vector((-0.226, 0, -0.14)), Vector((-0.238, 0, -0.163))]
parts.append(obj("grip", loft_path(grip_pts, lambda t: 0.0155 + 0.002 * math.sin(t * math.pi), lambda t: 0.021 + 0.003 * math.sin(t * math.pi), 16, 0.85), WOOD))
parts.append(obj("grip_cap", cyl((-0.239, 0, -0.166), (0.3, 0, -1), 0.017, 0.006, 16), BRASS))
# butt plate, steel rails beside the bolt groove, brass lock plates, sling-less
parts.append(obj("butt_plate", box(-0.457, 0, -0.085, 0.006, 0.044, 0.108, 0.002), IRON))
for s in (-1, 1):
    parts.append(obj("rail", box(0.12, s * 0.0085, 0.002, 0.48, 0.004, 0.006, 0.0008), STEEL))
    parts.append(obj("lockplate", box(-0.095, s * 0.0205, -0.02, 0.11, 0.003, 0.034, 0.001), BRASS))
    for x in (-0.135, -0.055):
        parts.append(obj("screw", cyl((x, s * 0.0222, -0.02), (0, 1, 0), 0.0042, 0.002, 10), STEEL))
# the bolt clip: a sprung steel tongue holding the bolt down in front of the nut
parts.append(obj("clip", box(-0.02, 0, 0.012, 0.06, 0.006, 0.002, 0.0006), STEEL))
parts.append(obj("clip_post", box(-0.052, 0, 0.006, 0.006, 0.01, 0.012, 0.0008), STEEL))
# lever pivot bosses and the stirrup lugs
for s in (-1, 1):
    parts.append(obj("boss", cyl((0.02, s * 0.022, -0.016), (0, 1, 0), 0.009, 0.006, 14), STEEL))
# trigger guard: a bent steel strap round the trigger
guard = [Vector((-0.07, 0, -0.048)), Vector((-0.09, 0, -0.078)), Vector((-0.13, 0, -0.088)), Vector((-0.165, 0, -0.078)), Vector((-0.176, 0, -0.05))]
parts.append(obj("guard", loft_path(guard, 0.004, 0.0022, 8, 0.6), STEEL))
# prod block straps (U-bolts) and the clamp plate
for x in (0.275, 0.325):
    ub = [Vector((x, -0.035, 0.012)), Vector((x, -0.035, -0.06)), Vector((x, 0.035, -0.06)), Vector((x, 0.035, 0.012))]
    parts.append(obj("ubolt", loft_path(ub, 0.0035, 0.0035, 10), IRON))
parts.append(obj("clamp", box(0.30, 0, -0.062, 0.07, 0.078, 0.008, 0.0015), IRON))
# sights: a peep on a post at the back of the lock, a blade on the prod block
parts.append(obj("peep_post", box(-0.17, 0, 0.012, 0.008, 0.006, 0.05, 0.001), STEEL))
peep = cyl((-0.17, 0, 0.042), (1, 0, 0), 0.008, 0.003, 18)
ring_o = obj("peep_ring", peep, STEEL)
# the peep's hole, cut in the ring alone (a boolean on the whole joined stock eats parts of it)
hole = bpy.data.objects.new("hole", bpy.data.meshes.new("hole"))
bmh = cyl((-0.17, 0, 0.042), (1, 0, 0), 0.0042, 0.02, 18); bmh.to_mesh(hole.data); bmh.free()
COL.objects.link(hole)
md = ring_o.modifiers.new("hole", "BOOLEAN"); md.operation = "DIFFERENCE"; md.object = hole; md.solver = "EXACT"
bpy.context.view_layer.objects.active = ring_o
bpy.ops.object.modifier_apply(modifier="hole")
bpy.data.objects.remove(hole)
parts.append(ring_o)
parts.append(obj("front_blade", box(0.345, 0, 0.022, 0.012, 0.0025, 0.046, 0.0006), STEEL))
for s in (-1, 1):
    parts.append(obj("front_ear", box(0.345, s * 0.009, 0.016, 0.016, 0.003, 0.036, 0.0008), STEEL))
tiller = join(parts, "Tiller")

# --- the prod: three leaves off a lorry spring ------------------------------------
def prod_arm(side):
    """side +1: the rifle's right (Blender -Y). Pivot at the block."""
    sgn = side
    arm = bpy.data.objects.new("Prod" + ("R" if side > 0 else "L"), None)
    COL.objects.link(arm)
    arm.location = (PROD_X, -sgn * 0.03, -0.004)
    leaves = []
    for li, (length, thick, back) in enumerate([(SPAN, 0.0075, 0.0), (SPAN * 0.74, 0.0065, 0.0075), (SPAN * 0.46, 0.006, 0.014)]):
        pts = []
        n = 18
        for i in range(n + 1):
            u = i / n
            y = 0.03 + (length - 0.03) * u
            x = PROD_X + 0.055 * (y / SPAN) ** 2 - back       # curving forward toward the tips
            pts.append(Vector((x, -sgn * y, -0.004)) - arm.location)
        width = lambda t, li=li: 0.0145 - 0.004 * t * (1 if li == 0 else 0.6)
        bm = loft_path(pts, lambda t, th=thick: th * 0.5, width, 8, 0.15)
        leaves.append(obj("leaf%d%s" % (li, "R" if side > 0 else "L"), bm, STEEL))
    # the string's eye at the tip: a small curled end
    tip = Vector((PROD_X + 0.055 + 0.004, -sgn * (SPAN - 0.004), -0.004)) - arm.location
    leaves.append(obj("eye", torus_arc(tip, 0.006, 0.0025, 0, 2 * math.pi, "XZ", 12, 8), STEEL))
    a = join(leaves, "ProdArm" + ("R" if side > 0 else "L"))
    a.parent = arm
    t = bpy.data.objects.new("Tip" + ("R" if side > 0 else "L"), None)
    COL.objects.link(t); t.parent = arm
    t.location = Vector((PROD_X + 0.052, -sgn * (SPAN - 0.006), 0.0)) - arm.location
    return arm
prod_r = prod_arm(1)
prod_l = prod_arm(-1)

# --- the rolling nut, the trigger, the stirrup ------------------------------------
nut = bpy.data.objects.new("Nut", None); COL.objects.link(nut)
nut.location = (NUT_X, 0, -0.002)
bmn = cyl((0, 0, 0), (0, 1, 0), 0.0165, 0.016, 24)
# the notch the string sits in and the slot for the bolt's nock
nn = obj("nutbody", bmn, BRASS)
nn.parent = nut
trig = bpy.data.objects.new("Trigger", None); COL.objects.link(trig)
trig.location = (-0.085, 0, -0.04)
tl = [Vector((0.0, 0, 0)), Vector((-0.02, 0, -0.012)), Vector((-0.045, 0, -0.03)), Vector((-0.06, 0, -0.04))]
tt = obj("trig", loft_path(tl, 0.0028, 0.0045, 8, 0.6), STEEL); tt.parent = trig
stir = obj("Stirrup", torus_arc((0.376, 0, -0.022), 0.045, 0.0055, -math.pi * 0.62, math.pi * 0.62, "XY", 28, 10), IRON)

# --- the spanning lever -------------------------------------------------------------
lever = bpy.data.objects.new("Lever", None); COL.objects.link(lever)
lever.location = (0.02, 0, -0.016)            # on the pivot bosses
lparts = []
L = 0.265
for s in (-1, 1):
    bar = [Vector((0.0, s * 0.0275, 0)), Vector((0.08, s * 0.0285, -0.006)), Vector((0.18, s * 0.03, -0.012)), Vector((L, s * 0.03, -0.014))]
    lparts.append(obj("bar", loft_path(bar, 0.0035, 0.007, 8, 0.4), STEEL))
    # the claw: a short hooked arm behind the pivot that takes the string
    claw = [Vector((0.0, s * 0.0275, 0)), Vector((-0.03, s * 0.026, 0.02)), Vector((-0.036, s * 0.024, 0.034))]
    lparts.append(obj("claw", loft_path(claw, 0.003, 0.0045, 8, 0.4), STEEL))
lparts.append(obj("handle", cyl((L, 0, -0.014), (0, 1, 0), 0.008, 0.07, 14), WOOD))
lv = join(lparts, "LeverBars"); lv.parent = lever
lh = bpy.data.objects.new("LeverHandle", None); COL.objects.link(lh); lh.parent = lever; lh.location = (L, 0, -0.014)

# --- markers --------------------------------------------------------------------------
def marker(name, p, parent=None):
    e = bpy.data.objects.new(name, None); COL.objects.link(e)
    e.location = p
    if parent:
        e.parent = parent
    return e
marker("NockRest", (NUT_X + 0.004, 0, 0.004))
marker("StringFree", (PROD_X + 0.045, 0, 0.004))
marker("BoltNock", (NUT_X + 0.006, 0, 0.004))
marker("SightRear", (-0.17, 0, 0.042))
marker("SightFront", (0.345, 0, 0.044))
marker("Muzzle", (0.40, 0, 0.004))
marker("LeverPivot", (0.02, 0, -0.016))

for o in bpy.data.objects:
    if o.type == "MESH":
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        o.select_set(False)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_animations=False)
print("tris", sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH"))
