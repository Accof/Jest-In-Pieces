"""Build Der Klappersoldat's game body from the Tripo model.

Run with Blender's Python (`pip install bpy`, or blender --background --python):
    python3 tools/build_klappersoldat.py <tripo.glb> <witzsoldat.blend> <out dir>

Writes into <out dir>:
  klappersoldat.glb       skinned body on the shared 21-bone skeleton
  klappersoldat_gibs.glb  one mesh per dismemberment segment (Gib_<Segment>)
  klappersoldat.json      segments, rest box, eye positions (Godot axes)
  klappersoldat.blend     the working file, for hand fixes

Same conventions as the clown and the WitzSoldat (see clown_segments.json):
- Bones: the WitzSoldat rig's names, hierarchy and rolls, moved to this
  model's joints (measured from its T-pose: neck, shoulders, elbows,
  wrists, crotch, knees, ankles).
- Segments: 15 ids in the second UV map "SegmentID" (u = (id + 0.5) / 16,
  v = 0.5, or 0.25 for a stump cap).
- Rest pose: each vertex's rest position in Godot axes, normalised to the
  rest box, in the colour attribute "RestPos".
- Stumps: the mesh is cut cleanly at every severable joint and each cut gets
  a cap fitted to its cross-section ("Gore" material) with a brass core
  ("BoneCore"), labelled with the child segment so the shader shows it only
  once that part is gone. Gibs carry caps at both ends.
- Weights: at most two bones a vertex, blended across each joint.
"""
import json
import math
import sys

import bpy  # first: bmesh and mathutils come with it
import bmesh
import mathutils
from mathutils import Vector

SRC, WITZ, OUT = sys.argv[-3:]
HEIGHT = 1.91

