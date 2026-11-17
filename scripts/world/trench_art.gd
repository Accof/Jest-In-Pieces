class_name TrenchArt
extends Node3D
## Dresses a TrenchMaze: the carved mud, revetments, duckboards, water,
## landmarks and the battlefield beyond. Built once per floor.

var maze: TrenchMaze
var rng := RandomNumberGenerator.new()
var _multi := {}                 ## key -> {mesh, mat, xfs}
var _body: StaticBody3D          ## revetment, roof and prop collision
var _mats := {}

const BAG := Vector3(0.52, 0.14, 0.3)


func build(m: TrenchMaze) -> void:
	maze = m
	rng.seed = m.rng.seed + 17
	_body = StaticBody3D.new()
	_body.name = "Props"
	_body.collision_layer = Maze.LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_terrain()
	_revetments()
	_parapets()
	_fire_steps()
	_duckboards()
	_water()
	_landmarks()
	_far()
	_flush()


static func tex(name_: String) -> Texture2D:
	return load("res://art/trench/%s.png" % name_)


## The overcast day (used by the game on trench floors): a bright-enough grey
## sky lighting everything, a faint soft sun, light haze in the distance.
static func make_environment() -> Environment:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/overcast_sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", tex("noise"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.2
	env.tonemap_white = 4.0
	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.0
	env.ssao_radius = 0.9
	env.ssao_power = 1.3
	env.ssil_enabled = true
	env.ssil_intensity = 0.5
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.6, 0.61, 0.63)
	env.fog_density = 0.0038
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.03
	return env


## A faint high sun behind the cloud: soft, weak shadows.
static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.light_color = Color(0.86, 0.89, 0.95)
	sun.light_energy = 0.42
	sun.light_angular_distance = 9.0
	sun.light_volumetric_fog_energy = 0.0
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 2.5
	sun.directional_shadow_max_distance = 60.0
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-35.0), 0.0)


## The carved ground as chunked meshes (16 m squares, for culling).
func _terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mud_terrain.gdshader")
	for pair: Array in [["churned", "mud_churned"], ["sludge", "mud_sludge"], ["wall", "soil_wall"], ["firm", "ground_firm"]]:
		mat.set_shader_parameter(pair[0] + "_a", tex(pair[1]))
		mat.set_shader_parameter(pair[0] + "_n", tex(pair[1] + "_n"))
		mat.set_shader_parameter(pair[0] + "_r", tex(pair[1] + "_r"))
	mat.set_shader_parameter("noise_tex", tex("noise"))
	var chunk := 80                   # samples per side
	var m := maze
	for cz in range(0, m.hz - 1, chunk):
		for cx in range(0, m.hx - 1, chunk):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var x1 := mini(cx + chunk, m.hx - 1)
			var z1 := mini(cz + chunk, m.hz - 1)
			var nx := x1 - cx + 1
			for iz in range(cz, z1 + 1):
				for ix in range(cx, x1 + 1):
					var i := ix + iz * m.hx
					var h := m.vis_h[i]
					var hl := m.vis_h[maxi(ix - 1, 0) + iz * m.hx]
					var hr := m.vis_h[mini(ix + 1, m.hx - 1) + iz * m.hx]
					var hd := m.vis_h[ix + maxi(iz - 1, 0) * m.hx]
					var hu := m.vis_h[ix + mini(iz + 1, m.hz - 1) * m.hx]
					var nrm := Vector3(hl - hr, 2.0 * TrenchMaze.RES, hd - hu).normalized()
					var sd := m.sdf[i]
					st.set_normal(nrm)
					st.set_color(Color(m.wet[i], 1.0 if sd <= 0.0 else 0.0, clampf(sd / 2.0, 0.0, 1.0), clampf(h + 3.0, 0.0, 4.0) / 4.0))
					st.add_vertex(Vector3(m.origin.x + ix * TrenchMaze.RES, h, m.origin.y + iz * TrenchMaze.RES))
			for iz in range(0, z1 - cz):
				for ix in range(0, nx - 1):
					var a := ix + iz * nx
					var b := a + 1
					var c := a + nx
					var e := c + 1
					st.add_index(a)
					st.add_index(b)
					st.add_index(c)
					st.add_index(b)
					st.add_index(e)
					st.add_index(c)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			add_child(mi)


