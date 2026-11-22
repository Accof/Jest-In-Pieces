extends Node
## The Drowned Trenches (TrenchMaze), checked. Sections (user args; none = all):
##   layouts   many seeds: every cell reachable, the trench parts all there,
##             no two trenches touching where they should not, route length,
##             trench length, build time
##   ground    the carved ground: collision matching the walked surface
##   game      in the game: floors 3, 6, 9 are trenches (2 and 4 are not),
##             overcast light there and the bunker dark back after, enemy
##             mix, the exit at the bunker door, the player walking the route
##             (duckboards, fire step) without catching or falling through
##   bodies    on a trench floor: deaths on duckboards, in water, on the
##             fire step, against a wall, a Carnival Curse: bodies settle on
##             the ground (not floating, not through it), blood pools
##   geo       the shape against the player and the soldiers (8 seeds): how
##             much of the trench floor the player can see out of standing up
##             (his eye 1.65 m over the walked surface), whether he sees over
##             the parapet from a fire step, floor width by kind of trench
##   nav       the gate before any new AI (floor 3 of a game): ramps, bridges
##             and top ground all one network; soldiers walk to every bridge
##             (up a ramp, along the top, over it) and into every dugout and
##             out; two stand abreast in the main trenches; the player walks
##             into a dugout and out, under a bridge, up a ramp and back
##   ambience  the player walks the route and wades the flooded stretch:
##             footsteps by surface (mud, duckboards, water), shells landing
##             far off (flash, boom), the music box plays near its dugout,
##             nothing of it hurts him; the dressing is all there (wire,
##             signs, clutter, the carnival things)
## Add "render" (with a window) for views in /tmp/tr_*.png; "ascii" prints a layout.

var render := false
var fails := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/tr_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["layouts", "ground", "geo", "nav", "overhaul", "field", "fogbank", "top", "suspense", "battle", "falls", "perf", "game", "bodies", "ambience", "battleviews", "views", "floor", "normals", "relief", "walls", "parallax", "section", "cine", "light"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("TRENCH: %d failed" % fails)
	get_tree().quit()


func _make(seed_: int) -> TrenchMaze:
	var m := TrenchMaze.new()
	add_child(m)
	m.generate(0, 0, seed_)
	return m


func _layouts() -> void:
	print("-- layouts")
	var bad := 0
	var lengths: Array[float] = []
	var routes: Array[float] = []
	var times: Array[float] = []
	var missing := {}
	for s in 30:
		var t0 := Time.get_ticks_msec()
		var m := TrenchMaze.new()
		m.w = TrenchMaze.GRID_W
		m.d = TrenchMaze.GRID_D
		m.rng.seed = 1000 + s
		var ok := false
		for attempt in 40:
			m._reset()
			if m._layout():
				ok = true
				break
		times.append(Time.get_ticks_msec() - t0)
		if not ok:
			bad += 1
			m.free()
			continue
		lengths.append(m.open_cells.size() * m.cell)
		m._astar.clear()
		for c: Vector2i in m.open_cells:
			m._astar.add_point(m.idx(c), Vector2(c.x, c.y))
		for k: String in m.links:
			var p := k.split("|")
			m._astar.connect_points(int(p[0]), int(p[1]))
		routes.append(m._astar.get_id_path(m.idx(m.start_cell), m.idx(m.exit_cell)).size() * m.cell)
		for need: String in ["dugout", "gunpit", "op", "tree", "flood_junction"]:
			if not m.landmarks.any(func(l: Dictionary) -> bool: return l.kind == need):
				missing[need] = missing.get(need, 0) + 1
		# no stray contact: every pair of touching open cells is linked
		for c: Vector2i in m.open_cells:
			for dir in Maze.DIRS:
				if m.open_cells.has(c + dir) and not m.linked(c, c + dir):
					bad += 1
		if s == 0 and OS.get_cmdline_user_args().has("ascii"):
			print(m.ascii())
		m.free()
	print("      %d of 30 failed; trench %.0f-%.0f m (avg %.0f); start to exit %.0f-%.0f m; layout %.0f ms avg; missing %s" % [
		bad, lengths.min(), lengths.max(), _avg(lengths), routes.min(), routes.max(), _avg(times), missing])
	_check(bad == 0, "every layout made, every cell reachable, nothing touching unlinked")
	_check(_avg(lengths) >= 180.0 and _avg(lengths) <= 340.0, "about 2-3x a bunker floor of trench (%.0f m)" % _avg(lengths))
	_check(missing.get("dugout", 0) + missing.get("op", 0) + missing.get("tree", 0) < 6, "the landmarks are nearly always there (%s)" % missing)


## Eye over the walked surface (FpsPlayer: camera 1.65 m up the body).
const EYE := 1.65


## Whether an eye at `eye` sees out over the top of the trench along `dir`:
## the line stays above the ground until it is well clear of the trench edge.
func _sees_out(m: TrenchMaze, p: Vector3, eye: float, dir: Vector2, lean := 0.0) -> bool:
	var dist := 0.15
	while dist < 9.0:
		var x := p.x + dir.x * dist
		var z := p.z + dir.y * dist
		var h := m.ground_height(x, z)
		if h > eye - lean * dist:
			return false
		if m._sample(m.sdf, x, z) > 1.2:
			return true                 # out over open ground and still above it
		dist += 0.1
	return false


func _sdf_at(m: TrenchMaze, x: float, z: float) -> float:
	return m._sample(m.sdf, x, z)


## Floor width at a cell centre, across the way the trench runs there.
func _width(m: TrenchMaze, c: Vector2i) -> float:
	var horizontal := m.open_cells.has(c + Vector2i(1, 0)) or m.open_cells.has(c + Vector2i(-1, 0))
	var vertical := m.open_cells.has(c + Vector2i(0, 1)) or m.open_cells.has(c + Vector2i(0, -1))
	if horizontal == vertical:
		return -1.0                     # a corner or an end: no one across
	var across := Vector2(0, 1) if horizontal else Vector2(1, 0)
	var ctr := Vector2((c.x + 0.5) * m.cell, (c.y + 0.5) * m.cell)
	var out := 0.0
	for s in [-1.0, 1.0]:
		var t := 0.0
		while t < 3.0 and _sdf_at(m, ctr.x + across.x * t * s, ctr.y + across.y * t * s) < -0.05:
			t += 0.05
		out += t
	return out


func _geo() -> void:
	print("-- geo")
	var floor_pts := 0
	var see_out := {}
	var tried := {}
	var step_view := 0
	var steps := 0
	var widths := {}
	var dirs: Array[Vector2] = []
	for k in 16:
		dirs.append(Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)))
	for sd in 8:
		var m := _make(500 + sd)
		for c: Vector2i in m.open_cells:
			var k: String = m.kind[c]
			if k in ["dugout"]:
				continue
			var w := _width(m, c)
			if w > 0.0:
				if not widths.has(k):
					widths[k] = []
				widths[k].append(w)
			# standing on the floor at a few points of the cell
			for j in 6:
				var p := Vector3((c.x + 0.25 + 0.25 * (j % 3)) * m.cell, 0, (c.y + (0.5 if j < 3 else 1.2)) * m.cell)
				if _sdf_at(m, p.x, p.z) > -0.25:
					continue
				if m.floor_height(p) > float(m.depth[c]) + 0.32:
					continue                # up the ramp to a fire step: meant to look out
				var eye := m.floor_height(p) + EYE
				var any := false
				for dv in dirs:
					if _sees_out(m, p, eye, dv):
						any = true
						break
				# a ramp's mouth is an opening: looking up it you see out
				if m.ramps.any(func(r: Dictionary) -> bool: return Vector2(r.cell).distance_to(Vector2(c)) < 3.5):
					continue
				tried[k] = tried.get(k, 0) + 1
				if any and OS.get_cmdline_user_args().has("why") and k == "support" and sd == 0:
					var near_ramp := m.ramps.any(func(r: Dictionary) -> bool: return Vector2(r.cell).distance_to(Vector2(c)) < 2.5)
					print("        support sees out at %s (cell %s, floor %.2f, depth %.2f, near a ramp %s)" % [p, c, m.floor_height(p), m.depth[c], near_ramp])
				if any:
					see_out[k] = see_out.get(k, 0) + 1
				floor_pts += 1
		# from each fire step, looking out over the parapet (toward -z)
		for c: Vector2i in m.bays:
			var p := Vector3((c.x + 0.5) * m.cell, 0, c.y * m.cell + TrenchMaze.EDGE - TrenchMaze.FIRE_STEP_D * 0.5)
			steps += 1
			if _sees_out(m, p, m.floor_height(p) + EYE, Vector2(0, -1)):
				step_view += 1
			elif OS.get_cmdline_user_args().has("why"):
				var eye := m.floor_height(p) + EYE
				var worst := -9.0
				var at := 0.0
				var dd := 0.15
				while dd < 6.0:
					var h := m.ground_height(p.x, p.z - dd) - eye
					if h > worst:
						worst = h
						at = dd
					dd += 0.1
				print("        step %s blocked: %.2f m over the eye, %.1f m out (sdf there %.2f)" % [c, worst, at, _sdf_at(m, p.x, p.z - at)])
		m.queue_free()
	await _frames(2)
	var all_out := 0
	var all_tried := 0
	var line := []
	for k: String in tried:
		all_out += see_out.get(k, 0)
		all_tried += tried[k]
		line.append("%s %d%%" % [k, int(100.0 * see_out.get(k, 0) / tried[k])])
	print("      standing on the floor (not at a ramp), sees out of the trench: %d%% of %d points (%s)" % [int(100.0 * all_out / all_tried), all_tried, ", ".join(line)])
	print("      from a fire step, sees over the parapet: %d of %d" % [step_view, steps])
	var wl := []
	for k: String in widths:
		var a: Array = widths[k]
		a.sort()
		wl.append("%s %.2f (min %.2f)" % [k, a[a.size() / 2], a[0]])
	print("      floor width, median: %s" % ", ".join(wl))
	_geo_out = 100.0 * all_out / all_tried
	_geo_step = float(step_view) / maxf(steps, 1)
	_geo_widths = widths


## Walk a brain-driven soldier to `to` by the maze; true if it gets there.
## `on_bridge` counts frames spent on a bridge deck (and how far off it).
func _soldier_walk(c: Clown, b: ClownBrain, to: Vector3, budget: float, stat: Dictionary) -> bool:
	var t := 0.0
	var m: TrenchMaze = game.maze
	var trail: Array = []
	while t < budget:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 90 == 0:
			trail.append("%s y%.2f yaw%.0f v%.2f" % [Vector2(c.global_position.x, c.global_position.z).snapped(Vector2(0.01, 0.01)), c.global_position.y, rad_to_deg(c.rotation.y), b._vel.length()])
			if trail.size() > 30:
				trail.pop_front()
		var got := b._go_to(to, 1.0 / 60.0, b.move_speed)
		b._after(1.0 / 60.0)              # (the brain's own frame is off: its turn, crouch, look)
		if got:
			return true
		var br := m.bridge_at(c.global_position)
		if not br.is_empty():
			stat.bridge = stat.get("bridge", 0) + 1
			stat.deck_off = maxf(stat.get("deck_off", 0.0), absf(c.global_position.y - float(br.deck)))
		if not m.ramp_at(c.global_position).is_empty():
			stat.ramp = stat.get("ramp", 0) + 1
		if m.on_top(c.global_position) and br.is_empty() and m.ramp_at(c.global_position).is_empty():
			stat.top = stat.get("top", 0) + 1
			stat.edge = minf(stat.get("edge", 9.0), m._sample(m.sdf, c.global_position.x, c.global_position.z))
		elif not m.on_top(c.global_position) and m.ramp_at(c.global_position).is_empty():
			stat.wall = maxf(stat.get("wall", -9.0), m._sample(m.sdf, c.global_position.x, c.global_position.z))
	print("          trail: ", trail)
	return false


func _player_to(p: FpsPlayer, pts: Array, budget: float) -> int:
	var reached := 0
	_key(KEY_W, true)
	for target: Vector3 in pts:
		var t := 0.0
		while t < budget:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.35:
				reached += 1
				break
			p.rotation.y = atan2(-to.x, -to.z)
			await get_tree().physics_frame
			t += 1.0 / 60.0
	_key(KEY_W, false)
	return reached


