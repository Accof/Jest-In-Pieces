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
## The Front's weather and the one visibility model (M4).
var atmosphere: FrontAtmosphere


func build(m: TrenchMaze) -> void:
	front = m as FrontMaze
	super.build(m)
	if front:
		atmosphere = FrontAtmosphere.new()
		atmosphere.name = "Atmosphere"
		add_child(atmosphere)
		_drift_smoke()
		# the rolling fog: the legacy day's banks, for the Front's geometry
		var fog := FrontFog.new()
		fog.name = "Fog"
		add_child(fog)
		fog.setup_front(front, self, rng.randi())
		atmosphere.front_fog = fog
		# (M4) the far battle's smoke columns: half as many billows, paler, so
		# they are shapes in the haze and not the picture
		for c in get_children():
			if c is CPUParticles3D and c.position.distance_to(Vector3(maze.w * maze.cell * 0.5, 0, maze.d * maze.cell * 0.5)) > 100.0:
				var cp := c as CPUParticles3D
				cp.amount = maxi(int(cp.amount * 0.5), 4)
				cp.scale_amount_max *= 0.75
				if cp.color_ramp:
					var g := cp.color_ramp.duplicate() as Gradient
					for i in g.get_point_count():
						var col := g.get_color(i)
						g.set_color(i, Color(col.r * 1.25, col.g * 1.25, col.b * 1.2, col.a * 0.7))
					cp.color_ramp = g


## The ground, wetter and darker than the legacy's day-after-rain: soaked,
## near-black in the foreground, water lying in every flat low place (M4,
## after the reference). The legacy level keeps TrenchArt's values.
func ground_material() -> ShaderMaterial:
	var had := _ground_mat != null
	var mat := super.ground_material()
	if front and not had:
		mat.set_shader_parameter("dry_ground", 0.12)
		mat.set_shader_parameter("puddles", 0.95)
		mat.set_shader_parameter("earth_darkness", 0.3)
		mat.set_shader_parameter("wall_tint", Color(0.6, 0.54, 0.47))        # brown, not olive
		mat.set_shader_parameter("floor_tint", Color(0.78, 0.7, 0.62))
		mat.set_shader_parameter("floor_darkness", 0.4)
		mat.set_shader_parameter("rock_darkness", 0.55)
		mat.set_shader_parameter("brightness", 0.82)
		mat.set_shader_parameter("water_col", Color(0.26, 0.26, 0.22))
		mat.set_shader_parameter("puddle_col", Color(0.07, 0.07, 0.06))
	return mat


## Low smoke drifting over No Man's Land on the wind: a few patches, each a
## slow emitter of wide soft billows that creep and thin out; the atmosphere
## counts them against sight. (The tall columns of the far battle are
## TrenchArt._smoke's, as before.)
func _drift_smoke() -> void:
	var mat := smoke_material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.58, 0.6, 0.55, 0.42)
	var z_near := (front.their_row0 + TrenchMaze.GRID_D) * maze.cell + 6.0
	var z_far := front.our_row0 * maze.cell - 6.0
	var wind := Vector3(0.55, 0.0, 0.18)
	for i in 8:
		var at := Vector3(rng.randf_range(2.0, maze.w * maze.cell - 2.0), 0, rng.randf_range(z_near, z_far))
		# from a shell hole where there is one near
		var best := Vector4.ZERO
		for cr: Vector4 in maze.crater_list:
			if Vector2(cr.x, cr.y).distance_to(Vector2(at.x, at.z)) < 9.0 and cr.z > 2.0:
				best = cr
		if best != Vector4.ZERO:
			at = Vector3(best.x, 0, best.y)
		at.y = height_at(at.x, at.z) - 0.3
		var p := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 8.0
		q.material = mat
		p.mesh = q
		p.amount = 16
		p.lifetime = 22.0
		p.preprocess = 14.0
		p.direction = Vector3(wind.x, 0.12, wind.z).normalized()
		p.spread = 18.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 0.9
		p.gravity = wind * 0.35
		p.damping_min = 0.01
		p.damping_max = 0.03
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 2.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.3
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(1, 2.0))
		p.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(0.6, 0.62, 0.56, 0.0))
		grad.add_point(0.15, Color(0.58, 0.6, 0.55, 0.5))
		grad.add_point(0.6, Color(0.6, 0.62, 0.57, 0.3))
		grad.set_color(grad.get_point_count() - 1, Color(0.65, 0.66, 0.62, 0.0))
		p.color_ramp = grad
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.position = at
		p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))
		p.emitting = true
		add_child(p)
		atmosphere.smoke_patches.append({pos = at + wind * 7.0 + Vector3.UP * 1.5, radius = 8.0, density = 0.06})


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


## The wire, from the maze's plan (FrontMaze.wire_belts): a belt in front of
## each fire trench (two rows of pickets, strands, concertina), gaps where the
## saps go out and the assault ramps come up, and short broken belts out in
## the middle. Each run of wire between two standing pickets, and each coil,
## gets a collision box the player cannot pass (LAYER_RAMP: him only, so sight
## and rounds go through); the brains path round it (the maze took its cells
## out of the top layer).
var _wire_body: StaticBody3D