# --- shared ------------------------------------------------------------------------
## A triplanar world-mapped material from an art/trench texture set (no
## stretching on scaled boxes).
func _mat(name_: String, scale := 1.0, rough := -1.0) -> StandardMaterial3D:
	var key := "%s:%s" % [name_, scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name_)
	m.normal_enabled = true
	m.normal_texture = tex(name_ + "_n")
	m.normal_scale = 0.8
	if ResourceLoader.exists("res://art/trench/%s_r.png" % name_) and rough < 0.0:
		m.roughness_texture = tex(name_ + "_r")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		m.roughness = rough if rough >= 0.0 else 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func _add(key: String, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not _multi.has(key):
		_multi[key] = {mesh = mesh, mat = mat, xfs = []}
	_multi[key].xfs.append(xf)


func _box(key: String, mat: Material, centre: Vector3, basis: Basis, size: Vector3) -> void:
	if not _multi.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		_multi[key] = {mesh = bm, mat = mat, xfs = []}
	_multi[key].xfs.append(Transform3D(basis.scaled_local(size), centre))


func _flush() -> void:
	for key: String in _multi:
		var e: Dictionary = _multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e.mesh
		mm.instance_count = e.xfs.size()
		for i in e.xfs.size():
			mm.set_instance_transform(i, e.xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = e.mat
		add_child(mmi)
	_multi.clear()


func _collide(centre: Vector3, basis: Basis, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, centre)
	_body.add_child(cs)


func _floor_at(x: float, z: float) -> float:
	return maze.ground_height(x, z)


## One edge of an open cell's floor: its two ends (at floor level, y unset),
## the inward normal and its length.
func _edge(c: Vector2i, dir: Vector2i) -> Dictionary:
	var r := maze._rect(c)
	var a: Vector2
	var b: Vector2
	match dir:
		Vector2i(-1, 0):
			a = Vector2(r.position.x, r.position.y); b = Vector2(r.position.x, r.end.y)
		Vector2i(1, 0):
			a = Vector2(r.end.x, r.position.y); b = Vector2(r.end.x, r.end.y)
		Vector2i(0, -1):
			a = Vector2(r.position.x, r.position.y); b = Vector2(r.end.x, r.position.y)
		_:
			a = Vector2(r.position.x, r.end.y); b = Vector2(r.end.x, r.end.y)
	# open neighbours along the edge: the edge runs right up to them (no gap)
	return {a = a, b = b, inward = -Vector2(dir), length = a.distance_to(b)}


# --- revetments ----------------------------------------------------------------------
## Every lined wall: timber boards between posts, corrugated iron on pickets,
## sandbags, woven hurdles, or boards that have come away. Each gets a thin
## collision box so bodies hit the lining, not the earth behind it.
func _revetments() -> void:
	var planks := _mat("board", 1.6)
	var timber := _mat("timber", 0.8)
	var wattle := _mat("wattle", 1.0)
	var iron := _mat("iron", 1.0)
	var bag := _mat("burlap", 0.5)
	var bag_mesh := _bag_mesh()
	var iron_mesh := _corrugated_mesh()
	for c: Vector2i in maze.open_cells:
		for dir in Maze.DIRS:
			var t := maze.wall(c, dir)
			if t == "" or t == "earth":
				continue
			var e := _edge(c, dir)
			var inward: Vector2 = e.inward
			var a2: Vector2 = e.a + inward * 0.02
			var b2: Vector2 = e.b + inward * 0.02
			var mid2 := (a2 + b2) * 0.5
			var length: float = e.length
			var base := _floor_at(mid2.x + inward.x * 0.25, mid2.y + inward.y * 0.25) - 0.08
			var top := maze.ground_height(mid2.x - inward.x * 0.45, mid2.y - inward.y * 0.45) + 0.05
			var h := top - base
			if h < 0.4:
				continue
			# most linings stop short of the top: earth above them, sandbags or not
			var full := h
			if t in ["timber", "iron", "wattle"]:
				h = minf(h, full * _lining_height(c, dir))
			var along := Vector3(b2.x - a2.x, 0, b2.y - a2.y).normalized()
			var inn := Vector3(inward.x, 0, inward.y)
			# the lining leans back with the wall
			var lean := maxf(float(TrenchMaze.WALL_W.get(t, 0.12)) - 0.04, 0.0) / h
			var up := (Vector3.UP - inn * lean).normalized()
			var basis := Basis(along, up, along.cross(up)).orthonormalized()
			var foot := Vector3(mid2.x, base, mid2.y)
			match t:
				"timber":
					var y := 0.0
					var k := 0
					while y < h - 0.05:
						var ph := minf(0.22, h - y)
						var jitter := Vector3(0, 0, rng.randf_range(-0.01, 0.01))
						var bb := basis.rotated(along, rng.randf_range(-0.015, 0.015))
						_box("rev_planks", planks, foot + up * (y + ph * 0.5) + inn * 0.015 + jitter, bb, Vector3(length + 0.04, ph - 0.012, 0.04))
						y += ph
						k += 1
					_posts(timber, foot, up, along, inn, length, h)
				"iron":
					var n := maxi(1, int(ceil(length / 0.7)))
					var sw := length / n
					for i in n:
						var p := foot + along * (-length * 0.5 + sw * (i + 0.5))
						var bb := basis.rotated(up, rng.randf_range(-0.03, 0.03)).rotated(along, rng.randf_range(-0.02, 0.02))
						_add("rev_iron", iron_mesh, iron, Transform3D(bb.scaled_local(Vector3(sw + 0.06, h + 0.1, 1.0)), p + up * (h * 0.5) + inn * 0.02))
					_posts(timber, foot, up, along, inn, length, h, 0.07)
				"wattle":
					_box("rev_wattle", wattle, foot + up * (h * 0.5) + inn * 0.03, basis, Vector3(length + 0.05, h, 0.06))
					_posts(timber, foot, up, along, inn, length, h + 0.15, 0.06)
				"sandbag":
					_bag_wall(bag_mesh, bag, foot, along, inn, length, h)
				"broken":
					_broken(planks, timber, foot, up, along, inn, length, h)
			if t != "broken":
				# collision for the lining: thin, just behind its face
				_collide(foot + up * (h * 0.5) - inn * 0.03, basis, Vector3(length, h, 0.08))


## How much of a wall a lining covers, the same along a stretch of trench.
func _lining_height(c: Vector2i, dir: Vector2i) -> float:
	var hsh := absi((c.x / 3) * 73856093 ^ (c.y / 3) * 19349663 ^ dir.x * 83492791 ^ dir.y * 2971) % 1000
	return 0.55 + 0.45 * float(hsh) / 1000.0


func _posts(mat: Material, foot: Vector3, up: Vector3, along: Vector3, inn: Vector3, length: float, h: float, size := 0.1) -> void:
	var n := 2 if length < 1.2 else 3
	for i in n:
		var t := float(i) / (n - 1) - 0.5
		var p := foot + along * (t * (length - size)) + inn * (0.05 + size * 0.3)
		var tilt := Basis(along, rng.randf_range(-0.03, 0.03)) * Basis(Vector3.FORWARD, rng.randf_range(-0.02, 0.02))
		var b := Basis(along, up, along.cross(up)).orthonormalized()
		_box("rev_posts", mat, p + up * ((h + 0.25) * 0.5 - 0.1), tilt * b, Vector3(size, h + 0.25, size))


## Sandbags laid in courses, header and stretcher, set back a little each course.
func _bag_wall(mesh: Mesh, mat: Material, foot: Vector3, along: Vector3, inn: Vector3, length: float, h: float) -> void:
	var rows := int(h / (BAG.y * 0.92))
	for r in rows:
		var y := r * BAG.y * 0.92 + BAG.y * 0.5
		var back := -inn * (r * 0.012)
		var n := maxi(1, int(round(length / (BAG.x * 0.95))))
		var off := (BAG.x * 0.5) if r % 2 == 1 else 0.0
		for i in n:
			var x := -length * 0.5 + (i + 0.5) * (length / n) + off * 0.5
			if absf(x) > length * 0.5 + 0.05:
				continue
			var p := foot + along * x + Vector3.UP * y + inn * (BAG.z * 0.5 + 0.0) + back
			var bb := Basis.looking_at(-inn, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.12, 0.12))
			bb = bb.rotated(along, rng.randf_range(-0.06, 0.06))
			var sc := Vector3(rng.randf_range(0.9, 1.08), rng.randf_range(0.85, 1.15), rng.randf_range(0.9, 1.05))
			_add("bags", mesh, mat, Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)).rotated(Vector3.UP, rng.randf_range(-0.1, 0.1)).scaled_local(sc), p))


