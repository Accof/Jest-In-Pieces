# Grip fitting (keeps fingers out of the gun)

1. `godot --headless --path . res://scenes/test_arms.tscn -- --dump`
   (with an optional /tmp/grip.txt to try a grip) writes /tmp/gun_tris.txt,
   /tmp/hand_verts.txt (skinned right-arm vertices) and /tmp/hand_bones.txt,
   all in gun-model space.
2. `python3 sdf.py` builds /tmp/sdf.npz, a signed distance grid around the grip
   (Frame, Hammer, Cylinder; the Tripo normals point inward, so the sign is flipped).
3. `python3 search2.py` / `thumb.py` pose each finger with `handfk.py` (each vertex
   rigid on its strongest bone) and pick the curl where every segment rests on the
   grip without entering it. The hand shift (z +0.01) is set in those scripts.
4. `python3 wind.py` checks the dumped vertices with a winding-number test
   (works on the open Tripo mesh) and prints how many are inside per bone.

Needs: pip install trimesh rtree scipy