func _wire() -> void:
	if front == null:
		super._wire()
		return
	_wire_body = StaticBody3D.new()
	_wire_body.name = "WireCollision"
	_wire_body.collision_layer = Maze.LAYER_RAMP
	_wire_body.collision_mask = 0
	add_child(_wire_body)
	var lines := PackedVector3Array()
	var cols := PackedColorArray()
	for b: Dictionary in front.wire_belts:
		_wire_belt(lines, cols, b)
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


func _wire_block(a: Vector3, b: Vector3, height: float, thick: float) -> void:
	var along := b - a
	along.y = 0.0
	var length := along.length()
	if length < 0.2:
		return
	var u := along / length
	var basis := Basis(u, Vector3.UP, u.cross(Vector3.UP))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, height, thick)
	cs.shape = box
	cs.transform = Transform3D(basis, (a + b) * 0.5 + Vector3.UP * height * 0.5)
	_wire_body.add_child(cs)


## One belt (TrenchArt._wire's geometry, laid along the belt's rows). A
## picket blown out leaves its strands tangled on the ground: it still stops
## a man, so the collision runs post position to post position; only a gap
## (a sap's, a ramp's) is open, and no run of wire or coil is laid across one.
func _wire_belt(lines: PackedVector3Array, cols: PackedColorArray, b: Dictionary) -> void:
	var picket := _mat("iron", 1.6)
	var f: int = b.f
	var gaps: Array = b.gaps
	for row in int(b.rows):
		var z: float = b.z + f * row * FrontMaze.WIRE_ROW
		var posts: Array[Vector3] = []          # the standing pickets' tops (INF: none here)
		var feet: Array[Vector3] = []           # every post position, gap or not
		var in_gap: Array[bool] = []
		var x: float = b.x0 + row * 1.2
		while x < b.x1:
			var gap := false
			for sx: float in gaps:
				if absf(x - sx) < FrontMaze.WIRE_GAP:
					gap = true
			var p := Vector3(x + rng.randf_range(-0.3, 0.3), 0, z + rng.randf_range(-0.3, 0.3))
			p.y = height_at(p.x, p.z)
			feet.append(p)
			in_gap.append(gap)
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
			var c := posts[i + 1]
			if a != Vector3.INF and c != Vector3.INF:
				for k in 3:
					if rng.randf() < 0.15:
						continue
					var fr: float = [1.0, 0.65, 0.3][k]
					var pa := Vector3(a.x, lerpf(height_at(a.x, a.z), a.y, fr), a.z)
					var pb := Vector3(c.x, lerpf(height_at(c.x, c.z), c.y, fr), c.z)
					_strand(lines, cols, pa, pb, rng.randf_range(0.05, 0.25))
				if rng.randf() < 0.7:
					_strand(lines, cols, a, Vector3(c.x, height_at(c.x, c.z) + 0.1, c.z), 0.1)
			# the wire on the ground between two posts stops a man, unless either
			# post is in a gap (the way through)
			if not in_gap[i] and not in_gap[i + 1]:
				_wire_block(feet[i], feet[i + 1], 1.1, 0.25)
	if b.coil:
		var zc: float = b.z + f * (FrontMaze.WIRE_ROW * (int(b.rows) - 1) + FrontMaze.WIRE_COIL)
		var x: float = b.x0
		while x < b.x1:
			var length := minf(rng.randf_range(4.0, 8.0), b.x1 - x)
			if rng.randf() < 0.85 and length > 1.5:
				# the segment, less any gap it crosses
				var pieces: Array = [[x, x + length]]
				for sx: float in gaps:
					var cut: Array = []
					for seg: Array in pieces:
						var g0: float = sx - FrontMaze.WIRE_GAP - 0.2
						var g1: float = sx + FrontMaze.WIRE_GAP + 0.2
						if seg[1] <= g0 or seg[0] >= g1:
							cut.append(seg)
						else:
							if seg[0] < g0:
								cut.append([seg[0], g0])
							if seg[1] > g1:
								cut.append([g1, seg[1]])
					pieces = cut
				var zz := zc + rng.randf_range(-0.3, 0.3)
				for seg: Array in pieces:
					if seg[1] - seg[0] < 1.2:
						continue
					_coil(lines, cols, Vector3(seg[0], 0, zz), seg[1] - seg[0], rng.randf_range(0.35, 0.5))
					_wire_block(Vector3(seg[0], height_at(seg[0], zz), zz), Vector3(seg[1], height_at(seg[1], zz), zz), 0.9, 0.9)
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
	mat.set_shader_parameter("colour", Color(0.085, 0.08, 0.07))      # (M4) dark water: it shows the sky by reflection
	mat.set_shader_parameter("deep", Color(0.045, 0.043, 0.04))
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
	# (M4) the mist in the reference's colour, a little thicker
	fm.set_shader_parameter("tint", Color(0.66, 0.70, 0.61))
	fm.set_shader_parameter("density", 0.12)
	fm.set_shader_parameter("height", 1.4)
	fm.set_shader_parameter("nml_boost", 2.6)
	fm.set_shader_parameter("bank_tint", Color(0.78, 0.80, 0.72))
	mist.material = fm
	add_child(mist)
