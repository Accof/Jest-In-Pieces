extends Node
## Autoload "Blood": splatter decals, flying droplets, mist and growing pools.
## Everything is pooled and capped so a long fight cannot tank the frame rate.

const LAYER_WORLD := 1
const MAX_DECALS := 320
const MAX_DROPLETS := 160
const MAX_POOLS := 28
const POOL_QUAD_RADIUS := 1.2          # metres; the largest pool that can form
const DRY_TIME := 50.0                 # seconds for fresh blood to darken
const FRESH := Color(1, 1, 1, 1)
const DRIED := Color(0.55, 0.42, 0.40, 1)

var _tex := {}                          # kind -> Array of [albedo, normal]
var _orm: Texture2D
var _decals: Array[Decal] = []
var _born := PackedFloat32Array()
var _next := 0
var _dry_cursor := 0

var _drop_pos := PackedVector3Array()
var _drop_vel := PackedVector3Array()
var _drop_size := PackedFloat32Array()
var _drop_life := PackedFloat32Array()

var _pools: Array = []                  # {node, r, target, born}
var _pool_material: ShaderMaterial
var _pool_mesh: PlaneMesh
var _mist: Array[GPUParticles3D] = []
var _mist_next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for spec in [["impact", 3], ["spray", 3], ["drip", 2], ["streak", 2]]:
		var list := []
		for i in spec[1]:
			var base := "res://art/blood/splat_%s_%d" % [spec[0], i]
			list.append([load(base + ".png"), load(base + "_n.png")])
		_tex[spec[0]] = list
	_orm = load("res://art/blood/splat_orm.png")
	for i in MAX_DECALS:
		var d := Decal.new()
		d.visible = false
		d.texture_orm = _orm
		d.normal_fade = 0.35
		d.upper_fade = 0.25
		d.lower_fade = 0.25
		d.cull_mask = 1                 # world only: never projected onto bodies
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 10.0
		add_child(d)
		_decals.append(d)
	_born.resize(MAX_DECALS)
	_pool_material = ShaderMaterial.new()
	_pool_material.shader = load("res://shaders/blood_pool.gdshader")
	_pool_material.set_shader_parameter("noise_tex", load("res://art/blood/pool_noise.png"))
	_pool_mesh = PlaneMesh.new()
	_pool_mesh.size = Vector2.ONE * POOL_QUAD_RADIUS * 2.0
	_pool_mesh.material = _pool_material
	_build_mist()


func clear() -> void:
	for d in _decals:
		d.visible = false
	for p in _pools:
		p.node.queue_free()
	_pools.clear()
	_drop_pos.clear(); _drop_vel.clear(); _drop_size.clear(); _drop_life.clear()


# --- splatter -----------------------------------------------------------------
## A bullet passing through flesh at `pos` travelling along `dir`.
## `amount` 0..2 scales how much blood comes out.
func spawn_hit(pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	dir = dir.normalized()
	_burst(pos, dir, amount)
	# Exit spray onto whatever is behind the target.
	var rays := 2 + int(amount * 4.0)
	for i in rays:
		var d := (dir + _rand_unit() * 0.42).normalized()
		var hit := _ray(pos + d * 0.05, pos + d * (2.4 + 2.2 * amount))
		if hit.is_empty():
			continue
		var dist: float = pos.distance_to(hit.position)
		var size := _rng.randf_range(0.2, 0.5) * (0.55 + 0.6 * amount) * clampf(1.25 - dist * 0.16, 0.45, 1.0)
		_splat_on(hit.position, hit.normal, d, size)
	# A little back spatter toward the shooter.
	for i in 1 + int(amount):
		var d := (-dir + _rand_unit() * 0.7).normalized()
		var hit := _ray(pos + d * 0.05, pos + d * 1.6)
		if not hit.is_empty():
			spawn_decal(hit.position, hit.normal, _rng.randf_range(0.08, 0.2), "drip")
	# Heavy drops that arc away and land on the floor.
	for i in 3 + int(amount * 7.0):
		var v := dir * _rng.randf_range(0.8, 4.2) + Vector3.UP * _rng.randf_range(0.3, 2.6) + _rand_unit() * 1.3
		add_droplet(pos, v, _rng.randf_range(0.05, 0.13))


## A single falling drop, for wounds that keep bleeding.
func add_droplet(pos: Vector3, vel: Vector3, size: float = 0.07) -> void:
	if _drop_pos.size() >= MAX_DROPLETS:
		return
	_drop_pos.append(pos); _drop_vel.append(vel); _drop_size.append(size); _drop_life.append(4.0)


func _splat_on(pos: Vector3, normal: Vector3, travel: Vector3, size: float) -> void:
	var facing: float = absf(travel.dot(normal))
	var along := (travel - normal * travel.dot(normal))
	if facing < 0.5 and along.length() > 0.05:
		# Glancing hit: the blood smears along the surface.
		spawn_decal(pos, normal, size * 1.1, "streak", along, 1.0, lerpf(2.2, 1.3, facing * 2.0))
	elif size > 0.3:
		spawn_decal(pos, normal, size, "impact")
	else:
		spawn_decal(pos, normal, size * 1.3, "spray", along)


## Place one decal. `along` (optional) points the texture's "up" along the surface.
func spawn_decal(pos: Vector3, normal: Vector3, size: float, kind: String, along: Vector3 = Vector3.ZERO, stretch_x: float = 1.0, stretch_z: float = 1.0) -> void:
	var d := _decals[_next]
	_born[_next] = Time.get_ticks_msec() / 1000.0
	_next = (_next + 1) % MAX_DECALS
	var pair: Array = _tex[kind][_rng.randi() % _tex[kind].size()]
	d.texture_albedo = pair[0]
	d.texture_normal = pair[1]
	var y := normal.normalized()
	var z := along - y * along.dot(y)
	if z.length() < 0.01:
		z = y.cross(_rand_unit())
		if z.length() < 0.01:
			z = y.cross(Vector3.RIGHT)
	z = -z.normalized()                 # texture "up" is the decal's -Z
	var x := y.cross(z).normalized()
	d.size = Vector3(size * stretch_x, 0.3, size * stretch_z)
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.modulate = FRESH
	d.visible = true


# --- pools --------------------------------------------------------------------
## Start (or feed) a pool on the floor. `radius` is where it will stop spreading.
func spawn_pool(pos: Vector3, normal: Vector3, radius: float) -> void:
	radius = minf(radius, POOL_QUAD_RADIUS * 0.8)
	for p in _pools:
		if p.node.global_position.distance_to(pos) < 0.35:
			p.target = minf(sqrt(p.target * p.target + radius * radius * 0.6), POOL_QUAD_RADIUS * 0.8)
			return
	if _pools.size() >= MAX_POOLS:
		var old: Dictionary = _pools.pop_front()
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: old.node.set_instance_shader_parameter("fade", v), 1.0, 0.0, 2.0)
		tw.tween_callback(old.node.queue_free)
	var m := MeshInstance3D.new()
	m.mesh = _pool_mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.layers = 2
	add_child(m)
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	m.global_transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, _rng.randf() * TAU), pos + y * 0.004)
	m.set_instance_shader_parameter("seed", _rng.randf() * 10.0)
	m.set_instance_shader_parameter("grow", 0.0)
	m.set_instance_shader_parameter("fade", 1.0)
	_pools.append({node = m, r = 0.02, target = radius})


