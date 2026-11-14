class_name Maze
extends Node3D
## A procedurally generated funhouse: a grid maze of tight corridors on several
## height levels, joined by real staircases that bodies can tumble down.

const CELL := 3.0            ## metres per grid cell (corridor width, wall to wall)
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

var w := 6
var d := 6
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
	var rooms: Array = []
	for i in maxi(1, (w * d) / 18):
		var c := Vector2i(rng.randi_range(0, w - 2), rng.randi_range(0, d - 2))
		var cells: Array[Vector2i] = [c, c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(1, 1)]
		rooms.append(cells)
		links[_key(cells[0], cells[1])] = true
		links[_key(cells[0], cells[2])] = true
		links[_key(cells[1], cells[3])] = true
		links[_key(cells[2], cells[3])] = true

	# 4. Settle the heights: rooms are flat, and no open edge may step more than one level.
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

	# 5. Staircases on every open edge that changes level. A cell never gets
	#    stairs on two neighbouring sides, which would run into each other.
	for z in d:
		for x in w:
			var c := Vector2i(x, z)
			var taken: Array[Vector2i] = []
			for dir in DIRS:
				var n := c + dir
				if not in_bounds(n) or not linked(c, n) or level[idx(n)] != level[idx(c)] + 1:
					continue
				var clash := false
				for t in taken:
					if t != -dir:
						clash = true
				if clash:
					links.erase(_key(c, n))
					if not _all_reachable():
						links[_key(c, n)] = true
					else:
						continue
				taken.append(dir)
				stairs.append({low = c, high = n, dir = dir})

	_stair_at.clear()
	for s: Dictionary in stairs:
		var id := idx(s.low)
		if not _stair_at.has(id):
			_stair_at[id] = []
		_stair_at[id].append(s)

	# 6. Pathfinding graph, start and the farthest cell as the exit.
	_astar.clear()
	for z in d:
		for x in w:
			_astar.add_point(idx(Vector2i(x, z)), Vector2(x, z))
	for k: String in links:
		var parts := k.split("|")
		_astar.connect_points(int(parts[0]), int(parts[1]))
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
	return Vector2i(clampi(int(floor(pos.x / CELL)), 0, w - 1), clampi(int(floor(pos.z / CELL)), 0, d - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, level[idx(c)] * LEVEL, (c.y + 0.5) * CELL)


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


## World-space waypoints from one position to another, through open cells.
func path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ids := _astar.get_id_path(idx(cell_of(from)), idx(cell_of(to)))
	for i in range(1, ids.size()):
		out.append(cell_center(Vector2i(ids[i] % w, ids[i] / w)))
	return out


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
