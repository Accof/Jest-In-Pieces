extends Node3D
## Eight clowns blown open at once (head, chest, belly, an arm off), then the
## frame time and the triangles drawn, new anatomy against the old
## (`-- --old`). Forward+: godot --path . scenes/perf_anatomy.tscn -- [--old]

var clowns: Array = []


func _ready() -> void:
	ClownGore.procedural_innards = "--old" in OS.get_cmdline_user_args()
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.4, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.4, 4.5)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.make_current()
	_run.call_deferred()


func _run() -> void:
	var bodies := ["clown", "witzsoldat", "rattlejack", "zornhauptmann"]
	for i in 8:
		var c := Clown.new()
		c.body = bodies[i % 4]
		add_child(c)
		c.global_position = Vector3((i % 4 - 1.5) * 1.1, 0, -float(i / 4) * 1.5)
		clowns.append(c)
	for i in 10:
		await get_tree().physics_frame
	var base := await _measure("intact")
	var t0 := Time.get_ticks_usec()
	for c: Clown in clowns:
		c.set_physics_process(false)
		var f := c.global_basis.z
		var hb := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(&"Head")).origin
		var ch := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(&"Chest")).origin
		var be := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(&"Spine")).origin
		c.gore.blast(&"Neck", hb + f * 0.09, -f, 0.065)
		c.gore.blast(&"Chest", ch + f * 0.12, -f, 0.095)
		c.gore.blast(&"Spine", be + f * 0.12, -f, 0.09)
		c.gore.sever(&"LeftLowerArm", Vector3(0.5, 0.3, 1.0))
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var opened := await _measure("opened")
	print("PERF %s build %.1f ms for 8 | intact %.2f ms %d tris | opened %.2f ms %d tris" % ["old" if ClownGore.procedural_innards else "new", build_ms, base[0], base[1], opened[0], opened[1]])
	get_tree().quit()


func _measure(_tag: String) -> Array:
	for i in 30:
		await get_tree().process_frame
	var t := 0.0
	var tris := 0
	var n := 120
	for i in n:
		var a := Time.get_ticks_usec()
		await get_tree().process_frame
		t += (Time.get_ticks_usec() - a) / 1000.0
		tris = maxi(tris, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	return [t / n, tris]
