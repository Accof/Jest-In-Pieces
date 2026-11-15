extends Node
## Renders a handful of views of a trench level to /tmp (needs a real renderer).
func _ready() -> void:
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
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
	# overview from above no man's land
	var mid := Vector3(m.w * Maze.CELL * 0.5, m.top_height(), m.d * Maze.CELL * 0.5)
	views.append(["over", mid + Vector3(-m.w * 2.2, 9, -m.d * 2.2), mid])
	# a trench cell looking along a link, a bunker cell, a dugout from the trench, a room
	var trench_done := false
	var bunker_done := false
	for z in m.d:
		for x in m.w:
			var c := Vector2i(x, z)
			for dir in Maze.DIRS:
				var n := c + dir
				if not m.in_bounds(n) or not m.linked(c, n):
					continue
				var p := m.cell_center(c) + Vector3.UP * 1.6
				var q := m.cell_center(n) + Vector3.UP * 1.5
				if m.is_trench(c) and m.is_trench(n) and not trench_done:
					views.append(["trench", p - (q - p) * 0.3, q]); trench_done = true
				elif not m.is_trench(c) and not m.is_trench(n) and not bunker_done and m.level[m.idx(c)] == m.level[m.idx(n)]:
					views.append(["bunker", p - (q - p) * 0.3, q]); bunker_done = true
	for s: Dictionary in m.stairs:
		if m.is_trench(s.high) and not m.is_trench(s.low):
			var hi := m.cell_center(s.high)
			var lo := m.cell_center(s.low)
			var d := (lo - hi); d.y = 0; d = d.normalized()
			views.append(["dugout", hi - d * 1.2 + Vector3.UP * 1.7, lo + Vector3.UP * 1.0])
			views.append(["door", hi - d * 2.4 + Vector3.UP * 1.5, lo + Vector3.UP * 2.6])
			views.append(["dugout_in", lo + Vector3.UP * 1.5 + d * 0.2, hi + Vector3.UP * 1.7 + d * 0.0])
			break
	for r: Array in m.rooms:
		var a := m.cell_center(r[0])
		var ctr := a + Vector3(Maze.CELL * 0.5, 0, Maze.CELL * 0.5)
		views.append(["room_" + ("trench" if m.is_trench(r[0]) else "bunker"), a + Vector3(-1.0, 1.7, -1.0), ctr + Vector3(1.5, 0.6, 1.5)])
	for v: Array in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/lvl_%s.png" % v[0])
		print("saved ", v[0])
	get_tree().quit()
