class_name FrontLights
extends Node3D
## (24 Nov 2026) Light to find the way by at dawn and at night: the moon
## alone left the trenches black and No Man's Land a guess. Three kinds,
## all warm, all flickering, none casting a shadow (the sun's splits and
## the frame budget stay as M6/M12 left them):
##
##   lanterns   hurricane lanterns hung from a short post arm on the trench's
##              back wall every 12-18 m along both networks, and one beside
##              every dugout door; a small flame in the glass, a 7 m glow
##   braziers   a perforated oil drum burning at a junction or a traverse
##              corner, a few a side: flames, embers, a thin smoke, an 11 m glow
##   wreck fires burning timber out in No Man's Land, along the crossing
##              every 25 m or so and a couple off it, 14 m of glow each: the
##              way across is a line of fires
##
## At night everything burns. At dawn the braziers and wreck fires still do
## and half the lanterns have been put out. By day nothing is built (the
## approved look, D-16/D-18, is untouched).
##
## Built by FrontArt after the fog, from the maze's seed; ticks the flicker
## itself. `lanterns`, `braziers`, `wreck_fires` count for the tests.

const SHEET := preload("res://art/level/fx_flame_sheet.png")
const FLAME_SHADER := preload("res://shaders/flame_sheet.gdshader")
const DRUM_SHADER := preload("res://shaders/brazier_drum.gdshader")

const LANTERN_EVERY := Vector2(6, 9)       # cells between lanterns along a trench (12-18 m)
const BRAZIERS_PER_SIDE := Vector2i(3, 5)
const WRECK_EVERY := 12                    # route cells between wreck fires in No Man's Land (24 m)
const LANTERN_COLOUR := Color(1.0, 0.70, 0.40)
const FIRE_COLOUR := Color(1.0, 0.56, 0.25)

var maze: FrontMaze
var light := FrontVariant.Light.NIGHT
var lanterns := 0
var braziers := 0
var wreck_fires := 0

var _rng := RandomNumberGenerator.new()
var _lights: Array = []          # [OmniLight3D, base energy, phase, kind]
var _t := 0.0
var _flame_mat: ShaderMaterial
var _lantern_parts := {}         # name -> [Mesh, Material, Array[Transform3D]]
var _lantern_flames: Array[Transform3D] = []
var _lantern_phases: Array[float] = []


func setup(m: FrontMaze, seed_: int, at_light: int) -> void:
	maze = m
	light = at_light as FrontVariant.Light
	_rng.seed = seed_
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("sheet", SHEET)
	_flame_mat.render_priority = 2
	_lanterns()
	_braziers()
	_wrecks()
	_commit_lanterns()
	set_process(true)


# --- lanterns --------------------------------------------------------------------------
func _lanterns() -> void:
	var dawn := light == FrontVariant.Light.DAWN
	var spots: Array[Vector3] = []
	# beside every dugout door
	for l: Dictionary in maze.landmarks:
		if l.kind != "dugout" or not l.has("entrance"):
			continue
		var c: Vector2i = l.entrance
		var dir: Vector2i = l.dir
		var e := _edge(c, dir)
		var along: Vector2 = (e.b - e.a).normalized()
		var p2: Vector2 = (e.a + e.b) * 0.5 + along * 0.75 + e.inward * 0.22
		var p := Vector3(p2.x, maze.floor_height(Vector3(p2.x, 0, p2.y)), p2.y)
		if _hang(p, Vector3(e.inward.x, 0, e.inward.y), dawn):
			spots.append(p)
	# along the trenches: every 12-18 m, on the back wall (the parados side)
	for side: Dictionary in [maze.ours, maze.theirs]:
		var cells: Array = side.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * 1000 + a.x < b.y * 1000 + b.x)
		var gap := _rng.randi_range(int(LANTERN_EVERY.x), int(LANTERN_EVERY.y))
		var since := 0
		for c: Vector2i in cells:
			var k: String = maze.kind.get(c, "")
			if not (k in ["fire", "support", "traverse", "junction", "comm"]):
				continue
			since += 1
			if since < gap:
				continue
			var f := maze.facing_of(c)
			var fd := Vector2i(0, -1) if f == -1 else Vector2i(0, 1)
			var back := -fd
			if maze.open_cells.has(c + back):
				back = Vector2i(1, 0) if _rng.randf() < 0.5 else Vector2i(-1, 0)
				if maze.open_cells.has(c + back):
					continue
			var e := _edge(c, back)
			var along: Vector2 = (e.b - e.a).normalized()
			var p2: Vector2 = (e.a + e.b) * 0.5 + along * _rng.randf_range(-0.5, 0.5) + e.inward * 0.22
			var p := Vector3(p2.x, maze.floor_height(Vector3(p2.x, 0, p2.y)), p2.y)
			var near := false
			for s in spots:
				if s.distance_to(p) < 7.0:
					near = true
			if near:
				continue
			if _hang(p, Vector3(e.inward.x, 0, e.inward.y), dawn):
				spots.append(p)
				since = 0
				gap = _rng.randi_range(int(LANTERN_EVERY.x), int(LANTERN_EVERY.y))


