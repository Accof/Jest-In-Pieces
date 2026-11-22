extends Node
## Surface-aware bullet and blast impacts (Operation Drowned Front, M5, D-07).
## One manager (autoload `Impacts`) that every world hit is reported to — the
## player's hitscan (and so the mounted Maxim), the soldiers' rifles' misses,
## the Rattlejack's gun, explosions — and that answers with the right thing
## for the surface: clods and a dark wet mark in the mud, splinters and a
## hole in timber, pale chips in concrete, a spark and a pockmark on iron,
## dust and fibres from a sandbag, a splash and a ripple on water.
##
## It never touches damage: it is told about a hit after the weapon code has
## done its work, and only draws, sounds and marks. Everything is pooled and
## capped (decals in a ring, one-shot emitters in a pool, a per-frame burst
## budget with an aggregate fallback for automatic fire, distance LOD), so a
## long fight cannot tank the frame rate, and hit detection is never
## throttled to pay for it.
##
## Classification (metadata first, D-07): a `surface` meta on the collider or
## on the CollisionShape3D hit (the dressers set these: "wood", "metal",
## "concrete", "sandbag", "wattle", "earth"); the trench heightfield asks
## `TrenchMaze.surface_at()` (mud / earth / wood / water) and the Front's
## crater water; a bunker's walls are concrete; anything else is "earth".

const MAX_DECALS := 240
const EMITTERS := 40                 ## one-shot debris emitters in the pool
const PUFFS := 28                    ## one-shot dust/mud-spray puff emitters
const RIPPLES := 16
const BURSTS_PER_FRAME := 6          ## beyond this, a hit gets its mark and sound only
const SOUNDS_PER_FRAME := 4
const NEAR_LOD := 45.0               ## past this from the player: mark only
const FAR_LOD := 90.0                ## past this: nothing
const SURFACES := ["mud", "earth", "wood", "concrete", "metal", "sandbag", "water", "wattle"]

var _decals: Array[Decal] = []
var _next := 0
var _emitters: Array[CPUParticles3D] = []
var _em_next := 0
var _puffs: Array[CPUParticles3D] = []
var _puff_next := 0
var _ripples: Array = []             ## [MeshInstance3D, age, life, size]
var _ripple_next := 0
var _tex := {}                       ## surface -> Array[Texture2D] (decal albedo)
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _frame := -1
var _bursts := 0
var _sounds := 0
# counters (tests)
var hits := 0
var by_surface := {}
var aggregated := 0


func _ready() -> void:
	_rng.randomize()
	for s in SURFACES:
		_tex[s] = _make_decal_textures(s)
		by_surface[s] = 0
	for i in MAX_DECALS:
		var d := Decal.new()
		d.visible = false
		d.cull_mask = 1
		d.normal_fade = 0.3
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 12.0
		add_child(d)
		_decals.append(d)
	for i in EMITTERS:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		add_child(p)
		_emitters.append(p)
	for i in PUFFS:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.9
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		p.mesh = _quad()
		p.mesh.material = _mat("puff")
		add_child(p)
		_puffs.append(p)
	for i in RIPPLES:
		var m := MeshInstance3D.new()
		m.mesh = _quad()
		m.material_override = _mat("ripple").duplicate()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_ripples.append([m, 0.0, 0.0, 0.0])


## The floor is torn down: nothing of this floor's marks survives into the next.
func clear() -> void:
	for d in _decals:
		d.visible = false
	for p in _emitters:
		p.emitting = false
		p.restart()
		p.emitting = false
	for p in _puffs:
		p.emitting = false
		p.restart()
		p.emitting = false
	for r in _ripples:
		(r[0] as MeshInstance3D).visible = false
		r[1] = 0.0
		r[2] = 0.0


