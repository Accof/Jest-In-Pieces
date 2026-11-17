class_name Maze
extends Node3D
## A procedurally generated funhouse: a grid maze of tight corridors on several
## height levels, joined by real staircases that bodies can tumble down.

const CELL := 3.0            ## metres per grid cell (corridor width, wall to wall)
## This maze's cell size: CELL for the bunker floors, smaller for the trench
## floor (TrenchMaze). Every query goes through this.
var cell := CELL
const LEVEL := 1.2           ## height of one level
const MAX_LEVEL := 3
const WALL_T := 0.3
const HEADROOM := 3.0
const STAIR_RUN := 1.5       ## how far a staircase reaches into the lower cell
const STAIR_WIDTH := 1.5
const STEPS := 6
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const LAYER_WORLD := 1
const LAYER_RAMP := 1 << 4   ## smooth ramps over the stairs, for the player only

## "bunker": one winding route from a short trench down into concrete bunkers
##   (the default);
## "trench": the whole grid as a maze, trench above and circus bunker below;
## "funhouse": the original look.
var theme := "bunker"
## Bunker theme: the main route from start to exit, in order.
var route: Array[Vector2i] = []
## Bunker theme: cells that are part of the level (the rest is solid earth).
var open_cells := {}
## Bunker theme: the open-air trench cells at the start of the route.
var trench_cells := {}
## Bunker theme: dead-end side rooms off the route.
var side_cells := {}
## Cells at or above this height level are open-sky trench; below it, roofed bunker.
var trench_level := 2
## How deep the trenches are below the ground surface, at their highest.
const TRENCH_DEPTH := 2.9
## Bunker ceiling height above the highest floor it has to clear.
const BUNKER_HEADROOM := 2.6

var w := 6
var d := 6
var rooms: Array = []                   ## each an Array of 4 cells
var level: PackedInt32Array            ## height level of each cell
var links := {}                         ## "a|b" -> true for every open edge
var start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var stairs: Array = []                  ## {low, high, dir}
var rng := RandomNumberGenerator.new()

var _astar := AStar2D.new()
var _stair_at := {}                     ## low cell id -> Array of stairs


func idx(c: Vector2i) -> int:
	return c.x + c.y * w


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < d


func _key(a: Vector2i, b: Vector2i) -> String:
	var ia := idx(a)
	var ib := idx(b)
	return "%d|%d" % [mini(ia, ib), maxi(ia, ib)]


func linked(a: Vector2i, b: Vector2i) -> bool:
	return links.has(_key(a, b))


