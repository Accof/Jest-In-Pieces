class_name TrenchMaze
extends Maze
## The Drowned Trenches: an outdoor floor, a Western Front trench system
## (1916-17) cut into open ground, the morning after heavy rain.
##
## The same Maze API as the bunker floors (cells, links, A*, floor_height,
## cell_center), so the enemies, gore, killcam and Carnival Curse work
## unchanged; but the grid is 1.5 m, the width of a trench, and the ground is
## one carved heightfield (see _carve) instead of boxes.
##
## Layout (z grows toward the rear; No Man's Land is beyond z = 0):
##   fire trench   crenellated bays and traverses, fire steps, parapet and parados
##   support line  sinuous, about 15 m behind, with dugouts off it
##   reserve line  partial, further back
##   communication trenches zigzagging between them (loops), and to the rear
##   saps out from the fire trench to an observation post
##   side stubs: dead-end firing positions, a flooded side trench, a gun pit
## The player comes in at the rear end of a communication trench; the exit is
## a concrete bunker at the far end of the fire trench.

const TCELL := 1.5               ## the grid: one trench width
const GRID_W := 32
const GRID_D := 28
const FIRE_ROW := 6
const SUPPORT_ROW := 14
const RESERVE_ROW := 21
const RES := 0.2                 ## heightfield sample spacing (m)
const MARGIN := 12.0             ## carved-terrain border round the grid (m)
const FIRE_STEP_H := 0.85        ## fire step above the bay floor (eye on it at the parapet top)
const FIRE_STEP_D := 0.6         ## and how deep it is (into the front wall)
const STEP_RAMP := 1.05          ## the walked surface eases up onto the step over this far

## What each open cell is: "fire", "traverse", "support", "reserve", "comm",
## "sap", "op", "stub", "dugout", "gunpit", "flood", "junction".
var kind := {}
## Cells of each named trench, in order: "fire", "support", ...
var trenches := {}
## Fire-trench bay cells (with a fire step on their front wall).
var bays := {}
## Cells under standing water.
var flooded := {}
## Cells where a wall has slumped in (still passable).
var collapsed := {}
## Landmarks: {kind, cell, dir}: "tree", "op", "gunpit", "dugout", "flood_junction", "exit", "start"
var landmarks: Array = []
## Base floor depth of each open cell (negative, metres below the ground).
var depth := {}

# the carved ground (filled by _carve)
var hx := 0                      ## samples along x
var hz := 0                      ## samples along z
var origin := Vector2.ZERO       ## world x/z of sample (0, 0)
var vis_h := PackedFloat32Array()   ## rendered surface
var col_h := PackedFloat32Array()   ## walked surface (duckboard tops, eased fire steps)
var sdf := PackedFloat32Array()     ## signed distance to the trench floor edge (m, < 0 inside)
var wet := PackedFloat32Array()     ## 0..1 wetness of the surface
var duckboards: Array = []          ## {a: Vector3, b: Vector3, broken: float, sunk: float}
var water: Array = []               ## {rect: Rect2, level: float}


func _init() -> void:
	theme = "trench_outdoor"
	cell = TCELL


func generate(_width: int, _depth: int, seed_value: int) -> void:
	w = GRID_W
	d = GRID_D
	rng.seed = seed_value
	for attempt in 40:
		_reset()
		if _layout():
			break
	level = PackedInt32Array()
	level.resize(w * d)
	stairs.clear()
	_finish_trench()


func _reset() -> void:
	links.clear()
	open_cells.clear()
	kind.clear()
	trenches.clear()
	bays.clear()
	flooded.clear()
	collapsed.clear()
	landmarks.clear()
	depth.clear()
	route.clear()
	side_cells.clear()
	trench_cells.clear()
	top_cells.clear()
	ramps.clear()
	bridges.clear()
	passing.clear()
	bridge_sites.clear()


func is_open(c: Vector2i) -> bool:
	return open_cells.has(c) or top_cells.has(c)


func is_trench(c: Vector2i) -> bool:
	return open_cells.has(c)


# --- layout ---------------------------------------------------------------------
## Mark a cell open as part of trench `name` (kind `k`).
func _open(c: Vector2i, k: String, name_: String) -> void:
	if not open_cells.has(c):
		open_cells[c] = true
		kind[c] = k
		if not trenches.has(name_):
			trenches[name_] = []
		trenches[name_].append(c)
	for dir in DIRS:
		var n := c + dir
		if open_cells.has(n):
			links[_key(c, n)] = true


## Whether a new trench may pass through `c`: in bounds (with a border) and not
## touching any open cell other than those in `allowed`.
func _free(c: Vector2i, allowed: Dictionary, border := 1) -> bool:
	if c.x < border or c.y < 1 or c.x >= w - border or c.y >= d:
		return false
	if open_cells.has(c) and not allowed.has(c):
		return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dz)
			if open_cells.has(n) and not allowed.has(n):
				return false
	return true


func _layout() -> bool:
	if not _fire_trench():
		return false
	if not _line("support", SUPPORT_ROW, 2, w - 3, 1):
		return false
	var r0 := int(w * rng.randf_range(0.18, 0.3))
	var r1 := int(w * rng.randf_range(0.66, 0.8))
	if not _line("reserve", RESERVE_ROW, r0, r1, 1):
		return false
	# communication trenches: front <-> support (three), support <-> reserve (two),
	# and two to the rear edge (one from the reserve, one from the support line)
	var made := 0
	for fx: float in [0.15, 0.5, 0.85]:
		if _comm("comm", "support", "fire", int(w * (fx + rng.randf_range(-0.06, 0.06)))):
			made += 1
	if made < 2:
		return false
	made = 0
	for fx: float in [r0 + 3, r1 - 3]:
		if _comm("comm", "reserve", "support", int(fx) + rng.randi_range(-1, 1)):
			made += 1
	if made < 1:
		return false
	var rear := _to_rear("reserve", int((r0 + r1) * 0.5) + rng.randi_range(-3, 3))
	if rear.is_empty():
		return false
	# saps out toward No Man's Land, each ending at an observation post
	var saps := 0
	for i in 6:
		if saps >= 2:
			break
		if _sap(int(w * rng.randf_range(0.2, 0.8))):
			saps += 1
	# side features off the lines
	_stubs()
	# start: the rear end of the communication trench to the rear edge
	start_cell = rear.back()
	landmarks.append({kind = "start", cell = start_cell})
	# exit: the end of the fire trench farther from the start
	var fire: Array = trenches["fire"]
	var a: Vector2i = fire[0]
	var b: Vector2i = fire.back()
	exit_cell = a if a.distance_to(start_cell) > b.distance_to(start_cell) else b
	landmarks.append({kind = "exit", cell = exit_cell, dir = Vector2i(-1, 0) if exit_cell == a else Vector2i(1, 0)})
	# every open cell reachable
	return _connected()


## The fire trench: bays along FIRE_ROW and traverses stepping back round
## blocks of earth (FIRE_ROW + 2), all the way across.
func _fire_trench() -> bool:
	var x := 2
	var z := FIRE_ROW
	var allowed := {}
	var last := w - 3
	while x <= last:
		var bay := rng.randi_range(3, 5)
		for i in bay:
			if x > last:
				break
			var c := Vector2i(x, z)
			_open(c, "fire", "fire")
			bays[c] = true
			x += 1
		if x > last - 2:
			while x <= last:
				_open(Vector2i(x, z), "fire", "fire")
				bays[Vector2i(x, z)] = true
				x += 1
			break
		# round the traverse: back two rows, along, forward again
		var t := rng.randi_range(3, 4)
		x -= 1
		_open(Vector2i(x, z + 1), "traverse", "fire")
		for i in t + 1:
			_open(Vector2i(x + i, z + 2), "traverse", "fire")
		x += t
		_open(Vector2i(x, z + 1), "traverse", "fire")
		x += 0
		_open(Vector2i(x, z), "fire", "fire")
		bays[Vector2i(x, z)] = true
		x += 1
	return trenches.has("fire") and trenches["fire"].size() > 20


## A sinuous line along `row` from x0 to x1, drifting a row either way now and then.
func _line(name_: String, row: int, x0: int, x1: int, drift: int) -> bool:
	var z := row
	var since := 0
	var own := {}
	for x in range(x0, x1 + 1):
		var c := Vector2i(x, z)
		if not _free(c, own):
			return false
		_open(c, name_, name_)
		own[c] = true
		since += 1
		if since >= rng.randi_range(4, 8) and x < x1 - 2 and x > x0 + 1:
			var nz := clampi(z + (1 if rng.randf() < 0.5 else -1), row - drift, row + drift)
			var n := Vector2i(x, nz)
			if nz != z and _free(n, own):
				_open(n, name_, name_)
				own[n] = true
				z = nz
				since = 0
	return true


