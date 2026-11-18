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

## Any gun, either hand (sdf2.py, handfk2.py, fit.py)
Used for the Trench Shotgun:
1. `godot --headless --path . res://scenes/test_trench.tscn -- --dump --side=R` (or L;
   add `--grip` to try /tmp/grip_t.txt)
2. `python3 sdf2.py Body -0.36 -0.10 0.0 0.22 -0.09 0.09 /tmp/fit/sdf_R.npz`
   (parts, then the box x0 x1 y0 y1 z0 z1 in gun-model space)
3. `NOSHIFT=1 SIDE=R TARGET=-0.164,0.087,0.003 python3 fit.py /tmp/fit/sdf_R.npz`
   prints each finger's curl that rests on the surface; with TARGET the index
   finger is aimed at that point (the trigger) instead. Without NOSHIFT it also
   searches a small hand offset that keeps the palm out (move the knuckle targets
   by it, then dump and fit again).
