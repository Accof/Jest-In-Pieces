# Build the refined trench shotgun from the untouched Tripo GLB.
# Blender 5.x (bpy as a Python module). Run:
#   python3 build_shotgun.py trench_shotgun_tripo_original.glb <out_dir>
# then copy <out_dir>/trench_shotgun.glb to art/weapons/trench_shotgun/.
#
# Coordinates (Blender, metres): +X muzzle, +Z up, Y across (+Y = left side).
# 1. weld, drop debris
# 2. stock 7.5% longer behind the receiver (vertex positions only, UVs untouched)
# 3. heat shield: the Tripo shell between its end bands is cut out and replaced by a
#    modelled 1.2 mm steel shield with staggered round holes, a dark barrel under it
# 4. pump: separated, lengthened 15% forward, its wood darkened in the texture;
#    a magazine tube under it to slide on
# 5. hammer spur: separated, pivot at its root
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix

SRC = sys.argv[-2] if len(sys.argv) > 2 else "/tmp/sg/src.glb"
OUT = sys.argv[-1] if len(sys.argv) > 2 else "/tmp/sg/out"
os.makedirs(OUT, exist_ok=True)

STOCK_JOINT = -0.215       # behind this, the stock is stretched
STOCK_K = 1.075
SHIELD_X = (0.086, 0.380)  # the part of the shield that is replaced
SHIELD_ARC = 128.0         # degrees either side of the top
PUMP_X = (0.060, 0.305)
PUMP_K = 1.15
MAG_Z = 0.1185             # magazine tube axis height
MAG_R = 0.0138
HAMMER_BOX = (-0.146, -0.131, 0.1745, 0.20, 0.0115)   # x0 x1 z0 z1 |y|
HERE = os.path.dirname(os.path.abspath(__file__))
PATCH = [float(x) for x in open(os.path.join(HERE, "patch.txt")).read().split()]   # plain steel square in the atlas (UV u0 v0 u1 v1)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
gun = [o for o in bpy.data.objects if o.type == "MESH"][0]
gun.name = "Body"
bpy.context.view_layer.objects.active = gun
# apply the import transform so mesh coordinates are world coordinates
bpy.ops.object.select_all(action="DESELECT"); gun.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mat_src = gun.data.materials[0]

def bm_of(o):
    bm = bmesh.new(); bm.from_mesh(o.data); return bm

def put(bm, o):
    bm.to_mesh(o.data); o.data.update(); bm.free()

# 1. weld + debris ---------------------------------------------------------------
bm = bm_of(gun)
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

# 2. stock -------------------------------------------------------------------------
n = 0
for v in bm.verts:
    if v.co.x < STOCK_JOINT:
        v.co.x = STOCK_JOINT + (v.co.x - STOCK_JOINT) * STOCK_K; n += 1
print("stock verts moved", n)

# 3a. fit the shield's axis (z centre, radius) on its top half ---------------------
pts = np.array([(v.co.y, v.co.z) for v in bm.verts if 0.13 < v.co.x < 0.33 and v.co.z > 0.14])
cz, R = 0.150, 0.022
for _ in range(3):
    ang = np.degrees(np.arctan2(pts[:, 0], pts[:, 1] - cz)); rad = np.hypot(pts[:, 0], pts[:, 1] - cz)
    outer = []
    for a in range(-120, 121, 6):
        k = np.abs(ang - a) < 3
        if k.sum(): outer.append(pts[k][rad[k].argmax()])
    o_ = np.array(outer)
    # algebraic circle fit with centre on y = 0: y^2 + (z-c)^2 = r^2
    A = np.c_[2 * o_[:, 1], np.ones(len(o_))]; b = o_[:, 0] ** 2 + o_[:, 1] ** 2
    sol = np.linalg.lstsq(A, b, rcond=None)[0]; cz = sol[0]; R = math.sqrt(sol[1] + cz * cz)
print("shield axis z %.4f radius %.4f" % (cz, R))

# 3b. cut the old shield shell out
cut = []
for f in bm.faces:
    c = f.calc_center_median()
    if not (SHIELD_X[0] < c.x < SHIELD_X[1]): continue
    r = math.hypot(c.y, c.z - cz)
    a = abs(math.degrees(math.atan2(c.y, c.z - cz)))
    if R - 0.012 < r < R + 0.006 and a < SHIELD_ARC:
        cut.append(f)
bmesh.ops.delete(bm, geom=cut, context="FACES")
print("old shield faces removed", len(cut))

# 4a. pump faces: around the magazine axis, in the pump's span, below the shield
pump_faces = []
for f in bm.faces:
    c = f.calc_center_median()
    if PUMP_X[0] < c.x < PUMP_X[1] and c.z < 0.1435 and math.hypot(c.y, c.z - MAG_Z) > 0.0165:
        pump_faces.append(f)
# 5a. hammer spur faces
x0, x1, z0, z1, yy = HAMMER_BOX
ham_faces = [f for f in bm.faces if x0 < f.calc_center_median().x < x1 and z0 < f.calc_center_median().z < z1 and abs(f.calc_center_median().y) < yy]
print("pump faces", len(pump_faces), "hammer faces", len(ham_faces))

