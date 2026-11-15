class_name LevelArt
extends Node3D
## Dresses a trench-theme Maze: WW1 trenches open to a dusk sky above, circus
## bunkers dug in below. Everything here is visual (plus a few prop
## colliders); the maze's own collision is unchanged.

const TEX := "res://art/level/"
const LAYER_WORLD := 1
const WARM := Color(1.0, 0.68, 0.36)
const BULB := Color(1.0, 0.7, 0.45)
const MAX_SHADOW_LIGHTS := 10

var maze: Maze
var rng := RandomNumberGenerator.new()
var top := 0.0

var _st := {}                 # material key -> SurfaceTool
var _multi := {}              # mesh key -> Array[Transform3D]
var _lights: Array = []       # [light, base energy, phase, speed]
var _shadow_lights := 0
var _props: StaticBody3D
var _t := 0.0
## Concrete dieselpunk bunkers (bunker theme) or the painted circus dugouts.
var bunker_style := true
var explosive_count := 0
## Every steel door leads somewhere; a floor has at most this many.
const MAX_EVENT_DOORS := 4
var event_door_count := 0
var _route_index := {}

static var _mats := {}
static var _meshes := {}


func build(m: Maze) -> void:
	maze = m
	rng.seed = m.rng.seed ^ 0x5eed
	top = m.top_height()
	bunker_style = m.theme == "bunker"
	_props = StaticBody3D.new()
	_props.collision_layer = LAYER_WORLD
	_props.collision_mask = 0
	add_child(_props)
	for i in m.route.size():
		_route_index[m.route[i]] = i
	for z in m.d:
		for x in m.w:
			_cell_surfaces(Vector2i(x, z))
	_walls()
	_stairs()
	_outer_ground()
	if bunker_style:
		_portals()
	for z in m.d:
		for x in m.w:
			var c := Vector2i(x, z)
			if not m.is_open(c):
				continue
			if m.is_trench(c):
				_dress_trench(c)
			else:
				_dress_bunker(c)
	_rooms()
	_entrances()
	_commit()


# --- surfaces ----------------------------------------------------------------------
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uvs: Array = []) -> void:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	var t: SurfaceTool = _st[key]
	var n := (b - a).cross(d - a).normalized()
	var p := [a, b, c, d]
	if uvs.is_empty():
		uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i: int in [0, 2, 1, 0, 3, 2]:
		t.set_normal(n)
		t.set_uv(uvs[i])
		t.add_vertex(p[i])


## A vertical rectangle on the plane through `base` facing `normal`, `half` wide
## along `along`, from height y0 to y1.
func _wall_quad(key: String, base: Vector3, along: Vector3, half: float, y0: float, y1: float) -> void:
	if y1 - y0 < 0.005:
		return
	var a := Vector3(base.x, y0, base.z) - along * half
	var b := Vector3(base.x, y0, base.z) + along * half
	_quad(key, a, b, Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z))


func _box_faces(key: String, c: Vector3, s: Vector3, skip_bottom := true) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		if skip_bottom and n == Vector3.DOWN:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = n.cross(u)
		var o := c + n * h.dot(n.abs())
		var eu := u * h.dot(u.abs())
		var ev := v * h.dot(v.abs())
		_quad(key, o - eu - ev, o - eu + ev, o + eu + ev, o + eu - ev)


func _cell_surfaces(c: Vector2i) -> void:
	var m := maze
	var centre := m.cell_center(c)
	var half := Maze.CELL * 0.5
	if not m.is_open(c):
		# solid ground: only its surface shows, from the trench
		_quad("ground", Vector3(centre.x - half, top, centre.z + half), Vector3(centre.x + half, top, centre.z + half), Vector3(centre.x + half, top, centre.z - half), Vector3(centre.x - half, top, centre.z - half))
		return
	var f := centre.y
	var trench := m.is_trench(c)
	var in_room := _room_of(c) >= 0
	var floor_key := "mud" if trench else ("floor_conc" if bunker_style else "concrete")
	var wall_key := "planks_dark" if trench or not bunker_style else "wall_low"
	var ceil_key := "ceil_conc" if bunker_style else "planks_dark"
	if trench or not in_room or bunker_style:
		_quad(floor_key, centre + Vector3(-half, 0, half), centre + Vector3(half, 0, half), centre + Vector3(half, 0, -half), centre + Vector3(-half, 0, -half))
	# risers: where a linked neighbour is lower, this floor's edge shows above it
	for dir in Maze.DIRS:
		var n := c + dir
		if m.in_bounds(n) and m.linked(c, n) and m.level[m.idx(n)] < m.level[m.idx(c)]:
			var dv := Vector3(dir.x, 0, dir.y)
			_wall_quad(wall_key, centre + dv * half, Vector3(dv.z, 0, -dv.x), half, m.level[m.idx(n)] * Maze.LEVEL, f)
	if trench:
		return
	# bunker: ceiling, and the faces of the earth block above it
	var ceil := m.ceiling_height(c)
	var cc := Vector3(centre.x, ceil, centre.z)
	_quad(ceil_key, cc + Vector3(-half, 0, -half), cc + Vector3(half, 0, -half), cc + Vector3(half, 0, half), cc + Vector3(-half, 0, half))
	_quad("ground", Vector3(centre.x - half, top, centre.z + half), Vector3(centre.x + half, top, centre.z + half), Vector3(centre.x + half, top, centre.z - half), Vector3(centre.x - half, top, centre.z - half))
	if bunker_style:
		# a steel I-beam across the corridor
		var along_x := _corridor_axis(c) == Vector3.RIGHT
		var b := Basis.IDENTITY if not along_x else Basis(Vector3.UP, PI * 0.5)
		if not in_room:
			_add_multi("ibeam", Transform3D(b.scaled_local(Vector3(Maze.CELL, 0.24, 0.16)), cc + Vector3(0, -0.12, 0)))
	else:
		for k: float in [-0.75, 0.75]:
			_add_multi("beam", Transform3D(Basis.IDENTITY.scaled_local(Vector3(Maze.CELL, 0.16, 0.16)), cc + Vector3(0, -0.08, k)))
	for dir in Maze.DIRS:
		var n := c + dir
		if not (m.in_bounds(n) and m.linked(c, n)) or m.is_trench(n):
			continue
		var dv := Vector3(dir.x, 0, dir.y)
		var nc := m.ceiling_height(n)
		if nc > ceil + 0.01:
			_wall_quad("wall_conc" if bunker_style else "planks_dark", centre + dv * half, Vector3(dv.z, 0, -dv.x), half, ceil, nc)


## Which way a corridor cell runs: RIGHT (along x) or BACK (along z).
func _corridor_axis(c: Vector2i) -> Vector3:
	var x := 0
	var z := 0
	for dir in Maze.DIRS:
		if not _blocked(c, dir):
			if dir.x != 0:
				x += 1
			else:
				z += 1
	return Vector3.RIGHT if x > z else Vector3.BACK