func _nav() -> void:
	print("-- nav")
	# the network on many seeds: one piece, with ramps and bridges
	var pieces := []
	var counts := {"ramps": 0, "bridges": 0, "top": 0}
	for sd in 8:
		var m := _make(700 + sd)
		counts.ramps += m.ramps.size()
		counts.bridges += m.bridges.size()
		counts.top += m.top_cells.size()
		var all := {}
		for c: Vector2i in m.open_cells:
			all[c] = true
		for c: Vector2i in m.top_cells:
			all[c] = true
		var first: Vector2i = m.start_cell
		var reach := 0
		var islands := 0
		for c: Vector2i in all:
			if m.path_cells(first, c) < 9999:
				reach += 1
		# how many top cells cannot be reached (islands up top, cut off by trenches)
		pieces.append("%d/%d" % [reach, all.size()])
		var bridged := m.bridges.all(func(b: Dictionary) -> bool: return m.path_cells(first, b.ends[0]) < 9999 and m.path_cells(first, b.ends[1]) < 9999)
		if not bridged:
			islands += 1
		counts["unbridged"] = counts.get("unbridged", 0) + islands
		m.queue_free()
	await _frames(2)
	print("      8 seeds: %d ramps, %d bridges, %d top cells; reachable from the start: %s" % [counts.ramps, counts.bridges, counts.top, ", ".join(pieces)])
	_check(counts.ramps >= 16 and counts.bridges >= 16, "every floor has ramps up and footbridges over (%d, %d on 8)" % [counts.ramps, counts.bridges])
	_check(counts.get("unbridged", 0) == 0, "every bridge's both ends reachable from the start")
	# in a game: soldiers and the player
	trench_seed = 4242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			trench_seed = int(a.substr(5))
	await _new_game(3)
	trench_seed = 0
	var m: TrenchMaze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	var c: Clown = game._spawn_clown(true, false)
	var b: ClownBrain = c.get_node("Brain")
	b.set_physics_process(false)
	b._cover_state = 0
	c.global_position = m.cell_center(m.start_cell)
	await _frames(2)
	var stat := {}
	var got := 0
	var goals: Array = []
	for br: Dictionary in m.bridges:
		goals.append(["bridge", m.cell_center(br.ends[1])])
		goals.append(["bridge back", m.cell_center(br.ends[0])])
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			goals.append(["dugout", m.cell_center(l.cell)])
			goals.append(["out of the dugout", m.cell_center(l.entrance)])
	for r: Dictionary in m.ramps:
		goals.append(["ramp down", m.cell_center(r.cell)])
	for g: Array in goals:
		var ok: bool = await _soldier_walk(c, b, g[1], 40.0, stat)
		if ok:
			got += 1
			print("        soldier reached %s" % g[0])
		else:
			print("        soldier did not reach %s %s (at %s, cell %s)" % [g[0], g[1], c.global_position, m.cell_of(c.global_position)])
	print("      soldier: %d of %d goals reached; frames on bridges %d (deck off by %.2f), up top %d (nearest the edge %.2f), on ramps %d" % [
		got, goals.size(), stat.get("bridge", 0), stat.get("deck_off", 0.0), stat.get("top", 0), stat.get("edge", 9.0), stat.get("ramp", 0)])
	_check(got == goals.size(), "a soldier walks to every bridge and over it, into every dugout and out, down every ramp")
	_check(stat.get("bridge", 0) > 0 and stat.get("deck_off", 0.0) < 0.05, "on the bridges it walks on the deck")
	_check(stat.get("edge", 9.0) > 0.5, "up top it keeps back from the edge (%.2f)" % stat.get("edge", 9.0))
	# two abreast in the main trenches: two soldiers' capsules (as the brain
	# sweeps them) side by side across the floor, 0.7 m apart, clear of the walls
	var shape := CapsuleShape3D.new()
	shape.radius = ClownBrain.BODY_RADIUS
	shape.height = ClownBrain.BODY_HEIGHT
	var space := m.get_world_3d().direct_space_state
	var abreast := 0
	var tried := 0
	for cc: Vector2i in m.open_cells:
		if not (m.kind[cc] in ["fire", "support"]) or not (m.open_cells.has(cc + Vector2i(1, 0)) and m.open_cells.has(cc + Vector2i(-1, 0))):
			continue
		tried += 1
		if tried > 60:
			break
		var r := m._rect(cc)
		var z0 := r.position.y
		if m.bays.has(cc):
			z0 = cc.y * m.cell + TrenchMaze.EDGE + 0.15     # the floor behind the fire step (the foot of its ramp)
		var best := 0
		# slide the pair across the floor: any place two fit counts
		var zz := z0 + 0.35
		while zz + 0.7 < r.end.y - 0.3:
			var ok := 0
			for dz: float in [0.0, 0.7]:
				var p0 := Vector3((cc.x + 0.5) * m.cell, 0, zz + dz)
				p0.y = m.floor_height(p0)
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.collision_mask = 1
				q.transform = Transform3D(Basis.IDENTITY, p0 + Vector3.UP * (ClownBrain.BODY_LIFT + ClownBrain.BODY_HEIGHT * 0.5))
				if space.intersect_shape(q, 1).is_empty():
					ok += 1
			best = maxi(best, ok)
			zz += 0.1
		if best == 2:
			abreast += 1
	print("      two soldiers abreast (capsules 0.7 m apart, clear of the walls): %d of %d main-trench cells" % [abreast, tried])
	_check(abreast >= tried * 0.9, "two soldiers stand abreast in the main trenches")
	c.queue_free()
	game.clowns.clear()
	# the player: into a dugout and out, under a bridge, up a ramp and back
	var p: FpsPlayer = game.player
	var legs := 0
	var reached := 0
	for l: Dictionary in m.landmarks:
		if l.kind != "dugout":
			continue
		var ent := m.cell_center(l.entrance)
		p.global_position = ent + Vector3.UP * 0.1
		await _frames(3)
		# through the door straight on, then over to the far corner, and back out
		var inside := m.cell_center(l.entrance + l.dir)
		var got_l := await _player_to(p, [inside, m.cell_center(l.cell), inside, ent], 6.0)
		got_l = 2 if got_l == 4 else 0
		if got_l < 2:
			print("        player stuck going into dugout %s from %s: at %s" % [l.cell, l.entrance, p.global_position])
		reached += got_l
		legs += 2
	print("      player into dugouts and back out: %d of %d" % [reached, legs])
	_check(reached == legs, "the player walks into every dugout and out again")
	var under := 0
	for br: Dictionary in m.bridges:
		var cc: Vector2i = br.cell
		p.global_position = m.cell_center(cc + Vector2i(-1, 0)) + Vector3.UP * 0.1
		await _frames(3)
		var u := await _player_to(p, [m.cell_center(cc), m.cell_center(cc + Vector2i(1, 0))], 6.0)
		u = 1 if u == 2 else 0
		if u == 0:
			print("        player stuck under bridge %s: at %s (floor %.2f, deck %.2f)" % [cc, p.global_position, m.floor_height(p.global_position), float(br.a.y)])
		under += u
	print("      player along the trench under each bridge: %d of %d" % [under, m.bridges.size()])
	_check(under == m.bridges.size(), "the player passes under the bridges")
	var up := 0
	for r: Dictionary in m.ramps:
		p.global_position = m.cell_center(r.cell) + Vector3.UP * 0.1
		await _frames(3)
		var head: Vector2 = r.head
		var top := Vector3(head.x, 0, head.y) + Vector3(Vector2(r.dir).x, 0, Vector2(r.dir).y) * 0.8
		var n := await _player_to(p, [top], 8.0)
		var was_top := m.on_top(p.global_position)
		n += await _player_to(p, [m.cell_center(r.cell)], 8.0)
		if n == 2 and was_top:
			up += 1
		else:
			print("        player on ramp %s: reached %d, up top %s, at %s" % [r.cell, n, was_top, p.global_position])
	print("      player up each ramp onto the top and back down: %d of %d" % [up, m.ramps.size()])
	_check(up == m.ramps.size(), "the player climbs out by the ramps and back")
	# over a bridge on foot
	var over := 0
	for br: Dictionary in m.bridges:
		p.global_position = m.cell_center(br.ends[0]) + Vector3.UP * 0.1
		await _frames(3)
		var a: Vector3 = br.a
		var e: Vector3 = br.b
		var n := await _player_to(p, [a, e, m.cell_center(br.ends[1])], 8.0)
		if n == 3:
			over += 1
	print("      player over each bridge: %d of %d" % [over, m.bridges.size()])
	_check(over == m.bridges.size(), "the player crosses the bridges")


var _geo_out := 0.0
var _geo_step := 0.0
var _geo_widths := {}


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


func _ground() -> void:
	print("-- ground")
	var t0 := Time.get_ticks_msec()
	var m := _make(77)
	print("      built in %d ms; %d x %d samples" % [Time.get_ticks_msec() - t0, m.hx, m.hz])
	if OS.get_cmdline_user_args().has("ascii"):
		print(m.ascii())
	await _frames(3)
	var space := m.get_world_3d().direct_space_state
	var worst := 0.0
	var depths: Array[float] = []
	for c: Vector2i in m.route:
		var p := m.cell_center(c)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			worst = 99.0
			continue
		worst = maxf(worst, absf((hit.position as Vector3).y - p.y))
		depths.append(m.ground_height(p.x + 3.0, p.z) - p.y)
	print("      collision vs floor_height along the route: worst %.3f m" % worst)
	_check(worst < 0.03, "the collision is the walked surface")
	m.queue_free()
	await _frames(2)


var game: Node3D
## Fixed level for the nav section (args "seed=N"), 0 for a random one.
var trench_seed := 0


func _new_game(floor_: int) -> void:
	if game == null:
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await _frames(2)
		FpsPlayer.god_mode = true
	game.start_run()
	if trench_seed != 0:
		game.rng.seed = trench_seed
	game.floor_number = floor_ - 1
	var t0 := Time.get_ticks_msec()
	game.next_floor()
	if game.maze is TrenchMaze:
		print("      trench floor built in %d ms" % (Time.get_ticks_msec() - t0))
	await _frames(3)


func _rifle() -> Dictionary:
	for w: Dictionary in FpsPlayer.WEAPONS:
		if w.name == "Rifle":
			return w
	return {}


## The fight out in No Man's Land (TrenchField): men holding cover and firing
## out, dashing between cover, ducking, killed now and then and reinforced
## through the mist; the player can shoot them from the fire step; nothing
## out there hurts him.
func _field() -> void:
	print("-- field")
	var tot := {men = 0, posts = 0, shots = 0, moves = 0, ducks = 0, reinf = 0, cas = 0, shells = 0, spawned = 0}
	var bad_bodies := 0
	var body_n := 0
	var closest_shell := INF
	var shell_n := [0, INF]
	var hits := [0, 0, 0, 0]       # tried, killed, hit him, hit his body (not a limb)
	var dists: Array[float] = []
	for sd in [4242, 1001, 777]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		var bt: TrenchBattle = game.battle
		var f: TrenchField = bt.field
		var pl: FpsPlayer = game.player
		pl.set_physics_process(false)
		# on a fire step, looking out over No Man's Land
		var eye := Vector3.ZERO
		for c: Vector2i in m.bays:
			var st := Vector3((c.x + 0.5) * m.cell, 0, c.y * m.cell + TrenchMaze.EDGE + 0.3)
			st.y = m.floor_height(st)
			pl.global_position = st
			eye = st + Vector3.UP * 1.65
			break
		tot.posts += f.posts.size()
		# watch the shells: none lands near him
		var watch := func(n: Node) -> void:
			if n is Explosion:
				(func() -> void:
					shell_n[1] = minf(shell_n[1], Vector2((n as Node3D).global_position.x - pl.global_position.x, (n as Node3D).global_position.z - pl.global_position.z).length())
					shell_n[0] += 1).call_deferred()
		get_tree().node_added.connect(watch)
		await _frames(60 * 90)
		get_tree().node_added.disconnect(watch)
		tot.men += f.alive().size()
		tot.reinf += f.reinforcements
		tot.cas += f.casualties
		tot.shells += f.shells
		tot.spawned += f.spawned
		for s: FieldSoldier in f.men:
			if is_instance_valid(s):
				tot.shots += s.shots
				tot.moves += s.moves
				tot.ducks += s.ducks
		for b: Clown in f.bodies:
			if not is_instance_valid(b):
				continue
			body_n += 1
			var hips: PhysicalBone3D = b.ragdoll.bones[&"Hips"]
			var g := (m.get_node("Art") as TrenchArt).height_at(hips.global_position.x, hips.global_position.z)
			if absf(hips.global_position.y - g) > 0.8:
				bad_bodies += 1
				print("        body off the ground: hips %.2f, ground %.2f at %s" % [hips.global_position.y, g, hips.global_position])
		# the long shot: the rifle from the step at men out there
		var w := _rifle()
		for s: FieldSoldier in f.alive():
			var c := s.clown
			var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
			var d := eye.distance_to(chest.global_position)
			if d < 20.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(eye, chest.global_position, 1 | 4)
			q.exclude = [pl.get_rid()]
			var r := pl.get_world_3d().direct_space_state.intersect_ray(q)
			if r.is_empty() or not (r.collider is PhysicalBone3D) or r.collider.get_meta(&"clown") != c:
				continue
			hits[0] += 1
			var hp: float = c.health
			var res := pl.shoot_ray(eye, (chest.global_position - eye).normalized(), w, randi())
			await _frames(2)
			print("        shot at %.0f m: hit %s, health %.0f -> %.0f, dead %s" % [d, res.get("collider"), hp, c.health, c.dead])
			var torso: bool = res.get("collider") is PhysicalBone3D and String((res.collider as PhysicalBone3D).bone_name) in ["Chest", "Spine", "Hips", "Neck", "Head"]
			if res.get("collider") is PhysicalBone3D and (res.collider as PhysicalBone3D).get_meta(&"clown") == c:
				hits[2] += 1
			if torso:
				hits[3] += 1
			if c.dead:
				hits[1] += 1
				dists.append(d)
			if hits[0] >= sd % 3 + 2:
				break
		pl.set_physics_process(true)
	print("      out there (3 floors, 90 s each): %d posts, %d men alive at the end, %d sent out in all; %d shots fired out, %d dashes, %d ducks; %d parties came in, %d killed by the battle, %d shells" % [tot.posts, tot.men, tot.spawned, tot.shots, tot.moves, tot.ducks, tot.reinf, tot.cas, tot.shells])
	print("      %d bodies out there, %d not on the ground; nearest of %d shells to the player %.1f m" % [body_n, bad_bodies, shell_n[0], shell_n[1]])
	print("      the rifle from the fire step: %d of %d shots hit the man (%d in the body, %d on an arm in front of it); %d killed, at %s m" % [hits[2], hits[0], hits[3], hits[2] - hits[3], hits[1], dists.map(func(x: float) -> String: return "%.0f" % x)])
	_check(tot.men > 0 and tot.shots > 0, "men out there hold cover and fire across No Man's Land")
	_check(tot.moves > 0, "they dash from cover to cover")
	_check(tot.reinf > 0, "parties come in along the line")
	_check(tot.cas > 0, "and some are killed by the battle")
	_check(body_n > 0 and bad_bodies == 0, "the dead lie on the ground out there")
	_check(shell_n[0] > 0 and shell_n[1] >= 14.0, "no shell lands within 14 m of the player")
	_check(hits[0] > 0 and hits[2] == hits[0], "the Lee-Enfield hits them from the fire step at range")
	_check(hits[3] > 0 and hits[1] >= hits[3], "and a round in the body kills")