## Boards come away: a few still on, some leaning out, some in the mud.
func _broken(planks: Material, timber: Material, foot: Vector3, up: Vector3, along: Vector3, inn: Vector3, length: float, h: float) -> void:
	var b := Basis(along, up, along.cross(up)).orthonormalized()
	var y := 0.0
	while y < h * 0.5:
		_box("rev_planks", planks, foot + up * (y + 0.11) + inn * 0.015, b, Vector3(length, 0.21, 0.04))
		y += 0.22
	for i in rng.randi_range(2, 3):
		var lean := Basis(along, rng.randf_range(0.25, 0.7)) * b
		var p := foot + along * rng.randf_range(-length * 0.3, length * 0.3) + inn * rng.randf_range(0.15, 0.35) + Vector3.UP * rng.randf_range(0.3, 0.7)
		_box("rev_planks", planks, p, lean.rotated(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(length * rng.randf_range(0.6, 1.0), 0.2, 0.04))
	for i in rng.randi_range(0, 2):
		var p := foot + along * rng.randf_range(-length * 0.4, length * 0.4) + inn * rng.randf_range(0.25, 0.6) + Vector3.UP * 0.1
		_box("rev_planks", planks, p, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(length * 0.7, 0.2, 0.04))
	var post := foot + along * (length * 0.5 - 0.05) + inn * 0.06
	_box("rev_posts", timber, post + Vector3.UP * (h * 0.45), Basis(along, 0.2) * b, Vector3(0.1, h * 0.9, 0.1))


## A sandbag: a squashed, slumped pillow.
func _bag_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 10
	m.rings = 6
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var p := v[i]
		# a flat-bottomed, boxy pillow, sagging in the middle
		var q := Vector3(signf(p.x) * pow(absf(p.x) * 2.0, 0.55) * 0.5, signf(p.y) * pow(absf(p.y) * 2.0, 0.8) * 0.5, signf(p.z) * pow(absf(p.z) * 2.0, 0.6) * 0.5)
		q.y = maxf(q.y, -0.42)
		q.y -= 0.08 * (1.0 - absf(q.x) * 2.0) * (1.0 if q.y > 0.0 else 0.0)
		v[i] = q * BAG
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st2 := SurfaceTool.new()
	st2.create_from(am, 0)
	st2.generate_normals()
	return st2.commit()


## A corrugated sheet one unit square (x along, y up), the waves across it.
func _corrugated_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 48
	for side in 2:
		for i in nx:
			var x0 := float(i) / nx - 0.5
			var x1 := float(i + 1) / nx - 0.5
			var z0 := sin(x0 * TAU * 8.0) * 0.012
			var z1 := sin(x1 * TAU * 8.0) * 0.012
			var n0 := Vector3(-cos(x0 * TAU * 8.0) * 0.6, 0, 1).normalized()
			var n1 := Vector3(-cos(x1 * TAU * 8.0) * 0.6, 0, 1).normalized()
			var zs := 1.0 if side == 0 else -1.0
			var quad := [[Vector3(x0, -0.5, z0), n0, Vector2(x0 + 0.5, 1)], [Vector3(x1, -0.5, z1), n1, Vector2(x1 + 0.5, 1)],
				[Vector3(x1, 0.5, z1), n1, Vector2(x1 + 0.5, 0)], [Vector3(x0, 0.5, z0), n0, Vector2(x0 + 0.5, 0)]]
			var order := [0, 2, 1, 0, 3, 2] if side == 0 else [0, 1, 2, 0, 2, 3]
			for k: int in order:
				st.set_normal(quad[k][1] * Vector3(1, 1, zs))
				st.set_uv(quad[k][2])
				st.add_vertex(quad[k][0] - Vector3(0, 0, 0.004 * zs))
	st.generate_tangents()
	return st.commit()


# --- parapet, parados, fire steps -----------------------------------------------------
## Sandbags along the top of the fire trench's front wall (a gap here and
## there to look through) and a lower row along the parados.
func _parapets() -> void:
	var mesh := _bag_mesh()
	var mat := _mat("burlap", 0.5)
	for c: Vector2i in maze.open_cells:
		var k: String = maze.kind[c]
		var front := k in ["fire", "op", "sap"] and not maze.open_cells.has(c + Vector2i(0, -1))
		var back := k in ["fire", "traverse", "support"] and not maze.open_cells.has(c + Vector2i(0, 1)) and rng.randf() < 0.6
		for pass_ in 2:
			if (pass_ == 0 and not front) or (pass_ == 1 and not back):
				continue
			var dir := Vector2i(0, -1) if pass_ == 0 else Vector2i(0, 1)
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
						continue                # a loophole
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
		var r := maze._rect(c)
		var z_edge := c.y * maze.cell + TrenchMaze.EDGE
		var depth_ := z_edge - r.position.y
		var x0 := r.position.x + 0.05
		var x1 := r.end.x - 0.05
		var cx := (x0 + x1) * 0.5
		var top := maze.ground_height(cx, z_edge - depth_ * 0.5)
		var base := maze.ground_height(cx, z_edge + 0.2)
		_box("step_planks", planks, Vector3(cx, top - 0.02, z_edge - depth_ * 0.5), Basis(), Vector3(x1 - x0, 0.05, depth_))
		var h := top - base
		if h > 0.1:
			_box("step_planks", planks, Vector3(cx, base + h * 0.5, z_edge + 0.01), Basis(), Vector3(x1 - x0, h + 0.05, 0.04))


# --- duckboards --------------------------------------------------------------------
func _duckboards() -> void:
	var wood := _mat("board", 1.0)
	var dark := _mat("timber", 0.8)
	for d: Dictionary in maze.duckboards:
		var a: Vector3 = d.a
		var b: Vector3 = d.b
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var along := (b - a).normalized()
		var flat := Vector3(along.x, 0, along.z).normalized()
		var side := flat.cross(Vector3.UP).normalized()
		var basis := Basis(side, along.cross(side).normalized(), -along).orthonormalized()
		# two runners under the slats, sagging a little
		for s in [-0.24, 0.24]:
			var mid: Vector3 = (a + b) * 0.5 + side * float(s) + Vector3.DOWN * 0.065
			_box("db_runners", dark, mid, basis, Vector3(0.06, 0.07, length))
		var n := int(length / 0.2)
		for i in n:
			var t := (i + 0.5) / n
			if rng.randf() < float(d.broken) * 0.8:
				continue                          # a missing slat: the water under it shows
			var p := a.lerp(b, t)
			var bb := basis
			var drop := 0.0
			if rng.randf() < float(d.broken):
				bb = bb.rotated(along, rng.randf_range(-0.25, 0.25)).rotated(side, rng.randf_range(-0.15, 0.15))
				drop = rng.randf_range(0.02, 0.07)
			bb = bb.rotated(Vector3.UP, rng.randf_range(-0.03, 0.03))
			var w := rng.randf_range(0.6, 0.66)
			_box("db_slats", wood, p + Vector3.DOWN * (0.015 + drop) + side * rng.randf_range(-0.02, 0.02), bb, Vector3(w, 0.035, 0.12))


# --- water -------------------------------------------------------------------------------
func _water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water_mud.gdshader")
	mat.set_shader_parameter("noise_tex", tex("noise"))
	for wa: Dictionary in maze.water:
		var r: Rect2 = wa.rect
		var pm := PlaneMesh.new()
		pm.size = r.size
		pm.subdivide_width = 0
		pm.subdivide_depth = 0
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.get_center().x, wa.level, r.get_center().y)
		add_child(mi)


