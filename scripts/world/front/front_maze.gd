class_name FrontMaze
extends TrenchMaze
## The Drowned Front (Operation Drowned Front, Milestone 2): two trench
## networks facing each other across No Man's Land, on one carved heightfield.
##
##   rear edge (z = d*cell)   OUR network: rear comm trench, reserve, support,
##                            fire trench facing -z, saps, wire        [rows d-28 .. d-1]
##   NO MAN'S LAND            open, shell-holed ground, nml_rows cells  [rows 28 .. d-29]
##   THEIR network            the same kind of system turned about: fire
##                            trench facing +z (toward us), support, reserve,
##                            their rear comm trench, the H.Q. at its end  [rows 0 .. 27]
##   front edge (z = 0)
##
## The player starts where the legacy trench floor started (the rear end of
## our rear communication trench), goes forward to the fire trench, up an
## assault ramp cut through the parapet, across No Man's Land, down a ramp
## into their fire trench, back through their lines to the H.Q. portal.
##
## Built on TrenchMaze (D-02: the legacy classes are not edited). Each
## network is laid out by TrenchMaze's own layout code in a scratch instance
## and copied into this grid (theirs turned 180 degrees). Everything that
## assumes "the front is toward -z" is overridden here with a per-cell
## `facing` (-1 ours, +1 theirs): the fire step's side of a bay (_rect,
## _floor_at, _ease_fire_steps, _widen_want), the parapet and parados
## (_carve, a copy of the legacy carve with that one change), the shell holes
## (_craters), the exit (exit_transform), and the dressing (FrontArt).

## Cells of No Man's Land between the two networks' blocks (1.5 m each).
## 52 rows = 78 m of open ground between the blocks; the fire trenches are 65
## cells (97 m) apart; the wire belts about 85 m. A prototype figure (D-12).
var nml_rows := 52
## -1: this cell's front is toward -z (our network); +1: toward +z (theirs).
var facing := {}
## Open cells of each network.
var ours := {}
var theirs := {}
## Rows the blocks start at.
var our_row0 := 0
var their_row0 := 0
## The assault ramps: {cell, dir, width, assault = true}, also in `ramps`.
var assault_ramps: Array = []
## Milliseconds the last generate() took, by stage (tests, the tracker).
var timing := {}
## The wire (Milestone 3): belts the player cannot walk through (collision
## for him only, so sight and rounds pass) and the brains path round (their
## cells are taken out of the top layer). A belt in front of each line, with
## gaps where the saps go out and the assault ramps come up; and a few short
## broken belts out in No Man's Land that shape the way across.
##   {z: the picket row nearest its trench, f: which way "out" is (+1/-1),
##    x0, x1: its run, rows: picket rows (2 for a front belt, 1 for a short
##    one), coil: bool, gaps: Array[float] (x of each gap)}
var wire_belts: Array = []
const WIRE_GAP := 2.4            ## half-width of a gap in a belt (m)
const WIRE_ROW := 1.6            ## between picket rows (m)
const WIRE_COIL := 1.4           ## the coils this far beyond the last row (m)
## Top cells taken out for the wire (tests).
var wire_cells := {}


func generate(_width: int, _depth: int, seed_value: int) -> void:
	w = GRID_W
	d = GRID_D * 2 + nml_rows
	their_row0 = 0
	our_row0 = GRID_D + nml_rows
	rng.seed = seed_value
	var t0 := Time.get_ticks_msec()
	var ok := false
	for attempt in 40:
		_reset()
		facing.clear()
		ours.clear()
		theirs.clear()
		assault_ramps.clear()
		if _layout_front() and _finish_front():
			ok = true
			break
	timing.total = Time.get_ticks_msec() - t0
	if not ok:
		push_error("FrontMaze: no layout with a route from start to exit in 40 attempts (seed %d)" % seed_value)


## Which way a cell's front is (where its parapet, fire step and No Man's Land
## are): -1 (toward -z) for our network, +1 for theirs; 0 for a top cell.
func facing_of(c: Vector2i) -> int:
	return facing.get(c, 0)