## A zigzag communication trench from line `from` forward (toward -z) to
## line `to`, starting near column x.
func _comm(name_: String, from: String, to: String, x: int) -> bool:
	var start := _cell_in(from, x)
	if start == Vector2i(-1, -1):
		return false
	var target_rows := {}
	for c: Vector2i in trenches[to]:
		target_rows[c] = true
	for attempt in 12:
		var path: Array[Vector2i] = []
		var c := start
		var ok := false
		var dir_x := 1 if rng.randf() < 0.5 else -1
		var allowed := {start: true}
		for n in _ring(start):
			if open_cells.has(n):
				allowed[n] = true
		var guard := 0
		while guard < 60:
			guard += 1
			# forward a few
			var fwd := rng.randi_range(2, 3)
			var hit := false
			for i in fwd:
				var n := c + Vector2i(0, -1)
				if target_rows.has(n) or _touches(n, target_rows):
					# joined: open n if it is not already part of the line
					if not target_rows.has(n):
						path.append(n)
					hit = true
					break
				if not _free(n, allowed):
					break
				path.append(n)
				allowed[n] = true
				for m in _ring(n):
					if path.has(m):
						allowed[m] = true
				c = n
			if hit:
				ok = true
				break
			# across one or two, alternating sides (the zigzag)
			var across := rng.randi_range(1, 2)
			var moved := 0
			for i in across:
				var n := c + Vector2i(dir_x, 0)
				if target_rows.has(n) or not _free(n, allowed):
					break
				path.append(n)
				allowed[n] = true
				c = n
				moved += 1
			dir_x = -dir_x
			if moved == 0 and fwd == 0:
				break
		if ok and path.size() >= 3:
			var tname := name_ + str(trenches.size())
			for p in path:
				_open(p, "comm", tname)
			# a widened junction where it leaves the line, now and then
			if rng.randf() < 0.5:
				_widen(start)
			return true
		# undo nothing (nothing was opened); try another start
		start = _cell_in(from, x + rng.randi_range(-3, 3))
		if start == Vector2i(-1, -1):
			return false
	return false


## Whether any 4-neighbour of `c` is in `set`.
func _touches(c: Vector2i, set_: Dictionary) -> bool:
	for dir in DIRS:
		if set_.has(c + dir):
			return true
	return false


