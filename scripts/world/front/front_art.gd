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
		mat.set_shader_parameter("earth_darkness", 0.28)
		mat.set_shader_parameter("wall_tint", Color(0.6, 0.5, 0.42))         # brown, not olive
		mat.set_shader_parameter("firm_tint", Color(0.8, 0.66, 0.54))        # the field's firm ground browned (reference mud: R > G > B)
		mat.set_shader_parameter("floor_tint", Color(0.78, 0.68, 0.58))
		mat.set_shader_parameter("floor_darkness", 0.4)
		mat.set_shader_parameter("rock_darkness", 0.5)
		mat.set_shader_parameter("brightness", 0.76)
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
	_dressing(z_near, z_far)
	call_deferred("_bodies", z_near, z_far)


## The litter of No Man's Land (package §C; M4 gate iteration): shattered
## trees and stumps in clusters, lone screw pickets and tangles of loose
## wire, ruined timber and duckboard, a gun pit or two with its wreck, kit
## dropped where men fell, sandbags blown off the lips, a ruin or two for a
## landmark. Thickest in the band in front of our wire, where the player
## looks at it most. Nothing here has collision (the wire belts and the
## holes are the field's real obstacles, D-14), so M3's routes stand.
func _dressing(z_near: float, z_far: float) -> void:
	var w := maze.w * maze.cell
	var bark := _plain("bark", Color(0.13, 0.115, 0.1), 0.9)
	var wood := _mat("timber", 0.8)
	var board := _mat("board", 1.0)
	var planks := _mat("planks_wet", 1.0)
	var rust := _plain("rust", Color(0.2, 0.15, 0.11), 0.85, 0.3)
	var burlap := _mat("burlap", 0.5)
	var bag_mesh := _bag_mesh()
	var near_band := z_far - 30.0                       # our side of the field: the view from our parapet
	# a point on the field, weighted toward the near band
	var spot := func() -> Vector3:
		var z := rng.randf_range(z_near, z_far) if rng.randf() < 0.4 else rng.randf_range(near_band, z_far)
		return Vector3(rng.randf_range(-8.0, w + 8.0), 0, z)
	# --- the wood: clusters of stumps and shattered trees (a copse that was)
	for k in 9:
		var c: Vector3 = spot.call()
		var r := rng.randf_range(5.0, 11.0)
		for i in rng.randi_range(4, 9):
			var a := rng.randf() * TAU
			var q := c + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * r
			if rng.randf() < 0.35:
				_dead_tree(q, bark, rng.randf_range(2.0, 6.0))
			else:
				_stump(q, bark)
	for i in 24:                                          # and strays
		_stump(spot.call(), bark)
	# --- lone pickets, some still carrying a strand, and the tangles
	var lines := PackedVector3Array()
	var cols := PackedColorArray()
	var picket := _plain("picket_iron", Color(0.14, 0.12, 0.1), 0.7, 0.5)
	for i in 70:
		var q: Vector3 = spot.call()
		q.y = height_at(q.x, q.z)
		var h := rng.randf_range(0.7, 1.4)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.5))
		_box("pickets", picket, q + tilt * Vector3.UP * (h * 0.5 - 0.15), tilt, Vector3(0.05, h, 0.05))
		if rng.randf() < 0.4:
			var q2 := q + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
			q2.y = height_at(q2.x, q2.z) + rng.randf_range(0.1, 0.6)
			_strand(lines, cols, q + tilt * Vector3.UP * h * rng.randf_range(0.5, 0.9), q2, rng.randf_range(0.2, 0.6))
	for i in 50:
		_tangle(lines, cols, spot.call(), rng.randf_range(0.6, 1.6))
	_lines_mesh("LooseWire", lines, cols)
	# --- ruined timber: beams, planks, a splintered duckboard here and there
	for i in 60:
		var q: Vector3 = spot.call()
		q.y = height_at(q.x, q.z)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var length := rng.randf_range(1.2, 3.2)
		var tilt := yaw * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		var m: Material = [wood, board, planks][rng.randi() % 3]
		if rng.randf() < 0.3:                             # a duckboard, half sunk
			for sx in [-0.28, 0.28]:
				_box("nml_timber", wood, q + tilt * Vector3(sx, 0.02, 0), tilt, Vector3(0.06, 0.06, length))
			var n := int(length / 0.14)
			for k in n:
				if rng.randf() < 0.75:
					_box("nml_planks", planks, q + tilt * Vector3(0, 0.06, -length * 0.5 + (k + 0.5) * 0.14), tilt, Vector3(0.62, 0.025, 0.11))
		else:
			var sz := Vector3(rng.randf_range(0.1, 0.22), rng.randf_range(0.08, 0.2), length)
			_box("nml_timber", m, q + tilt * Vector3(0, sz.y * 0.3, 0), tilt, sz)
	# --- gun pits: a ring of thrown-up earth and bags round a wrecked piece
	for i in 2:
		var c: Vector3 = spot.call()
		c.y = height_at(c.x, c.z)
		var yaw := rng.randf() * TAU
		for k in 14:
			var a := yaw + k * TAU / 14.0 + rng.randf_range(-0.1, 0.1)
			if rng.randf() < 0.3:
				continue
			var q := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.6, 3.4)
			q.y = height_at(q.x, q.z)
			var bb := Basis(Vector3.UP, a + PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
			_add("bags", bag_mesh, burlap, Transform3D(bb.scaled_local(Vector3(rng.randf_range(0.85, 1.05), rng.randf_range(0.8, 1.05), 1.0)), q + Vector3.UP * TrenchArt.BAG.y * 0.3))
		var lb := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(0.2, 0.6))
		_box("nml_wood", wood, c + lb * Vector3(0, 0.45, 0), lb, Vector3(0.9, 0.6, 1.4))
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.07
		barrel.bottom_radius = 0.11
		barrel.height = 2.2
		barrel.radial_segments = 10
		_add("gun_barrels", barrel, rust, Transform3D(lb * Basis(Vector3.RIGHT, PI * 0.5 + 0.3), c + lb * Vector3(0, 0.8, 0.9)))
		_wheel(c + lb * Vector3(0.9, 0.55, -0.2), lb * Basis(Vector3.FORWARD, PI * 0.5), wood)
		_wheel(c + Vector3(rng.randf_range(-2.5, 2.5), 0.08, rng.randf_range(-2.5, 2.5)), Basis(Vector3.UP, rng.randf() * TAU), wood)
		for k in 4:
			_thing("helmet", _ground_xf(c + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))))
	# --- kit where men fell: helmets most of all, a rifle, a stretcher, tins, a reel
	for i in 50:
		_thing("helmet", _ground_xf(spot.call()))
	for i in 10:
		var xf := _ground_xf(spot.call())
		_thing("rifle", Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.5 + rng.randf_range(0.15, 0.4)), xf.origin))
	for i in 3:
		var xf := _ground_xf(spot.call())
		_thing("stretcher", Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.5 + rng.randf_range(0.1, 0.3)), xf.origin))
	for i in 8:
		_thing("tins", _ground_xf(spot.call()))
	for i in 3:
		_thing("reel", _ground_xf(spot.call()))
	for i in 5:
		_thing("blanket", _ground_xf(spot.call()))
	# --- sandbags blown off the lips, lying where they fell
	for i in 50:
		var q: Vector3 = spot.call()
		q.y = height_at(q.x, q.z)
		var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		_add("bags", bag_mesh, burlap, Transform3D(bb.scaled_local(Vector3(rng.randf_range(0.85, 1.05), rng.randf_range(0.8, 1.05), 1.0)), q + Vector3.UP * TrenchArt.BAG.y * 0.25))
	# --- a landmark: the footings of a farm building, knocked down to the sills
	var brick := _plain("old_brick", Color(0.22, 0.18, 0.15), 0.95)
	var c := Vector3(rng.randf_range(6.0, w - 6.0), 0, rng.randf_range(z_near + 20.0, z_far - 20.0))
	_cottage_ruin(c, Basis(Vector3.UP, rng.randf() * TAU), brick)


