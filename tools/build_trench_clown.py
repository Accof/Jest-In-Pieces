"""Build the trench clown's game body from Andrew's Tripo model (24 Nov 2026):
the basic clown, the one you meet most - black leather greatcoat, a Stahlhelm
with a riveted eye-slit visor strapped over the face, a bloody grin under it,
a trench club in the hand.

Run with Blender's Python (`pip install bpy`, or blender --background --python):
    python3 tools/build_trench_clown.py <tripo.glb> <witzsoldat.blend> <out dir>

Writes into <out dir>:
  trench_clown.glb          skinned body on the WitzSoldat's skeleton, with the
                            model's own PBR maps (colour, metal/roughness, normal)
  trench_clown_gibs.glb     one mesh per dismemberment segment (Gib_<Segment>);
                            no images: the game gives them the body's material
  trench_clown.json         segments, rest box, helmet centre and size (Godot axes)
  trench_clown.blend        the working file, for hand fixes

Adapted from tools/build_witzsoldat_dark.py. Differences: the helmet stays on
(see SPLIT_HELMET below for why), and the joints are measured from this model
(shorter arms, baggy breeches joined to the knee). Same conventions as the clown (clown_segments.json):
- Segments: 15 ids in the second UV map "SegmentID" (u = (id + 0.5) / 16,
  v = 0.5, or 0.25 for a stump cap).
- Rest pose: each vertex's rest position in Godot axes, normalised to the
  rest box, in the colour attribute "RestPos".
- Stumps: the mesh is cut cleanly at every severable joint and each cut gets
  a cap ("Gore" material) with a bone core ("BoneCore"), labelled with the
  child segment so the shader shows it only once that part is gone.
- Weights: at most two bones a vertex, blended across each joint.
"""
import json
import math
import os
import sys

import bpy  # first: bmesh and mathutils come with it
import bmesh
import mathutils
from mathutils import Vector

SRC, WITZ, OUT = sys.argv[-3:]
HEIGHT = 1.93          # the WitzSoldat's, to the top of the helmet
OUTNAME = "trench_clown"