# --- layout ----------------------------------------------------------------------------
## One network's layout, by TrenchMaze's own code, in a scratch instance.
func _scratch_layout(seed_: int) -> TrenchMaze:
	var m := TrenchMaze.new()
	m.w = GRID_W
	m.d = GRID_D
	m.rng.seed = seed_
	for attempt in 40:
		m._reset()
		if m._layout():
			return m
	m.free()
	return null


## Our cell `c` (local to the network's block) in this grid.
func _our(c: Vector2i) -> Vector2i:
	return Vector2i(c.x, c.y + our_row0)


## Their cell `c` in this grid: the block turned 180 degrees (so their fire
## trench faces us and their rear is at the front edge).
func _their(c: Vector2i) -> Vector2i:
	return Vector2i(w - 1 - c.x, GRID_D - 1 - c.y + their_row0)


func _layout_front() -> bool:
	var a := _scratch_layout(rng.randi())
	if a == null:
		return false
	var b := _scratch_layout(rng.randi())
	if b == null:
		a.free()
		return false
	_merge(a, func(c: Vector2i) -> Vector2i: return _our(c), func(v: Vector2i) -> Vector2i: return v, -1, "a", ours)
	_merge(b, func(c: Vector2i) -> Vector2i: return _their(c), func(v: Vector2i) -> Vector2i: return -v, 1, "b", theirs)
	# the way in: the rear end of our rear communication trench, as it was
	start_cell = _our(a.start_cell)
	# the way out: the H.Q., at the rear end of THEIR rear communication trench
	# (through their fire trench and back through their lines to get there)
	exit_cell = _their(b.start_cell)
	landmarks.append({kind = "start", cell = start_cell})
	landmarks.append({kind = "exit", cell = exit_cell, dir = Vector2i(0, -1)})
	a.free()
	b.free()
	# links: every pair of open neighbours (within a network they are one
	# trench or a junction of two; the networks never touch)
	for c: Vector2i in open_cells:
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if open_cells.has(c + dir):
				links[_key(c, c + dir)] = true
	# an assault ramp must be possible on each side, or it is no crossing
	return not _assault_candidates(-1).is_empty() and not _assault_candidates(1).is_empty()


## Copy one scratch network into this grid through `map` (cells) and `dmap`
## (directions), facing `f`, its trench names suffixed `tag`.
func _merge(m: TrenchMaze, map: Callable, dmap: Callable, f: int, tag: String, into: Dictionary) -> void:
	for c: Vector2i in m.open_cells:
		var g: Vector2i = map.call(c)
		open_cells[g] = true
		kind[g] = m.kind[c]
		facing[g] = f
		into[g] = true
		if m.bays.has(c):
			bays[g] = true
		if m.flooded.has(c):
			flooded[g] = true
		if m.collapsed.has(c):
			collapsed[g] = true
		if m.side_cells.has(c):
			side_cells[g] = true
	for name_: String in m.trenches:
		var cells: Array = []
		for c: Vector2i in m.trenches[name_]:
			cells.append(map.call(c))
		trenches[name_ + "_" + tag] = cells
	for l: Dictionary in m.landmarks:
		if l.kind in ["start", "exit"]:
			continue
		var g := l.duplicate()
		g.cell = map.call(l.cell)
		if l.has("entrance"):
			g.entrance = map.call(l.entrance)
		if l.has("dir"):
			g.dir = dmap.call(l.dir)
		landmarks.append(g)