func _walls() -> void:
	var m := maze
	var half := Maze.CELL * 0.5
	var t := Maze.WALL_T * 0.5
	for z in m.d:
		for x in m.w:
			var c := Vector2i(x, z)
			if not m.is_open(c):
				continue
			var centre := m.cell_center(c)
			var trench := m.is_trench(c)
			var ceil := top if trench else m.ceiling_height(c)
			var f := centre.y
			var style := "harlequin" if rng.randf() < 0.75 else "canvas"
			var conc := "wall_conc" if bunker_style else "planks_dark"
			for dir in Maze.DIRS:
				var n := c + dir
				var dv := Vector3(dir.x, 0, dir.y)
				var along := Vector3(-dv.z, 0, dv.x)
				if m.in_bounds(n) and m.linked(c, n):
					if not trench and m.is_trench(n):
						# lintel over the way out to the trench: its face toward the
						# trench, and its underside seen from the doorway
						var lb := m.ceiling_height(c)
						var face := centre + dv * (half + t)
						_wall_quad(conc if bunker_style else "planks", face, -along, half, lb, top)
						var u0 := centre + dv * (half - t); var u1 := centre + dv * (half + t)
						_quad("ceil_conc" if bunker_style else "planks_dark", Vector3(u0.x, lb, u0.z) + along * half, Vector3(u1.x, lb, u1.z) + along * half, Vector3(u1.x, lb, u1.z) - along * half, Vector3(u0.x, lb, u0.z) - along * half)
						_quad("ground", Vector3(u0.x, top, u0.z) - along * half, Vector3(u1.x, top, u1.z) - along * half, Vector3(u1.x, top, u1.z) + along * half, Vector3(u0.x, top, u0.z) + along * half)
					continue
				var face := centre + dv * (half - t)
				var span := half - t
				if trench:
					_wall_quad("planks", face, along, span, f, f + 2.2)
					_wall_quad("sandbags", face, along, span, f + 2.2, top)
				elif bunker_style:
					_wall_quad("wall_low", face, along, span, f, f + 0.9)
					_wall_quad("wall_conc", face, along, span, f + 0.9, ceil)
					if not _stair_side(c, dir):
						_bunker_wall_detail(c, dir, face, along, span, f, ceil)
				else:
					_wall_quad("planks_dark", face, along, span, f, f + 1.0)
					_wall_quad(style, face, along, span, f + 1.0, ceil)
				# top of the wall: ground level, plus the wall's end caps where it stops
				var a := centre + dv * (half - t); var b := centre + dv * (half + t)
				_quad("ground", Vector3(a.x, top, a.z) - along * (half + t), Vector3(b.x, top, b.z) - along * (half + t), Vector3(b.x, top, b.z) + along * (half + t), Vector3(a.x, top, a.z) + along * (half + t))
				if not m.in_bounds(n):
					_wall_quad(conc, centre + dv * (half + t), -along, half + t, 0.0, top)
				for side: float in [-1.0, 1.0]:
					var nb := c + Vector2i(int(along.x * side), int(along.z * side))
					if m.in_bounds(nb) and m.linked(c, nb):
						var e := centre + dv * half + along * side * (half + t)
						_wall_quad("planks_dark" if trench else conc, e, dv * side, t, f, top)
				if trench:
					_trench_wall_props(c, dir, face, along, span, f)


## Paint, doors and posters on a bunker wall. Most walls are bare concrete.
func _bunker_wall_detail(c: Vector2i, dir: Vector2i, face: Vector3, along: Vector3, span: float, f: float, ceil: float) -> void:
	var dv := Vector3(dir.x, 0, dir.y)
	var out := -dv
	var roll := rng.randf()
	if roll < 0.2:
		# the circus was here once: a panel of faded harlequin paint
		var p := face + out * 0.006
		var w := span - 0.12
		var y0 := f + 0.95
		var y1 := ceil - 0.3
		var a := Vector3(p.x, y0, p.z) - along * w
		var b := Vector3(p.x, y0, p.z) + along * w
		var u := w * 2.0 / 1.2
		var v := (y1 - y0) / 1.2
		_quad("harlequin_faded", a, b, Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z), [Vector2(0, v), Vector2(u, v), Vector2(u, 0), Vector2(0, 0)])
	elif roll < 0.32 and event_door_count < MAX_EVENT_DOORS:
		_steel_door(face + out * 0.004, along, out, f, rng.randf_range(-0.5, 0.5))
	elif roll < 0.38:
		_poster(face - dv * 0.012 + along * rng.randf_range(-0.6, 0.6), Basis(along, Vector3.UP, out), f + 1.55, 0.5)


## A sealed steel door set into the concrete, with a frame you can see.
func _steel_door(p: Vector3, along: Vector3, out: Vector3, f: float, offset: float) -> void:
	var c := p + along * offset
	var hw := 0.55
	var h := 2.1
	var a := Vector3(c.x, f, c.z) - along * hw
	var b := Vector3(c.x, f, c.z) + along * hw
	_quad("door", a, b, Vector3(b.x, f + h, b.z), Vector3(a.x, f + h, a.z), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var fb := Basis(along, Vector3.UP, out)
	for side: float in [-1.0, 1.0]:
		_add_multi("steel_box", Transform3D(fb.scaled_local(Vector3(0.1, h + 0.1, 0.08)), Vector3(c.x, f + (h + 0.1) * 0.5, c.z) + along * side * (hw + 0.05) + out * 0.04))
	_add_multi("steel_box", Transform3D(fb.scaled_local(Vector3(hw * 2 + 0.2, 0.1, 0.08)), Vector3(c.x, f + h + 0.05, c.z) + out * 0.04))
	_add_multi("steel_box", Transform3D(fb.scaled_local(Vector3(0.05, 0.3, 0.06)), Vector3(c.x, f + 1.0, c.z) + along * (hw - 0.15) + out * 0.03))
	var door := EventDoor.new()
	add_child(door)
	door.position = Vector3(c.x, f, c.z)
	door.basis = fb
	event_door_count += 1


func _stairs() -> void:
	var m := maze
	var tread := Maze.STAIR_RUN / Maze.STEPS
	var rise := Maze.LEVEL / Maze.STEPS
	for s: Dictionary in m.stairs:
		var base := m.level[m.idx(s.low)] * Maze.LEVEL
		var dir := Vector3(s.dir.x, 0, s.dir.y)
		var side := Vector3(dir.z, 0, -dir.x)
		var edge := m.cell_center(s.low) + dir * Maze.CELL * 0.5
		edge.y = base
		var key := "floor_conc" if bunker_style and not m.is_trench(s.low) else "planks_dark"
		for i in Maze.STEPS - 1:
			var near := (Maze.STEPS - 1 - i) * tread
			var centre := edge - dir * near * 0.5 + Vector3.UP * (i + 1) * rise * 0.5
			var size := (dir.abs() * near + side.abs() * Maze.STAIR_WIDTH + Vector3.UP * (i + 1) * rise)
			_box_faces(key, centre, size)
		if key == "floor_conc":
			# a steel handrail down one side
			var rail_side := side * (Maze.STAIR_WIDTH * 0.5 + 0.08)
			var top_p := edge + rail_side + Vector3.UP * (Maze.LEVEL + 0.9)
			var bot_p := edge - dir * Maze.STAIR_RUN + rail_side + Vector3.UP * 0.9
			var mid := (top_p + bot_p) * 0.5
			var len := top_p.distance_to(bot_p)
			var y := (top_p - bot_p).normalized()
			var x := side.normalized()
			_add_multi("pipe", Transform3D(Basis(x, y, x.cross(y)).scaled_local(Vector3(0.6, len, 0.6)), mid))
			for k: float in [0.1, 0.9]:
				var q := bot_p.lerp(top_p, k)
				_add_multi("pipe", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.5, 0.9, 0.5)), q + Vector3.DOWN * 0.45))


