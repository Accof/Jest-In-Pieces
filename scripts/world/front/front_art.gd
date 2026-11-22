class_name FrontArt
extends TrenchArt
## Dresses a FrontMaze: TrenchArt, with the few things that assume "the front
## is toward -z" turned to face each cell's own front (FrontMaze.facing_of):
## the parapet sandbags, the fire-step boards, the wire belts (one in front of
## each fire trench, with gaps where the saps go out and at the assault
## ramps), the dead trees and wreckage of No Man's Land (now between the two
## networks), and the ground mist's extent. Everything else (terrain,
## revetments, duckboards, water, dugouts, bridges, ramps, props, signs, the
## carnival, the wind, the far scenery) is TrenchArt's as it is.
##
## Milestone 2 (geometry): enough dressing to play and judge the layout; the
## reference atmosphere is Milestone 4, functional cover and wire Milestone 3.

var front: FrontMaze


func build(m: TrenchMaze) -> void:
	front = m as FrontMaze
	super.build(m)


func _fdir(c: Vector2i) -> Vector2i:
	return Vector2i(0, front.facing_of(c) if front else -1)


## Sandbags on the parapet (the cell's front) and, now and then, the parados.
func _parapets() -> void:
	var mesh := _bag_mesh()
	var mat := _mat("burlap", 0.5)
	for c: Vector2i in maze.open_cells:
		var k: String = maze.kind[c]
		var fd := _fdir(c)
		var front_ := k in ["fire", "op", "sap"] and not maze.open_cells.has(c + fd) and maze.wall(c, fd) != "ramp"
		var back := k in ["fire", "traverse", "support"] and not maze.open_cells.has(c - fd) and rng.randf() < 0.6 and maze.wall(c, -fd) != "ramp"
		for pass_ in 2:
			if (pass_ == 0 and not front_) or (pass_ == 1 and not back):
				continue
			var dir := fd if pass_ == 0 else -fd
			var e := _edge(c, dir)
			var a: Vector2 = e.a
			var b: Vector2 = e.b
			var out := Vector2(dir) * (0.45 if pass_ == 0 else 0.4)
			var rows := 2
			var gap := rng.randf() < 0.35 and pass_ == 0
			for r in rows:
				var n := 3
				for i in n:
					if gap and r == rows - 1 and i == 1:
						continue
					var t := (i + 0.5 + (0.5 if r % 2 else 0.0)) / n
					if t > 1.0:
						continue
					var p2 := a.lerp(b, t) + out + Vector2(dir) * (r * -0.03)
					var y := maze.ground_height(p2.x, p2.y)
					var along := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
					var bb := Basis(along, Vector3.UP, along.cross(Vector3.UP)).rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
					_add("bags", mesh, mat, Transform3D(bb.scaled_local(Vector3(rng.randf_range(0.9, 1.05), rng.randf_range(0.85, 1.1), 1.0)), Vector3(p2.x, y + BAG.y * (0.35 + r * 0.9), p2.y)))


## Each fire bay's step: a board top and a boarded riser under the front wall.
func _fire_steps() -> void:
	var planks := _mat("board", 1.6)
	for c: Vector2i in maze.bays:
		var f := front.facing_of(c) if front else -1
		var r := maze._rect(c)
		var x0 := r.position.x + 0.05
		var x1 := r.end.x - 0.05
		var cx := (x0 + x1) * 0.5
		var z_edge: float
		var depth_: float
		if f == 1:
			z_edge = (c.y + 1) * maze.cell - TrenchMaze.EDGE
			depth_ = r.end.y - z_edge
		else:
			z_edge = c.y * maze.cell + TrenchMaze.EDGE
			depth_ = z_edge - r.position.y
		var step_mid := z_edge + f * depth_ * 0.5
		var top := maze.ground_height(cx, step_mid)
		var base := maze.ground_height(cx, z_edge - f * 0.2)
		_box("step_planks", planks, Vector3(cx, top - 0.02, step_mid), Basis(), Vector3(x1 - x0, 0.05, depth_))
		var h := top - base
		if h > 0.1:
			_box("step_planks", planks, Vector3(cx, base + h * 0.5, z_edge - f * 0.01), Basis(), Vector3(x1 - x0, h + 0.05, 0.04))


## A wire belt in front of each fire trench: two rows of pickets and the
## strands between, concertina along the front, gaps where the saps go out
## and where the assault ramps come up.
func _wire() -> void:
	var m := maze
	if front == null:
		super._wire()
		return
	var lines := PackedVector3Array()
	var cols := PackedColorArray()
	for f in [-1, 1]:
		var gaps: Array[float] = []
		for l: Dictionary in m.landmarks:
			if l.kind == "op" and front.facing_of(l.cell) == f:
				gaps.append((l.cell.x + 0.5) * m.cell)
		for r: Dictionary in front.assault_ramps:
			if r.dir.y == f:
				gaps.append((r.cell.x + 0.5) * m.cell)
		# the block's front edge: our block starts at our_row0 (its front is
		# that row's z), theirs ends at their_row0 + GRID_D
		var z0 := front.our_row0 * m.cell if f == -1 else (front.their_row0 + TrenchMaze.GRID_D) * m.cell
		_wire_belt(lines, cols, z0, f, gaps)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wire_sway.gdshader")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Wire"
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_wire_lines = lines


