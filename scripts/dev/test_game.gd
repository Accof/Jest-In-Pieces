extends Node
## Headless check of the maze generator and one pass round the game loop.
func _ready() -> void:
	_run()

func _run() -> void:
	# --- mazes
	var bad := 0
	var stair_total := 0
	var worst_step := 0.0
	var route_total := 0
	var barrel_total := 0
	for i in 40:
		var m := Maze.new()
		add_child(m)
		var size := 5 + i % 5
		m.generate(size, size, 1000 + i)
		stair_total += m.stairs.size()
		var seen_low := {}
		for st: Dictionary in m.stairs:
			if seen_low.has(st.low):
				bad += 1                 # two staircases rising out of one cell
			seen_low[st.low] = true
		for z in m.d:
			for x in m.w:
				var c := Vector2i(x, z)
				if m.is_open(c) and m.path_cells(m.start_cell, c) == 0 and c != m.start_cell:
					bad += 1
				for dir in Maze.DIRS:
					var n := c + dir
					if m.in_bounds(n) and m.linked(c, n) and absi(m.level[m.idx(c)] - m.level[m.idx(n)]) > 1:
						bad += 1
		# walk the route to the exit and look for jumps in floor height
		var pts: Array[Vector3] = [m.cell_center(m.start_cell)]
		pts.append_array(m.path(m.cell_center(m.start_cell), m.cell_center(m.exit_cell)))
		for k in range(1, pts.size()):
			var prev := m.floor_height(pts[k - 1])
			for s in 61:
				var p := pts[k - 1].lerp(pts[k], s / 60.0)
				var h := m.floor_height(p)
				worst_step = max(worst_step, absf(h - prev))
				prev = h
		route_total += m.route.size()
		barrel_total += (m.get_node("Art") as LevelArt).explosive_count
		m.free()
	print("routes: %.1f cells on average, %.1f fuel drums" % [route_total / 40.0, barrel_total / 40.0])
	print("mazes: 40 generated, problems=%d, stairs per maze=%.1f, biggest floor jump on a route=%.2fm" % [bad, stair_total / 40.0, worst_step])

	# --- game loop
	var game: Node3D = _test_game_scene().instantiate()
	add_child(game)
	await get_tree().process_frame
	game.start_run()
	print("floor %d: maze %dx%d, clowns=%d, gunmen=%d, state=%d" % [game.floor_number, game.maze.w, game.maze.d, game.clowns.size(), game.clowns.filter(func(c): return c.has_gun).size(), game.state])
	var start := {}
	for c: Clown in game.clowns:
		start[c] = c.global_position
	var hp: float = game.player.health
	# 1. Standing still and silent: nobody should come hunting.
	for f in 600:
		await get_tree().physics_frame
	var hunting: int = game.clowns.filter(func(c): return c.get_node("Brain").mind == ClownBrain.Mind.HUNT).size()
	var wandered: int = game.clowns.filter(func(c): return c.global_position.distance_to(start[c]) > 1.0).size()
	print("10s silent: %d of %d hunting, %d wandered, player health %.0f -> %.0f" % [hunting, game.clowns.size(), wandered, hp, game.player.health])
	# 2. Fire one pistol shot at the ceiling: only clowns within earshot react.
	game.player.camera.rotation.x = 1.4
	game.player.fire()
	await get_tree().physics_frame
	var heard := []
	for c: Clown in game.clowns:
		var cells: int = game.maze.path_cells(game.maze.cell_of(c.global_position), game.maze.cell_of(game.player.global_position)) - 1
		heard.append("%d cells:%s" % [cells, "HUNT" if c.get_node("Brain").mind == ClownBrain.Mind.HUNT else "idle"])
	print("after one shot: ", heard)
	# 3. Stand in front of an unaware clown: it should notice within a second.
	var idle_ones: Array = game.clowns.filter(func(c): return c.get_node("Brain").mind != ClownBrain.Mind.HUNT and not c.has_meta(&"seated"))
	if not idle_ones.is_empty():
		var c: Clown = idle_ones[0]
		# stand 2m away down an open corridor, with the clown turned towards us
		var m2: Maze = game.maze
		var here := m2.cell_of(c.global_position)
		var spot := m2.cell_center(here)
		for dir in Maze.DIRS:
			if m2.in_bounds(here + dir) and m2.linked(here, here + dir) and m2.level[m2.idx(here + dir)] == m2.level[m2.idx(here)]:
				spot = m2.cell_center(here + dir)
				break
		c.global_position = m2.cell_center(here)
		game.player.global_position = spot + Vector3.UP * 0.05
		for f in 60:
			var to: Vector3 = game.player.global_position - c.global_position
			c.rotation.y = atan2(to.x, to.z)          # keep it looking our way while it wanders
			await get_tree().physics_frame
		print("stood in front of an idle clown for 1s: mind=%d (1 = hunting)" % c.get_node("Brain").mind)
	var off_floor := 0.0
	for f in 600:
		await get_tree().physics_frame
		if f % 30 == 0:
			for c: Clown in game.clowns:
				off_floor = max(off_floor, absf(c.global_position.y - game.maze.floor_height(c.global_position)))
	print("10s later: player health %.0f, worst height off floor %.2fm" % [game.player.health, off_floor])
	for c: Clown in game.clowns.duplicate():
		c.hit({collider = c.ragdoll.bones[&"Neck"], position = c.global_position + Vector3(0, 1.75, 0), direction = Vector3(0, 0, -1), damage = 200.0, impulse = 14.0, shot_id = 1})
	for f in 240:
		await get_tree().physics_frame
	var lowest := 99.0
	for c: Clown in game.clowns:
		lowest = min(lowest, c.ragdoll.bones[&"Hips"].global_position.y - game.maze.floor_height(c.ragdoll.bones[&"Hips"].global_position))
	for c: Clown in game.clowns:
		var hip_at: Vector3 = c.ragdoll.bones[&"Hips"].global_position
		var off: float = hip_at.y - game.maze.floor_height(hip_at)
		if off < -0.2:
			print("   below floor: %s seated=%s off=%.2f at %s cell %s" % [c.body, c.has_meta(&"seated"), off, hip_at.snapped(Vector3.ONE * 0.1), game.maze.cell_of(hip_at)])
	print("all shot: remaining=%d exit_open=%s tickets=%d, lowest pelvis vs floor %.2fm (negative = fell through)" % [game.remaining, game.exit_open, game.run_tickets, lowest])
	game.player.global_position = game._exit.global_position + Vector3.UP * 0.1
	for f in 5:
		await get_tree().process_frame
	print("at exit: state=%d (2 = choosing upgrade), offer=%s" % [game.state, game._offer.map(func(u): return u.name)])
	game._pick_upgrade(0)
	for f in 5:
		await get_tree().physics_frame
	print("floor %d: clowns=%d, taken=%s, state=%d" % [game.floor_number, game.clowns.size(), game.taken, game.state])
	var soldiers: Array = game.clowns.filter(func(c): return c.body == "witzsoldat")
	print("floor %d WitzSoldats: %d (helmets on: %d, rifles: %d)" % [game.floor_number, soldiers.size(), soldiers.filter(func(c): return c.has_helmet).size(), soldiers.filter(func(c): return c.has_rifle).size()])
	game.player.take_damage(9999.0)
	await get_tree().process_frame
	print("died: state=%d (3 = dead), saved tickets=%d best_floor=%d" % [game.state, int(game.save.tickets), int(game.save.best_floor)])
	get_tree().paused = false
	get_tree().quit()


## The game scene, set to use a throwaway save so a test never touches yours.
func _test_game_scene() -> PackedScene:
	Engine.set_meta(&"test_save", true)
	return load("res://scenes/game.tscn")
