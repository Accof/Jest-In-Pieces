extends Node3D
## Dev: three bodies shot a few times each (no kill), in dim warm bunker
## light with a lantern, filmed close to judge the blood soaking.
## godot res://scenes/look_blood.tscn -- <out-prefix>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/k/blood"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.03, 0.035)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.16, 0.15, 0.15)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	lamp.position = Vector3(1.2, 2.3, 1.8)
	lamp.shadow_enabled = true
	add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -40, 0)
	fill.light_energy = 0.25
	add_child(fill)
	var floor_ := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	fm.mesh = pm
	floor_.add_child(fm)
	add_child(floor_)
	var bodies := ["clown", "witzsoldat", "rattlejack"]
	var cs: Array[Clown] = []
	for i in bodies.size():
		var c := Clown.new()
		c.body = bodies[i]
		c.max_health = 100000.0
		add_child(c)
		c.position = Vector3(-1.0 + 1.0 * i, 0, 0)
		cs.append(c)
	for f in 5:
		await get_tree().physics_frame
	var id := 1
	for c in cs:
		c.health = 100000.0
		for spot: Array in [[&"Chest", Vector3(0.05, 0.08, 0)], [&"Spine", Vector3(-0.07, -0.02, 0)], [&"UpperLeg", Vector3(0, 0, 0)], [&"Chest", Vector3(-0.08, -0.05, 0)]]:
			var key: StringName = spot[0]
			var pb: PhysicalBone3D = c.ragdoll.bones.get(key, c.ragdoll.bones.get(StringName("Left" + key), null))
			if pb == null:
				pb = c.ragdoll.bones[&"LeftUpperLeg"]
			id += 1
			c.hit({collider = pb, position = pb.global_position + Vector3(0, 0, 0.12) + spot[1], direction = Vector3(0, 0, -1), damage = 14.0, impulse = 0.5, shot_id = id, weapon = "Pistol", dist = 6.0})
			for f in 6:
				await get_tree().physics_frame
	for f in 150:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 38
	var shots := [[Vector3(0, 1.3, 3.4), Vector3(0, 1.0, 0)], [Vector3(1.0, 1.35, 1.25), Vector3(1.0, 1.15, 0)], [Vector3(0.0, 1.35, 1.25), Vector3(0.0, 1.15, 0)]]
	for i in shots.size():
		cam.position = shots[i][0]
		cam.look_at(shots[i][1])
		cam.make_current()
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, i])
	get_tree().quit()