func _outer_ground() -> void:
	var m := maze
	var W := m.w * Maze.CELL
	var D := m.d * Maze.CELL
	var R := 70.0
	for r: Array in [[-R, -R, W + R, 0.0], [-R, D, W + R, D + R], [-R, 0.0, 0.0, D], [W, 0.0, W + R, D]]:
		_quad("ground", Vector3(r[0], top, r[3]), Vector3(r[2], top, r[3]), Vector3(r[2], top, r[1]), Vector3(r[0], top, r[1]))
	# barbed-wire pickets and coils dotted across no man's land
	for i in 46:
		var p := Vector3(rng.randf_range(-R * 0.6, W + R * 0.6), top, rng.randf_range(-R * 0.6, D + R * 0.6))
		if p.x > -2 and p.x < W + 2 and p.z > -2 and p.z < D + 2:
			continue
		var yaw := rng.randf() * TAU
		_wire_run(p, Vector3(cos(yaw), 0, sin(yaw)), rng.randf_range(4.0, 9.0))
	for i in 18:
		var p := Vector3(rng.randf_range(-R * 0.7, W + R * 0.7), top, rng.randf_range(-R * 0.7, D + R * 0.7))
		if p.x > -3 and p.x < W + 3 and p.z > -3 and p.z < D + 3:
			continue
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.5))
		_add_multi("post", Transform3D(tilt.scaled_local(Vector3(0.14, rng.randf_range(1.6, 3.2), 0.14)), p + Vector3.UP * 0.6))


# --- trench dressing ----------------------------------------------------------------
func _trench_wall_props(c: Vector2i, dir: Vector2i, face: Vector3, along: Vector3, span: float, f: float) -> void:
	var dv := Vector3(dir.x, 0, dir.y)
	var basis_out := Basis(along, Vector3.UP, -dv)        # +Z points out of the wall
	# revetment posts holding the planks back
	for k: float in [-1.0, 0.0, 1.0]:
		var p := face - dv * 0.07 + along * k * (span - 0.08)
		var h := top - f + 0.25
		_add_multi("post", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.14, h, 0.14)), Vector3(p.x, f + h * 0.5, p.z)))
	# sandbags along the lip, two rows
	var lip := face + dv * (Maze.WALL_T * 0.5)
	for row in 2:
		var n := 5
		for i in n:
			var tt := (i + 0.5 * (row % 2)) / n - 0.5
			var p := Vector3(lip.x, top + 0.07 + row * 0.13, lip.z) + along * tt * Maze.CELL - dv * 0.05 + dv * row * 0.08
			var yaw := Basis(Vector3.UP, rng.randf_range(-0.12, 0.12))
			_add_multi("sandbag", Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)) * yaw, p))
	# barbed wire on the far side of the lip
	if rng.randf() < 0.55:
		_wire_run(Vector3(lip.x, top, lip.z) + dv * 0.55 - along * span, along, span * 2.0)
	# bunting strung along the wall
	if rng.randf() < 0.35:
		_bunting(Vector3(face.x, f + 2.45, face.z) - dv * 0.05 - along * span, Vector3(face.x, f + 2.45, face.z) - dv * 0.05 + along * span)
	# a poster pinned to the boards
	if rng.randf() < 0.18:
		_poster(face - dv * 0.012 + along * rng.randf_range(-0.6, 0.6), basis_out, f + 1.55, 0.55)
	# a lantern hung on a post
	if rng.randf() < 0.22:
		var p := face - dv * 0.22 + along * (span - 0.08)
		_lantern(Vector3(p.x, f + 2.05, p.z), 0.9, 6.0)


func _dress_trench(c: Vector2i) -> void:
	var m := maze
	var centre := m.cell_center(c)
	# duckboards along every same-level way out, and across the middle
	var parts := [[centre, Vector3(1.2, 0.06, 1.2)]]
	for dir in Maze.DIRS:
		var n := c + dir
		if m.in_bounds(n) and m.linked(c, n) and m.level[m.idx(n)] == m.level[m.idx(c)]:
			var dv := Vector3(dir.x, 0, dir.y)
			var len := Maze.CELL * 0.5 - 0.6
			parts.append([centre + dv * (0.6 + len * 0.5), dv.abs() * len + Vector3(1.0, 0.06, 1.0) * (Vector3.ONE - dv.abs())])
	for p: Array in parts:
		var s: Vector3 = p[1]
		var length_axis := Vector3.RIGHT if s.x >= s.z else Vector3.BACK
		var b := Basis(length_axis, Vector3.UP, length_axis.cross(Vector3.UP))
		var size := Vector3(maxf(s.x, s.z), s.y, minf(s.x, s.z))
		_add_multi("duckboard", Transform3D(b.scaled_local(size), p[0] + Vector3.UP * 0.035))
	# strings of bulbs across the trench now and then
	if rng.randf() < 0.2:
		var ax := Vector3.RIGHT if rng.randf() < 0.5 else Vector3.BACK
		_string_lights(centre + Vector3.UP * 2.7 - ax * 1.3, centre + Vector3.UP * 2.7 + ax * 1.3, 0.35)
	# camouflage netting over the odd stretch
	if rng.randf() < 0.18:
		_camo_net(centre, top - 0.1)
	# clutter in the corners
	_corner_clutter(c, true)


# --- bunker dressing ------------------------------------------------------------
func _dress_bunker(c: Vector2i) -> void:
	var m := maze
	var centre := m.cell_center(c)
	var ceil := m.ceiling_height(c)
	var half := Maze.CELL * 0.5
	var in_room := _room_of(c) >= 0
	if not bunker_style:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				if not _blocked(c, Vector2i(int(sx), 0)) and not _blocked(c, Vector2i(0, int(sz))):
					continue
				var p := centre + Vector3(sx * (half - 0.22), 0, sz * (half - 0.22))
				_add_multi("post", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.16, ceil - centre.y, 0.16)), Vector3(p.x, (centre.y + ceil) * 0.5, p.z)))
		if not in_room and rng.randf() < 0.7:
			_hanging_lantern(Vector3(centre.x + rng.randf_range(-0.4, 0.4), ceil, centre.z + rng.randf_range(-0.4, 0.4)), 1.5, 5.5)
		if not in_room:
			_corner_clutter(c, false)
		return
	if in_room:
		return
	var axis := _corridor_axis(c)
	var side := Vector3(axis.z, 0, axis.x)
	var straight := _blocked(c, Vector2i(int(side.x), int(side.z))) and _blocked(c, -Vector2i(int(side.x), int(side.z)))
	# pipes and a cable run along one side of straight corridors
	if straight:
		var b := Basis(Vector3.BACK, PI * 0.5) if axis == Vector3.RIGHT else Basis(Vector3.RIGHT, PI * 0.5)
		var wall := centre + side * (half - Maze.WALL_T * 0.5 - 0.14)
		_add_multi("pipe", Transform3D(b.scaled_local(Vector3(1.1, Maze.CELL, 1.1)), Vector3(wall.x, ceil - 0.2, wall.z)))
		_add_multi("pipe", Transform3D(b.scaled_local(Vector3(0.7, Maze.CELL, 0.7)), Vector3(wall.x, ceil - 0.42, wall.z) + side * 0.03))
		_add_multi("cable", Transform3D(b.scaled_local(Vector3(1, Maze.CELL, 1)), Vector3(wall.x, ceil - 0.6, wall.z) + side * 0.06))
	# a caged bulb every other cell along the route; side rooms most of the time
	var ri: int = _route_index.get(c, -1)
	var lit := (ri >= 0 and ri % 2 == 0) or (ri < 0 and rng.randf() < 0.6)
	if lit:
		_bulb(Vector3(centre.x, ceil, centre.z) + axis * rng.randf_range(-0.3, 0.3))
	# a red fuel drum now and then (never right at the start)
	if bunker_style and (ri < 0 or ri >= 4) and rng.randf() < 0.28:
		_explosive(c)
	_corner_clutter(c, false)
	if m.side_cells.has(c):
		_corner_clutter(c, false)
		_corner_clutter(c, false)