# --- landmarks -----------------------------------------------------------------------------
func _landmarks() -> void:
	for l: Dictionary in maze.landmarks:
		match String(l.kind):
			"exit":
				_bunker_portal(l.cell, l.dir)
			"dugout":
				_dugout(l)
			"tree":
				_tree(l.cell)
			"gunpit":
				_gun(l)
			"op":
				_op(l.cell)


## The way down: a concrete bunker entrance in the end wall of the fire trench.
func _bunker_portal(c: Vector2i, dir: Vector2i) -> void:
	var conc := _mat("timber", 0.8)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.36, 0.35, 0.33)
	cm.roughness = 0.85
	cm.albedo_texture = load("res://art/level/wall_conc.png")
	cm.uv1_triplanar = true
	cm.uv1_world_triplanar = true
	cm.uv1_scale = Vector3.ONE * 0.5
	var e := _edge(c, dir)
	var mid: Vector2 = (e.a + e.b) * 0.5
	var inward := Vector3(-dir.x, 0, -dir.y)
	var along := Vector3(dir.y, 0, dir.x)
	var base := maze.floor_height(Vector3(mid.x, 0, mid.y) + inward * 0.5)
	var p := Vector3(mid.x, base, mid.y)
	var b := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	# a squat concrete face with a doorway, steel lintel, the clown's mark
	_box("conc", cm, p + Vector3.UP * 1.25 - inward * 0.25, b, Vector3(2.6, 2.6, 0.5))
	_box("conc", cm, p + Vector3.UP * 2.3 + inward * 0.05, b, Vector3(2.0, 0.35, 0.2))
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.03, 0.03, 0.03)
	_box("portal_dark", door, p + Vector3.UP * 1.05 + inward * 0.02, b, Vector3(1.15, 2.1, 0.05))
	_collide(p + Vector3.UP * 1.25 - inward * 0.25, b, Vector3(2.6, 2.6, 0.5))
	var sign := Label3D.new()
	sign.text = "H.Q. BUNKER"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.modulate = Color(0.85, 0.82, 0.75)
	sign.position = p + Vector3.UP * 2.62 + inward * 0.16
	sign.basis = Basis.looking_at(-inward, Vector3.UP)
	add_child(sign)