# --- generation ---------------------------------------------------------------
func generate(width: int, depth: int, seed_value: int) -> void:
	w = width
	d = depth
	rng.seed = seed_value
	links.clear()
	stairs.clear()
	level = PackedInt32Array()
	level.resize(w * d)
	route.clear()
	open_cells.clear()
	trench_cells.clear()
	side_cells.clear()
	rooms = []
	if theme == "bunker":
		_generate_linear()
		_finish()
		return

	# 1. A perfect maze by depth-first carving, with heights drifting as it goes.
	var seen := {}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	seen[Vector2i.ZERO] = true
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir in DIRS:
			var n := c + dir
			if in_bounds(n) and not seen.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = options[rng.randi() % options.size()]
		seen[n] = true
		links[_key(c, n)] = true
		var step: int = [0, 0, 0, 1, 1, -1][rng.randi() % 6]
		level[idx(n)] = clampi(level[idx(c)] + step, 0, MAX_LEVEL)
		stack.append(n)

	# 2. Knock through some extra walls so there are loops to be flanked through.
	var extra := int(w * d * 0.14)
	for i in extra * 6:
		if extra <= 0:
			break
		var c := Vector2i(rng.randi() % w, rng.randi() % d)
		var n := c + DIRS[rng.randi() % 4]
		if in_bounds(n) and not linked(c, n) and absi(level[idx(c)] - level[idx(n)]) <= 1:
			links[_key(c, n)] = true
			extra -= 1

	# 3. A few open 2x2 rooms on one level.
	rooms = []
	for i in maxi(1, (w * d) / 18):
		var c := Vector2i(rng.randi_range(0, w - 2), rng.randi_range(0, d - 2))
		var cells: Array[Vector2i] = [c, c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(1, 1)]
		rooms.append(cells)
		links[_key(cells[0], cells[1])] = true
		links[_key(cells[0], cells[2])] = true
		links[_key(cells[1], cells[3])] = true
		links[_key(cells[2], cells[3])] = true

	# 4. Settle the heights, then place a staircase on every open edge that
	#    changes level. A cell only ever has ONE staircase leading up out of it:
	#    two in one cell meet in the middle and leave nowhere to stand. Where a
	#    cell would get a second, that edge is walled off, or, if that would cut
	#    part of the maze off, the far side is brought down to the same level.
	#    Lowering a cell can disturb its neighbours, so repeat until it all holds.
	var settled := false
	while not settled:
		settled = true
		var changed := true
		while changed:
			changed = false
			for cells: Array in rooms:
				var low := MAX_LEVEL
				for c: Vector2i in cells:
					low = mini(low, level[idx(c)])
				for c: Vector2i in cells:
					if level[idx(c)] != low:
						level[idx(c)] = low
						changed = true
			for z in d:
				for x in w:
					var c := Vector2i(x, z)
					for dir in DIRS:
						var n := c + dir
						if in_bounds(n) and linked(c, n) and level[idx(n)] > level[idx(c)] + 1:
							level[idx(n)] = level[idx(c)] + 1
							changed = true
		stairs.clear()
		for z in d:
			if not settled:
				break
			for x in w:
				var c := Vector2i(x, z)
				var has_stair := false
				for dir in DIRS:
					var n := c + dir
					if not in_bounds(n) or not linked(c, n) or level[idx(n)] != level[idx(c)] + 1:
						continue
					if not has_stair:
						has_stair = true
						stairs.append({low = c, high = n, dir = dir})
						continue
					links.erase(_key(c, n))
					if not _all_reachable():
						links[_key(c, n)] = true
						level[idx(n)] = level[idx(c)]
						settled = false
						break
				if not settled:
					break

	# 6. Split the floor into trench above and bunker below, as near half and
	#    half as the heights allow. Every link between the zones changes level,
	#    so every entrance from trench to bunker is a staircase.
	var best := 99.0
	for t in range(1, MAX_LEVEL + 1):
		var n := 0
		for i in level.size():
			if level[i] >= t:
				n += 1
		var frac := float(n) / level.size()
		var score := absf(frac - 0.5) + (1.0 if n == 0 or n == level.size() else 0.0)
		if score < best:
			best = score
			trench_level = t

	# 7. Pathfinding graph, start and the farthest cell as the exit.
	_finish()


func _finish() -> void:
	_astar.clear()
	for z in d:
		for x in w:
			_astar.add_point(idx(Vector2i(x, z)), Vector2(x, z))
	for k: String in links:
		var parts := k.split("|")
		_astar.connect_points(int(parts[0]), int(parts[1]))
	_stair_at.clear()
	for s: Dictionary in stairs:
		var id := idx(s.low)
		if not _stair_at.has(id):
			_stair_at[id] = []
		_stair_at[id].append(s)
	if theme == "bunker":
		start_cell = route[0]
		exit_cell = route[route.size() - 1]
	else:
		start_cell = Vector2i(rng.randi() % w, rng.randi() % d)
		var far := 0
		exit_cell = start_cell
		for z in d:
			for x in w:
				var steps := _astar.get_id_path(idx(start_cell), idx(Vector2i(x, z))).size()
				if steps > far:
					far = steps
					exit_cell = Vector2i(x, z)
	_build()