## Fire bays an assault ramp could leave from, on the side facing `f`: a bay
## (not a sap's mouth, not under a bridge), the ground ahead clear of trench
## for four cells and a cell either side, in bounds.
func _assault_candidates(f: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := Vector2i(0, f)
	for c: Vector2i in bays:
		if facing.get(c, 0) != f or kind.get(c, "") != "fire":
			continue
		if open_cells.has(c + dir):
			continue
		var ok := true
		for i in range(1, 5):
			for j: int in [-1, 0, 1]:
				var m := c + dir * i + Vector2i(j, 0)
				if not in_bounds(m) or open_cells.has(m):
					ok = false
		# a plain stretch of bay either side (the ramp is wider than a cell)
		if not (bays.has(c + Vector2i(1, 0)) and bays.has(c + Vector2i(-1, 0))):
			ok = false
		if ok:
			out.append(c)
	return out


## Ramps up through the parapet into No Man's Land ("over the top"): up to
## three a side, spread along the fire trench. Picked after the ordinary ramps
## and before the carve, which cuts them like any other.
func _assault_ramps() -> void:
	assault_ramps.clear()
	for f in [-1, 1]:
		var cands := _assault_candidates(f)
		cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x < q.x)
		var picked: Array[Vector2i] = []
		for frac: float in [0.5, 0.15, 0.85]:
			var want := int(frac * (cands.size() - 1))
			var best := Vector2i(-1, -1)
			var bd := 999
			for c: Vector2i in cands:
				if picked.any(func(p: Vector2i) -> bool: return absi(p.x - c.x) < 7):
					continue
				if ramps.any(func(r: Dictionary) -> bool: return Vector2(r.cell).distance_to(Vector2(c)) < 4.0):
					continue
				var dd := absi(cands.find(c) - want)
				if dd < bd:
					bd = dd
					best = c
			if best != Vector2i(-1, -1):
				picked.append(best)
		for c: Vector2i in picked:
			var r := {cell = c, dir = Vector2i(0, f), width = RAMP_W + 0.4, assault = true}
			ramps.append(r)
			assault_ramps.append(r)
			bays.erase(c)                        # the ramp leaves from the floor: no fire step here


## The belts: see wire_belts. A front belt runs the whole width (the flanks
## too: the way past the end of a fire trench is through the wire or not at
## all), gaps at every sap's observation post and every assault ramp. Out in
## the middle, three to five short belts of a single row and a coil, 8-18 m
## long, at least 6 m apart, none within 6 m of a gap's line.
func _plan_wire() -> void:
	wire_belts.clear()
	for f in [-1, 1]:
		var gaps: Array[float] = []
		for l: Dictionary in landmarks:
			if l.kind == "op" and facing.get(l.cell, 0) == f:
				gaps.append((l.cell.x + 0.5) * cell)
		for r: Dictionary in assault_ramps:
			if r.dir.y == f:
				gaps.append((r.cell.x + 0.5) * cell)
		var z0 := our_row0 * cell if f == -1 else (their_row0 + GRID_D) * cell
		wire_belts.append({z = z0 - f * 0.4, f = f, x0 = -MARGIN - 1.0, x1 = w * cell + MARGIN + 1.0, rows = 2, coil = true, gaps = gaps})
	var z_near := (their_row0 + GRID_D) * cell + 12.0
	var z_far := our_row0 * cell - 12.0
	var want := rng.randi_range(3, 5)
	var tries := 0
	var mids: Array = []
	while mids.size() < want and tries < 60:
		tries += 1
		var length := rng.randf_range(8.0, 18.0)
		var x0 := rng.randf_range(-4.0, w * cell + 4.0 - length)
		var z := rng.randf_range(z_near, z_far)
		var f := -1 if rng.randf() < 0.5 else 1
		var ok := true
		for b: Dictionary in mids:
			# apart from one another: not within 6 m in z while overlapping in x
			if absf(b.z - z) < 6.0 and x0 < b.x1 + 6.0 and x0 + length > b.x0 - 6.0:
				ok = false
		if ok:
			var belt := {z = z, f = f, x0 = x0, x1 = x0 + length, rows = 1, coil = true, gaps = [] as Array[float]}
			mids.append(belt)
	wire_belts.append_array(mids)


## The band a belt covers, from the picket row nearest its trench out to the coil.
func belt_band(b: Dictionary) -> Vector2:
	var depth_: float = WIRE_ROW * (int(b.rows) - 1) + (WIRE_COIL if b.coil else 0.0)
	var za: float = b.z
	var zb: float = b.z + b.f * depth_
	return Vector2(minf(za, zb) - 0.35, maxf(za, zb) + 0.35)


## Is (x, z) in the wire (a belt's band, not in one of its gaps)?
func wire_at(x: float, z: float) -> bool:
	for b: Dictionary in wire_belts:
		if x < b.x0 or x > b.x1:
			continue
		var band := belt_band(b)
		if z < band.x or z > band.y:
			continue
		var in_gap := false
		for gx: float in b.gaps:
			if absf(x - gx) < WIRE_GAP:
				in_gap = true
		if not in_gap:
			return true
	return false


