extends Node3D
## Dev: the WitzSoldat's two looks side by side (the original on the left, the
## dark one on the right), driven through the same states at the same moments:
## stand, walk, run, turning, aimed, firing and the bolt, a flinch from a hit,
## the club's swing, a death, then the corpses. Bunker or trench light.
##   godot --path . res://scenes/look_witz_looks.tscn -- [--light=bunker|trench] [--tag=x]
## Writes /tmp/witz_<tag>_<light>_<state>_<front|side>.png.

var pair: Array[Clown] = []
var light := "bunker"
var tag := "x"
var cam: Camera3D
var speed := 0.0
var turning := 0.0
var mud := -1.0         # --mud=x: every uniform this muddy (else each man's own)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--light="):
			light = a.substr(8)
		if a.begins_with("--mud="):
			mud = float(a.substr(6))
		if a.begins_with("--tag="):
			tag = a.substr(6)
	_stage()
	_run()


func _physics_process(delta: float) -> void:
	for c in pair:
		if c.dead:
			continue
		c.rotation.y += turning * delta
		c.velocity = c.global_basis.z * speed


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var e := env.environment
	e.background_mode = Environment.BG_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if light == "trench":
		e.background_color = Color(0.32, 0.34, 0.36)
		e.ambient_light_color = Color(0.36, 0.38, 0.42)
		e.ambient_light_energy = 0.7
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-30), deg_to_rad(25), 0)
		sun.light_color = Color(0.82, 0.86, 0.92)
		sun.light_energy = 1.1
		sun.shadow_enabled = true
		add_child(sun)
	else:
		e.background_color = Color(0.02, 0.018, 0.015)
		e.ambient_light_color = Color(0.25, 0.18, 0.12)
		e.ambient_light_energy = 0.35
		for p: Vector3 in [Vector3(-1.6, 2.4, 1.8), Vector3(1.8, 2.2, 0.6)]:
			var l := OmniLight3D.new()
			l.position = p
			l.light_color = Color(1.0, 0.72, 0.42)
			l.light_energy = 2.6
			l.omni_range = 7.0
			l.shadow_enabled = true
			add_child(l)
	add_child(env)
	var floor_ := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	fs.shape = box
	fs.position.y = -0.1
	floor_.add_child(fs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.18, 0.14) if light == "bunker" else Color(0.2, 0.17, 0.13)
	mat.roughness = 0.95
	pm.material = mat
	fm.mesh = pm
	floor_.add_child(fm)
	add_child(floor_)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(state: String, views := ["front", "side"]) -> void:
	for v: String in views:
		var mid := Vector3(0, 1.05, 0)
		match v:
			"front":
				cam.position = Vector3(0, 1.35, 4.6)
			"side":
				cam.position = Vector3(4.6, 1.35, 0.4)
			"close":
				cam.position = Vector3(0, 1.7, 2.0)
				mid = Vector3(0, 1.6, 0)
			"legs":
				cam.position = Vector3(0.6, 0.75, 2.3)
				mid = Vector3(0, 0.55, 0)
			"floor":
				cam.position = Vector3(0.3, 2.2, 3.4)
				mid = Vector3(0, 0.25, -0.2)
		cam.look_at(mid)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/witz_%s_%s_%s_%s.png" % [tag, light, state, v])


func _state(walk: float, run: float, aim: float, attack := 0.0) -> void:
	for c in pair:
		c.walk_amount = walk
		c.run_amount = run
		c.aim_amount = aim
		c.attack_amount = attack
		c.aim_point = c.global_position + c.global_basis.z * 8.0 + Vector3.UP * 1.3


func _run() -> void:
	seed(1917)
	for i in 2:
		var c := Clown.new()
		c.body = "witzsoldat"
		c.look = ["witzsoldat", "witzsoldat_dark"][i]
		add_child(c)
		c.global_position = Vector3(-0.75 + 1.5 * i, 0, 0)
		c.give_rifle()
		c.always_pose = true
		c.set_process(true)
		pair.append(c)
	await _frames(20)
	for c in pair:
		if mud >= 0.0:
			for m: ShaderMaterial in c.gore._materials:
				m.set_shader_parameter("mud_amount", mud)
		print("mud ", c.look, " ", c.gore.mud_level, " -> ", c.gore._materials[0].get_shader_parameter("mud_amount"))
	_state(0, 0, 0)
	await _frames(30)
	await _shot("1_stand", ["front", "side", "close", "legs"])
	speed = 1.5
	_state(1, 0, 0)
	await _frames(37)
	await _shot("2_walk")
	speed = 5.0
	_state(1, 1, 0)
	await _frames(41)
	await _shot("3_run")
	speed = 0.0
	turning = 1.6
	_state(0.4, 0, 0)
	await _frames(25)
	await _shot("4_turn", ["front"])
	turning = 0.0
	for c in pair:
		c.rotation.y = 0.0
	_state(0, 0, 1)
	await _frames(60)
	await _shot("5_aim", ["front", "side", "close"])
	for c in pair:
		c.fired()
	await _frames(3)
	await _shot("6_fire", ["side"])
	await _frames(40)
	await _shot("7_bolt", ["side", "close"])
	await _frames(60)
	_state(0, 0, 0)
	await _frames(30)
	# a hit: the same flinch on each
	for c in pair:
		var ch := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(&"Chest")).origin
		c._flinch_from(ch + Vector3(0.05, 0, 0.12), -c.global_basis.z, 30.0)
	await _frames(6)
	await _shot("8_hit", ["front"])
	await _frames(40)
	# the club's swing (one in four carries one): the same pose from the attack value
	for c in pair:
		c._drop_rifle()
		c.has_rifle = false
		c.has_gun = false
		c.give_club()
	_state(0, 0, 0, 0.9)
	await _frames(20)
	await _shot("9_club", ["front", "side"])
	_state(0, 0, 0, 0.0)
	await _frames(20)
	# killed by the same body shot
	for c in pair:
		seed(3)
		var pb: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
		c.hit({collider = pb, position = pb.global_position + c.global_basis.z * 0.12, direction = -c.global_basis.z, damage = 300.0,
			impulse = 8.0, heavy = true, can_dismember = false, shot_id = 9})
	await _frames(20)
	await _shot("10_dying", ["front", "side"])
	await _frames(200)
	await _shot("11_dead", ["front", "floor"])
	get_tree().quit()
