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
for o in (gun, drum):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/mp18.blend")
V = np.array([gun.matrix_world @ v.co for v in gun.data.vertices])
print("body bounds (m)", V.min(0).round(3), V.max(0).round(3))
print("bore z %.4f m, muzzle x %.4f m, drum pivot %s, drum out along %s" % (BORE_Z * SCALE, MUZZLE_X * SCALE, tuple(round(c, 4) for c in cut), tuple(round(c, 3) for c in CUT_N)))
for img in bpy.data.images:
    if img.size[0] > 2048: img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT + "/mp18.glb", export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90, export_yup=True, export_apply=True)
subprocess.run([sys.executable, os.path.join(HERE, "glb_fix_images.py"), OUT + "/mp18.glb"], check=True)