SEGMENTS = ["Pelvis", "Torso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg",
            "LeftFoot", "RightUpperArm", "RightLowerArm", "RightHand", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
SEG = {n: i for i, n in enumerate(SEGMENTS)}
SEGMENT_BONE = {"Pelvis": "Hips", "Torso": "Spine", "Head": "Neck"}

# --- joints (Blender axes: +X the model's left, -Y forward, +Z up), metres ----
NECK_CUT = 1.63        # head comes off here (the narrowest point of the neck)
WAIST = 1.08           # pelvis / torso
SHOULDER_X = 0.24      # arm comes off here
ELBOW_X = 0.49
WRIST_X = 0.725
ARM_Z = 1.43
ARM_Y = 0.05
CROTCH = 0.685         # legs come off here (just below where they part)
KNEE_Z = 0.55
ANKLE_Z = 0.13
ARM_MIN_Z = 1.25       # below this nothing is arm

BONES = {
    "Hips": ((0, 0.02, 0.95), (0, 0.02, WAIST)),
    "Spine": ((0, 0.02, WAIST), (0, 0.02, 1.26)),
    "Chest": ((0, 0.02, 1.26), (0, 0.02, 1.56)),
    "Neck": ((0, 0.02, 1.56), (0, 0.01, NECK_CUT)),
    "Head": ((0, 0.01, NECK_CUT), (0, 0.01, 1.9)),
    "LeftShoulder": ((0.03, 0.02, 1.47), (SHOULDER_X, ARM_Y, ARM_Z)),
    "LeftUpperArm": ((SHOULDER_X, ARM_Y, ARM_Z), (ELBOW_X, ARM_Y, ARM_Z)),
    "LeftLowerArm": ((ELBOW_X, ARM_Y, ARM_Z), (WRIST_X, 0.045, 1.425)),
    "LeftHand": ((WRIST_X, 0.045, 1.425), (0.9, 0.04, 1.41)),
    "LeftUpperLeg": ((0.11, 0.03, 0.93), (0.17, 0.035, KNEE_Z)),
    "LeftLowerLeg": ((0.17, 0.035, KNEE_Z), (0.195, 0.06, ANKLE_Z)),
    "LeftFoot": ((0.195, 0.06, ANKLE_Z), (0.205, -0.09, 0.04)),
    "LeftToes": ((0.205, -0.09, 0.04), (0.205, -0.17, 0.04)),
}
for name in list(BONES):
    if name.startswith("Left"):
        h, t = BONES[name]
        BONES["Right" + name[4:]] = ((-h[0], h[1], h[2]), (-t[0], t[1], t[2]))

PARENT_SEG = {"UpperArm": "Torso", "LowerArm": "UpperArm", "Hand": "LowerArm",
              "UpperLeg": "Pelvis", "LowerLeg": "UpperLeg", "Foot": "LowerLeg", "Head": "Torso"}


def seg_of(p: Vector) -> str:
    side = "Left" if p.x > 0 else "Right"
    ax = abs(p.x)
    if p.z >= NECK_CUT and ax < 0.2:
        return "Head"
    if ax >= SHOULDER_X and p.z > ARM_MIN_Z:
        if ax < ELBOW_X:
            return side + "UpperArm"
        if ax < WRIST_X:
            return side + "LowerArm"
        return side + "Hand"
    if p.z < CROTCH:
        if p.z >= KNEE_Z:
            return side + "UpperLeg"
        if p.z >= ANKLE_Z:
            return side + "LowerLeg"
        return side + "Foot"
    return "Torso" if p.z >= WAIST else "Pelvis"


def parent_of(seg: str) -> str:
    if seg == "Head":
        return "Torso"
    side = "Left" if seg.startswith("Left") else "Right"
    base = seg[len(side):]
    par = PARENT_SEG[base]
    return par if par in ("Torso", "Pelvis") else side + par


# the cut that separates each severable segment from its parent: point, normal (toward the child)
def cut_of(seg: str):
    if seg == "Head":
        return Vector((0, 0, NECK_CUT)), Vector((0, 0, 1))
    s = 1.0 if seg.startswith("Left") else -1.0
    base = seg[4:] if seg.startswith("Left") else seg[5:]
    return {
        "UpperArm": (Vector((s * SHOULDER_X, 0, 0)), Vector((s, 0, 0))),
        "LowerArm": (Vector((s * ELBOW_X, 0, 0)), Vector((s, 0, 0))),
        "Hand": (Vector((s * WRIST_X, 0, 0)), Vector((s, 0, 0))),
        "UpperLeg": (Vector((0, 0, CROTCH)), Vector((0, 0, -1))),
        "LowerLeg": (Vector((0, 0, KNEE_Z)), Vector((0, 0, -1))),
        "Foot": (Vector((0, 0, ANKLE_Z)), Vector((0, 0, -1))),
    }[base]


SEVERABLE = [s for s in SEGMENTS if s not in ("Pelvis", "Torso")]


# --- weights: two bones at most, blended across each joint --------------------------
def smooth(a: float, b: float, x: float) -> float:
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def chain_weight(x: float, joints: list, bones: list, blend: float) -> dict:
    """bones[i] covers x between joints[i-1] and joints[i] (joints ascending)."""
    for i, j in enumerate(joints):
        if x < j - blend:
            return {bones[i]: 1.0}
        if x < j + blend:
            w = smooth(j - blend, j + blend, x)
            return {bones[i]: 1.0 - w, bones[i + 1]: w}
    return {bones[-1]: 1.0}


def weights_for(p: Vector) -> dict:
    side = "Left" if p.x > 0 else "Right"
    ax = abs(p.x)
    if p.z > ARM_MIN_Z and ax > 0.14 and p.z < NECK_CUT - 0.02:
        return chain_weight(ax, [0.17, SHOULDER_X, ELBOW_X, WRIST_X],
                            ["Chest", side + "Shoulder", side + "UpperArm", side + "LowerArm", side + "Hand"], 0.03)
    if p.z < CROTCH:
        # down the leg (z falling): foot, shin, thigh
        return chain_weight(p.z, [ANKLE_Z, KNEE_Z], [side + "Foot", side + "LowerLeg", side + "UpperLeg"], 0.035)
    if p.z < 0.86 and ax > 0.03:
        # breeches between the crotch and the belt follow the thigh more the lower they are
        w = smooth(0.86, CROTCH, p.z)
        return {"Hips": 1.0 - w, side + "UpperLeg": w} if w > 0.001 else {"Hips": 1.0}
    return chain_weight(p.z, [WAIST, 1.26, 1.56, NECK_CUT], ["Hips", "Spine", "Chest", "Neck", "Head"], 0.035)


# --- build ---------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.data.objects if o.type == "MESH"][0]
body.name = "Klappersoldat"
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
top = max(v.co.z for v in body.data.vertices)
scale = HEIGHT / top
for v in body.data.vertices:
    v.co *= scale
mat = body.data.materials[0]
mat.name = "Material"
print("scaled by %.3f" % scale)

bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
# a little lighter: about 22k triangles, like the WitzSoldat
bm.to_mesh(body.data)
bm.free()
dec = body.modifiers.new("dec", "DECIMATE")
dec.ratio = 0.72
bpy.ops.object.modifier_apply(modifier="dec")
print("triangles after decimate:", len(body.data.polygons))

# --- cut cleanly at every severable joint ---------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
for seg in SEVERABLE:
    point, normal = cut_of(seg)
    par = parent_of(seg)
    geom = []
    for f in bm.faces:
        c = f.calc_center_median()
        if abs((c - point).dot(normal)) > 0.06:
            continue
        a = seg_of(c)
        # only faces of this limb (or its parent right at the joint)
        if a in (seg, par) or (seg.endswith("UpperLeg") and a in (seg, "Pelvis")):
            if seg != "Head" and seg[:4] != ("Left" if c.x > 0 else "Righ"):
                continue
            geom.append(f)
    if not geom:
        continue
    verts = {v for f in geom for v in f.verts}
    edges = {e for f in geom for e in f.edges}
    bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + geom, plane_co=point, plane_no=normal, dist=0.0001)