func _ring(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dz != 0:
				out.append(c + Vector2i(dx, dz))
	return out


## The cell of trench `name_` nearest column x.
func _cell_in(name_: String, x: int) -> Vector2i:
	if not trenches.has(name_):
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var bd := 999
	for c: Vector2i in trenches[name_]:
		var dd := absi(c.x - x)
		if dd < bd and kind[c] != "traverse":
			bd = dd
			best = c
	return best


## A communication trench from line `from` back to the rear edge. Returns its cells.
func _to_rear(from: String, x: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := _cell_in(from, x)
	if start == Vector2i(-1, -1):
		return out
	for attempt in 10:
		var path: Array[Vector2i] = []
		var c := start
		var allowed := {start: true}
		for n in _ring(start):
			if open_cells.has(n):
				allowed[n] = true
		var dir_x := 1 if rng.randf() < 0.5 else -1
		var ok := false
		var guard := 0
		while guard < 40:
			guard += 1
			var back := rng.randi_range(2, 3)
			for i in back:
				var n := c + Vector2i(0, 1)
				if n.y >= d:
					ok = true
					break
				if not _free(n, allowed):
					break
				path.append(n)
				allowed[n] = true
				c = n
			if ok or c.y >= d - 1:
				ok = true
				break
			var across := rng.randi_range(1, 2)
			for i in across:
				var n := c + Vector2i(dir_x, 0)
				if not _free(n, allowed):
					break
				path.append(n)
				allowed[n] = true
				c = n
			dir_x = -dir_x
		if ok and path.size() >= 3:
			var tname := "rear" + str(trenches.size())
			for p in path:
				_open(p, "comm", tname)
			return path
		start = _cell_in(from, x + rng.randi_range(-3, 3))
	return out


## A sap: a short zigzag from a fire bay out into No Man's Land, ending at an
## observation post (a widened, sandbagged end).
func _sap(x: int) -> bool:
	var start := Vector2i(-1, -1)
	var bd := 999
	for c: Vector2i in trenches["fire"]:
		if bays.has(c) and absi(c.x - x) < bd:
			bd = absi(c.x - x)
			start = c
	if start == Vector2i(-1, -1):
		return false
	var path: Array[Vector2i] = []
	var c := start
	var allowed := {start: true}
	for n in _ring(start):
		if open_cells.has(n):
			allowed[n] = true
	var dir_x := 1 if rng.randf() < 0.5 else -1
	while c.y > 2:
		var n := c + Vector2i(0, -1)
		if not _free(n, allowed, 2):
			return false
		path.append(n)
		allowed[n] = true
		c = n
		if c.y == FIRE_ROW - 2 and rng.randf() < 0.7:
			var s := c + Vector2i(dir_x, 0)
			if not _free(s, allowed, 2):
				return false
			path.append(s)
			allowed[s] = true
			c = s
	if path.size() < 3:
		return false
	var tname := "sap" + str(trenches.size())
	for p in path:
		_open(p, "sap", tname)
	kind[c] = "op"
	bays.erase(start)               # the sap leaves through the front wall here: no fire step
	landmarks.append({kind = "op", cell = c})
	return true


## Dead ends off the lines: dugouts behind the support and reserve lines, a
## flooded side trench, a gun pit, short firing positions; and the landmarks.
func _stubs() -> void:
	var made := {"dugout": 0, "flood": 0, "gunpit": 0, "stub": 0}
	var want := {"dugout": 3, "flood": 1, "gunpit": 1, "stub": 2}
	var lines := ["support", "reserve", "support", "fire"]
	for attempt in 120:
		var k: String = ["dugout", "flood", "gunpit", "stub"][attempt % 4]
		if made[k] >= want[k]:
			continue
		var line: String = lines[rng.randi() % lines.size()]
		if k == "gunpit" and line == "fire":
			line = "reserve"
		if not trenches.has(line):
			continue
		var cells: Array = trenches[line]
		var from: Vector2i = cells[rng.randi() % cells.size()]
		if kind.get(from, "") == "traverse" or from == start_cell:
			continue
		var dir := Vector2i(0, 1) if (k != "stub" or rng.randf() < 0.5) else Vector2i(0, -1)
		if line == "fire":
			dir = Vector2i(0, 1)
		if _stub(from, dir, k):
			made[k] += 1
	# a flooded junction and a shattered tree at two of the comm/line junctions
	var junctions: Array[Vector2i] = []
	for c: Vector2i in open_cells:
		var n := 0
		for dir in DIRS:
			if open_cells.has(c + dir):
				n += 1
		if n >= 3 and kind[c] in ["support", "reserve", "junction"]:
			junctions.append(c)
	_shuffle(junctions)
	if junctions.size() >= 1:
		var j: Vector2i = junctions[0]
		landmarks.append({kind = "tree", cell = j})
	if junctions.size() >= 2:
		var j: Vector2i = junctions[1]
		landmarks.append({kind = "flood_junction", cell = j})
		flooded[j] = true
		for dir in DIRS:
			if open_cells.has(j + dir) and rng.randf() < 0.8:
				flooded[j + dir] = true
	# a stretch of one communication trench where the wall has slumped in
	var comms: Array = []
	for n: String in trenches:
		if n.begins_with("comm"):
			comms.append(n)
	if not comms.is_empty():
		var t: Array = trenches[comms[rng.randi() % comms.size()]]
		if t.size() >= 4:
			var i := rng.randi_range(1, t.size() - 3)
			collapsed[t[i]] = true
			collapsed[t[i + 1]] = true


## One side feature off `from`, heading `dir`.
func _stub(from: Vector2i, dir: Vector2i, k: String) -> bool:
	var length: int = {"dugout": 1, "flood": rng.randi_range(3, 4), "gunpit": 1, "stub": rng.randi_range(1, 2)}[k]
	var allowed := {from: true}
	for n in _ring(from):
		if open_cells.has(n):
			allowed[n] = true
	var path: Array[Vector2i] = []
	var c := from
	for i in length:
		var n := c + dir
		if not _free(n, allowed):
			return false
		path.append(n)
		allowed[n] = true
		c = n
	# the room at the end: a dugout 3 across and 2 deep (4.5 x 3 m), a gun pit 3x3
	var room: Array[Vector2i] = []
	if k == "dugout" or k == "gunpit":
		var size := 2 if k == "dugout" else 3
		var size_w := 3
		var side := Vector2i(dir.y, dir.x)
		var off := -(size_w / 2)
		for a in size:
			for b in size_w:
				var r := c + dir * (a + 1) + side * (b + off)
				if not _free(r, allowed):
					return false
				room.append(r)
				allowed[r] = true
	var tname := k + str(trenches.size())
	for p in path:
		_open(p, "stub" if k != "flood" else "flood", tname)
		if k == "flood":
			flooded[p] = true
	for r in room:
		_open(r, k, tname + "_room")
		side_cells[r] = true
	if k == "dugout" or k == "gunpit":
		landmarks.append({kind = k, cell = room[0], entrance = c, dir = dir})
	return true


## Widen a junction cell sideways into a 2x2 (a little room to manoeuvre).
func _widen(c: Vector2i) -> void:
	for side: Vector2i in [Vector2i(0, 1), Vector2i(0, -1)]:
		var cells: Array[Vector2i] = [c + side, c + side + Vector2i(1, 0)]
		var ok := true
		for n in cells:
			if open_cells.has(n):
				continue
			var allowed := {}
			for m in _ring(n):
				if open_cells.has(m) and m.distance_to(c) < 2.5:
					allowed[m] = true
			if not _free(n, allowed):
				ok = false
		if ok:
			for n in cells:
				_open(n, "junction", "junction")
			_open(c + Vector2i(1, 0), "junction", "junction")
			return


## Shuffle with the floor's own generator (Array.shuffle() draws on the global
## one, so the same seed gave a different floor from run to run).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _connected() -> bool:
	if open_cells.is_empty():
		return false
	var first: Vector2i = open_cells.keys()[0]
	var seen := {first: true}
	var q: Array[Vector2i] = [first]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for dir in DIRS:
			var n := c + dir
			if open_cells.has(n) and not seen.has(n) and linked(c, n):
				seen[n] = true
				q.append(n)
	return seen.size() == open_cells.size()


# --- after the layout -----------------------------------------------------------
func _finish_trench() -> void:
	_astar.clear()
	for c: Vector2i in open_cells:
		_astar.add_point(idx(c), Vector2(c.x, c.y))
	for k: String in links:
		var parts := k.split("|")
		_astar.connect_points(int(parts[0]), int(parts[1]))
	# the main route, start to exit
	var ids := _astar.get_id_path(idx(start_cell), idx(exit_cell))
	route.clear()
	for id in ids:
		route.append(Vector2i(id % w, id / w))
	_passing_places()
	_pick_ramps()
	_pick_bridges()
	_depths()
	_carve()
	_top_layer()
	_build_trench_world()


## A passing place every 4-6 cells along each communication trench: on a
## straight stretch, the floor widened on one side for a cell, so two men can
## get by each other.
func _passing_places() -> void:
	passing.clear()
	for name_: String in trenches:
		if not (name_.begins_with("comm") or name_.begins_with("rear")):
			continue
		var cells: Array = trenches[name_]
		var next := rng.randi_range(2, 4)
		for i in range(1, cells.size() - 1):
			next -= 1
			if next > 0:
				continue
			var c: Vector2i = cells[i]
			var run: Vector2i = cells[i + 1] - cells[i - 1]
			if run.length_squared() != 4:
				continue                    # a corner: no room
			var side := Vector2i(run.y / 2, run.x / 2) * (1 if rng.randf() < 0.5 else -1)
			if open_cells.has(c + side) or open_cells.has(c - side):
				continue
			passing[c] = side
			next = rng.randi_range(4, 6)


## Base floor depth per cell, by what it is, drifting gently along each trench.
func _depths() -> void:
	# Below the ground round them (see _carve, which adds the local ground):
	# deep enough that a man standing on the duckboards is hidden (his eye is
	# 1.65 m up; the parapet and parados add to the front and back), but for
	# the observation posts, the gun pit, and the fire steps you climb to look out.
	var base := {"fire": -2.0, "traverse": -2.2, "support": -2.35, "reserve": -2.3, "comm": -2.3,
		"sap": -2.15, "op": -1.75, "stub": -2.25, "dugout": -2.85, "gunpit": -1.15, "flood": -2.45, "junction": -2.35}
	for c: Vector2i in open_cells:
		var k: String = kind[c]
		var v: float = base.get(k, -2.0)
		v += sin(c.x * 0.37 + c.y * 0.21 + rng.randf() * 0.0) * 0.08 + sin(c.x * 0.13 - c.y * 0.29) * 0.06
		if flooded.has(c) and k != "flood":
			v -= 0.18
		if bridge_sites.has(c):
			v -= 0.55                    # dug out under a footbridge: headroom (2.1 m and more)
		elif bridge_sites.has(c + Vector2i(1, 0)) or bridge_sites.has(c - Vector2i(1, 0)):
			v -= 0.45
		depth[c] = v


# --- walls -----------------------------------------------------------------------
## What lines the wall on side `dir` of open cell `c` (only where that side
## is earth): "timber", "iron", "sandbag", "wattle", "earth" or "broken".
var walls := {}


func wall(c: Vector2i, dir: Vector2i) -> String:
	return walls.get(_wkey(c, dir), "")


func _wkey(c: Vector2i, dir: Vector2i) -> String:
	return "%d,%d,%d,%d" % [c.x, c.y, dir.x, dir.y]


## Revetment per wall side, by trench: stretches of the same kind, some of it
## broken down, the communication trenches mostly bare earth.
func _walls() -> void:
	walls.clear()
	for name_: String in trenches:
		var cells: Array = trenches[name_]
		var current := ""
		var left := 0
		for c: Vector2i in cells:
			if left <= 0:
				current = _revet_for(kind[c])
				left = rng.randi_range(3, 7)
			left -= 1
			for dir in DIRS:
				if open_cells.has(c + dir):
					continue
				var t := current
				var k: String = kind[c]
				if k == "traverse" and dir.y != 0:
					t = "sandbag"
				if k in ["op", "dugout", "gunpit"]:
					t = "sandbag"
				if collapsed.has(c):
					t = "earth"
				if t != "earth" and rng.randf() < 0.12:
					t = "broken"
				walls[_wkey(c, dir)] = t
	# a ramp's mouth: no lining across it
	for r: Dictionary in ramps:
		walls[_wkey(r.cell, r.dir)] = "ramp"


func _revet_for(k: String) -> String:
	var r := rng.randf()
	match k:
		"fire": return "timber" if r < 0.5 else ("sandbag" if r < 0.8 else "wattle")
		"traverse": return "timber" if r < 0.6 else "earth"
		"support", "junction": return "iron" if r < 0.4 else ("timber" if r < 0.6 else ("wattle" if r < 0.75 else "earth"))
		"reserve": return "wattle" if r < 0.35 else ("iron" if r < 0.55 else "earth")
		"comm": return "earth" if r < 0.7 else ("timber" if r < 0.85 else "wattle")
		"sap", "op": return "sandbag"
		"stub", "flood": return "earth" if r < 0.7 else "wattle"
	return "earth"


# --- the carved ground ------------------------------------------------------------
## The shell holes on this floor: Vector4(x, z, radius, depth).
var crater_list: Array[Vector4] = []
## How far each kind of wall leans back from the floor edge to the top (m).
const WALL_W := {"timber": 0.12, "iron": 0.12, "sandbag": 0.22, "wattle": 0.14, "earth": 0.5, "broken": 0.42}


## One heightfield for the whole floor: ground with shell craters, the trenches
## cut into it (floor, walls by their lining, fire steps), parapet and parados,
## duckboards and water. vis_h is drawn, col_h walked on.
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
	# the shell holes, stamped in once (each touches only the samples round it)
	var holes := PackedFloat32Array()
	holes.resize(n)
	for cr: Vector4 in craters:
		var reach := cr.z * 1.35
		for iz in range(maxi(int((cr.y - reach - origin.y) / RES), 0), mini(int((cr.y + reach - origin.y) / RES) + 2, hz)):
			for ix in range(maxi(int((cr.x - reach - origin.x) / RES), 0), mini(int((cr.x + reach - origin.x) / RES) + 2, hx)):
				var dd := Vector2(origin.x + ix * RES - cr.x, origin.y + iz * RES - cr.y).length() / cr.z
				if dd < 1.35:
					holes[ix + iz * hx] += -cr.w * maxf(0.0, 1.0 - dd * dd) + cr.w * 0.35 * exp(-pow((dd - 1.0) * 4.0, 2.0))
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
	# each cell's depth is below the ground round it (the ground rolls by
	# +-0.35 m: in a dip a trench of fixed depth was shallow enough to see out of)
	for c: Vector2i in open_cells:
		depth[c] += ground.get_noise_2d((c.x + 0.5) * cell, (c.y + 0.5) * cell) * 0.35
	for iz in hz:
		for ix in hx:
			var x := origin.x + ix * RES
			var z := origin.y + iz * RES
			var i := ix + iz * hx
			# the ground up top
			var g := ground.get_noise_2d(x, z) * 0.35 + fine.get_noise_2d(x, z) * 0.04 + holes[i]
			# the trench
			var near := _nearest(x, z)
			var sd: float = near.d
			var h := g
			var wetness := 0.35 + clampf(-g * 0.6, 0.0, 0.3)
			if sd < 3.0:
				var c: Vector2i = near.cell
				var wt: String = near.wall
				var ww: float = WALL_W.get(wt, 0.4)
				sd += wobble.get_noise_2d(x, z) * (0.025 if ww < 0.2 else 0.09)
				if ww >= 0.3:
					sd += slump.get_noise_2d(x * 1.3, z * 1.3) * 0.12
				var fl := _floor_at(x, z, c, sd, slump, fine)
				# parapet in front of the fire trench, parados behind it and the support line
				var k: String = kind[c]
				var front := z < (c.y) * cell + 0.2
				if sd > 0.0 and k in ["fire", "traverse", "sap", "op"] and front:
					g += 0.22 * _mound(sd, 0.1, 1.9)        # the parapet: a man on the fire step looks over it
				elif sd > 0.0 and k in ["fire", "traverse", "support", "junction"] and not front:
					g += 0.28 * _mound(sd, 0.1, 1.4)
				if sd <= 0.0:
					h = fl
					wetness = 0.8 + clampf(-(fl - depth.get(c, fl)) * 2.0, 0.0, 0.2)
				else:
					var t := clampf(sd / ww, 0.0, 1.0)
					# a little slumped earth at the foot, steep above
					var prof := 1.0 - pow(1.0 - t, 1.6) if ww < 0.3 else pow(t, 0.75)
					h = lerpf(fl, g, prof)
					if ww >= 0.3:
						h += fine.get_noise_2d(x * 0.6, z * 0.6) * 0.25 * t * (1.0 - t) * 4.0   # slumps and bulges
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


## How much of the sky each point of the ground can see (0..1), on a grid
## SKY_STEP samples apart: the trench walls block it, so the floor and the
## foot of the walls get a fraction of the sky's light and the parapets get
## all of it. Eight directions, the highest horizon within 4 m in each; a
## direction's share is 1 - sin(horizon angle). Used as ambient occlusion by
## the ground and the props (and nothing else changes: the sun still casts
## its own shadows).
const SKY_STEP := 2
var sky_vis := PackedFloat32Array()   ## per sample (filled from the coarse grid)
var sky_w := 0                        ## the coarse grid's size
var sky_d := 0
var sky_coarse := PackedFloat32Array()


func _bake_sky() -> void:
	sky_w = (hx - 1) / SKY_STEP + 1
	sky_d = (hz - 1) / SKY_STEP + 1
	sky_coarse.resize(sky_w * sky_d)
	var dists := [0.3, 0.6, 1.0, 1.5, 2.1, 2.8, 3.8]
	var dirs: Array[Vector2] = []
	for k in 8:
		dirs.append(Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)))
	for cz in sky_d:
		for cx in sky_w:
			var ix := mini(cx * SKY_STEP, hx - 1)
			var iz := mini(cz * SKY_STEP, hz - 1)
			var i := ix + iz * hx
			if sdf[i] > 4.5:
				sky_coarse[cx + cz * sky_w] = 1.0
				continue
			var x := origin.x + ix * RES
			var z := origin.y + iz * RES
			var h0 := vis_h[i] + 0.05
			var sum := 0.0
			for dv in dirs:
				var best := 0.0
				for dist: float in dists:
					var hh := _sample(vis_h, x + dv.x * dist, z + dv.y * dist) - h0
					if hh > 0.0:
						best = maxf(best, hh / sqrt(hh * hh + dist * dist))   # sin of the angle up to it
				sum += 1.0 - best
			sky_coarse[cx + cz * sky_w] = sum / dirs.size()
	sky_vis.resize(hx * hz)
	for iz in hz:
		for ix in hx:
			sky_vis[ix + iz * hx] = sky_at_index(ix, iz)


