extends Node3D
## The Drowned Front (Operation Drowned Front, Milestone 2), checked.
## Sections (user args; none = all):
##   layouts   40 seeds: two networks either side of an empty No Man's Land,
##             every trench cell of each reachable within it, a route from the
##             start (our rear) to the H.Q. (their rear) that goes up an
##             assault ramp, over the top and down one of theirs; the distance
##             between the fire trenches; how long a floor takes to build
##   geo       one seed: parapets on each fire trench's own front (ours toward
##             -z, theirs toward +z), fire steps on the front of each bay, the
##             assault ramps climb from floor to ground at a walkable slope,
##             the wire belts stand in front of each line
##   game      floor 3 of a run is the Front, SURVIVAL, with the enemies in
##             the trenches (two in three in theirs, none out in the open),
##             the H.Q. door at the exit; the player walks the whole way from
##             the start to the H.Q. by the maze's own path and goes in with [E]
##   views     (with "render", Forward+): /tmp/front_*.png: the whole front from
##             above, our parapet looking across, the middle of No Man's Land,
##             their fire trench, the H.Q.
##   godot --headless --fixed-fps 60 res://scenes/test_front.tscn [-- section... seed=N render]

var fails := 0
var game: Node3D
var render := false
var fixed_seed := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	for a in args:
		if a.begins_with("seed="):
			fixed_seed = int(a.substr(5))
	var secs := ["layouts", "geo", "game", "views"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("FRONT: %d failed" % fails)
	get_tree().quit()


func _make(seed_: int) -> FrontMaze:
	var m := FrontMaze.new()
	add_child(m)
	m.generate(0, 0, seed_)
	return m


## Cells reachable from `c` along links.
func _reach(m: Maze, c: Vector2i) -> Dictionary:
	var seen := {c: true}
	var q: Array[Vector2i] = [c]
	while not q.is_empty():
		var p: Vector2i = q.pop_back()
		for dir in Maze.DIRS:
			var n := p + dir
			if not seen.has(n) and m.links.has(m._key(p, n)):
				seen[n] = true
				q.append(n)
	return seen


# --- layouts -------------------------------------------------------------------------------
func _layouts() -> void:
	print("-- layouts")
	var n := 40
	var bad := 0
	var times: Array[int] = []
	var routes: Array[int] = []
	var tops: Array[int] = []
	var gaps: Array[float] = []
	var opens: Array[int] = []
	var assault_used := 0
	for i in n:
		var seed_ := 1916 + i * 7919 if fixed_seed == 0 else fixed_seed
		var m := _make(seed_)
		var why := []
		if m.route.size() < 10:
			why.append("no route")
		if not m.ours.has(m.start_cell):
			why.append("start not in our network")
		if not m.theirs.has(m.exit_cell):
			why.append("exit not in theirs")
		# the strip between the blocks holds no trench
		for c: Vector2i in m.open_cells:
			if c.y >= m.their_row0 + TrenchMaze.GRID_D and c.y < m.our_row0:
				why.append("trench cell in No Man's Land at %s" % c)
				break
		# each network hangs together as trench (links), separately
		var from_start := _reach(m, m.start_cell)
		var from_exit := _reach(m, m.exit_cell)
		var ours_ok := true
		var theirs_ok := true
		for c: Vector2i in m.ours:
			if not from_start.has(c):
				ours_ok = false
		for c: Vector2i in m.theirs:
			if not from_exit.has(c):
				theirs_ok = false
		if not ours_ok:
			why.append("our network not all reachable")
		if not theirs_ok:
			why.append("their network not all reachable")
		# the route: our trench, up a ramp (an assault ramp through the parapet,
		# or an ordinary one and round the end of the fire trench along the
		# flank), over the top, down into theirs
		var up := -1
		var down := -1
		var by_assault := 0
		for k in range(1, m.route.size()):
			var prev: Vector2i = m.route[k - 1]
			var c: Vector2i = m.route[k]
			if up < 0 and m.ours.has(prev) and m.top_cells.has(c):
				up = k
				if m.assault_ramps.any(func(r: Dictionary) -> bool: return r.cell == prev):
					by_assault += 1
			if up >= 0 and down < 0 and m.top_cells.has(prev) and m.theirs.has(c):
				down = k
				if m.assault_ramps.any(func(r: Dictionary) -> bool: return r.cell == c):
					by_assault += 1
		if up < 0 or down < 0 or down < up:
			why.append("route does not go up out of ours and down into theirs (up %d, down %d)" % [up, down])
		assault_used += by_assault
		# and the assault ramps themselves lead somewhere: their top cells are
		# in the graph and joined to the start and the exit
		for r: Dictionary in m.assault_ramps:
			if m.path_cells(m.start_cell, r.top) >= 9999 or m.path_cells(r.top, m.exit_cell) >= 9999:
				why.append("assault ramp at %s is not on the way" % r.cell)
		var on_top := 0
		for c: Vector2i in m.route:
			if m.top_cells.has(c):
				on_top += 1
		if m.assault_ramps.size() < 2:
			why.append("only %d assault ramps" % m.assault_ramps.size())
		if not why.is_empty():
			bad += 1
			print("      seed %d: %s" % [seed_, ", ".join(why)])
		times.append(int(m.timing.total))
		routes.append(m.route.size())
		tops.append(on_top)
		opens.append(m.open_cells.size())
		gaps.append((m.our_row0 + TrenchMaze.FIRE_ROW - (m.their_row0 + TrenchMaze.GRID_D - 1 - TrenchMaze.FIRE_ROW)) * m.cell)
		m.queue_free()
		await _frames(1)
		if fixed_seed != 0:
			break
	var tsum := 0
	var tmax := 0
	for t in times:
		tsum += t
		tmax = maxi(tmax, t)
	var rsum := 0
	for r in routes:
		rsum += r
	var osum := 0
	for o in opens:
		osum += o
	var topsum := 0
	for t in tops:
		topsum += t
	print("      %d of %d seeds failed; %d trench cells avg; route %d cells avg (%d of them over the top); the main route used an assault ramp %d times of %d (the rest go round a flank); fire trenches %.0f m apart; build %d ms avg, %d ms worst (headless)" % [bad, times.size(), osum / times.size(), rsum / routes.size(), topsum / tops.size(), assault_used, times.size() * 2, gaps[0], tsum / times.size(), tmax])
	_check(bad == 0, "every seed: two whole networks, an empty No Man's Land, a route up, over and down, every assault ramp on the way")


# --- geo -----------------------------------------------------------------------------------
func _geo() -> void:
	print("-- geo")
	var m := _make(1916 if fixed_seed == 0 else fixed_seed)
	for f in [-1, 1]:
		var who := "ours" if f == -1 else "theirs"
		# parapet: the ground 0.9 m out on the front of a fire bay stands higher
		# than 0.9 m out on the back
		var front_sum := 0.0
		var back_sum := 0.0
		var cnt := 0
		var step_ok := 0
		var step_n := 0
		for c: Vector2i in m.bays:
			if m.facing_of(c) != f:
				continue
			var r := m._rect(c)
			var x := r.get_center().x
			var z_front := (r.position.y - 0.9) if f == -1 else (r.end.y + 0.9)
			var z_back := (r.end.y + 0.9) if f == -1 else (r.position.y - 0.9)
			front_sum += m.ground_height(x, z_front)
			back_sum += m.ground_height(x, z_back)
			cnt += 1
			# the fire step: the walked surface at the front edge is about
			# FIRE_STEP_H above the floor in the middle of the bay
			var z_step := (r.position.y + 0.25) if f == -1 else (r.end.y - 0.25)
			var step := m.floor_height(Vector3(x, 0, z_step))
			var mid := m.floor_height(Vector3(x, 0, r.get_center().y + (0.3 if f == -1 else -0.3)))
			step_n += 1
			if step - mid > TrenchMaze.FIRE_STEP_H * 0.6:
				step_ok += 1
		_check(cnt > 10 and front_sum / cnt > back_sum / cnt + 0.1, "%s: the parapet is on the front of the fire trench (front %.2f m, back %.2f m, %d bays)" % [who, front_sum / maxi(cnt, 1), back_sum / maxi(cnt, 1), cnt])
		_check(step_ok >= step_n * 0.8, "%s: the fire steps are on the front of the bays (%d of %d)" % [who, step_ok, step_n])
		# the assault ramps: from the bay floor up to the ground, no step
		# steeper than a man walks (the walked surface, 0.2 m at a time)
		var nramps := 0
		for r: Dictionary in m.assault_ramps:
			if r.dir.y != f:
				continue
			nramps += 1
			var foot: Vector2 = r.foot
			var head: Vector2 = r.head
			var y0 := m.floor_height(Vector3(foot.x, 0, foot.y - f * 0.3))
			var y1 := m.floor_height(Vector3(head.x, 0, head.y + f * 0.6))
			var worst := 0.0
			var last := m.floor_height(Vector3(foot.x, 0, foot.y - f * 0.3))
			var steps := int((head - foot).length() / 0.2) + 4
			for i in steps:
				var p := foot + (head - foot).normalized() * (0.2 * i - 0.3)
				var y := m.floor_height(Vector3(p.x, 0, p.y))
				worst = maxf(worst, absf(y - last) / 0.2)
				last = y
			_check(y1 - y0 > 1.2 and worst < 1.0, "%s: assault ramp at %s climbs %.2f m to the top, steepest %.0f degrees" % [who, r.cell, y1 - y0, rad_to_deg(atan(worst))])
		_check(nramps >= 1, "%s: %d assault ramps" % [who, nramps])
	# the wire: pickets stand in front of each line, inside No Man's Land
	var art: FrontArt = m.get_node("Art")
	# (every fourth picket is a rattle spot; a MultiMesh's transforms cannot be
	# read back headless)
	var near_ours := 0
	var near_theirs := 0
	var z_ours := m.our_row0 * m.cell
	var z_theirs := (m.their_row0 + TrenchMaze.GRID_D) * m.cell
	for p: Vector3 in art.rattle_spots:
		if p.z > z_ours - 3.2 and p.z < z_ours + 1.0:
			near_ours += 1
		if p.z < z_theirs + 3.2 and p.z > z_theirs - 1.0:
			near_theirs += 1
	_check(near_ours >= 5 and near_theirs >= 5 and near_ours + near_theirs >= art.rattle_spots.size() * 0.95, "wire pickets in front of each line (%d ours, %d theirs of %d rattle spots)" % [near_ours, near_theirs, art.rattle_spots.size()])
	# the H.Q. is at the front edge of the world, in their rear trench
	var xf := m.exit_transform()
	_check(xf.origin.z < 3.0 and m.theirs.has(m.exit_cell) and m.kind[m.exit_cell] == "comm", "the H.Q. portal at the end of their rear communication trench (z %.1f)" % xf.origin.z)
	m.queue_free()
	await _frames(1)


# --- game ----------------------------------------------------------------------------------
func _new_game(seed_: int) -> void:
	if game:
		game.queue_free()
		await _frames(2)
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(seed_)
	game.rng.seed = seed_
	game.start_run()
	FpsPlayer.god_mode = true
	game.floor_number = 2
	game.next_floor()
	await _frames(3)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _game() -> void:
	print("-- game")
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var m := game.maze as FrontMaze
	_check(m != null, "floor 3 is the Drowned Front")
	if m == null:
		return
	_check(game.objective == 1 and game.exit_open, "SURVIVAL, the H.Q. open")
	_check(game.battle == null, "no legacy battle on the Front (its director comes later)")
	var in_theirs := 0
	var in_open := 0
	var on_top := 0
	for c: Clown in game.clowns:
		var cell := m.cell_of(c.global_position)
		if m.theirs.has(cell):
			in_theirs += 1
		if m.open_cells.has(cell):
			in_open += 1
		if m.top_cells.has(cell):
			on_top += 1
	_check(in_open == game.clowns.size() and on_top == 0, "%d enemies, all in the trenches, none out in the open" % game.clowns.size())
	_check(in_theirs >= game.clowns.size() * 0.45, "%d of them in the enemy lines" % in_theirs)
	var door: Node = game._exit.get_node_or_null("ExitDoor")
	_check(door != null and game._exit.global_position.distance_to(m.exit_transform().origin) < 0.01, "the H.Q. door stands at the exit")
	var p: FpsPlayer = game.player
	_check(m.ours.has(m.cell_of(p.global_position)) and m.cell_of(p.global_position) == m.start_cell, "the player starts at our rear")
	# the whole way, by the maze's own path (what the enemies follow too)
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	var goal := m.exit_transform().origin
	var way := m.path(p.global_position, goal)
	_check(way.size() > 60, "a path from the start to the H.Q.: %d points" % way.size())
	var stuck := 0
	var reached := 0
	var worst_off := 0.0
	var worst_at := Vector3.ZERO
	var highest := -99.0
	var lowest := 99.0
	var nudges := 0
	_key(KEY_W, true)
	for i in way.size():
		var target: Vector3 = way[i]
		var t := 0.0
		var last := p.global_position
		var stall := 0.0
		var side_t := 0.0
		var side := Vector3.ZERO
		var side_sign := 1.0
		while t < 6.0:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.45:
				break
			var aim := to
			if side_t > 0.0:
				side_t -= 1.0 / 60.0
				aim = to.normalized() * 0.4 + side
			p.rotation.y = atan2(-aim.x, -aim.z)
			await get_tree().physics_frame
			t += 1.0 / 60.0
			var off := absf(p.global_position.y - m.floor_height(p.global_position))
			if off > worst_off:
				worst_off = off
				worst_at = p.global_position
			highest = maxf(highest, p.global_position.y)
			lowest = minf(lowest, p.global_position.y)
			stall = stall + 1.0 / 60.0 if Vector2(p.global_position.x - last.x, p.global_position.z - last.z).length() < 0.6 / 60.0 else 0.0
			last = p.global_position
			if stall > 0.5 and side_t <= 0.0:
				stall = 0.0
				side = to.normalized().cross(Vector3.UP) * side_sign
				side_sign = -side_sign
				side_t = 0.45
				nudges += 1
		if t >= 6.0:
			stuck += 1
			var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.5, target + Vector3.UP * 0.5, 1)
			var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			print("        stuck at point %d: at %s, target %s (cell %s %s); in the way: %s" % [i, p.global_position.snapped(Vector3.ONE * 0.1), target.snapped(Vector3.ONE * 0.1), m.cell_of(target), m.kind.get(m.cell_of(target), "top" if m.top_cells.has(m.cell_of(target)) else "?"), r.get("collider")])
		else:
			reached += 1
	_key(KEY_W, false)
	var wc := m.cell_of(worst_at)
	print("      walked: %d of %d points reached, %d stuck, %d side-steps; worst height off the ground %.2f m at %s (cell %s, %s%s); went from %.1f m down to %.1f m up" % [reached, way.size(), stuck, nudges, worst_off, worst_at.snapped(Vector3.ONE * 0.1), wc, m.kind.get(wc, "top"), ", on a ramp" if not m.ramp_at(worst_at).is_empty() else "", lowest, highest])
	_check(stuck == 0, "the player walks the whole way: our trenches, up, across No Man's Land, down, through theirs")
	_check(worst_off < 0.7, "and stays on the ground (crater rims and ramp cuts stand the capsule off the sampled surface a little)")
	_check(highest > -0.6 and lowest < -1.6, "he was up on the ground (%.1f m) and down in the trenches (%.1f m)" % [highest, lowest])
	_check(p.global_position.distance_to(goal) < 2.5 and game.state == game.State.PLAYING, "at the H.Q. door, still playing (%.1f m)" % p.global_position.distance_to(goal))
	# in with [E]
	p.look_at(Vector3(goal.x, p.global_position.y, goal.z))
	p.rotation.x = 0.0
	p.camera.rotation.x = 0.0
	await _frames(2)
	var u: Object = p._usable()
	if u == null:
		p.global_position = goal + game._exit.global_basis.z * 1.2 + Vector3.UP * 0.1
		p.look_at(Vector3(goal.x, p.global_position.y, goal.z))
		p.rotation.x = 0.0
		p.camera.rotation.x = 0.0
		await _frames(2)
		u = p._usable()
	_check(u is ExitDoor, "looking at the H.Q. door: the [E] prompt")
	p._use()
	await _frames(3)
	_check(game.state == game.State.UPGRADE, "[E]: the upgrades, floor done (state %d)" % game.state)


