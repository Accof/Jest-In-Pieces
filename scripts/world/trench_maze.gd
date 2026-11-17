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
const FIRE_STEP_H := 0.6         ## fire step above the bay floor
const FIRE_STEP_D := 0.6         ## and how deep it is (into the front wall)

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


func is_open(c: Vector2i) -> bool:
	return open_cells.has(c)


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
	junctions.shuffle()
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
	# the room at the end: a dugout 2x2, a gun pit 3x3
	var room: Array[Vector2i] = []
	if k == "dugout" or k == "gunpit":
		var size := 2 if k == "dugout" else 3
		var side := Vector2i(dir.y, dir.x)
		var off := -(size / 2)
		for a in size:
			for b in size:
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
	_depths()
	_carve()
	_build_trench_world()


## Base floor depth per cell, by what it is, drifting gently along each trench.
func _depths() -> void:
	var base := {"fire": -1.65, "traverse": -1.8, "support": -2.1, "reserve": -2.0, "comm": -2.15,
		"sap": -1.75, "op": -1.6, "stub": -2.05, "dugout": -2.55, "gunpit": -1.15, "flood": -2.3, "junction": -2.1}
	for c: Vector2i in open_cells:
		var k: String = kind[c]
		var v: float = base.get(k, -2.0)
		v += sin(c.x * 0.37 + c.y * 0.21 + rng.randf() * 0.0) * 0.08 + sin(c.x * 0.13 - c.y * 0.29) * 0.06
		if flooded.has(c) and k != "flood":
			v -= 0.18
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
					g += 0.32 * _mound(sd, 0.1, 1.9)
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
	col_h = vis_h.duplicate()
	_bake_sky()
	_ease_fire_steps()
	_lay_duckboards()
	_lay_water()


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
## rises over 0.7 m (a slope he can climb) instead of the riser.
func _ease_fire_steps() -> void:
	for c: Vector2i in bays:
		var ze := c.y * cell + EDGE
		for iz in range(int((ze - origin.y) / RES) - 1, int((ze + 0.75 - origin.y) / RES) + 2):
			for ix in range(int((c.x * cell - origin.x) / RES), int(((c.x + 1) * cell - origin.x) / RES) + 1):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var i := ix + iz * hx
				if sdf[i] > -0.05:
					continue
				var z := origin.y + iz * RES
				var top := _sample(vis_h, origin.x + ix * RES, ze - 0.3)
				var t := clampf((z - ze) / 0.7, 0.0, 1.0)
				col_h[i] = maxf(col_h[i], top - t * FIRE_STEP_H - 0.02)


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


## The floor of an open cell: the cell, less a little at each wall, out to
## its open neighbours, and (fire bays) out over the fire step.
func _rect(c: Vector2i) -> Rect2:
	var x0 := c.x * cell
	var z0 := c.y * cell
	var x1 := x0 + cell
	var z1 := z0 + cell
	if not open_cells.has(c + Vector2i(-1, 0)):
		x0 += EDGE
	if not open_cells.has(c + Vector2i(1, 0)):
		x1 -= EDGE
	if not open_cells.has(c + Vector2i(0, -1)):
		z0 += EDGE
		if bays.has(c):
			z0 -= FIRE_STEP_D
	if not open_cells.has(c + Vector2i(0, 1)):
		z1 -= EDGE
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
		var lo := Vector2(minf(a.x, e.x), minf(a.z, e.z)) - Vector2.ONE * 0.6
		var hi := Vector2(maxf(a.x, e.x), maxf(a.z, e.z)) + Vector2.ONE * 0.6
		for iz in range(int((lo.y - origin.y) / RES), int((hi.y - origin.y) / RES) + 2):
			for ix in range(int((lo.x - origin.x) / RES), int((hi.x - origin.x) / RES) + 2):
				if ix < 0 or iz < 0 or ix >= hx or iz >= hz:
					continue
				var p := Vector2(origin.x + ix * RES, origin.y + iz * RES) - Vector2(a.x, a.z)
				var along := clampf(p.dot(u), 0.0, length)
				var across := absf(p.dot(Vector2(-u.y, u.x)))
				var beyond := absf(p.dot(u) - along)
				var top := lerpf(a.y, e.y, along / maxf(length, 0.001))
				var k := 1.0 - smoothstep(0.31, 0.5, across) * 1.0
				k *= 1.0 - smoothstep(0.0, 0.25, beyond)
				var i := ix + iz * hx
				if k > 0.0:
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
	var art := TrenchArt.new()
	art.name = "Art"
	add_child(art)
	art.build(self)


# --- queries ----------------------------------------------------------------------
func cell_center(c: Vector2i) -> Vector3:
	var p := Vector3((c.x + 0.5) * cell, 0.0, (c.y + 0.5) * cell)
	p.y = floor_height(p)
	return p


## The walked surface under a point: the carved ground, duckboard tops and all.
func floor_height(pos: Vector3) -> float:
	return _sample(col_h, pos.x, pos.z)


func ground_height(x: float, z: float) -> float:
	return _sample(vis_h, x, z)


## The open cell a point counts as being in: its own, or (for a point up on
## the ground or in a wall) the nearest open one.
func cell_of(pos: Vector3) -> Vector2i:
	var c := super.cell_of(pos)
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
	for i in range(1, ids.size()):
		out.append(cell_center(Vector2i(ids[i] % w, ids[i] / w)))
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


func keep_walkable(pos: Vector3) -> Vector3:
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