# --- what was hit ----------------------------------------------------------------------
## The surface at a ray hit (`hit` as PhysicsDirectSpaceState3D gives it).
func classify(hit: Dictionary) -> String:
	var c: Object = hit.get("collider")
	if c == null:
		return "earth"
	var pos: Vector3 = hit.position
	# the shape itself first (a lining in a trench wall, a crate), then its body
	if c is CollisionObject3D and hit.has("shape"):
		var owner_id: int = (c as CollisionObject3D).shape_find_owner(hit.shape)
		var owner: Object = (c as CollisionObject3D).shape_owner_get_owner(owner_id)
		if owner and owner.has_meta(&"surface"):
			return str(owner.get_meta(&"surface"))
	if c.has_meta(&"surface"):
		return str(c.get_meta(&"surface"))
	var parent: Node = (c as Node).get_parent() if c is Node else null
	if parent is TrenchMaze:
		var tm := parent as TrenchMaze
		if tm is FrontMaze and _in_crater_water(tm as FrontMaze, pos):
			return "water"
		var s := tm.surface_at(pos)
		if s == "water" or s == "wood" or s == "mud":
			return s
		# "earth" is the firm ground up top: on the Front it is all saturated mud
		return "mud" if tm is FrontMaze else "earth"
	if parent is Maze:
		return "concrete"
	return "earth"


func _in_crater_water(fm: FrontMaze, pos: Vector3) -> bool:
	for cr: Vector4 in fm.crater_list:
		if cr.w < 0.55:
			continue
		var dxz := Vector2(pos.x - cr.x, pos.z - cr.y).length()
		if dxz > cr.z * 0.7:
			continue
		var level := fm.ground_height(cr.x, cr.y) + cr.w * 0.35
		if pos.y <= level + 0.06:
			return true
	return false


# --- the hits --------------------------------------------------------------------------
## A bullet into the world. `hit` from the ray; `dir` the round's direction;
## `w` the weapon (name, damage) or {} for a soldier's rifle; `energy` scales
## the show (1 rifle, 0.6 pistol, 1.6 Maxim).
func bullet(hit: Dictionary, dir: Vector3, w: Dictionary = {}, energy := 1.0) -> String:
	if hit.is_empty() or not is_inside_tree():
		return ""
	var surface := classify(hit)
	var pos: Vector3 = hit.position
	var n: Vector3 = hit.normal
	if n.length_squared() < 0.5:
		n = -dir
	hits += 1
	by_surface[surface] = int(by_surface.get(surface, 0)) + 1
	var dist := _player_distance(pos)
	if dist > FAR_LOD:
		return surface
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_bursts = 0
		_sounds = 0
	# the mark, always (bounded by the ring)
	if surface == "water":
		_ripple(pos, n, 0.5 + 0.4 * energy)
	else:
		_mark(surface, pos, n, dir, energy)
	# the sound: a few a frame, the rest are lost in the noise
	if _sounds < SOUNDS_PER_FRAME:
		_sounds += 1
		_sound(surface, pos, energy)
	# the debris: budgeted, and not at distance
	if dist > NEAR_LOD or _bursts >= BURSTS_PER_FRAME:
		aggregated += 1
		return surface
	_bursts += 1
	_debris(surface, pos, n, dir, energy)
	return surface


## An explosion at `pos` (the Explosion node has done its own blast; this adds
## what the ground under it is made of): a plume of mud or a sheet of water,
## dust off concrete.
func blast(pos: Vector3, radius: float) -> String:
	if not is_inside_tree():
		return ""
	var world := get_tree().root.get_world_3d() if get_tree().root else null
	if world == null:
		return ""
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.8, pos + Vector3.DOWN * 2.5, 1)
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var surface := classify(hit)
	var at: Vector3 = hit.position
	var n: Vector3 = hit.normal
	if _player_distance(at) > FAR_LOD * 1.5:
		return surface
	var e := clampf(radius / 2.5, 0.8, 3.0)
	match surface:
		"water":
			_emit("drops", at, Vector3.UP, 1.0, e * 2.2)
			_puff(at + Vector3.UP * 0.3, Vector3.UP, e * 1.6, Color(0.55, 0.57, 0.52, 0.5), 1.4)
			for i in 3:
				_ripple(at + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * radius * 0.4, Vector3.UP, radius * (0.6 + 0.3 * i))
		"mud":
			_emit("clods", at, Vector3.UP, 1.0, e * 2.5)
			_puff(at + Vector3.UP * 0.4, Vector3.UP, e * 1.8, Color(0.16, 0.14, 0.11, 0.7), 1.6)
			_mark("mud", at, n, Vector3.DOWN, e * 1.6)
		"earth":
			_emit("clods", at, Vector3.UP, 1.0, e * 2.0)
			_puff(at + Vector3.UP * 0.4, Vector3.UP, e * 2.0, Color(0.36, 0.32, 0.26, 0.6), 1.8)
			_mark("earth", at, n, Vector3.DOWN, e * 1.6)
		"concrete":
			_emit("chips", at, Vector3.UP, 1.0, e * 1.5)
			_puff(at + Vector3.UP * 0.4, Vector3.UP, e * 2.0, Color(0.55, 0.53, 0.49, 0.55), 1.8)
		_:
			_puff(at + Vector3.UP * 0.4, Vector3.UP, e * 1.6, Color(0.3, 0.27, 0.22, 0.6), 1.5)
	return surface


