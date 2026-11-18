import bpy, math
from mathutils import Euler
bpy.ops.wm.open_mainfile(filepath='/tmp/arm/out/arms.blend')
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
for o in bpy.data.objects:
    if o.animation_data: o.animation_data_clear()
O = bpy.data.objects
D = math.radians
FINGERS = ['index', 'middle', 'ring', 'little']
def curl(a, b, c):
    out = {}
    for n in FINGERS:
        out[f'{n}_01'] = (a, 0, 0); out[f'{n}_02'] = (b, 0, 0); out[f'{n}_03'] = (c, 0, 0)
    return out
POSES = {
    'open': {},
    'fist': {**curl(80, 95, 60), 'thumb_01': (25, 0, 0), 'thumb_02': (35, 0, 0), 'thumb_03': (40, 0, 0)},
    'grip': {**curl(70, 85, 45), 'thumb_01': (30, 0, 0), 'thumb_02': (20, 0, 0), 'thumb_03': (25, 0, 0)},
    'trigger': {**curl(70, 85, 45), 'index_01': (30, 0, 0), 'index_02': (45, 0, 0), 'index_03': (25, 0, 0),
                'thumb_01': (30, 0, 0), 'thumb_02': (20, 0, 0), 'thumb_03': (25, 0, 0)},
}
for side in ('L', 'R'):
    rig = O[f'ArmRig_{side}']
    rig.animation_data_create()
    for pname, pose in POSES.items():
        act = bpy.data.actions.new(f'{pname}')
        rig.animation_data.action = act
        for pb in rig.pose.bones:
            pb.rotation_mode = 'XYZ'
            x, y, z = pose.get(pb.name[:-2], (0, 0, 0))
            pb.rotation_euler = Euler((D(x), D(y), D(z)), 'XYZ')
            pb.keyframe_insert('rotation_euler', frame=1)
        track = rig.animation_data.nla_tracks.new(); track.name = pname
        track.strips.new(pname, 1, act)
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_euler = (0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True); O[f'Arm_{side}'].select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=f'/tmp/arm/out/sep/arm_{side}.gltf', export_format='GLTF_SEPARATE', export_texture_dir='textures', use_selection=True,
        export_yup=True, export_skins=True, export_animations=True, export_nla_strips=True,
        export_tangents=True, export_image_format='AUTO', export_def_bones=False, export_animation_mode='NLA_TRACKS')
bpy.ops.wm.save_as_mainfile(filepath='/tmp/arm/out/arms.blend')
