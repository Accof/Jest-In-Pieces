extends Node3D
## Dev: film one enemy body in good light from a few angles.
## godot res://scenes/look_body.tscn -- <body> <out-prefix> [walk]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var body: String = args[0] if args.size() > 0 else "witzsoldat"
	var out: String = args[1] if args.size() > 1 else "/tmp/k/look"
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.3, 0.3, 0.33)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 35, 0); sun.light_energy = 1.0; add_child(sun)
	var floor_ := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); floor_.mesh = pm; add_child(floor_)
	var c: Clown = (load("res://scripts/clown/klappersoldat.gd").new() if body == "klappersoldat" else Clown.new())
	if body != "klappersoldat":
		c.body = body
	add_child(c)
	await get_tree().process_frame
	var cam := Camera3D.new(); add_child(cam); cam.fov = 40
	var shots := [[Vector3(0, 1.72, 0.6), Vector3(0, 1.7, 0)], [Vector3(0.9, 1.75, 0.15), Vector3(0, 1.72, 0)], [Vector3(0, 1.1, 3.6), Vector3(0, 0.95, 0)], [Vector3(2.6, 1.1, -2.2), Vector3(0, 0.95, 0)], [Vector3(-0.5, 1.8, -0.9), Vector3(0, 1.5, 0)]]
	for i in shots.size():
		cam.position = shots[i][0]; cam.look_at(shots[i][1])
		for f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, i])
	get_tree().quit()