# --- views (render) ---------------------------------------------------------------------
func _shot(name_: String) -> void:
	await _frames(3)
	get_viewport().get_texture().get_image().save_png("/tmp/front_%s.png" % name_)
	print("      /tmp/front_%s.png" % name_)


func _views() -> void:
	if not render:
		return
	print("-- views")
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var m := game.maze as FrontMaze
	game.player.visible = false
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.far = 600.0
	cam.fov = 70.0
	await _frames(30)
	var mid := Vector3(m.w * m.cell * 0.5, 0, m.d * m.cell * 0.5)
	cam.global_position = mid + Vector3(0, 150, 120)
	cam.look_at(mid)
	await _shot("above")
	cam.fov = 75.0
	# our parapet, looking across (from an assault ramp's head)
	var up_ramp: Dictionary = {}
	var down_ramp: Dictionary = {}
	for r: Dictionary in m.assault_ramps:
		if r.dir.y == -1 and up_ramp.is_empty():
			up_ramp = r
		if r.dir.y == 1 and down_ramp.is_empty():
			down_ramp = r
	if not up_ramp.is_empty():
		var h: Vector2 = up_ramp.head
		var pos := Vector3(h.x, 0, h.y - 1.0)
		pos.y = m.floor_height(pos) + 1.65
		cam.global_position = pos
		cam.look_at(Vector3(m.w * m.cell * 0.5, pos.y - 3.0, (m.their_row0 + TrenchMaze.GRID_D) * m.cell))
		await _shot("our_parapet")
	# the middle of No Man's Land, looking at their line
	var nml := Vector3(m.w * m.cell * 0.5, 0, (m.their_row0 + TrenchMaze.GRID_D + m.our_row0) * 0.5 * m.cell)
	nml.y = m.floor_height(nml) + 1.65
	cam.global_position = nml
	cam.look_at(Vector3(nml.x, nml.y - 1.0, (m.their_row0 + TrenchMaze.GRID_D) * m.cell))
	await _shot("no_mans_land")
	cam.look_at(Vector3(nml.x, nml.y - 1.0, m.our_row0 * m.cell))
	await _shot("looking_back")
	# their fire trench, from the foot of a ramp
	if not down_ramp.is_empty():
		var f: Vector2 = down_ramp.foot
		var pos := Vector3(f.x, 0, f.y - 1.2)
		pos.y = m.floor_height(pos) + 1.65
		cam.global_position = pos
		cam.look_at(Vector3(pos.x + 6.0, pos.y - 0.6, pos.z))
		await _shot("their_fire_trench")
	# the H.Q.
	var xf := m.exit_transform()
	var pos := xf.origin + xf.basis.z * 4.0
	pos.y = m.floor_height(pos) + 1.6
	cam.global_position = pos
	cam.look_at(xf.origin + Vector3.UP * 1.2)
	await _shot("hq")