# --- the linear bunker layout --------------------------------------------------
## One winding route of straight corridors from a trench at the top down into the
## bunker, with a few stairwells along it, a couple of wide halls and some dead-end
## side rooms. Everything off the route is solid ground.
func _generate_linear() -> void:
	var target := int(w * d * 0.42)
	for attempt in 300:
		var r := _walk_route(target)
		if r.size() > route.size():
			route = r
		if route.size() >= target:
			break
	for c in route:
		open_cells[c] = true
	for i in range(1, route.size()):
		links[_key(route[i - 1], route[i])] = true
	var trench_len := mini(3, route.size() / 4)
	for i in trench_len:
		trench_cells[route[i]] = true

	# stairwells: only down, only on straight runs, spread along the route
	var n_stairs := clampi(1 + route.size() / 12, 1, MAX_LEVEL)
	var lows := {}
	for k in n_stairs:
		var want := int(lerpf(trench_len + 2, route.size() - 3, (k + 0.5) / n_stairs))
		for off in [0, 1, -1, 2, -2, 3, -3]:
			var i: int = want + off
			if i < trench_len + 1 or i > route.size() - 2 or lows.has(i) or lows.has(i - 1) or lows.has(i + 1):
				continue
			if route[i] - route[i - 1] != route[i + 1] - route[i]:
				continue
			lows[i] = true
			break
	var lv := lows.size()
	for i in route.size():
		if lows.has(i):
			lv -= 1
			stairs.append({low = route[i], high = route[i - 1], dir = route[i - 1] - route[i]})
		level[idx(route[i])] = lv

	# wide halls: a corridor pair widened sideways into a 2x2 room
	var halls := 1 + route.size() / 16
	var tries := 0
	while halls > 0 and tries < 200:
		tries += 1
		var i := rng.randi_range(trench_len + 1, route.size() - 3)
		var c := route[i]
		var n := route[i + 1]
		if lows.has(i) or lows.has(i + 1) or _in_room(c) or _in_room(n):
			continue
		var dir := n - c
		var side := Vector2i(dir.y, dir.x) * (1 if rng.randf() < 0.5 else -1)
		var a := c + side
		var b := n + side
		if not in_bounds(a) or not in_bounds(b) or open_cells.has(a) or open_cells.has(b):
			continue
		for x in [a, b]:
			open_cells[x] = true
			level[idx(x)] = level[idx(c)]
		links[_key(c, a)] = true
		links[_key(n, b)] = true
		links[_key(a, b)] = true
		var cells: Array = [c, n, a, b]
		cells.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x + p.y * 1000 < q.x + q.y * 1000)
		rooms.append(cells)
		halls -= 1

	# dead-end side rooms (stores, latrines, somewhere to hide)
	var sides := route.size() / 5
	tries = 0
	while sides > 0 and tries < 300:
		tries += 1
		var i := rng.randi_range(trench_len, route.size() - 2)
		var c := route[i]
		if lows.has(i):
			continue
		var dir: Vector2i = DIRS[rng.randi() % 4]
		var n := c + dir
		if not in_bounds(n) or open_cells.has(n):
			continue
		open_cells[n] = true
		side_cells[n] = true
		level[idx(n)] = level[idx(c)]
		links[_key(c, n)] = true
		sides -= 1
	for z in d:
		for x in w:
			if not open_cells.has(Vector2i(x, z)):
				level[idx(Vector2i(x, z))] = 0


func _in_room(c: Vector2i) -> bool:
	for r: Array in rooms:
		if r.has(c):
			return true
	return false


## A self-avoiding walk made of straight runs of 2-4 cells.
func _walk_route(target: int) -> Array[Vector2i]:
	var start := Vector2i(rng.randi() % w, rng.randi() % d)
	var r: Array[Vector2i] = [start]
	var used := {start: true}
	var dir: Vector2i = DIRS[rng.randi() % 4]
	while r.size() < target:
		var options: Array = []
		for nd in DIRS:
			if nd == -dir:
				continue
			var fit := 0
			for k in range(1, rng.randi_range(2, 4) + 1):
				var p: Vector2i = r.back() + nd * k
				if not in_bounds(p) or used.has(p):
					break
				fit = k
			if fit >= 2 or (fit >= 1 and r.size() == 1):
				options.append([nd, fit])
		if options.is_empty():
			break
		var pick: Array = options[rng.randi() % options.size()]
		for k in range(1, pick[1] + 1):
			var p: Vector2i = r.back() + pick[0]
			r.append(p)
			used[p] = true
		dir = pick[0]
	return r


func _all_reachable() -> bool:
	var seen := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for dir in DIRS:
			var n := c + dir
			if in_bounds(n) and not seen.has(n) and linked(c, n):
				seen[n] = true
				queue.append(n)
	return seen.size() == w * d


# --- queries ------------------------------------------------------------------
func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(pos.x / cell)), 0, w - 1), clampi(int(floor(pos.z / cell)), 0, d - 1))


