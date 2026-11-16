class_name MechFx
extends Node3D
## Sparks and machine sounds for clockwork bodies (the Klappersoldat).
## One shared node, made on first use under the scene root: a ring of pooled
## spark emitters and flash lights, and a ring of 3D sound players.
## Nothing here is per-frame once an effect has started.

const SPARK_POOL := 10
const SOUND_POOL := 20
## Sound names with numbered variants (name_0.wav, name_1.wav ...).
const VARIANTS := {"step": 3, "ping": 3}

var _sparks: Array[GPUParticles3D] = []
var _flashes: Array[OmniLight3D] = []
var _spark_next := 0
var _players: Array[AudioStreamPlayer3D] = []
var _player_next := 0
var _streams := {}


static func get_fx(from: Node) -> MechFx:
	var root := from.get_tree().root
	var fx := root.get_node_or_null("MechFx") as MechFx
	if fx == null:
		fx = MechFx.new()
		fx.name = "MechFx"
		root.add_child(fx)
	return fx


## A spray of orange sparks at `pos`, thrown along `dir`. `amount` 0..2.
static func sparks(from: Node, pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_fx(from)._spark(pos, dir, amount)


## Play one of the clockwork sounds (art/klapper/sfx) at `pos`.
static func sound(from: Node, sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_fx(from)._play(sound_name, pos, volume_db, pitch)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 6.0
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	quad.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.95, 0.7, 1))
	fade.add_point(0.5, Color(1.0, 0.55, 0.15, 1))
	fade.set_color(fade.get_point_count() - 1, Color(0.6, 0.15, 0.02, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for i in SPARK_POOL:
		var pm := ParticleProcessMaterial.new()
		pm.spread = 40.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 7.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		pm.damping_min = 0.5
		pm.damping_max = 2.0
		pm.color_ramp = ramp
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.35
		pm.collision_friction = 0.3
		var g := GPUParticles3D.new()
		g.process_material = pm
		g.draw_pass_1 = quad
		g.amount = 40
		g.lifetime = 0.5
		g.one_shot = true
		g.explosiveness = 0.92
		g.emitting = false
		g.layers = 2
		g.trail_enabled = false
		add_child(g)
		_sparks.append(g)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.25)
		l.omni_range = 1.3
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_flashes.append(l)
	for i in SOUND_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 30.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_players.append(p)


func _spark(pos: Vector3, dir: Vector3, amount: float) -> void:
	var i := _spark_next
	_spark_next = (_spark_next + 1) % SPARK_POOL
	var g := _sparks[i]
	g.global_position = pos
	var pm := g.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	g.amount_ratio = clampf(0.25 + amount * 0.4, 0.15, 1.0)
	g.restart()
	g.emitting = true
	var l := _flashes[i]
	l.global_position = pos + pm.direction * 0.05
	l.light_energy = 0.3 * clampf(amount, 0.3, 2.0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)


func _play(sound_name: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	var file := sound_name
	if VARIANTS.has(sound_name):
		file = "%s_%d" % [sound_name, randi() % int(VARIANTS[sound_name])]
	if not _streams.has(file):
		_streams[file] = load("res://art/klapper/sfx/%s.wav" % file)
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
