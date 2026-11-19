"""Build the WW1 stick grenade (a temporary model) for the game.

    python3 art/weapons/grenade/source/build_stick_grenade.py art/weapons/grenade

Writes stick_grenade.glb: a Stielhandgranate-style grenade at real size,
about 36 cm overall:
  Head    the steel can, 7 cm across and 10 cm tall, field-grey paint worn
          through to dark steel and rust, mud caked on the lower half, scratches
  Handle  the wooden handle, 2.6 cm thick and 25 cm long, grain, grime and dents
  Collar  the steel collar joining them
  Cap     the screw cap on the handle's end (the pull cord is behind it)
  Grip    an empty where the hand holds it, near the cap end
  Fuse    an empty at the end of the handle (where the fuse smoke comes out)

Axes (glTF, as Godot sees them): the grenade along +Y, the head at the top;
the origin at its balance point, about a third of the way down from the head.

The textures are generated here (numpy), not painted: replace the GLB with a
proper asset whenever there is one. The game only needs the node names above.
"""
import math
import os
import sys

import bpy
import numpy as np

OUT = sys.argv[-1]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng = np.random.default_rng(1916)
N = 512


def noise(n, octaves=5, base=4):
    out = np.zeros((n, n))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        k = base * 2 ** o
        g = rng.random((k + 1, k + 1))
        # bilinear upsample, wrapping in u so the cylinder's seam does not show
        g[:, -1] = g[:, 0]
        x = np.linspace(0, k, n, endpoint=False)
        i = np.floor(x).astype(int)
        f = x - i
        f = f * f * (3 - 2 * f)
        a = g[i][:, i] * (1 - f)[None, :] + g[i][:, i + 1] * f[None, :]
        b = g[i + 1][:, i] * (1 - f)[None, :] + g[i + 1][:, i + 1] * f[None, :]
        out += amp * (a * (1 - f)[:, None] + b * f[:, None])
        tot += amp
        amp *= 0.5
    return out / tot


def scratches(n, count, light):
    m = np.zeros((n, n))
    for _ in range(count):
        x0, y0 = rng.random(2) * n
        ang = rng.normal(0.0, 0.5) + (0 if rng.random() < 0.5 else math.pi / 2)
        ln = rng.uniform(12, 70)
        for t in np.linspace(0, ln, int(ln * 2)):
            x = int(x0 + math.cos(ang) * t) % n
            y = int(y0 + math.sin(ang) * t) % n
            m[y, x] = max(m[y, x], light * rng.uniform(0.5, 1.0))
    return m