## Sky visibility at a heightfield sample (bilinear on the coarse grid).
func sky_at_index(ix: int, iz: int) -> float:
	var fx := float(ix) / SKY_STEP
	var fz := float(iz) / SKY_STEP
	var x0 := mini(int(fx), sky_w - 2)
	var z0 := mini(int(fz), sky_d - 2)
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(sky_coarse[x0 + z0 * sky_w], sky_coarse[x0 + 1 + z0 * sky_w], tx)
	var b := lerpf(sky_coarse[x0 + (z0 + 1) * sky_w], sky_coarse[x0 + 1 + (z0 + 1) * sky_w], tx)
	return lerpf(a, b, tz)


## The coarse sky visibility and the ground height as a texture (R vis, G
## height), for the props' shader to look up at their own position.
func sky_texture() -> ImageTexture:
	var img := Image.create(sky_w, sky_d, false, Image.FORMAT_RGF)
	for cz in sky_d:
		for cx in sky_w:
			var ix := mini(cx * SKY_STEP, hx - 1)
			var iz := mini(cz * SKY_STEP, hz - 1)
			img.set_pixel(cx, cz, Color(sky_coarse[cx + cz * sky_w], vis_h[ix + iz * hx], 0.0))
	return ImageTexture.create_from_image(img)


## The player has no step-up: in front of each fire step the walked surface
## rises over STEP_RAMP (a slope he can climb, about 39 degrees) instead of the riser.
func _ease_fire_steps() -> void:
	for c: Vector2i in bays:
		var ze := c.y * cell + EDGE
		for iz in range(int((ze - origin.y) / RES) - 1, int((ze + STEP_RAMP + 0.05 - origin.y) / RES) + 2):
			for ix in range(int((c.x * cell - origin.x) / RES), int(((c.x + 1) * cell - origin.x) / RES) + 1):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var i := ix + iz * hx
				if sdf[i] > -0.05:
					continue
				var z := origin.y + iz * RES
				var x := origin.x + ix * RES
				var top := _sample(vis_h, x, ze - 0.3)
				var t := clampf((z - ze) / STEP_RAMP, 0.0, 1.0)
				# where the next cell along has no fire step (a bridge over it, a sap
				# leaving, the end of the bay), the ramp eases down sideways too: no
				# ledge across the floor to walk into
				var f := 1.0
				if not bays.has(c + Vector2i(-1, 0)):
					f = minf(f, clampf((x - c.x * cell) / 0.75, 0.0, 1.0))
				if not bays.has(c + Vector2i(1, 0)):
					f = minf(f, clampf(((c.x + 1) * cell - x) / 0.75, 0.0, 1.0))
				var want := top - t * FIRE_STEP_H - 0.02
				col_h[i] = maxf(col_h[i], lerpf(col_h[i], want, f))


func _mound(sd: float, a: float, b: float) -> float:
	if sd < a or sd > b:
		return 0.0
	var t := (sd - a) / (b - a)
	return sin(t * PI) * (1.0 - t * 0.3)


## Shell holes: a few on the top ground between the lines, many in No Man's
## Land. Each Vector4(x, z, radius, depth).
func _craters() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for i in 70:
		var x := rng.randf_range(-MARGIN, w * cell + MARGIN)
		var z := rng.randf_range(-MARGIN, FIRE_ROW * cell - 3.0) if i < 45 else rng.randf_range(0.0, d * cell + MARGIN)
		var r := rng.randf_range(1.2, 3.6)
		var near := _nearest(x, z)
		if near.d < r + 1.2:
			continue
		out.append(Vector4(x, z, r, rng.randf_range(0.35, 1.1) * r / 2.4))
	return out


## Per grid cell: the open cells within two, with their floor rects
## (the carve asks this for every sample, so it is built once).
var _near_cache := {}


func _near_list(c0: Vector2i) -> Array:
	var out := []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := c0 + Vector2i(dx, dz)
			if open_cells.has(c):
				out.append([c, _rect(c)])
	return out


func _build_near_cache() -> void:
	_near_cache.clear()
	var lo := Vector2i(int(floor(origin.x / cell)) - 1, int(floor(origin.y / cell)) - 1)
	var hi := Vector2i(int(ceil((origin.x + hx * RES) / cell)) + 1, int(ceil((origin.y + hz * RES) / cell)) + 1)
	for cz in range(lo.y, hi.y):
		for cx in range(lo.x, hi.x):
			var l := _near_list(Vector2i(cx, cz))
			if not l.is_empty():
				_near_cache[Vector2i(cx, cz)] = l


## The floor-edge signed distance at (x, z) (m; < 0 on the floor), the open
## cell it belongs to and the kind of wall there.
func _nearest(x: float, z: float) -> Dictionary:
	var cx := int(floor(x / cell))
	var cz := int(floor(z / cell))
	var best := 99.0
	var best_c := Vector2i(-1, -1)
	var best_dir := Vector2i.ZERO
	var acc := 99.0
	var near: Array = _near_cache.get(Vector2i(cx, cz), []) if not _near_cache.is_empty() else _near_list(Vector2i(cx, cz))
	for entry: Array in near:
		if true:
			var c: Vector2i = entry[0]
			var r: Rect2 = entry[1]
			var q := Vector2(x, z)
			var dist := _rect_sd(q, r)
			# smooth union: rounds the earth corners the trench turns round
			acc = _smin(acc, dist, 0.3) if acc < 98.0 else dist
			if dist < best:
				best = dist
				best_c = c
				# which side of this cell's rect is nearest
				var to_l := q.x - r.position.x
				var to_r := r.end.x - q.x
				var to_t := q.y - r.position.y
				var to_b := r.end.y - q.y
				var m := minf(minf(to_l, to_r), minf(to_t, to_b))
				if q.x < r.position.x or (m == to_l and q.y >= r.position.y and q.y <= r.end.y):
					best_dir = Vector2i(-1, 0)
				elif q.x > r.end.x or m == to_r:
					best_dir = Vector2i(1, 0)
				elif q.y < r.position.y or m == to_t:
					best_dir = Vector2i(0, -1)
				else:
					best_dir = Vector2i(0, 1)
				if q.x < r.position.x or q.x > r.end.x or q.y < r.position.y or q.y > r.end.y:
					# outside: the side we are beyond (a corner: the larger excess)
					var ex := maxf(r.position.x - q.x, q.x - r.end.x)
					var ez := maxf(r.position.y - q.y, q.y - r.end.y)
					if ex >= ez:
						best_dir = Vector2i(-1, 0) if q.x < r.position.x else Vector2i(1, 0)
					else:
						best_dir = Vector2i(0, -1) if q.y < r.position.y else Vector2i(0, 1)
	if best_c == Vector2i(-1, -1):
		return {d = 99.0, cell = best_c, wall = "earth", dir = best_dir}
	var wt := wall(best_c, best_dir)
	return {d = acc, cell = best_c, wall = wt if wt != "" else "earth", dir = best_dir}


const EDGE := 0.06

## The main lines are wider than the grid's one-cell trench: the floor runs
## on past the cell into the earth beside it (m, per side with earth there).
## Fire bays widen to the rear (the fire step is in front), the support line
## both ways, so two soldiers stand abreast (each 0.3 m in radius) with room
## to pass; the reserve a little; junctions open out. Communication trenches
## stay one cell, with a passing place every few cells (PASSING).
const WIDEN := {"fire": 0.9, "support": 0.65, "reserve": 0.3, "junction": 0.35}
const PASSING := 0.6
## Earth always left between two trenches' floors where one has been widened
## toward the other (with the walls' lean, about a metre of ground up top).
const MIN_EARTH := 1.0
## Comm cells with a passing place, and to which side: cell -> dir.
var passing := {}


