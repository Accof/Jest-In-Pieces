extends Node
## Enemies against the level: a dozen hunters chase the player round floors
## with stairs. Every frame, every living one is checked for being inside a
## wall (its cell is not open, or its body overlaps level geometry), sunk
## below the floor, or stuck beside a staircase. Prints the counts.

var game: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	var totals := {frames = 0, in_wall = 0, overlap = 0, sunk = 0, pocket = 0, stuck = 0}
	var floors := 3
	for fl in floors:
		game.start_run()
		game.floor_number = 3 + fl * 2          # bigger floors, more stairs
		game.next_floor()
		await get_tree().physics_frame
		var m: Maze = game.maze
		var p: FpsPlayer = game.player
		for c: Clown in game.clowns:
			var b := c.get_node_or_null("Brain")
			if b and b is ClownBrain and not c.has_meta(&"seated"):
				b.alert(p.global_position)
		# a dozen more, right on the stairs and in the corners, to make it hard
		var spots: Array[Vector2i] = []
		for s: Dictionary in m.stairs:
			spots.append(s.low)
			spots.append(s.high)
		for i in 12:
			var cell: Vector2i = spots[i % spots.size()] if not spots.is_empty() else m.route[i % m.route.size()]
			var c: Clown = game._spawn_clown(i % 3 == 0, i % 3 == 1)
			c.global_position = m.cell_center(cell) + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
			c.global_position.y = m.floor_height(c.global_position)
			(c.get_node("Brain") as ClownBrain).alert(p.global_position)
		var last := {}
		var still := {}
		var t := 0.0
		var hop := 0.0
		print("floor %d: %d clowns, %d stairs" % [game.floor_number, game.clowns.size(), m.stairs.size()])
		while t < 30.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			hop -= 1.0 / 60.0
			p.health = p.stats.max_health
			if hop <= 0.0:
				# the player moves around the route, so they keep chasing, up and down the stairs
				hop = 4.0
				var cell: Vector2i = m.route[randi() % m.route.size()]
				p.global_position = m.cell_center(cell) + Vector3.UP * (m.floor_height(m.cell_center(cell)) + 0.1)
				for c: Clown in game.clowns:
					var b := c.get_node_or_null("Brain")
					if b and b is ClownBrain and not c.dead and not c.has_meta(&"seated"):
						b.alert(p.global_position)
			for c: Clown in game.clowns:
				if not is_instance_valid(c) or c.dead or c.downed or c.crawling or c.has_meta(&"seated"):
					continue
				totals.frames += 1
				var pos := c.global_position
				var cell := m.cell_of(pos)
				if not m.is_open(cell):
					totals.in_wall += 1
					if not last.has(c):
						last[c] = true
						print("   in a wall: %s at %s (cell %s)" % [c.body, pos.snapped(Vector3.ONE * 0.01), cell])
				if _overlaps(c, pos):
					totals.overlap += 1
					if totals.overlap % 400 == 1:
						var hit := _overlap_info(c, pos)
						print("   overlap: %s at %s cell %s: %s mind=%d moving=%.2f" % [c.body, pos.snapped(Vector3.ONE * 0.01), cell, hit, (c.get_node("Brain") as ClownBrain).mind, c.velocity.length()])
				var fy := m.floor_height(pos)
				if pos.y < fy - 0.25:
					totals.sunk += 1
				if _in_pocket(m, pos):
					totals.pocket += 1
				# stuck: wants to move, has not moved for 3 seconds
				var key := c.get_instance_id()
				var prev: Array = still.get(key, [pos, 0.0])
				# (melee clowns only: gunmen stand still to shoot on purpose)
				if not c.has_gun and (prev[0] as Vector3).distance_to(pos) < 0.05 and (c.get_node("Brain") as ClownBrain).mind == ClownBrain.Mind.HUNT and pos.distance_to(p.global_position) > 3.0:
					prev[1] += 1.0 / 60.0
					if prev[1] > 3.0:
						totals.stuck += 1
						if totals.stuck % 600 == 1:
							print("   stuck: %s at %s cell %s, %.1fm from player, gun=%s rifle=%s pocket=%s" % [c.body, pos.snapped(Vector3.ONE * 0.01), cell, pos.distance_to(p.global_position), c.has_gun, c.has_rifle, _in_pocket(m, pos)])
				else:
					prev = [pos, 0.0]
				still[key] = prev
	print("TOTAL living-clown frames %d: in a wall %d, overlapping geometry %d, sunk below floor %d, in a stair pocket %d, stuck >3s %d" % [totals.frames, totals.in_wall, totals.overlap, totals.sunk, totals.pocket, totals.stuck])
	get_tree().quit()


static var _shape: CapsuleShape3D
func _overlaps(c: Clown, pos: Vector3) -> bool:
	if _shape == null:
		_shape = CapsuleShape3D.new()
		_shape.radius = 0.2
		_shape.height = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 1.0)
	q.collision_mask = 1
	return not c.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _overlap_info(c: Clown, pos: Vector3) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 1.0)
	q.collision_mask = 1
	var r := c.get_world_3d().direct_space_state.intersect_shape(q, 1)
	if r.is_empty():
		return "-"
	var o: Object = r[0].collider
	return "%s (%s)" % [o.name, o.get_parent().name if o is Node else ""]


## Beside a staircase, in the low strip between the stair and the side wall.
func _in_pocket(m: Maze, pos: Vector3) -> bool:
	var c := m.cell_of(pos)
	for s: Dictionary in m.stairs:
		if s.low != c:
			continue
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var rel := pos - m.cell_center(c)
		var along := rel.dot(dir)
		var across := absf(rel.dot(Vector3(dir.z, 0, -dir.x)))
		if along > Maze.CELL * 0.5 - Maze.STAIR_RUN and across > Maze.STAIR_WIDTH * 0.5 + 0.15:
			return true
	return false