# --- the marks -------------------------------------------------------------------------
func _mark(surface: String, pos: Vector3, n: Vector3, dir: Vector3, energy: float) -> void:
	var d := _decals[_next]
	_next = (_next + 1) % MAX_DECALS
	var texs: Array = _tex[surface]
	d.texture_albedo = texs[_rng.randi() % texs.size()]
	var size := 0.0
	match surface:
		"mud":
			size = _rng.randf_range(0.22, 0.34) * (0.8 + 0.4 * energy)
			d.modulate = Color(0.7, 0.66, 0.6)           # darkens the wet earth
			d.albedo_mix = 0.85
		"earth":
			size = _rng.randf_range(0.16, 0.26) * (0.8 + 0.3 * energy)
			d.modulate = Color(0.8, 0.76, 0.7)
			d.albedo_mix = 0.6
		"wood":
			size = _rng.randf_range(0.07, 0.11)
			d.modulate = Color(0.5, 0.42, 0.33)
			d.albedo_mix = 0.95
		"concrete":
			size = _rng.randf_range(0.1, 0.16)
			d.modulate = Color(1.2, 1.18, 1.12)
			d.albedo_mix = 0.9
		"metal":
			size = _rng.randf_range(0.05, 0.08)
			d.modulate = Color(0.75, 0.75, 0.78)
			d.albedo_mix = 0.9
		"sandbag", "wattle":
			size = _rng.randf_range(0.07, 0.12)
			d.modulate = Color(0.6, 0.55, 0.47)
			d.albedo_mix = 0.8
		_:
			size = 0.15
			d.modulate = Color.WHITE
			d.albedo_mix = 0.8
	# glancing rounds smear the mark along the line
	var y := n.normalized()
	var along := dir - y * dir.dot(y)
	var stretch := 1.0
	if along.length() > 0.01:
		stretch = 1.0 + clampf(along.length() * 1.2, 0.0, 1.0) * (0.8 if surface in ["mud", "earth", "sandbag"] else 0.3)
	var z := along.normalized() if along.length() > 0.01 else y.cross(Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	z = z.rotated(y, _rng.randf_range(-0.2, 0.2))
	var x := y.cross(z).normalized()
	d.size = Vector3(size, 0.25, size * stretch)
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.visible = true


func _ripple(pos: Vector3, n: Vector3, size: float) -> void:
	var r: Array = _ripples[_ripple_next]
	_ripple_next = (_ripple_next + 1) % RIPPLES
	var m: MeshInstance3D = r[0]
	var y := n.normalized() if n.y > 0.5 else Vector3.UP
	var t := y.cross(Vector3.RIGHT).normalized()
	var x := y.cross(t).normalized()
	# the quad faces +Z: lay it with its Z along the water's normal
	m.global_transform = Transform3D(Basis(x, t, y).rotated(y, _rng.randf() * TAU), pos + y * 0.02)
	m.scale = Vector3.ONE * 0.05
	m.visible = true
	r[1] = 0.0
	r[2] = 0.9 + size * 0.5
	r[3] = size


# --- the debris ------------------------------------------------------------------------
func _debris(surface: String, pos: Vector3, n: Vector3, dir: Vector3, energy: float) -> void:
	# the direction the stuff flies: off the surface, pushed along the round
	# on a glancing hit; off the ground it goes up
	var cosang := clampf(-dir.dot(n), 0.0, 1.0)             # 1 square on, 0 glancing
	var refl := dir.bounce(n).normalized()
	var out := (n * (0.5 + 0.5 * cosang) + refl * (1.0 - cosang) * 0.8).normalized()
	if n.y > 0.6:
		out = (out + Vector3.UP * 0.6).normalized()
	match surface:
		"mud":
			_emit("clods", pos, out, cosang, energy)
			_emit("wet", pos, out, cosang, energy)
			_puff(pos + n * 0.1, out, 0.35 + 0.25 * energy, Color(0.16, 0.14, 0.11, 0.55), 0.7)
		"earth":
			_emit("grit", pos, out, cosang, energy)
			_puff(pos + n * 0.1, out, 0.45 + 0.3 * energy, Color(0.42, 0.37, 0.29, 0.5), 0.9)
		"wood":
			_emit("splinters", pos, out, cosang, energy)
			_puff(pos + n * 0.05, out, 0.18, Color(0.5, 0.42, 0.3, 0.35), 0.5)
		"concrete":
			_emit("chips", pos, out, cosang, energy)
			_puff(pos + n * 0.08, out, 0.35 + 0.2 * energy, Color(0.62, 0.6, 0.55, 0.55), 0.8)
		"metal":
			_emit("sparks", pos, out, cosang, energy)
			if _rng.randf() < 0.3:
				_emit("chips", pos, out, cosang, energy * 0.4)
		"sandbag", "wattle":
			_emit("grit", pos, out, cosang, energy * 0.8)
			_emit("fibres", pos, out, cosang, energy)
			_puff(pos + n * 0.08, out, 0.3 + 0.2 * energy, Color(0.45, 0.4, 0.3, 0.55), 0.8)
		"water":
			_emit("drops", pos, (Vector3.UP * 0.8 + out * 0.3).normalized(), cosang, energy)
			_puff(pos + Vector3.UP * 0.15, Vector3.UP, 0.25 + 0.2 * energy, Color(0.6, 0.62, 0.58, 0.45), 0.5)


## One-shot debris of `kind` from `pos` toward `out`.
func _emit(kind: String, pos: Vector3, out: Vector3, cosang: float, energy: float) -> void:
	var p := _emitters[_em_next]
	_em_next = (_em_next + 1) % EMITTERS
	p.emitting = false
	p.global_position = pos
	p.direction = out
	p.spread = 35.0 + 25.0 * (1.0 - cosang)
	p.color_ramp = null
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	match kind:
		"clods":
			p.mesh = _box(0.045)
			p.mesh.material = _mat("mud")
			p.amount = int(8 + 8 * energy)
			p.lifetime = 1.1
			p.initial_velocity_min = 2.0 * energy
			p.initial_velocity_max = 5.0 * energy
			p.gravity = Vector3(0, -12.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.6
			p.damping_min = 0.5
			p.damping_max = 1.5
		"wet":
			p.mesh = _box(0.02)
			p.mesh.material = _mat("wet")
			p.amount = int(10 + 10 * energy)
			p.lifetime = 0.6
			p.initial_velocity_min = 3.0 * energy
			p.initial_velocity_max = 7.0 * energy
			p.gravity = Vector3(0, -14.0, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.2
			p.damping_min = 1.0
			p.damping_max = 2.0
		"grit":
			p.mesh = _box(0.018)
			p.mesh.material = _mat("grit")
			p.amount = int(10 + 10 * energy)
			p.lifetime = 0.8
			p.initial_velocity_min = 2.5 * energy
			p.initial_velocity_max = 6.0 * energy
			p.gravity = Vector3(0, -12.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
			p.damping_min = 0.5
			p.damping_max = 1.5
		"splinters":
			p.mesh = _stick(0.07, 0.008)
			p.mesh.material = _mat("splinter")
			p.amount = int(5 + 5 * energy)
			p.lifetime = 1.2
			p.spread = 25.0 + 20.0 * (1.0 - cosang)
			p.initial_velocity_min = 3.0 * energy
			p.initial_velocity_max = 7.0 * energy
			p.gravity = Vector3(0, -11.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.5
			p.damping_min = 0.8
			p.damping_max = 1.6
		"chips":
			p.mesh = _box(0.022)
			p.mesh.material = _mat("chip")
			p.amount = int(6 + 6 * energy)
			p.lifetime = 1.0
			p.initial_velocity_min = 2.5 * energy
			p.initial_velocity_max = 6.5 * energy
			p.gravity = Vector3(0, -12.0, 0)
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.4
			p.damping_min = 0.5
			p.damping_max = 1.2
		"sparks":
			p.mesh = _stick(0.05, 0.006)
			p.mesh.material = _mat("spark")
			p.amount = int(5 + 7 * energy)
			p.lifetime = 0.45
			p.spread = 20.0 + 30.0 * (1.0 - cosang)
			p.initial_velocity_min = 5.0
			p.initial_velocity_max = 11.0
			p.gravity = Vector3(0, -9.0, 0)
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.2
			p.damping_min = 2.0
			p.damping_max = 4.0
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
			g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
			p.color_ramp = g
		"fibres":
			p.mesh = _stick(0.03, 0.004)
			p.mesh.material = _mat("fibre")
			p.amount = int(4 + 4 * energy)
			p.lifetime = 1.4
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.5
			p.gravity = Vector3(0, -2.5, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			p.damping_min = 1.0
			p.damping_max = 2.0
		"drops":
			p.mesh = _box(0.02)
			p.mesh.material = _mat("drop")
			p.amount = int(12 + 12 * energy)
			p.lifetime = 0.8
			p.spread = 30.0
			p.initial_velocity_min = 2.5 * energy
			p.initial_velocity_max = 6.0 * energy
			p.gravity = Vector3(0, -12.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
			p.damping_min = 0.3
			p.damping_max = 1.0
	p.restart()
	p.emitting = true


## A soft puff of dust or spray that drifts off and thins.
func _puff(pos: Vector3, out: Vector3, size: float, col: Color, life: float) -> void:
	var p := _puffs[_puff_next]
	_puff_next = (_puff_next + 1) % PUFFS
	p.emitting = false
	p.global_position = pos
	p.amount = 4
	p.lifetime = life
	p.direction = out
	p.spread = 40.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.4, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.12, col)
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.restart()
	p.emitting = true


func _sound(surface: String, pos: Vector3, energy: float) -> void:
	var name_ := ""
	var db := -6.0 + 3.0 * energy
	match surface:
		"mud": name_ = "imp_mud"
		"earth": name_ = "imp_earth"
		"wood": name_ = "imp_wood"
		"concrete": name_ = "imp_stone"
		"metal": name_ = "imp_metal"
		"sandbag", "wattle": name_ = "imp_bag"
		"water": name_ = "imp_water"
	if name_ != "":
		SfxSynth.play(self, name_, pos, db, _rng.randf_range(0.9, 1.1), 4.0, 40.0)


func _process(delta: float) -> void:
	for r in _ripples:
		var m: MeshInstance3D = r[0]
		if not m.visible:
			continue
		r[1] += delta
		var t: float = r[1] / maxf(r[2], 0.01)
		if t >= 1.0:
			m.visible = false
			continue
		var size: float = r[3]
		m.scale = Vector3.ONE * lerpf(0.05, size, 1.0 - pow(1.0 - t, 2.0))
		(m.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 - t)


# --- helpers ---------------------------------------------------------------------------
func _player_distance(pos: Vector3) -> float:
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D if get_tree() else null
	return pl.global_position.distance_to(pos) if pl else 0.0


static func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


var _box_cache := {}
func _box(s: float) -> BoxMesh:
	if not _box_cache.has(s):
		var b := BoxMesh.new()
		b.size = Vector3.ONE * s
		_box_cache[s] = b
	return (_box_cache[s] as BoxMesh).duplicate()


func _stick(length: float, thick: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(thick, thick, length)
	return b


func _mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"puff":
			var sm := StandardMaterial3D.new()
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm.vertex_color_use_as_albedo = true
			sm.albedo_texture = load("res://art/level/fx_smoke.png")
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.no_depth_test = false
			m = sm
		"ripple":
			var rm := ShaderMaterial.new()
			rm.shader = load("res://shaders/impact_ripple.gdshader")
			m = rm
		_:
			var sm := StandardMaterial3D.new()
			sm.roughness = 0.9
			match kind:
				"mud": sm.albedo_color = Color(0.11, 0.09, 0.07)
				"wet":
					sm.albedo_color = Color(0.08, 0.07, 0.06)
					sm.roughness = 0.3
				"grit": sm.albedo_color = Color(0.35, 0.3, 0.23)
				"splinter": sm.albedo_color = Color(0.55, 0.42, 0.26)
				"chip": sm.albedo_color = Color(0.6, 0.58, 0.54)
				"spark":
					sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					sm.vertex_color_use_as_albedo = true
					sm.albedo_color = Color(1.0, 0.8, 0.5)
				"fibre": sm.albedo_color = Color(0.5, 0.45, 0.33)
				"drop":
					sm.albedo_color = Color(0.55, 0.58, 0.55)
					sm.roughness = 0.2
					sm.metallic = 0.3
			m = sm
	_mats[kind] = m
	return m


## The marks, drawn in code: a few of each so no two hits match.
func _make_decal_textures(surface: String) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(surface)
	for v in 3:
		var n := 48
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var cx := n * 0.5
		# a ragged outline: a handful of harmonics with random amplitude and phase
		var harm := []
		for k in 6:
			harm.append([rng.randi_range(2, 9), rng.randf_range(0.03, 0.12), rng.randf() * TAU])
		var rag := func(ang: float, amp: float) -> float:
			var e := 0.0
			for h: Array in harm:
				e += sin(ang * float(h[0]) + float(h[2])) * float(h[1])
			return e * amp
		var grain := FastNoiseLite.new()
		grain.seed = rng.randi()
		grain.frequency = 0.18
		for y in n:
			for x in n:
				var dx := (x - cx) / cx
				var dy := (y - cx) / cx
				var r := sqrt(dx * dx + dy * dy)
				var ang := atan2(dy, dx)
				var g := grain.get_noise_2d(x, y) * 0.5 + 0.5          # 0..1
				var a := 0.0
				var col := Color.WHITE
				match surface:
					"mud", "earth", "sandbag", "wattle":
						# a ragged dark splat with a darker, wetter core and flecks thrown about
						var edge: float = 0.66 + rag.call(ang, 0.7)
						a = clampf((edge - r) / 0.2, 0.0, 1.0) * (0.5 + 0.5 * clampf(1.0 - r / 0.35, 0.0, 1.0))
						a *= 0.45 + 0.55 * g
						if r > edge and r < 0.98 and g > 0.72:
							a = maxf(a, (g - 0.72) * 2.5 * (1.0 - r))      # flecks
						col = Color(0.3, 0.26, 0.22) if surface != "earth" else Color(0.6, 0.56, 0.5)
					"wood":
						# a small hole with torn grain around it, along the grain (x)
						var hole: float = clampf((0.26 + rag.call(ang, 0.6) - r) / 0.08, 0.0, 1.0)
						var along := absf(dx) * 1.3 + absf(dy) * 0.5
						var tear := clampf((0.85 - along) / 0.3, 0.0, 1.0) * (0.25 + 0.5 * g) * (1.0 - hole)
						a = maxf(hole, tear * 0.7)
						col = Color(0.12, 0.09, 0.06) if hole > 0.5 else Color(0.75, 0.62, 0.45)
					"concrete":
						# a pale chip, a dark pit in the middle, dust about
						var pit: float = clampf((0.2 + rag.call(ang, 0.5) - r) / 0.08, 0.0, 1.0)
						var chip: float = clampf((0.62 + rag.call(ang, 0.35) - r) / 0.35, 0.0, 1.0) * (0.2 + 0.8 * g) * (0.5 + 0.5 * clampf(1.0 - r / 0.5, 0.0, 1.0))
						a = maxf(pit, chip * 0.85)
						col = Color(0.3, 0.3, 0.28) if pit > 0.5 else Color(0.85, 0.83, 0.78)
					"metal":
						var pit: float = clampf((0.3 + rag.call(ang, 0.4) - r) / 0.1, 0.0, 1.0)
						var ring := clampf((0.75 - r) / 0.2, 0.0, 1.0) * 0.5 * (0.6 + 0.4 * g)
						a = maxf(pit, ring)
						col = Color(0.15, 0.15, 0.16) if pit > 0.5 else Color(0.7, 0.7, 0.72)
					_:
						a = clampf((0.8 - r) / 0.3, 0.0, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
		out.append(ImageTexture.create_from_image(img))
	return out