## What is left of a cottage: broken walls no higher than a man's chest,
## most of them gone to the footings, rubble about.
func _cottage_ruin(at: Vector3, face: Basis, mat: Material) -> void:
	var w := rng.randf_range(6.0, 9.0)
	var dpt := rng.randf_range(4.0, 6.0)
	at.y = height_at(at.x, at.z) - 0.25
	for side in 4:
		var along := face * (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK)
		var length := w if side % 2 == 0 else dpt
		var off := face * (Vector3(0, 0, dpt * 0.5) if side == 0 else Vector3(0, 0, -dpt * 0.5) if side == 2 else Vector3(w * 0.5, 0, 0) if side == 1 else Vector3(-w * 0.5, 0, 0))
		var n := int(length / 1.2)
		for k in n:
			if rng.randf() < 0.25:
				continue
			var t := (k + 0.5) / n - 0.5
			var hh := rng.randf_range(0.3, 1.6) * (1.0 if rng.randf() < 0.7 else 1.6)
			var cpos := at + off + along * t * length + Vector3.UP * hh * 0.5
			_box("cottage", mat, cpos, Basis(along.cross(Vector3.UP), Vector3.UP, along).orthonormalized(), Vector3(0.45, hh, length / n + 0.03))
	for k in 10:
		var q := at + face * Vector3(rng.randf_range(-w, w) * 0.7, 0, rng.randf_range(-dpt, dpt) * 0.7)
		var sz := rng.randf_range(0.3, 0.9)
		_box("cottage", mat, q + Vector3.UP * sz * 0.15, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), Vector3(sz, sz * 0.4, sz * 0.7))