func _rooms() -> void:
	var m := maze
	for ri in m.rooms.size():
		var cells: Array = m.rooms[ri]
		var a: Vector2i = cells[0]
		var trench := m.is_trench(a)
		var lo := m.cell_center(a)
		var mid := lo + Vector3(Maze.CELL * 0.5, 0, Maze.CELL * 0.5)
		if trench:
			for c: Vector2i in cells:
				_corner_clutter(c, true)
				_corner_clutter(c, true)
			_add_multi("wheel", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, 1.35), _free_spot(cells, 0.5) + Vector3.UP * 0.45))
			continue
		var ceil := 99.0
		for c: Vector2i in cells:
			ceil = minf(ceil, m.ceiling_height(c))
		var kind := ri % 3
		if bunker_style:
			# a concrete column holding up the middle, steel beams off it
			_box_faces("wall_conc", Vector3(mid.x, (lo.y + ceil) * 0.5, mid.z), Vector3(0.55, ceil - lo.y, 0.55))
			_collider(Vector3(0.55, ceil - lo.y, 0.55), Transform3D(Basis.IDENTITY, Vector3(mid.x, (lo.y + ceil) * 0.5, mid.z)))
			for b: Basis in [Basis.IDENTITY, Basis(Vector3.UP, PI * 0.5)]:
				_add_multi("ibeam", Transform3D(b.scaled_local(Vector3(Maze.CELL * 2.0, 0.26, 0.18)), Vector3(mid.x, ceil - 0.13, mid.z)))
			for c: Vector2i in cells:
				if rng.randf() < 0.3:
					_explosive(c)
			_bulb(Vector3(mid.x - 1.4, ceil, mid.z - 1.4))
			_bulb(Vector3(mid.x + 1.4, ceil, mid.z + 1.4))
			if kind == 1:
				# the mess: what is left of the circus lives here
				var y := lo.y + 0.004
				var hw := Maze.CELL - 0.15
				_quad("sunburst_faded", Vector3(mid.x - hw, y, mid.z + hw), Vector3(mid.x + hw, y, mid.z + hw), Vector3(mid.x + hw, y, mid.z - hw), Vector3(mid.x - hw, y, mid.z - hw))
				_bunting(Vector3(mid.x - 2.6, ceil - 0.3, mid.z - 2.6), Vector3(mid.x, ceil - 0.25, mid.z))
		else:
			var half := Maze.CELL
			var y := lo.y + 0.004
			_quad("sunburst", Vector3(mid.x - half, y, mid.z + half), Vector3(mid.x + half, y, mid.z + half), Vector3(mid.x + half, y, mid.z - half), Vector3(mid.x - half, y, mid.z - half),
				[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			_hanging_lantern(Vector3(mid.x, ceil, mid.z), 2.2, 7.5)
			_string_lights(Vector3(mid.x - 2.6, ceil - 0.12, mid.z - 2.6), Vector3(mid.x + 2.6, ceil - 0.12, mid.z - 2.6), 0.25)
			_string_lights(Vector3(mid.x + 2.6, ceil - 0.12, mid.z + 2.6), Vector3(mid.x - 2.6, ceil - 0.12, mid.z + 2.6), 0.25)
		match kind:
			0:   # dormitory
				for c: Vector2i in cells:
					var spot := _wall_spot(c, 1.0)
					if spot.is_empty():
						continue
					_bunk(spot.pos, spot.basis)
			1:   # mess: a table, a gramophone on a circus drum
				_table(mid + Vector3(0.9, 0, 0.9))
				var g := _free_spot(cells, 0.6)
				_drum(g)
				_gramophone(g + Vector3.UP * 0.62)
				for c: Vector2i in cells:
					_corner_clutter(c, false)
			_:   # stores
				for c: Vector2i in cells:
					_corner_clutter(c, false)
					_corner_clutter(c, false)
					var spot := _wall_spot(c, 0.4)
					if not spot.is_empty():
						_shelf(spot.pos, spot.basis)


func _entrances() -> void:
	var m := maze
	var done := {}
	for z in m.d:
		for x in m.w:
			var high := Vector2i(x, z)
			if not m.is_open(high) or not m.is_trench(high):
				continue
			for dir in Maze.DIRS:
				var low := high - dir
				if not m.in_bounds(low) or not m.linked(high, low) or m.is_trench(low) or done.has(low):
					continue
				done[low] = true
				_entrance(low, high, dir)


## The way into the bunker, seen from the trench: a frame and a clown's face.
func _entrance(low: Vector2i, high: Vector2i, dir: Vector2i) -> void:
	var m := maze
	var dv := Vector3(dir.x, 0, dir.y)
	var along := Vector3(-dv.z, 0, dv.x)
	var edge := m.cell_center(low) + dv * Maze.CELL * 0.5
	var tf := minf(m.level[m.idx(high)], m.level[m.idx(low)]) * Maze.LEVEL
	var lb := m.ceiling_height(low)
	var front := Vector3(edge.x, 0, edge.z) + dv * (Maze.WALL_T * 0.5 + 0.06)
	var w := Maze.STAIR_WIDTH * 0.5 + 0.12
	if bunker_style:
		# a cast concrete portal with a steel lintel
		for side: float in [-1.0, 1.0]:
			var p := front + along * side * (w + 0.25)
			_box_faces("wall_conc", Vector3(p.x, (tf + lb + 0.4) * 0.5, p.z) + dv * 0.1, Vector3(0.5, lb + 0.4 - tf, 0.5) * (Vector3.ONE - dv.abs()) + dv.abs() * 0.5)
			_collider(Vector3(0.5, lb + 0.4 - tf, 0.5), Transform3D(Basis.IDENTITY, Vector3(p.x, (tf + lb + 0.4) * 0.5, p.z) + dv * 0.1))
			_bulb(Vector3(p.x, tf + 2.25, p.z) + dv * 0.45, true)
		_add_multi("ibeam", Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)).scaled_local(Vector3(w * 2.0 + 1.2, 0.32, 0.3)), Vector3(front.x, lb + 0.12, front.z) + dv * 0.12))
	else:
		for side: float in [-1.0, 1.0]:
			var p := front + along * side * w
			_add_multi("beam_v", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.2, lb - tf + 0.2, 0.2)), Vector3(p.x, (tf + lb) * 0.5, p.z)))
			_lantern(Vector3(p.x, tf + 1.9, p.z) + dv * 0.2 + along * side * 0.18, 1.6, 6.0)
		_add_multi("beam_v", Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)).scaled_local(Vector3(w * 2.0 + 0.4, 0.24, 0.22)), Vector3(front.x, lb + 0.05, front.z)))
		_bunting(Vector3(front.x, lb + 0.2, front.z) - along * (w + 0.6) + dv * 0.1, Vector3(front.x, lb + 0.2, front.z) + along * (w + 0.6) + dv * 0.1)
	# the clown over the door
	var head := _clown_head()
	if head:
		var mi := MeshInstance3D.new()
		mi.mesh = head
		mi.transform = Transform3D(Basis(-along, Vector3.UP, dv).scaled_local(Vector3.ONE * 2.3) * Basis(Vector3.RIGHT, -0.15), Vector3(front.x, lb + 0.62, front.z) + dv * 0.2)
		add_child(mi)


