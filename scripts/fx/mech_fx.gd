class_name MechFx
extends Node3D
## Sparks, electric arcs, smoke and machine sounds for clockwork bodies (the
## Klappersoldat). One shared node, made on first use under the scene root,
## holding pooled emitters and lights; nothing here runs per frame once an
## effect has started, apart from the arcs' few frames of flicker.

const SPARK_POOL := 12
const ARC_POOL := 12
const SOUND_POOL := 20
## Sound names with numbered variants (name_0.wav, name_1.wav ...).
const VARIANTS := {"step": 3, "ping": 3}

var _sparks: Array[GPUParticles3D] = []
var _floors: Array[GPUParticlesCollisionBox3D] = []
var _flashes: Array[OmniLight3D] = []
var _spark_next := 0
var _arcs: Array[MeshInstance3D] = []
var _arc_next := 0
var _arc_mat: StandardMaterial3D
var _players: Array[AudioStreamPlayer3D] = []
var _player_next := 0
var _streams := {}
var _smoke_mat: StandardMaterial3D
var _smoke_quad: QuadMesh
var _smoke_process: ParticleProcessMaterial


static func get_fx(from: Node) -> MechFx:
	var root := from.get_tree().root
	var fx := root.get_node_or_null("MechFx") as MechFx
	if fx == null:
		fx = MechFx.new()
		fx.name = "MechFx"
		root.add_child(fx)
	return fx


## A spray of sparks at `pos`, thrown along `dir`. `amount` 0..2.
static func sparks(from: Node, pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_fx(from)._spark(pos, dir, amount)


## A crackling blue electric arc jumping out of `pos` (a wound shorting out).
static func arc(from: Node, pos: Vector3, reach: float = 0.25) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_fx(from)._arc(pos, reach)


## A thin, steady wisp of smoke rising from a point on `parent` (a wound),
## following it as it moves. Stops after `seconds` and cleans itself up.
static func smoke(parent: Node3D, local_pos: Vector3, seconds: float) -> GPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	return get_fx(parent)._smoke(parent, local_pos, seconds)


## Play one of the clockwork sounds (art/klapper/sfx) at `pos`.
static func sound(from: Node, sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_fx(from)._play(sound_name, pos, volume_db, pitch)


func _ready() -> void:
	_build_sparks()
	_build_arcs()
	_build_smoke()
	for i in SOUND_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 30.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_players.append(p)


# --- sparks --------------------------------------------------------------------------
# Real sparks are hot flecks of metal: they leave fast, draw streaks (the eye
# smears them along their path), arc down under gravity, skitter and bounce
# off the floor, and cool from white through orange to dull red in well under
# a second, with the odd ember lasting longer.
func _build_sparks() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/spark.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.97, 0.85, 1.0))
	ramp.add_point(0.12, Color(1.0, 0.82, 0.45, 1.0))
	ramp.add_point(0.45, Color(1.0, 0.45, 0.08, 0.95))
	ramp.add_point(0.8, Color(0.6, 0.12, 0.02, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.25, 0.03, 0.0, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	# streaks shrink as they cool and slow
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.5, 0.7))
	shrink.add_point(Vector2(1.0, 0.15))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	for i in SPARK_POOL:
		var pm := ParticleProcessMaterial.new()
		pm.spread = 50.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 6.5
		pm.gravity = Vector3(0, -9.8, 0)
		pm.damping_min = 0.2
		pm.damping_max = 1.2
		pm.particle_flag_align_y = true
		# the streak's length in metres (its width is a fraction of that, in the shader)
		pm.scale_min = 0.03
		pm.scale_max = 0.085
		pm.scale_curve = shrink_tex
		pm.color_ramp = ramp_tex
		pm.lifetime_randomness = 0.7
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.35
		pm.collision_friction = 0.25
		pm.collision_use_scale = false
		var g := GPUParticles3D.new()
		g.process_material = pm
		g.draw_pass_1 = quad
		g.amount = 48
		g.lifetime = 0.85
		g.one_shot = true
		g.explosiveness = 0.95
		g.randomness = 0.6
		g.fixed_fps = 60
		g.local_coords = false
		g.emitting = false
		g.layers = 2
		g.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
		g.collision_base_size = 0.004
		add_child(g)
		_sparks.append(g)
		# the floor they bounce on: a thin box moved under each burst
		var floor_box := GPUParticlesCollisionBox3D.new()
		floor_box.size = Vector3(6.0, 0.4, 6.0)
		add_child(floor_box)
		_floors.append(floor_box)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.omni_range = 1.3
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_flashes.append(l)


func _spark(pos: Vector3, dir: Vector3, amount: float) -> void:
	var i := _spark_next
	_spark_next = (_spark_next + 1) % SPARK_POOL
	var g := _sparks[i]
	g.global_position = pos
	var pm := g.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	g.amount_ratio = clampf(0.2 + amount * 0.4, 0.12, 1.0)
	var floor_y := pos.y - 1.6
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.05, pos + Vector3.DOWN * 3.0, 1))
	if not hit.is_empty():
		floor_y = hit.position.y
	_floors[i].global_position = Vector3(pos.x, floor_y - 0.2, pos.z)
	g.restart()
	g.emitting = true
	var l := _flashes[i]
	l.light_color = Color(1.0, 0.65, 0.3)
	l.global_position = pos + pm.direction * 0.05
	l.light_energy = 0.35 * clampf(amount, 0.3, 2.0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.07)


