extends Node
## Renders a handful of views of a trench level to /tmp (needs a real renderer).
func _ready() -> void:
	var game: Node3D = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	game.start_run()
	for c in game.clowns:
		c.process_mode = Node.PROCESS_MODE_DISABLED
	for n in game.get_children():
		if n is CanvasLayer or n is Control:
			n.visible = false
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	var m: Maze = game.maze
	var cam := Camera3D.new()
	cam.fov = 75
	add_child(cam)
	cam.make_current()
	var views := []
	var mid := Vector3(m.w * Maze.CELL * 0.5, m.top_height(), m.d * Maze.CELL * 0.5)
	views.append(["over", mid + Vector3(-m.w * 1.2, 14, -m.d * 1.2), mid])
	# the longest straight run of bunker corridor, looking down it
	var best := 0
	for i in range(m.route.size() - 1):
		var k := i
		while k + 1 < m.route.size() and m.route[k + 1] - m.route[k] == m.route[i + 1] - m.route[i] and m.level[m.idx(m.route[k + 1])] == m.level[m.idx(m.route[i])]:
			k += 1
		if k - i > best and not m.is_trench(m.route[i]):
			best = k - i
			var a := m.cell_center(m.route[i]); var b := m.cell_center(m.route[k])
			var dvec := (b - a).normalized()
			views = views.filter(func(v): return v[0] != "corridor")
			views.append(["corridor", a - dvec * 1.2 + Vector3.UP * 1.65, b + Vector3.UP * 1.3])
	# the trench at the start, looking along the route
	var t0 := m.cell_center(m.route[0]); var t1 := m.cell_center(m.route[1])
	views.append(["trench", t0 - (t1 - t0).normalized() * 1.0 + Vector3.UP * 1.65, t1 + Vector3.UP * 1.4])
	# the way in, from the trench
	for i in range(1, m.route.size()):
		if m.is_trench(m.route[i - 1]) and not m.is_trench(m.route[i]):
			var a := m.cell_center(m.route[i - 1]); var b := m.cell_center(m.route[i])
			var dvec := (b - a).normalized()
			views.append(["entrance", a - dvec * 1.3 + Vector3.UP * 1.6, b + Vector3.UP * 1.7])
			break
	# a stairwell, looking down it
	if not m.stairs.is_empty():
		var s0: Dictionary = m.stairs[0]
		var hi := m.cell_center(s0.high); var lo := m.cell_center(s0.low)
		var dvec := (lo - hi); dvec.y = 0; dvec = dvec.normalized()
		views.append(["stairs", hi - dvec * 1.0 + Vector3.UP * 1.65, lo + dvec * 2.0 + Vector3.UP * 0.8])
	for r: Array in m.rooms:
		var a := m.cell_center(r[0])
		var ctr := a + Vector3(Maze.CELL * 0.5, 0, Maze.CELL * 0.5)
		views.append(["room%d" % views.size(), a + Vector3(-0.9, 1.65, -0.9), ctr + Vector3(1.8, 0.9, 1.8)])
	for v: Array in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/lvl_%s.png" % v[0])
		print("saved ", v[0])
	get_tree().quit()


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
