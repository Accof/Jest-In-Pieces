extends Node3D
## Exposed anatomy up close, in the game's own environment: a body of each kind
## with its head, chest and belly blown open, an arm off, a knee broken, and
## the severed arm lying in front; lit as a bunker (a bare bulb) or a trench
## (overcast sky and a low sun).
##   godot --rendering-method forward_plus res://scenes/look_anatomy.tscn -- --body=clown --light=bunker --tag=after
## Writes /tmp/anat_<tag>_<body>_<light>_<view>.png
##   --ragdoll   kill it first and film the corpse (does it all stay with the bones?)
var body := "clown"
var light := "bunker"
var tag := "x"
var cam: Camera3D
var c: Clown


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--body="):
			body = a.substr(7)
		elif a.begins_with("--light="):
			light = a.substr(8)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	_build()
	_run()


func _build() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.065, 0.075)
	sky_mat.sky_horizon_color = Color(0.26, 0.24, 0.23)
	sky_mat.ground_bottom_color = Color(0.04, 0.035, 0.03)
	sky_mat.ground_horizon_color = Color(0.2, 0.18, 0.16)
	sky_mat.sky_energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.31, 0.34)
	env.ambient_light_energy = 0.2 if light == "bunker" else 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if light == "bunker" else Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if light == "bunker":
		var bulb := OmniLight3D.new()
		bulb.light_color = Color(1.0, 0.78, 0.52)
		bulb.light_energy = 2.6
		bulb.omni_range = 7.0
		bulb.shadow_enabled = true
		bulb.position = Vector3(0.6, 2.4, 1.2)
		add_child(bulb)
	else:
		var sun := DirectionalLight3D.new()
		sun.light_color = Color(0.58, 0.62, 0.72)
		sun.light_energy = 0.9
		sun.shadow_enabled = true
		sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(25.0), 0.0)        # low overcast light on the front (the wall is behind)
		add_child(sun)
	# floor and a wall behind
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_texture = load("res://art/level/floor_conc.png")
	floor_m.uv1_triplanar = true
	floor_m.roughness = 0.85
	for b: Array in [[Vector3(12, 0.2, 12), Vector3(0, -0.1, 0)], [Vector3(12, 4, 0.3), Vector3(0, 2, -1.5)]]:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[0]
		cs.shape = sh
		sb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.material_override = floor_m
		sb.add_child(mi)
		sb.position = b[1]
		add_child(sb)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()


func _bone(b: StringName) -> Vector3:
	var bi := c.skeleton.find_bone(b)
	if c.ragdoll.active:
		return c.skeleton.global_transform * c.ragdoll.bone_pose(bi).origin
	return c.skeleton.global_transform * c.skeleton.get_bone_global_pose(bi).origin


func _shot(view: String, at: Vector3, from: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/anat_%s_%s_%s_%s.png" % [tag, body, light, view])


func _run() -> void:
	ClownGore.procedural_innards = "--old" in OS.get_cmdline_user_args()
	c = Clown.new()
	c.body = body
	add_child(c)
	c.global_position = Vector3(0, 0, 0)
	for i in 10:
		await get_tree().physics_frame
	c.set_physics_process(false)
	var fwd := c.global_basis.z          # the body faces +Z
	if c.has_method("knock_off_helmet") and c.get("_helmet") != null:
		c.knock_off_helmet(Vector3(1, 0.5, 0), _bone(&"Head") + Vector3.UP * 0.15)
		for i in 5:
			await get_tree().physics_frame
	var head := _bone(&"Head")
	var chest := _bone(&"Chest") + Vector3.UP * 0.06
	var belly := _bone(&"Spine")
	c.gore.blast(&"Neck", head + Vector3(0.0, 0.06, 0.0) + fwd * 0.09, -fwd, 0.065)
	# and the crown blown off: the brain under it (the head's top, found along the up axis)
	var top := head + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(top, head, 1 << 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var crown: Vector3 = hit.position if not hit.is_empty() else head + Vector3.UP * 0.12
	c.gore.blast(&"Neck", crown + fwd * 0.02, Vector3.DOWN, 0.06)
	c._head_open = true
	if "--punch" in OS.get_cmdline_user_args():
		c.gore.punch_through(&"Chest", chest + fwd * 0.12, -fwd, c.punch_radius)    # point-blank shotgun, clean through
	else:
		c.gore.blast(&"Chest", chest + fwd * 0.12, -fwd, 0.095)
	c.gore.blast(&"Spine", belly + fwd * 0.12, -fwd, 0.09)
	c.gore.show_broken_knee("Right")
	c.gore.show_broken_arm("Right")
	c.gore.sever(&"LeftLowerArm", Vector3(0.6, 0.4, 1.2))
	c.gore.sever(&"LeftLowerLeg", Vector3(0.3, 0.2, 0.9))
	var behead := "--behead" in OS.get_cmdline_user_args()
	if behead:
		c.gore.sever(&"Neck", Vector3(0.2, 1.0, 0.4))
	var ragdoll := "--ragdoll" in OS.get_cmdline_user_args()
	if ragdoll:
		c.health = -1.0
		c._die({direction = -fwd, heavy = true, pinned = false}, &"Chest")
		for i in 150:
			await get_tree().physics_frame
	else:
		for i in 150:                    # (the blood mist settles)
			await get_tree().physics_frame
	# blood off the lens: remove decals that would hide what is being judged? (no: keep the game's look)
	head = _bone(&"Head") + Vector3.UP * 0.07
	chest = _bone(&"Chest") + Vector3.UP * 0.05
	belly = _bone(&"Spine")
	var knee := _bone(&"RightLowerLeg")
	if ragdoll:
		await _shot("corpse", chest, chest + Vector3(0.9, 1.1, 1.2))
		await _shot("corpse_head", head, head + Vector3(0.3, 0.45, 0.35))
		get_tree().quit()
		return
	await _shot("1_head", head, head + Vector3(0.12, 0.12, 0.42))
	await _shot("2_head_top", head, head + Vector3(0.0, 0.42, 0.22))
	await _shot("3_chest", chest, chest + Vector3(0.1, 0.06, 0.5))
	await _shot("4_belly", belly, belly + Vector3(-0.12, 0.04, 0.5))
	await _shot("5_body", (chest + belly) * 0.5, (chest + belly) * 0.5 + Vector3(0.5, 0.15, 1.5))
	var stump := _bone(&"LeftLowerArm")
	await _shot("6_stump", stump, stump + Vector3(0.35, -0.05, 0.3))
	await _shot("7_knee", knee, knee + Vector3(-0.3, 0.1, 0.45))
	var arm := (_bone(&"RightLowerArm") + _bone(&"RightHand")) * 0.5
	await _shot("9_arm", arm, arm + Vector3(-0.15, 0.25, 0.35))
	var leg := _bone(&"LeftLowerLeg")
	await _shot("10_leg_stump", leg, leg + Vector3(0.3, -0.25, 0.35))
	if behead:
		var neck := _bone(&"Chest") + Vector3.UP * 0.25
		await _shot("11_neck", neck, neck + Vector3(0.2, 0.35, 0.3))
	var k := 0
	for n in get_children():
		if n is Gib and k < 3:
			var gp: Vector3 = (n as Gib).global_position
			await _shot("8_gib%d" % k, gp, gp + Vector3(0.25, 0.35, 0.35))
			k += 1
	print("ANAT done")
	get_tree().quit()
