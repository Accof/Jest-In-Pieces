class_name Clockwork
## Meshes and materials for clockwork insides: gears, springs, rods, wires,
## panels and porcelain. Shared by the Klappersoldat's dressing and by the
## mechanical side of ClownGore. Everything is built once and cached.

static var _cache := {}


# --- materials ------------------------------------------------------------------
## "brass", "steel", "iron", "copper", "wire_red", "wire_black", "porcelain",
## "rust", "oil", "amber" (glowing eye), "panel".
static func mat(kind: String) -> StandardMaterial3D:
	var key := "m_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		"brass":
			m.albedo_color = Color(0.62, 0.45, 0.2); m.metallic = 0.9; m.roughness = 0.38
		"steel":
			m.albedo_color = Color(0.42, 0.43, 0.44); m.metallic = 0.85; m.roughness = 0.42
		"iron":
			m.albedo_color = Color(0.14, 0.13, 0.12); m.metallic = 0.7; m.roughness = 0.62
		"panel":
			m.albedo_color = Color(0.2, 0.2, 0.19); m.metallic = 0.75; m.roughness = 0.5
		"copper":
			m.albedo_color = Color(0.6, 0.3, 0.17); m.metallic = 0.85; m.roughness = 0.4
		"wire_red":
			m.albedo_color = Color(0.42, 0.06, 0.05); m.roughness = 0.6
		"wire_black":
			m.albedo_color = Color(0.05, 0.05, 0.05); m.roughness = 0.55
		"porcelain":
			m.albedo_color = Color(0.84, 0.8, 0.72); m.roughness = 0.22
		"rust":
			m.albedo_color = Color(0.3, 0.14, 0.07); m.metallic = 0.3; m.roughness = 0.85
		"oil":
			m.albedo_color = Color(0.02, 0.018, 0.015); m.roughness = 0.08; m.metallic = 0.2
		"amber":
			m.albedo_color = Color(1.0, 0.6, 0.2)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.12)
			m.emission_energy_multiplier = 4.0
		"red_nose":
			m.albedo_color = Color(0.45, 0.06, 0.05); m.roughness = 0.35
	_cache[key] = m
	return m


# --- meshes ---------------------------------------------------------------------
## A spur gear lying in the XY plane (axle along Z), `teeth` teeth, 1 m across
## the tips; scale it to size. `hub` is the axle hole as a fraction.
static func gear(teeth: int = 12) -> Mesh:
	var key := "gear_%d" % teeth
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline: Array[Vector2] = []
	var r_tip := 0.5
	var r_root := 0.5 - minf(0.12, 1.6 / teeth)
	for i in teeth:
		var a := TAU * i / teeth
		var step := TAU / teeth
		for k: Array in [[0.0, r_root], [0.18, r_tip], [0.5, r_tip], [0.68, r_root]]:
			var aa: float = a + step * k[0]
			outline.append(Vector2(cos(aa), sin(aa)) * k[1])
	var hub := 0.1
	var half := 0.08          # thickness 0.16 of the diameter
	# faces: a ring from the hub out to the toothed rim, front and back
	var n := outline.size()
	for z: float in [half, -half]:
		var nz := Vector3(0, 0, signf(z))
		for i in n:
			var p0 := outline[i]
			var p1 := outline[(i + 1) % n]
			var h0 := p0.normalized() * hub
			var h1 := p1.normalized() * hub
			for v: Vector2 in [h0, p0, p1, h0, p1, h1]:
				st.set_normal(nz)
				st.add_vertex(Vector3(v.x, v.y, z))
	# the rim, round every tooth
	for i in n:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var e := (p1 - p0)
		var nn := Vector3(e.y, -e.x, 0).normalized()
		for v: Vector3 in [Vector3(p0.x, p0.y, half), Vector3(p0.x, p0.y, -half), Vector3(p1.x, p1.y, -half), Vector3(p0.x, p0.y, half), Vector3(p1.x, p1.y, -half), Vector3(p1.x, p1.y, half)]:
			st.set_normal(nn)
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat("brass"))
	_cache[key] = mesh
	return mesh