## Above the trenches: riflemen on the open ground in front of the fire
## trench, sentries looking down, men climbing out and back, beats and pairs
## along the trenches, the marksman (who fires only when he can see the
## player's head), and men up top firing down into a trench once alerted.
func _top() -> void:
	print("-- top")
	var tot := {}
	var top_shots := 0
	var on_top_ok := [0, 0]
	var beat_legs := 0
	var pair_gap := 0.0
	var pair_n := 0
	var climb := [0, 0, 0]       # runners on climb routes, seen up top, seen in a trench
	var mark := {hurt = 0, placed = 0, hidden_shots = 0, open_shots = 0, open_hits = 0, killed = 0, dist = 0.0}
	var down := [0, 0]           # top men alerted with the player below, of them fired
	for sd in [4242, 1001, 777]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		var bt: TrenchBattle = game.battle
		for k: String in bt.counts:
			tot[k] = tot.get(k, 0) + bt.counts[k]
		var pl: FpsPlayer = game.player
		pl.set_physics_process(false)
		pl.global_position = Vector3(-400, 0, -400)
		var climbers := {}
		for d: BattleDuty in bt.duties:
			if d.kind == BattleDuty.Kind.RUNNER and d.route.size() == 2 and (m.on_top(d.route[0]) != m.on_top(d.route[1])):
				climbers[d] = [false, false]
		for i in 60 * 50:
			await get_tree().physics_frame
			if i % 15 == 0:
				for d: BattleDuty in climbers:
					if is_instance_valid(d.clown):
						if m.on_top(d.clown.global_position):
							climbers[d][0] = true
						else:
							climbers[d][1] = true
				for d: BattleDuty in bt.duties:
					if d.leader != null and is_instance_valid(d.leader) and d.follow_delay <= 0.0 and d.brain.mind == ClownBrain.Mind.IDLE:
						pair_gap = maxf(pair_gap, d.clown.global_position.distance_to(d.leader.clown.global_position))
		for d: BattleDuty in climbers:
			climb[0] += 1
			climb[1] += 1 if climbers[d][0] else 0
			climb[2] += 1 if climbers[d][1] else 0
		for d: BattleDuty in bt.duties:
			if d.kind == BattleDuty.Kind.TOP_RIFLE:
				top_shots += d.shots
			if d.kind in [BattleDuty.Kind.TOP_RIFLE, BattleDuty.Kind.SENTRY, BattleDuty.Kind.MARKSMAN]:
				on_top_ok[0] += 1
				if m.on_top(d.clown.global_position) or m.top_cells.has(m.cell_of(d.clown.global_position)):
					on_top_ok[1] += 1
			if d.kind == BattleDuty.Kind.TRENCH_PATROL:
				beat_legs += d.legs
				if d.leader != null:
					pair_n += 1
		# the marksman: hidden in a trench he never fires; in his sight he does
		for d: BattleDuty in bt.duties:
			if d.kind != BattleDuty.Kind.MARKSMAN:
				continue
			mark.placed += 1
			var me := d.clown.global_position + Vector3.UP * 1.5
			# somewhere in a trench, 25 m and more from him
			var hid := Vector3.INF
			var open := Vector3.INF
			for c: Vector2i in m.open_cells:
				var p := m.cell_center(c)
				var dd := p.distance_to(d.clown.global_position)
				if dd < 25.0 or dd > 60.0:
					continue
				var head := p + Vector3.UP * 1.55
				var seen := d.brain._clear(me, head)
				var cone := Vector3(d.face.x, 0, d.face.z).normalized().dot(Vector3(head.x - me.x, 0, head.z - me.z).normalized()) > cos(deg_to_rad(75.0))
				if not m.top_cells.has(c) and not seen and hid == Vector3.INF:
					hid = p
				if seen and cone and open == Vector3.INF:
					open = p
			if hid != Vector3.INF:
				pl.global_position = hid
				var s0 := d.mark_shots
				await _frames(60 * 12)
				mark.hidden_shots += d.mark_shots - s0
			if open != Vector3.INF:
				pl.global_position = open
				var s0 := d.mark_shots
				var h0 := d.mark_hits
				await _frames(60 * 20)
				mark.open_shots += d.mark_shots - s0
				mark.open_hits += d.mark_hits - h0
				# and back at him with the rifle from there
				var eye := open + Vector3.UP * 1.65
				# at whatever of him shows: the chest, else the head
				var aim_at: Vector3 = d.clown.ragdoll.bones[&"Chest"].global_position
				var qq := PhysicsRayQueryParameters3D.create(eye, aim_at, 1)
				if not pl.get_world_3d().direct_space_state.intersect_ray(qq).is_empty():
					aim_at = d.clown.ragdoll.bones[&"Neck"].global_position + Vector3.UP * 0.08
				mark.dist = eye.distance_to(aim_at)
				var hp: float = d.clown.health
				var res := pl.shoot_ray(eye, (aim_at - eye).normalized(), _rifle(), randi())
				await _frames(2)
				print("        rifle at the marksman %.0f m: hit %s at %s, health %.0f -> %.0f, mind %s" % [mark.dist, res.get("collider"), res.get("position"), hp, d.clown.health, d.brain.mind])
				if d.clown.dead:
					mark.killed += 1
				if d.clown.health < hp:
					mark.hurt += 1
			pl.global_position = Vector3(-400, 0, -400)
		# a man up top, the player in the trench below him in plain sight: he fires down
		for d: BattleDuty in bt.duties:
			if not (d.kind in [BattleDuty.Kind.TOP_RIFLE, BattleDuty.Kind.SENTRY, BattleDuty.Kind.PATROL]) or d.clown.dead or not d.clown.has_rifle:
				continue
			var me := d.clown.global_position + Vector3.UP * 1.5
			var below := Vector3.INF
			for c: Vector2i in m.open_cells:
				if m.top_cells.has(c):
					continue
				var p := m.cell_center(c)
				var dd := Vector2(p.x - me.x, p.z - me.z).length()
				if dd > 3.0 and dd < 12.0 and p.y < me.y - 1.8 and d.brain._clear(me, p + Vector3.UP * 1.3):
					below = p
					break
			if below == Vector3.INF:
				continue
			down[0] += 1
			pl.global_position = below
			var r0 := d.brain.rounds_fired
			d.brain.alert(below, false)
			await _frames(60 * 10)
			print("        %s %s up top, the player %.1f m off and %.1f m below: %d rounds, now %s" % [d.name_of(), d.clown.body, Vector2(below.x - me.x, below.z - me.z).length(), me.y - 1.5 - below.y, d.brain.rounds_fired - r0, "on top" if m.on_top(d.clown.global_position) else "in the trench"])
			if d.brain.rounds_fired > r0:
				down[1] += 1
			pl.global_position = Vector3(-400, 0, -400)
			break
		pl.set_physics_process(true)
	print("      duties %s" % [tot])
	print("      up top: %d of %d top riflemen, sentries and marksmen on the top; the top riflemen fired %d rounds out" % [on_top_ok[1], on_top_ok[0], top_shots])
	print("      climbing out and back: %d runners, %d seen up top, %d seen in a trench; beats walked %d legs; %d pairs, the second never more than %.1f m behind" % [climb[0], climb[1], climb[2], beat_legs, pair_n, pair_gap])
	print("      marksman: %d placed; %d rounds while the player was hidden in a trench; %d rounds (%d hits) while he was in sight; shot back with the rifle at %.0f m: %d killed" % [mark.placed, mark.hidden_shots, mark.open_shots, mark.open_hits, mark.dist, mark.killed])
	print("      firing down: %d of %d top men fired down into the trench once alerted" % [down[1], down[0]])
	_check(tot.get("top_rifle", 0) > 0 and top_shots > 0 and on_top_ok[1] == on_top_ok[0], "riflemen up on the open ground in front of the fire trench, firing out")
	_check(tot.get("sentry", 0) > 0, "sentries up top looking down into the trenches")
	_check(climb[0] > 0 and climb[1] > 0 and climb[2] > 0, "men climb out of the trenches and go back down")
	_check(beat_legs > 0, "beats along the trenches, round the bends")
	_check(pair_n == 0 or pair_gap < 4.0, "pairs keep together")
	_check(mark.placed > 0 and mark.hidden_shots == 0, "the marksman never fires at a player he cannot see")
	_check(mark.open_shots > 0, "but does once he can see the player's head")
	_check(mark.placed == 0 or mark.hurt > 0, "and the rifle hits him from where he was seen (%d of %d killed outright: his raised arms take some rounds)" % [mark.killed, mark.placed])
	_check(down[0] > 0 and down[1] == down[0], "a man up top fires down into the trench")


## Suspense: men sent across the player's way ahead of him (out of sight,
## never from behind, along real trenches); the battle's lulls and flare-ups;
## sounds that come from somewhere (boots from a man, calls from a man off
## along the trenches, screams from out in No Man's Land).
func _suspense() -> void:
	print("-- suspense")
	var enc := {sent = 0, crossed = 0, seen_at_start = 0, from_behind = 0, met = 0}
	var pace := {changes = 0, lull = 0.0, surge = 0.0, flashes_lull = 0, flashes_norm = 0, t_lull = 0.0, t_norm = 0.0}
	var snd := {steps = 0, steps_sourced = 0, calls = 0, calls_ok = 0, screams = 0, screams_out = 0, rattles = 0}
	var fs := ["fs_mud", "fs_wood", "fs_water", "fs_earth", "bridge_step"]
	var fs_streams := fs.map(func(n: String) -> AudioStream: return SfxSynth.stream(n))
	var shout := SfxSynth.stream("shout")
	var scream := SfxSynth.stream("scream")
	for sd in [4242, 1001, 777]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		var bt: TrenchBattle = game.battle
		var pl: FpsPlayer = game.player
		pl.set_physics_process(false)
		var watch := func(n: Node) -> void:
			if not (n is AudioStreamPlayer3D):
				return
			var ap := n as AudioStreamPlayer3D
			(func() -> void:
				var at := ap.global_position
				if fs_streams.has(ap.stream):
					snd.steps += 1
					for c in bt._all + bt.field.men.map(func(f: FieldSoldier) -> Clown: return f.clown if is_instance_valid(f) else null):
						if c != null and is_instance_valid(c) and Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length() < 1.2:
							snd.steps_sourced += 1
							break
				elif ap.stream == shout:
					snd.calls += 1
					for c in bt._all:
						if is_instance_valid(c) and c.global_position.distance_to(at) < 2.0:
							snd.calls_ok += 1
							break
				elif ap.stream == scream:
					snd.screams += 1
					if at.z < -4.0:
						snd.screams_out += 1).call_deferred()
		get_tree().node_added.connect(watch)
		# the player stands at points along the route (in the trench), a minute at each
		for k in 3:
			var c: Vector2i = m.route[mini(m.route.size() - 1, (k + 1) * m.route.size() / 4)]
			pl.global_position = m.cell_center(c)
			var head := pl.global_position + Vector3.UP * 1.6
			for t in 6:
				bt._t_encounter = 0.0
				var before := bt.encounters
				await _frames(2)
				if bt.encounters > before:
					var e: Array = bt.encounter_log.back()
					var d: BattleDuty = e[0]
					enc.sent += 1
					var q := PhysicsRayQueryParameters3D.create(head, d.clown.global_position + Vector3.UP * 1.4, 1)
					if pl.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
						enc.seen_at_start += 1
					var pc := m.cell_of(pl.global_position)
					if m.path_cells(m.cell_of(d.clown.global_position), pc) <= m.path_cells(m.cell_of(e[1]), pc):
						enc.from_behind += 1
					var c0 := d.crossed
					for f in 60 * 45:
						await get_tree().physics_frame
						if d.crossed > c0 or not is_instance_valid(d.clown) or d.brain.mind != ClownBrain.Mind.IDLE:
							break
					if is_instance_valid(d.clown) and d.crossed > c0:
						enc.crossed += 1
					elif is_instance_valid(d.clown) and d.brain.mind != ClownBrain.Mind.IDLE:
						enc.met += 1
					break
				await _frames(60 * 8)
		# pacing: a lull, then the ordinary din, 40 s each, counting the far flashes
		bt.pace = TrenchBattle.Pace.LULL
		bt._t_pace = 40.0
		var f0 := bt.far_flashes
		await _frames(60 * 40)
		pace.flashes_lull += bt.far_flashes - f0
		pace.lull = maxf(pace.lull, bt.calm)
		bt.pace = TrenchBattle.Pace.NORMAL
		bt._t_pace = 40.0
		await _frames(60 * 12)          # (calm easing back)
		f0 = bt.far_flashes
		await _frames(60 * 40)
		pace.flashes_norm += bt.far_flashes - f0
		bt._t_pace = 0.5
		await _frames(60)
		pace.changes += bt.pace_changes
		snd.rattles += bt.rattles
		get_tree().node_added.disconnect(watch)
		pl.set_physics_process(true)
	print("      encounters: %d sent, %d walked through, %d met the player on the way; %d were in the player's sight when sent, %d came from behind him" % [enc.sent, enc.crossed, enc.met, enc.seen_at_start, enc.from_behind])
	print("      pacing: %d changes; in a lull calm reached %.1f and the far side fired %d flashes in 40 s against %d in the ordinary din" % [pace.changes, pace.lull, pace.flashes_lull, pace.flashes_norm])
	print("      sound: %d soldiers' footsteps, %d at a soldier; %d calls, %d from a man; %d screams, %d out in No Man's Land; %d kit rattles" % [snd.steps, snd.steps_sourced, snd.calls, snd.calls_ok, snd.screams, snd.screams_out, snd.rattles])
	_check(enc.sent > 0 and enc.crossed + enc.met == enc.sent, "men cross the player's way ahead of him, and walk through (or meet him)")
	_check(enc.seen_at_start == 0 and enc.from_behind == 0, "never sent from in his sight or from behind him")
	_check(pace.lull > 1.8 and pace.flashes_lull < pace.flashes_norm, "lulls: the far side goes quiet for a while")
	_check(snd.steps > 0 and snd.steps_sourced == snd.steps, "every soldier's footstep comes from a soldier")
	_check(snd.calls > 0 and snd.calls_ok == snd.calls, "calls come from men off along the trenches")
	_check(snd.screams > 0 and snd.screams_out == snd.screams, "screams come from out in No Man's Land")


## Render: the battle as the player sees it (/tmp/tr_bv_<shot>_<tag>.png):
## a party coming through the mist, No Man's Land in action, a rifleman out
## there through a narrow view (the rifle's sights), a man dashing between
## cover, a man up top over the trench.
func _battleviews() -> void:
	if not render:
		return
	print("-- battleviews")
	var tag := "now"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	trench_seed = 4242
	await _new_game(3)
	trench_seed = 0
	var m: TrenchMaze = game.maze
	var bt: TrenchBattle = game.battle
	var f: TrenchField = bt.field
	var pl: FpsPlayer = game.player
	pl.set_physics_process(false)
	pl.visible = false
	for cl in game.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	# the step: the middle bay of the fire trench
	var bays: Array[Vector2i] = []
	for c: Vector2i in m.bays:
		bays.append(c)
	bays.sort()
	var bay: Vector2i = bays[bays.size() / 2]
	var step := Vector3((bay.x + 0.5) * m.cell, 0, bay.y * m.cell + TrenchMaze.EDGE + 0.3)
	step.y = m.floor_height(step)
	var eye := step + Vector3.UP * 1.62
	# a firing position up on the open ground in front of the fire trench (the
	# player gets there by a footbridge or a ramp): No Man's Land in full view
	var best_top := Vector2i(-1, -1)
	var mid_x := m.w * 0.5
	for c: Vector2i in m.top_cells:
		if c.y <= TrenchMaze.FIRE_ROW - 2 and c.y >= 1 and (best_top.x < 0 or absf(c.x - mid_x) < absf(best_top.x - mid_x)):
			best_top = c
	if best_top.x >= 0:
		step = m.cell_center(best_top)
		step.y = m.floor_height(step)
		eye = step + Vector3.UP * 1.65
	print("        eye at %s" % eye)
	pl.global_position = step
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	bt._t_encounter = 9999.0
	# (the waiting and the searching are not drawn: on a software renderer each
	# drawn frame takes seconds; only the frames before each shot are)
	RenderingServer.render_loop_enabled = false
	get_viewport().disable_3d = true
	var tw := Time.get_ticks_msec()
	await _frames(60)
	print("        60 undrawn frames: %d ms" % (Time.get_ticks_msec() - tw))
	await _frames(60 * 19)
	var space := get_viewport().world_3d.direct_space_state
	var in_view := func(c: Clown) -> bool:
		var q := PhysicsRayQueryParameters3D.create(eye, c.global_position + Vector3.UP * 1.1, 1)
		return space.intersect_ray(q).is_empty()
	var shoot := func(name_: String, at: Vector3, look: Vector3, fov: float, frames := 10) -> void:
		if not only.is_empty() and not only.has(name_):
			return
		cam.global_position = at
		cam.look_at(look)
		cam.fov = fov
		# (a man of the floor's own standing right by the camera would fill the
		# frame: hidden for the shot, and said so)
		for c: Clown in game.clowns:
			if is_instance_valid(c):
				var close := c.global_position.distance_to(at) < 4.5 and name_ != "above"
				c.visible = not close
				if close:
					print("        (hid %s %.1f m from the camera)" % [c.body, c.global_position.distance_to(at)])
		var t0 := Time.get_ticks_msec()
		RenderingServer.render_loop_enabled = true
		get_viewport().disable_3d = false
		await _frames(frames)
		await _shot("bv_%s_%s" % [name_, tag])
		RenderingServer.render_loop_enabled = false
		get_viewport().disable_3d = true
		print("      %s: %d ms" % [name_, Time.get_ticks_msec() - t0])
	# 1: a party coming in from the flank through the mist
	f._reinforce(3)
	var lead: FieldSoldier = f.men.back()
	for i in 60 * 30:
		await get_tree().physics_frame
		if not is_instance_valid(lead) or (lead.clown.global_position.distance_to(eye) < 40.0 and in_view.call(lead.clown)):
			break
	if is_instance_valid(lead):
		print("        the party's lead %.0f m off" % lead.clown.global_position.distance_to(eye))
		await shoot.call("mist", eye, lead.clown.global_position + Vector3.UP * 1.0, 32.0, 24)
	# 2: No Man's Land in action, a shell landing out there
	f._shell(eye + Vector3(-6.0, 0, -28.0))
	await shoot.call("nml", eye, eye + Vector3(0, -1.2, -30.0), 70.0, 8)
	# 3: a rifleman out there, as through the sights
	var best: FieldSoldier = null
	for i in 60 * 30:
		for s2: FieldSoldier in f.alive():
			var d := s2.clown.global_position.distance_to(eye)
			if d > 28.0 and d < 60.0 and s2.state == FieldSoldier.State.HOLD and s2._phase == 2 and in_view.call(s2.clown):
				best = s2
				break
		if best != null:
			break
		await get_tree().physics_frame
	if best:
		print("        the rifleman %.0f m off" % best.clown.global_position.distance_to(eye))
		await shoot.call("rifleman", eye, best.clown.global_position + Vector3.UP * 1.2, 18.0, 6)
	# 4: a man dashing between cover
	var runner: FieldSoldier = null
	for i in 60 * 40:
		for s2: FieldSoldier in f.alive():
			var d := s2.clown.global_position.distance_to(eye)
			if d > 15.0 and d < 55.0 and s2.state == FieldSoldier.State.MOVE and s2._delay <= 0.0 and not s2._jog and in_view.call(s2.clown):
				runner = s2
				break
		if runner != null:
			break
		await get_tree().physics_frame
	if runner:
		print("        the runner %.0f m off" % runner.clown.global_position.distance_to(eye))
		await shoot.call("dash", eye, runner.clown.global_position + Vector3.UP * 1.0, 35.0, 4)
	# 5: a man up top, seen from the trench below
	for d: BattleDuty in bt.duties:
		if not (d.kind in [BattleDuty.Kind.TOP_RIFLE, BattleDuty.Kind.SENTRY]) or d.clown.dead:
			continue
		var me := d.clown.global_position
		var below := Vector3.INF
		for c: Vector2i in m.open_cells:
			if m.top_cells.has(c):
				continue
			var p := m.cell_center(c)
			var dd := Vector2(p.x - me.x, p.z - me.z).length()
			if dd > 6.5 and dd < 12.0 and p.y < me.y - 1.8:
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.6, me + Vector3.UP * 1.3, 1)
				if get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
					below = p
					break
		if below == Vector3.INF:
			continue
		await shoot.call("above", below + Vector3.UP * 1.6, me + Vector3.UP * 1.0, 50.0, 8)
		break
	RenderingServer.render_loop_enabled = true
	get_viewport().disable_3d = false
	# 6: a fog bank rolling in over No Man's Land toward the lines
	if only.is_empty() or only.has("bank") or only.has("bank_trench"):
		var fg: TrenchFog = bt.fog
		var bk: TrenchFog.Bank = fg.roll_in(0)
		bk.pos = Vector3(eye.x + 4.0, 0, eye.z - 24.0)
		bk.vel = Vector3(0.1, 0, 1.2)
		bk.age = 60.0
		bk.density = bk.peak
		await _frames(60 * 4)
		await shoot.call("bank", eye + Vector3.UP * 0.4, Vector3(eye.x, eye.y - 1.0, eye.z - 25.0), 65.0, 24)
		# 7: and from down in a trench as it pours in
		var tc := Vector3.INF
		for c: Vector2i in m.open_cells:
			if m.top_cells.has(c) or m.bays.has(c) or m.kind.get(c, "") != "support":
				continue
			tc = m.cell_center(c)
			break
		if tc != Vector3.INF:
			bk.pos = Vector3(tc.x + 3.0, 0, tc.z - 2.0)
			bk.vel = Vector3(0.2, 0, 0.6)
			await _frames(60 * 6)
			var lk := tc + Vector3(6.0, 1.4, 0.0)
			for dir in Maze.DIRS:
				var n: Vector2i = m.cell_of(tc) + dir * 3
				if m.is_open(n) and not m.top_cells.has(n):
					lk = m.cell_center(n) + Vector3.UP * 1.3
					break
			await shoot.call("bank_trench", tc + Vector3.UP * 1.6, lk, 70.0, 24)
	cam.queue_free()


