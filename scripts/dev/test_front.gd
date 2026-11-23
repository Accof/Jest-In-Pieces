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
##   cover     (M3) the shell holes of No Man's Land: a man standing on the
##             floor of one is chest-deep, crouched his head is under the rim;
##             every wall is one he can walk (under 36 degrees); the player
##             crouches (Ctrl): capsule, eye and pace, and stands again
##   wire      (M3) the belts: no top cell under the wire except at a gap; a
##             player walking into a belt is stopped by it and walks through a
##             gap; the brains' path from their lines to ours crosses at a gap
##   crossing  (M3) a rifleman in their fire trench, alerted to the player at
##             our parapet, comes across No Man's Land and arrives
##   game      floor 3 of a run is the Front, SURVIVAL, with the enemies in
##             the trenches (two in three in theirs, none out in the open),
##             the H.Q. door at the exit; the player walks the whole way from
##             the start to the H.Q. by the maze's own path and goes in with [E]
##   atmos     (M4, with "render", Forward+) the four pictures of the visual
##             gate at fixed cameras on seed 1916: (a) our frontline parapet,
##             (b) the No Man's Land panorama, (c) mud, shell hole and wire
##             close to, (d) soldiers at 14, 26 and 42 m in the haze, (e) the same in a thicker bank;
##             /tmp/front_gate_*.png. Also checks the environments are kept
##             apart (bunker, legacy, Front) and the visibility model's range.
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
	var secs := ["layouts", "geo", "cover", "wire", "crossing", "game", "views", "atmos"]
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
	print("      %d of %d seeds failed; %d trench cells avg; route %d cells avg (%d of them over the top); the main route used an assault ramp %d times of %d (the rest go through a sap's gap in the wire); fire trenches %.0f m apart; build %d ms avg, %d ms worst (headless)" % [bad, times.size(), osum / times.size(), rsum / routes.size(), topsum / tops.size(), assault_used, times.size() * 2, gaps[0], tsum / times.size(), tmax])
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
	_check(near_ours >= 5 and near_theirs >= 5, "wire pickets in front of each line (%d ours, %d theirs of %d rattle spots; the rest are the short belts out in the middle)" % [near_ours, near_theirs, art.rattle_spots.size()])
	# the H.Q. is at the front edge of the world, in their rear trench
	var xf := m.exit_transform()
	_check(xf.origin.z < 3.0 and m.theirs.has(m.exit_cell) and m.kind[m.exit_cell] == "comm", "the H.Q. portal at the end of their rear communication trench (z %.1f)" % xf.origin.z)
	m.queue_free()
	await _frames(1)