## How far past its cell the floor of `c` reaches on side `dir` (0 if that
## side is open, or a narrow trench). Limited where another trench's floor is
## only a cell of earth away.
func widen_of(c: Vector2i, dir: Vector2i) -> float:
	var want := _widen_want(c, dir)
	if want <= 0.0:
		return 0.0
	var perp := Vector2i(dir.y, dir.x)
	var n2 := c + dir * 2
	for m in [n2, n2 + perp, n2 - perp]:
		if open_cells.has(m):
			want = minf(want, maxf(cell - 2.0 * EDGE - MIN_EARTH - _widen_want(m, -dir), 0.0))
	return want


func _widen_want(c: Vector2i, dir: Vector2i) -> float:
	if not open_cells.has(c) or open_cells.has(c + dir):
		return 0.0
	var k: String = kind.get(c, "")
	match k:
		"fire":
			return WIDEN.fire if dir == Vector2i(0, 1) else 0.0
		"support", "reserve":
			return WIDEN[k] if dir.y != 0 else 0.0
		"junction":
			return WIDEN.junction
		"comm":
			return PASSING if passing.get(c, Vector2i.ZERO) == dir else 0.0
	return 0.0


## The floor of an open cell: the cell, less a little at each wall, out to
## its open neighbours, and (fire bays) out over the fire step; wider for the
## main lines (widen_of).
func _rect(c: Vector2i) -> Rect2:
	var x0 := c.x * cell
	var z0 := c.y * cell
	var x1 := x0 + cell
	var z1 := z0 + cell
	if not open_cells.has(c + Vector2i(-1, 0)):
		x0 += EDGE - widen_of(c, Vector2i(-1, 0))
	if not open_cells.has(c + Vector2i(1, 0)):
		x1 -= EDGE - widen_of(c, Vector2i(1, 0))
	if not open_cells.has(c + Vector2i(0, -1)):
		z0 += EDGE - widen_of(c, Vector2i(0, -1))
		if bays.has(c):
			z0 -= FIRE_STEP_D
	if not open_cells.has(c + Vector2i(0, 1)):
		z1 -= EDGE - widen_of(c, Vector2i(0, 1))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _rect_sd(q: Vector2, r: Rect2) -> float:
	var c := r.get_center()
	var hsz := r.size * 0.5
	var dv := (q - c).abs() - hsz
	var outside := Vector2(maxf(dv.x, 0.0), maxf(dv.y, 0.0)).length()
	return outside + minf(maxf(dv.x, dv.y), 0.0)


func _smin(a: float, b: float, k: float) -> float:
	var hh := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, hh) - k * hh * (1.0 - hh)


## The trench floor at (x, z): the depths of the cells round it blended,
## ruts, mud heaped against the walls, fire steps, slumped-in earth.
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
	f += fine.get_noise_2d(x * 1.7, z * 1.7) * 0.035                 # ruts and boot holes
	f += clampf(slump.get_noise_2d(x, z), -1.0, -0.3) * 0.12 + 0.036 # shallow sumps
	f += 0.13 * (1.0 - smoothstep(-0.38, 0.0, sd))                    # mud piled at the foot of the walls
	if collapsed.has(c):
		# the wall has come in: a mound of earth along one side
		var side := 1.0 if (c.x + c.y) % 2 == 0 else -1.0
		var across := (x - (c.x + 0.5) * cell) * side if links.has(_key(c, c + Vector2i(0, 1))) or links.has(_key(c, c + Vector2i(0, -1))) else (z - (c.y + 0.5) * cell) * side
		f += 0.55 * smoothstep(-0.2, 0.75, across)
	if bays.has(c) and z < c.y * cell + EDGE:
		f += FIRE_STEP_H                                                 # the fire step under the front wall
	return f


## Duckboards down the middle of the trenches (not the flooded side trench,
## where they are sunk, nor the slumped stretch): straight runs between cell
## centres. They are walked on: col_h is raised under them.
func _lay_duckboards() -> void:
	duckboards.clear()
	for name_: String in trenches:
		var cells: Array = trenches[name_]
		if name_.begins_with("junction") or name_.begins_with("dugout") or name_.begins_with("gunpit"):
			continue
		var run: Array[Vector2i] = []
		for i in cells.size():
			var c: Vector2i = cells[i]
			# no boards over the stretch dug out under a footbridge: laid level
			# across it they would stand a knee's height over the mud at the
			# ends, a ledge to anyone coming in from a side trench
			if bridge_sites.has(c) or bridge_sites.has(c + Vector2i(1, 0)) or bridge_sites.has(c - Vector2i(1, 0)):
				_board_run(run)
				run = []
				continue
			if not run.is_empty():
				var prev: Vector2i = run.back()
				var straight := run.size() < 2 or (c - prev) == (prev - run[run.size() - 2])
				if (c - prev).length_squared() != 1 or not straight:
					_board_run(run)
					run = []
					if (c - prev).length_squared() == 1:
						run.append(prev)
			run.append(c)
		_board_run(run)
	# under the boards the walked surface is the board top
	for b: Dictionary in duckboards:
		var a: Vector3 = b.a
		var e: Vector3 = b.b
		var dir := (e - a)
		var length := Vector2(dir.x, dir.z).length()
		var u := Vector2(dir.x, dir.z) / maxf(length, 0.001)
		var lo := Vector2(minf(a.x, e.x), minf(a.z, e.z)) - Vector2.ONE * 1.2
		var hi := Vector2(maxf(a.x, e.x), maxf(a.z, e.z)) + Vector2.ONE * 1.2
		for iz in range(int((lo.y - origin.y) / RES), int((hi.y - origin.y) / RES) + 2):
			for ix in range(int((lo.x - origin.x) / RES), int((hi.x - origin.x) / RES) + 2):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var p := Vector2(origin.x + ix * RES, origin.y + iz * RES) - Vector2(a.x, a.z)
				var along := clampf(p.dot(u), 0.0, length)
				var across := absf(p.dot(Vector2(-u.y, u.x)))
				var beyond := absf(p.dot(u) - along)
				var top := lerpf(a.y, e.y, along / maxf(length, 0.001))
				var i := ix + iz * hx
				# where the boards stand well above the mud round them (a deeper
				# stretch alongside, a run's end over a dip) the walked surface
				# eases down off them instead of dropping: no ledge to catch on
				var lift := clampf((top - vis_h[i]) * 1.6, 0.0, 0.6)
				var k := 1.0 - smoothstep(0.31, 0.5 + lift, across) * 1.0
				k *= 1.0 - smoothstep(0.0, 0.25 + lift, beyond)
				if k > 0.0 and sdf[i] < 0.0:
					col_h[i] = maxf(col_h[i], lerpf(vis_h[i], top, k))
					if across < 0.36 and beyond < 0.05:
						vis_h[i] = minf(vis_h[i], top - 0.07)   # boards sit in the mud


func _board_run(run: Array[Vector2i]) -> void:
	if run.size() < 2:
		return
	var a := _cell_floor(run[0])
	var b := _cell_floor(run.back())
	var dir := (b - a).normalized()
	# reach into the corner cells so runs meet
	a -= dir * 0.3
	b += dir * 0.3
	var sunk := 0.0
	var broken := 0.0
	for c in run:
		if flooded.has(c):
			sunk = 0.12
		if collapsed.has(c):
			broken = 0.6
	if rng.randf() < 0.2:
		broken = maxf(broken, rng.randf_range(0.1, 0.3))
	a.y += 0.11 - sunk
	b.y += 0.11 - sunk
	duckboards.append({a = a, b = b, broken = broken, sunk = sunk})


## A cell's floor at its centre, from the carved surface.
func _cell_floor(c: Vector2i) -> Vector3:
	var p := Vector3((c.x + 0.5) * cell, 0.0, (c.y + 0.5) * cell)
	p.y = _sample(vis_h, p.x, p.z)
	return p


## Shallow puddles in the floor's low places: how much water (0..1) stands
## at each sample, for the ground's shader (UV2.y). A sample holds water
## where it lies below the floor round it (sumps, ruts, the hollow along a
## wall's foot) and the ground is wet; and a few waterlogged corners, in
## patches. Not in the flooded stretches (they have their own water) or up top.
var puddle := PackedFloat32Array()


func _bake_puddles() -> void:
	puddle.resize(hx * hz)
	puddle.fill(0.0)
	# the floor round each sample: a 1 m box blur of the surface, rows then columns
	var tmp := PackedFloat32Array()
	tmp.resize(hx * hz)
	var mean := PackedFloat32Array()
	mean.resize(hx * hz)
	var r := 2
	for iz in hz:
		var row := iz * hx
		for ix in hx:
			var sum := 0.0
			var n := 0
			for k in range(maxi(ix - r, 0), mini(ix + r, hx - 1) + 1):
				sum += vis_h[row + k]
				n += 1
			tmp[row + ix] = sum / n
	for iz in hz:
		for ix in hx:
			var sum := 0.0
			var n := 0
			for k in range(maxi(iz - r, 0), mini(iz + r, hz - 1) + 1):
				sum += tmp[ix + k * hx]
				n += 1
			mean[ix + iz * hx] = sum / n
	var corners := FastNoiseLite.new()
	corners.seed = rng.randi()
	corners.frequency = 0.22
	var count := 0
	var floor_n := 0
	for iz in hz:
		for ix in hx:
			var i := ix + iz * hx
			if sdf[i] > -0.1:
				continue
			var x := origin.x + ix * RES
			var z := origin.y + iz * RES
			var c := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
			if flooded.has(c) or (bays.has(c) and z < c.y * cell + EDGE + 0.2):
				continue
			floor_n += 1
			var low := mean[i] - vis_h[i]
			var p := smoothstep(0.006, 0.035, low) * smoothstep(0.6, 0.85, wet[i])
			# waterlogged corners: a patch here and there where it is wettest
			var corner := smoothstep(0.62, 0.8, corners.get_noise_2d(x, z) * 0.5 + 0.5) * smoothstep(-0.05, -0.45, sdf[i] + 0.0) * 0.85
			p = maxf(p, corner * smoothstep(0.7, 0.9, wet[i]))
			puddle[i] = p
			if p > 0.4:
				count += 1
	puddle_share = float(count) / maxf(floor_n, 1)