def split_off(bm, faces, name):
    """copy faces into a new object, delete them from bm"""
    nb = bmesh.new()
    uvl = bm.loops.layers.uv.active; nuv = nb.loops.layers.uv.new("UVMap")
    vmap = {}
    for f in faces:
        vs = []
        for v in f.verts:
            if v not in vmap: vmap[v] = nb.verts.new(v.co)
            vs.append(vmap[v])
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue
        for la, lb in zip(f.loops, nf.loops): lb[nuv].uv = la[uvl].uv
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    me = bpy.data.meshes.new(name); nb.to_mesh(me); nb.free()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat_src)
    return ob

pump = split_off(bm, pump_faces, "Pump")
hammer = split_off(bm, ham_faces, "Hammer")
# close the body where the hammer came out (a dark slot is fine: real guns have one)
edges = [e for e in bm.edges if e.is_boundary and x0 - 0.004 < e.verts[0].co.x < x1 + 0.004 and e.verts[0].co.z > z0 - 0.004]
if edges: bmesh.ops.holes_fill(bm, edges=edges, sides=64)
put(bm, gun)

# 4b. pump: close its open top (it was fused to the shield), stretch it forward
pb = bm_of(pump)
PUMP_TOP = 0.1335          # just under the shield's lower edges, so it slides clear of them
for v in pb.verts:
    if v.co.z > PUMP_TOP: v.co.z = PUMP_TOP
bmesh.ops.remove_doubles(pb, verts=pb.verts, dist=0.0003)
bmesh.ops.dissolve_degenerate(pb, edges=pb.edges, dist=0.0002)
filled = bmesh.ops.holes_fill(pb, edges=[e for e in pb.edges if e.is_boundary], sides=400)
bmesh.ops.triangulate(pb, faces=filled["faces"], quad_method="BEAUTY", ngon_method="BEAUTY")
xs = [v.co.x for v in pb.verts]; prear = min(xs)
for v in pb.verts: v.co.x = prear + (v.co.x - prear) * PUMP_K
print("pump x %.3f..%.3f (was ..%.3f)" % (prear, max(v.co.x for v in pb.verts), max(xs)))
put(pb, pump)
hb = bm_of(hammer)
bmesh.ops.holes_fill(hb, edges=[e for e in hb.edges if e.is_boundary], sides=64)
put(hb, hammer)

# --- new parts ------------------------------------------------------------------------
def patch_uv(bm, mode):
    """put every face's UVs inside the plain-steel square of the atlas"""
    uvl = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    u0, v0, u1, v1 = PATCH
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            if mode == "cyl":
                s = (p.x * 7.0) % 1.0; t = (math.atan2(p.y, p.z - cz) / math.tau + 0.5)
            else:
                s = (p.x * 7.0) % 1.0; t = ((p.y + p.z) * 9.0) % 1.0
            l[uvl].uv = (u0 + (u1 - u0) * (0.1 + 0.8 * s), v0 + (v1 - v0) * (0.1 + 0.8 * t))

def tube(name, x0, x1, zc, r, segs, arc=360.0, thick=0.0):
    """an open or closed tube along X, optional arc (degrees, centred on top) and wall thickness"""
    bm = bmesh.new()
    full = arc >= 359.9
    n = segs if full else segs + 1
    def ring(x, rr):
        out = []
        for i in range(n):
            a = math.radians(-arc / 2 + arc * i / segs)
            out.append(bm.verts.new((x, rr * math.sin(a), zc + rr * math.cos(a))))
        return out
    a0, a1 = ring(x0, r), ring(x1, r)
    rings = [(a0, a1)]
    if thick > 0:
        b0, b1 = ring(x0, r - thick), ring(x1, r - thick)
    m = n if full else n - 1
    for i in range(m):
        j = (i + 1) % n
        bm.faces.new((a0[i], a0[j], a1[j], a1[i]))                       # outer
        if thick > 0:
            bm.faces.new((b0[i], b1[i], b1[j], b0[j]))                   # inner
            bm.faces.new((a0[i], b0[i], b0[j], a0[j]))                   # rear edge
            bm.faces.new((a1[i], a1[j], b1[j], b1[i]))                   # front edge
    if thick > 0 and not full:
        for (p0, p1, q0, q1) in ((a0[0], a1[0], b0[0], b1[0]), (a0[-1], a1[-1], b0[-1], b1[-1])):
            bm.faces.new((p0, q0, q1, p1))                               # the long cut edges
    if thick == 0 and full:
        bm.faces.new(list(reversed(a0))); bm.faces.new(a1)               # caps
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    patch_uv(bm, "cyl")
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob

dark = bpy.data.materials.new("BarrelDark")
dark.use_nodes = True
bsdf = dark.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.035, 0.035, 0.038, 1)
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.55