## Concrete pillars and a steel header at every opening between bunker cells:
## the frames you see receding down a corridor.
func _portals() -> void:
	var m := maze
	var half := Maze.CELL * 0.5
	for z in m.d:
		for x in m.w:
			var c := Vector2i(x, z)
			if not m.is_open(c) or m.is_trench(c):
				continue
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n := c + dir
				if not m.in_bounds(n) or not m.linked(c, n) or m.is_trench(n):
					continue
				var rc := _room_of(c)
				if rc >= 0 and rc == _room_of(n):
					continue
				var dv := Vector3(dir.x, 0, dir.y)
				var along := Vector3(-dv.z, 0, dv.x)
				var edge := m.cell_center(c) + dv * half
				var y0 := minf(m.level[m.idx(c)], m.level[m.idx(n)]) * Maze.LEVEL
				var y1 := minf(m.ceiling_height(c), m.ceiling_height(n))
				for side: float in [-1.0, 1.0]:
					var p := edge + along * side * (half - 0.2)
					var size := along.abs() * 0.4 + dv.abs() * 0.55 + Vector3.UP * (y1 - y0)
					var ctr := Vector3(p.x, (y0 + y1) * 0.5, p.z)
					_box_faces("wall_conc", ctr, size)
					_collider(size, Transform3D(Basis.IDENTITY, ctr))
				var hb := Basis(along, Vector3.UP, along.cross(Vector3.UP))
				_add_multi("ibeam", Transform3D(hb.scaled_local(Vector3(Maze.CELL, 0.34, 0.3)), Vector3(edge.x, y1 - 0.17, edge.z)))


# --- props -------------------------------------------------------------------------
func _corner_clutter(c: Vector2i, trench: bool) -> void:
	if rng.randf() > (0.55 if trench else 0.45):
		return
	var spot := _corner_spot(c)
	if spot.is_empty():
		return
	var p: Vector3 = spot.pos
	var roll := rng.randf()
	if roll < 0.5:
		var s := rng.randf_range(0.55, 0.75)
		_crate(p, s, rng.randf_range(-0.3, 0.3))
		if rng.randf() < 0.45:
			_crate(p + Vector3.UP * s + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)), s * 0.8, rng.randf_range(-0.6, 0.6))
	elif roll < 0.72 and (trench or bunker_style):
		_barrel(p)
		if rng.randf() < 0.4:
			_barrel(p + Vector3(rng.randf_range(-0.1, 0.1), 0, 0) + (maze.cell_center(c) - p).normalized() * 0.62)
	elif roll < 0.8 and not bunker_style:
		_drum(p)
	elif roll < 0.84:
		_drum(p)      # the odd circus drum, even down here
	elif trench or bunker_style:
		for i in 6:   # a heap of sandbags
			var q := p + Vector3(rng.randf_range(-0.3, 0.3), 0.08 + (i / 3) * 0.13, rng.randf_range(-0.3, 0.3))
			_add_multi("sandbag", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q))
	else:
		_crate(p, 0.5, 0.0)
		_lantern(p + Vector3.UP * 0.62, 0.9, 4.0)


## A red fuel drum in a free corner: shoot it to blow up anyone near it.
func _explosive(c: Vector2i) -> void:
	var spot := _corner_spot(c)
	if spot.is_empty():
		return
	var b := ExplosiveBarrel.new()
	add_child(b)
	b.position = spot.pos
	b.rotation.y = rng.randf() * TAU
	explosive_count += 1


func _barrel(p: Vector3) -> void:
	_add_multi("barrel", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3.UP * 0.44))
	_collider(Vector3(0.58, 0.88, 0.58), Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.44))


## A bare bulb in a wire cage, hung from the ceiling on its flex.
func _bulb(ceiling_point: Vector3, wall_mounted := false) -> void:
	var drop := 0.0 if wall_mounted else rng.randf_range(0.3, 0.55)
	if not wall_mounted:
		_add_multi("rail_v", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.012, drop, 0.012)), ceiling_point + Vector3.DOWN * drop * 0.5))
	var p := ceiling_point + Vector3.DOWN * (drop + 0.1)
	var dead := not wall_mounted and rng.randf() < 0.12
	_add_multi("cage", Transform3D(Basis.IDENTITY, p))
	_add_multi("bulb_dead" if dead else "bulb_big", Transform3D(Basis.IDENTITY, p))
	if dead:
		return
	var l := OmniLight3D.new()
	l.position = p + Vector3.DOWN * 0.05
	l.light_color = BULB
	l.light_energy = 3.2
	l.omni_range = 8.0
	l.omni_attenuation = 1.6
	l.light_volumetric_fog_energy = 2.5
	l.light_size = 0.06
	l.shadow_enabled = true
	l.shadow_bias = 0.06
	l.distance_fade_enabled = true
	l.distance_fade_begin = 28.0
	l.distance_fade_length = 8.0
	l.distance_fade_shadow = 16.0
	add_child(l)
	var bad := rng.randf() < 0.15
	_lights.append([l, l.light_energy, rng.randf() * 100.0, rng.randf_range(6.0, 11.0) * (3.0 if bad else 1.0)])


func _corner_spot(c: Vector2i) -> Dictionary:
	var m := maze
	var centre := m.cell_center(c)
	var options := []
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var a := Vector2i(sx, 0); var b := Vector2i(0, sz)
			if _blocked(c, a) and _blocked(c, b) and not _stair_side(c, a) and not _stair_side(c, b):
				options.append(centre + Vector3(sx * 0.92, 0, sz * 0.92))
	if options.is_empty():
		return {}
	var key := "%d,%d" % [c.x, c.y]
	var used: Array = _used.get(key, [])
	options = options.filter(func(o: Vector3) -> bool: return not used.has(o))
	if options.is_empty():
		return {}
	var p: Vector3 = options[rng.randi() % options.size()]
	used.append(p)
	_used[key] = used
	return {pos = p}
var _used := {}


## Against the middle of a blank wall, facing into the cell, or {}.
func _wall_spot(c: Vector2i, depth: float) -> Dictionary:
	var m := maze
	var centre := m.cell_center(c)
	var dirs := Maze.DIRS.duplicate()
	dirs.shuffle()
	for dir: Vector2i in dirs:
		if not _blocked(c, dir) or _stair_side(c, dir):
			continue
		var dv := Vector3(dir.x, 0, dir.y)
		var key := "w%d,%d,%d,%d" % [c.x, c.y, dir.x, dir.y]
		if _used.has(key):
			continue
		_used[key] = true
		var along := Vector3(-dv.z, 0, dv.x)
		return {pos = centre + dv * (Maze.CELL * 0.5 - Maze.WALL_T * 0.5 - depth * 0.5 - 0.03), basis = Basis(along, Vector3.UP, -dv)}
	return {}


func _free_spot(cells: Array, depth: float) -> Vector3:
	for c: Vector2i in cells:
		var s := _corner_spot(c)
		if not s.is_empty():
			return s.pos
	return maze.cell_center(cells[0])


func _blocked(c: Vector2i, dir: Vector2i) -> bool:
	var n := c + dir
	return not maze.in_bounds(n) or not maze.linked(c, n)


