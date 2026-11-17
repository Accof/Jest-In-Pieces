extends Node
## Dev: blood pools in a real level. Finds a staircase, bleeds two bodies'
## worth at the top edge and one by a corridor wall, lets them spread, and
## films them in the game's own lighting (with a window):
## godot res://scenes/look_pools_game.tscn
var game: Node3D


func _ready() -> void:
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	seed(4242)
	game.rng.seed = 4242
	game.start_run()
	for i in 6:
		if not game.maze.stairs.is_empty():
			break
		game.next_floor()
		await get_tree().process_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await get_tree().physics_frame
	var m: Maze = game.maze
	var s: Dictionary = m.stairs[0]
	var dir := Vector3(s.dir.x, 0, s.dir.y)
	var edge := m.cell_center(s.low) + dir * Maze.CELL * 0.5
	var top_y := m.level[m.idx(s.high)] * Maze.LEVEL
	var space := get_viewport().world_3d.direct_space_state
	var top := _floor(space, edge + dir * 0.25 + Vector3.UP * (top_y + 0.5))
	Blood.spawn_pool(top, Vector3.UP, 0.85)
	Blood.spawn_pool(_floor(space, edge + dir * 0.45 + Vector3(dir.z, 0, -dir.x) * 0.4 + Vector3.UP * (top_y + 0.5)), Vector3.UP, 0.8)
	print("stairs at ", edge, " going ", dir, " top ", top)
	# the player out of the way, looking at nothing
	game.player.global_position = m.cell_center(s.low) + Vector3.UP * 0.2 - dir * 1.2
	var t := 0.0
	while t < 11.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55
	cam.make_current()
	var low_c := m.cell_center(s.low) + Vector3.UP * (m.level[m.idx(s.low)] * Maze.LEVEL)
	var side := Vector3(dir.z, 0, -dir.x)
	var low_y := m.level[m.idx(s.low)] * Maze.LEVEL
	var views := [[edge - dir * 2.7 + side * 0.35 + Vector3.UP * (low_y + 1.5), edge + dir * 0.3 + Vector3.UP * (top_y - 0.1)],
		[edge + dir * 1.3 + side * 0.3 + Vector3.UP * (top_y + 1.4), edge - dir * 0.9 + Vector3.UP * (top_y - 0.7)]]
	for i in views.size():
		cam.global_position = views[i][0]
		cam.look_at(views[i][1])
		for f in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/k/pools_game_%d.png" % i)
	get_tree().quit()


func _floor(space: PhysicsDirectSpaceState3D, from: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else from
