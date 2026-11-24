class_name FrontFlares
extends Node3D
## (Milestone 11) Flares over No Man's Land on the dusk crossing. Every so
## often one goes up from their line: a pop, a point of light climbing for
## a second, then burning as it drifts down on its parachute for about ten
## seconds, swinging a little, and dying out. While it burns the field is
## lit from above (one OmniLight, no shadows: the budget) and everyone sees
## further through the haze - FrontAtmosphere.visibility multiplies by the
## glow, the same for the guns, the brains and the player. Telegraphed: the
## pop and the climb come before the light is full.
##
## Fair by construction: a flare changes what can be seen, never what can
## be hit; the guns' arcs and the artillery's zone are what they were.

signal flare_up(at: Vector3)
signal flare_out

const FIRST := Vector2(18.0, 40.0)
const EVERY := Vector2(45.0, 90.0)
const CLIMB := 1.2              ## seconds up to the top
const BURN := 9.0               ## seconds burning on the way down
const FADE := 1.6               ## guttering out
const TOP := 28.0               ## metres up at the top
const SINK := 1.6               ## m/s down under the parachute
const ENERGY := 30.0
const RANGE := 120.0
const REACH := 0.45             ## how far across the field (0 their line, 1 ours) it arcs out before it hangs

var maze: FrontMaze
var player: FpsPlayer
var atmosphere: FrontAtmosphere
var flares := 0                  ## launched, for the tests
var glow := 0.0                  ## 0..1 now
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _clock := 0.0
var _light: OmniLight3D
var _spark: MeshInstance3D
var _age := -1.0                 ## seconds since the launch, -1 idle
var _from := Vector3.ZERO
var _apex := Vector3.ZERO        ## over the field, where it hangs
var _sway := 0.0


func setup(m: FrontMaze, p: FpsPlayer, seed_: int) -> void:
	maze = m
	player = p
	_rng.seed = seed_
	_t = _rng.randf_range(FIRST.x, FIRST.y)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.9, 0.7)
	_light.light_energy = 0.0
	_light.omni_range = RANGE
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.visible = false
	add_child(_light)
	# the flare itself: a small bright billboard
	_spark = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 4.0)      # a hot point with a halo: it has to read from 80 m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load("res://art/level/fx_fire.png")
	mat.albedo_color = Color(1.0, 0.95, 0.8, 1.0)
	q.material = mat
	_spark.mesh = q
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark.visible = false
	add_child(_spark)


func _atmos() -> FrontAtmosphere:
	if atmosphere == null or not is_instance_valid(atmosphere):
		atmosphere = get_tree().get_first_node_in_group(&"fog") as FrontAtmosphere
	return atmosphere


func _physics_process(delta: float) -> void:
	if maze == null or player == null:
		return
	_clock += delta
	if _age < 0.0:
		_t -= delta
		if _t <= 0.0:
			launch_now()
		return
	_age += delta
	var total := CLIMB + BURN + FADE
	var h: float
	var bright: float
	if _age < CLIMB:
		var u := _age / CLIMB
		h = TOP * (1.0 - (1.0 - u) * (1.0 - u))
		bright = 0.15 + 0.85 * smoothstep(0.55, 1.0, u)     # a spark climbing, bursting bright at the top
	else:
		var since := _age - CLIMB
		h = maxf(TOP - SINK * since, 4.0)
		bright = 1.0 if since < BURN else maxf(1.0 - (since - BURN) / FADE, 0.0)
		bright *= 0.92 + 0.08 * sin(_clock * 23.0) * sin(_clock * 7.3)   # the burn flickers
	_sway += delta
	var sway := Vector3(sin(_sway * 0.9) * 1.5, 0, cos(_sway * 0.7) * 1.2) * clampf((_age - CLIMB) / 2.0, 0.0, 1.0)
	var along := clampf(_age / CLIMB, 0.0, 1.0)
	var at := _from.lerp(_apex, along) + Vector3.UP * h + sway
	_light.global_position = at
	_light.light_energy = ENERGY * bright
	_spark.global_position = at
	(_spark.mesh as QuadMesh).material.albedo_color.a = bright
	glow = bright
	var a := _atmos()
	if a:
		a.flare_glow = glow
	if _age >= total:
		_age = -1.0
		glow = 0.0
		if a:
			a.flare_glow = 0.0
		_light.visible = false
		_spark.visible = false
		_t = _rng.randf_range(EVERY.x, EVERY.y)
		flare_out.emit()


## A flare now, from their parapet at a random x (biased toward the player's
## lane: they want to see what is coming at them).
func launch_now() -> void:
	var w := maze.w * maze.cell
	var x := _rng.randf_range(4.0, w - 4.0)
	if _rng.randf() < 0.6:
		x = clampf(player.global_position.x + _rng.randf_range(-18.0, 18.0), 4.0, w - 4.0)
	var z := (maze.their_row0 + TrenchMaze.GRID_D) * maze.cell - 2.0
	_from = Vector3(x, maze.ground_height(x, z) + 1.5, z)
	# it arcs out over the field and hangs there, lighting it from above
	var z_ours := maze.our_row0 * maze.cell
	var za := lerpf(z, z_ours, REACH)
	_apex = Vector3(clampf(x + _rng.randf_range(-6.0, 6.0), 4.0, w - 4.0), maze.ground_height(x, za) + 1.5, za)
	_age = 0.0
	_sway = _rng.randf() * TAU
	flares += 1
	_light.visible = true
	_spark.visible = true
	_light.global_position = _from
	_spark.global_position = _from
	# the pop, from where it went up, and the hiss of the climb
	SfxSynth.play(self, "pop", _from, 2.0, _rng.randf_range(0.6, 0.75), 12.0, 220.0)
	SfxSynth.play(self, "whoosh", _from + Vector3.UP * 3.0, -6.0, _rng.randf_range(0.5, 0.65), 12.0, 180.0)
	flare_up.emit(_from)


## Seconds to the next launch (the tests).
func next_in() -> float:
	return _t if _age < 0.0 else -1.0