func _stair_side(c: Vector2i, dir: Vector2i) -> bool:
	for s: Dictionary in maze.stairs:
		if s.low == c and s.dir == dir:
			return true
	return false


func _room_of(c: Vector2i) -> int:
	for i in maze.rooms.size():
		if maze.rooms[i].has(c):
			return i
	return -1


func _crate(p: Vector3, s: float, yaw: float) -> void:
	_add_multi("crate", Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3.ONE * s), p + Vector3.UP * s * 0.5))
	_collider(Vector3.ONE * s, Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * s * 0.5))


func _drum(p: Vector3) -> void:
	_add_multi("drum", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3.UP * 0.3))
	_collider(Vector3(0.7, 0.6, 0.7), Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.3))


func _bunk(p: Vector3, b: Basis) -> void:
	# metal frame, two mattresses
	var L := 1.9; var W := 0.85
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_multi("rail_v", Transform3D(b.scaled_local(Vector3(0.04, 1.7, 0.04)), p + b * Vector3(sx * L * 0.5, 0.85, sz * W * 0.5)))
	for y: float in [0.35, 1.25]:
		_add_multi("mattress", Transform3D(b.scaled_local(Vector3(L, 0.14, W)), p + b * Vector3(0, y, 0)))
		for sz: float in [-1.0, 1.0]:
			_add_multi("rail_h", Transform3D(b.scaled_local(Vector3(L, 0.04, 0.04)), p + b * Vector3(0, y - 0.08, sz * W * 0.5)))
	_collider(Vector3(L, 1.7, W), Transform3D(b, p + Vector3.UP * 0.85))


func _table(p: Vector3) -> void:
	_add_multi("plank_box", Transform3D(Basis.IDENTITY.scaled_local(Vector3(1.6, 0.06, 0.9)), p + Vector3.UP * 0.76))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_multi("post", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.07, 0.74, 0.07)), p + Vector3(sx * 0.7, 0.37, sz * 0.38)))
	_collider(Vector3(1.6, 0.8, 0.9), Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.4))
	_lantern(p + Vector3(0.3, 0.79, 0.1), 1.1, 5.0)
	for i in 2:
		_add_multi("plank_box", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.4, 0.45, 0.4)), p + Vector3(-0.4 + i * 0.8, 0.225, 0.75)))


func _shelf(p: Vector3, b: Basis) -> void:
	for y: float in [0.4, 0.95, 1.5]:
		_add_multi("plank_box", Transform3D(b.scaled_local(Vector3(1.8, 0.04, 0.4)), p + b * Vector3(0, y, 0)))
		for i in rng.randi_range(1, 3):
			var s := rng.randf_range(0.22, 0.32)
			_add_multi("crate", Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled_local(Vector3.ONE * s), p + b * Vector3(rng.randf_range(-0.7, 0.7), y + 0.02 + s * 0.5, 0)))
	for sx: float in [-1.0, 1.0]:
		_add_multi("post", Transform3D(b.scaled_local(Vector3(0.06, 1.9, 0.4)), p + b * Vector3(sx * 0.9, 0.95, 0)))
	_collider(Vector3(1.9, 1.9, 0.4), Transform3D(b, p + Vector3.UP * 0.95))


func _gramophone(p: Vector3) -> void:
	_add_multi("plank_box", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.36, 0.16, 0.36)), p + Vector3.UP * 0.08))
	var horn := Basis(Vector3.RIGHT, -0.9) * Basis(Vector3.UP, rng.randf() * TAU)
	_add_multi("horn", Transform3D(horn, p + Vector3(0, 0.42, 0.12)))


func _camo_net(centre: Vector3, y: float) -> void:
	var h := Maze.CELL * 0.55
	var n := 5
	for i in n:
		for j in n:
			var corners := []
			for k in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var u: float = k.x / n * 2.0 - 1.0
				var v: float = k.y / n * 2.0 - 1.0
				var sag := (1.0 - u * u) * (1.0 - v * v) * 0.45
				corners.append(Vector3(centre.x + u * h, y - sag, centre.z + v * h))
			var uvs := [Vector2(i, j + 1) / n, Vector2(i + 1, j + 1) / n, Vector2(i + 1, j) / n, Vector2(i, j) / n]
			_quad("camonet", corners[0], corners[1], corners[2], corners[3], uvs)


func _poster(p: Vector3, b: Basis, y: float, w: float) -> void:
	var h := w * 1.5
	var right := b.x; var out := b.z
	var tilt := Basis(out, rng.randf_range(-0.06, 0.06))
	right = tilt * right
	var upv := tilt * Vector3.UP
	var c := Vector3(p.x, y, p.z) + out * 0.004
	_quad("poster", c - right * w * 0.5 - upv * h * 0.5, c + right * w * 0.5 - upv * h * 0.5, c + right * w * 0.5 + upv * h * 0.5, c - right * w * 0.5 + upv * h * 0.5,
		[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)])


func _bunting(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var n := int(length / 0.32)
	var along := (b - a).normalized()
	for i in n:
		var t0 := float(i) / n; var t1 := float(i + 1) / n
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sin(t0 * PI) * 0.18
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sin(t1 * PI) * 0.18
		var tip := (p0 + p1) * 0.5 + Vector3.DOWN * 0.26
		var mid := (p0 + p1) * 0.5
		_quad("pennant", p0, p1, p1 + (tip - mid) * 0.0 + Vector3.DOWN * 0.0 + (tip - p1) * 1.0, p0 + (tip - p0) * 1.0,
			[Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1), Vector2(0.5, 1)])


func _wire_run(start: Vector3, along: Vector3, length: float) -> void:
	var n := maxi(1, int(round(length / 1.5)))
	var side := along.cross(Vector3.UP)
	for i in n + 1:
		var p := start + along * (length * i / n)
		for s: float in [-1.0, 1.0]:   # X-shaped picket
			_add_multi("picket", Transform3D(Basis(along, s * 0.45).scaled_local(Vector3(0.05, 1.1, 0.05)), p + Vector3.UP * 0.45 + side * 0.0))
	var segs := maxi(1, int(round(length / 3.0)))
	for i in segs:
		var p := start + along * (length * (i + 0.5) / segs) + Vector3.UP * 0.35
		_add_multi("coil", Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)).scaled_local(Vector3(length / segs / 3.0, 1, 1)), p))


func _string_lights(a: Vector3, b: Vector3, sag: float) -> void:
	var n := maxi(3, int(a.distance_to(b) / 0.45))
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * sag
		_add_multi("bulb", Transform3D(Basis.IDENTITY, p))
	var mid := a.lerp(b, 0.5) + Vector3.DOWN * (sag + 0.1)
	_light(mid, 0.9, 4.0, false)


func _lantern(p: Vector3, energy: float, range_: float) -> void:
	_add_multi("lantern", Transform3D(Basis.IDENTITY, p))
	_add_multi("lantern_glass", Transform3D(Basis.IDENTITY, p))
	_light(p + Vector3.UP * 0.02, energy, range_, true)


func _hanging_lantern(ceiling_point: Vector3, energy: float, range_: float) -> void:
	var drop := 0.55
	_add_multi("rail_v", Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.012, drop, 0.012)), ceiling_point + Vector3.DOWN * drop * 0.5))
	_lantern(ceiling_point + Vector3.DOWN * (drop + 0.12), energy, range_)


