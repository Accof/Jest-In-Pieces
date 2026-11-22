class_name TrenchAmbience
extends Node3D
## The sound and weather of the Drowned Trenches, round the player:
##   wind (a loop) and the low rumble of the guns far off
##   shells landing in the distance: a flash on the horizon, the boom after
##     it by the speed of sound, now and then a puff of smoke where it fell
##   machine guns and rifles a long way off, now and then
##   timber creaking in the linings, water dripping at dugout doors, loose
##     iron and wire rattling, water moving when you are near it
##   very occasionally a whistle far down the line
##   the music box in the dugout playing a few bars when you are near it,
##     and once in a long while, from nowhere, a faint carnival tune
##   the player's footsteps by what they land on (mud, water, duckboards,
##     firmer ground), with a splash and a ripple in water, a fleck of mud
## Never anything that hurts: the war stays far off.

var maze: TrenchMaze
var art: TrenchArt
var rng := RandomNumberGenerator.new()
## The quieter details (rattles, water, the whistle) draw from their own
## numbers so they never shift when and where the shells fall.
var _rng_b := RandomNumberGenerator.new()
var player: Node3D
## Counters, for the tests.
var steps := {}
var booms := 0
var flashes := 0
var tunes := 0

var _wind: AudioStreamPlayer
var _rumble: AudioStreamPlayer
## The battle's pacing (TrenchBattle.calm): above 1 the guns go quieter.
var calm := 1.0
var _t_boom := 3.0
var _t_mg := 8.0
var _t_rifle := 4.0
var _t_creak := 9.0
var _t_drip := 1.0
var _t_tune := 40.0
var _t_ghost := 160.0
var _t_rattle := 12.0
var _t_slosh := 6.0
var _t_whistle := 90.0
var _stride := 0.0
var _last := Vector3.INF
var _ripples: Array[MeshInstance3D] = []
var _ripple_i := 0
var _flash_mat: StandardMaterial3D


func setup(m: TrenchMaze, a: TrenchArt) -> void:
	maze = m
	art = a
	rng.seed = m.rng.seed + 31
	_rng_b.seed = m.rng.seed + 53
	_wind = _loop("wind", -17.0)
	_rumble = _loop("rumble", -21.0)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.albedo_texture = load("res://art/level/fx_fire.png")
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.55, 0.0)
	_flash_mat.no_depth_test = false
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/ripple.gdshader")
	for i in 8:
		var mi := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(0.9, 0.9)
		mi.mesh = q
		mi.material_override = rm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_ripples.append(mi)


func _loop(name_: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = SfxSynth.stream(name_)
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
		if player == null:
			return
	var at := player.global_position
	_t_boom -= delta
	_t_mg -= delta
	_t_rifle -= delta
	_t_creak -= delta
	_t_drip -= delta
	_t_tune -= delta
	_t_ghost -= delta
	_t_rattle -= delta
	_t_slosh -= delta
	_t_whistle -= delta
	if _t_boom <= 0.0:
		_t_boom = rng.randf_range(5.0, 16.0) * calm
		_shell(at)
	if _t_mg <= 0.0:
		_t_mg = rng.randf_range(9.0, 26.0) * calm
		_far_sound("mg_far", at, rng.randf_range(120.0, 400.0), -14.0)
	if _t_rifle <= 0.0:
		_t_rifle = rng.randf_range(3.0, 10.0) * calm
		_far_sound("rifle_far", at, rng.randf_range(80.0, 300.0), -12.0)
	if _t_creak <= 0.0:
		_t_creak = rng.randf_range(8.0, 22.0)
		var near := _nearest(art.creak_spots, at, 14.0)
		if near != Vector3.INF:
			SfxSynth.play(self, "timber_creak", near, -16.0, rng.randf_range(0.8, 1.2))
	if _t_drip <= 0.0:
		_t_drip = rng.randf_range(0.6, 2.2)
		var near := _nearest(art.drip_spots, at, 12.0)
		if near != Vector3.INF:
			SfxSynth.play(self, "drip", near + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), -12.0, rng.randf_range(0.85, 1.25))
	if _t_tune <= 0.0:
		_t_tune = rng.randf_range(35.0, 70.0)
		if art.music_box != Vector3.INF and art.music_box.distance_to(at) < 14.0:
			SfxSynth.play(self, "carnival_tune", art.music_box, -12.0, 1.0)
			tunes += 1
	if _t_ghost <= 0.0:
		# from nowhere, faint: nobody is winding anything
		_t_ghost = rng.randf_range(150.0, 300.0)
		_far_sound("carnival_tune", at, 30.0, -30.0)
		tunes += 1
	if _t_rattle <= 0.0:
		_t_rattle = _rng_b.randf_range(16.0, 40.0)
		var near := _nearest(art.rattle_spots, at, 30.0)
		if near != Vector3.INF:
			SfxSynth.play(self, "metal_rattle", near, -20.0, _rng_b.randf_range(0.85, 1.15))
	if _t_slosh <= 0.0:
		_t_slosh = _rng_b.randf_range(9.0, 24.0)
		for k in 6:
			var a := _rng_b.randf() * TAU
			var q := at + Vector3(cos(a), 0, sin(a)) * _rng_b.randf_range(1.5, 5.0)
			if maze.surface_at(q) == "water":
				SfxSynth.play(self, "water_slosh", Vector3(q.x, maze.water_level(q), q.z), -16.0, _rng_b.randf_range(0.85, 1.1))
				break
	if _t_whistle <= 0.0:
		_t_whistle = _rng_b.randf_range(90.0, 200.0)
		_far_sound("whistle_far", at, 300.0, -26.0)
	_footsteps(at, delta)


