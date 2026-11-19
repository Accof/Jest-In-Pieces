extends Node
## First-person captures of blood pools at the game's own size: three pools (a
## gib's, a wound's, a body's) on the floor in front of the player, after they
## have spread and settled. --sandbox: the gore sandbox; otherwise a generated
## level (seed 20261118). --tag=<name>: /tmp/look_pools_<tag>_{near,far}.png.
var tag := "x"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(n: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/look_pools_%s_%s.png" % [tag, n])


func _floor(space: PhysicsDirectSpaceState3D, at: Vector3) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 2.0, 1))
	return hit.position if not hit.is_empty() else at


func _run() -> void:
	var p: FpsPlayer
	if "--sandbox" in OS.get_cmdline_user_args():
		var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
		add_child(room)
		await get_tree().physics_frame
		p = room.player
		p.global_position = Vector3(0, 0.05, 1.5)
	else:
		Engine.set_meta(&"test_save", true)
		var game: Node3D = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		game.rng.seed = 20261118
		game.start_run()
		await _wait(0.5)
		p = game.player
		for c: Clown in game.clowns:
			c.process_mode = Node.PROCESS_MODE_DISABLED
	p.god_mode = true
	await _wait(0.3)
	var space := p.get_world_3d().direct_space_state
	var cam := p.camera
	# face down the longest clear line from where the player stands
	var best := 0.0
	var best_yaw := 0.0
	for i in 24:
		var yaw := TAU * i / 24.0
		var d := Vector3(-sin(yaw), 0, -cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + d * 40.0, 1)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var dist := 40.0 if hit.is_empty() else cam.global_position.distance_to(hit.position)
		if dist > best:
			best = dist
			best_yaw = yaw
	p.rotation.y = best_yaw
	await get_tree().physics_frame
	var fwd := Vector3(-sin(best_yaw), 0, -cos(best_yaw))
	var side := fwd.cross(Vector3.UP)
	var base := p.global_position
	# the radii the game asks for: a body (0.85), a wound (0.45), a gib (0.2)
	for s: Array in [[1.3, -0.45, 0.85], [1.6, 0.55, 0.45], [0.9, 0.35, 0.2]]:
		var at := _floor(space, base + fwd * float(s[0]) + side * float(s[1]))
		Blood.spawn_pool(at, Vector3.UP, s[2])
	await _wait(11.0)
	cam.rotation = Vector3(-0.75, 0, 0)
	await _shot("near")
	cam.rotation = Vector3(-0.3, 0, 0)
	await _shot("far")
	get_tree().quit()