## Share of the trench floor under a puddle (for tests).
var puddle_share := 0.0


## Standing water: each connected group of flooded cells gets one level,
## a little above its lowest floor.
func _lay_water() -> void:
	water.clear()
	var seen := {}
	for c0: Vector2i in flooded:
		if seen.has(c0):
			continue
		var group: Array[Vector2i] = []
		var q: Array[Vector2i] = [c0]
		seen[c0] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			group.append(c)
			for dir in DIRS:
				var n := c + dir
				if flooded.has(n) and not seen.has(n):
					seen[n] = true
					q.append(n)
		var lowest := 0.0
		var r := Rect2()
		for c in group:
			lowest = minf(lowest, depth[c])
			var cr := Rect2(c.x * cell - 0.3, c.y * cell - 0.3, cell + 0.6, cell + 0.6)
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
		water.append({rect = r, level = lowest + 0.24, cells = group})
	# rainwater left in the deeper shell holes
	# (added by the art from the crater list is not kept; a few here instead)


# --- up top: the ground over the trenches, ramps out, footbridges across ---------------
## Soldiers move over the open ground as well as along the trenches: up a ramp
## cut in a trench's back wall, along the top, over a footbridge laid across a
## main trench. The top is part of the same pathfinding: an earth cell whose
## middle is well clear of every trench is a top cell (top_cells), linked to
## its top neighbours; a ramp links a trench cell to the top cell at its head;
## a bridge links the top cells either side of the trench it spans. Trench
## cells and top cells never overlap (one is open, the other earth), so the
## Maze API (cell_of, cell_center, path, path_cells, linked) serves both.
var top_cells := {}
## {cell: the trench cell at its foot, dir: out of the trench, top: the top
##  cell at its head, foot: Vector2, head: Vector2 (x/z), width}
var ramps: Array = []
## {cell: the trench cell spanned, dir: along the bridge, ends: [top cell, top
##  cell], a: Vector3, b: Vector3 (deck ends, on the ground), width}
var bridges: Array = []
const RAMP_LEN := 3.7            ## rise about 2.3 m: 32 degrees, a man walks it
const RAMP_W := 1.3
const BRIDGE_W := 1.15
## How close to a trench's floor edge a soldier up top will go (m).
const TOP_CLEAR := 0.65


## Ramps out of the trench: one up into each stretch of open ground the
## trenches cut the top into (the strip between the fire and support lines,
## the ground behind the reserve, and so on: each walled off from the rest by
## trenches), so every bit of the top a soldier might walk, or a footbridge
## might land on, can be got to. The foot is in a plain straight bit of
## trench, the ground clear ahead for four cells. Picked before the carve
## (which cuts them).
func _pick_ramps() -> void:
	ramps.clear()
	# the stretches of ground: earth cells joined across their sides
	var region := {}
	var sizes: Array[int] = []
	for z in d:
		for x in w:
			var c0 := Vector2i(x, z)
			if open_cells.has(c0) or region.has(c0):
				continue
			var id := sizes.size()
			var q: Array[Vector2i] = [c0]
			region[c0] = id
			var n := 0
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				n += 1
				for dir in DIRS:
					var m := c + dir
					if in_bounds(m) and not open_cells.has(m) and not region.has(m):
						region[m] = id
						q.append(m)
			sizes.append(n)
	var pref := {"support": 0, "reserve": 0, "comm": 1, "junction": 1, "fire": 2, "traverse": 3}
	var cands := {}                  # region -> [[c, dir, rank]]
	for c: Vector2i in open_cells:
		var k: String = kind[c]
		if not pref.has(k) or c == start_cell or c == exit_cell or passing.has(c):
			continue
		for dir: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if open_cells.has(c + dir):
				continue
			if k == "fire" and dir == Vector2i(0, -1):
				continue                     # not over the parapet into No Man's Land
			var perp := Vector2i(dir.y, dir.x)
			if not (open_cells.has(c + perp) and open_cells.has(c - perp)):
				continue                     # a straight stretch at the foot
			var ok := true
			var rid: int = region.get(c + dir, -1)
			for i in range(1, 5):
				for j: int in [-1, 0, 1]:
					var m: Vector2i = c + dir * i + perp * j
					if open_cells.has(m) or not in_bounds(m) or region.get(m, -2) != rid:
						ok = false
			if ok:
				if not cands.has(rid):
					cands[rid] = []
				cands[rid].append([c, dir, pref[k]])
	var rids := cands.keys()
	rids.sort()
	for rid: int in rids:
		if sizes[rid] < 12:
			continue
		var opts: Array = cands[rid]
		_shuffle(opts)
		opts.sort_custom(func(p: Array, q: Array) -> bool: return p[2] < q[2])
		for o: Array in opts:
			var c: Vector2i = o[0]
			if ramps.any(func(r: Dictionary) -> bool: return Vector2(r.cell).distance_to(Vector2(c)) < 6.0):
				continue
			ramps.append({cell = c, dir = o[1], width = RAMP_W})
			break


## Cut the ramps into the carved ground: a slope from the trench floor at the
## wall's foot up to the ground RAMP_LEN beyond, with steep cut sides; counted
## as trench floor (sdf) so a soldier on it is still in the trench until he
## reaches the top.
## Narrow troughs in a trench floor (where two cells' floors and the
## smoothing between them leave a dip a hand's breadth to a stride across)
## are filled in: a man could not climb out of one without a step. Only dips
## under 1.2 m across with floor both sides, never the flooded stretches (their
## water sits in them) or the long dig under a footbridge (far wider).
var troughs_filled := 0


func _fill_troughs() -> void:
	var floor_of := func(i: int) -> bool: return sdf[i] < -0.05
	for pass_ in 3:
		for axis in 2:
			var step := 1 if axis == 0 else hx
			for iz in range(3, hz - 3):
				for ix in range(3, hx - 3):
					var i := ix + iz * hx
					if not floor_of.call(i):
						continue
					var x := origin.x + ix * RES
					var z := origin.y + iz * RES
					var c := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
					if flooded.has(c):
						continue
					var best := -INF
					for d in range(1, 4):
						var a := i - d * step
						var b := i + d * step
						if not (floor_of.call(a) and floor_of.call(b)):
							break
						best = maxf(best, minf(vis_h[a], vis_h[b]))
					if best > vis_h[i] + 0.12:
						vis_h[i] = best - 0.04
						troughs_filled += 1


## Round the stretches dug out under the footbridges (and where a site was
## dug but no bridge built) the floor drops 0.45-0.55 m from one cell to the
## next: ease it so no slope there is steeper than a man walks without a step
## (about 24 degrees). Only near the digs; never a fire bay, a ramp or a
## flooded stretch.
func _ease_digs() -> void:
	if bridge_sites.is_empty():
		return
	var near := {}
	for site: Vector2i in bridge_sites:
		for dz in range(-2, 3):
			for dx in range(-3, 4):
				near[site + Vector2i(dx, dz)] = true
	var idxs := PackedInt32Array()
	for iz in range(1, hz - 1):
		for ix in range(1, hx - 1):
			var i := ix + iz * hx
			if sdf[i] > -0.05:
				continue
			var x := origin.x + ix * RES
			var z := origin.y + iz * RES
			var c := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
			if not near.has(c) or bays.has(c) or flooded.has(c) or not ramp_at(Vector3(x, 0, z)).is_empty():
				continue
			idxs.append(i)
	var ok := {}
	for i in idxs:
		ok[i] = true
	var lim := 0.09
	for pass_ in 10:
		for i in idxs:
			for j in [i + 1, i + hx]:
				if not ok.has(j):
					continue
				var d: float = vis_h[i] - vis_h[j]
				if absf(d) > lim:
					var adj: float = (absf(d) - lim) * 0.5 * signf(d)
					vis_h[i] -= adj
					vis_h[j] += adj