## A dugout: a timber-framed entrance off the trench, a roof of beams,
## corrugated iron and sandbags over the pit, and a lantern inside.
func _dugout(l: Dictionary) -> void:
	var timber := _mat("timber", 0.8)
	var iron := _mat("iron", 1.0)
	var cells: Array[Vector2i] = []
	for c: Vector2i in maze.open_cells:
		if maze.kind[c] == "dugout" and Vector2(c).distance_to(Vector2(l.cell)) < 2.5:
			cells.append(c)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in cells:
		lo = lo.min(Vector2(c) * maze.cell)
		hi = hi.max((Vector2(c) + Vector2.ONE) * maze.cell)
	var mid := (lo + hi) * 0.5
	var floor_y := maze.floor_height(Vector3(mid.x, 0, mid.y))
	var roof_y := floor_y + 2.05
	var size := hi - lo + Vector2(0.4, 0.4)
	# beams across, iron over them, bags on top
	var n := int(size.x / 0.45)
	for i in n:
		var x := lo.x - 0.2 + (i + 0.5) * size.x / n
		_box("dug_beams", timber, Vector3(x, roof_y, mid.y), Basis(), Vector3(0.14, 0.16, size.y))
	_box("dug_iron", iron, Vector3(mid.x, roof_y + 0.1, mid.y), Basis(), Vector3(size.x, 0.03, size.y))
	var bag := _mat("burlap", 0.5)
	var mesh := _bag_mesh()
	for r in 2:
		for i in int(size.x / 0.5):
			for j in int(size.y / 0.32):
				var p := Vector3(lo.x - 0.1 + (i + 0.5) * 0.5 + (0.25 if j % 2 else 0.0), roof_y + 0.18 + r * 0.13, lo.y - 0.1 + (j + 0.5) * 0.32)
				if p.x > hi.x + 0.15:
					continue
				_add("bags", mesh, bag, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p))
	_collide(Vector3(mid.x, roof_y + 0.12, mid.y), Basis(), Vector3(size.x, 0.3, size.y))
	# entrance frame where the stub meets it
	var ent: Vector2i = l.entrance
	var dir: Vector2i = l.dir
	var e := _edge(ent, dir)
	var fm: Vector2 = (e.a + e.b) * 0.5 + Vector2(dir) * 0.05
	var fy := maze.floor_height(Vector3(fm.x, 0, fm.y))
	var across := Vector3(dir.y, 0, dir.x)
	for s in [-0.55, 0.55]:
		_box("dug_beams", timber, Vector3(fm.x, fy + 1.0, fm.y) + across * s, Basis(), Vector3(0.14, 2.1, 0.14))
	_box("dug_beams", timber, Vector3(fm.x, fy + 2.0, fm.y), Basis(Vector3.UP, PI * 0.5 if dir.y == 0 else 0.0), Vector3(1.35, 0.16, 0.16))
	# a lantern burning inside: warm light in the cold day
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.68, 0.38)
	lamp.light_energy = 1.4
	lamp.omni_range = 4.5
	lamp.shadow_enabled = false
	lamp.position = Vector3(mid.x, floor_y + 1.6, mid.y)
	add_child(lamp)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.8, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.65, 0.3)
	glass.emission_energy_multiplier = 3.0
	_box("lantern", glass, lamp.position + Vector3.DOWN * 0.05, Basis(), Vector3(0.1, 0.16, 0.1))