## The top layer, less the cells under the wire (their links and pathfinding
## points go too), so the brains cross at the gaps like the player.
func _top_layer() -> void:
	super._top_layer()
	wire_cells.clear()
	if wire_belts.is_empty():
		return
	var keep := {}
	for r: Dictionary in ramps:
		keep[r.top] = true
	for b: Dictionary in bridges:
		keep[b.ends[0]] = true
		keep[b.ends[1]] = true
	for c: Vector2i in top_cells.keys():
		if keep.has(c):
			continue
		var cx := (c.x + 0.5) * cell
		var cz := (c.y + 0.5) * cell
		var blocked := false
		for off: Vector2 in [Vector2(0, 0), Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
			if wire_at(cx + off.x * cell * 0.9, cz + off.y * cell * 0.9):
				blocked = true
		if blocked:
			wire_cells[c] = true
	for c: Vector2i in wire_cells:
		top_cells.erase(c)
		if _astar.has_point(idx(c)):
			_astar.remove_point(idx(c))
		for dir in DIRS:
			links.erase(_key(c, c + dir))


func _finish_front() -> bool:
	var t0 := Time.get_ticks_msec()
	_astar.clear()
	for c: Vector2i in open_cells:
		_astar.add_point(idx(c), Vector2(c.x, c.y))
	for k: String in links:
		var parts := k.split("|")
		_astar.connect_points(int(parts[0]), int(parts[1]))
	_passing_places()
	_pick_ramps()
	_assault_ramps()
	_pick_bridges()
	_plan_wire()
	_depths()
	timing.layout = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_carve()
	timing.carve = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_top_layer()
	# the main route, start to the H.Q.: along our trenches, up a ramp, over
	# the top, down into theirs (only now that the top is in the graph)
	var ids := _astar.get_id_path(idx(start_cell), idx(exit_cell))
	route.clear()
	for id in ids:
		route.append(Vector2i(id % w, id / w))
	timing.top = Time.get_ticks_msec() - t0
	if route.size() < 10:
		return false
	level = PackedInt32Array()
	level.resize(w * d)
	stairs.clear()
	t0 = Time.get_ticks_msec()
	_build_trench_world()
	timing.world = Time.get_ticks_msec() - t0
	return true


## The world: the legacy collision (one heightfield, the edge wall) and the
## front's own dressing (FrontArt, which is TrenchArt turned to face both ways).
func _build_trench_world() -> void:
	for c in get_children():
		c.queue_free()
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = hx
	shape.map_depth = hz
	shape.map_data = col_h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(origin.x + (hx - 1) * RES * 0.5, 0.0, origin.y + (hz - 1) * RES * 0.5)
	cs.scale = Vector3(RES, 1.0, RES)
	body.add_child(cs)
	var edge := StaticBody3D.new()
	edge.name = "Edge"
	edge.collision_layer = LAYER_RAMP
	edge.collision_mask = 0
	add_child(edge)
	var lo := Vector3(origin.x, 0, origin.y)
	var hi := Vector3(origin.x + (hx - 1) * RES, 0, origin.y + (hz - 1) * RES)
	for side: Array in [[Vector3(lo.x, 0, (lo.z + hi.z) * 0.5), Vector3(0.4, 12, hi.z - lo.z)], [Vector3(hi.x, 0, (lo.z + hi.z) * 0.5), Vector3(0.4, 12, hi.z - lo.z)],
			[Vector3((lo.x + hi.x) * 0.5, 0, lo.z), Vector3(hi.x - lo.x, 12, 0.4)], [Vector3((lo.x + hi.x) * 0.5, 0, hi.z), Vector3(hi.x - lo.x, 12, 0.4)]]:
		var bx := BoxShape3D.new()
		bx.size = side[1]
		var wall_cs := CollisionShape3D.new()
		wall_cs.shape = bx
		wall_cs.position = side[0]
		edge.add_child(wall_cs)
	var art := FrontArt.new()
	art.name = "Art"
	add_child(art)
	art.build(self)


# --- the front of a cell: what TrenchMaze assumes is -z ------------------------------
## The floor of an open cell (fire bays: out over the fire step, on the front).
func _rect(c: Vector2i) -> Rect2:
	var x0 := c.x * cell
	var z0 := c.y * cell
	var x1 := x0 + cell
	var z1 := z0 + cell
	var f: int = facing.get(c, -1)
	if not open_cells.has(c + Vector2i(-1, 0)):
		x0 += EDGE - widen_of(c, Vector2i(-1, 0))
	if not open_cells.has(c + Vector2i(1, 0)):
		x1 -= EDGE - widen_of(c, Vector2i(1, 0))
	if not open_cells.has(c + Vector2i(0, -1)):
		z0 += EDGE - widen_of(c, Vector2i(0, -1))
		if bays.has(c) and f == -1:
			z0 -= FIRE_STEP_D
	if not open_cells.has(c + Vector2i(0, 1)):
		z1 -= EDGE - widen_of(c, Vector2i(0, 1))
		if bays.has(c) and f == 1:
			z1 += FIRE_STEP_D
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## Fire bays widen to the rear (the fire step is in front).
func _widen_want(c: Vector2i, dir: Vector2i) -> float:
	if kind.get(c, "") == "fire":
		if not open_cells.has(c) or open_cells.has(c + dir):
			return 0.0
		return WIDEN.fire if dir == Vector2i(0, -facing.get(c, -1)) else 0.0
	return super._widen_want(c, dir)


## Where a bay's fire step is: on the front edge of the floor.
func _on_step(c: Vector2i, z: float) -> bool:
	if facing.get(c, -1) == 1:
		return z > (c.y + 1) * cell - EDGE
	return z < c.y * cell + EDGE


func _floor_at(x: float, z: float, c: Vector2i, sd: float, slump: FastNoiseLite, fine: FastNoiseLite) -> float:
	var sum := 0.0
	var wsum := 0.0
	var fx := x / cell - 0.5
	var fz := z / cell - 0.5
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dz)
			if not depth.has(n):
				continue
			var dd := Vector2(fx - n.x, fz - n.y).length_squared()
			var wgt := 1.0 / (dd + 0.25)
			sum += depth[n] * wgt
			wsum += wgt
	var f := sum / maxf(wsum, 0.001)
	f += fine.get_noise_2d(x * 1.7, z * 1.7) * 0.035
	f += clampf(slump.get_noise_2d(x, z), -1.0, -0.3) * 0.12 + 0.036
	f += 0.13 * (1.0 - smoothstep(-0.38, 0.0, sd))
	if collapsed.has(c):
		var side := 1.0 if (c.x + c.y) % 2 == 0 else -1.0
		var across := (x - (c.x + 0.5) * cell) * side if links.has(_key(c, c + Vector2i(0, 1))) or links.has(_key(c, c + Vector2i(0, -1))) else (z - (c.y + 0.5) * cell) * side
		f += 0.55 * smoothstep(-0.2, 0.75, across)
	if bays.has(c) and _on_step(c, z):
		f += FIRE_STEP_H
	return f


