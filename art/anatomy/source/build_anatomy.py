"""Build the enemies' exposed anatomy from two open anatomical datasets.

    python3 tools/anatomy/build_anatomy.py --atlas <human-atlas>/public/models --organs <dir of VH_M_*.glb> --out art/anatomy

Sources (both CC BY 4.0; credited in art/anatomy/CREDITS.txt):
  BodyParts3D 4.0, (c) The Database Center for Life Science: skull, jaw and teeth,
      brain (gyri, cerebellum, brainstem), ribs, costal cartilage, sternum, vertebrae,
      pelvis, the long bones, stomach, colon.
      Read from the human-atlas repository's packing (github.com/ashemag/human-atlas,
      public/models: atlas.json + body-*.bin), itself BodyParts3D 4.0's
      isa_BP3D_4.0_obj_99 meshes, simplified.
  Human Reference Atlas 3D reference organs v1.3 (HuBMAP CCF; Visible Human male;
      Kristen Browne, Heidi Schlehlein): heart, lungs, liver, kidneys, small intestine.
      github.com/hubmapconsortium/ccf-releases, v1.3/models/VH_M_*.glb.

Everything lands in one reference frame, BodyParts3D's own: metres, +Y up,
+Z to the front, +X the body's left, feet at y = 0 (a man about 1.75 m tall).
The reference organs sit in the Visible Human frame, which agrees in its
axes and scale; it is moved up 0.812 m onto BodyParts3D (fitted on the two
kidneys, which both sets have; the heart then lands on BodyParts3D's own).

Writes one GLB per region, each mesh named for what it is and carrying a
material named for how it is to be shaded (bone, cartilage, brain, heart,
lung, liver, gut, kidney): head, chest, belly, pelvis. And the joint ends of the
long bones for stumps, gibs and broken limbs (joints.glb, see build_joints.py).
"""
import argparse
import contextlib
import io
import os
import re
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from bp3d import Atlas  # noqa: E402

VH_TO_BP3D = np.array([-0.002, 0.812, 0.0045])     # glTF frame (y up, z front)

# What goes where: region -> [(node name, material, triangle budget, BodyParts3D names | None, reference organ meshes | None)]
ORDINAL = "first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth".split()


def regions(A):
    sk = A.names(lambda p: p["system"] == "skeletal")
    nv = A.names(lambda p: p["system"] == "nervous")
    skull = [n for n in sk if re.search(r"Frontal bone|parietal bone|Occipital bone|temporal bone|Sphenoid|Ethmoid|zygomatic|maxilla|nasal bone|lacrimal|palatine bone|Vomer|Mandible|tooth", n)]
    brain = [n for n in nv if re.search(r"gyrus|lobule|lobe|insula|Cerebellum|Pons|Medulla|Midbrain|Peduncle", n) and not re.search("artery|branch", n)]
    ribs = [n for n in sk if re.search(r" rib$", n)]
    cart = [n for n in sk if "costal cartilage" in n]
    sternum = ["Manubrium", "Body of sternum", "Xiphoid process"]
    thoracic = ["%s thoracic vertebra" % o.capitalize() for o in ORDINAL]
    thoracic_disks = [n for n in sk if n.startswith("Intervertebral disk of") and "thoracic" in n]
    cervical = ["Atlas", "Axis"] + ["%s cervical vertebra" % o.capitalize() for o in ORDINAL[2:7]]
    lumbar = ["%s lumbar vertebra" % o.capitalize() for o in ORDINAL[:5]]
    lumbar_disks = [n for n in sk if n.startswith("Intervertebral disk of") and "lumbar" in n]
    mu = A.names(lambda p: p["system"] == "muscular")
    # the walls round the organs: between and over the ribs, the diaphragm, the back
    chest_mu = [n for n in mu if re.search(r"external intercostal muscle|^Diaphragm|pectoralis|serratus anterior|iliocostalis thoracis|longissimus thoracis|Transverse part of .* trapezius|Ascending part of .* trapezius", n, re.I)]
    # (internal and innermost intercostals lie under the external ones, and spinalis and semispinalis
    #  under the long back muscles: never seen through a wound, and thin sheets that will not decimate)
    belly_mu = [n for n in mu if re.search(r"external oblique$|psoas major|iliocostalis lumborum", n, re.I) and "arytenoid" not in n]
    return {
        "head": [
            ("Skull", "bone", 5500, skull, None),
            ("Brain", "brain", 8000, brain, None),
        ],
        "chest": [
            ("Ribcage", "bone", 7000, ribs + sternum + thoracic + ["Left clavicle", "Right clavicle"], None),
            ("Cartilage", "cartilage", 1600, cart + thoracic_disks, None),
            ("Lungs", "lung", 4000, None, ("VH_M_Lung", lambda n: "bronchopulmonary_segment" in n)),
            ("Heart", "heart", 3000, None, ("VH_M_Heart", lambda n: re.search("ventricle$|cardiac_atrium", n) is not None)),
            ("Vessels", "heart", 800, ["Esophagus"], None),
            ("Muscle", "muscle", 4500, chest_mu, None),
        ],
        "neck": [
            ("Cervical", "bone", 2000, cervical, None),
        ],
        "belly": [
            ("Lumbar", "bone", 2000, lumbar, None),
            ("Disks", "cartilage", 400, lumbar_disks, None),
            ("Liver", "liver", 2000, None, ("VH_M_Liver", lambda n: n.endswith("liver_capsule"))),
            ("Stomach", "gut", 1000, ["Stomach"], None),
            ("Bowel", "gut", 4500, None, ("VH_M_Small_Intestine", lambda n: re.search("jejunum|ileum|duodenum_", n) is not None)),
            ("Colon", "colon", 1800, ["Ascending colon", "Transverse colon", "Descending colon"], None),
            ("Kidneys", "kidney", 1000, ["Left kidney", "Right kidney"], None),
            ("Muscle", "muscle", 2500, belly_mu, None),
        ],
        "pelvis": [
            ("Pelvis", "bone", 3500, ["Left hip bone", "Right hip bone", "Sacrum"], None),
        ],
    }