## The shattered tree: a stripped trunk snapped off, splintered at the top.
func _tree(c: Vector2i) -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.17, 0.15, 0.13)
	bark.roughness = 0.9
	bark.albedo_texture = tex("timber")
	bark.uv1_scale = Vector3(1, 3, 1)
	# on the top ground beside the junction, the side with most room
	var best := Vector2.ZERO
	for dir in Maze.DIRS:
		if not maze.open_cells.has(c + dir):
			best = Vector2(dir)
			break
	var base2 := (Vector2(c) + Vector2(0.5, 0.5)) * maze.cell + best * (maze.cell * 0.5 + 1.1)
	var y := maze.ground_height(base2.x, base2.y) - 0.3
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.34
	trunk.height = 4.6
	trunk.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = trunk
	mi.material_override = bark
	mi.position = Vector3(base2.x, y + 2.3, base2.y)
	mi.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))
	add_child(mi)
	var top := mi.position + mi.basis.y * 2.3
	for i in 6:
		var sp := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.3, 0.9)
		_box("splinters", bark, top + sp + mi.basis.y * h * 0.5, mi.basis * Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0.0, 0.25)), Vector3(0.05, h, 0.04))
	for i in 2:
		var at := mi.position + mi.basis.y * rng.randf_range(0.0, 1.8)
		var dir := Vector3(cos(i * 2.6 + 0.4), 0.5, sin(i * 2.6 + 0.4)).normalized()
		var length := rng.randf_range(0.6, 1.3)
		_box("splinters", bark, at + dir * length * 0.5, Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT), Vector3(0.09, 0.09, length))
	var cs_pos := mi.position
	_collide(cs_pos, mi.basis, Vector3(0.5, 4.6, 0.5))


