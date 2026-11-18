"""Builds the game's SMLE Mk III from "Lee Enfield MKIII" by Giuliano.Sgroi (Sketchfab,
CC-BY-4.0: credit in CREDITS.txt beside the model). The source glTF is untouched.
Run: python3 build_smle_sk.py <scene.gltf> <outdir>   (Blender 5 as a Python module)
Removes the bayonet, the sling and the loose display round (the empty sling swivels
stay, as on a real rifle). Turns it to the game's axes (+X muzzle, +Z up, -Y the
rifle's right; glTF +Z right), scales it to 1132 mm, splits the bolt into Bolt (slides)
> BoltTurn (turns about the bore) and CockingPiece, and adds the markers the game reads."""
import bpy, bmesh, math, sys, os, subprocess, numpy as np
from mathutils import Vector, Matrix
SRC, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
parts = {o.data.materials[0].name: o for o in bpy.data.objects if o.type == "MESH"}
for n in ("Bayonet", "Strap", "Ammo"):
    bpy.data.objects.remove(parts.pop(n))
for o in parts.values():                      # flatten Sketchfab's wrapper empties: the game reads root-level positions
    m = o.matrix_world.copy(); o.parent = None; o.matrix_world = m
for o in [o for o in bpy.data.objects if o.type == "EMPTY"]:
    bpy.data.objects.remove(o)
print("1. removed the bayonet, the sling and the loose round")

# 2. source units -> metres on the game's axes: muzzle (source -Y) to +X, the rifle's
# right (source -X) to -Y; the whole rifle (bayonet off) is 15.034 source units
L_SRC = 15.034
S = 1.132 / L_SRC
# then shifted so the bore (bolt axis) sits 0.1917 up on the centre line and the charger
# bridge where the game's rifle always had it, so the hands and reload paths still line up
SHIFT = Vector((-0.0033, 0.0014, 0.1143))
XF = Matrix.Translation(SHIFT) @ Matrix.Scale(S, 4) @ Matrix.Rotation(math.pi / 2, 4, "Z")
def P(x, y, z):                       # a source point, in the game's metres
    return XF @ Vector((x, y, z))
for o in parts.values():
    o.data.transform(o.matrix_world); o.matrix_world = Matrix()
    o.data.transform(XF)

# 3. the bolt: the Mechanic part's biggest piece is the bolt (body, head, root, handle,
# knob); the three small pieces behind it are the cocking piece
mech = parts.pop("Mechanic")
bm = bmesh.new(); bm.from_mesh(mech.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
bm.faces.ensure_lookup_table()
seen, isl = set(), []
for f in bm.faces:
    if f.index in seen: continue
    st, comp = [f], []
    seen.add(f.index)
    while st:
        g = st.pop(); comp.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h.index not in seen: seen.add(h.index); st.append(h)
    isl.append(comp)
isl.sort(key=len, reverse=True)
bolt_faces = set(isl[0])
AXIS_Y, AXIS_Z = P(-0.019, 0, 1.028).y, P(-0.019, 0, 1.028).z          # the bolt's (and bore's) axis
ROOT_X = P(0, 3.40, 0).x                                               # the pivot: on the axis at the handle's root
BOLT_ORIGIN = Vector((ROOT_X, AXIS_Y, AXIS_Z))
def split(keep, name):
    b = bm.copy()
    b.faces.ensure_lookup_table()
    drop = [b.faces[f.index] for f in bm.faces if (f in bolt_faces) != keep]
    bmesh.ops.delete(b, geom=drop, context="FACES")
    me = bpy.data.meshes.new(name); b.to_mesh(me); b.free()
    me.transform(Matrix.Translation(-BOLT_ORIGIN))
    me.materials.append(mech.data.materials[0])
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o
bolt = bpy.data.objects.new("Bolt", None); bpy.context.scene.collection.objects.link(bolt)
bolt.location = BOLT_ORIGIN; bolt.empty_display_size = 0.01
turn = split(True, "BoltTurn"); turn.parent = bolt
cock = split(False, "CockingPiece"); cock.parent = bolt
TV = np.array([v.co[:] for v in turn.data.vertices]) + np.array(BOLT_ORIGIN[:])
knob_pts = TV[TV[:, 1] < TV[:, 1].min() + 0.012]                        # the knob: the part furthest right
KNOB = Vector(knob_pts.mean(0))
bm.free(); bpy.data.objects.remove(mech)
print("3. bolt: %d faces turning, %d in the cocking piece; axis at height %.4f m; knob %s" % (
    len(turn.data.polygons), len(cock.data.polygons), AXIS_Z, tuple(round(c, 4) for c in KNOB)))

# 4. the rest is one Body (wood, metal, magazine: their own materials)
bpy.ops.object.select_all(action="DESELECT")
for o in parts.values(): o.select_set(True)
bpy.context.view_layer.objects.active = parts["Metal"]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"; body.data.name = "Body"
BV = np.array([v.co[:] for v in body.data.vertices])
print("4. body: length %.3f m, %d polygons, materials %s" % (np.ptp(BV[:, 0]), len(body.data.polygons), [m.name for m in body.data.materials]))

# 5. the markers the game reads (measured on the source: the rear sight's U notch,
# shoulders 1.5048 high at -0.97; the foresight blade's tip 1.4409 at -6.527; the
# muzzle's face at -6.916, centre 0.853)
def marker(name, p, parent=None):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.location = p; e.empty_display_size = 0.005
    if parent: e.parent = parent; e.location = p - parent.location
    return e
# the charger bridge: the highest metal over the bolt-way between the magazine's ends
mag_lo, mag_hi = P(0, 2.543, 0).x, P(0, 1.272, 0).x
over = BV[(BV[:, 0] > mag_lo - 0.02) & (BV[:, 0] < mag_hi) & (np.abs(BV[:, 1] - AXIS_Y) < 0.004) & (BV[:, 2] > AXIS_Z + 0.006)]
bridge_x = float(over[np.argmax(over[:, 2]), 0]) if len(over) else mag_lo
bridge_top = float(over[:, 2].max()) if len(over) else AXIS_Z + 0.015
marker("Muzzle", Vector((P(0, -6.916, 0).x, AXIS_Y, AXIS_Z)))      # the bore exits on the bolt axis
marker("SightRear", P(0, -0.969, 1.4714))      # the bottom of the U notch, where the blade tip sits
marker("SightFront", P(0, -6.527, 1.4409))
marker("Ejection", Vector((P(0, 2.0, 0).x, AXIS_Y - 0.009, AXIS_Z + 0.006)))
marker("ChargerGuide", Vector((bridge_x + 0.0015, AXIS_Y, bridge_top)))
marker("MagMouth", Vector(((mag_lo + mag_hi) / 2, AXIS_Y, AXIS_Z - 0.006)))
marker("Knob", KNOB, bolt)
print("5. charger bridge at x %.4f, top %.4f; magazine x %.4f..%.4f" % (bridge_x, bridge_top, mag_lo, mag_hi))

# 6. export: textures to 2K, re-encoded as plain JPEGs for Godot
for o in (body, turn, cock):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40), keep_sharp_edges=True)
for img in bpy.data.images:
    if img.size[0] > 2048: img.scale(2048, 2048)
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/smle.blend")
bpy.ops.export_scene.gltf(filepath=OUT + "/smle.glb", export_format="GLB", export_yup=True, export_animations=False)
subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "glb_fix_images.py"), OUT + "/smle.glb"], check=True)
print("6. exported", OUT + "/smle.glb")