# --- cover (M3) ---------------------------------------------------------------------------------
func _cover() -> void:
	print("-- cover")
	var m := _make(1916 if fixed_seed == 0 else fixed_seed)
	var z_near := (m.their_row0 + TrenchMaze.GRID_D) * m.cell
	var z_far := m.our_row0 * m.cell
	var n := 0
	var chest_deep := 0
	var head_under := 0
	var walkable := 0
	var worst_slope := 0.0
	var depths: Array[float] = []
	for cr: Vector4 in m.crater_list:
		if cr.y < z_near or cr.y > z_far or cr.z < 2.2:
			continue
		n += 1
		var floor_y := m.floor_height(Vector3(cr.x, 0, cr.y))
		# the rim: the highest ground within 0.9-1.3 radii, in eight directions
		var rim := -99.0
		var steep := 0.0
		for k in 8:
			var dir := Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0))
			# (the slope over a stride, 0.6 m: a 0.2 m step across the bilinear
			# heightfield's diagonals reads a third steeper than the surface is)
			var ys: Array[float] = [floor_y]
			var dist := 0.0
			while dist < cr.z * 1.4:
				dist += 0.2
				var px := cr.x + dir.x * dist
				var pz := cr.y + dir.y * dist
				if m._sample(m.sdf, px, pz) < 0.6:
					break                    # into a trench (a sap's post by the wire): not the hole's wall
				var y := m.floor_height(Vector3(px, 0, pz))
				ys.append(y)
				if ys.size() > 3:
					steep = maxf(steep, absf(y - ys[ys.size() - 4]) / 0.6)
				if dist > cr.z * 0.9:
					rim = maxf(rim, y)
		var cover := rim - floor_y
		depths.append(cover)
		if cover >= 1.25:
			chest_deep += 1
		if cover >= FpsPlayer.CROUCH_EYE + 0.15:
			head_under += 1
		if steep < tan(deg_to_rad(45.0)):
			walkable += 1
		else:
			print("      steep hole at (%.1f, %.1f) r %.1f depth %.2f: %.0f degrees; nearest trench floor %.1f m, on a ramp %s, in the wire %s" % [cr.x, cr.y, cr.z, cr.w, rad_to_deg(atan(steep)), m._nearest(cr.x, cr.y).d, not m.ramp_at(Vector3(cr.x, 0, cr.y)).is_empty(), m.wire_at(cr.x, cr.y)])
		worst_slope = maxf(worst_slope, steep)
	var dsum := 0.0
	for dd in depths:
		dsum += dd
	print("      %d holes 2.2 m and more across in No Man's Land; floor to rim %.2f m on average; %d chest-deep (1.25 m+), %d a crouched head under the rim, %d with every wall under 45 degrees over a stride (steepest %.0f; the player climbs 50)" % [n, dsum / maxi(n, 1), chest_deep, head_under, walkable, rad_to_deg(atan(worst_slope))])
	_check(n >= 25, "enough holes to move between (%d)" % n)
	_check(chest_deep >= n * 0.75, "most are chest-deep: real cover standing")
	_check(head_under >= n * 0.8, "most hide a crouched man's head")
	_check(walkable == n, "every hole can be walked into and out of (no wall steeper than 45 degrees over a stride; the player climbs 50)")
	m.queue_free()
	await _frames(1)
	# the crouch itself, on a real floor
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var p: FpsPlayer = game.player
	var eye0: float = p.camera.position.y
	_check(is_equal_approx(eye0, FpsPlayer.STAND_EYE) and p.crouch == 0.0, "standing: eye at %.2f m" % eye0)
	_key(KEY_CTRL, true)
	for i in 30:
		await get_tree().physics_frame
	_check(p.crouch > 0.99 and absf(p.camera.position.y - FpsPlayer.CROUCH_EYE) < 0.01 and absf(p._capsule.height - FpsPlayer.CROUCH_H) < 0.01, "Ctrl held: crouched, eye %.2f m, capsule %.2f m" % [p.camera.position.y, p._capsule.height])
	_check(absf(p.chest_height() - 0.8) < 0.01 and absf(p.eye_height() - FpsPlayer.CROUCH_EYE) < 0.01, "his chest and eye are reported lower for whoever aims at him")
	# pace: half (the speed asked of the body, so a wall in the way does not count)
	_key(KEY_W, true)
	for i in 20:
		await get_tree().physics_frame
	var crouched_pace := Vector2(p.velocity.x, p.velocity.z).length()
	_key(KEY_W, false)
	_key(KEY_CTRL, false)
	for i in 30:
		await get_tree().physics_frame
	_check(p.crouch == 0.0 and is_equal_approx(p.camera.position.y, FpsPlayer.STAND_EYE), "let go: standing again")
	_key(KEY_W, true)
	for i in 20:
		await get_tree().physics_frame
	var pace := Vector2(p.velocity.x, p.velocity.z).length()
	_key(KEY_W, false)
	_check(crouched_pace < pace * 0.6 and crouched_pace > 1.0, "crouched he moves at %.1f m/s against %.1f walking" % [crouched_pace, pace])


