"""Build the enemy rifle (the WitzSoldat's bolt-action) from its Tripo model.

Run with Blender's Python (`pip install bpy`, or blender --background --python):
    python3 tools/build_enemy_rifle.py <abs tripo.glb> <abs out dir>

Writes into <out dir>:
  enemy_rifle.glb    the rifle, butt plate at the origin, barrel along +Z (the
                     muzzle end), +Y up, the bore axis on x = 0 at y = BORE_Y:
                     the frame Clown.give_rifle() laid the old box rifle out in.
                     Two objects: "Body" (everything but the bolt handle) and
                     "Bolt" (the handle and its knob), the latter with its
                     origin on the bore axis at the handle's root, so a turn
                     about its local Z lifts the handle and a shift along Z
                     draws it back. The model's own PBR maps.
  enemy_rifle.json   what the game needs to hold it: the muzzle, the trigger,
                     the wrist of the stock (where the right hand goes), the
                     fore-end's underside (the left hand), the bolt handle's
                     root and knob, the stock's half-width at the wrist, the
                     collision box.

Scale: Tripo's model is 1.04 m end to end; it is scaled to LENGTH (a Mauser
Karabiner 98's 1.11 m). Its bore axis is found as the barrel's centre line in
the front third; the whole model is turned so that axis is +Z and the rifle
is upright (the stock's drop hangs at -Y).
"""
import json
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

SRC, OUT = sys.argv[-2:]
LENGTH = 1.11            # m, butt plate to muzzle
BORE_Y = 0.025           # the bore axis above the rifle's origin (the old layout's)

# --- import --------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(objs) == 1, objs
body = objs[0]
body.name = "Body"
bpy.context.view_layer.objects.active = body
body.select_set(True)
# bake the node transform into the mesh
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = body.data
mat = me.materials[0]
mat.name = "Rifle"

# Blender (x, y, z) -> game frame G (x, up, fwd): G = (bx, bz, -by)
def to_g(v):
    return np.array([v.x, v.z, -v.y])


def from_g(g):
    return Vector((g[0], -g[2], g[1]))


V = np.array([to_g(v.co) for v in me.vertices])
print("source verts", len(V), "bounds", V.min(0), V.max(0))

# --- find the bore axis and turn the rifle onto it -----------------------------------
# the long axis in the ground plane (x, z) by PCA
xz = V[:, [0, 2]]
c = xz.mean(0)
u, s, vt = np.linalg.svd(xz - c, full_matrices=False)
ax = vt[0]
ang = math.atan2(ax[0], ax[1])          # yaw that brings `ax` onto +z
R = np.array([[math.cos(ang), 0, -math.sin(ang)], [0, 1, 0], [math.sin(ang), 0, math.cos(ang)]])
W = (V - np.array([c[0], 0, c[1]])) @ R.T
# the muzzle is the thin end: compare the section heights at the two ends
zmin, zmax = W[:, 2].min(), W[:, 2].max()
h_lo = np.ptp(W[np.abs(W[:, 2] - (zmin + 0.03)) < 0.015, 1])
h_hi = np.ptp(W[np.abs(W[:, 2] - (zmax - 0.03)) < 0.015, 1])
if h_lo < h_hi:
    # muzzle at -z: turn it round (about y)
    W[:, 0] *= -1
    W[:, 2] *= -1
    R = np.diag([-1, 1, -1]) @ R
    zmin, zmax = -zmax, -zmin