## Fog banks (TrenchFog): a cloud rolls in, its puffs pour down into the
## trenches it crosses, it is gone again; while it is there it hides the
## player from a soldier as it hides the soldier from him; the director sends
## banks and heavy spells on its own.
func _fogbank() -> void:
	print("-- fogbank")
	var res := {made = 0, spells = 0, sank = 0, puffs_over_trench = 0, passed = 0, seen_clear = 0, seen_fog = 0, pairs = 0, near_seen = 0}
	for sd in [4242, 1001]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		var bt: TrenchBattle = game.battle
		var fg: TrenchFog = bt.fog
		var pl: FpsPlayer = game.player
		pl.set_physics_process(false)
		pl.global_position = Vector3(-400, 0, -400)
		# a bank rolling straight in; put it over the middle of the lines and let it drift
		var b: TrenchFog.Bank = fg.roll_in(0)
		b.pos = Vector3(m.w * m.cell * 0.5, 0, m.d * m.cell * 0.35)
		b.vel = Vector3(0, 0, 0.3)
		b.age = 40.0
		b.density = b.peak
		await _frames(60 * 6)
		for pi in b.puffs.size():
			var p: Array = b.puffs[pi]
			var at: Vector3 = p[5]                       # where it is drawn
			var c := m.cell_of(at)
			if m.open_cells.has(c) and not m.top_cells.has(c) and m.floor_height(at) < -1.6:
				res.puffs_over_trench += 1
				# its bottom down on the trench floor (not riding over the top)
				var size: float = p[1] * (0.8 + 0.2 * b.radius / 20.0)
				if p[3] - size * 0.28 < m.floor_height(at) + 0.6:
					res.sank += 1
		# sight through it: a soldier and the player 12-20 m apart along a trench,
		# in his cone, nothing in the way, both in the bank
		for d: BattleDuty in bt.duties:
			if not is_instance_valid(d.clown) or d.clown.dead or d.brain.mind != ClownBrain.Mind.IDLE:
				continue
			var eye := d.clown.global_position + Vector3.UP * 1.5
			var fwd := Vector3(d.clown.global_basis.z.x, 0, d.clown.global_basis.z.z).normalized()
			var spot := Vector3.INF
			for k in range(12, 21):
				var q := d.clown.global_position + fwd * k
				q.y = m.floor_height(q)
				if m.is_open(m.cell_of(q)) and d.brain._clear(eye, q + Vector3.UP * 1.5):
					spot = q
			if spot == Vector3.INF:
				continue
			pl.global_position = spot
			# clear: the bank moved far off
			var keep := b.pos
			b.pos = Vector3(-500, 0, -500)
			if not d.brain._can_see_player():
				b.pos = keep
				pl.global_position = Vector3(-400, 0, -400)
				continue                        # (not in his sight even in the clear: no pair)
			res.pairs += 1
			res.seen_clear += 1
			b.pos = (eye + spot) * 0.5
			b.pos.y = 0.0
			if d.brain._can_see_player():
				res.seen_fog += 1
			# close by he still makes him out
			pl.global_position = d.clown.global_position + fwd * 4.0
			if d.brain._can_see_player():
				res.near_seen += 1
			b.pos = keep
			pl.global_position = Vector3(-400, 0, -400)
			if res.pairs >= 3 * (sd % 2 + 1):
				break
		# it rolls on and is gone
		b.vel = Vector3(0, 0, 6.0)
		for i in 60 * 60:
			await get_tree().physics_frame
			if not fg.banks.has(b):
				res.passed += 1
				break
		# left to itself for five minutes: banks and heavy spells come
		var made0 := fg.banks_made
		fg._t_bank = 5.0
		fg._t_heavy = 5.0
		await _frames(60 * 60 * 3)
		res.made += fg.banks_made - made0
		res.spells += fg.heavy_spells
		print("        heaviness now %.2f, %d banks in the air" % [fg.heaviness, fg.banks.size()])
		pl.set_physics_process(true)
	print("      puffs over a trench: %d, of them sunk into it %d; banks gone after crossing %d of 2" % [res.puffs_over_trench, res.sank, res.passed])
	print("      a soldier and the player 12-20 m apart: seen %d of %d in the clear, %d of %d in a bank; 4 m apart in the bank: %d seen" % [res.seen_clear, res.pairs, res.seen_fog, res.pairs, res.near_seen])
	print("      left to itself (3 min x 2): %d banks rolled in, %d heavy spells" % [res.made, res.spells])
	_check(res.puffs_over_trench > 0 and res.sank * 4 >= res.puffs_over_trench * 3, "a bank's cloud pours down into the trenches it crosses")
	_check(res.passed == 2, "and rolls on and is gone")
	_check(res.pairs > 0 and res.seen_clear == res.pairs and res.seen_fog == 0, "in a bank a soldier cannot see the player 12-20 m off (he can in the clear)")
	_check(res.near_seen == res.pairs, "but close by he still makes him out")
	_check(res.made > 0 and res.spells > 0, "banks and heavy spells come on their own")


## The battle round the player (TrenchBattle, BattleDuty): the soldiers at
## their jobs while nobody knows the player is there, the frontline taken from
## behind, a local alarm, going back to their posts, and the far side's fire.
func _battle() -> void:
	print("-- battle")
	var tot := {frontline = 0, guard = 0, runner = 0, patrol = 0, bridge_runs = 0}
	var shots := 0
	var legs := {runner = 0, patrol = 0}
	var hunting := 0
	var on_top := 0
	var crossed := 0
	var fx := [0, 0, 0]
	var ambushed := [0, 0]
	var alarm := {near = 0, near_told = 0, far = 0, far_told = 0}
	var back := [0, 0]
	for sd in [4242, 1001, 777]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		var bt: TrenchBattle = game.battle
		for k: String in bt.counts:
			tot[k] = tot.get(k, 0) + bt.counts[k]
		var pl: FpsPlayer = game.player
		var home := pl.global_position
		# out of the way: nobody can see or hear the player
		pl.set_physics_process(false)
		pl.global_position = Vector3(-400, 0, -400)
		var runners: Array[BattleDuty] = []
		for d: BattleDuty in bt.duties:
			if d.kind == BattleDuty.Kind.RUNNER and bt.counts.bridge_runs > 0:
				runners.append(d)
		var was_on_bridge := {}
		for i in 60 * 40:
			await get_tree().physics_frame
			if i % 10 == 0:
				for d: BattleDuty in bt.duties:
					if is_instance_valid(d.clown) and not m.bridge_at(d.clown.global_position + Vector3.UP * 0.2).is_empty():
						was_on_bridge[d] = true
		crossed += was_on_bridge.size()
		for d: BattleDuty in bt.duties:
			shots += d.shots
			if d.kind == BattleDuty.Kind.RUNNER:
				legs.runner += d.legs
			if d.kind == BattleDuty.Kind.PATROL:
				legs.patrol += d.legs
				if m.on_top(d.clown.global_position):
					on_top += 1
			var b := d.brain
			if b.mind != ClownBrain.Mind.IDLE:
				hunting += 1
		fx[0] += bt.far_flashes
		fx[1] += bt.flares
		fx[2] += bt.tracer_bursts
		# from behind: the player close behind a rifleman at the step, for 3 s
		for d: BattleDuty in bt.duties:
			if d.kind != BattleDuty.Kind.FRONTLINE or d.brain.mind != ClownBrain.Mind.IDLE:
				continue
			var behind := d.post + Vector3(0, 0, 2.2)
			if not m.is_open(m.cell_of(behind)):
				continue
			behind.y = m.floor_height(behind)
			pl.global_position = behind
			# (only his own noticing counts: another man seeing the player and
			# calling out is the alarm, tested below)
			var noticed := [false]
			var on_alert := func(_w: Vector3, firsthand: bool) -> void:
				if firsthand:
					noticed[0] = true
			d.brain.alerted.connect(on_alert)
			for i in 180:
				await get_tree().physics_frame
			d.brain.alerted.disconnect(on_alert)
			ambushed[0] += 1
			if not noticed[0]:
				ambushed[1] += 1
			pl.global_position = Vector3(-400, 0, -400)
			break
		# one man sees the player: those near him are told, the far ones are not
		var first: BattleDuty = null
		for d: BattleDuty in bt.duties:
			if d.brain.mind == ClownBrain.Mind.IDLE:
				first = d
				break
		if first:
			var where := first.clown.global_position
			var told_any := {}
			first.brain.alert(home, true, true)
			for i in 70:
				await get_tree().physics_frame
				for o: Clown in game.clowns:
					var ob := o.get_node_or_null("Brain") as ClownBrain
					if ob and ob.mind == ClownBrain.Mind.HUNT:
						told_any[o] = true
			print("      %s called out %d time(s)" % [first.name_of(), first.shouted])
			for o: Clown in game.clowns:
				if o == first.clown or o.dead:
					continue
				var b := o.get_node_or_null("Brain") as ClownBrain
				if b == null:
					continue
				var dist := o.global_position.distance_to(where)
				var told := told_any.has(o)
				if dist <= 7.0:
					print("        near %s %.1f m: %s" % [o.body, dist, "told" if told else "not told"])
				if dist <= 7.0:
					alarm.near += 1
					alarm.near_told += 1 if told else 0
				elif dist > 30.0:
					alarm.far += 1
					alarm.far_told += 1 if told else 0
			# nobody finds anyone: they give up, search, and go back to their posts
			for i in 60 * 60:
				await get_tree().physics_frame
			for d: BattleDuty in bt.duties:
				if d.returned > 0:
					back[0] += 1
					var at_post := d.kind in [BattleDuty.Kind.RUNNER, BattleDuty.Kind.PATROL, BattleDuty.Kind.TRENCH_PATROL] or Vector3(d.post.x - d.clown.global_position.x, 0, d.post.z - d.clown.global_position.z).length() < 0.8
					if at_post and d.brain.mind == ClownBrain.Mind.IDLE:
						back[1] += 1
		pl.set_physics_process(true)
	print("      duties %s; frontline shots %d; legs %s; patrols up top %d; men seen on a bridge %d; still unaware %d" % [tot, shots, legs, on_top, crossed, hunting])
	print("      far side: %d flashes, %d flares, %d tracer bursts" % fx)
	print("      from behind: %d of %d riflemen at the step did not notice" % [ambushed[1], ambushed[0]])
	print("      alarm: %d of %d within 7 m told; %d of %d beyond 30 m told" % [alarm.near_told, alarm.near, alarm.far_told, alarm.far])
	print("      back to duty: %d of %d alerted men back at it" % [back[1], back[0]])
	_check(tot.frontline > 0 and tot.guard + tot.runner + tot.patrol > 0, "the soldiers have jobs: frontline riflemen and guards, runners or patrols")
	_check(shots > 0, "the frontline fires over the parapet now and then")
	_check(legs.runner > 0, "runners run their messages")
	_check(tot.patrol == 0 or legs.patrol > 0, "patrols walk their beat up top")
	_check(tot.bridge_runs == 0 or crossed > 0, "men cross the footbridges")
	_check(hunting == 0, "nobody hunts a player nobody has seen or heard")
	_check(fx[0] > 0 and fx[1] > 0 and fx[2] > 0, "the far side fires: flashes, flares, tracer")
	_check(ambushed[0] == 0 or ambushed[1] == ambushed[0], "a rifleman at the step can be come at from behind")
	_check(alarm.near == 0 or alarm.near_told * 2 >= alarm.near, "the alarm reaches the men near him")
	_check(alarm.far_told == 0, "and not the men far off")
	_check(back[0] > 0 and back[1] * 4 >= back[0] * 3, "they go back to their duties")