def to_blender(V):
    """glTF frame (x, y up, z front) -> Blender (x, y back, z up)."""
    return np.c_[V[:, 0], -V[:, 2], V[:, 1]]


def mesh_object(name, V, F):
    me = bpy.data.meshes.new(name)
    me.from_pydata(to_blender(V).tolist(), [], F.tolist())
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def import_organ(path, keep):
    before = set(bpy.data.objects)
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    meshes = []
    off = to_blender(VH_TO_BP3D[None])[0]
    for o in objs:
        if o.type == "MESH" and keep(o.name):
            o.data = o.data.copy()
            o.data.transform(o.matrix_world)
            o.parent = None
            o.matrix_world.identity()
            o.data.transform(__import__("mathutils").Matrix.Translation(off))
            meshes.append(o)
    for o in objs:
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def finish(objs, name, mat, budget):
    """Join, weld, cut down to `budget` triangles, smooth; one object named `name`."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0003)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    now = tris
    for _ in range(4):                   # (one pass can stall on meshes of many small pieces)
        if now <= budget * 1.05:
            break
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = budget / now
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
        now = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
    ob.data.materials.clear()
    ob.data.materials.append(m)
    after = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    return ob, tris, after


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--atlas", required=True)
    ap.add_argument("--organs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    A = Atlas(args.atlas)
    os.makedirs(args.out, exist_ok=True)
    for region, groups in regions(A).items():
        if args.only and region not in args.only.split(","):
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        made = []
        for name, mat, budget, names, organ in groups:
            objs = []
            if names:
                for n, V, F in A.parts(names):
                    objs.append(mesh_object(n, V, F))
            if organ:
                objs += import_organ(os.path.join(args.organs, organ[0] + ".glb"), organ[1])
            if not objs:
                print("  %s/%s: nothing found" % (region, name))
                continue
            ob, before, after = finish(objs, name, mat, budget)
            made.append(ob)
            co = np.array([v.co for v in ob.data.vertices])
            lo = co.min(0)
            hi = co.max(0)
            print("  %-7s %-10s %-9s %6d -> %5d tris   x %.3f..%.3f  y(up) %.3f..%.3f  z(front) %.3f..%.3f" % (
                region, name, mat, before, after, lo[0], hi[0], lo[2], hi[2], -hi[1], -lo[1]))
        bpy.ops.object.select_all(action="DESELECT")
        for o in made:
            o.select_set(True)
        path = os.path.join(args.out, region + ".glb")
        with contextlib.redirect_stdout(io.StringIO()):
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                      export_normals=True, export_materials="EXPORT", export_texcoords=False)
        print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