func _light(p: Vector3, energy: float, range_: float, may_shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = WARM
	l.light_energy = energy
	l.omni_range = range_
	l.omni_attenuation = 1.4
	if may_shadow and _shadow_lights < MAX_SHADOW_LIGHTS and rng.randf() < 0.5:
		l.shadow_enabled = true
		_shadow_lights += 1
	add_child(l)
	_lights.append([l, energy, rng.randf() * 100.0, rng.randf_range(6.0, 11.0)])


func _collider(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	_props.add_child(cs)


# --- lights flicker ---------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	for e: Array in _lights:
		var l: OmniLight3D = e[0]
		var ph: float = e[2]
		var sp: float = e[3]
		var f := 0.88 + 0.08 * sin(_t * sp + ph) + 0.05 * sin(_t * sp * 2.7 + ph * 1.3)
		if fposmod(_t * 0.37 + ph, 9.0) < 0.12:     # the odd stutter
			f *= 0.45
		l.light_energy = e[1] * f


# --- building the meshes ------------------------------------------------------------
func _add_multi(key: String, xf: Transform3D) -> void:
	if not _multi.has(key):
		_multi[key] = []
	_multi[key].append(xf)


func _commit() -> void:
	for key: String in _st:
		var mi := MeshInstance3D.new()
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _mat(key)
		if key in ["camonet", "pennant", "harlequin_faded", "door", "poster", "sunburst_faded", "sunburst"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		add_child(mi)
	for key: String in _multi:
		var xfs: Array = _multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(key)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if key in ["bulb", "lantern_glass", "coil", "rail_v", "rail_h", "bulb_big", "bulb_dead", "cable"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


static func _tex(name: String) -> Texture2D:
	return load(TEX + name + ".png")


## Materials: tiling ones are mapped in world space so every surface lines up.
static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var tiling := {"planks": [2.0, 0.85], "planks_dark": [2.0, 0.85], "sandbags": [2.0, 0.95], "harlequin": [2.0, 0.7],
		"canvas": [2.0, 0.9], "mud": [2.5, 1.0], "ground": [4.0, 1.0], "concrete": [3.0, 0.85], "metal": [1.0, 0.55],
		"wall_conc": [2.0, 0.9], "wall_low": [2.0, 0.7], "floor_conc": [2.0, 0.8], "ceil_conc": [2.0, 0.95]}
	if tiling.has(key):
		var base: String = "wall_conc" if key == "ceil_conc" else key
		m.albedo_texture = _tex(base)
		m.normal_enabled = true
		m.normal_texture = _tex(base + "_n")
		m.roughness = tiling[key][1]
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / float(tiling[key][0])
		if key.begins_with("planks"):
			m.uv1_scale = Vector3(0.22, 0.5, 0.22)      # boards run long
		if key == "ceil_conc":
			m.albedo_color = Color(0.6, 0.58, 0.55)
		if key in ["wall_conc", "wall_low", "floor_conc"]:
			m.roughness = 1.0
			m.roughness_texture = _tex(key + "_r")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if key == "mud" or key == "ground":
			m.roughness = 1.0
			m.roughness_texture = _tex(key + "_r")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if key == "planks_dark":
			m.albedo_color = Color(0.75, 0.75, 0.75)
	else:
		match key:
			"sunburst":
				m.albedo_texture = _tex("sunburst")
				m.roughness = 0.8
			"sunburst_faded":
				m.albedo_texture = _tex("sunburst_faded")
				m.roughness = 0.75
			"harlequin_faded":
				m.albedo_texture = _tex("harlequin_faded")
				m.normal_enabled = true
				m.normal_texture = _tex("harlequin_faded_n")
				m.roughness = 0.85
			"door":
				m.albedo_texture = _tex("door")
				m.normal_enabled = true
				m.normal_texture = _tex("door_n")
				m.metallic = 0.5
				m.roughness = 0.6
			"steel":
				m.albedo_texture = _tex("metal")
				m.normal_enabled = true
				m.normal_texture = _tex("metal_n")
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.albedo_color = Color(0.7, 0.72, 0.68)
				m.metallic = 0.65
				m.roughness = 0.55
			"barrel":
				m.albedo_texture = _tex("metal")
				m.albedo_color = Color(0.55, 0.62, 0.5)
				m.uv1_scale = Vector3(2, 1, 1)
				m.metallic = 0.5
				m.roughness = 0.6
			"bulb_hot":
				m.albedo_color = Color(1.0, 0.8, 0.55)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.7, 0.4)
				m.emission_energy_multiplier = 9.0
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"bulb_off":
				m.albedo_color = Color(0.3, 0.28, 0.25)
				m.metallic = 0.2
				m.roughness = 0.2
			"poster":
				m.albedo_texture = _tex("poster")
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.roughness = 0.9
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"pennant":
				m.albedo_texture = _tex("pennant")
				m.albedo_color = Color(0.6, 0.58, 0.55)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.roughness = 0.9
			"camonet":
				m.albedo_texture = _tex("camonet")
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.uv1_scale = Vector3(3, 3, 1)
				m.roughness = 1.0
			"crate":
				m.albedo_texture = _tex("crate")
				m.normal_enabled = true
				m.normal_texture = _tex("crate_n")
				m.roughness = 0.8
			"drum":
				m.albedo_texture = _tex("drum")
				m.roughness = 0.6
			"wood":
				m.albedo_texture = _tex("timber")
				m.normal_enabled = true
				m.normal_texture = _tex("timber_n")
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3(0.7, 0.35, 0.7)
				m.roughness = 0.9
			"iron":
				m.albedo_texture = _tex("metal")
				m.uv1_triplanar = true
				m.metallic = 0.6
				m.roughness = 0.6
			"cloth":
				m.albedo_color = Color(0.36, 0.31, 0.24)
				m.roughness = 1.0
			"brass":
				m.albedo_color = Color(0.55, 0.42, 0.18)
				m.metallic = 0.85
				m.roughness = 0.35
			"glass":
				m.albedo_color = Color(1.0, 0.75, 0.4)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.62, 0.28)
				m.emission_energy_multiplier = 3.0
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"wire":
				m.albedo_color = Color(0.12, 0.1, 0.09)
				m.metallic = 0.7
				m.roughness = 0.6
			"sandbag":
				m.albedo_texture = _tex("sandbags")
				m.uv1_scale = Vector3(0.25, 0.5, 1)
				m.roughness = 0.95
	_mats[key] = m
	return m


## Meshes for the instanced props, all built once and shared.
func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"post", "beam", "beam_v", "plank_box":
			var b := BoxMesh.new(); b.material = _mat("wood"); mesh = b
		"duckboard":
			mesh = _uv_box(Vector3.ONE, _mat_duck())
		"crate":
			mesh = _uv_box(Vector3.ONE, _mat("crate"))
		"drum":
			var c := CylinderMesh.new(); c.top_radius = 0.34; c.bottom_radius = 0.38; c.height = 0.6; c.radial_segments = 20
			c.material = _mat("drum"); mesh = c
		"sandbag":
			var s := CapsuleMesh.new(); s.radius = 0.14; s.height = 0.56; s.radial_segments = 8; s.rings = 3
			s.material = _mat("sandbag"); mesh = s
			# lying down and squashed: built into the mesh so instances only rotate
			var am := ArrayMesh.new()
			var arr := s.get_mesh_arrays()
			var xf := Basis(Vector3.BACK, PI * 0.5).scaled_local(Vector3(0.62, 1.0, 1.0))
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i] = xf * v[i]
				nr[i] = (xf.inverse().transposed() * nr[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = nr
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(0, _mat("sandbag"))
			mesh = am
		"rail_v", "rail_h", "picket":
			var b := BoxMesh.new(); b.material = _mat("iron") if key != "picket" else _mat("wood"); mesh = b
		"mattress":
			var b := BoxMesh.new(); b.material = _mat("cloth"); mesh = b
		"bulb":
			var s := SphereMesh.new(); s.radius = 0.035; s.height = 0.07; s.radial_segments = 6; s.rings = 3
			s.material = _mat("glass"); mesh = s
		"lantern_glass":
			var c := CylinderMesh.new(); c.top_radius = 0.05; c.bottom_radius = 0.06; c.height = 0.16; c.radial_segments = 8
			c.material = _mat("glass"); mesh = c
		"lantern":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in 4:   # cage bars
				var a := k * PI * 0.5 + PI * 0.25
				_st_box(st, Vector3(cos(a) * 0.075, 0, sin(a) * 0.075), Vector3(0.012, 0.2, 0.012))
			_st_box(st, Vector3(0, 0.11, 0), Vector3(0.16, 0.025, 0.16))
			_st_box(st, Vector3(0, -0.105, 0), Vector3(0.15, 0.02, 0.15))
			_st_box(st, Vector3(0, 0.16, 0), Vector3(0.012, 0.08, 0.06))
			mesh = st.commit()
			mesh.surface_set_material(0, _mat("iron"))
		"wheel":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var r := 0.45
			for k in 16:
				var a := k * TAU / 16.0
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				var t := Vector3(-sin(a), 0, cos(a))
				_st_box(st, p, Vector3(0.06, 0.06, 0.06) + t.abs() * 0.14, Basis(Vector3.UP, -a))
			for k in 8:
				var a := k * TAU / 8.0
				_st_box(st, Vector3(cos(a) * r * 0.5, 0, sin(a) * r * 0.5), Vector3(r, 0.035, 0.035), Basis(Vector3.UP, -a))
			_st_box(st, Vector3.ZERO, Vector3(0.12, 0.14, 0.12))
			mesh = st.commit()
			mesh.surface_set_material(0, _mat("wood"))
		"horn":
			var c := CylinderMesh.new(); c.top_radius = 0.2; c.bottom_radius = 0.02; c.height = 0.42; c.radial_segments = 16
			c.material = _mat("brass"); mesh = c
		"coil":
			mesh = _coil_mesh()
		"ibeam":
			# a unit-length steel I-section along x: flanges top and bottom, a web between
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st_box(st, Vector3(0, 0.44, 0), Vector3(1, 0.12, 1))
			_st_box(st, Vector3(0, -0.44, 0), Vector3(1, 0.12, 1))
			_st_box(st, Vector3.ZERO, Vector3(1, 0.8, 0.3))
			mesh = st.commit()
			mesh.surface_set_material(0, _mat("steel"))
		"steel_box":
			var b := BoxMesh.new(); b.material = _mat("steel"); mesh = b
		"pipe":
			var c := CylinderMesh.new(); c.top_radius = 0.055; c.bottom_radius = 0.055; c.height = 1.0; c.radial_segments = 10; c.rings = 1
			c.material = _mat("steel"); mesh = c
		"cable":
			var c := CylinderMesh.new(); c.top_radius = 0.018; c.bottom_radius = 0.018; c.height = 1.0; c.radial_segments = 5; c.rings = 1
			c.material = _mat("wire"); mesh = c
		"barrel":
			var c := CylinderMesh.new(); c.top_radius = 0.29; c.bottom_radius = 0.29; c.height = 0.88; c.radial_segments = 18; c.rings = 2
			c.material = _mat("barrel"); mesh = c
		"bulb_big":
			var s := SphereMesh.new(); s.radius = 0.045; s.height = 0.11; s.radial_segments = 8; s.rings = 4
			s.material = _mat("bulb_hot"); mesh = s
		"bulb_dead":
			var s := SphereMesh.new(); s.radius = 0.045; s.height = 0.11; s.radial_segments = 8; s.rings = 4
			s.material = _mat("bulb_off"); mesh = s
		"cage":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in 4:
				var a := k * PI * 0.5 + PI * 0.25
				_st_box(st, Vector3(cos(a) * 0.065, -0.01, sin(a) * 0.065), Vector3(0.008, 0.16, 0.008))
			_st_box(st, Vector3(0, 0.075, 0), Vector3(0.08, 0.03, 0.08))
			_st_box(st, Vector3(0, -0.085, 0), Vector3(0.11, 0.008, 0.11))
			mesh = st.commit()
			mesh.surface_set_material(0, _mat("iron"))
	_meshes[key] = mesh
	return mesh


static func _mat_duck() -> Material:
	if _mats.has("duck"):
		return _mats["duck"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("duckboard")
	m.normal_enabled = true
	m.normal_texture = _tex("duckboard_n")
	m.roughness = 0.8
	m.uv1_scale = Vector3(2, 1, 1)
	_mats["duck"] = m
	return m


## A unit box whose every face shows the whole texture (crates, duckboards).
static func _uv_box(size: Vector3, mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_box(st, Vector3.ZERO, size)
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


static func _st_box(st: SurfaceTool, c: Vector3, s: Vector3, b: Basis = Basis.IDENTITY) -> void:
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
		var o := n * h.dot(n.abs())
		var eu := u * h.dot(u.abs())
		var ev := v * h.dot(v.abs())
		var p := [o - eu - ev, o + eu - ev, o + eu + ev, o - eu + ev]
		var uv := [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(b * n)
			st.set_uv(uv[i])
			st.add_vertex(c + b * p[i])


## Concertina wire: a 3m long helix of thin wire.
static func _coil_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var turns := 9
	var steps := turns * 14
	var r := 0.32
	var tube := 0.009
	var prev: Array = []
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * turns * TAU
		var p := Vector3(-1.5 + t * 3.0, sin(a) * r, cos(a) * r)
		var tangent := Vector3(3.0, cos(a) * r * turns * TAU, -sin(a) * r * turns * TAU).normalized()
		var n1 := tangent.cross(Vector3.RIGHT).normalized()
		if n1.length() < 0.1:
			n1 = Vector3.UP
		var n2 := tangent.cross(n1).normalized()
		var ring: Array = []
		for k in 4:
			var ang := k * TAU / 4.0
			ring.append(p + (n1 * cos(ang) + n2 * sin(ang)) * tube)
		if not prev.is_empty():
			for k in 4:
				var k2 := (k + 1) % 4
				var q := [prev[k], prev[k2], ring[k2], ring[k]]
				var nn: Vector3 = ((q[1] - q[0]).cross(q[3] - q[0])).normalized()
				for idx: int in [0, 2, 1, 0, 3, 2]:
					st.set_normal(nn)
					st.add_vertex(q[idx])
		prev = ring
	var m := st.commit()
	m.surface_set_material(0, _mat("wire"))
	return m


## The clown's own head, used as the carved face over dugout doors.
static func _clown_head() -> Mesh:
	if _meshes.has("clown_head"):
		return _meshes["clown_head"]
	var scene: PackedScene = load("res://art/clown/clown_gibs.glb")
	var mesh: Mesh = null
	if scene:
		var inst := scene.instantiate()
		var node := inst.get_node_or_null("Gib_Head") as MeshInstance3D
		if node:
			mesh = node.mesh
		inst.free()
	_meshes["clown_head"] = mesh
	return mesh
