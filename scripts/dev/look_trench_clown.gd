extends Node3D
## Dev: the trench clown (24 Nov 2026) as the game builds him - standing with
## his club, mid-swing, walking, and after a round through the chest (the
## ragdoll), from the front and the side.
##   godot --path . res://scenes/look_trench_clown.tscn [-- --tag=x]
## Writes /tmp/tclown_<tag>_<view>.png.

var tag := "a"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
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
	sun.shadow_enabled = true
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
	var men: Array[Clown] = []
	for i in 3:
		var c := Clown.new()
		c.body = "clown"
		add_child(c)
		c.global_position = Vector3(-1.6 + 1.6 * i, 0, 0)
		c.give_club()
		c.always_pose = true
		c.set_process(true)
		men.append(c)
	await _frames(10)
	men[0].walk_amount = 0.0
	men[1].walk_amount = 1.0
	men[1].drive_phase = true
	men[2].attack_amount = 0.85
	await _frames(70)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.position = Vector3(0, 1.2, 6.0)
	cam.look_at(Vector3(0, 0.95, 0))
	await _shot("front")
	cam.position = Vector3(5.5, 1.2, 2.5)
	cam.look_at(Vector3(0, 0.95, 0))
	await _shot("side")
	cam.position = Vector3(0.6, 1.75, 1.4)
	cam.look_at(men[1].global_position + Vector3.UP * 1.6)
	await _shot("face")
	# a round through the chest of the middle one, and the ragdoll takes him
	cam.position = Vector3(0, 1.2, 6.0)
	cam.look_at(Vector3(0, 0.95, 0))
	seed(5)
	var c := men[1]
	var pb: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	c.hit({collider = pb, position = pb.global_position + c.global_basis.z * 0.12, direction = -c.global_basis.z, damage = 300.0,
		impulse = 4.0, heavy = false, can_dismember = false, shot_id = 9})
	await _frames(30)
	await _shot("death_500ms")
	await _frames(120)
	await _shot("death_2500ms")
	get_tree().quit()


func _shot(view: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/tclown_%s_%s.png" % [tag, view])
	print("shot ", view)