print("length (source units) %.3f" % (zmax - zmin))
scale = LENGTH / (zmax - zmin)
W *= scale
zmin, zmax = W[:, 2].min(), W[:, 2].max()
W[:, 2] -= zmin                                       # butt plate at z = 0
# the bore: the barrel's centre in the front third (clear of the stock and bands)
front = W[(W[:, 2] > LENGTH * 0.72) & (W[:, 2] < LENGTH * 0.94)]
# the barrel is the densest ring: take the median of its y and x
bore_y = float(np.median(front[:, 1]))
bore_x = float(np.median(front[:, 0]))
W[:, 0] -= bore_x
W[:, 1] += BORE_Y - bore_y
print("bore found at x %.4f y %.4f (source scaled); now x 0, y %.3f" % (bore_x, bore_y, BORE_Y))
# the model's roll: the stock's drop should hang straight down; the bolt
# handle sticks out to -x (the shooter's right). Check the handle's side.
rec = W[(W[:, 2] > 0.28) & (W[:, 2] < 0.42)]
x_lo, x_hi = rec[:, 0].min(), rec[:, 0].max()
print("receiver x extent %.3f .. %.3f" % (x_lo, x_hi))
if abs(x_hi) > abs(x_lo):
    # the handle is on +x: mirror x (and keep handedness by mirroring z as well
    # would turn the muzzle; instead rotate 180 about z: x -> -x, y -> -y, then
    # the stock would hang up - so a true mirror in x it is, which is fine for
    # a rifle: it becomes its mirror image, a left-handed rifle made right)
    W[:, 0] *= -1
    MIRRORED = True
else:
    MIRRORED = False
print("mirrored in x:", MIRRORED)

# write the frame back into the mesh
for v, g in zip(me.vertices, W):
    v.co = from_g(g)
if MIRRORED:
    # a mirror flips the winding: put it back
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
me.update()

# --- the features --------------------------------------------------------------------
def slab(z0, z1):
    return W[(W[:, 2] >= z0) & (W[:, 2] < z1)]


# stock half-width and the bottom line along the rifle, in 1 cm steps
prof = []
for z0 in np.arange(0.0, LENGTH, 0.01):
    s = slab(z0, z0 + 0.01)
    if len(s) < 3:
        prof.append((z0, None))
        continue
    prof.append((z0, dict(bottom=float(s[:, 1].min()), top=float(s[:, 1].max()), x_lo=float(s[:, 0].min()), x_hi=float(s[:, 0].max()))))

# the bolt handle: what sticks out past the receiver's side on -x, in the
# rear half, above the stock's bottom
stock_half = float(np.percentile(np.abs(W[(W[:, 2] > 0.5) & (W[:, 2] < 0.8), 0]), 97))
print("stock half-width (fore-end) %.3f" % stock_half)
handle_mask = (W[:, 0] < -(stock_half + 0.012)) & (W[:, 2] > 0.2) & (W[:, 2] < 0.6) & (W[:, 1] > BORE_Y - 0.03)
H = W[handle_mask]
assert len(H) > 20, "no bolt handle found on -x"
handle_z = float(np.median(H[:, 2]))
knob = H[H[:, 0].argmin()]
print("bolt handle: z %.3f, knob at %s, %d verts" % (handle_z, knob.round(3), len(H)))
bolt_root = np.array([0.0, BORE_Y, handle_z])

# the trigger guard: the lowest structure under the receiver just behind the
# handle (a Mauser's trigger sits under the bolt handle); the trigger blade
# is inside it, toward its front
g = slab(handle_z - 0.08, handle_z + 0.03)
guard_bottom = float(g[:, 1].min())
# the guard's z range: slices whose bottom is within 2 cm of the lowest
gz = [z0 for (z0, p) in prof if p and handle_z - 0.1 < z0 < handle_z + 0.05 and p["bottom"] < guard_bottom + 0.02]
guard_z0, guard_z1 = min(gz), max(gz) + 0.01
# the stock's underside just behind the guard (the wrist's belly)
behind = [p["bottom"] for (z0, p) in prof if p and guard_z0 - 0.06 < z0 < guard_z0 - 0.01]
wrist_belly = float(np.median(behind)) if behind else guard_bottom + 0.04
trigger = np.array([0.0, guard_bottom + 0.6 * (wrist_belly - guard_bottom), guard_z0 + 0.35 * (guard_z1 - guard_z0)])
print("trigger guard z %.3f..%.3f bottom %.3f; trigger at %s" % (guard_z0, guard_z1, guard_bottom, trigger.round(3)))