func _ground_below(from: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
	var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return (r.position as Vector3).y if not r.is_empty() else from.y - 6.0


## Vertical deaths: a soldier shot on a footbridge, and one shot at the edge of
## a trench up top, fall into the trench as ragdolls and come to rest on its floor.
func _falls() -> void:
	print("-- falls")
	var res := []
	for sd in [4242, 1001, 777]:
		trench_seed = sd
		await _new_game(3)
		trench_seed = 0
		var m: TrenchMaze = game.maze
		for c: Clown in game.clowns:
			c.queue_free()
		game.clowns.clear()
		await _frames(2)
		game.player.global_position = m.cell_center(m.start_cell) + Vector3.UP * 0.2
		var cases := []
		if not m.bridges.is_empty():
			var br: Dictionary = m.bridges[0]
			var mid: Vector3 = ((br.a as Vector3) + (br.b as Vector3)) * 0.5
			var along: Vector3 = ((br.b as Vector3) - (br.a as Vector3)) * Vector3(1, 0, 1)
			# off the side without the handrail
			var side: Vector3 = -(br.get("rail_side", along.normalized().cross(Vector3.UP)) as Vector3).normalized()
			mid.y = m.floor_height(mid + Vector3.UP * 0.3)
			cases.append(["bridge", mid, side, _ground_below(mid + Vector3.DOWN * 0.3)])
			var edge := mid + side * 0.3
			edge.y = m.floor_height(edge + Vector3.UP * 0.3)
			cases.append(["bridge edge", edge, side, _ground_below(mid + Vector3.DOWN * 0.3)])
		# up top at the lip of a support or reserve trench, shot toward it
		var hit := false
		for t: Vector2i in m.open_cells:
			if hit:
				break
			if m.bays.has(t) or not (m.kind.get(t, "") in ["support", "reserve"]):
				continue
			for dir in Maze.DIRS:
				if m.open_cells.has(t + dir):
					continue
				var dv := Vector3(dir.x, 0, dir.y)
				var r := m._rect(t)
				var at := m.cell_center(t)
				var half := (r.size.x if dir.x != 0 else r.size.y) * 0.5
				var ctr := r.get_center()
				at = Vector3(ctr.x, 0, ctr.y) + dv * (half + 0.45)
				at.y = m.floor_height(at)
				var fl := m.floor_height(m.cell_center(t))
				if at.y > fl + 1.5 and m.bridge_at(at, 1.0).is_empty():
					cases.append(["parapet", at, -dv, fl])
					hit = true
					break
		var men := []
		for cs: Array in cases:
			var c: Clown = game._spawn_clown(true, false)
			c.global_position = cs[1]
			c.rotation.y = atan2(-cs[2].x, -cs[2].z)
			var b := c.get_node_or_null("Brain")
			if b:
				b.set_process(false)
				b.set_physics_process(false)
			men.append(c)
		await _frames(20)
		for i in men.size():
			var c: Clown = men[i]
			var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
			var dir: Vector3 = (cases[i][2] as Vector3).normalized()
			# a round through the middle of the chest (not the throat: that one
			# drops him on the spot to bleed out, wherever he stands)
			c.enable_throat_death = false
			c.hit({collider = chest, position = chest.global_position - dir * 0.1 - Vector3.UP * 0.05, direction = dir, damage = 500.0, impulse = 22.0, shot_id = randi()})
		await _frames(60 * 7)
		for i in men.size():
			var c: Clown = men[i]
			var hips: PhysicalBone3D = c.ragdoll.bones[&"Hips"]
			var floor_y: float = cases[i][3]
			var start_y: float = (cases[i][1] as Vector3).y
			var lv := hips.linear_velocity.length()
			print("      %s (seed %d): from %.2f m to hips %.2f m (trench floor %.2f), moving %.2f m/s" % [cases[i][0], sd, start_y, hips.global_position.y, floor_y, lv])
			if hips.global_position.y > floor_y + 0.9 and OS.get_cmdline_user_args().has("why"):
				var q := PhysicsRayQueryParameters3D.create(hips.global_position, hips.global_position + Vector3.DOWN * 3.0, 1)
				var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
				var off := hips.global_position - (cases[i][1] as Vector3)
				print("        lying on %s at %s; hips moved %s from where he stood; pushed %s" % [r.get("collider"), r.get("position"), off, cases[i][2]])
			var hy := hips.global_position.y
			var on_floor := hy < start_y - 0.8 and hy < floor_y + 0.9 and hy > floor_y - 0.3
			var on_deck := hy > start_y - 0.15 and hy < start_y + 0.9
			res.append([cases[i][0], on_floor, lv < 0.3, on_floor or on_deck])
	var deck := res.filter(func(r: Array) -> bool: return r[0].begins_with("bridge"))
	var over := deck.filter(func(r: Array) -> bool: return r[1]).size()
	print("      shot on a footbridge: %d of %d went over the side into the trench (the rest crumpled where they stood, on the deck)" % [over, deck.size()])
	_check(deck.size() > 0 and over * 2 >= deck.size(), "men shot on a footbridge fall from it into the trench (at least half)")
	_check(deck.all(func(r: Array) -> bool: return r[3] and r[2]), "and every one comes to rest on the deck or the trench floor, not in the air")
	for kind_: String in ["parapet"]:
		# (not every body has to go over: most do)
		var all := res.filter(func(r: Array) -> bool: return r[0] == kind_)
		var fell := all.filter(func(r: Array) -> bool: return r[1]).size()
		_check(not all.is_empty() and fell * 3 >= all.size() * 2, "shot at the lip of a trench, most fall in and land on its floor (%d of %d)" % [fell, all.size()])
		_check(all.all(func(r: Array) -> bool: return r[2]), "and comes to rest there")


## CPU cost of the battle (the soldiers' duties and the far side's effects):
## the physics and process step on a trench floor with it, and with it taken
## away. Headless, so the GPU (and the mist) are not in it.
func _perf() -> void:
	print("-- perf")
	var res := {}
	for with_battle in [true, false, true, false]:
		trench_seed = 4242
		await _new_game(3)
		trench_seed = 0
		var bt: TrenchBattle = game.battle
		if not with_battle:
			for d: BattleDuty in bt.duties:
				d.brain.duty = null
				d.brain.perceive_every = 0.0
				d.queue_free()
			bt.duties.clear()
			bt.set_process(false)
			if bt.field:
				bt.field.queue_free()          # and the men out in No Man's Land
		await _frames(120)
		var n := 900
		var t0 := Time.get_ticks_usec()
		for i in n:
			await get_tree().physics_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		res[with_battle] = res.get(with_battle, []) + [ms]
		print("      %s: %.2f ms a frame (wall clock, headless: physics, AI, scripts), %d enemies%s" % ["with the battle" if with_battle else "without it", ms, game.clowns.size(), (", %d men out in No Man's Land" % bt.field.alive().size()) if with_battle and bt.field else ""])
	var a: float = (res[true][0] + res[true][1]) * 0.5
	var b: float = (res[false][0] + res[false][1]) * 0.5
	print("      the battle adds %.2f ms a frame on the CPU (%.2f against %.2f)" % [a - b, a, b])
	_check(a - b < 2.0, "the battle costs under 2 ms a frame on the CPU")


func _game() -> void:
	print("-- game")
	var kinds := []
	for f in [1, 2, 3, 4, 6]:
		await _new_game(f)
		kinds.append("%d:%s" % [game.floor_number, "trench" if game.maze is TrenchMaze else "bunker"])
		if f == 3:
			var env: Environment = game._world_env.environment
			_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and env.ambient_light_energy > 0.5 and env.fog_mode == Environment.FOG_MODE_DEPTH and env.adjustment_color_correction != null, "overcast sky light, depth haze and the cold grade on the trench floor")
			var counts := {}
			for c: Clown in game.clowns:
				counts[c.body] = counts.get(c.body, 0) + 1
			print("      floor 3 enemies: %s" % counts)
			var soldiers: int = game.clowns.filter(func(c: Clown) -> bool: return c.body != "clown").size()
			_check(soldiers >= game.clowns.size() * 0.6, "mostly soldiers (%d of %d)" % [soldiers, game.clowns.size()])
			var m: TrenchMaze = game.maze
			var ex: Vector3 = game._exit.global_position
			_check(m.is_open(m.cell_of(ex)) and absf(ex.y - m.floor_height(ex)) < 0.1, "the exit door stands on the floor in the end of the fire trench")
			await _walk(m)
		if f == 4:
			_check(game._world_env.environment == game._bunker_env, "back to the bunker's dark below ground")
	print("      floors: %s" % [kinds])
	_check(kinds == ["1:bunker", "2:bunker", "3:trench", "4:bunker", "6:trench"], "every third floor is the trenches")


## Where a man walks through cell `c`: the middle of the floor, but behind
## the fire step in a bay (the step is for standing on to look out, at the
## front), and to one side of anything standing in the middle (a shattered tree).
func _walk_point(m: TrenchMaze, c: Vector2i) -> Vector3:
	var p := m.cell_center(c)
	if m.bays.has(c):
		var r := m._rect(c)
		p.z = r.end.y - 0.55
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 0.9
	q.shape = cap
	q.collision_mask = 1
	for off: Vector3 in [Vector3.ZERO, Vector3(0.55, 0, 0), Vector3(-0.55, 0, 0), Vector3(0, 0, 0.55), Vector3(0, 0, -0.55), Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0), Vector3(0, 0, 0.9), Vector3(0, 0, -0.9), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5)]:
		var at := p + off
		at.y = m.floor_height(at)
		q.transform = Transform3D(Basis(), at + Vector3.UP * 1.0)
		var hits := space.intersect_shape(q, 4).filter(func(h: Dictionary) -> bool: return h.collider.name != "Ground")
		if hits.is_empty() and m.is_open(m.cell_of(at)):
			return at
	return p


## Walk the player along the whole route by input-free velocity: he should
## follow the floor (duckboards, slopes) and never fall through or stick.
func _walk(m: TrenchMaze) -> void:
	var p: FpsPlayer = game.player
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	p.global_position = m.cell_center(m.route[0]) + Vector3.UP * 0.2
	var stuck := 0
	var nudges := 0
	var worst_off := 0.0
	var reached := 0
	_key(KEY_W, true)
	for i in range(1, m.route.size()):
		var target := _walk_point(m, m.route[i])
		var t := 0.0
		# (like a player: held up by something, he steps to one side and on)
		var last := p.global_position
		var stall := 0.0
		var side_t := 0.0
		var side := Vector3.ZERO
		var side_sign := 1.0
		while t < 4.0:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.35:
				break
			var aim := to
			if side_t > 0.0:
				side_t -= 1.0 / 60.0
				aim = to.normalized() * 0.4 + side
			p.rotation.y = atan2(-aim.x, -aim.z)        # walk at it (forward is -Z)
			await get_tree().physics_frame
			t += 1.0 / 60.0
			worst_off = maxf(worst_off, absf(p.global_position.y - m.floor_height(p.global_position)))
			stall = stall + 1.0 / 60.0 if Vector2(p.global_position.x - last.x, p.global_position.z - last.z).length() < 0.6 / 60.0 else 0.0
			last = p.global_position
			if stall > 0.5 and side_t <= 0.0:
				stall = 0.0
				side = to.normalized().cross(Vector3.UP) * side_sign
				side_sign = -side_sign
				side_t = 0.45
				nudges += 1
		if t >= 4.0:
			stuck += 1
			var c: Vector2i = m.route[i]
			var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.5, target + Vector3.UP * 0.5, 1)
			var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			print("        stuck going %s -> %s (%s%s%s), at %s, target %s; in the way: %s at %s (maze seed %d)" % [m.route[i - 1], c, m.kind.get(c, "?"), ", bridge" if m.bridge_sites.has(c) or m.bridges.any(func(b: Dictionary) -> bool: return b.cell == c) else "", ", bay" if m.bays.has(c) else "", p.global_position, target, r.get("collider"), r.get("position"), m.rng.seed])
		else:
			reached += 1
	_key(KEY_W, false)
	print("      walked the route: %d of %d cells reached, %d stuck (%d side-steps round something), worst height off the walked surface %.2f m" % [reached, m.route.size() - 1, stuck, nudges, worst_off])
	_check(stuck == 0, "the player walks the whole route, start to exit")
	_check(worst_off < 0.5, "and stays on the ground (%.2f m)" % worst_off)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _bodies() -> void:
	print("-- bodies")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	game.player.global_position = m.cell_center(m.start_cell) + Vector3.UP * 0.2
	# spots: on a duckboard, in water, on a fire step, against a wall
	var spots := {}
	for d: Dictionary in m.duckboards:
		if d.sunk == 0.0 and not spots.has("duckboard"):
			spots["duckboard"] = ((d.a as Vector3) + (d.b as Vector3)) * 0.5
	for wa: Dictionary in m.water:
		var cells: Array = wa.cells
		spots["water"] = m.cell_center(cells[0])
		break
	for c: Vector2i in m.bays:
		var r := m._rect(c)
		spots["fire step"] = Vector3(r.get_center().x, 0, r.position.y + 0.3)
		break
	for c: Vector2i in m.open_cells:
		if m.wall(c, Vector2i(1, 0)) == "earth":
			var r := m._rect(c)
			spots["earth wall"] = Vector3(r.end.x - 0.35, 0, r.get_center().y)
			break
	var kinds := ["witzsoldat", "clown", "rattlejack", "klappersoldat"]
	var i := 0
	var victims := {}
	for name_: String in spots:
		var p: Vector3 = spots[name_]
		p.y = m.floor_height(p)
		var c: Clown
		match kinds[i % kinds.size()]:
			"rattlejack": c = game.spawn_rattlejack()
			"klappersoldat": c = game.spawn_klapper()
			_: c = game._spawn_clown(kinds[i % kinds.size()] == "witzsoldat", false)
		c.global_position = p
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		victims[name_] = c
		i += 1
	await _frames(20)
	for name_: String in victims:
		var c: Clown = victims[name_]
		var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
		var dir := Vector3(randf_range(-1, 1), -0.1, randf_range(-1, 1)).normalized()
		c.hit({collider = chest, position = chest.global_position - dir * 0.1, direction = dir, damage = 500.0, impulse = 18.0, shot_id = randi()})
	# and a Carnival Curse on a WitzSoldat in the middle of a trench
	var cc: Clown = game._spawn_clown(true, false)
	var cp := m.cell_center(m.route[m.route.size() / 2])
	cc.global_position = cp
	await _frames(15)
	var cursed: bool = cc.begin_curse({}, cc.global_position + Vector3.UP * 1.3, -cc.global_basis.z)
	await _frames(60 * 6)
	for name_: String in victims:
		var c: Clown = victims[name_]
		_report(m, name_, c)
	_check(cursed, "the curse takes a WitzSoldat in the trench")
	if is_instance_valid(cc):
		_report(m, "cursed", cc)
		var info: Dictionary = cc.get_meta(&"curse", {})
		_check(info.get("handover_at", -1.0) > 2.0, "the execution ran to the ragdoll (%.2f s)" % info.get("handover_at", -1.0))
	print("      blood pools %d" % Blood.pools().size())
	_check(Blood.pools().size() >= 2, "blood pools on the trench floor")