# --- wire (M3) ------------------------------------------------------------------------------------
func _wire() -> void:
	print("-- wire")
	var m := _make(1916 if fixed_seed == 0 else fixed_seed)
	# the layer: no top cell in the wire; the gaps are open
	var bad := 0
	var gap_cells := 0
	for b: Dictionary in m.wire_belts:
		var band := m.belt_band(b)
		for c: Vector2i in m.top_cells:
			var cx := (c.x + 0.5) * m.cell
			var cz := (c.y + 0.5) * m.cell
			if cx < b.x0 or cx > b.x1 or cz < band.x or cz > band.y:
				continue
			var in_gap := false
			for gx: float in b.gaps:
				if absf(cx - gx) < FrontMaze.WIRE_GAP:
					in_gap = true
			if in_gap:
				gap_cells += 1
			else:
				bad += 1
	print("      %d belts (%d short ones in the middle), %d cells taken out for the wire, %d gap cells left in" % [m.wire_belts.size(), m.wire_belts.size() - 2, m.wire_cells.size(), gap_cells])
	_check(bad == 0 and m.wire_cells.size() > 40, "no top cell in the wire")
	_check(gap_cells >= 6, "the gaps are open ground")
	# the brains' way across goes through a gap
	var a := m.cell_center(m.theirs.keys()[0])
	var way := m.path(a, m.cell_center(m.start_cell))
	var through_wire := 0
	for pt: Vector3 in way:
		if m.wire_at(pt.x, pt.z):
			through_wire += 1
	_check(way.size() > 30 and through_wire == 0, "a path from their lines to our start never crosses the wire (%d points)" % way.size())
	m.queue_free()
	await _frames(1)
	# the collision: into the belt, and through a gap
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var fm := game.maze as FrontMaze
	var p: FpsPlayer = game.player
	var belt: Dictionary = fm.wire_belts[0]           # ours
	# a stretch with no gap within 8 m
	var x := 0.0
	var found := false
	for xi in range(4, int(fm.w * fm.cell) - 4):
		x = float(xi)
		var clear := true
		for gx: float in belt.gaps:
			if absf(x - gx) < 4.5:
				clear = false
		if clear:
			found = true
			break
	_check(found, "a stretch of our belt with no gap near (x %.0f)" % x)
	var z_start: float = belt.z + 3.0           # behind the belt (its trench side)
	var start := Vector3(x, 0, z_start)
	start.y = fm.floor_height(start) + 0.1
	p.global_position = start
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0                           # facing -z: into the belt
	_key(KEY_W, true)
	for i in 240:
		await get_tree().physics_frame
	_key(KEY_W, false)
	var went := start.z - p.global_position.z
	_check(went > 1.0 and went < 5.0 and p.global_position.z > fm.belt_band(belt).x - 0.3, "walking into the belt for 4 s he is held at it (%.1f m on, the wire from %.1f to %.1f m)" % [went, belt.z + 3.0 - fm.belt_band(belt).y, belt.z + 3.0 - fm.belt_band(belt).x])
	# through a gap: the one in front of an assault ramp, from the ramp's head
	# (a sap's gap has the sap's trench behind it)
	var gx0 := 0.0
	var head := Vector2.ZERO
	for r: Dictionary in fm.assault_ramps:
		if r.dir.y == -1:
			gx0 = (r.cell.x + 0.5) * fm.cell
			head = r.head
			break
	start = Vector3(gx0, 0, head.y - 1.0)
	start.y = fm.floor_height(start) + 0.1
	p.global_position = start
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	_key(KEY_W, true)
	for i in 240:
		await get_tree().physics_frame
	_key(KEY_W, false)
	went = start.z - p.global_position.z
	_check(went > 7.0, "through the gap at x %.1f he walks on (%.1f m)" % [gx0, went])


