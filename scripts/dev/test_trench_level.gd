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
	var secs := ["layouts", "ground", "geo", "nav", "overhaul", "game", "bodies", "ambience", "views", "floor", "normals", "relief", "walls", "parallax", "section", "cine"]
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
	while t < budget:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if b._go_to(to, 1.0 / 60.0, b.move_speed):
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
	var worst_off := 0.0
	var reached := 0
	_key(KEY_W, true)
	for i in range(1, m.route.size()):
		var target := m.cell_center(m.route[i])
		var t := 0.0
		while t < 2.5:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.35:
				break
			p.rotation.y = atan2(-to.x, -to.z)        # walk at it (forward is -Z)
			await get_tree().physics_frame
			t += 1.0 / 60.0
			worst_off = maxf(worst_off, absf(p.global_position.y - m.floor_height(p.global_position)))
		if t >= 2.5:
			stuck += 1
		else:
			reached += 1
	_key(KEY_W, false)
	print("      walked the route: %d of %d cells reached, %d stuck, worst height off the walked surface %.2f m" % [reached, m.route.size() - 1, stuck, worst_off])
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
	await _frames(4)
	var first := true
	for sh: Array in shots:
		cam.global_position = sh[1]
		cam.look_at(sh[2])
		await _frames(40 if first else 14)
		first = false
		await _shot("ov_%s_%s" % [sh[0], tag])
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