## A shell somewhere far off: a flash low on the horizon, the boom arriving
## later by the speed of sound, sometimes smoke rising where it fell.
func _shell(at: Vector3) -> void:
	var a := rng.randf_range(-PI * 0.95, -PI * 0.05) if rng.randf() < 0.75 else rng.randf_range(0.0, TAU)
	var r := rng.randf_range(160.0, 600.0)
	var where := Vector3(at.x + cos(a) * r, 0, at.z + sin(a) * r)
	where.y = art.height_at(where.x, where.z) if absf(where.z) < 400.0 else 0.0
	booms += 1
	if flashes == 0 or rng.randf() < 0.6:          # the first one always shows
		_flash(where, r)
	var delay := r / 343.0
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if is_inside_tree():
			_far_sound("artillery" if r > 250.0 else "artillery_near", at, r, lerpf(-6.0, -15.0, clampf((r - 160.0) / 440.0, 0.0, 1.0))))
	if rng.randf() < 0.3 and art.smoke_material():
		add_child(TrenchArt.make_plume(art.smoke_material(), where, rng.randf_range(0.8, 1.6), true))


func _flash(where: Vector3, r: float) -> void:
	flashes += 1
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * clampf(r * 0.06, 8.0, 30.0)
	mi.mesh = q
	var m := _flash_mat.duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = where + Vector3.UP * q.size.y * 0.25
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.75, 0.05)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(mi.queue_free)


## A sound from far away in a direction: a 3D player well out from the
## listener (so it comes from somewhere), its loudness set by hand.
func _far_sound(name_: String, at: Vector3, dist: float, db: float) -> void:
	var a := rng.randf() * TAU
	var p := AudioStreamPlayer3D.new()
	p.stream = SfxSynth.stream(name_)
	if p.stream == null:
		return
	p.volume_db = db
	p.unit_size = 40.0
	p.max_distance = 200.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.pitch_scale = rng.randf_range(0.9, 1.08)
	add_child(p)
	p.global_position = at + Vector3(cos(a), 0.1, sin(a)) * 40.0
	p.finished.connect(p.queue_free)
	p.play()


func _nearest(spots: Array[Vector3], at: Vector3, within: float) -> Vector3:
	var best := Vector3.INF
	var bd := within
	for s in spots:
		var d := s.distance_to(at)
		if d < bd:
			bd = d
			best = s
	return best


## The player's footsteps: a stride's walk along the ground makes a step,
## sounding by what it lands on; in water a splash and a ripple, in mud now
## and then a fleck thrown up.
func _footsteps(at: Vector3, delta: float) -> void:
	var body := player as CharacterBody3D
	if body == null or not body.is_on_floor():
		_last = at
		return
	if _last == Vector3.INF:
		_last = at
	var moved := Vector2(at.x - _last.x, at.z - _last.z).length()
	_last = at
	if moved > 1.0:
		return                     # teleported
	_stride += moved
	var speed := moved / maxf(delta, 0.001)
	var stride := 0.62 if speed < 5.0 else 0.85
	if _stride < stride:
		return
	_stride = 0.0
	var surf := maze.surface_at(at)
	steps[surf] = steps.get(surf, 0) + 1
	var foot := at + Vector3.UP * 0.05
	SfxSynth.play(self, "fs_" + surf, foot, -10.0 if surf != "water" else -8.0, rng.randf_range(0.9, 1.1))
	if surf == "water":
		var lvl := maze.water_level(at)
		_ripple(Vector3(at.x, lvl + 0.005, at.z))
		_splash(Vector3(at.x, lvl, at.z), Color(0.3, 0.27, 0.23, 0.8), 10)
	elif surf == "mud" and rng.randf() < 0.35:
		_splash(foot, Color(0.12, 0.09, 0.06, 1.0), 5)


func _ripple(at: Vector3) -> void:
	var mi := _ripples[_ripple_i]
	_ripple_i = (_ripple_i + 1) % _ripples.size()
	mi.global_position = at
	mi.visible = true
	mi.set_instance_shader_parameter("start", Time.get_ticks_msec() / 1000.0)


func _splash(at: Vector3, col: Color, n: int) -> void:
	var p := CPUParticles3D.new()
	var q := SphereMesh.new()
	q.radius = 0.012
	q.height = 0.024
	q.radial_segments = 4
	q.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.3
	q.material = m
	p.mesh = q
	p.amount = n
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -9.8, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = at