## The slope up onto each fire step, from the trench side (whichever that is).
func _ease_fire_steps() -> void:
	for c: Vector2i in bays:
		var f: int = facing.get(c, -1)
		var ze := (c.y * cell + EDGE) if f == -1 else ((c.y + 1) * cell - EDGE)
		var z_lo := ze if f == -1 else ze - STEP_RAMP - 0.05
		var z_hi := ze + STEP_RAMP + 0.05 if f == -1 else ze
		for iz in range(int((z_lo - origin.y) / RES) - 1, int((z_hi - origin.y) / RES) + 2):
			for ix in range(int((c.x * cell - origin.x) / RES), int(((c.x + 1) * cell - origin.x) / RES) + 1):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var i := ix + iz * hx
				if sdf[i] > -0.05:
					continue
				var z := origin.y + iz * RES
				var x := origin.x + ix * RES
				var top := _sample(vis_h, x, ze + 0.3 * f)        # out on the step
				var t := clampf(((z - ze) if f == -1 else (ze - z)) / STEP_RAMP, 0.0, 1.0)
				var ff := 1.0
				if not bays.has(c + Vector2i(-1, 0)):
					ff = minf(ff, clampf((x - c.x * cell) / 0.75, 0.0, 1.0))
				if not bays.has(c + Vector2i(1, 0)):
					ff = minf(ff, clampf(((c.x + 1) * cell - x) / 0.75, 0.0, 1.0))
				var want := top - t * FIRE_STEP_H - 0.02
				col_h[i] = maxf(col_h[i], lerpf(col_h[i], want, ff))


