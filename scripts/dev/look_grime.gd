extends Node3D
## Dev: how worn each soldier is (Clown._roll_grime). A row per look, the four
## kinds left to right (clean, dusty, splashed, caked), then the Rattlejack and
## the officer; the whole line and each helmet close up. Trench light.
##   godot --path . res://scenes/look_grime.tscn -- [--tag=x] [--random]
## Writes /tmp/grime_<tag>_<shot>.png.

var tag := "x"
var random := false
var cam: Camera3D
var men: Array[Clown] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		if a == "--random":
			random = true
	_stage()
	_run()


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var e := env.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.32, 0.34)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.36, 0.38, 0.42)
	e.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(20), 0)
	sun.light_color = Color(0.82, 0.86, 0.92)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var floor_ := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	fs.shape = box
	fs.position.y = -0.1
	floor_.add_child(fs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.17, 0.13)
	mat.roughness = 0.95
	pm.material = mat
	fm.mesh = pm
	floor_.add_child(fm)
	add_child(floor_)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()


func _man(body: String, look: String, kind: int, at: Vector3) -> Clown:
	var c: Clown
	match body:
		"rattlejack":
			c = Rattlejack.new()
		"zornhauptmann":
			c = Zornhauptmann.new()
		_:
			c = Clown.new()
			c.body = body
			c.look = look
	c.grime_kind = -1 if random else kind
	add_child(c)
	c.global_position = at
	c.always_pose = true
	c.set_process(true)
	men.append(c)
	return c


func _snap(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/grime_%s_%s.png" % [tag, name_])


func _run() -> void:
	seed(1916)
	for k in 4:
		_man("witzsoldat", "witzsoldat_dark", k, Vector3(-3.0 + 1.2 * k, 0, 0))
		_man("witzsoldat", "witzsoldat", k, Vector3(-3.0 + 1.2 * k, 0, -2.4))
	_man("rattlejack", "", 3, Vector3(2.4, 0, 0))
	_man("zornhauptmann", "", 1, Vector3(3.6, 0, 0))
	for i in 30:
		await get_tree().physics_frame
	for c in men:
		print(c.look if c.look != "" else c.body, " grime ", c.grime)
	cam.position = Vector3(0.3, 1.6, 7.5)
	cam.look_at(Vector3(0.3, 1.0, -1.0))
	await _snap("line")
	cam.fov = 30
	# helmets of the front row, close
	for i in 6:
		var c := men[i * 2] if i < 4 else men[4 + i]
		var head := c.global_position + Vector3(0, 1.78, 0)
		cam.position = head + Vector3(0.35, 0.28, 0.75)
		cam.look_at(head)
		await _snap("helmet%d" % i)
	# the back row (the plain look)
	for i in 4:
		var c := men[i * 2 + 1]
		var head := c.global_position + Vector3(0, 1.78, 0)
		cam.position = head + Vector3(-0.3, 0.3, 0.75)
		cam.look_at(head)
		await _snap("plain%d" % i)
	get_tree().quit()