## A ruined field gun in its pit: wheels, a snapped trail, the barrel down.
func _gun(l: Dictionary) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.18, 0.15)
	steel.roughness = 0.6
	steel.metallic = 0.4
	var wood := _mat("timber", 0.8)
	var cells: Array[Vector2i] = []
	for c: Vector2i in maze.open_cells:
		if maze.kind[c] == "gunpit" and Vector2(c).distance_to(Vector2(l.cell)) < 3.5:
			cells.append(c)
	var mid := Vector3.ZERO
	for c in cells:
		mid += Vector3((c.x + 0.5) * maze.cell, 0, (c.y + 0.5) * maze.cell)
	mid /= maxf(cells.size(), 1)
	mid.y = maze.floor_height(mid)
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	for s in [-0.75, 0.75]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.6
		wheel.bottom_radius = 0.6
		wheel.height = 0.1
		wheel.radial_segments = 14
		var mi := MeshInstance3D.new()
		mi.mesh = wheel
		mi.material_override = wood
		mi.basis = b * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		mi.position = mid + b * Vector3(s, 0.55, 0)
		add_child(mi)
	_box("gun_steel", steel, mid + b * Vector3(0, 0.75, 0.3), b * Basis(Vector3.RIGHT, -0.12), Vector3(0.18, 0.18, 2.3))
	_box("gun_steel", steel, mid + b * Vector3(0, 0.95, -0.35), b * Basis(Vector3.RIGHT, 0.1), Vector3(1.5, 0.9, 0.04))
	_box("gun_steel", steel, mid + b * Vector3(0.05, 0.3, -1.4), b * Basis(Vector3.UP, 0.25) * Basis(Vector3.RIGHT, 0.3), Vector3(0.14, 0.12, 1.7))
	_collide(mid + b * Vector3(0, 0.7, 0), b, Vector3(1.6, 1.3, 1.2))