## A post against the wall at `foot` with a short arm out over the trench,
## the lantern hanging from it. At dawn half of them are out (no flame, no
## light; the lantern still hangs there).
func _hang(foot: Vector3, inward: Vector3, dawn: bool) -> bool:
	var lit := not dawn or _rng.randf() < 0.5
	var post_h := 1.95
	var basis := Basis.looking_at(inward, Vector3.UP) if inward.length() > 0.1 else Basis.IDENTITY
	_part("post", Transform3D(basis, foot + Vector3.UP * post_h * 0.5 - inward * 0.06))
	var arm_at := foot + Vector3.UP * (post_h - 0.08) + inward * 0.15
	_part("arm", Transform3D(basis, arm_at))
	var hang := foot + Vector3.UP * (post_h - 0.12) + inward * 0.3
	var sway := _rng.randf_range(-0.06, 0.06)
	var lb := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).rotated(Vector3.RIGHT, sway)
	_part("handle", Transform3D(lb, hang - Vector3.UP * 0.05))
	_part("cap", Transform3D(lb, hang - Vector3.UP * 0.12))
	_part("glass", Transform3D(lb, hang - Vector3.UP * 0.21))
	_part("tank", Transform3D(lb, hang - Vector3.UP * 0.31))
	if lit:
		_lantern_flames.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.07, 0.1, 1.0)), hang - Vector3.UP * 0.21))
		_lantern_phases.append(_rng.randf())
		var omni := _omni(LANTERN_COLOUR, 2.4, 8.0, 1.6)
		omni.position = hang - Vector3.UP * 0.2 + inward * 0.05
		_lights.append([omni, omni.light_energy, _rng.randf() * TAU, "lantern"])
	lanterns += 1
	return true


func _part(name: String, xf: Transform3D) -> void:
	if not _lantern_parts.has(name):
		_lantern_parts[name] = [_lantern_mesh(name), _lantern_material(name), []]
	(_lantern_parts[name][2] as Array).append(xf)


func _lantern_mesh(name: String) -> Mesh:
	match name:
		"post":
			var b := BoxMesh.new()
			b.size = Vector3(0.09, 1.95, 0.09)
			return b
		"arm":
			var b := BoxMesh.new()
			b.size = Vector3(0.05, 0.05, 0.42)
			return b
		"handle":
			var t := TorusMesh.new()
			t.inner_radius = 0.045
			t.outer_radius = 0.052
			t.rings = 12
			t.ring_segments = 6
			return t
		"cap":
			var c := CylinderMesh.new()
			c.top_radius = 0.02
			c.bottom_radius = 0.06
			c.height = 0.07
			c.radial_segments = 10
			return c
		"glass":
			var c := CylinderMesh.new()
			c.top_radius = 0.045
			c.bottom_radius = 0.05
			c.height = 0.12
			c.radial_segments = 12
			return c
		_:
			var c := CylinderMesh.new()
			c.top_radius = 0.058
			c.bottom_radius = 0.052
			c.height = 0.085
			c.radial_segments = 12
			return c