func is_trench(c: Vector2i) -> bool:
	if theme == "bunker":
		return trench_cells.has(c)
	return theme == "trench" and level[idx(c)] >= trench_level


## Part of the playable level (always true outside the bunker theme).
func is_open(c: Vector2i) -> bool:
	return theme != "bunker" or open_cells.has(c)


## Height of the ground surface (the top of every wall).
func top_height() -> float:
	var hi := 0
	for v in level:
		hi = maxi(hi, v)
	return hi * LEVEL + TRENCH_DEPTH if theme != "funhouse" else MAX_LEVEL * LEVEL + HEADROOM


## Bunker ceiling: clears its own floor and any floor it steps up to.
func ceiling_height(c: Vector2i) -> float:
	var hi := level[idx(c)]
	for dir in DIRS:
		var n := c + dir
		if in_bounds(n) and linked(c, n):
			hi = maxi(hi, level[idx(n)])
	return hi * LEVEL + BUNKER_HEADROOM


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * cell, level[idx(c)] * LEVEL, (c.y + 0.5) * cell)


## Height of the walkable surface under a point (stairs are treated as a slope).
func floor_height(pos: Vector3) -> float:
	var c := cell_of(pos)
	var base := level[idx(c)] * LEVEL
	for s: Dictionary in _stair_at.get(idx(c), []):
		var centre := cell_center(c)
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var rel := pos - centre
		var along := rel.dot(dir)                       # -CELL/2 .. CELL/2
		var across := absf(rel.dot(Vector3(dir.z, 0, -dir.x)))
		var t := (along - (CELL * 0.5 - STAIR_RUN)) / STAIR_RUN
		if t > 0.0 and across <= STAIR_WIDTH * 0.5 + 0.15:
			return base + LEVEL * clampf(t, 0.0, 1.0)
	return base


## Where a clown may stand: near a staircase, on the stair itself, not in
## the low strip beside it (a dead end under the rail with a wall of the
## level above at the end of it).
func keep_walkable(pos: Vector3) -> Vector3:
	var c := cell_of(pos)
	for s: Dictionary in _stair_at.get(idx(c), []):
		var centre := cell_center(c)
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var side := Vector3(dir.z, 0, -dir.x)
		var rel := pos - centre
		var along := rel.dot(dir)
		if along < CELL * 0.5 - STAIR_RUN - 0.45:
			continue                         # well short of the stair: the whole cell is floor
		var across := rel.dot(side)
		var limit := STAIR_WIDTH * 0.5 - 0.25
		if absf(across) > limit:
			pos -= side * (across - signf(across) * limit)
	return pos


## World-space waypoints from one position to another, through open cells.
func path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ids := _astar.get_id_path(idx(cell_of(from)), idx(cell_of(to)))
	for i in range(1, ids.size()):
		out.append(cell_center(Vector2i(ids[i] % w, ids[i] / w)))
	return out


## Where the exit door stands, facing back into the level.
func exit_transform() -> Transform3D:
	return Transform3D(Basis(), cell_center(exit_cell))


## A distance given in bunker cells (3 m), as a number of this maze's cells.
func span(bunker_cells: int) -> int:
	return int(round(bunker_cells * CELL / cell))


## This maze's cell size relative to a bunker cell (1 in the bunkers).
func scale() -> float:
	return cell / CELL


func path_cells(a: Vector2i, b: Vector2i) -> int:
	return _astar.get_id_path(idx(a), idx(b)).size()