func _process(delta: float) -> void:
	# Pools spread quickly at first and slow as they thin out.
	for p in _pools:
		if p.r < p.target - 0.002:
			p.r += (p.target - p.r) * (1.0 - exp(-delta / 3.2))
			p.node.set_instance_shader_parameter("grow", p.r / POOL_QUAD_RADIUS)
	# Darken a few decals each frame as the blood dries.
	var now := Time.get_ticks_msec() / 1000.0
	for i in 12:
		_dry_cursor = (_dry_cursor + 1) % MAX_DECALS
		var d := _decals[_dry_cursor]
		if d.visible:
			d.modulate = FRESH.lerp(DRIED, clampf((now - _born[_dry_cursor]) / DRY_TIME, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _drop_pos.size():
		var p := _drop_pos[i]
		var v := _drop_vel[i] + Vector3.DOWN * 9.8 * delta
		var q := p + v * delta
		var hit := _ray(p, q)
		_drop_life[i] -= delta
		if not hit.is_empty():
			var s := _drop_size[i]
			var along: Vector3 = v - hit.normal * v.dot(hit.normal)
			var slant: float = clampf(along.length() / maxf(v.length(), 0.01), 0.0, 1.0)
			spawn_decal(hit.position, hit.normal, s * 2.2, "drip", along, 1.0, 1.0 + slant * 0.8)
			_drop_life[i] = 0.0
		if _drop_life[i] <= 0.0:
			var last := _drop_pos.size() - 1
			_drop_pos[i] = _drop_pos[last]; _drop_vel[i] = _drop_vel[last]
			_drop_size[i] = _drop_size[last]; _drop_life[i] = _drop_life[last]
			_drop_pos.resize(last); _drop_vel.resize(last); _drop_size.resize(last); _drop_life.resize(last)
		else:
			_drop_pos[i] = q
			_drop_vel[i] = v
			i += 1


# --- helpers ------------------------------------------------------------------
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().find_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return space.intersect_ray(q)


func _rand_unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)


func _build_mist() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.01, 0.012, 0.9)
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for i in 6:
		var pm := ParticleProcessMaterial.new()
		pm.spread = 32.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 6.5
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.4
		pm.scale_max = 1.6
		pm.damping_min = 1.0
		pm.damping_max = 3.0
		pm.color_ramp = ramp
		var g := GPUParticles3D.new()
		g.process_material = pm
		g.draw_pass_1 = quad
		g.amount = 48
		g.lifetime = 0.55
		g.one_shot = true
		g.explosiveness = 0.95
		g.emitting = false
		g.layers = 2
		add_child(g)
		_mist.append(g)


## A puff of fine blood spray.
func mist(pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	_burst(pos, dir, amount)


func _burst(pos: Vector3, dir: Vector3, amount: float) -> void:
	var g := _mist[_mist_next]
	_mist_next = (_mist_next + 1) % _mist.size()
	g.global_position = pos
	(g.process_material as ParticleProcessMaterial).direction = dir
	g.amount_ratio = clampf(0.35 + amount * 0.45, 0.2, 1.0)
	g.restart()
	g.emitting = true