func _lantern_material(name: String) -> Material:
	var m := StandardMaterial3D.new()
	match name:
		"post", "arm":
			m.albedo_color = Color(0.22, 0.16, 0.11)
			m.roughness = 0.92
		"glass":
			m.albedo_color = Color(1.0, 0.72, 0.42, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.emission_enabled = true
			m.emission = Color(1.0, 0.62, 0.3)
			m.emission_energy_multiplier = 0.9
			m.roughness = 0.15
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.albedo_color = Color(0.3, 0.28, 0.25)
			m.metallic = 0.7
			m.roughness = 0.55
	return m


func _commit_lanterns() -> void:
	for name: String in _lantern_parts:
		var e: Array = _lantern_parts[name]
		var xfs: Array = e[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e[0]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "lantern_" + name
		mmi.multimesh = mm
		mmi.material_override = e[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	if not _lantern_flames.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		q.center_offset = Vector3(0, 0.5, 0)
		mm.mesh = q
		mm.instance_count = _lantern_flames.size()
		for i in _lantern_flames.size():
			mm.set_instance_transform(i, _lantern_flames[i])
			mm.set_instance_custom_data(i, Color(_lantern_phases[i], 1.1, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "lantern_flames"
		mmi.multimesh = mm
		var mat := _flame_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("flicker", 0.35)
		mat.set_shader_parameter("brightness", 1.4)
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- braziers --------------------------------------------------------------------------
func _braziers() -> void:
	for side: Dictionary in [maze.ours, maze.theirs]:
		var want := _rng.randi_range(BRAZIERS_PER_SIDE.x, BRAZIERS_PER_SIDE.y)
		var cands: Array = []
		for c: Vector2i in side.keys():
			var k: String = maze.kind.get(c, "")
			if k in ["junction", "traverse", "fire"]:
				cands.append(c)
		cands.shuffle()
		var placed: Array[Vector3] = []
		for c: Vector2i in cands:
			if placed.size() >= want:
				break
			var r := maze._rect(c)
			# in a corner of the cell, out of the way
			var cx := r.position.x + (0.45 if _rng.randf() < 0.5 else r.size.x - 0.45)
			var cz := r.position.y + (0.45 if _rng.randf() < 0.5 else r.size.y - 0.45)
			var p := Vector3(cx, 0, cz)
			p.y = maze.floor_height(p)
			var ok := true
			for o in placed:
				if o.distance_to(p) < 16.0:
					ok = false
			if not ok:
				continue
			_brazier(p)
			placed.append(p)


## An oil drum with holes cut round its top third, burning: the drum, the
## fire in its mouth, embers, a little smoke, the glow.
func _brazier(at: Vector3) -> void:
	var drum := CylinderMesh.new()
	drum.top_radius = 0.29
	drum.bottom_radius = 0.29
	drum.height = 0.88
	drum.radial_segments = 14
	var dm := ShaderMaterial.new()
	dm.shader = DRUM_SHADER
	dm.set_shader_parameter("phase", _rng.randf() * TAU)
	var mi := MeshInstance3D.new()
	mi.mesh = drum
	mi.material_override = dm
	mi.position = at + Vector3.UP * 0.44
	mi.rotation.y = _rng.randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cs := StaticBody3D.new()
	cs.collision_layer = 1
	var sh := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.9
	sh.shape = cyl
	cs.add_child(sh)
	cs.position = mi.position
	cs.set_meta(&"surface", "metal")
	add_child(cs)
	_fire(at + Vector3.UP * 0.8, 0.75, 1.0)
	var omni := _omni(FIRE_COLOUR, 6.0, 12.0, 1.4)
	omni.position = at + Vector3.UP * 1.3
	_lights.append([omni, omni.light_energy, _rng.randf() * TAU, "brazier"])
	braziers += 1


# --- wreck fires in No Man's Land --------------------------------------------------------
func _wrecks() -> void:
	var z_ours := (maze.our_row0 + TrenchMaze.FIRE_ROW) * maze.cell
	var z_theirs := (maze.their_row0 + TrenchMaze.GRID_D - 1 - TrenchMaze.FIRE_ROW) * maze.cell
	var lo := minf(z_ours, z_theirs) + 6.0
	var hi := maxf(z_ours, z_theirs) - 6.0
	var placed: Array[Vector3] = []
	# along the crossing: a fire every WRECK_EVERY route cells, a few metres
	# off the path so it lights the way without blocking it
	var since := _rng.randi_range(3, WRECK_EVERY)
	for c: Vector2i in maze.route:
		var centre := maze.cell_center(c)
		if centre.z < lo or centre.z > hi:
			continue
		since += 1
		if since < WRECK_EVERY:
			continue
		var p := _off_route(centre, placed)
		if p == Vector3.INF:
			continue
		_wreck(p)
		placed.append(p)
		since = 0
	# and a couple off it, so the field is not only the one line
	for _i in 2:
		for _try in 12:
			var x := _rng.randf_range(8.0, maze.w * maze.cell - 8.0)
			var z := _rng.randf_range(lo, hi)
			var p := Vector3(x, 0, z)
			if maze.wire_at(x, z):
				continue
			var ok := true
			for o in placed:
				if o.distance_to(p) < 20.0:
					ok = false
			if not ok:
				continue
			p.y = maze.ground_height(x, z)
			if maze.water_level(p) > p.y:
				continue
			_wreck(p)
			placed.append(p)
			break


func _off_route(centre: Vector3, placed: Array[Vector3]) -> Vector3:
	for _try in 10:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(2.5, 4.5)
		var p := centre + Vector3(cos(a) * d, 0, sin(a) * d)
		if p.x < 4.0 or p.x > maze.w * maze.cell - 4.0 or maze.wire_at(p.x, p.z):
			continue
		var ok := true
		for o in placed:
			if o.distance_to(p) < 12.0:
				ok = false
		if not ok:
			continue
		p.y = maze.ground_height(p.x, p.z)
		if maze.water_level(p) > p.y:
			continue
		return p
	return Vector3.INF


## Burning timber: three charred baulks thrown together, the fire in them.
func _wreck(at: Vector3) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.09, 0.07, 0.06)
	wood.roughness = 0.95
	wood.emission_enabled = true
	wood.emission = Color(1.0, 0.3, 0.05)
	wood.emission_energy_multiplier = 0.5
	var yaw := _rng.randf() * TAU
	for i in 3:
		var b := BoxMesh.new()
		b.size = Vector3(0.14, 0.12, _rng.randf_range(1.1, 1.7))
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.material_override = wood
		var bb := Basis(Vector3.UP, yaw + i * 1.9 + _rng.randf_range(-0.4, 0.4)).rotated(Vector3.RIGHT, _rng.randf_range(-0.25, 0.25))
		mi.transform = Transform3D(bb, at + Vector3.UP * (0.08 + 0.1 * i) + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_fire(at + Vector3.UP * 0.25, 2.0, 1.7)
	var omni := _omni(FIRE_COLOUR, 9.0, 20.0, 1.3)
	omni.position = at + Vector3.UP * 1.6
	_lights.append([omni, omni.light_energy, _rng.randf() * TAU, "wreck"])
	wreck_fires += 1


# --- the fire itself ---------------------------------------------------------------------
## Flames (the sprite sheet, additive), embers drifting up, a thin dark
## smoke. `size` scales the flames, `spread` the base they rise from.
func _fire(at: Vector3, size: float, spread: float) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	# flames
	# the body of the fire: two upright tongues always there at the base
	var fm := _flame_mat.duplicate() as ShaderMaterial
	fm.set_shader_parameter("brightness", 1.25)
	fm.set_shader_parameter("flicker", 0.2)
	for i in 2:
		var core := QuadMesh.new()
		core.size = Vector2(0.62, 0.95) * size
		core.center_offset = Vector3(0, 0.4 * size, 0)
		var cm := _flame_mat.duplicate() as ShaderMaterial
		cm.set_shader_parameter("brightness", 1.5)
		cm.set_shader_parameter("flicker", 0.3)
		cm.set_shader_parameter("frame_rate", 20.0 + 7.0 * i)
		core.material = cm
		var ci := MeshInstance3D.new()
		ci.mesh = core
		ci.position = Vector3(0.05 * spread * (1 if i == 0 else -1), 0, 0.04 * spread * (1 if i == 0 else -1))
		ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ci)
	# and the tongues that rise and go out
	var p := GPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.75) * size
	q.center_offset = Vector3(0, 0.3 * size, 0)
	q.material = fm
	p.draw_pass_1 = q
	p.amount = int(22 * spread)
	p.lifetime = 0.7
	p.randomness = 0.6
	p.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.16, 0.03, 0.16) * spread
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.25 * size
	pm.initial_velocity_max = 0.7 * size
	pm.gravity = Vector3(0, 0.7, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.8))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.85, 0.0))
	grad.add_point(0.12, Color(1.0, 0.9, 0.7, 1.0))
	grad.add_point(0.55, Color(1.0, 0.6, 0.3, 0.8))
	grad.add_point(1.0, Color(0.6, 0.15, 0.03, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
	root.add_child(p)
	# embers
	var e := GPUParticles3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(0.022, 0.022)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	em.vertex_color_use_as_albedo = true
	em.disable_fog = true
	em.albedo_color = Color(1.0, 0.55, 0.2)
	eq.material = em
	e.draw_pass_1 = eq
	e.amount = int(22 * spread)
	e.lifetime = 2.4
	e.randomness = 0.8
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(0.2, 0.1, 0.2) * spread
	epm.direction = Vector3.UP
	epm.spread = 30.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.6
	epm.gravity = Vector3(0, 0.35, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 1.4
	epm.turbulence_noise_scale = 3.0
	epm.turbulence_influence_min = 0.05
	epm.turbulence_influence_max = 0.12
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	eg.add_point(0.5, Color(1.0, 0.4, 0.1, 0.9))
	eg.add_point(1.0, Color(0.5, 0.1, 0.0, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = eg
	epm.color_ramp = egt
	e.process_material = epm
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 6, 6))
	root.add_child(e)
	# smoke: a few dark puffs
	var s := CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.9, 0.9) * size
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://art/level/fx_smoke.png")
	sm.albedo_color = Color(0.08, 0.07, 0.07, 0.35)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.disable_receive_shadows = true
	sq.material = sm
	s.mesh = sq
	s.amount = 8
	s.lifetime = 3.2
	s.randomness = 0.6
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.15 * spread
	s.direction = Vector3.UP
	s.spread = 12.0
	s.initial_velocity_min = 0.5
	s.initial_velocity_max = 0.9
	s.gravity = Vector3(0.25, 0.4, 0)
	s.scale_amount_min = 0.6
	s.scale_amount_max = 1.0
	var scv := Curve.new()
	scv.add_point(Vector2(0, 0.3))
	scv.add_point(Vector2(1, 1.6))
	s.scale_amount_curve = scv
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 0.0))
	sg.add_point(0.2, Color(1, 1, 1, 0.5))
	sg.add_point(1.0, Color(1, 1, 1, 0.0))
	s.color_ramp = sg
	s.position.y = 0.6 * size
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)


func _omni(colour: Color, energy: float, range_: float, atten: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = colour
	o.light_energy = energy
	o.omni_range = range_
	o.omni_attenuation = atten
	o.shadow_enabled = false
	o.set_meta(&"no_shadow_choice", true)
	o.light_specular = 0.6
	add_child(o)
	return o


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
	return {a = a, b = b, inward = Vector2(-dir.x, -dir.y)}


## The flicker: every light breathes on its own phase, a fire more than a lantern.
func _process(delta: float) -> void:
	_t += delta
	for e: Array in _lights:
		var o: OmniLight3D = e[0]
		var ph: float = e[2]
		var fire: bool = e[3] != "lantern"
		var f := sin(_t * 7.1 + ph) * 0.5 + sin(_t * 17.3 + ph * 2.0) * 0.3 + sin(_t * 2.3 + ph * 0.5) * 0.2
		o.light_energy = float(e[1]) * (1.0 + (0.28 if fire else 0.14) * f)