## A prop's transform on the open ground: on the field, facing a random way.
func _ground_xf(at: Vector3) -> Transform3D:
	at.y = height_at(at.x, at.z)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at)


## What is left of a tree: a short trunk, split and splintered at the top.
func _stump(p: Vector3, bark: Material) -> void:
	p.y = height_at(p.x, p.z) - 0.15
	var h := rng.randf_range(0.4, 1.5)
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
	var tr := CylinderMesh.new()
	tr.top_radius = rng.randf_range(0.14, 0.26)
	tr.bottom_radius = rng.randf_range(0.28, 0.45)
	tr.height = h
	tr.radial_segments = 8
	tr.rings = 1
	_add("stumps_%d" % int(h * 4.0), tr, bark, Transform3D(tilt, p + tilt * Vector3.UP * h * 0.5))
	for k in rng.randi_range(2, 4):
		var dir := (tilt * Vector3(cos(k * 1.7 + p.z), rng.randf_range(0.6, 1.6), sin(k * 1.7 + p.z))).normalized()
		var length := rng.randf_range(0.25, 0.9)
		_box("splinters", bark, p + tilt * Vector3.UP * h + dir * length * 0.5, Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT), Vector3(0.06, 0.06, length))


## A tangle of loose wire: a few loops thrown about a point, lying on the
## ground and standing up off it.
func _tangle(lines: PackedVector3Array, cols: PackedColorArray, at: Vector3, size: float) -> void:
	var g := height_at(at.x, at.z)
	var u := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 0.5), rng.randf_range(-1, 1)).normalized()
	var v := u.cross(Vector3.UP).normalized()
	var loops := rng.randi_range(3, 7)
	var prev := Vector3.INF
	var steps := loops * 14
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * loops * TAU
		# the axis wanders so the loops do not stack
		var uu := (u + Vector3(sin(t * 5.0), 0.0, cos(t * 3.7)) * 0.4).normalized()
		var vv := uu.cross(Vector3.UP).normalized()
		var r := size * (0.6 + 0.4 * sin(t * 9.0 + at.x))
		var p := at + (uu * cos(a) + vv * sin(a)) * r + Vector3(0, size * 0.5 * (1.0 + sin(a)), 0) * 0.5 + Vector3(t - 0.5, 0, 0) * size
		var gy := height_at(p.x, p.z)
		p.y = maxf(p.y - at.y + g, gy + 0.04)
		if prev != Vector3.INF:
			lines.append(prev)
			cols.append(Color(0.4, 0, 0))
			lines.append(p)
			cols.append(Color(0.4, 0, 0))
		prev = p


func _lines_mesh(name_: String, lines: PackedVector3Array, cols: PackedColorArray) -> void:
	if lines.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wire_sway.gdshader")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The dead of earlier attacks: WitzSoldats as they fell, in and about the
## holes and along the wire, the game's own bodies (corpses from the start:
## no kill to count, every gore system as it is). Made a frame after the
## world, as the ragdolls need the ground under them.
const BODIES := 18
var bodies: Array[Clown] = []
func _bodies(z_near: float, z_far: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	var w := maze.w * maze.cell
	for i in BODIES:
		var at: Vector3
		if i % 3 == 0 and not maze.crater_list.is_empty():       # in a hole
			var cr: Vector4 = maze.crater_list[rng.randi() % maze.crater_list.size()]
			var a := rng.randf() * TAU
			at = Vector3(cr.x + cos(a) * cr.z * rng.randf_range(0.0, 0.8), 0, cr.y + sin(a) * cr.z * rng.randf_range(0.0, 0.8))
		elif i % 3 == 1 and not front.wire_belts.is_empty():     # at the wire
			var b: Dictionary = front.wire_belts[rng.randi() % front.wire_belts.size()]
			at = Vector3(rng.randf_range(2.0, w - 2.0), 0, float(b.z) + rng.randf_range(-2.5, 2.5))
		else:
			at = Vector3(rng.randf_range(0.0, w), 0, rng.randf_range(z_near, z_far))
		if at.z < z_near or at.z > z_far:
			continue
		at.y = height_at(at.x, at.z) + 0.35
		var c := Clown.new()
		c.body = "witzsoldat"
		add_child(c)
		c.global_position = at
		c.rotation.y = rng.randf() * TAU
		if rng.randf() < 0.5:                                      # already down
			c.rotation.x = PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			c.global_position.y += 0.4
		bodies.append(c)
	await get_tree().physics_frame
	for c in bodies:
		if is_instance_valid(c):
			c.make_corpse()


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
	fm.set_shader_parameter("tint", Color(0.66, 0.67, 0.61))
	fm.set_shader_parameter("density", 0.12)
	fm.set_shader_parameter("height", 1.4)
	fm.set_shader_parameter("nml_boost", 2.6)
	fm.set_shader_parameter("bank_tint", Color(0.80, 0.80, 0.75))
	mist.material = fm
	add_child(mist)