func _ambience() -> void:
	print("-- ambience")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var amb: TrenchAmbience = m.get_node("Art/Ambience")
	var art: TrenchArt = m.get_node("Art")
	var p: FpsPlayer = game.player
	var hp := p.health
	FpsPlayer.god_mode = false
	await _walk(m)
	# and through the water
	for wa: Dictionary in m.water:
		var cells: Array = wa.cells
		p.global_position = m.cell_center(cells[0]) + Vector3.UP * 0.2
		await _frames(5)
		_key(KEY_W, true)
		for i in 90:
			var to := m.cell_center(cells[mini(1, cells.size() - 1)]) - p.global_position
			if Vector2(to.x, to.z).length() < 0.3:
				to = m.cell_center(cells[0]) - p.global_position
			p.rotation.y = atan2(-to.x, -to.z)
			await get_tree().physics_frame
		_key(KEY_W, false)
		break
	# stand by the music box a while
	if art.music_box != Vector3.INF:
		amb._t_tune = 0.5
		p.global_position = m.cell_center(m.cell_of(art.music_box)) + Vector3.UP * 0.2
		await _frames(60)
	print("      steps %s; shells %d (flashes %d); tunes %d; health %.0f -> %.0f" % [amb.steps, amb.booms, amb.flashes, amb.tunes, hp, p.health])
	_check(amb.steps.get("mud", 0) + amb.steps.get("wood", 0) > 20, "footsteps along the trench (mud and duckboards)")
	_check(amb.steps.get("wood", 0) > 5, "duckboards sound like wood")
	_check(amb.steps.get("water", 0) > 0 or m.water.is_empty(), "wading the flooded stretch splashes")
	_check(amb.booms > 0 and amb.flashes > 0, "the guns far off: flashes and booms")
	_check(art.music_box == Vector3.INF or amb.tunes > 0, "the music box plays when you are by it")
	_check(p.health >= hp, "none of it hurts")
	FpsPlayer.god_mode = true
	var counts := {}
	for mmi in art.find_children("*", "MultiMeshInstance3D", false, false):
		counts[mmi.name] = (mmi as MultiMeshInstance3D).multimesh.instance_count
	print("      dressing: %s" % counts)
	_check(art.get_node_or_null("Wire") != null and art.get_node_or_null("Balloon") != null, "wire in No Man's Land, a red balloon caught on it")
	_check(art.find_children("*", "Label3D", false, false).size() >= 4, "signs at the junctions (%d)" % art.find_children("*", "Label3D", false, false).size())
	_check(counts.get("crates", 0) >= 4 and counts.get("helmets", 0) + counts.get("tins", 0) > 3, "clutter about the place")


func _report(m: TrenchMaze, name_: String, c: Clown) -> void:
	var lowest := 9.0
	var hips := 9.0
	var under := 0.0
	for bn: StringName in c.ragdoll.bones:
		var pb: PhysicalBone3D = c.ragdoll.bones[bn]
		var g := m.floor_height(pb.global_position)
		var off := pb.global_position.y - g
		lowest = minf(lowest, off)
		if bn == &"Hips":
			hips = off
		under = minf(under, off)
	var speed := 0.0
	for pb: PhysicalBone3D in c.ragdoll.bones.values():
		speed = maxf(speed, pb.linear_velocity.length())
	print("      %s (%s): hips %.2f m above the walked surface, lowest bone %.2f, moving %.2f m/s" % [name_, c.body, hips, lowest, speed])
	# slumped against the sloping earth wall a body can end up sitting: allow more there
	var top := 0.8 if name_ == "earth wall" else 0.6
	_check(hips > -0.12 and hips < top and lowest > -0.2, "%s: lying on the ground, not floating or through it" % name_)
	_check(speed < 0.3, "%s: at rest" % name_)


