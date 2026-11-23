extends Node3D
## Dev: how a rifleman's arms go when he is killed aiming (left) and
## crouched (right): the old settings (arms pulled all the way to hanging,
## full reflex fling, thrown wide) beside the new, frame by frame.
##   godot --path . res://scenes/look_rifle_death.tscn -- [--old] [--tag=x]
## Writes /tmp/rdeath_<tag>_<ms>.png (both men, from the front, at 0, 100,
## 250, 500, 900 and 1800 ms after the shot).

var tag := "new"
var pair: Array[Clown] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	if "--old" in OS.get_cmdline_user_args():
		Clown.rifle_arm_settle = 1.0
		Clown.rifle_arm_fling = 1.0
		Clown.rifle_arms_wide = true
		Clown.rifle_arm_tone = 1.0
		if tag == "new":
			tag = "old"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.4, 0.44)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_ := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	floor_.add_child(cs)
	floor_.position.y = -0.1
	floor_.collision_layer = 1
	add_child(floor_)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	fm.mesh = pm
	add_child(fm)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	seed(1917)
	for i in 2:
		var c := Clown.new()
		c.body = "witzsoldat"
		c.look = "witzsoldat_dark"
		add_child(c)
		c.global_position = Vector3(-0.9 + 1.8 * i, 0, 0)
		c.give_rifle()
		c.always_pose = true
		c.set_process(true)
		pair.append(c)
	await _frames(10)
	for i in 2:
		var c := pair[i]
		c.walk_amount = 0.0
		c.run_amount = 0.0
		c.aim_amount = 1.0 if i == 0 else 0.3
		c.crouch_amount = 0.0 if i == 0 else 1.0
		c.aim_point = c.global_position + c.global_basis.z * 8.0 + Vector3.UP * 1.3
	await _frames(70)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45
	cam.position = Vector3(0, 1.3, 5.0)
	cam.look_at(Vector3(0, 0.9, 0))
	await _shot(0)
	for c in pair:
		seed(5)
		var pb: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
		c.hit({collider = pb, position = pb.global_position + c.global_basis.z * 0.12, direction = -c.global_basis.z, damage = 300.0,
			impulse = 4.0, heavy = false, can_dismember = false, shot_id = 9})
	var at := 0
	for ms: int in [100, 250, 500, 900, 1800]:
		await _frames(int((ms - at) * 0.06))
		at = ms
		await _shot(ms)
	get_tree().quit()


func _shot(ms: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/rdeath_%s_%04d.png" % [tag, ms])