# the wrist of the stock: 6-10 cm behind the trigger, its section's centre
wz = trigger[2] - 0.085
ws = slab(wz - 0.015, wz + 0.015)
wrist = np.array([0.0, float((ws[:, 1].min() + ws[:, 1].max()) * 0.5), wz])
wrist_half = float(np.percentile(np.abs(ws[:, 0]), 95))
wrist_h = float(ws[:, 1].max() - ws[:, 1].min())
print("wrist at %s, half-width %.3f, height %.3f" % (wrist.round(3), wrist_half, wrist_h))

# the fore-end's underside: the stock's bottom line ahead of the magazine
fore = {}
for zf in (0.5, 0.55, 0.6, 0.65, 0.7):
    s = slab(zf - 0.02, zf + 0.02)
    fore["%.2f" % zf] = [0.0, float(s[:, 1].min()), zf]
print("fore-end bottoms", fore)
muzzle = [0.0, BORE_Y, float(W[:, 2].max())]
butt_h = float(np.ptp(slab(0.0, 0.03)[:, 1]))
box = dict(size=[2 * stock_half + 0.01, butt_h, LENGTH], centre=[0.0, float(slab(0.0, 0.03)[:, 1].mean()), LENGTH * 0.5])

# --- cut the bolt handle into its own object -----------------------------------------
def is_handle_face(f):
    for v in f.verts:
        gg = to_g(v.co)
        if not ((gg[0] < -(stock_half + 0.004)) and (0.2 < gg[2] < 0.6) and (gg[1] > BORE_Y - 0.03)):
            return False
    return True


# the bolt is a copy of the body with everything but the handle removed (so
# its UVs, normals and material come along untouched); the body loses the
# handle's faces
bolt_me = me.copy()
bolt_me.name = "Bolt"
bm = bmesh.new()
bm.from_mesh(bolt_me)
keep = [f for f in bm.faces if is_handle_face(f)]
print("bolt handle faces", len(keep))
assert len(keep) > 10
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in set(keep)], context="FACES")
bm.to_mesh(bolt_me)
bm.free()
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if is_handle_face(f)], context="FACES")
bm.to_mesh(me)
bm.free()
bolt = bpy.data.objects.new("Bolt", bolt_me)
bpy.context.scene.collection.objects.link(bolt)
# the bolt's origin on the bore axis at the handle's root
root_bl = from_g(bolt_root)
for v in bolt_me.vertices:
    v.co -= root_bl
bolt.location = root_bl
bolt.parent = body
bolt.matrix_parent_inverse = Matrix.Identity(4)
for o in (body, bolt):
    for pg in o.data.polygons:
        pg.use_smooth = True

# --- the json --------------------------------------------------------------------------
info = dict(
    length=LENGTH, bore_y=BORE_Y, mirrored=MIRRORED,
    muzzle=muzzle, trigger=trigger.tolist(),
    wrist=wrist.tolist(), wrist_half=wrist_half, wrist_h=wrist_h,
    fore=fore, stock_half=stock_half,
    bolt_root=bolt_root.tolist(), bolt_knob=(knob - bolt_root).tolist(),
    trigger_guard=[guard_z0, guard_z1, guard_bottom],
    box=box,
)
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "enemy_rifle.json"), "w") as fh:
    json.dump(info, fh, indent=1)
print(json.dumps(info, indent=1))

# --- export ----------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bolt.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "enemy_rifle.glb"), export_format="GLB", use_selection=True,
                          export_apply=True, export_yup=True, export_image_format="AUTO", export_texcoords=True,
                          export_normals=True, export_materials="EXPORT", export_animations=False, export_skins=False)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "enemy_rifle.blend"))
print("done")