def save(name, rgb):
    img = bpy.data.images.new(name, N, N, alpha=False)
    px = np.ones((N, N, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(px[::-1].ravel())      # Blender's rows run bottom up
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


# --- the head: field grey, chipped to steel and rust, mud low down ---------------
v = np.linspace(0, 1, N)[:, None] * np.ones((1, N))            # v: 0 top of the image .. 1 bottom
paint = np.array([0.30, 0.32, 0.27])
steel = np.array([0.16, 0.16, 0.17])
rust = np.array([0.33, 0.18, 0.09])
mud = np.array([0.20, 0.15, 0.10])
n1 = noise(N, 6, 4)
n2 = noise(N, 5, 8)
n3 = noise(N, 4, 3)
chip = np.clip((n2 - 0.62) * 8.0, 0, 1)                        # paint worn off
rusty = np.clip((n1 - 0.55) * 5.0, 0, 1) * chip
mud_amt = np.clip((n3 * 0.9 + v * 0.8 - 0.95) * 3.0, 0, 1)    # caked on the lower half
col = paint[None, None] * (0.85 + 0.3 * n1[..., None])
col = col * (1 - chip[..., None]) + steel * chip[..., None]
col = col * (1 - rusty[..., None]) + rust * rusty[..., None]
col = col * (1 - mud_amt[..., None]) + mud * (0.8 + 0.4 * n2[..., None]) * mud_amt[..., None]
sc = scratches(N, 90, 0.35)
col = col + sc[..., None] * np.array([0.9, 0.9, 0.85])
head_img = save("grenade_head", col)
rough = np.clip(0.55 + 0.25 * mud_amt + 0.15 * rusty - 0.3 * sc - 0.12 * chip, 0, 1)
metal = np.clip(chip * 0.8 * (1 - rusty) * (1 - mud_amt) + sc * 0.6, 0, 1)
head_orm = save("grenade_head_orm", np.stack([np.ones_like(rough), rough, metal], -1))

# --- the handle: beech, grain along it, grime from hands, dents -------------------
grain = noise(N, 3, 2)
lines = 0.5 + 0.5 * np.sin((np.linspace(0, 1, N)[None, :] * 60.0 + grain * 9.0) * math.pi)
wood = np.array([0.46, 0.33, 0.19])
dark = np.array([0.25, 0.17, 0.10])
grime = np.clip((noise(N, 5, 6) - 0.45) * 2.5, 0, 1)
col = wood * (0.8 + 0.25 * lines[..., None]) * (0.9 + 0.2 * grain[..., None])
col = col * (1 - 0.65 * grime[..., None]) + dark * 0.65 * grime[..., None]
col = col * (1 - mud_amt[..., None] * 0.6) + mud * mud_amt[..., None] * 0.6
dents = scratches(N, 40, 0.25)
col = col - dents[..., None] * 0.35
handle_img = save("grenade_handle", col)
rough_h = np.clip(0.72 - 0.25 * grime + 0.1 * mud_amt, 0, 1)      # handled smooth where gripped
handle_orm = save("grenade_handle_orm", np.stack([np.ones_like(rough_h), rough_h, np.zeros_like(rough_h)], -1))


def material(name, img, orm, metal_default=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if orm is not None:
        t2 = nt.nodes.new("ShaderNodeTexImage")
        t2.image = orm
        t2.image.colorspace_settings.name = "Non-Color"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t2.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = metal_default
        bsdf.inputs["Roughness"].default_value = 0.5
    return m


head_mat = material("GrenadeHead", head_img, head_orm)
handle_mat = material("GrenadeHandle", handle_img, handle_orm)
steel_mat = bpy.data.materials.new("GrenadeSteel")
steel_mat.use_nodes = True
b = steel_mat.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.11, 0.11, 0.115, 1)
b.inputs["Metallic"].default_value = 0.85
b.inputs["Roughness"].default_value = 0.5

# Blender axes: Z up along the grenade; glTF export turns Z into +Y.
HEAD_R, HEAD_H = 0.035, 0.10
HANDLE_R, HANDLE_L = 0.013, 0.25
COLLAR_R, COLLAR_H = 0.017, 0.022
# from the head's top down: head, collar, handle, cap
top = 0.0
parts = []


def cyl(name, r, h, z_top, mat, verts=24, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(0, 0, z_top - h / 2))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier="bevel")
    bpy.ops.object.shade_smooth()
    return o


head = cyl("Head", HEAD_R, HEAD_H, top, head_mat, 32, 0.006)
collar = cyl("Collar", COLLAR_R, COLLAR_H, top - HEAD_H + 0.004, steel_mat, 20, 0.002)
handle = cyl("Handle", HANDLE_R, HANDLE_L, top - HEAD_H - COLLAR_H + 0.008, handle_mat, 16, 0.002)
end = top - HEAD_H - COLLAR_H - HANDLE_L + 0.008
cap = cyl("Cap", HANDLE_R + 0.0015, 0.016, end + 0.006, steel_mat, 16, 0.002)
# the head's crimped top rim and the hook-clip on its side
rim = cyl("Rim", HEAD_R + 0.0012, 0.006, top - 0.004, steel_mat, 32, 0.001)
rim.parent = head
bpy.ops.mesh.primitive_cube_add(size=1, location=(HEAD_R + 0.004, 0, top - HEAD_H * 0.55))
clip = bpy.context.active_object
clip.name = "Clip"
clip.scale = (0.004, 0.012, 0.05)
bpy.ops.object.transform_apply(scale=True)
clip.data.materials.append(steel_mat)
clip.parent = head
total = HEAD_H + COLLAR_H + HANDLE_L - 0.016 + 0.016
# balance point: the head is about two thirds of the weight
mass_head, mass_handle = 0.4, 0.2
z_head = top - HEAD_H / 2
z_handle = top - HEAD_H - COLLAR_H - HANDLE_L / 2
balance = (mass_head * z_head + mass_handle * z_handle) / (mass_head + mass_handle)
for o in bpy.data.objects:
    if o.parent is None:
        o.location.z -= balance
# markers
for name, z in (("Grip", end + 0.06 - balance), ("Fuse", end - 0.002 - balance), ("HeadCentre", z_head - balance)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = (0, 0, z)
print("overall %.3f m, balance %.3f m below the top, head centre %.3f, grip %.3f, fuse %.3f above the origin" % (
    top - end + 0.002, -balance, z_head - balance, end + 0.06 - balance, end - balance))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "stick_grenade.glb"), export_format="GLB", export_yup=True,
                          export_image_format="AUTO")
for f in ("grenade_head", "grenade_head_orm", "grenade_handle", "grenade_handle_orm"):
    p = os.path.join(OUT, f + ".png")
    if os.path.exists(p):
        os.remove(p)                   # packed into the GLB