SEGMENTS = ["Pelvis", "Torso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg",
            "LeftFoot", "RightUpperArm", "RightLowerArm", "RightHand", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
SEG = {n: i for i, n in enumerate(SEGMENTS)}
SEGMENT_BONE = {"Pelvis": "Hips", "Torso": "Spine", "Head": "Neck"}

# --- joints (Blender axes: +X the model's left, -Y forward, +Z up), metres ----
# measured from the T-pose at 1.93 m: sleeves 1.39..1.56 high at the shoulder
# sloping to 1.32..1.39 at the glove, set back y -0.04..0.12; the glove from
# x 0.63 (cuff) to 0.79 (fingertips); the breeches one baggy mass to the knee
# at 0.52, puttees below, boot tops 0.12; belt and pouches 0.95..1.11, the
# coat's collar top 1.62, the visor's top edge 1.80, crown 1.93
NECK_CUT = 1.62        # head comes off here (the collar's top, under the chin)
WAIST = 1.08           # pelvis / torso (the belt)
SHOULDER_X = 0.24      # arm comes off here
ELBOW_X = 0.47
WRIST_X = 0.66
ARM_Z = 1.44
ARM_Y = 0.04           # the sleeves hang a little behind the middle of the chest
CROTCH = 0.78          # legs come off here (through the joined breeches)
KNEE_Z = 0.52
ANKLE_Z = 0.12
ARM_MIN_Z = 1.28       # below this nothing is arm
HAND_TIP_X = 0.79

BONES = {
    "Hips": ((0, 0.01, 0.97), (0, 0.01, WAIST)),
    "Spine": ((0, 0.01, WAIST), (0, 0.01, 1.26)),
    "Chest": ((0, 0.01, 1.26), (0, 0.01, 1.53)),
    "Neck": ((0, 0.005, 1.53), (0, 0.0, NECK_CUT)),
    "Head": ((0, 0.0, NECK_CUT), (0, 0.0, 1.86)),
    "LeftShoulder": ((0.03, 0.03, 1.47), (SHOULDER_X, ARM_Y, ARM_Z)),
    "LeftUpperArm": ((SHOULDER_X, ARM_Y, ARM_Z), (ELBOW_X, ARM_Y, ARM_Z - 0.03)),
    "LeftLowerArm": ((ELBOW_X, ARM_Y, ARM_Z - 0.03), (WRIST_X, 0.0, 1.375)),
    "LeftHand": ((WRIST_X, 0.0, 1.375), (HAND_TIP_X, -0.03, 1.34)),
    "LeftUpperLeg": ((0.11, 0.02, 0.95), (0.16, 0.03, KNEE_Z)),
    "LeftLowerLeg": ((0.16, 0.03, KNEE_Z), (0.19, 0.04, ANKLE_Z)),
    "LeftFoot": ((0.19, 0.04, ANKLE_Z), (0.2, -0.1, 0.03)),
    "LeftToes": ((0.2, -0.1, 0.03), (0.2, -0.2, 0.03)),
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
    if p.z >= NECK_CUT and ax < 0.22:
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
    if p.z < 0.9 and ax > 0.03:
        # breeches between the crotch and the belt follow the thigh more the lower they are
        w = smooth(0.9, CROTCH, p.z)
        return {"Hips": 1.0 - w, side + "UpperLeg": w} if w > 0.001 else {"Hips": 1.0}
    return chain_weight(p.z, [WAIST, 1.26, BONES["Chest"][1][2], NECK_CUT], ["Hips", "Spine", "Chest", "Neck", "Head"], 0.035)


# --- build ---------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: -len(o.data.vertices))
body = meshes[0]
for o in meshes[1:]:                   # Tripo slivers
    bpy.data.objects.remove(o)
body.name = "TrenchClown"
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

# --- the helmet off the head? NO (24 Nov 2026) ----------------------------------------
# Tried four ways (see git history of this file): the visor plate is riveted to
# the helmet's band and there is no face modelled behind it - no eyes, the
# cheeks and brow under the plate are Tripo's guesswork - and the ear flaps and
# rear skirt are fused to the head with nothing beneath. Every cut left either
# half a helmet on the scalp or a faceless dome with the plate's ends poking
# out. So, like the Klappersoldat, this body keeps its helmet on: one skinned
# mesh, the Head segment is the helmeted head, the head gib too. A Tripo model
# generated with a separated helmet (the Rattlejack's way) would bring the
# knock-off back; the code is kept under SPLIT_HELMET for that day.
SPLIT_HELMET = os.environ.get("SPLIT_HELMET", "0") == "1"
helmet_obj = None
hcen = Vector()
hhi = hlo = Vector()
if SPLIT_HELMET:
    # --- the helmet off the head ----------------------------------------------------------
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    crown = [v.co for v in bm.verts if v.co.z > HEIGHT - 0.03]
    axis = sum(crown, Vector()) / len(crown)
    # This helmet is painted (nothing above the collar is metal in its map), so
    # the cut is geometric. Helmet: the dome above the visor's top edge all round;
    # below that edge, the ear flaps and the rear skirt - the shell beyond the
    # skull's width at the sides and behind the nape - down to the jaw. Not
    # helmet: the visor plate and its riveted band at the front (strapped over
    # the face; nothing is modelled behind it, so it stays as a mask), the face,
    # the neck.
    JAW = 1.655
    EYE_LINE = 1.725       # the visor plate's bottom edge, just above the nose
    cand = set()
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z < JAW or abs(c.x) > 0.25:
            continue
        # The face: the nose, the grin, the chin and the cheeks, in front of the
        # skull below the visor's bottom edge, and the cheeks and brow behind the
        # plate (it stands 6 cm off them). Everything else from the jaw up - the
        # dome, the ear flaps and rear skirt (fused to the head in this mesh, no
        # surface under them), the riveted visor plate and its band - is the
        # helmet, one piece, and the scalp dome takes its place: with it shot off
        # he has no eyes, a bare dome down to the nose and the grin under it.
        face = c.y < -0.03 and abs(c.x) < 0.13 and (c.z < EYE_LINE or c.y > -0.16)
        if not face:
            cand.add(f.index)


    def components(sel):
        seen, out = set(), []
        for i in sel:
            if i in seen:
                continue
            comp, stack = {i}, [i]
            seen.add(i)
            while stack:
                f = bm.faces[stack.pop()]
                for e in f.edges:
                    for g in e.link_faces:
                        if g.index in sel and g.index not in seen:
                            seen.add(g.index)
                            comp.add(g.index)
                            stack.append(g.index)
            out.append(comp)
        return out


    comps = sorted(components(cand), key=len, reverse=True)
    best = set(comps[0])
    for comp in comps[1:]:
        if len(comp) >= 40:          # rivets and the like, if they came out as islands
            best |= comp
    # non-metal patches wholly inside it: small islands of the rest whose every
    # neighbour is helmet
    rest = {f.index for f in bm.faces if f.index not in best and f.calc_center_median().z > JAW and abs(f.calc_center_median().x) < 0.25}
    for comp in components(rest):
        if len(comp) > 300:
            continue
        border = {g.index for i in comp for e in bm.faces[i].edges for g in e.link_faces} - comp
        if border and border <= best:
            best |= comp
    # and whatever else stands off the skull at the sides or behind (strap ends,
    # hinge plates at the temples): with the helmet, not left poking out of the scalp
    for f in bm.faces:
        c = f.calc_center_median()
        if f.index not in best and c.z >= JAW and c.y >= -0.03 and Vector((c.x - axis.x, c.y - axis.y)).length > 0.125 and abs(c.x) < 0.25:
            best.add(f.index)
    helm = set(best)
    print("helmet faces", len(best), "of", len(cand), "metal candidates")
    helmet_faces = [bm.faces[i] for i in best]
    # the rim of the hole it leaves (edges between helmet and head)
    rim = [v.co.copy() for f in helmet_faces for e in f.edges if any(g.index not in best for g in e.link_faces) for v in e.verts]
    hb = bmesh.new()
    huv = hb.loops.layers.uv.new("UVMap")
    src_uv = bm.loops.layers.uv["UVMap"]
    vmap = {}
    for f in helmet_faces:
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = hb.verts.new(v.co)
            vs.append(vmap[v.index])
        try:
            nf = hb.faces.new(vs)
        except ValueError:
            continue
        nf.smooth = True
        for l, sl in zip(nf.loops, f.loops):
            l[huv].uv = sl[src_uv].uv
    # The helmet's faces stay on the body as the scalp: pulled in to a skull-sized
    # dome (no hole to cap, the face's top edge is shared), smoothed, and given a
    # dark cropped-hair material. Unseen until the helmet is shot off.
    rc = sum(rim, Vector()) / len(rim)
    r = max((v - rc).length for v in rim)
    scalp_mat = bpy.data.materials.new("Scalp")
    scalp_mat.use_nodes = True
    sb = [n for n in scalp_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
    sb.inputs["Base Color"].default_value = (0.05, 0.035, 0.025, 1)
    sb.inputs["Roughness"].default_value = 0.9
    body.data.materials.append(scalp_mat)
    scalp_i = len(body.data.materials) - 1
    uvl = bm.loops.layers.uv["UVMap"]
    scalp_faces = [bm.faces[i] for i in helm]      # every helmet face, specks included
    edge = {v for f in scalp_faces for v in f.verts if any(g.index not in helm for g in v.link_faces)}
    inner = {v for f in scalp_faces for v in f.verts} - edge
    # the skull's outline reaches the mask's brow (12 cm in front of the middle at
    # 1.80 m, where the face's top edge now is), so that edge is barely moved
    SKULL_X, SKULL_FRONT, SKULL_BACK = 0.092, 0.14, 0.095
    top_z = 1.875                       # the crown of the skull, well inside the dome
    SKULL_UP = top_z - 1.76              # the crown above the skull's middle
    cy = axis.y - 0.015
    C = Vector((axis.x, cy, 1.76))        # the middle of the skull, at the eyes


    def skull_r(d):
        """Horizontal radius of the skull's outline in direction d (2D)."""
        if d.length < 1e-6:
            return SKULL_X
        n = d.normalized()
        ry = SKULL_FRONT if n.y < 0 else SKULL_BACK
        return 1.0 / math.sqrt((n.x / SKULL_X) ** 2 + (n.y / ry) ** 2)


    def on_skull(co):
        """Straight out from the middle of the skull onto its surface: an
        ellipsoid, round on top (a smooth dome, as the other models' skulls)."""
        d = co - C
        if d.length < 1e-6:
            d = Vector((0, 0, 1))
        ry = SKULL_FRONT if d.y < 0 else SKULL_BACK
        rz = SKULL_UP if d.z > 0 else 0.07
        k = 1.0 / math.sqrt((d.x / SKULL_X) ** 2 + (d.y / ry) ** 2 + (d.z / rz) ** 2)
        return C + d * k


    def to_rim(co):
        """An edge vert (shared with the face): in to the skull's outline at its height."""
        d = Vector((co.x - C.x, co.y - C.y))
        R = skull_r(d)
        up = max(co.z - C.z, 0.0) / SKULL_UP
        R *= math.sqrt(max(1.0 - up * up, 0.05))
        down = max(C.z - co.z, 0.0) / 0.13             # the skull rounds off under the ears into the neck
        R *= max(math.sqrt(max(1.0 - down * down, 0.0)), 0.55)
        if d.length > R:
            d = d.normalized() * R
        return Vector((C.x + d.x, C.y + d.y, co.z))


    for v in edge:
        v.co = to_rim(v.co)
    for v in inner:
        v.co = on_skull(v.co)
    for _ in range(16):                 # relax it smooth, keeping it on the skull
        new_co = {}
        for v in inner:
            nb = [e.other_vert(v).co for e in v.link_edges]
            new_co[v] = on_skull(sum(nb, Vector()) / len(nb) * 0.7 + v.co * 0.3)
        for v, c in new_co.items():
            v.co = c
    far = [v.co for v in edge | inner if (Vector((v.co.x - C.x, v.co.y - C.y)).length > 0.11)]
    print("scalp verts outside the skull", len(far))
    scalp_set = edge | inner
    for f in scalp_faces:
        f.material_index = scalp_i
        for l in f.loops:
            l[uvl].uv = (0.5, 0.5)
    far = [v.co for v in edge | inner if (Vector((v.co.x - axis.x, v.co.y - cy)).length > 0.11)]
    print("scalp verts outside the skull", len(far), [tuple(round(x, 3) for x in c) for c in far[:6]])
    bm.normal_update()
    scalp = scalp_faces
    print("scalp faces", len(scalp))
    bm.to_mesh(body.data)
    bm.free()

    # the helmet: its own object, origin at its centre, a dark liner across the underside
    hlo = Vector((min(v.co.x for v in hb.verts), min(v.co.y for v in hb.verts), min(v.co.z for v in hb.verts)))
    hhi = Vector((max(v.co.x for v in hb.verts), max(v.co.y for v in hb.verts), max(v.co.z for v in hb.verts)))
    hcen = (hlo + hhi) / 2
    liner_ring = sorted({v for e in hb.edges if e.is_boundary for v in e.verts if (v.co - rc).length < r * 1.25},
                        key=lambda v: math.atan2(v.co.y - rc.y, v.co.x - rc.x))
    liner = []
    if len(liner_ring) > 4:
        lc = hb.verts.new(rc + Vector((0, 0, 0.01)))
        for k in range(len(liner_ring)):
            try:
                f = hb.faces.new([liner_ring[k], lc, liner_ring[(k + 1) % len(liner_ring)]])
                liner.append(f)
            except ValueError:
                pass
    for v in hb.verts:
        v.co -= hcen
    hme = bpy.data.meshes.new("Helmet")
    hb.to_mesh(hme)
    hb.free()
    hme.materials.append(mat)
    liner_mat = bpy.data.materials.new("Liner")
    liner_mat.use_nodes = True
    lb = [n for n in liner_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
    lb.inputs["Base Color"].default_value = (0.04, 0.03, 0.02, 1)
    hme.materials.append(liner_mat)
    nl = len(liner)
    for p in hme.polygons[len(hme.polygons) - nl:]:
        p.material_index = 1
    helmet_obj = bpy.data.objects.new("Helmet", hme)
    helmet_obj.location = hcen
    bpy.context.scene.collection.objects.link(helmet_obj)
    print("helmet centre", hcen, "size", hhi - hlo, "liner", nl)


# Decimation (23 Nov 2026): OFF. At 0.5 the edge collapses crossed the UV
# seams and islands (the weld before it had fused their vertices), and the
# maps came out smeared in triangular streaks across the belt, pouches and
# buttons - "stretched", nothing like Tripo's preview. The model stays at
# Tripo's 47k triangles; a lower level of detail for distance is M12's job.
# DEC_RATIO=<0..1> in the environment brings it back for an experiment.
DEC_RATIO = float(os.environ.get("DEC_RATIO", "1.0"))
if DEC_RATIO < 0.999:
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
    bm.to_mesh(body.data)
    bm.free()
    dec = body.modifiers.new("dec", "DECIMATE")
    dec.ratio = DEC_RATIO
    bpy.ops.object.modifier_apply(modifier="dec")
    print("triangles after decimate:", len(body.data.polygons))
    # Tripo's custom normals do not survive decimation (they come out faceted, a
    # flat patch to each triangle on the mask): drop them, shade smooth, sharp only
    # at real creases.
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(60))
else:
    # the seams' duplicate vertices are kept (the cuts below weld what they
    # need themselves); Tripo's own normals too: it is what its preview shows
    print("triangles (no decimation):", len(body.data.polygons))

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
rig.name = "WitzRig"
rig.data.name = "WitzRig"
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
        nf.smooth = f.smooth
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
def export(objs, path, images="JPEG"):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_vertex_color="ACTIVE",
                              export_apply=False, export_image_format=images, export_jpeg_quality=95)


# The body carries the model's three 4K maps (colour and normal as they came,
# metal/roughness from an 11 MB PNG to a quality-95 JPEG); the gibs and the
# helmet carry none and are given the body's material in the game, so the maps
# are stored once.
export([rig, body], OUT + "/" + OUTNAME + ".glb")
export(gib_objs, OUT + "/" + OUTNAME + "_gibs.glb", "NONE")
info = {
    "segments": SEGMENTS,
    "rest_bbox_min": [lo.x, lo.y, lo.z],
    "rest_bbox_size": [size.x, size.y, size.z],
    "note": "Godot axes. Same skeleton names and segment ids as the clown. Built by tools/build_trench_clown.py.",
}
if helmet_obj is not None:
    helmet_obj.location = Vector()
    export([helmet_obj], OUT + "/" + OUTNAME + "_helmet.glb", "NONE")
    helmet_obj.location = hcen
    hsize = hhi - hlo
    info["helmet_center"] = [hcen.x, hcen.z, -hcen.y]
    info["helmet_size"] = [hsize.x, hsize.z, hsize.y]
json.dump(info, open(OUT + "/" + OUTNAME + ".json", "w"), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/" + OUTNAME + ".blend")
print("done")