# label every face, find each cut's rim
seg_layer = bm.loops.layers.uv.new("SegmentID")
uv = bm.loops.layers.uv["UVMap"]
face_seg = {}
for f in bm.faces:
    s = seg_of(f.calc_center_median())
    face_seg[f] = s
    for l in f.loops:
        l[seg_layer].uv = ((SEG[s] + 0.5) / 16.0, 0.5)
rims = {}
for seg in SEVERABLE:
    point, normal = cut_of(seg)
    par = parent_of(seg)
    pts = []
    for e in bm.edges:
        segs = {face_seg[f] for f in e.link_faces}
        if seg in segs and len(segs) > 1:
            pts += [v.co.copy() for v in e.verts]
    if len(pts) < 6:
        # cut found nothing to share (e.g. a gap): take the child's verts nearest the plane
        near = [v.co.copy() for f in bm.faces if face_seg[f] == seg for v in f.verts if abs((v.co - point).dot(normal)) < 0.02]
        pts = near
    rims[seg] = pts
    print("cut %-14s rim points %d" % (seg, len(pts)))

# --- stump caps --------------------------------------------------------------------
gore_i = len(body.data.materials)
body.data.materials.append(bpy.data.materials.new("Gore"))
core_i = len(body.data.materials)
body.data.materials.append(bpy.data.materials.new("BoneCore"))
for name, col, metal, rough in [("Gore", (0.087, 0.0002, 0.0002, 1), 0.0, 0.3), ("BoneCore", (0.61, 0.52, 0.35, 1), 0.0, 0.5)]:
    m = body.data.materials[name]
    m.diffuse_color = col
    m.use_nodes = True
    bsdf = [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough


def cap_disc(seg: str):
    """12 points round the cut's cross-section, its centre and normal."""
    point, normal = cut_of(seg)
    pts = rims[seg]
    c = sum(pts, Vector()) / len(pts)
    c -= normal * (c - point).dot(normal)          # onto the cut plane
    u = normal.orthogonal().normalized()
    w = normal.cross(u).normalized()
    ring = []
    for k in range(12):
        a = math.tau * k / 12
        d = u * math.cos(a) + w * math.sin(a)
        reach = max([(p - c).dot(d) for p in pts] + [0.01])
        ring.append(c + d * reach * 0.97)
    return c, normal, ring


caps = {s: cap_disc(s) for s in SEVERABLE}


def add_fan(target_bm, centre, ring, facing: Vector, material: int, label: int, flag: float, uvl, segl):
    """A fan of triangles, wound to face `facing`."""
    cv = target_bm.verts.new(centre)
    rv = [target_bm.verts.new(p) for p in ring]
    out = []
    for k in range(len(rv)):
        tri = [cv, rv[k], rv[(k + 1) % len(rv)]]
        n = (tri[1].co - tri[0].co).cross(tri[2].co - tri[0].co)
        if n.dot(facing) < 0:
            tri = [tri[0], tri[2], tri[1]]
        f = target_bm.faces.new(tri)
        f.material_index = material
        for l in f.loops:
            if uvl is not None:
                l[uvl].uv = (0.5, 0.5)
            if segl is not None:
                l[segl].uv = ((label + 0.5) / 16.0, flag)
        out.append(f)
    return cv, rv


def add_cap(target_bm, seg: str, facing_child: bool, uvl, segl, label_seg: str, flag: float):
    c, n, ring = caps[seg]
    facing = n if facing_child else -n
    add_fan(target_bm, c + facing * 0.0015, [p + facing * 0.0015 for p in ring], facing, gore_i, SEG[label_seg], flag, uvl, segl)
    r = sum((p - c).length for p in ring) / len(ring)
    core = [c + (p - c).normalized() * r * 0.24 + facing * 0.003 for p in ring]
    add_fan(target_bm, c + facing * 0.003, core, facing, core_i, SEG[label_seg], flag, uvl, segl)


# body: a cap at each joint on the parent's side, labelled with the child
cap_verts = []
for seg in SEVERABLE:
    before = len(bm.verts)
    add_cap(bm, seg, True, uv, seg_layer, seg, 0.25)
    bm.verts.ensure_lookup_table()
    cap_verts.append((seg, list(range(before, len(bm.verts)))))
bm.to_mesh(body.data)
bm.free()

# --- the rig: the WitzSoldat's armature, its joints moved to this body --------------------
with bpy.data.libraries.load(WITZ, link=False) as (src, dst):
    dst.objects = ["WitzRig"]
rig = dst.objects[0]
rig.name = "KlapperRig"
rig.data.name = "KlapperRig"
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for eb in rig.data.edit_bones:
    if eb.name in BONES:
        roll = eb.roll
        eb.head = Vector(BONES[eb.name][0])
        eb.tail = Vector(BONES[eb.name][1])
        eb.roll = roll
bpy.ops.object.mode_set(mode="OBJECT")

# --- weights -----------------------------------------------------------------------
me = body.data
groups = {b.name: body.vertex_groups.new(name=b.name) for b in rig.data.bones}
cap_parent = {}
for seg, idx in cap_verts:
    par = SEGMENT_BONE.get(parent_of(seg), parent_of(seg))
    bone = {"Torso": "Chest", "Pelvis": "Hips"}.get(parent_of(seg), par)
    for i in idx:
        cap_parent[i] = bone
for v in me.vertices:
    if v.index in cap_parent:
        groups[cap_parent[v.index]].add([v.index], 1.0, "REPLACE")
        continue
    for b, w in weights_for(v.co).items():
        if w > 0.001:
            groups[b].add([v.index], w, "REPLACE")
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = rig

# --- rest positions in Godot axes, normalised -------------------------------------------
gd = [Vector((v.co.x, v.co.z, -v.co.y)) for v in me.vertices]
lo = Vector((min(p.x for p in gd), min(p.y for p in gd), min(p.z for p in gd)))
hi = Vector((max(p.x for p in gd), max(p.y for p in gd), max(p.z for p in gd)))
lo -= Vector((0.005, 0.005, 0.005))
size = hi - lo + Vector((0.01, 0.01, 0.01))
rest = me.color_attributes.new("RestPos", "FLOAT_COLOR", "POINT")
for i, p in enumerate(gd):
    q = p - lo
    rest.data[i].color = (q.x / size.x, q.y / size.y, q.z / size.z, 1.0)
me.color_attributes.active_color = rest
me.uv_layers.active = me.uv_layers["UVMap"]
me.uv_layers["UVMap"].active_render = True

# --- the eyes: amber texels on the front of the head -----------------------------------------
img = None
for n in mat.node_tree.nodes:
    if n.type == "TEX_IMAGE":
        img = n.image
eyes = []
if img:
    w, h = img.size
    px = img.pixels[:]
    found = {1: [], -1: []}
    uvd = me.uv_layers["UVMap"].data
    for poly in me.polygons:
        c = poly.center
        if not (1.66 < c.z < 1.79 and c.y < -0.08 and abs(c.x) < 0.09):
            continue
        u, vv = uvd[poly.loop_indices[0]].uv
        x = min(int(u * w), w - 1)
        y = min(int(vv * h), h - 1)
        r, g, b = px[(y * w + x) * 4: (y * w + x) * 4 + 3]
        if r > 0.55 and g > 0.25 and b < 0.25 and r > g * 1.3:
            found[1 if c.x > 0 else -1].append(Vector(c))
    for s in (1, -1):
        if found[s]:
            e = sum(found[s], Vector()) / len(found[s])
            eyes.append([e.x, e.z, -e.y])
if len(eyes) == 1:                     # one found: the other is its mirror
    eyes.append([-eyes[0][0], eyes[0][1], eyes[0][2]])
print("eyes", eyes)

# --- gibs: one object per segment, origin at its bone's head, caps at both ends -----------
gib_objs = []
src_bm = bmesh.new()
src_bm.from_mesh(me)
src_seg = src_bm.loops.layers.uv["SegmentID"]
for seg in SEGMENTS:
    bone = rig.data.bones[SEGMENT_BONE.get(seg, seg)]
    origin = bone.head_local.copy()
    gbm = bmesh.new()
    guv = gbm.loops.layers.uv.new("UVMap")
    vmap = {}
    for f in src_bm.faces:
        u0 = f.loops[0][src_seg].uv
        if abs(u0.y - 0.5) > 0.1 or int(u0.x * 16) != SEG[seg]:
            continue
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = gbm.verts.new(v.co - origin)
            vs.append(vmap[v.index])
        try:
            nf = gbm.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = f.material_index
        for l, sl in zip(nf.loops, f.loops):
            l[guv].uv = sl[src_bm.loops.layers.uv["UVMap"]].uv
    # its own cut (facing back toward where it joined), and every cut to its children
    for other in SEVERABLE:
        if other == seg:
            c, n, ring = caps[other]
            add_fan(gbm, c - origin - n * 0.0015, [p - origin - n * 0.0015 for p in ring], -n, gore_i, 0, 0.5, guv, None)
            r = sum((p - c).length for p in ring) / len(ring)
            add_fan(gbm, c - origin - n * 0.003, [c - origin + (p - c).normalized() * r * 0.24 - n * 0.003 for p in ring], -n, core_i, 0, 0.5, guv, None)
        elif parent_of(other) == seg:
            c, n, ring = caps[other]
            add_fan(gbm, c - origin + n * 0.0015, [p - origin + n * 0.0015 for p in ring], n, gore_i, 0, 0.5, guv, None)
            r = sum((p - c).length for p in ring) / len(ring)
            add_fan(gbm, c - origin + n * 0.003, [c - origin + (p - c).normalized() * r * 0.24 + n * 0.003 for p in ring], n, core_i, 0, 0.5, guv, None)
    gme = bpy.data.meshes.new("Gib_" + seg)
    gbm.to_mesh(gme)
    gbm.free()
    for m in me.materials:
        gme.materials.append(m)
    go = bpy.data.objects.new("Gib_" + seg, gme)
    go.location = origin
    bpy.context.scene.collection.objects.link(go)
    gib_objs.append(go)
    print("gib %-14s faces %d" % (seg, len(gme.polygons)))
src_bm.free()

# --- export ------------------------------------------------------------------------------
def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_vertex_color="ACTIVE",
                              export_apply=False)


export([rig, body], OUT + "/klappersoldat.glb")
export(gib_objs, OUT + "/klappersoldat_gibs.glb")
json.dump({
    "segments": SEGMENTS,
    "rest_bbox_min": [lo.x, lo.y, lo.z],
    "rest_bbox_size": [size.x, size.y, size.z],
    "eyes": eyes,
    "note": "Godot axes. Same skeleton names and segment ids as the clown. Built by tools/build_klappersoldat.py.",
}, open(OUT + "/klappersoldat.json", "w"), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/klappersoldat.blend")
print("done")