## Shell holes: many across No Man's Land, thickest in the middle, a few
## behind each line. Each Vector4(x, z, radius, depth).
func _craters() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var z_near := (their_row0 + GRID_D) * cell          # the front of their block
	var z_far := our_row0 * cell                         # the front of ours
	for i in 190:
		var x := rng.randf_range(-MARGIN * 0.5, w * cell + MARGIN * 0.5)
		var z: float
		var r: float
		var depth_: float
		if i < 150:
			# No Man's Land: holes a man can get down into: 2.2-4.5 m across the
			# rim, 0.9-1.7 m deep (chest-deep and more; the raised rim adds to
			# it), the walls no steeper than he can walk
			z = rng.randf_range(z_near - 2.0, z_far + 2.0)
			r = rng.randf_range(2.2, 4.5) if rng.randf() < 0.7 else rng.randf_range(1.2, 2.2)
			depth_ = clampf(0.42 * r, 0.9, 1.7) if r >= 2.2 else rng.randf_range(0.3, 0.6)
		else:
			# a few behind each line, the old small kind
			z = rng.randf_range(z_far, d * cell + MARGIN) if i < 170 else rng.randf_range(-MARGIN, z_near)
			r = rng.randf_range(1.2, 3.0)
			depth_ = rng.randf_range(0.35, 1.0) * r / 2.4
		var near := _nearest(x, z)
		if near.d < r + 1.2:
			continue
		# holes may run into one another a little (linked holes), never sit inside each other
		if out.any(func(o: Vector4) -> bool: return Vector2(o.x, o.y).distance_to(Vector2(x, z)) < (o.z + r) * 0.6):
			continue
		out.append(Vector4(x, z, r, depth_))
	return out


## The H.Q. portal: in the end wall of their rear communication trench, at
## the front edge of the world.
func exit_transform() -> Transform3D:
	var dir := Vector2i(0, -1)
	for l: Dictionary in landmarks:
		if l.kind == "exit":
			dir = l.dir
	var r := _rect(exit_cell)
	var inward := Vector3(-dir.x, 0, -dir.y)
	var half := r.size.x * 0.5 if dir.x != 0 else r.size.y * 0.5
	var p := Vector3(r.get_center().x, 0, r.get_center().y) + Vector3(dir.x, 0, dir.y) * (half - 0.3)
	p.y = floor_height(p)
	return Transform3D(Basis.looking_at(-inward, Vector3.UP), p)


## Where the floor's enemies may be put: trench cells (never the open ground),
## at least `min_steps` from `c`; their network listed twice, so two in three
## stand in the enemy lines and the rest in ours.
func cells_far_from(c: Vector2i, min_steps: int) -> Array[Vector2i]:
	# steps along the pathfinding graph (trench links, ramps, bridges, the top)
	var dist := {c: 0}
	var q: Array[Vector2i] = [c]
	var head := 0
	while head < q.size():
		var p := q[head]
		head += 1
		for id in _astar.get_point_connections(idx(p)):
			var n := Vector2i(id % w, id / w)
			if not dist.has(n):
				dist[n] = dist[p] + 1
				q.append(n)
	var out: Array[Vector2i] = []
	for n: Vector2i in open_cells:
		if dist.has(n) and dist[n] > min_steps:
			out.append(n)
			if theirs.has(n):
				out.append(n)
	return out