# --- electric arcs ----------------------------------------------------------------------
func _build_arcs() -> void:
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.albedo_color = Color(0.7, 0.85, 1.0)
	_arc_mat.emission_enabled = true
	_arc_mat.emission = Color(0.45, 0.7, 1.0)
	_arc_mat.emission_energy_multiplier = 8.0
	_arc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mat.no_depth_test = false
	for i in ARC_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = _arc_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2
		mi.visible = false
		add_child(mi)
		_arcs.append(mi)


func _arc(pos: Vector3, reach: float) -> void:
	var mi := _arcs[_arc_next]
	_arc_next = (_arc_next + 1) % ARC_POOL
	mi.global_position = pos
	var end := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)).normalized() * reach * randf_range(0.6, 1.2)
	_draw_bolt(mi.mesh as ImmediateMesh, end)
	mi.visible = true
	var l := _flashes[_spark_next]
	_spark_next = (_spark_next + 1) % SPARK_POOL
	l.light_color = Color(0.45, 0.65, 1.0)
	l.global_position = pos
	l.light_energy = 0.6
	var tw := create_tween()
	# it crackles: redrawn jagged twice, then gone
	tw.tween_interval(0.035)
	tw.tween_callback(func() -> void: _draw_bolt(mi.mesh as ImmediateMesh, end * randf_range(0.8, 1.15)))
	tw.tween_interval(0.035)
	tw.tween_callback(func() -> void: _draw_bolt(mi.mesh as ImmediateMesh, end.rotated(Vector3.UP, randf_range(-0.6, 0.6))))
	tw.tween_interval(0.04)
	tw.tween_callback(func() -> void: mi.visible = false)
	tw.parallel().tween_property(l, "light_energy", 0.0, 0.11)


## A jagged bolt from the origin to `end`, with a fork or two: thin crossed
## ribbons so it reads from any side.
func _draw_bolt(im: ImmediateMesh, end: Vector3) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _jag(Vector3.ZERO, end, 7, end.length() * 0.22)
	_ribbon(im, pts, 0.004)
	for f in randi_range(1, 2):
		var from: Vector3 = pts[randi_range(2, pts.size() - 2)]
		var fork := from + (end - from).rotated(Vector3(randf(), randf(), randf()).normalized(), randf_range(0.5, 1.2)) * randf_range(0.3, 0.6)
		_ribbon(im, _jag(from, fork, 4, (fork - from).length() * 0.25), 0.0025)
	im.surface_end()


func _jag(a: Vector3, b: Vector3, n: int, wander: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [a]
	for k in range(1, n):
		var t := float(k) / n
		pts.append(a.lerp(b, t) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * wander * sin(t * PI))
	pts.append(b)
	return pts


func _ribbon(im: ImmediateMesh, pts: Array[Vector3], w: float) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var d := (b - a).normalized()
		for side: Vector3 in [d.cross(Vector3.UP), d.cross(Vector3.RIGHT)]:
			if side.length() < 0.01:
				continue
			side = side.normalized() * w
			for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
				im.surface_add_vertex(v)


# --- smoke ---------------------------------------------------------------------------------
func _build_smoke() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = grad
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_texture = soft
	_smoke_mat.albedo_color = Color(0.5, 0.5, 0.52)
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_smoke_quad = QuadMesh.new()
	_smoke_quad.size = Vector2(0.1, 0.1)
	_smoke_quad.material = _smoke_mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.1, Color(1, 1, 1, 0.34))
	fade.add_point(0.55, Color(1, 1, 1, 0.18))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	grow.max_value = 1.0
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	_smoke_process = ParticleProcessMaterial.new()
	_smoke_process.direction = Vector3.UP
	_smoke_process.spread = 6.0
	_smoke_process.initial_velocity_min = 0.22
	_smoke_process.initial_velocity_max = 0.36
	_smoke_process.gravity = Vector3(0, 0.06, 0)       # warm: it rises on its own
	_smoke_process.damping_min = 0.02
	_smoke_process.damping_max = 0.06
	_smoke_process.scale_min = 0.8
	_smoke_process.scale_max = 1.4
	_smoke_process.scale_curve = grow_tex
	_smoke_process.color_ramp = fade_tex
	_smoke_process.turbulence_enabled = true
	_smoke_process.turbulence_noise_strength = 0.35
	_smoke_process.turbulence_noise_scale = 1.6
	_smoke_process.turbulence_influence_min = 0.04
	_smoke_process.turbulence_influence_max = 0.09
	_smoke_process.angle_min = -180.0
	_smoke_process.angle_max = 180.0


func _smoke(parent: Node3D, local_pos: Vector3, seconds: float) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.process_material = _smoke_process
	g.draw_pass_1 = _smoke_quad
	g.amount = 40
	g.lifetime = 5.0
	g.local_coords = false
	g.layers = 2
	g.visibility_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3, 4, 3))
	g.position = local_pos
	parent.add_child(g)
	g.emitting = true
	var tw := g.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void: g.emitting = false)
	tw.tween_interval(g.lifetime + 0.2)
	tw.tween_callback(g.queue_free)
	return g


func _play(sound_name: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	var file := sound_name
	if VARIANTS.has(sound_name):
		file = "%s_%d" % [sound_name, randi() % int(VARIANTS[sound_name])]
	if not _streams.has(file):
		_streams[file] = load("res://art/klapper/sfx/%s.wav" % file) if ResourceLoader.exists("res://art/klapper/sfx/%s.wav" % file) else null
	var stream: AudioStream = _streams[file]
	if stream == null:
		return
	var p := _players[_player_next]
	_player_next = (_player_next + 1) % SOUND_POOL
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()