# 3c. the new shield: 1.2 mm wall, holes punched by one boolean
SX0, SX1 = SHIELD_X
shield = tube("Shield", SX0, SX1, cz, R, 64, arc=2 * SHIELD_ARC + 4, thick=0.0012)
shield.data.materials.append(mat_src)
HOLE_R = 0.0036
ROW_DA = 0.0125 / R                                  # radians between rows (12.5 mm of arc)
COL = 0.0135
cut_bm = bmesh.new()
rows = [k for k in range(-3, 4)]
x_start = SX0 + 0.012; x_end = SX1 - 0.012
holes = 0
for k in rows:
    a = k * ROW_DA
    off = COL * 0.5 if k % 2 else 0.0
    x = x_start + off
    while x <= x_end:
        d = Vector((0, math.sin(a), math.cos(a)))
        centre = Vector((x, 0, cz)) + d * R
        res = bmesh.ops.create_cone(cut_bm, cap_ends=True, cap_tris=False, segments=16, radius1=HOLE_R, radius2=HOLE_R, depth=0.012,
                                    matrix=Matrix.Translation(centre) @ d.to_track_quat("Z", "X").to_matrix().to_4x4())
        holes += 1; x += COL
patch_uv(cut_bm, "flat")
cme = bpy.data.meshes.new("Holes"); cut_bm.to_mesh(cme); cut_bm.free()
cutter = bpy.data.objects.new("Holes", cme); bpy.context.scene.collection.objects.link(cutter)
cutter.data.materials.append(mat_src)
mod = shield.modifiers.new("holes", "BOOLEAN"); mod.operation = "DIFFERENCE"; mod.object = cutter; mod.solver = "EXACT"
bpy.context.view_layer.objects.active = shield
bpy.ops.object.select_all(action="DESELECT"); shield.select_set(True)
bpy.ops.object.modifier_apply(modifier="holes")
bpy.data.objects.remove(cutter)
print("holes", holes, "shield tris", sum(len(p.vertices) - 2 for p in shield.data.polygons))

# 3d. the barrel under it, dark
barrel = tube("BarrelInner", SX0 - 0.004, SX1 + 0.004, cz, 0.0165, 24)
barrel.data.materials.append(dark)
# 4c. the magazine tube the pump rides on (the Tripo hull had none under the pump)
mag = tube("MagTube", 0.035, 0.33, MAG_Z, MAG_R - 0.0006, 24)   # hidden inside the Tripo tube at both ends
mag.data.materials.append(mat_src)

def smooth(o, angle=40.0):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
for o in (pump, hammer):
    print(o.name, "mesh fixes:", o.data.validate(verbose=False))
for o in (shield, barrel, mag, pump, hammer): smooth(o)
# join the static new parts into the body (fewer draw calls)
bpy.ops.object.select_all(action="DESELECT")
for o in (shield, barrel, mag, gun): o.select_set(True)
bpy.context.view_layer.objects.active = gun
bpy.ops.object.join()

# pivots: pump at its own centre, hammer at its root (it tips back about Y)
def set_origin(o, p):
    me = o.data; me.transform(Matrix.Translation(-Vector(p))); o.location = Vector(p)
pv = [v.co for v in pump.data.vertices]
set_origin(pump, (sum(v.x for v in pv) / len(pv), 0.0, MAG_Z))
set_origin(hammer, ((x0 + x1) * 0.5 + 0.004, 0.0, 0.160))

# 4d. darken the pump's wood in a copy of the colour texture
from PIL import Image, ImageDraw, ImageEnhance
col_img = [i for i in bpy.data.images if i.name == "Color"][0]
col_img.filepath_raw = OUT + "/_color_src.png"; col_img.file_format = "PNG"; col_img.save()
src = Image.open(OUT + "/_color_src.png").convert("RGB")
W, H = src.size
mask = Image.new("L", (W, H), 0); dr = ImageDraw.Draw(mask)
uvl = pump.data.uv_layers.active.data
for p in pump.data.polygons:
    dr.polygon([(uvl[l].uv[0] * W, (1 - uvl[l].uv[1]) * H) for l in p.loop_indices], fill=255)
from PIL import ImageFilter
mask = mask.filter(ImageFilter.MaxFilter(5))
darker = ImageEnhance.Color(ImageEnhance.Brightness(src).enhance(0.62)).enhance(0.8)
out = Image.composite(darker, src, mask)
out.save(OUT + "/shotgun_color.jpg", quality=93)
os.remove(OUT + "/_color_src.png")
new_img = bpy.data.images.load(OUT + "/shotgun_color.jpg")
for n in mat_src.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image == col_img:
        n.image = new_img
print("pump wood darkened over %.1f%% of the atlas" % (100 * np.array(mask).astype(bool).mean()))

# smooth shading on the new round parts is in the hull already; custom normals from import stay
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/trench_shotgun.blend")
for o in bpy.data.objects: print("OBJ", o.name, len(o.data.polygons), tuple(round(c, 3) for c in o.location))
for img in bpy.data.images:
    if img.size[0] > 2048: img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT + "/trench_shotgun.glb", export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90, export_yup=True, export_apply=True)
# Godot's JPEG decoder rejects some JPEGs Blender writes: re-encode them with PIL
import subprocess
subprocess.run([sys.executable, os.path.join(HERE, "glb_fix_images.py"), OUT + "/trench_shotgun.glb"], check=True)
