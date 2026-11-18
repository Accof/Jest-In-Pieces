extends Node
## First-person captures of the rifle in a generated level (the game's own bunker and
## trench lighting): hip, aimed, bolt fully open, bolt closed; the Webley, trench gun and
## MP 18 alongside for comparison. Pass --tag=<name>: /tmp/look_rifle_<tag>_*.png.
var tag := "x"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	_run()


func _shot(n: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/look_rifle_%s_%s.png" % [tag, n])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	var p: FpsPlayer
	if "--sandbox" in OS.get_cmdline_user_args():
		var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
		add_child(room)
		await get_tree().physics_frame
		p = room.player
		p.global_position = Vector3(0, 0.05, 1.5)
		await _wait(0.5)
	else:
		Engine.set_meta(&"test_save", true)
		var game: Node3D = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		game.rng.seed = 20261118                                  # the same level every time
		game.start_run()
		await _wait(0.5)
		p = game.player
		for c: Clown in game.clowns:
			c.process_mode = Node.PROCESS_MODE_DISABLED            # nobody interrupts
	p.god_mode = true
	# face down the longest clear line from the start
	var best := 0.0
	var best_yaw := 0.0
	var space := p.get_world_3d().direct_space_state
	for i in 24:
		var yaw := TAU * i / 24.0
		var d := Vector3(-sin(yaw), 0, -cos(yaw))
		var from := p.camera.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 40.0, 1)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var dist := 40.0 if hit.is_empty() else from.distance_to(hit.position)
		if dist > best:
			best = dist
			best_yaw = yaw
	p.rotation.y = best_yaw
	p.camera.rotation.x = -0.05
	var v := p.view
	for k: Array in [[FpsPlayer.REVOLVER, "webley"], [FpsPlayer.TRENCH, "trench"], [FpsPlayer.MP18, "mp18"]]:
		p.select_weapon(k[0])
		await _wait(0.6)
		await _shot(k[1])
	p.select_weapon(FpsPlayer.RIFLE)
	await _wait(0.8)
	await _shot("1_hip")
	p.aim_override = 1.0
	await _wait(0.7)
	if "--droptest" in OS.get_cmdline_user_args():
		var arm: FPArm = v._arms[ViewModel.RIFLE]["R"]
		for d in [0.0, 26.0, -26.0, 40.0, -40.0]:
			v.aim_drop = d
			await _wait(0.1)
			var sk := arm.skeleton
			var top := -9.0
			var cam := p.camera
			for b in sk.get_bone_count():
				var q := cam.to_local(sk.global_transform * sk.get_bone_global_pose(b).origin)
				if q.z < 0.0:
					top = maxf(top, q.y / -q.z)          # the highest a bone reaches on screen (tan of its angle)
			print("drop %+.0f: highest bone at %.1f deg" % [d, rad_to_deg(atan(top))])
		v.aim_drop = ViewModel.L_AIM_WRIST_DROP
	await _shot("2_aimed")
	p.aim_override = 0.0
	await _wait(0.6)
	# bolt fully open: hold the cycle at the back
	v.rifle_cycle()
	v._cycle_t = 0.45
	p.set_process(false); p.set_physics_process(false)
	v._le_done["eject"] = true
	v.animate(0.0, 0.0, Vector2.ZERO)
	v.set_process(false)
	await _shot("3_open")
	v._cycle_t = -1.0
	v.animate(0.0, 0.0, Vector2.ZERO)
	await _shot("4_closed")
	print("LOOK done (%s)" % tag)
	get_tree().quit()
