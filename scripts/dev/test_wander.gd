extends Node
## Unaware clowns going about their business (idle wandering, then a search
## after losing the player): how often does a step run into a wall or a
## doorway pillar instead of going through the opening?

func _ready() -> void:
	_run()


func _run() -> void:
	Engine.set_meta(&"test_save", true)
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	var moves := 0
	var blocked := 0
	var where := {}
	for fl in 3:
		game.start_run()
		game.floor_number = 3 + fl * 2
		game.next_floor()
		await get_tree().physics_frame
		var m: Maze = game.maze
		# the player out of the way, somewhere nobody can see
		game.player.global_position = m.cell_center(m.route[0]) + Vector3.UP * 30.0
		game.player.set_physics_process(false)
		# a few extra, started off-centre in their cells (as after a chase)
		for i in 10:
			var cell: Vector2i = m.route[(i * 7 + 3) % m.route.size()]
			var c: Clown = game._spawn_clown(false, false)
			c.global_position = m.keep_walkable(m.cell_center(cell) + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)))
			c.global_position.y = m.floor_height(c.global_position)
		for c: Clown in game.clowns:
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b:
				b.moves = 0
				b.blocked = 0
				# half of them searching, as if they had just lost the player
				if c.get_instance_id() % 2 == 0 and not c.has_meta(&"seated"):
					b.mind = ClownBrain.Mind.SEARCH
					b._search_left = 40.0
					b._wander_to = c.global_position
		for f in 60 * 40:
			await get_tree().physics_frame
		for c: Clown in game.clowns:
			var b := c.get_node_or_null("Brain") as ClownBrain
			if b and is_instance_valid(c) and not c.dead:
				moves += b.moves
				blocked += b.blocked
				if b.blocked > 30 and where.size() < 12:
					var here := m.cell_of(c.global_position)
					var tgt := m.cell_of(b._wander_to)
					var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3.UP * 1.0, b._wander_to + Vector3.UP * (1.0 + c.global_position.y - b._wander_to.y), 1)
					var h := c.get_world_3d().direct_space_state.intersect_ray(q)
					where[c.get_instance_id()] = "%s blocked %d/%d at %s cell %s lvl %d -> target %s cell %s lvl %d linked=%s mind=%d seated=%s; ray hits %s at %s" % [c.body, b.blocked, b.moves, c.global_position.snapped(Vector3.ONE * 0.1), here, m.level[m.idx(here)], b._wander_to.snapped(Vector3.ONE * 0.1), tgt, m.level[m.idx(tgt)], m.linked(here, tgt), b.mind, c.has_meta(&"seated"), (h.collider as Node).name if h else "-", (h.position as Vector3).snapped(Vector3.ONE * 0.1) if h else Vector3.ZERO]
	for k in where:
		print("   " + where[k])
	print("UNAWARE: %d steps taken, %d ran into something (%.1f%%)" % [moves, blocked, 100.0 * blocked / maxf(moves, 1)])
	get_tree().quit()
