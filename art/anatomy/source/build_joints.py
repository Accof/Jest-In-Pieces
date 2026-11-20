"""The ends of the long bones, for stumps, severed limbs and broken knees and elbows.

    python3 art/anatomy/source/build_joints.py --atlas <human-atlas>/public/models --out art/anatomy

From BodyParts3D 4.0 (CC BY 4.0): humerus, radius and ulna, femur, tibia and
fibula, both sides. Each end of each becomes a piece: the joint end itself
(the head of the humerus, its condyles at the elbow, the knee's condyles and
plateau, ...) and a length of shaft, snapped across with a splintered edge and
the break filled with marrow.

Each piece is laid out on its own frame: the middle of the joint at the origin,
+Y up the shaft (away from the joint), +Z to the body's front, in metres at
real size; the piece's node carries `extras`: the bone's whole length and the
shaft's width, for the game to size it to each body.

Writes joints.glb with nodes <Side><Piece>: Humerus_Prox, Humerus_Dist,
Forearm_Prox, Forearm_Dist, Femur_Prox, Femur_Dist, Shin_Prox, Shin_Dist.
"""
import argparse
import contextlib
import io
import json
import os
import sys

import bpy  # (first: it brings bmesh and mathutils with it)
import bmesh
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from bp3d import Atlas  # noqa: E402

# piece -> (bones in it, which end (+1: the end the main bone's axis points to), length kept as a share of the main bone)
PIECES = {
    "Humerus": (["humerus"], 0.30),
    "Forearm": (["radius", "ulna"], 0.30),
    "Femur": (["femur"], 0.26),
    "Shin": (["tibia", "fibula"], 0.28),
}
rng = np.random.default_rng(1917)


def axis_of(V):
    """Main axis of a long bone and its two ends (top end first, by height)."""
    c = V.mean(0)
    _, _, vt = np.linalg.svd(V - c, full_matrices=False)
    ax = vt[0]
    if ax[1] < 0:
        ax = -ax                                   # pointing up the body
    t = (V - c) @ ax
    return c, ax, t.min(), t.max()


def joint_centre(V, c, ax, t_end, side_sign):
    """The middle of a joint end: the bone within 2.5 cm of its end."""
    t = (V - c) @ ax
    near = V[(t - t_end) * side_sign > -0.025]
    return near.mean(0)


def to_bl(v):
    return Vector((v[0], -v[2], v[1]))


def make_piece(parts, main, end, keep_share, name):
    """`parts`: [(name, V, F)]; `main`: index of the long bone that sets the axis;
    `end`: 'Prox' (the top end, by height) or 'Dist'."""
    V0 = parts[main][1]
    c, ax, tmin, tmax = axis_of(V0)
    length = tmax - tmin
    up_end = end == "Prox"
    t_end = tmax if up_end else tmin
    sgn = 1.0 if up_end else -1.0
    jc = joint_centre(V0, c, ax, t_end, sgn)
    # the piece's frame: origin at the joint, +Y into the shaft, +Z the body's front
    y = -ax * sgn
    z = np.array([0.0, 0.0, 1.0])
    z = z - y * (z @ y)
    z /= np.linalg.norm(z)
    x = np.cross(y, z)
    R = np.stack([x, y, z])                          # rows: world -> piece
    keep = length * keep_share
    width = 0.0
    me_all = []
    for n, V, F in parts:
        Vp = (V - jc) @ R.T
        me = bpy.data.meshes.new(n)
        me.from_pydata([to_bl(v) for v in Vp], [], F.tolist())
        me.validate()
        ob = bpy.data.objects.new(n, me)
        bpy.context.scene.collection.objects.link(ob)
        me_all.append(ob)
        shaft = Vp[(Vp[:, 1] > keep * 0.6) & (Vp[:, 1] < keep)]
        if len(shaft) and n == parts[main][0]:
            width = 2.0 * np.median(np.hypot(shaft[:, 0], shaft[:, 2]))
    bpy.ops.object.select_all(action="DESELECT")
    for o in me_all:
        o.select_set(True)
    bpy.context.view_layer.objects.active = me_all[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
    # snap it across the shaft: everything further up the shaft than `keep` goes
    # (the piece's +Y is Blender's +Z after to_bl)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, keep)), plane_no=Vector((0, 0, 1)), clear_outer=True)
    rim = set()
    for e in res["geom_cut"]:
        if isinstance(e, bmesh.types.BMEdge):
            rim.update(e.verts)
    # the marrow: fill the open end (flat for now)
    holes = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    for f in holes.get("faces", []):
        f.material_index = 1
    # then splinter the rim: points of cortex standing proud, the break between
    # them dropping back toward the joint (the marrow face breaks with it)
    ph = rng.random() * 6.28
    for v in rim:
        a = np.arctan2(v.co.y, v.co.x)
        spike = 0.55 + 0.45 * np.sin(a * 4 + ph) + rng.normal(0, 0.3)
        v.co.z += float(np.clip(spike, -0.4, 1.3)) * width * 0.4 - width * 0.15
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.materials.clear()
    ob.data.materials.append(bpy.data.materials.get("bone") or bpy.data.materials.new("bone"))
    ob.data.materials.append(bpy.data.materials.get("marrow") or bpy.data.materials.new("marrow"))
    tris = len(ob.data.polygons)
    if tris > 1400:
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = 1400 / tris
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth()
    ob["length"] = float(length)
    ob["width"] = float(width)
    ob["kept"] = float(keep)
    print("  %-18s bone %.3f m, shaft %.1f mm wide, kept %.3f m, %d tris" % (name, length, width * 1000, keep, len(ob.data.polygons)))
    return ob


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--atlas", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    A = Atlas(args.atlas)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    made = []
    for side in ("Left", "Right"):
        for piece, (bones, share) in PIECES.items():
            names = ["%s %s" % (side, b) for b in bones]
            for end in ("Prox", "Dist"):
                parts = A.parts(names)
                parts.sort(key=lambda p: names.index(p[0]))
                made.append(make_piece(parts, 0, end, share, "%s%s_%s" % (side, piece, end)))
    bpy.ops.object.select_all(action="DESELECT")
    for o in made:
        o.select_set(True)
    path = os.path.join(args.out, "joints.glb")
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_extras=True, export_texcoords=False)
    print("wrote", path, os.path.getsize(path))


if __name__ == "__main__":
    main()
