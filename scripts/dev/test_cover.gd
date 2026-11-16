extends Node
## A WitzSoldat in a bunker corridor with the player: does it take cover,
## peek out and shoot? Pass --render for /tmp/cover_*.png.
var render := false


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _run() -> void:
	var game: Node3D = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.start_run()
	await get_tree().physics_frame
	var m: Maze = game.maze
	# the longest straight run on one level
	var best := [0, 0]
	for i in range(m.route.size() - 1):
		var k := i
		while k + 1 < m.route.size() and m.route[k + 1] - m.route[k] == m.route[i + 1] - m.route[i] and m.level[m.idx(m.route[k + 1])] == m.level[m.idx(m.route[i])]:
			k += 1
		if k - i > best[1] - best[0]:
			best = [i, k]
	var a: Vector3 = m.cell_center(m.route[best[0]])
	var b: Vector3 = m.cell_center(m.route[best[1]])
	print("straight run of %d cells" % (best[1] - best[0] + 1))
	# keep only one soldier, at the far end
	var soldier: Clown = null
	for c: Clown in game.clowns:
		if soldier == null:
			soldier = c
		else:
			c.queue_free()
	await get_tree().physics_frame
	game.clowns = [soldier] as Array[Clown]
	# make it a WitzSoldat if it is not
	if soldier.body != "witzsoldat":
		soldier.queue_free()
		await get_tree().physics_frame
		soldier = Clown.new()
		soldier.body = "witzsoldat"
		game._world.add_child(soldier)
		soldier.give_rifle()
		var brain := ClownBrain.new()
		brain.maze = m
		brain.player = game.player
		brain.others = game.clowns
		brain.name = "Brain"
		brain.rifleman()
		soldier.add_child(brain)
		game.clowns = [soldier] as Array[Clown]
	soldier.global_position = b
	game.player.global_position = a + Vector3.UP * 0.1
	game.player.look_at(Vector3(b.x, game.player.global_position.y, b.z))
	var brain: ClownBrain = soldier.get_node("Brain")
	brain.debug_cover = true
	brain.alert(game.player.global_position, false)
	var states := []
	var last := -1
	var crouched := 0.0
	var shots := 0
	var hp: float = game.player.health
	var saved := {}
	for f in 60 * 14:
		await get_tree().physics_frame
		if render and brain._cover_state == 0 and f % 90 == 45:
			brain._find_cover()                 # the render run is slow: nudge it
		if brain._cover_state != last:
			last = brain._cover_state
			states.append("%.1fs:%s" % [f / 60.0, ["open", "to cover", "hiding", "peeking"][last]])
		if soldier.crouch_amount > 0.9:
			crouched += 1.0 / 60.0
		if render and not saved.has(last) and last in [2, 3]:
			saved[last] = true
			var cam := Camera3D.new()
			game._world.add_child(cam)
			var to_p: Vector3 = (game.player.global_position - soldier.global_position)
			to_p.y = 0
			to_p = to_p.normalized()
			cam.global_position = soldier.global_position + to_p * 1.6 + to_p.cross(Vector3.UP) * 1.2 + Vector3.UP * 1.5
			cam.look_at(soldier.global_position + Vector3.UP * 0.8)
			cam.make_current()
			var lamp := OmniLight3D.new()
			game._world.add_child(lamp)
			lamp.global_position = cam.global_position
			lamp.light_energy = 1.5
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/tmp/cover_%d.png" % last)
			game.player.camera.make_current()
			cam.queue_free()
			lamp.queue_free()
	print("cover states: ", states)
	print("time crouched in cover: %.1fs" % crouched)
	FpsPlayer.god_mode = false
	get_tree().quit()


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