## One belt in front of the block whose front edge is at z0: rows 0.4 m
## behind and 1.2 m beyond it, coils 2.6 m out (f = -1: out is -z, our block;
## f = +1: out is +z, theirs). TrenchArt._wire's geometry, turned by f.
func _wire_belt(lines: PackedVector3Array, cols: PackedColorArray, z0: float, f: int, gap_x: Array[float]) -> void:
	var m := maze
	var picket := _mat("iron", 1.6)
	var x0 := -6.0
	var x1 := m.w * m.cell + 6.0
	for row in 2:
		# TrenchArt's rows are at z = 0.4 and -1.2 (the second further out, toward
		# -z); here that is measured from z0, out along f
		var z := z0 - f * (0.4 - row * 1.6)
		var posts: Array[Vector3] = []
		var x := x0 + row * 1.2
		while x < x1:
			var gap := false
			for sx in gap_x:
				if absf(x - sx) < 2.2:
					gap = true
			var p := Vector3(x + rng.randf_range(-0.3, 0.3), 0, z + rng.randf_range(-0.35, 0.35))
			p.y = height_at(p.x, p.z)
			if gap or rng.randf() < 0.08:
				posts.append(Vector3.INF)
			else:
				var lean := Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0.0, 0.25 if rng.randf() < 0.8 else 0.6))
				var hgt := rng.randf_range(1.0, 1.3)
				_box("wire_pickets", picket, p + lean * Vector3.UP * hgt * 0.5, lean, Vector3(0.035, hgt, 0.035))
				posts.append(p + lean * Vector3.UP * hgt)
				if posts.size() % 4 == 0:
					rattle_spots.append(p + Vector3.UP * 0.8)
			x += rng.randf_range(2.2, 2.8)
		for i in posts.size() - 1:
			var a := posts[i]
			var b := posts[i + 1]
			if a == Vector3.INF or b == Vector3.INF:
				continue
			for k in 3:
				if rng.randf() < 0.15:
					continue
				var fr: float = [1.0, 0.65, 0.3][k]
				var pa := Vector3(a.x, lerpf(height_at(a.x, a.z), a.y, fr), a.z)
				var pb := Vector3(b.x, lerpf(height_at(b.x, b.z), b.y, fr), b.z)
				_strand(lines, cols, pa, pb, rng.randf_range(0.05, 0.25))
			if rng.randf() < 0.7:
				_strand(lines, cols, a, Vector3(b.x, height_at(b.x, b.z) + 0.1, b.z), 0.1)
	var zc := z0 + f * 2.6
	var x := x0
	while x < x1:
		var length := rng.randf_range(4.0, 8.0)
		var gap := false
		for sx in gap_x:
			if absf(x + length * 0.5 - sx) < 4.0:
				gap = true
		if not gap and rng.randf() < 0.85:
			_coil(lines, cols, Vector3(x, 0, zc + rng.randf_range(-0.4, 0.4)), length, rng.randf_range(0.35, 0.5))
		x += length + rng.randf_range(0.5, 2.5)


## No Man's Land is between the networks now: its dead trees and the wrecked
## limber stand there; a few trees behind each line; water in the deep holes.
func _no_mans_land() -> void:
	if front == null:
		super._no_mans_land()
		return
	var bark := _plain("bark", Color(0.13, 0.115, 0.1), 0.9)
	var z_near := (front.their_row0 + TrenchMaze.GRID_D) * maze.cell + 6.0
	var z_far := front.our_row0 * maze.cell - 6.0
	for i in 9:
		var p := Vector3(rng.randf_range(-30.0, maze.w * maze.cell + 30.0), 0, rng.randf_range(z_near, z_far))
		_dead_tree(p, bark, rng.randf_range(2.5, 6.5))
	for i in 3:
		var p := Vector3(rng.randf_range(-30.0, maze.w * maze.cell + 30.0), 0, maze.d * maze.cell + rng.randf_range(14.0, 40.0))
		_dead_tree(p, bark, rng.randf_range(3.0, 7.0))
	for i in 3:
		var p := Vector3(rng.randf_range(-30.0, maze.w * maze.cell + 30.0), 0, -rng.randf_range(14.0, 40.0))
		_dead_tree(p, bark, rng.randf_range(3.0, 7.0))
	var wood := _mat("timber", 0.8)
	for i in 2:
		var lp := Vector3(rng.randf_range(6.0, maze.w * maze.cell - 6.0), 0, rng.randf_range(z_near + 8.0, z_far - 8.0))
		lp.y = height_at(lp.x, lp.z)
		var lb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, 0.35)
		_box("nml_wood", wood, lp + lb * Vector3(0, 0.5, 0), lb, Vector3(1.1, 0.7, 1.6))
		_wheel(lp + lb * Vector3(0.75, 0.5, 0.3), lb * Basis(Vector3.FORWARD, PI * 0.5), wood)
		_wheel(lp + Vector3(2.0, 0.08, 1.0), Basis(), wood)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water_mud.gdshader")
	mat.set_shader_parameter("noise_tex", tex("noise"))
	for cr: Vector4 in maze.crater_list:
		if cr.w < 0.55:
			continue
		var bottom := maze.ground_height(cr.x, cr.y)
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * cr.z * 1.4
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.set_instance_shader_parameter("round", 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cr.x, bottom + cr.w * 0.35, cr.y)
		add_child(mi)


## The ground mist over the whole front, No Man's Land thickest.
func _mist() -> void:
	if front == null:
		super._mist()
		return
	var w := maze.w * maze.cell
	var d := maze.d * maze.cell
	var lo := Vector3(-60.0, -3.2, -40.0)
	var hi := Vector3(w + 60.0, 5.0, d + 30.0)
	mist = FogVolume.new()
	mist.name = "GroundMist"
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist.size = hi - lo
	mist.position = (hi + lo) * 0.5
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/ground_mist.gdshader")
	fm.set_shader_parameter("noise_tex", tex("noise"))
	fm.set_shader_parameter("nml_z", (front.our_row0 + TrenchMaze.FIRE_ROW) * maze.cell - 2.5)
	mist.material = fm
	add_child(mist)