# --- crossing (M3) --------------------------------------------------------------------------------
func _crossing() -> void:
	print("-- crossing")
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var m := game.maze as FrontMaze
	var p: FpsPlayer = game.player
	# the player at the head of our first assault ramp, on the top
	var ramp: Dictionary = {}
	for r: Dictionary in m.assault_ramps:
		if r.dir.y == -1:
			ramp = r
			break
	var head: Vector2 = ramp.head
	p.global_position = Vector3(head.x, 0, head.y - 1.5)
	p.global_position.y = m.floor_height(p.global_position) + 0.1
	p.velocity = Vector3.ZERO
	# one rifleman in their fire trench, the rest gone
	var runner: Clown = null
	for c: Clown in game.clowns:
		if runner == null and m.theirs.has(m.cell_of(c.global_position)) and c.has_rifle and not (c is Rattlejack) and not (c is Zornhauptmann) and not (c is Klappersoldat):
			runner = c
		else:
			c.queue_free()
	game.clowns.clear()
	if runner == null:
		_check(false, "no rifleman in their lines to send")
		return
	game.clowns.append(runner)
	# put him on their fire step side, by a bay
	var bay := Vector2i(-1, -1)
	for c: Vector2i in m.bays:
		if m.theirs.has(c):
			bay = c
			break
	runner.global_position = m.cell_center(bay) + Vector3(0, 0, -0.4)
	runner.global_position.y = m.floor_height(runner.global_position)
	await _frames(3)
	var brain: ClownBrain = runner.get_node("Brain")
	brain.use_cover = false
	var d0 := runner.global_position.distance_to(p.global_position)
	brain.alert(p.global_position)
	var t := 0.0
	var closest := d0
	var in_wire := 0
	var up_top := 0
	var frames := 0
	while t < 150.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		frames += 1
		brain.alert(p.global_position, false)
		if runner.dead:
			break
		var d := runner.global_position.distance_to(p.global_position)
		closest = minf(closest, d)
		# inside the wire (not brushing a belt's edge, where a rifleman may stop to shoot)
		var rp := runner.global_position
		if m.wire_at(rp.x, rp.z) and m.wire_at(rp.x, rp.z - 0.4) and m.wire_at(rp.x, rp.z + 0.4):
			in_wire += 1
		if m.on_top(runner.global_position):
			up_top += 1
		if d < 12.0:
			break
	print("      from %.0f m: closest %.1f m after %.0f s; %d of %d frames up on the open ground, %d in the wire" % [d0, closest, t, up_top, frames, in_wire])
	_check(d0 > 70.0, "he started across No Man's Land (%.0f m)" % d0)
	_check(closest < 25.0, "he came over the top and across to within rifle range of the player (riflemen stop to shoot)")
	_check(up_top > 60, "crossing the open ground")
	_check(in_wire == 0, "never through the wire (%d frames inside a belt)" % in_wire)


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
## `only=bd` (with `atmos render`): take only the named gate shots
func _want(letter: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			return letter in a.substr(5)
	return true


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
	# (M3) down in a shell hole, crouched, the rim and their line beyond it
	var best := Vector4.ZERO
	for cr: Vector4 in m.crater_list:
		if cr.z > 3.0 and cr.y > (m.their_row0 + TrenchMaze.GRID_D) * m.cell + 20.0 and cr.y < m.our_row0 * m.cell - 20.0 and (best == Vector4.ZERO or absf(cr.x - m.w * m.cell * 0.5) < absf(best.x - m.w * m.cell * 0.5)):
			best = cr
	if best != Vector4.ZERO:
		var hole := Vector3(best.x, 0, best.y + best.z * 0.3)
		hole.y = m.floor_height(hole) + FpsPlayer.CROUCH_EYE
		cam.global_position = hole
		cam.look_at(Vector3(best.x, hole.y + 0.3, (m.their_row0 + TrenchMaze.GRID_D) * m.cell))
		await _shot("shell_hole")
		hole.y = m.floor_height(hole) + FpsPlayer.STAND_EYE
		cam.global_position = hole
		cam.look_at(Vector3(best.x, hole.y - 0.4, (m.their_row0 + TrenchMaze.GRID_D) * m.cell))
		await _shot("shell_hole_standing")
	# (M3) our wire, from the open ground in front of it, looking along the belt
	var wz: float = m.wire_belts[0].z - 4.0
	var wire_at := Vector3(m.w * m.cell * 0.2, 0, wz)
	wire_at.y = m.floor_height(wire_at) + 1.65
	cam.global_position = wire_at
	var belt_z: float = m.wire_belts[0].z
	cam.look_at(Vector3(m.w * m.cell * 0.8, wire_at.y - 0.8, belt_z - 1.0))
	await _shot("wire")
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


# --- atmos (M4) -------------------------------------------------------------------------------
func _atmos() -> void:
	print("-- atmos")
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	var m := game.maze as FrontMaze
	# the environments are kept apart
	_check(game._world_env.environment == game._front_env and game._front_env != game._trench_env and game._front_env != game._bunker_env, "the Front has its own environment")
	var atm: FrontAtmosphere = get_tree().get_first_node_in_group(&"fog")
	_check(atm != null and atm.visibility(Vector3.ZERO, Vector3(0, 0, 20)) > 0.5 and atm.visibility(Vector3.ZERO, Vector3(0, 0, FrontAtmosphere.SIGHT_M)) < 0.31 and atm.visibility(Vector3.ZERO, Vector3(0, 0, 90)) < 0.16,
		"one visibility model: clear at 20 m (%.2f), the brains' limit at %.0f m (%.2f), all but gone by 90 m (%.2f)" % [atm.visibility(Vector3.ZERO, Vector3(0, 0, 20)) if atm else -1.0, FrontAtmosphere.SIGHT_M, atm.visibility(Vector3.ZERO, Vector3(0, 0, FrontAtmosphere.SIGHT_M)) if atm else -1.0, atm.visibility(Vector3.ZERO, Vector3(0, 0, 90)) if atm else -1.0])
	# the rolling fog: banks already on the field, and a sight line through one is cut
	var ffog: FrontFog = atm.front_fog as FrontFog if atm else null
	var cut := 1.0
	if ffog and not ffog.banks.is_empty():
		var bk: TrenchFog.Bank = ffog.banks[0]
		var from := bk.pos + Vector3(-bk.radius - 2.0, 1.5, 0)
		var to := bk.pos + Vector3(bk.radius + 2.0, 1.5, 0)
		cut = ffog.visibility(from, to)
	# the dead of earlier attacks lie out there, already dead, not enemies
	await _frames(4)
	var fart: FrontArt = game.maze.get_node_or_null("Art") as FrontArt
	var dead_ok := fart != null and fart.bodies.size() >= 10
	if fart:
		for c: Clown in fart.bodies:
			if not is_instance_valid(c) or not c.dead or game.clowns.has(c):
				dead_ok = false
	_check(dead_ok, "the field's dead: %d bodies, all corpses, none counted as enemies (%d enemies)" % [fart.bodies.size() if fart else 0, game.clowns.size()])
	_check(ffog != null and ffog.banks.size() >= 2 and cut < 0.6, "the rolling fog: %d banks on the field at load, a line through the first gets %.2f of the way" % [ffog.banks.size() if ffog else 0, cut])
	game.next_floor()
	await _frames(2)
	_check(not (game.maze is TrenchMaze) and game._world_env.environment == game._bunker_env, "the next floor, a bunker, has the bunker environment back")
	game.survival_trenches = false
	game.floor_number = 5
	game.next_floor()
	await _frames(2)
	_check(game.maze is TrenchMaze and not (game.maze is FrontMaze) and game._world_env.environment == game._trench_env, "the legacy trench keeps TrenchArt's environment")
	game.survival_trenches = true
	if not render:
		return
	await _new_game(1916 if fixed_seed == 0 else fixed_seed)
	m = game.maze as FrontMaze
	game.player.visible = false
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.far = 600.0
	cam.fov = 75.0
	await _frames(40)
	var z_theirs := (m.their_row0 + TrenchMaze.GRID_D) * m.cell
	var mid_x := m.w * m.cell * 0.5
	# (a) our frontline parapet: eye height on a fire step, looking out
	var bay := Vector2i(-1, -1)
	for c: Vector2i in m.bays:
		if m.ours.has(c) and absi(c.x - 16) < 6 and (bay == Vector2i(-1, -1) or absi(c.x - 16) < absi(bay.x - 16)):
			bay = c
	var r := m._rect(bay)
	var on_step := Vector3(r.get_center().x, 0, r.position.y + 0.3)
	on_step.y = m.floor_height(on_step) + 1.65
	cam.global_position = on_step
	cam.look_at(Vector3(on_step.x + 2.0, on_step.y - 0.25, z_theirs))
	print("      (a) parapet camera %s" % on_step.snapped(Vector3.ONE * 0.01))
	if _want("a"):
		await _shot("gate_a_parapet")
	# (t) in the trench: standing on the floor of our fire trench, looking along it
	if _want("t"):
		var in_trench := Vector3(r.get_center().x, 0, r.get_center().y)
		in_trench.y = m.floor_height(in_trench) + 1.65
		cam.global_position = in_trench
		var along := Vector3(in_trench.x + 14.0, in_trench.y - 0.4, in_trench.z + 1.0)
		cam.look_at(along)
		print("      (t) in-trench camera %s" % in_trench.snapped(Vector3.ONE * 0.01))
		await _shot("gate_t_trench")
	# (b) the panorama: from the lip of a shell hole a third of the way across
	var pan := Vector3(mid_x - 4.0, 0, m.our_row0 * m.cell - 26.0)
	pan.y = m.floor_height(pan) + 1.65
	cam.global_position = pan
	cam.look_at(Vector3(mid_x + 6.0, pan.y - 0.9, z_theirs - 10.0))
	print("      (b) panorama camera %s" % pan.snapped(Vector3.ONE * 0.01))
	if _want("b"):
		await _shot("gate_b_panorama")
	# (c) the ground close to: mud, a water-filled hole, the wire, from a crouch
	var hole := Vector4.ZERO
	var wz: float = m.wire_belts[0].z
	for cr: Vector4 in m.crater_list:
		if cr.z > 2.4 and cr.w > 0.6 and cr.y < wz - 4.0 and cr.y > wz - 22.0 and (hole == Vector4.ZERO or absf(cr.x - mid_x) < absf(hole.x - mid_x)):
			hole = cr
	var low := Vector3(hole.x - hole.z * 1.5, 0, hole.y + hole.z * 1.6)
	low.y = m.floor_height(low) + 0.75
	cam.global_position = low
	cam.look_at(Vector3(hole.x + 2.0, low.y - 0.6, wz - 2.0))
	print("      (c) ground camera %s, hole %s" % [low.snapped(Vector3.ONE * 0.01), hole])
	if _want("c"):
		await _shot("gate_c_ground")
	# (d) silhouettes: three soldiers out in the haze at 25, 40 and 60 m
	# the eye is low, a man crouched at a hole's lip, so the figures stand
	# against the sky and not the dark ground band
	var eye := Vector3(mid_x, 0, m.our_row0 * m.cell - 10.0)
	eye.y = m.floor_height(eye) + 1.0
	var men: Array[Clown] = []
	for d: float in [14.0, 26.0, 42.0]:
		var c := Clown.new()
		c.body = "witzsoldat"
		game._world.add_child(c)
		# on open ground, not down a shell hole: slide sideways until the
		# floor is within 0.3 m of the field level
		var at := Vector3(mid_x + (d - 26.0) * 0.3, 0, eye.z - d)
		for k in 12:
			at.y = m.floor_height(at)
			if at.y > -0.3:
				break
			at.x += 1.5 if k % 2 == 0 else -1.5 * (k + 1)
		c.global_position = at
		c.rotation.y = PI + 0.2
		c.give_rifle()
		c.always_pose = true
		c.set_process(true)
		men.append(c)
	await _frames(6)
	cam.global_position = eye
	cam.fov = 60.0
	cam.look_at(Vector3(mid_x, eye.y + 0.2, eye.z - 26.0))
	print("      (d) silhouette camera %s; men at 14, 26, 42 m" % eye.snapped(Vector3.ONE * 0.01))
	if _want("d"):
		await _shot("gate_d_silhouettes")
	# (e) the same men in a thicker bank: sight ~30 m instead of 55
	var env: Environment = game._front_env
	var keep: Array[float] = [env.fog_density, env.fog_depth_end, env.fog_depth_begin]
	env.fog_density = 1.0
	env.fog_depth_begin = 3.0
	env.fog_depth_end = 75.0
	await _frames(6)
	print("      (e) the same, fog end %.0f m" % env.fog_depth_end)
	if _want("e"):
		await _shot("gate_e_silhouettes_dense")
	env.fog_density = keep[0]
	env.fog_depth_end = keep[1]
	env.fog_depth_begin = keep[2]
	for c in men:
		c.queue_free()