## The observation post at the head of a sap: sandbags round it and a periscope.
func _op(c: Vector2i) -> void:
	var p := maze.cell_center(c)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.21, 0.18)
	steel.roughness = 0.55
	var top := maze.ground_height(p.x, p.z - 1.0)
	_box("periscope", steel, Vector3(p.x + 0.3, (p.y + top) * 0.5 + 0.4, p.z - 0.55), Basis(), Vector3(0.07, top - p.y + 0.8, 0.09))
	_box("periscope", steel, Vector3(p.x + 0.3, top + 0.75, p.z - 0.58), Basis(), Vector3(0.09, 0.12, 0.14))


# --- the far battlefield ---------------------------------------------------------------------
## Beyond the carved ground: the battlefield to the horizon, low and coarse,
## churned and shell-holed toward No Man's Land (z < 0), lost in haze.
func _far() -> void:
	var m := maze
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mud_terrain.gdshader")
	for pair: Array in [["churned", "mud_churned"], ["sludge", "mud_sludge"], ["wall", "soil_wall"], ["firm", "ground_firm"]]:
		mat.set_shader_parameter(pair[0] + "_a", tex(pair[1]))
		mat.set_shader_parameter(pair[0] + "_n", tex(pair[1] + "_n"))
		mat.set_shader_parameter(pair[0] + "_r", tex(pair[1] + "_r"))
	mat.set_shader_parameter("noise_tex", tex("noise"))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var holes := FastNoiseLite.new()
	holes.seed = rng.randi()
	holes.noise_type = FastNoiseLite.TYPE_CELLULAR
	holes.frequency = 0.09
	var inner := Rect2(m.origin, Vector2((m.hx - 1) * TrenchMaze.RES, (m.hz - 1) * TrenchMaze.RES))
	var step := 2.5
	var reach := 260.0
	var lo := inner.position - Vector2.ONE * reach
	var n := int((inner.size.x + reach * 2.0) / step) + 1
	var nz := int((inner.size.y + reach * 2.0) / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize(n * nz)
	for iz in nz:
		for ix in n:
			var x := lo.x + ix * step
			var z := lo.y + iz * step
			var q := Vector2(x, z)
			var h := noise.get_noise_2d(x, z) * 2.2
			# shell holes everywhere out there, thickest in No Man's Land
			var nml := 1.0 - smoothstep(-30.0, 10.0, z)
			var cell := holes.get_noise_2d(x, z)
			h += (minf(cell, 0.2) - 0.2) * (1.2 + 1.8 * nml)
			# meet the carved ground at its edge
			var dx := maxf(maxf(inner.position.x - x, x - inner.end.x), 0.0)
			var dz := maxf(maxf(inner.position.y - z, z - inner.end.y), 0.0)
			var out := Vector2(dx, dz).length()
			var edge_h := m.ground_height(clampf(x, inner.position.x, inner.end.x), clampf(z, inner.position.y, inner.end.y))
			h = lerpf(edge_h - 0.04, h, smoothstep(0.0, 25.0, out))
			if out <= 0.0:
				h = edge_h - 0.12              # under the carved ground: hidden
			hs[ix + iz * n] = h
	for iz in nz:
		for ix in n:
			var i := ix + iz * n
			var hl := hs[maxi(ix - 1, 0) + iz * n]
			var hr := hs[mini(ix + 1, n - 1) + iz * n]
			var hd := hs[ix + maxi(iz - 1, 0) * n]
			var hu := hs[ix + mini(iz + 1, nz - 1) * n]
			var x := lo.x + ix * step
			var z := lo.y + iz * step
			st.set_normal(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			var nml := 1.0 - smoothstep(-30.0, 10.0, z)
			st.set_color(Color(0.6, 0.0, lerpf(1.0, 0.4, nml), 0.5))
			st.add_vertex(Vector3(x, hs[i], z))
	for iz in nz - 1:
		for ix in n - 1:
			var x := lo.x + (ix + 0.5) * step
			var z := lo.y + (iz + 0.5) * step
			if inner.grow(-step).has_point(Vector2(x, z)):
				continue
			var a := ix + iz * n
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	var mi := MeshInstance3D.new()
	mi.name = "Battlefield"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