## A coil spring along +Y, 1 m long and 1 m across; scale it.
static func spring(turns: float = 6.0) -> Mesh:
	var key := "spring_%d" % int(turns * 10)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := int(turns * 14)
	var ring := 6
	var wire := 0.05
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		var a := TAU * turns * t
		pts.append(Vector3(cos(a) * 0.45, t - 0.5, sin(a) * 0.45))
	for i in segs:
		var a := pts[i]
		var b := pts[i + 1]
		var fwd := (b - a).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		var up := side.cross(fwd).normalized()
		for k in ring:
			var a0 := TAU * k / ring
			var a1 := TAU * (k + 1) / ring
			var o0 := (side * cos(a0) + up * sin(a0)) * wire
			var o1 := (side * cos(a1) + up * sin(a1)) * wire
			for v: Vector3 in [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]:
				st.set_normal((v - (a if v.distance_to(a) < v.distance_to(b) else b)).normalized())
				st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat("steel"))
	_cache[key] = mesh
	return mesh


## A cylinder along +Y, 1 m long and 1 m across.
static func rod() -> Mesh:
	if not _cache.has("rod"):
		var c := CylinderMesh.new()
		c.top_radius = 0.5
		c.bottom_radius = 0.5
		c.height = 1.0
		c.radial_segments = 10
		c.rings = 1
		_cache["rod"] = c
	return _cache["rod"]


static func box() -> Mesh:
	if not _cache.has("box"):
		_cache["box"] = BoxMesh.new()
	return _cache["box"]


static func ball() -> Mesh:
	if not _cache.has("ball"):
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 12
		s.rings = 6
		_cache["ball"] = s
	return _cache["ball"]


## A ring (a wind-up key's bow), lying in the XY plane, 1 m across.
static func loop() -> Mesh:
	if not _cache.has("loop"):
		var t := TorusMesh.new()
		t.inner_radius = 0.34
		t.outer_radius = 0.5
		t.rings = 18
		t.ring_segments = 8
		_cache["loop"] = t
	return _cache["loop"]


## A jagged flat shard (porcelain or sheet metal) about 1 m across; scale it.
static func shard(seed_: int) -> Mesh:
	var key := "shard_%d" % seed_
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	var k := rng.randi_range(4, 6)
	for i in k:
		var a := TAU * i / k + rng.randf_range(-0.3, 0.3)
		pts.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.25, 0.5))
	for z: float in [0.04, -0.04]:
		for i in k:
			for v: Vector2 in [Vector2.ZERO, pts[i], pts[(i + 1) % k]]:
				st.set_normal(Vector3(0, 0, signf(z)))
				st.add_vertex(Vector3(v.x, v.y, z))
	for i in k:
		var a := pts[i]
		var b := pts[(i + 1) % k]
		var nn := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		for v: Vector3 in [Vector3(a.x, a.y, 0.04), Vector3(a.x, a.y, -0.04), Vector3(b.x, b.y, -0.04), Vector3(a.x, a.y, 0.04), Vector3(b.x, b.y, -0.04), Vector3(b.x, b.y, 0.04)]:
			st.set_normal(nn)
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat("panel"))
	_cache[key] = mesh
	return mesh


# --- placing parts -----------------------------------------------------------------
## Add a mesh part under `parent` at `pos` with `size` (per-axis scale) and
## rotation `rot` (euler, radians). Returns it.
static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.layers = 2
	mi.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)
	parent.add_child(mi)
	return mi


## A rod (or wire) running from `a` to `b`, `thick` across.
static func span(parent: Node3D, material: Material, a: Vector3, b: Vector3, thick: float) -> MeshInstance3D:
	var y := b - a
	var len := y.length()
	if len < 0.0001:
		return null
	y /= len
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var mi := MeshInstance3D.new()
	mi.mesh = rod()
	mi.material_override = material
	mi.layers = 2
	mi.transform = Transform3D(Basis(x * thick, y * len, z * thick), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


## A sagging cable from `a` to `b` in a few straight pieces.
static func cable(parent: Node3D, material: Material, a: Vector3, b: Vector3, sag: float, thick: float) -> void:
	var prev := a
	var n := 4
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		span(parent, material, prev, p, thick)
		prev = p


## A gear (axle along `axis`), `size` across the tips. Returns the node, so a
## caller can spin it.
static func gear_at(parent: Node3D, pos: Vector3, size: float, axis: Vector3, teeth: int = 12, material_kind: String = "brass") -> MeshInstance3D:
	var z := axis.normalized()
	var x := z.cross(Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var y := z.cross(x)
	var mi := MeshInstance3D.new()
	mi.mesh = gear(teeth)
	mi.material_override = mat(material_kind)
	mi.layers = 2
	mi.transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * size), pos)
	parent.add_child(mi)
	return mi