func _cut_ramps() -> void:
	for r: Dictionary in ramps:
		var c: Vector2i = r.cell
		var dir: Vector2i = r.dir
		var rc := _rect(c)
		var mid := rc.get_center()
		var foot := mid + Vector2(dir) * (absf(dir.x) * rc.size.x + absf(dir.y) * rc.size.y) * 0.5
		var head := foot + Vector2(dir) * RAMP_LEN
		r.foot = foot
		r.head = head
		var tp := head + Vector2(dir) * 0.9
		r.top = Vector2i(int(floor(tp.x / cell)), int(floor(tp.y / cell)))
		var fl := _sample(vis_h, mid.x, mid.y)
		var top := _sample(vis_h, head.x + dir.x * 0.6, head.y + dir.y * 0.6)
		var u := Vector2(dir)
		var side := Vector2(-u.y, u.x)
		var lo := foot.min(head) - Vector2.ONE * 1.6
		var hi := foot.max(head) + Vector2.ONE * 1.6
		for iz in range(int((lo.y - origin.y) / RES), int((hi.y - origin.y) / RES) + 1):
			for ix in range(int((lo.x - origin.x) / RES), int((hi.x - origin.x) / RES) + 1):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var p := Vector2(origin.x + ix * RES, origin.y + iz * RES) - foot
				var along := p.dot(u)
				var across := absf(p.dot(side))
				if along < -0.2 or along > RAMP_LEN + 0.3:
					continue
				var in_strip := along < RAMP_LEN - 0.4
				var t := clampf(along / RAMP_LEN, 0.0, 1.0)
				var ramp_h := lerpf(fl, top, t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65)
				var half: float = r.width * 0.5
				var i := ix + iz * hx
				if across <= half:
					vis_h[i] = minf(vis_h[i], ramp_h)
					if along > 0.0:
						vis_h[i] = ramp_h
					if in_strip:
						sdf[i] = minf(sdf[i], -0.4)     # still trench floor till near the top
					wet[i] = maxf(wet[i], 0.7)
				elif across <= half + 0.45:
					# the cut sides: steep, falling to the ramp
					var k: float = (across - half) / 0.45
					vis_h[i] = minf(vis_h[i], lerpf(ramp_h, vis_h[i], k * k))


