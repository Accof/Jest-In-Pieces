extends Node
## Walks the player down the Grand Staircase and back up, holding W, and
## reports whether he gets stuck anywhere.

func _ready() -> void:
	_run()


func _run() -> void:
	var game: Node3D = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.start_run()
	await get_tree().physics_frame
	var room := GrandStaircase.new()
	game.world().add_child(room)
	room.global_position = Vector3(4000, 0, 0)
	room.build()
	var p: FpsPlayer = game.player
	room.player = p
	await get_tree().physics_frame
	for n in room.get_children():
		if n is ShotTrigger and n.global_position.y < room.global_position.y + GrandStaircase.TOP + 1.5:
			n.shot(n.global_position, Vector3.FORWARD, 50.0)      # shoot the rope: barrels and rope go
	for f in 300:
		await get_tree().physics_frame
	for lane: float in [-3.5, -1.5, 0.0, 1.8, 3.6]:
		p.global_position = room.to_global(Vector3(lane, GrandStaircase.TOP + 0.1, 1.2))
		p.velocity = Vector3.ZERO
		await _walk(p, room, Vector3(0, 0, -1), lane, "down")
		await _walk(p, room, Vector3(0, 0, 1), lane, "up")
	get_tree().quit()


func _walk(p: FpsPlayer, room: Node3D, dir: Vector3, lane: float, label: String) -> void:
	p.rotation.y = 0.0 if dir.z < 0.0 else PI
	var down := InputEventKey.new()
	down.keycode = KEY_W
	down.physical_keycode = KEY_W
	down.pressed = true
	Input.parse_input_event(down)
	var stuck := 0.0
	var worst := Vector3.ZERO
	var t := 0.0
	while t < 9.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var l := room.to_local(p.global_position)
		if (dir.z < 0.0 and l.z < GrandStaircase.BOTTOM_Z - 1.5) or (dir.z > 0.0 and l.z > 1.0):
			break
		if absf(p.get_real_velocity().z) < 0.4:
			stuck += 1.0 / 60.0
			worst = l
		else:
			stuck = 0.0
		if stuck > 0.5:
			break
	var up := InputEventKey.new()
	up.keycode = KEY_W
	up.physical_keycode = KEY_W
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().physics_frame
	var l2 := room.to_local(p.global_position)
	print("lane %.1f %s: ended z=%.2f y=%.2f %s" % [lane, label, l2.z, l2.y, ("STUCK at z=%.2f y=%.2f" % [worst.z, worst.y]) if stuck > 0.5 else "ok"])


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