## Render only: normal-map orientation through the mud shader. Textures
## made the way tools/gen_trench_textures.py makes them (OpenGL: red = -dh/du,
## green = +dh/drow, i.e. tilted toward the top of the image) from a known
## slope, compressed to two channels as the import does, on the ground up
## top, the trench floor and walls facing each way; the shader's world normal
## (debug_view) must lean away from the uphill side.
func _normals() -> void:
	if not render:
		return
	print("-- normals")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	add_child(cam)
	cam.make_current()
	var ramps := {"u": _ramp_tex(true), "row": _ramp_tex(false)}
	var shader: Shader = load("res://shaders/mud_terrain.gdshader" if not OS.get_cmdline_user_args().has("oldshader") else "res://shaders/zz_old_mud.gdshader")
	# surfaces: name, centre, outward normal, which world axis the texture's u
	# runs along, which way image-down (row) runs, floor mask, distance from edge
	var surfaces := [
		["ground", Vector3(0, 0, 0), Vector3.UP, Vector3.RIGHT, Vector3.BACK, 0.0, 1.0],
		["floor", Vector3(0, 0, 0), Vector3.UP, Vector3.RIGHT, Vector3.BACK, 1.0, 0.0],
		["wall +x", Vector3(0, 0, 0), Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, 0.0, 0.2],
		["wall -x", Vector3(0, 0, 0), Vector3.LEFT, Vector3.BACK, Vector3.DOWN, 0.0, 0.2],
		["wall +z", Vector3(0, 0, 0), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.0, 0.2],
		["wall -z", Vector3(0, 0, 0), Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, 0.0, 0.2],
	]
	var bad := 0
	var lines := []
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	for sf: Array in surfaces:
		for ramp: String in ramps:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			for k in ["wall_n", "rocks_n", "firm_n", "floor_n"]:
				mat.set_shader_parameter(k, ramps[ramp])
			mat.set_shader_parameter("noise_tex", black)        # no puddles over the test surface
			mat.set_shader_parameter("floor_scan", sf[0] == "floor")
			mat.set_shader_parameter("floor_depth", 0.0)
			mat.set_shader_parameter("debug_view", 1)
			var mi := MeshInstance3D.new()
			mi.mesh = _quad(sf[2], Color(0.0, sf[5], sf[6] * 0.5, 0.5))
			mi.material_override = mat
			add_child(mi)
			var out: Vector3 = sf[2]
			cam.global_position = out * 3.0
			cam.look_at(Vector3.ZERO, Vector3.FORWARD if absf(out.y) > 0.9 else Vector3.UP)
			await _frames(3 if not lines.is_empty() else 30)   # the first waits for the shader to compile
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2).srgb_to_linear()
			var nrm := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
			# uphill: along u for the u ramp, along image-down for the row ramp
			var uphill: Vector3 = sf[3] if ramp == "u" else sf[4]
			var lean := nrm.dot(uphill)
			var faces := nrm.dot(out)
			var ok := lean < -0.1 and faces > 0.5
			if not ok:
				bad += 1
			lines.append("%s, slope along %s: normal (%.2f, %.2f, %.2f), toward uphill %.2f, outward %.2f %s" % [sf[0], ramp, nrm.x, nrm.y, nrm.z, lean, faces, "" if ok else "  <- WRONG"])
			mi.queue_free()
			await _frames(1)
	# the props' shader (pbr_object): a board (grain along it) and an iron
	# sheet (rust running down), faces each way. Expected (u, v) per face, as
	# the shader maps them with variation off: the uphill side is +u for a
	# slope along u, +v (down the image) for a slope down the rows.
	var obj_shader: Shader = load("res://shaders/pbr_object.gdshader")
	var props := [
		["board +z", true, Vector3.BACK, Vector3.UP, Vector3.RIGHT],
		["board -z", true, Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		["board +y", true, Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		["board +x", true, Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		["iron +z", false, Vector3.BACK, Vector3.RIGHT, Vector3.DOWN],
		["iron -x", false, Vector3.LEFT, Vector3.BACK, Vector3.DOWN],
		["iron +y", false, Vector3.UP, Vector3.RIGHT, Vector3.BACK],
	]
	for pr: Array in props:
		for ramp: String in ramps:
			var mat := ShaderMaterial.new()
			mat.shader = obj_shader
			mat.set_shader_parameter("normal_tex", ramps[ramp])
			mat.set_shader_parameter("noise_tex", black)
			mat.set_shader_parameter("grain", pr[1])
			mat.set_shader_parameter("vary", false)
			mat.set_shader_parameter("debug_view", 1)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			mi.mesh = bm
			mi.scale = Vector3(2.0, 0.6, 0.3) if pr[1] else Vector3(1.4, 2.0, 0.4)
			mi.material_override = mat
			add_child(mi)
			var out: Vector3 = pr[2]
			cam.size = 0.1
			cam.global_position = out * 3.0
			cam.look_at(Vector3.ZERO, Vector3.FORWARD if absf(out.y) > 0.9 else Vector3.UP)
			await _frames(30 if pr == props[0] and ramp == "u" else 3)
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2).srgb_to_linear()
			var nrm := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
			var uphill: Vector3 = pr[3] if ramp == "u" else pr[4]
			var lean := nrm.dot(uphill)
			var faces := nrm.dot(out)
			var ok := lean < -0.1 and faces > 0.5
			if not ok:
				bad += 1
			lines.append("%s, slope along %s: normal (%.2f, %.2f, %.2f), toward uphill %.2f, outward %.2f %s" % [pr[0], ramp, nrm.x, nrm.y, nrm.z, lean, faces, "" if ok else "  <- WRONG"])
			mi.queue_free()
			await _frames(1)
	for l: String in lines:
		print("      " + l)
	_check(bad == 0, "raised detail leans away from the uphill side, and faces out, on every surface (%d wrong)" % bad)
	env.queue_free()
	cam.queue_free()


## Render only: raised and recessed detail lit. A normal map of three
## domes and a groove (encoded as the generator does, compressed like the
## import) on a patch of ground and a wall, a low sun from the right: the
## domes should be lit on their right, the groove's right-hand bank in shade
## (/tmp/tr_relief.png; "oldshader" uses shaders/zz_old_mud.gdshader).
func _relief() -> void:
	if not render:
		return
	print("-- relief")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.25, 0.25)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var tex := _relief_tex()
	var gimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	gimg.fill(Color(0.55, 0.5, 0.45))
	var grey := ImageTexture.create_from_image(gimg)
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	var path := "res://shaders/mud_terrain.gdshader" if not OS.get_cmdline_user_args().has("oldshader") else "res://shaders/zz_old_mud.gdshader"
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for k in ["churned", "sludge", "wall", "firm"]:
		mat.set_shader_parameter(k + "_n", tex)
		mat.set_shader_parameter(k + "_a", grey)
	mat.set_shader_parameter("noise_tex", black)
	mat.set_shader_parameter("floor_scan", false)
	mat.set_shader_parameter("mud_tile", 2.0)
	mat.set_shader_parameter("wall_tile", 2.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	add_child(cam)
	cam.make_current()
	var shots := []
	for out: Vector3 in [Vector3.UP, Vector3.BACK, Vector3.LEFT]:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(out, Color(0.0, 0.0, 0.5 if out == Vector3.UP else 0.1, 0.5))
		mi.material_override = mat
		# the patch lines up with one texture tile
		mi.position = Vector3(1, 0, 1) if out == Vector3.UP else (Vector3(1, -1, 0) if out == Vector3.BACK else Vector3(0, -1, 1))
		add_child(mi)
		# a low sun from the right of the view (and a little from above)
		var right := Vector3.RIGHT if out == Vector3.UP else (Vector3.RIGHT if out == Vector3.BACK else Vector3.FORWARD)
		var up := Vector3.FORWARD if out == Vector3.UP else Vector3.UP
		var toward_light := (right * 0.85 + out * 0.45 + up * 0.25).normalized()
		sun.look_at_from_position(Vector3.ZERO, -toward_light, Vector3.UP if absf(toward_light.y) < 0.95 else Vector3.RIGHT)
		cam.global_position = mi.position + out * 3.0
		cam.look_at(mi.position, up)
		await _frames(30 if shots.is_empty() else 4)
		await get_tree().process_frame
		shots.append(get_viewport().get_texture().get_image())
		mi.queue_free()
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var sheet := Image.create(w * shots.size(), h, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png("/tmp/tr_relief%s.png" % ("_old" if OS.get_cmdline_user_args().has("oldshader") else ""))
	env.queue_free()
	sun.queue_free()
	cam.queue_free()


## Three raised domes and a sunken groove, as a normal map.
func _relief_tex() -> Texture2D:
	var n := 128
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	for y in n:
		for x in n:
			var v := 0.0
			for d: Vector3 in [Vector3(0.25, 0.3, 0.13), Vector3(0.7, 0.28, 0.1), Vector3(0.3, 0.75, 0.12)]:
				var r := Vector2(x / float(n) - d.x, y / float(n) - d.y).length() / d.z
				v += maxf(0.0, 1.0 - r * r)
			var gx := x / float(n) - 0.72
			if absf(y / float(n) - 0.72) < 0.18:
				v -= maxf(0.0, 1.0 - (gx * gx) / (0.06 * 0.06))     # the groove, running down the image
			hgt[x + y * n] = v
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var gxx := (hgt[(x + 1) % n + y * n] - hgt[(x - 1 + n) % n + y * n]) * 0.5 * n / 6.0
			var gyy := (hgt[x + ((y + 1) % n) * n] - hgt[x + ((y - 1 + n) % n) * n]) * 0.5 * n / 6.0
			var nn := Vector3(-gxx, gyy, 1.0).normalized()       # as tools/gen_trench_textures.py: nx = -gx, ny = +gy
			img.set_pixel(x, y, Color(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5))
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)
	return ImageTexture.create_from_image(img)


## A normal map of a plain slope, encoded as the texture generator does
## (OpenGL), compressed to two channels like the import.
func _ramp_tex(along_u: bool) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var k := 0.6
	var nrm := Vector3(-k, 0.0, 1.0) if along_u else Vector3(0.0, k, 1.0)
	nrm = nrm.normalized()
	img.fill(Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)
	return ImageTexture.create_from_image(img)


## A 2 m quad through the origin facing `out`, with vertex colour `col`.
func _quad(out: Vector3, col: Color) -> Mesh:
	var a := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := out.cross(a).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(out)
	st.set_color(col)
	var p := [-a - b, a - b, a + b, -a + b]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(p[i])
	var m := st.commit()
	return m


## Render only: the walls and the ground up top in the game's light, with the
## current shader and (if shaders/zz_old_mud.gdshader is there) the old one
## (/tmp/tr_walls_<view>_new|old.png).
func _walls() -> void:
	if not render:
		return
	print("-- walls")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 70.0
	var mats := _mud_mats(m)
	var k := m.route.size() / 2
	var p := m.cell_center(m.route[k])
	var shots := {
		"trench": [p + Vector3.UP * 1.65, m.cell_center(m.route[k + 2]) + Vector3.UP * 1.2],
		"wall": [p + Vector3.UP * 1.3, p + Vector3(0.0, 1.0, -1.0)],
		"earth": [p + Vector3.UP * 1.3, p + Vector3(0.0, 1.0, -1.0)],
		"top": [Vector3(m.w * m.cell * 0.5, 2.2, m.d * m.cell * 0.6), Vector3(m.w * m.cell * 0.5 + 4.0, 0.0, m.d * m.cell * 0.6 - 6.0)],
	}
	# a bare earth wall, seen across the trench
	for c: Vector2i in m.open_cells:
		var hit := false
		for dir in Maze.DIRS:
			if m.wall(c, dir) == "earth" and m.wall(c, -dir) == "earth" and m.kind[c] == "comm":
				var cc := m.cell_center(c)
				shots["earth"] = [cc + Vector3(-dir.x, 0, -dir.y) * 0.55 + Vector3.UP * 1.4, cc + Vector3(dir.x, 0, dir.y) * 1.2 + Vector3.UP * 0.9]
				hit = true
				break
		if hit:
			break
	var old_path := "res://shaders/zz_old_mud.gdshader"
	var versions := ["new"]
	if ResourceLoader.exists(old_path):
		versions.append("old")
	for v: String in versions:
		for sm in mats:
			sm.shader = load("res://shaders/mud_terrain.gdshader" if v == "new" else old_path)
		for name_: String in shots:
			cam.global_position = shots[name_][0]
			cam.look_at(shots[name_][1])
			await _frames(30 if name_ == "trench" else 4)
			await _shot("walls_%s_%s" % [name_, v])


func _mud_mats(m: TrenchMaze) -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	for mi in m.get_node("Art").get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader.resource_path.contains("mud") and not mats.has(sm):
				mats.append(sm)
	return mats


## Parallax on the trench floor. Two checks:
##  - depth: with the height map flat at the bottom (everything 4.5 cm deep),
##    the parallaxed floor must look like the same floor lowered 4.5 cm
##    without parallax, seen from steep to grazing (the views compared pixel
##    by pixel);
##  - in the trench: down the longest straight stretch at five pitches, with
##    and without parallax (/tmp/tr_pom_<pitch>_on|off.png), for the eye.
func _parallax() -> void:
	if not render:
		return
	print("-- parallax")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var flat_img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	flat_img.fill(Color(1.0, 1.0, 0.0))                  # AO 1, roughness 1, height 0: all at the bottom
	var flat := ImageTexture.create_from_image(flat_img)
	var nimg := Image.create(8, 8, false, Image.FORMAT_RGB8)
	nimg.fill(Color(0.5, 0.5, 1.0))
	var nflat := ImageTexture.create_from_image(nimg)
	var checker := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var c := ((x / 16) + (y / 16)) % 2
			checker.set_pixel(x, y, Color(0.9, 0.2, 0.1) if c == 0 else Color(0.1, 0.3, 0.9))
	checker.generate_mipmaps()
	var check := ImageTexture.create_from_image(checker)
	var bimg := Image.create(4, 4, false, Image.FORMAT_RGB8)
	bimg.fill(Color.BLACK)
	var black := ImageTexture.create_from_image(bimg)
	var mats := []
	for pom in [true, false]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/mud_terrain.gdshader")
		mat.set_shader_parameter("floor_a", check)
		mat.set_shader_parameter("floor_n", nflat)
		mat.set_shader_parameter("floor_ard", flat)
		mat.set_shader_parameter("noise_tex", black)
		mat.set_shader_parameter("floor_depth", 0.045 if pom else 0.0)
		mat.set_shader_parameter("floor_parallax_range", 1000.0)
		mat.set_shader_parameter("floor_water", -1.0)
		mat.set_shader_parameter("debug_view", 3)
		mats.append(mat)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	var worst := 0.0
	for pitch_deg in [80.0, 60.0, 40.0, 25.0, 17.0]:
		var imgs := []
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _quad(Vector3.UP, Color(1.0, 1.0, 0.0, 0.5))
			mi.scale = Vector3(6, 1, 6)
			mi.material_override = mats[mini(i, 1)]
			mi.position = Vector3(0, -0.045 if i == 1 else 0.0, 0)      # 0 parallax; 1 no parallax, lowered; 2 no parallax, not lowered (control)
			add_child(mi)
			var pitch := deg_to_rad(pitch_deg)
			cam.global_position = Vector3(0.3, 0.6 * sin(pitch) + 0.1, 0.6 * cos(pitch) + 0.2)
			cam.look_at(Vector3(0.3, 0.0, 0.2))
			await _frames(30 if imgs.is_empty() and pitch_deg == 80.0 else 4)
			await get_tree().process_frame
			imgs.append(get_viewport().get_texture().get_image())
			mi.queue_free()
			await _frames(1)
		var frac := _img_diff(imgs[0], imgs[1])
		var control := _img_diff(imgs[0], imgs[2])
		worst = maxf(worst, frac if pitch_deg >= 25.0 else 0.0)
		print("      looking %2d deg down: parallaxed vs really lowered 4.5 cm: %.1f%% of pixels differ (vs not lowered at all: %.1f%%)" % [int(pitch_deg), frac * 100.0, control * 100.0])
		if pitch_deg >= 25.0 and control < 0.05:
			worst = 1.0                     # the parallax did nothing visible: the check means nothing
	_check(worst < 0.04, "parallax puts the surface where the height map says, from steep to low angles (worst %.1f%%)" % (worst * 100.0))
	env.queue_free()
	cam.queue_free()
	# in the trench, down the longest straight run
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var best: Array = []
	for name_: String in m.trenches:
		var cells: Array = m.trenches[name_]
		var run: Array = []
		for c: Vector2i in cells:
			if run.size() >= 2 and (c - (run.back() as Vector2i)) != ((run.back() as Vector2i) - (run[run.size() - 2] as Vector2i)):
				run = [run.back()]
			if not run.is_empty() and ((c - (run.back() as Vector2i)).length_squared() != 1):
				run = []
			run.append(c)
			if run.size() > best.size():
				best = run.duplicate()
	var a0 := m.cell_center(best[0])
	var a1 := m.cell_center(best.back())
	var dir := (a1 - a0)
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3.ZERO
	var cam2 := Camera3D.new()
	cam2.fov = 75.0
	add_child(cam2)
	cam2.make_current()
	var gm := _mud_mats(m)
	print("      longest straight stretch: %d cells (%.1f m)" % [best.size(), best.size() * m.cell])
	# the duckboards hide most of the floor: lift them out for these views
	for n in ["db_slats", "db_runners"]:
		var node := m.get_node_or_null("Art/" + n)
		if node:
			node.visible = false
	for pitch_deg in [3.0, 10.0, 20.0, 35.0, 60.0]:
		for pom in [true, false]:
			for sm in gm:
				sm.set_shader_parameter("floor_depth", 0.045 if pom else 0.0)
			cam2.global_position = a0 + side + Vector3.UP * 1.65 - dir * 0.3
			cam2.look_at(cam2.global_position + dir * cos(deg_to_rad(pitch_deg)) + Vector3.DOWN * sin(deg_to_rad(pitch_deg)))
			await _frames(30 if pitch_deg == 3.0 and pom else 3)
			await _shot("pom_%02d_%s" % [int(pitch_deg), "on" if pom else "off"])
	for sm in gm:
		sm.set_shader_parameter("floor_depth", 0.045)
	cam2.queue_free()


func _img_diff(a: Image, b: Image) -> float:
	var diff := 0
	var tot := 0
	for y in range(a.get_height() / 4, a.get_height() * 3 / 4, 2):
		for x in range(a.get_width() / 4, a.get_width() * 3 / 4, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			tot += 1
			if absf(ca.r - cb.r) + absf(ca.b - cb.b) > 0.5:
				diff += 1
	return float(diff) / maxf(tot, 1)


## Render only: the cinematic look, from first-person height, the same
## layout every time (seed 4242) so stages compare: down a long trench, over
## the parapet, an enemy 8 m off, a dark corner, looking up out of the trench
## (/tmp/tr_cine_<shot>_<tag>.png; "tag=xyz" names the set).
func _cine() -> void:
	if not render:
		return
	print("-- cine")
	var tag := "now"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	if game == null:
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await _frames(2)
		FpsPlayer.god_mode = true
	game.start_run()
	game.floor_number = 2
	game.rng.seed = 4242
	game.next_floor()
	await _frames(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for cl in game.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false               # no HUD in these
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	# the longest straight stretch
	var best: Array = []
	for name_: String in m.trenches:
		var cells: Array = m.trenches[name_]
		var run: Array = []
		for c: Vector2i in cells:
			if run.size() >= 2 and (c - (run.back() as Vector2i)) != ((run.back() as Vector2i) - (run[run.size() - 2] as Vector2i)):
				run = [run.back()]
			if not run.is_empty() and ((c - (run.back() as Vector2i)).length_squared() != 1):
				run = []
			run.append(c)
			if run.size() > best.size():
				best = run.duplicate()
	var a0 := m.cell_center(best[0])
	var a1 := m.cell_center(best.back())
	var dir := (a1 - a0)
	dir.y = 0.0
	dir = dir.normalized()
	# an enemy 8 m down it, standing still
	var foe: Clown = game._spawn_clown(true, false)
	var fp := a0 + dir * minf(8.0, a0.distance_to(a1))
	fp.y = m.floor_height(fp)
	foe.global_position = fp
	foe.rotation.y = atan2(-dir.x, -dir.z)
	await _frames(2)
	foe.global_position = fp
	print("      enemy at %s, %0.1f m from the eye (now at %s, in tree %s, visible %s, body %s, model %s)" % [fp, fp.distance_to(a0), foe.global_position, foe.is_inside_tree(), foe.is_visible_in_tree(), foe.body, foe.get("_model")])
	var b := foe.get_node_or_null("Brain")
	if b:
		b.set_process(false)
		b.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	var shots := {}
	var eye := a0 + Vector3.UP * 1.65 - dir * 0.4
	shots["long"] = [eye, eye + dir * 10.0 + Vector3.DOWN * 0.9]
	shots["enemy"] = [eye, fp + Vector3.UP * 1.2]
	shots["up"] = [eye, eye + dir * 4.0 + Vector3.UP * 3.0]
	if OS.get_cmdline_user_args().has("near"):
		shots["near"] = [fp - dir * 2.5 + Vector3.UP * 1.6, fp + Vector3.UP * 1.0]
	for c: Vector2i in m.bays:
		var r := m._rect(c)
		var p := Vector3(r.get_center().x, 0, r.position.y + 0.3)
		p.y = m.floor_height(p) + 1.65
		shots["parapet"] = [p, p + Vector3(0.4, 0.02, -1.0)]
		# up on the fire step, head over the parapet: the battlefield
		var v := p + Vector3(0, 0.9, 0.1)
		shots["vista"] = [v, v + Vector3(0.15, 0.03, -1.0)]
		break
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var ent := m.cell_center(l.entrance)
			var inward := Vector3(l.dir.x, 0, l.dir.y)
			shots["corner"] = [ent - inward * 0.9 + Vector3.UP * 1.6, ent + inward * 1.5 + Vector3.UP * 0.7]
			break
	var first := true
	for name_: String in shots:
		cam.global_position = shots[name_][0]
		cam.look_at(shots[name_][1])
		await _frames(60 if first else 30)          # the eye adaptation settles
		first = false
		await _shot("cine_%s_%s" % [name_, tag])
		if name_ == "enemy":
			print("      at the shot: enemy valid %s at %s, cam %s" % [is_instance_valid(foe), foe.global_position if is_instance_valid(foe) else Vector3.ZERO, cam.global_position])
	foe.queue_free()
	cam.queue_free()


## Render only: the overhauled level's spaces at eye height, with soldiers
## placed (and posed still): a communication trench down its length, two
## abreast in a fire bay, a soldier on a footbridge seen from below and from
## the top, the dugout from its door and inside, a ramp up, the view standing
## on the floor and from a fire step (/tmp/tr_ov_<shot>_<tag>.png).
func _overhaul() -> void:
	if not render:
		return
	print("-- overhaul")
	var tag := "now"
	var sd := 4242
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
		if a.begins_with("seed="):
			sd = int(a.substr(5))
	trench_seed = sd
	await _new_game(3)
	trench_seed = 0
	if OS.get_cmdline_user_args().has("nomist"):
		game._world_env.environment.volumetric_fog_enabled = false
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for cl in game.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	var men: Array[Clown] = []
	var put := func(at: Vector3, face: Vector3, aim := false) -> Clown:
		var c: Clown = game._spawn_clown(true, false)
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		at.y = m.floor_height(at)
		c.global_position = at
		c.rotation.y = atan2(face.x, face.z)
		if aim:
			c.aim_amount = 1.0
			c.aim_point = at + face * 8.0 + Vector3.UP * 1.4
		men.append(c)
		return c
	var shots := []
	# a communication trench, down its longest straight
	var best: Array = []
	for name_: String in m.trenches:
		if not name_.begins_with("comm"):
			continue
		var cells: Array = m.trenches[name_]
		var run: Array = []
		for c: Vector2i in cells:
			if run.size() >= 2 and (c - (run.back() as Vector2i)) != ((run.back() as Vector2i) - (run[run.size() - 2] as Vector2i)):
				run = [run.back()]
			run.append(c)
			if run.size() > best.size():
				best = run.duplicate()
	if best.size() >= 2:
		var a0 := m.cell_center(best[0])
		var a1 := m.cell_center(best.back())
		var dv := (a1 - a0) * Vector3(1, 0, 1)
		shots.append(["comm", a0 + Vector3.UP * 1.65 - dv.normalized() * 0.3, a1 + Vector3.UP * 1.2])
	# a fire bay: two soldiers abreast behind the step, from along the trench
	for c: Vector2i in m.bays:
		if not (m.bays.has(c + Vector2i(1, 0)) and m.open_cells.has(c + Vector2i(-3, 0)) and m.kind.get(c + Vector2i(-3, 0), "") == "fire"):
			continue
		var r := m._rect(c)
		var zf := c.y * m.cell + TrenchMaze.EDGE + 0.45
		var zb := r.end.y - 0.4
		var x := (c.x + 0.5) * m.cell
		put.call(Vector3(x, 0, zf), Vector3(0, 0, -1), true)
		put.call(Vector3(x + 0.3, 0, zb), Vector3(-1, 0, 0))
		var eye := Vector3((c.x - 3 + 0.5) * m.cell, 0, (zf + zb) * 0.5)
		eye.y = m.floor_height(eye) + 1.65
		shots.append(["fire_two", eye, Vector3(x, eye.y - 0.5, (zf + zb) * 0.5)])
		var ov := Vector3(x - 1.5, 0, r.end.y - 0.3)
		ov.y = m.floor_height(ov) + 1.65
		shots.append(["fire_wide", ov, Vector3(x + 1.0, ov.y - 0.6, zf - 0.3)])
		break
	# a footbridge with a soldier on it: from the trench below, and from the top
	if not m.bridges.is_empty():
		var br: Dictionary = m.bridges[0]
		var a: Vector3 = br.a
		var e: Vector3 = br.b
		var mid := (a + e) * 0.5
		var on: Clown = put.call(mid, (e - a).normalized() * Vector3(1, 0, 1))
		on.global_position.y = float(m.bridge_at(on.global_position + Vector3.UP * 0.2).get("deck", mid.y))
		var cc: Vector2i = br.cell
		var below := m.cell_center(cc + Vector2i(-2, 0)) + Vector3.UP * 1.65
		shots.append(["bridge_below", below, mid + Vector3.UP * 0.6])
		var top_eye := m.cell_center(br.ends[0]) + Vector3.UP * 1.65 + Vector3(2.5, 0, 0)
		shots.append(["bridge_top", top_eye, mid + Vector3.UP * 0.9])
	# the dugout: from the door, and inside from the door looking in
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var ent := m.cell_center(l.entrance)
			var inward := Vector3(l.dir.x, 0, l.dir.y)
			shots.append(["dugout_door", ent - inward * 1.2 + Vector3.UP * 1.65, ent + inward * 1.5 + Vector3.UP * 1.1])
			var inside := m.cell_center(l.entrance + l.dir)
			put.call(m.cell_center(l.entrance + l.dir * 2) + Vector3(l.dir.y, 0, l.dir.x) * 1.0, -inward)
			shots.append(["dugout_in", inside - inward * 0.3 + Vector3.UP * 1.65, inside + inward * 3.0 + Vector3.UP * 0.9])
			break
	# a ramp, from the trench floor
	if not m.ramps.is_empty():
		var r: Dictionary = m.ramps[0]
		var foot: Vector2 = r.foot
		var head: Vector2 = r.head
		var u := (head - foot).normalized()
		var at := Vector3(foot.x - u.x * 1.6, 0, foot.y - u.y * 1.6)
		at.y = m.floor_height(at) + 1.65
		shots.append(["ramp", at, Vector3(head.x, at.y + 0.5, head.y)])
	# standing on the support line's floor, looking at its back wall
	for c: Vector2i in m.open_cells:
		if m.kind[c] == "support" and m.open_cells.has(c + Vector2i(1, 0)) and m.open_cells.has(c + Vector2i(-1, 0)):
			var p := m.cell_center(c) + Vector3.UP * 1.65
			shots.append(["support_stand", p + Vector3(0, 0, -0.5), p + Vector3(3.0, -0.2, 1.6)])
			break
	# up on a fire step looking out over No Man's Land (the mist), and down at
	# the floor where the puddles are
	for c: Vector2i in m.bays:
		var st := Vector3((c.x + 0.5) * m.cell, 0, c.y * m.cell + TrenchMaze.EDGE + 0.3)
		st.y = m.floor_height(st) + 1.8
		shots.append(["nml_mist", st, st + Vector3(0.6, -0.9, -25.0)])
		break
	var wettest := Vector2i(-1, -1)
	var most := 0.0
	for c: Vector2i in m.open_cells:
		if m.flooded.has(c) or m.bays.has(c) or m.top_cells.has(c):
			continue
		var p := m.cell_center(c)
		if m.surface_at(p) != "mud":
			continue                       # (puddles under the duckboards don't show)
		var upq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.UP * 8.0, 1)
		if not get_viewport().world_3d.direct_space_state.intersect_ray(upq).is_empty():
			continue                       # (nor under a roof)
		var sum := 0.0
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var ix := int(round((p.x + dx * 0.2 - m.origin.x) / TrenchMaze.RES))
				var iz := int(round((p.z + dz * 0.2 - m.origin.y) / TrenchMaze.RES))
				if ix >= 0 and iz >= 0 and ix < m.hx and iz < m.hz:
					sum += m.puddle[ix + iz * m.hx]
		if sum > most:
			most = sum
			wettest = c
	if wettest.x >= 0:
		var p := m.cell_center(wettest)
		var e := p
		for dir in Maze.DIRS:
			if m.linked(wettest, wettest + dir):
				e = p + Vector3(dir.x, 0, dir.y) * 1.3
				break
		e.y = m.floor_height(e) + 1.6
		shots.append(["puddles", e, p + Vector3.DOWN * 0.3])
	await _frames(4)
	var first := true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			var keep := a.substr(5).split(",")
			shots = shots.filter(func(sh: Array) -> bool: return keep.has(sh[0]))
	for sh: Array in shots:
		cam.global_position = sh[1]
		cam.look_at(sh[2])
		var t0 := Time.get_ticks_msec()
		await _frames(24 if first else 10)
		first = false
		await _shot("ov_%s_%s" % [sh[0], tag])
		print("      shot %s: %d ms" % [sh[0], Time.get_ticks_msec() - t0])
	for c in men:
		c.queue_free()
	cam.queue_free()


## Render only: representative stretches for the materials, at eye height:
## a fire bay (sandbags, boards, fire step), an iron-lined support stretch,
## a bare earth communication trench, the slumped stretch, a duckboard close
## up, a sandbag wall close up (/tmp/tr_sec_*.png).
func _section() -> void:
	if not render:
		return
	print("-- section")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 72.0
	var shots := {}
	# looking along a trench from cell c toward the next in its trench list
	var along := func(c: Vector2i, name_: String) -> void:
		for t: String in m.trenches:
			var cells: Array = m.trenches[t]
			var i := cells.find(c)
			if i >= 0 and i + 2 < cells.size():
				shots[name_] = [m.cell_center(c) + Vector3.UP * 1.62, m.cell_center(cells[i + 2]) + Vector3.UP * 1.1]
				return
	for c: Vector2i in m.bays:
		if m.wall(c, Vector2i(0, 1)) != "" or true:
			along.call(c, "bay")
			break
	for c: Vector2i in m.open_cells:
		if not shots.has("iron") and (m.wall(c, Vector2i(0, 1)) == "iron" or m.wall(c, Vector2i(0, -1)) == "iron"):
			along.call(c, "iron")
		if not shots.has("earth") and m.kind[c] == "comm" and m.wall(c, Vector2i(1, 0)) == "earth":
			along.call(c, "earth")
		if not shots.has("slump") and m.collapsed.has(c):
			var p := m.cell_center(c)
			for dir in Maze.DIRS:
				if m.open_cells.has(c - dir):
					var back := m.cell_center(c - dir)
					shots["slump"] = [back + Vector3.UP * 1.62 - Vector3(dir.x, 0, dir.y) * 0.5, p + Vector3.UP * 0.6]
					break
		for dir in Maze.DIRS:
			if not shots.has("bags") and m.wall(c, dir) == "sandbag" and m.kind[c] in ["fire", "traverse", "sap"]:
				var p := m.cell_center(c)
				shots["bags"] = [p - Vector3(dir.x, 0, dir.y) * 0.45 + Vector3.UP * 1.2, p + Vector3(dir.x, 0, dir.y) * 0.8 + Vector3.UP * 0.8]
	var d: Dictionary = m.duckboards[m.duckboards.size() / 2]
	var mid: Vector3 = ((d.a as Vector3) + (d.b as Vector3)) * 0.5
	shots["boards"] = [mid + Vector3(0.35, 1.0, 0.35), mid]
	for name_: String in shots:
		cam.global_position = shots[name_][0]
		cam.look_at(shots[name_][1])
		await _frames(40 if name_ == shots.keys()[0] else 4)
		await _shot("sec_" + name_)
	print("      shots: %s" % [shots.keys()])


## Render only: the trench floor close up (eye height down the trench, the
## ground at your feet, a flooded stretch), with the scanned mud and, for
## comparison, the old procedural sludge (/tmp/tr_floor_*_new|old.png).
func _floor() -> void:
	if not render:
		return
	print("-- floor")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 70.0
	var mats: Array[ShaderMaterial] = []
	for mi in m.get_node("Art").get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader.resource_path.ends_with("mud_terrain.gdshader") and not mats.has(sm):
				mats.append(sm)
	# a stretch with no duckboards (the flooded side trench or a dugout stub), and the main route
	var bare := m.route[m.route.size() / 2]
	for c: Vector2i in m.open_cells:
		if m.kind[c] in ["gunpit"]:
			bare = c
			break
	var flood := m.start_cell
	for wa: Dictionary in m.water:
		flood = (wa.cells as Array)[0]
		break
	var k := m.route.size() / 3
	var shots := {
		"eye": [m.cell_center(m.route[k]) + Vector3.UP * 1.65, m.cell_center(m.route[k + 3]) + Vector3.UP * 0.2],
		"feet": [m.cell_center(bare) + Vector3(0.2, 1.6, 0.6), m.cell_center(bare) + Vector3(0.0, 0.0, -0.4)],
		"low": [m.cell_center(bare) + Vector3(-0.5, 0.45, 0.5), m.cell_center(bare) + Vector3(0.6, 0.0, -0.5)],
		"flood": [m.cell_center(flood) + Vector3(0.3, 1.6, 0.9), m.cell_center(flood) + Vector3(0, 0, -0.8)],
	}
	for scan in [true, false]:
		for sm in mats:
			sm.set_shader_parameter("floor_scan", scan)
		for name_: String in shots:
			cam.global_position = shots[name_][0]
			cam.look_at(shots[name_][1])
			await _frames(3)
			await _shot("floor_%s_%s" % [name_, "new" if scan else "old"])


func _views() -> void:
	if not render:
		return
	print("-- views")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	var keep: Clown = null
	for c: Clown in game.clowns:
		if keep == null and c.body == "witzsoldat":
			keep = c
		else:
			c.queue_free()
	game.clowns.clear()
	if keep:
		game.clowns.append(keep)
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.far = 500.0
	cam.fov = 75.0
	await _frames(30)
	var mid := Vector3(m.w * m.cell * 0.5, 0, m.d * m.cell * 0.5)
	cam.global_position = mid + Vector3(-20, 45, 45)
	cam.look_at(mid)
	await _frames(2)
	await _shot("top")
	var i := 0
	var picks := [m.start_cell, m.route[m.route.size() / 4], m.route[m.route.size() / 2], m.route[m.route.size() * 3 / 4], m.route[m.route.size() - 3]]
	for c: Vector2i in picks:
		var k := m.route.find(c)
		var p := m.cell_center(c) + Vector3.UP * 1.65
		cam.global_position = p
		var look := m.cell_center(m.route[mini(k + 3, m.route.size() - 1)]) + Vector3.UP * 1.4
		if Vector2(look.x - p.x, look.z - p.z).length() < 0.5:
			look = p + Vector3(1, -0.1, 0)
		cam.look_at(look)
		await _frames(2)
		await _shot("eye_%d" % i)
		i += 1
	# over the parapet from a fire step, into No Man's Land
	for c: Vector2i in m.bays:
		var r := m._rect(c)
		cam.global_position = Vector3(r.get_center().x, m.floor_height(Vector3(r.get_center().x, 0, r.position.y + 0.25)) + 1.65, r.position.y + 0.3)
		cam.look_at(cam.global_position + Vector3(0.3, 0.05, -1))
		await _frames(2)
		await _shot("nml")
		break
	# into a dugout from its door
	var art: TrenchArt = m.get_node("Art")
	for l: Dictionary in m.landmarks:
		if l.kind == "dugout":
			var ent := m.cell_center(l.entrance)
			cam.global_position = ent + Vector3.UP * 1.5 - Vector3(l.dir.x, 0, l.dir.y) * 0.6
			cam.look_at(m.cell_center(l.cell) + Vector3(l.dir.x, 0, l.dir.y) * 0.8 + Vector3.UP * 0.8)
			await _frames(2)
			await _shot("dugout")
			break
	# the music box's dugout, if there is one
	if art.music_box != Vector3.INF:
		var room := m.cell_center(m.cell_of(art.music_box))
		var away := (room - art.music_box)
		away.y = 0.0
		cam.global_position = art.music_box + away.normalized() * 1.1 + Vector3.UP * 0.6
		cam.look_at(art.music_box + Vector3.UP * 0.3)
		await _frames(2)
		await _shot("musicbox")
	# the porcelain head in the mud
	for mmi in art.find_children("porcelain_head", "MultiMeshInstance3D", false, false):
		var at: Vector3 = (mmi as MultiMeshInstance3D).multimesh.get_instance_transform(0).origin
		var c := m.cell_of(at)
		cam.global_position = m.cell_center(c) + Vector3.UP * 1.0 + (m.cell_center(c) - at).normalized() * 0.3
		cam.look_at(at)
		await _frames(2)
		await _shot("head")
	# out over the wire from high up behind the parapet
	cam.global_position = Vector3(m.w * m.cell * 0.5, 3.0, 9.0)
	cam.look_at(Vector3(m.w * m.cell * 0.5, 0.0, -15.0))
	await _frames(2)
	await _shot("wire")
	# a soldier in a trench, from 6 m: can he be seen?
	for c: Clown in game.clowns:
		if is_instance_valid(c) and c.body == "witzsoldat":
			var at := c.global_position
			var cc := m.cell_of(at)
			var k := m.route.find(cc)
			var from := at + Vector3(4, 1.6, 0)
			for dir in Maze.DIRS:
				var n: Vector2i = cc + dir * 3
				if m.open_cells.has(n) and m.open_cells.has(cc + dir) and m.open_cells.has(cc + dir * 2):
					from = m.cell_center(n) + Vector3.UP * 1.6
					break
			cam.global_position = from
			cam.look_at(at + Vector3.UP * 1.1)
			await _frames(2)
			await _shot("enemy")
			break



## How dark the trench is: the same views with the lighting as it is and as
## lifted (render: /tmp/tr_light_<view>_<variant>.png). Variants are applied
## to the live materials and environment, so nothing else changes.
func _light() -> void:
	if not render:
		return
	print("-- light")
	await _new_game(3)
	var m: TrenchMaze = game.maze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 75.0
	cam.attributes = TrenchArt.make_camera_attributes()
	var art: TrenchArt = m.get_node("Art")
	var ground: Array[ShaderMaterial] = []
	for mi in art.get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm.shader.resource_path.ends_with("mud_terrain.gdshader") and not ground.has(sm):
				ground.append(sm)
	var props: Array[ShaderMaterial] = []
	for mt: Material in art._mats.values():
		if mt is ShaderMaterial and (mt as ShaderMaterial).shader.resource_path.ends_with("pbr_object.gdshader"):
			props.append(mt)
	var env: Environment = game._world_env.environment
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	# the longest straight run of the route: looking along its floor, and down
	# at the boards a couple of metres ahead (as a player walking it does)
	var best := [0, 0]
	for i in range(m.route.size() - 1):
		var j := i
		while j + 1 < m.route.size() and m.route[j + 1] - m.route[j] == m.route[i + 1] - m.route[i]:
			j += 1
		if j - i > best[1] - best[0]:
			best = [i, j]
	var a := m.cell_center(m.route[best[0]])
	var b := m.cell_center(m.route[best[1]])
	var fwd := (b - a)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var eye := a + Vector3.UP * (m.floor_height(a) + 1.65 - a.y)
	var views := {
		"along": [eye, eye + fwd * 8.0 + Vector3.DOWN * 1.6],
		"down": [eye, eye + fwd * 2.4 + Vector3.DOWN * 1.65],
		"feet": [eye, eye + fwd * 1.2 + Vector3.DOWN * 1.65],
	}
	var variants: Array = Array(OS.get_environment("LIGHT_VARIANTS").split(";")) if OS.has_environment("LIGHT_VARIANTS") else ["now"]
	for v: String in variants:
		# "now", or "fd=0.6,sf=0.22,amb=0.9,ae=0.3" (floor darkness, sky floor, ambient energy, auto exposure scale)
		# (the settings in the game; "old" is how they were before the lift)
		var fd := 0.75
		var sf := 0.3
		var amb := 1.05
		var ae := 0.4
		var occ := 0.6
		var ex := 1.0
		var ms := 260.0
		var gi := 1.0 if TrenchArt.bounce_light else 0.0
		var ge := 1.5
		var sun := 1.2 if TrenchArt.bounce_light else 0.85
		if TrenchArt.bounce_light:
			amb = 1.0
			occ = 0.0
			ms = 280.0
		if v == "old" or v == "fill":
			gi = 0.0
			sun = 0.85
			amb = 1.05
			occ = 0.6
			ms = 260.0
		if v == "old":
			fd = 0.4
			sf = 0.12
			amb = 0.75
			ae = 0.2
			occ = 1.0
			ms = 125.0
		if v != "now" and v != "old":
			for kv in v.split(","):
				var p := kv.split("=")
				match p[0]:
					"fd": fd = float(p[1])
					"sf": sf = float(p[1])
					"amb": amb = float(p[1])
					"ae": ae = float(p[1])
					"occ": occ = float(p[1])
					"exp": ex = float(p[1])
					"ms": ms = float(p[1])
					"gi": gi = float(p[1])
					"ge": ge = float(p[1])
					"sun": sun = float(p[1])
		for sm in ground:
			sm.set_shader_parameter("floor_darkness", fd)
			sm.set_shader_parameter("sky_floor", sf)
			sm.set_shader_parameter("sky_occlusion", occ)
		env.tonemap_exposure = ex
		env.sdfgi_enabled = gi > 0.5
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_min_cell_size = 0.15
		env.sdfgi_cascades = 4
		env.sdfgi_energy = ge
		env.sdfgi_bounce_feedback = 0.6
		for l in game.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).light_energy = sun
		for sm in props:
			sm.set_shader_parameter("sky_floor", sf)
			sm.set_shader_parameter("sky_occlusion", occ)
		env.ambient_light_energy = amb
		(cam.attributes as CameraAttributesPractical).auto_exposure_scale = ae
		(cam.attributes as CameraAttributesPractical).auto_exposure_max_sensitivity = ms
		for name_: String in views:
			cam.global_position = views[name_][0]
			cam.look_at(views[name_][1])
			await _frames(40 if gi < 0.5 else 150)
			await _shot("light_%s_%s" % [name_, v.replace("=", "").replace(",", "_").replace(".", "")])