## The top layer: top cells, ramps' heads, footbridges, the links, and the
## pathfinding points for them.
func _top_layer() -> void:
	top_cells.clear()
	bridges.clear()
	# a dugout's roof stands up out of the ground (beams, iron, sandbags): the
	# ground round it is not walked over
	var roofed := {}
	for c: Vector2i in open_cells:
		if kind[c] == "dugout":
			for n in _ring(c):
				roofed[n] = true
	for z in d:
		for x in w:
			var c := Vector2i(x, z)
			if open_cells.has(c) or roofed.has(c):
				continue
			var ctr := Vector2((x + 0.5) * cell, (z + 0.5) * cell)
			if _sample(sdf, ctr.x, ctr.y) < 0.8:
				continue
			var clear := true
			for dv: Vector2 in [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
				if _sample(sdf, ctr.x + dv.x * cell, ctr.y + dv.y * cell) < 0.3:
					clear = false
			if clear:
				top_cells[c] = true
	for r: Dictionary in ramps:
		if not top_cells.has(r.top):
			top_cells[r.top] = true
	# footbridges at the sites picked before the carve, where there is top
	# ground at both ends
	for c: Vector2i in bridge_sites:
		var ends := []
		for sgn in [-1, 1]:
			var found := Vector2i(-1, -1)
			for i in range(1, 5):
				var n := c + Vector2i(0, sgn * i)
				if open_cells.has(n):
					break
				if top_cells.has(n):
					found = n
					break
			ends.append(found)
		if ends[0] == Vector2i(-1, -1) or ends[1] == Vector2i(-1, -1):
			continue
		var x := (c.x + 0.5) * cell
		# the deck's ends: on the ground a little past each lip, flush with it
		# (the player has no step-up)
		var za := _lip(x, (c.y + 0.5) * cell, -1) - 0.55
		var zb := _lip(x, (c.y + 0.5) * cell, 1) + 0.55
		var a := Vector3(x, _sample(vis_h, x, za) + 0.02, za)
		var b := Vector3(x, _sample(vis_h, x, zb) + 0.02, zb)
		bridges.append({cell = c, dir = Vector2i(0, 1), ends = ends, a = a, b = b, width = BRIDGE_W})
	# links and pathfinding points
	for c: Vector2i in top_cells:
		_astar.add_point(idx(c), Vector2(c.x, c.y))
	for c: Vector2i in top_cells:
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + dir
			if not top_cells.has(n):
				continue
			var m := Vector2((c.x + 0.5 + dir.x * 0.5) * cell, (c.y + 0.5 + dir.y * 0.5) * cell)
			if _sample(sdf, m.x, m.y) < 0.55:
				continue
			links[_key(c, n)] = true
			_astar.connect_points(idx(c), idx(n))
	for r: Dictionary in ramps:
		_astar.connect_points(idx(r.cell), idx(r.top))
	for b: Dictionary in bridges:
		_astar.connect_points(idx(b.ends[0]), idx(b.ends[1]))


## Cells of the main lines a footbridge will cross (two over the fire
## trench, two over the support line), on straight stretches with earth for
## three cells either side; picked before the carve, because a fire bay
## under a bridge loses its fire step (whose ramp would bring a man's head up
## into the stringers).
var bridge_sites: Array[Vector2i] = []


func _pick_bridges() -> void:
	bridge_sites.clear()
	var want := {"fire": 2, "support": 2, "reserve": 1}
	var cands: Array[Vector2i] = []
	for c: Vector2i in open_cells:
		var k: String = kind[c]
		if not want.has(k):
			continue
		if not (open_cells.has(c + Vector2i(1, 0)) and open_cells.has(c + Vector2i(-1, 0))):
			continue
		var ok := true
		for sgn in [-1, 1]:
			for i in range(1, 3):
				for j in [0]:
					if open_cells.has(c + Vector2i(j, sgn * i)) or not in_bounds(c + Vector2i(j, sgn * i)):
						ok = false
		if ok and not ramps.any(func(r: Dictionary) -> bool: return Vector2(r.cell).distance_to(Vector2(c)) < 3.0):
			cands.append(c)
	_shuffle(cands)
	var made := {}
	for c in cands:
		var k: String = kind[c]
		if made.get(k, 0) >= want[k]:
			continue
		if bridge_sites.any(func(b: Vector2i) -> bool: return absi(b.x - c.x) < 5 and absi(b.y - c.y) < 6):
			continue
		bridge_sites.append(c)
		# no fire steps in the stretch under it either (their ramps would bring a
		# man's head up into the stringers)
		bays.erase(c)
		bays.erase(c + Vector2i(1, 0))
		bays.erase(c + Vector2i(-1, 0))
		made[k] = made.get(k, 0) + 1


## Where the trench edge is up the z line through (x, z), going `sgn` (the
## ground level reached: sdf past the wall's top).
func _lip(x: float, z: float, sgn: int) -> float:
	var t := 0.0
	while t < 4.0 and _sample(sdf, x, z + sgn * t) < 0.55:
		t += 0.05
	return z + sgn * t


## The footbridge under a point, if any (on it or just above), else {}.
## `reach` > 0 also counts the ground that far past each end, in line with it.
func bridge_at(pos: Vector3, reach := 0.0) -> Dictionary:
	for b: Dictionary in bridges:
		var a: Vector3 = b.a
		var e: Vector3 = b.b
		var ab := Vector2(e.x - a.x, e.z - a.z)
		var l := ab.length()
		var u := ab / l
		var q := Vector2(pos.x - a.x, pos.z - a.z)
		var along := q.dot(u)
		if along < -0.1 - reach or along > l + 0.1 + reach:
			continue
		if absf(q.dot(Vector2(-u.y, u.x))) > b.width * 0.5 + 0.05 + reach * 0.15:
			continue
		var deck := lerpf(a.y, e.y, clampf(along / l, 0.0, 1.0))
		if pos.y > deck - 1.0:
			return {bridge = b, deck = deck, along = along, length = l, across = q.dot(Vector2(-u.y, u.x))}
	return {}


## The ramp a point is on, if any: {ramp, along (m up it from the foot), across}.
func ramp_at(pos: Vector3) -> Dictionary:
	for r: Dictionary in ramps:
		if not r.has("foot"):
			continue
		var foot: Vector2 = r.foot
		var u := Vector2(r.dir)
		var q := Vector2(pos.x, pos.z) - foot
		var along := q.dot(u)
		if along < 0.0 or along > RAMP_LEN + 0.6:
			continue
		var across := q.dot(Vector2(-u.y, u.x))
		if absf(across) > float(r.width) * 0.5 + 0.1:
			continue
		return {ramp = r, along = along, across = across}
	return {}


## Whether a point is up on the ground (or a bridge) rather than down in a trench.
func on_top(pos: Vector3) -> bool:
	if not bridge_at(pos).is_empty():
		return true
	return _sample(sdf, pos.x, pos.z) > 0.15


# --- the world: collision and the look ---------------------------------------------
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
	# a heightmap is centred on its node, one unit per sample: scale it to RES
	cs.position = Vector3(origin.x + (hx - 1) * RES * 0.5, 0.0, origin.y + (hz - 1) * RES * 0.5)
	cs.scale = Vector3(RES, 1.0, RES)
	body.add_child(cs)
	# the edge of the world: the carved ground ends MARGIN past the grid; a wall
	# there keeps the player in. It stops the player only (LAYER_RAMP): rounds,
	# grenades and bodies go on out over No Man's Land (TrenchBattle's field
	# gives the ground out there its own collision)
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
	var art := TrenchArt.new()
	art.name = "Art"
	add_child(art)
	art.build(self)


# --- queries ----------------------------------------------------------------------
func cell_center(c: Vector2i) -> Vector3:
	var p := Vector3((c.x + 0.5) * cell, 0.0, (c.y + 0.5) * cell)
	p.y = floor_height(p)
	return p


## The walked surface under a point: the carved ground, duckboard tops and
## all; a footbridge's deck for a point on it (or a little above or below).
func floor_height(pos: Vector3) -> float:
	if not bridges.is_empty():
		var br := bridge_at(pos)
		if not br.is_empty():
			return br.deck
	return _sample(col_h, pos.x, pos.z)


func ground_height(x: float, z: float) -> float:
	return _sample(vis_h, x, z)


## The open cell a point counts as being in: its own, or (for a point up on
## the ground or in a wall) the nearest open one.
func cell_of(pos: Vector3) -> Vector2i:
	var c := super.cell_of(pos)
	if not ramps.is_empty():
		var ra := ramp_at(pos)
		if not ra.is_empty():
			var r: Dictionary = ra.ramp
			return r.cell if ra.along < RAMP_LEN * 0.6 else r.top
	if not top_cells.is_empty() and on_top(pos):
		var br := bridge_at(pos, 1.6)
		if not br.is_empty():
			# on a bridge or coming up to it in line: the nearer end
			var b: Dictionary = br.bridge
			return b.ends[0] if br.along < br.length * 0.5 else b.ends[1]
		if top_cells.has(c):
			return c
		var tb := c
		var tbd := 1e9
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector2i(dx, dz)
				if top_cells.has(n):
					var dd := Vector2((n.x + 0.5) * cell - pos.x, (n.y + 0.5) * cell - pos.z).length_squared()
					if dd < tbd:
						tbd = dd
						tb = n
		if tbd < 1e9:
			return tb
	if open_cells.has(c):
		return c
	var best := c
	var bd := 1e9
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var n := c + Vector2i(dx, dz)
			if open_cells.has(n):
				var dd := Vector2((n.x + 0.5) * cell - pos.x, (n.y + 0.5) * cell - pos.z).length_squared()
				if dd < bd:
					bd = dd
					best = n
	return best


func path_cells(a: Vector2i, b: Vector2i) -> int:
	if not _astar.has_point(idx(a)) or not _astar.has_point(idx(b)):
		return 9999
	return _astar.get_id_path(idx(a), idx(b)).size()


func path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a := idx(cell_of(from))
	var b := idx(cell_of(to))
	if not _astar.has_point(a) or not _astar.has_point(b):
		return out
	var ids := _astar.get_id_path(a, b)
	var crossing: Array[bool] = []
	for i in range(1, ids.size()):
		var prev := Vector2i(ids[i - 1] % w, ids[i - 1] / w)
		var c := Vector2i(ids[i] % w, ids[i] / w)
		# a ramp or a bridge between two path cells: go by its ends, in line with it
		for p in _crossing(prev, c):
			out.append(p)
			crossing.append(true)
		out.append(cell_center(c))
		crossing.append(false)
	# a ramp's or bridge's end already reached, or already passed (on the ramp,
	# on the deck): on to the next
	while out.size() > 1 and crossing[0]:
		var p0 := Vector2(out[0].x, out[0].z)
		var p1 := Vector2(out[1].x, out[1].z)
		var me := Vector2(from.x, from.z)
		if me.distance_to(p0) < 0.45 or (me.distance_to(p0) < 3.0 and (p1 - p0).dot(me - p0) > 0.0 and me.distance_to(p1) < p0.distance_to(p1)):
			out.pop_front()
			crossing.pop_front()
		else:
			break
	return out


## The points to go by between path cells `a` and `b` when they are joined by a
## ramp (its foot and head) or a footbridge (its deck ends); none otherwise.
func _crossing(a: Vector2i, b: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if (a - b).length_squared() <= 1:
		return out
	for r: Dictionary in ramps:
		if not r.has("foot"):
			continue
		var foot: Vector2 = r.foot
		var head: Vector2 = r.head
		var fp := Vector3(foot.x, 0, foot.y) - Vector3(Vector2(r.dir).x, 0, Vector2(r.dir).y) * 0.3
		var hp := Vector3(head.x, 0, head.y) + Vector3(Vector2(r.dir).x, 0, Vector2(r.dir).y) * 0.3
		fp.y = floor_height(fp)
		hp.y = floor_height(hp)
		if r.cell == a and r.top == b:
			out.append(fp)
			out.append(hp)
			return out
		if r.top == a and r.cell == b:
			out.append(hp)
			out.append(fp)
			return out
	for br: Dictionary in bridges:
		var e0: Vector2i = br.ends[0]
		var e1: Vector2i = br.ends[1]
		var pa: Vector3 = br.a
		var pb: Vector3 = br.b
		var u := (pb - pa).normalized()
		if e0 == a and e1 == b:
			out.append(pa - u * 0.3)
			out.append(pb + u * 0.3)
			return out
		if e1 == a and e0 == b:
			out.append(pb + u * 0.3)
			out.append(pa - u * 0.3)
			return out
	return out


func cells_far_from(c: Vector2i, min_steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: Vector2i in open_cells:
		var k := path_cells(c, n)
		if k > min_steps and k < 9999:
			out.append(n)
	return out


## What a foot comes down on at `pos`: "water" (standing water over the
## ankle), "wood" (duckboards, fire-step boards), "mud" (the trench floor),
## "earth" (firmer ground up top).
func surface_at(pos: Vector3) -> String:
	for wa: Dictionary in water:
		var r: Rect2 = wa.rect
		if r.has_point(Vector2(pos.x, pos.z)) and float(wa.level) > ground_height(pos.x, pos.z) + 0.03:
			return "water"
	if _sample(col_h, pos.x, pos.z) - _sample(vis_h, pos.x, pos.z) > 0.04:
		return "wood"
	var fx := clampi(int((pos.x - origin.x) / RES), 0, hx - 1)
	var fz := clampi(int((pos.z - origin.y) / RES), 0, hz - 1)
	return "mud" if sdf[fx + fz * hx] < 0.3 else "earth"


## Water level at a point, or -INF if there is none.
func water_level(pos: Vector3) -> float:
	for wa: Dictionary in water:
		if (wa.rect as Rect2).has_point(Vector2(pos.x, pos.z)):
			return wa.level
	return -INF


## The exit door: in the bunker portal at the end of the fire trench.
func exit_transform() -> Transform3D:
	var dir := Vector2i(1, 0)
	for l: Dictionary in landmarks:
		if l.kind == "exit":
			dir = l.dir
	var r := _rect(exit_cell)
	var inward := Vector3(-dir.x, 0, -dir.y)
	var p := Vector3(r.get_center().x, 0, r.get_center().y) + Vector3(dir.x, 0, dir.y) * (r.size.x * 0.5 - 0.3)
	p.y = floor_height(p)
	return Transform3D(Basis.looking_at(-inward, Vector3.UP), p)


## Where a soldier may stand: up top, not over the edge (TOP_CLEAR back from
## it); on a footbridge, on its deck; on a ramp, within its cut. Down in a
## trench the walls stop its capsule (ClownBrain._collide).
func keep_walkable(pos: Vector3) -> Vector3:
	if sdf.is_empty():
		return pos
	var br := bridge_at(pos)
	if not br.is_empty():
		var b: Dictionary = br.bridge
		var a: Vector3 = b.a
		var e: Vector3 = b.b
		var u := Vector2(e.x - a.x, e.z - a.z).normalized()
		var side := Vector2(-u.y, u.x)
		var limit: float = b.width * 0.5 - 0.3
		var off: float = br.across
		if absf(off) > limit:
			var fix := side * (off - signf(off) * limit)
			pos.x -= fix.x
			pos.z -= fix.y
		return pos
	var ra := ramp_at(pos)
	if not ra.is_empty():
		# on a ramp: keep within its cut
		var r: Dictionary = ra.ramp
		var u := Vector2(r.dir)
		var side := Vector2(-u.y, u.x)
		var limit: float = float(r.width) * 0.5 - 0.3
		var off: float = ra.across
		if absf(off) > limit:
			var fix := side * (off - signf(off) * limit)
			pos.x -= fix.x
			pos.z -= fix.y
		return pos
	var s := _sample(sdf, pos.x, pos.z)
	var g := Vector2(_sample(sdf, pos.x + 0.1, pos.z) - _sample(sdf, pos.x - 0.1, pos.z), _sample(sdf, pos.x, pos.z + 0.1) - _sample(sdf, pos.x, pos.z - 0.1))
	if g.length_squared() < 1e-6:
		return pos
	g = g.normalized()
	# (down in the trench the walls are solid to its capsule already: the floor
	# edge's distance field has too much noise in it to steer by)
	if s > 0.15 and s < TOP_CLEAR:
		pos.x += g.x * (TOP_CLEAR - s)
		pos.z += g.y * (TOP_CLEAR - s)
	return pos


## No roof anywhere (dugout roofs are their own collision): open sky.
func ceiling_height(_c: Vector2i) -> float:
	return 50.0


func top_height() -> float:
	return 0.0


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	if arr.is_empty():
		return 0.0
	var fx := clampf((x - origin.x) / RES, 0.0, hx - 1.001)
	var fz := clampf((z - origin.y) / RES, 0.0, hz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := ix + iz * hx
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + hx], arr[i + hx + 1], tx)
	return lerpf(a, b, tz)


## The layout as text, for tests: # earth, . trench, ~ flooded, B bay,
## D dugout, G gun pit, O observation post, S start, E exit.
func ascii() -> String:
	var lines: Array[String] = []
	for z in d:
		var s := ""
		for x in w:
			var c := Vector2i(x, z)
			if c == start_cell:
				s += "S"
			elif c == exit_cell:
				s += "E"
			elif not open_cells.has(c):
				s += "#"
			elif flooded.has(c):
				s += "~"
			else:
				s += {"fire": "B", "traverse": ".", "dugout": "D", "gunpit": "G", "op": "O", "junction": "+", "sap": ",", "stub": "s"}.get(kind[c], ".")
		lines.append(s)
	return "\n".join(lines)