func cells_far_from(c: Vector2i, min_steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in d:
		for x in w:
			var n := Vector2i(x, z)
			if path_cells(c, n) > min_steps:
				out.append(n)
	return out


# --- geometry -----------------------------------------------------------------
func _build() -> void:
	for n in get_children():
		n.queue_free()
	if theme != "funhouse":
		_build_trench()
	else:
		_build_funhouse()


## Collision for the trench theme; the look is built by LevelArt.
func _build_trench() -> void:
	var top := top_height()
	var boxes: Array = []
	for z in d:
		for x in w:
			var c := Vector2i(x, z)
			var h := level[idx(c)] * LEVEL
			boxes.append([Vector3((x + 0.5) * CELL, (h - 0.5) * 0.5, (z + 0.5) * CELL), Vector3(CELL, h + 0.5, CELL)])
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n := c + dir
				if not in_bounds(n) or not linked(c, n):
					var mid := Vector3((x + 0.5) * CELL, top * 0.5, (z + 0.5) * CELL) + Vector3(dir.x, 0, dir.y) * CELL * 0.5
					var size := Vector3(WALL_T, top, CELL + WALL_T) if dir.x != 0 else Vector3(CELL + WALL_T, top, WALL_T)
					boxes.append([mid, size])
			if not is_open(c):
				boxes.append([Vector3((x + 0.5) * CELL, top * 0.5, (z + 0.5) * CELL), Vector3(CELL, top, CELL)])
				continue
			if not is_trench(c):
				# solid earth above the bunker ceiling
				var ceil := ceiling_height(c)
				boxes.append([Vector3((x + 0.5) * CELL, (ceil + top) * 0.5 + 0.0, (z + 0.5) * CELL), Vector3(CELL, top - ceil, CELL)])
				# a lintel over every opening from this bunker cell out into a trench
				for dir in DIRS:
					var n := c + dir
					if in_bounds(n) and linked(c, n) and is_trench(n):
						var mid := Vector3((x + 0.5) * CELL, (ceil + top) * 0.5, (z + 0.5) * CELL) + Vector3(dir.x, 0, dir.y) * CELL * 0.5
						var size := Vector3(WALL_T, top - ceil, CELL) if dir.x != 0 else Vector3(CELL, top - ceil, WALL_T)
						boxes.append([mid, size])
		boxes.append([Vector3(0, top * 0.5, (z + 0.5) * CELL), Vector3(WALL_T, top, CELL + WALL_T)])
	for x in w:
		boxes.append([Vector3((x + 0.5) * CELL, top * 0.5, 0), Vector3(CELL + WALL_T, top, WALL_T)])
	_add_stairs(boxes)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		cs.shape = shape
		cs.position = b[0]
		body.add_child(cs)
	var art := LevelArt.new()
	art.name = "Art"
	add_child(art)
	art.build(self)


## Stair step boxes (added to `boxes`) and the smooth ramps the player walks on.
func _add_stairs(boxes: Array) -> void:
	var ramps := StaticBody3D.new()
	ramps.collision_layer = LAYER_RAMP
	ramps.collision_mask = 0
	add_child(ramps)
	var tread := STAIR_RUN / STEPS
	var rise := LEVEL / STEPS
	for s: Dictionary in stairs:
		var base := level[idx(s.low)] * LEVEL
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var side := Vector3(dir.z, 0, -dir.x)
		var edge := cell_center(s.low) + dir * CELL * 0.5
		edge.y = base
		for i in STEPS - 1:
			var near := (STEPS - 1 - i) * tread
			var centre := edge - dir * near * 0.5 + Vector3.UP * (i + 1) * rise * 0.5
			var size := (dir.abs() * near + side.abs() * STAIR_WIDTH + Vector3.UP * (i + 1) * rise)
			boxes.append([centre, size])
		var cs := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		var length := sqrt(STAIR_RUN * STAIR_RUN + LEVEL * LEVEL)
		slab.size = Vector3(STAIR_WIDTH, 0.1, length)
		cs.shape = slab
		ramps.add_child(cs)
		var mid := edge - dir * STAIR_RUN * 0.5 + Vector3.UP * LEVEL * 0.5
		var slope := (dir * STAIR_RUN + Vector3.UP * LEVEL).normalized()
		var up := side.cross(slope).normalized()
		if up.y < 0.0:
			up = -up
		cs.transform = Transform3D(Basis(up.cross(slope).normalized(), up, slope), mid - up * 0.05)


func _build_funhouse() -> void:
	var top := MAX_LEVEL * LEVEL + HEADROOM
	var boxes: Array = []           # [centre, size]
	for z in d:
		for x in w:
			var c := Vector2i(x, z)
			var h := level[idx(c)] * LEVEL
			boxes.append([Vector3((x + 0.5) * CELL, (h - 0.5) * 0.5, (z + 0.5) * CELL), Vector3(CELL, h + 0.5, CELL)])
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n := c + dir
				if not in_bounds(n) or not linked(c, n):
					var mid := Vector3((x + 0.5) * CELL, top * 0.5, (z + 0.5) * CELL) + Vector3(dir.x, 0, dir.y) * CELL * 0.5
					var size := Vector3(WALL_T, top, CELL + WALL_T) if dir.x != 0 else Vector3(CELL + WALL_T, top, WALL_T)
					boxes.append([mid, size])
		boxes.append([Vector3(0, top * 0.5, (z + 0.5) * CELL), Vector3(WALL_T, top, CELL + WALL_T)])
	for x in w:
		boxes.append([Vector3((x + 0.5) * CELL, top * 0.5, 0), Vector3(CELL + WALL_T, top, WALL_T)])
	boxes.append([Vector3(w * CELL * 0.5, top + 0.15, d * CELL * 0.5), Vector3(w * CELL + 1.0, 0.3, d * CELL + 1.0)])

	var ramps := StaticBody3D.new()
	ramps.collision_layer = LAYER_RAMP
	ramps.collision_mask = 0
	add_child(ramps)
	var tread := STAIR_RUN / STEPS
	var rise := LEVEL / STEPS
	for s: Dictionary in stairs:
		var base := level[idx(s.low)] * LEVEL
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var side := Vector3(dir.z, 0, -dir.x)
		var edge := cell_center(s.low) + dir * CELL * 0.5
		edge.y = base
		for i in STEPS - 1:
			# Each step is solid all the way back to the upper floor.
			var near := (STEPS - 1 - i) * tread
			var centre := edge - dir * near * 0.5 + Vector3.UP * (i + 1) * rise * 0.5
			var size := (dir.abs() * near + side.abs() * STAIR_WIDTH + Vector3.UP * (i + 1) * rise)
			boxes.append([centre, size])
		var cs := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		var length := sqrt(STAIR_RUN * STAIR_RUN + LEVEL * LEVEL)
		slab.size = Vector3(STAIR_WIDTH, 0.1, length)
		cs.shape = slab
		ramps.add_child(cs)
		var mid := edge - dir * STAIR_RUN * 0.5 + Vector3.UP * LEVEL * 0.5
		var slope := (dir * STAIR_RUN + Vector3.UP * LEVEL).normalized()
		var up := side.cross(slope).normalized()
		if up.y < 0.0:
			up = -up
		cs.transform = Transform3D(Basis(up.cross(slope).normalized(), up, slope), mid - up * 0.05)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for b: Array in boxes:
		_add_box(st, b[0], b[1])
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		cs.shape = shape
		cs.position = b[0]
		body.add_child(cs)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/funhouse.gdshader")
	var palettes := [
		[Color(0.50, 0.07, 0.07), Color(0.74, 0.68, 0.56)], [Color(0.30, 0.10, 0.42), Color(0.78, 0.66, 0.20)],
		[Color(0.08, 0.30, 0.30), Color(0.72, 0.66, 0.58)], [Color(0.55, 0.26, 0.05), Color(0.16, 0.12, 0.20)],
	]
	var pal: Array = palettes[rng.randi() % palettes.size()]
	mat.set_shader_parameter("stripe_a", pal[0])
	mat.set_shader_parameter("stripe_b", pal[1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

	# Sparse, sickly coloured lights; most of the maze is left to the flashlight.
	var hues := [Color(1.0, 0.25, 0.2), Color(0.7, 0.3, 1.0), Color(0.3, 1.0, 0.5), Color(1.0, 0.8, 0.3)]
	for z in d:
		for x in w:
			if (x + z * 2) % 3 != 0:
				continue
			var l := OmniLight3D.new()
			l.position = cell_center(Vector2i(x, z)) + Vector3.UP * 2.3
			l.omni_range = 5.5
			l.light_energy = rng.randf_range(0.5, 1.1)
			l.light_color = hues[rng.randi() % hues.size()]
			l.shadow_enabled = false
			add_child(l)


func _add_box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = n.cross(u)
		var o := c + n * h.dot(n.abs())
		var eu := u * h.dot(u.abs())
		var ev := v * h.dot(v.abs())
		var p := [o - eu - ev, o + eu - ev, o + eu + ev, o - eu + ev]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.add_vertex(p[i])