# --- the carve: TrenchMaze._carve with the parapet on each cell's own front --------------
func _carve() -> void:
	_walls()
	origin = Vector2(-MARGIN, -MARGIN)
	hx = int((w * cell + MARGIN * 2.0) / RES) + 1
	hz = int((d * cell + MARGIN * 2.0) / RES) + 1
	var n := hx * hz
	vis_h.resize(n)
	sdf.resize(n)
	wet.resize(n)
	_near_cache.clear()
	var craters := _craters()
	_build_near_cache()
	var holes := PackedFloat32Array()
	holes.resize(n)
	var lips := PackedFloat32Array()
	lips.resize(n)
	# (the Front's shell hole: a cosine bowl, so the wall is never steeper
	# than about 33 degrees however deep the hole, and a low wide lip; where
	# holes run into one another the deeper bowl wins rather than the two
	# adding up into a wall. The legacy's parabola with its sharp lip, summed,
	# stood a man in a 1.5 m hole at the foot of a 50-degree wall.)
	for cr: Vector4 in craters:
		var reach := cr.z * 1.6
		for iz in range(maxi(int((cr.y - reach - origin.y) / RES), 0), mini(int((cr.y + reach - origin.y) / RES) + 2, hz)):
			for ix in range(maxi(int((cr.x - reach - origin.x) / RES), 0), mini(int((cr.x + reach - origin.x) / RES) + 2, hx)):
				var dd := Vector2(origin.x + ix * RES - cr.x, origin.y + iz * RES - cr.y).length() / cr.z
				if dd < 1.6:
					var i := ix + iz * hx
					holes[i] = minf(holes[i], -cr.w * 0.5 * (1.0 + cos(PI * minf(dd, 1.0))))
					lips[i] = maxf(lips[i], cr.w * 0.12 * exp(-pow((dd - 1.2) * 2.0, 2.0)))
	for i in n:
		holes[i] += lips[i]
	crater_list = craters
	var ground := FastNoiseLite.new()
	ground.seed = rng.randi()
	ground.frequency = 0.045
	ground.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = rng.randi()
	fine.frequency = 0.9
	fine.fractal_octaves = 2
	var wobble := FastNoiseLite.new()
	wobble.seed = rng.randi()
	wobble.frequency = 1.6
	var slump := FastNoiseLite.new()
	slump.seed = rng.randi()
	slump.frequency = 0.5
	for c: Vector2i in open_cells:
		depth[c] += ground.get_noise_2d((c.x + 0.5) * cell, (c.y + 0.5) * cell) * 0.35
	for iz in hz:
		for ix in hx:
			var x := origin.x + ix * RES
			var z := origin.y + iz * RES
			var i := ix + iz * hx
			var g := ground.get_noise_2d(x, z) * 0.35 + fine.get_noise_2d(x, z) * 0.04 + holes[i]
			var near := _nearest(x, z)
			var sd: float = near.d
			var h := g
			var wetness := 0.5 + clampf(-g * 0.7, 0.0, 0.35)      # (M4: soaked, water in the low places)
			if sd < 3.0:
				var c: Vector2i = near.cell
				var wt: String = near.wall
				var ww: float = WALL_W.get(wt, 0.4)
				sd += wobble.get_noise_2d(x, z) * (0.025 if ww < 0.2 else 0.09)
				if ww >= 0.3:
					sd += slump.get_noise_2d(x * 1.3, z * 1.3) * 0.12
				var fl := _floor_at(x, z, c, sd, slump, fine)
				# parapet on the cell's own front, parados behind it
				var k: String = kind[c]
				var f: int = facing.get(c, -1)
				var front := (z < c.y * cell + 0.2) if f == -1 else (z > (c.y + 1) * cell - 0.2)
				if sd > 0.0 and k in ["fire", "traverse", "sap", "op"] and front:
					g += 0.22 * _mound(sd, 0.1, 1.9)
				elif sd > 0.0 and k in ["fire", "traverse", "support", "junction"] and not front:
					g += 0.28 * _mound(sd, 0.1, 1.4)
				if sd <= 0.0:
					h = fl
					wetness = 0.8 + clampf(-(fl - depth.get(c, fl)) * 2.0, 0.0, 0.2)
				else:
					var t := clampf(sd / ww, 0.0, 1.0)
					var prof := 1.0 - pow(1.0 - t, 1.6) if ww < 0.3 else pow(t, 0.75)
					h = lerpf(fl, g, prof)
					if ww >= 0.3:
						h += fine.get_noise_2d(x * 0.6, z * 0.6) * 0.25 * t * (1.0 - t) * 4.0
					wetness = lerpf(0.75, 0.45, t)
			vis_h[i] = h
			sdf[i] = sd
			wet[i] = clampf(wetness, 0.0, 1.0)
	_cut_ramps()
	_fill_troughs()
	_ease_digs()
	col_h = vis_h.duplicate()
	_bake_sky()
	_ease_fire_steps()
	_lay_duckboards()
	_lay_water()
	_bake_puddles()
