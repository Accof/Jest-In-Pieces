class_name FrontArtillery
extends Node3D
## The guns behind their lines, on the Drowned Front (M6, package C5): now and
## then a salvo of a few shells comes down on the field, each one whistling in
## for a couple of seconds first so you know it is coming and roughly where;
## then a lull. The far rumble and flashes are the art's ambience as before;
## these are the dangerous ones. Fair by construction: a shell is never
## aimed within `CLEAR` of where you are when it is fired, never more than
## one of a salvo lands near you, nothing falls in the H.Q. trench or on the
## way in behind our rear, and between salvos there is always a window.
## The blast is the game's own `Explosion` (`shell` profile), so damage, the
## ragdolls, the gore and the scorch are what they always were; `Impacts`
## adds what the ground was made of.

signal shell_landed(at: Vector3)
signal shell_coming(at: Vector3, in_seconds: float)

const FIRST := Vector2(25.0, 45.0)          ## seconds before the first salvo
const LULL := Vector2(32.0, 70.0)           ## between salvos
const SALVO := Vector2i(3, 5)
const SALVO_SPREAD := Vector2(1.6, 3.2)     ## seconds between the shells of a salvo
const WHISTLE := 2.4                        ## seconds of warning
const CLEAR := 7.5                          ## never aimed closer to the player than this
const NEAR := 16.0                          ## "near the player": at most one of these a salvo

var maze: FrontMaze
var player: FpsPlayer
var z_min := 0.0                            ## the fair zone: the field and the two front parapets
var z_max := 0.0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _pending: Array = []                    ## [{at, t}] shells in the air
var _salvo_left := 0
var _salvo_centre := Vector3.ZERO
var _salvo_near_used := false
var _salvo_t := 0.0
# counters (tests)
var salvos := 0
var shells := 0
var landed: Array[Vector3] = []
var windows: Array[float] = []              ## the lulls as they happen
var _last_land_t := -1.0
var _last_salvo_end := -1.0
var _clock := 0.0


func setup(m: FrontMaze, p: FpsPlayer, seed_: int) -> void:
	maze = m
	player = p
	_rng.seed = seed_
	z_min = (m.their_row0 + TrenchMaze.GRID_D - 1 - TrenchMaze.FIRE_ROW) * m.cell - 1.0
	z_max = (m.our_row0 + TrenchMaze.FIRE_ROW + 1) * m.cell + 1.0
	_t = _rng.randf_range(FIRST.x, FIRST.y) * float(m.knobs.get("art_first", 1.0))


func _physics_process(delta: float) -> void:
	if maze == null or player == null:
		return
	_clock += delta
	var now := _clock
	# the shells in the air
	for s: Dictionary in _pending.duplicate():
		s.t -= delta
		if s.t <= 0.0:
			_pending.erase(s)
			_land(s.at)
	# a salvo in progress
	if _salvo_left > 0:
		_salvo_t -= delta
		if _salvo_t <= 0.0:
			_salvo_t = _rng.randf_range(SALVO_SPREAD.x, SALVO_SPREAD.y)
			_salvo_left -= 1
			_fire_one()
			if _salvo_left == 0:
				_last_salvo_end = now
				_t = _rng.randf_range(LULL.x, LULL.y) * float(maze.knobs.get("art_lull", 1.0))
		return
	_t -= delta
	if _t <= 0.0:
		salvo_now()


## A salvo, now: its centre on the field, biased toward the player's part of
## it (the guns have seen the attack) but never on him.
func salvo_now(centre := Vector3.INF) -> void:
	if _last_salvo_end >= 0.0:
		windows.append(_clock - _last_salvo_end)
	salvos += 1
	_salvo_left = _rng.randi_range(SALVO.x, SALVO.y) + int(maze.knobs.get("art_salvo_extra", 0))
	_salvo_near_used = false
	_salvo_t = 0.0
	if centre != Vector3.INF:
		_salvo_centre = centre
	else:
		var w := maze.w * maze.cell
		if _rng.randf() < 0.6 and _in_zone(player.global_position):
			var a := _rng.randf() * TAU
			_salvo_centre = player.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(10.0, 24.0)
		else:
			_salvo_centre = Vector3(_rng.randf_range(4.0, w - 4.0), 0, _rng.randf_range(z_min + 8.0, z_max - 8.0))
	_salvo_centre.x = clampf(_salvo_centre.x, -6.0, maze.w * maze.cell + 6.0)
	_salvo_centre.z = clampf(_salvo_centre.z, z_min, z_max)


func _fire_one() -> void:
	var at := Vector3.INF
	for attempt in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.0, 9.0)
		var p := _salvo_centre + Vector3(cos(a), 0, sin(a)) * r
		p.x = clampf(p.x, -6.0, maze.w * maze.cell + 6.0)
		p.z = clampf(p.z, z_min, z_max)
		var dp := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		if dp < CLEAR:
			continue
		if dp < NEAR:
			if _salvo_near_used:
				continue
			_salvo_near_used = true
		at = p
		break
	if at == Vector3.INF:
		return
	at.y = maze.ground_height(at.x, at.z)
	shells += 1
	_pending.append({at = at, t = WHISTLE})
	shell_coming.emit(at, WHISTLE)
	# the whistle, from up where it is coming from, so it reads as "incoming, there"
	SfxSynth.play(self, "shell_whistle", at + Vector3.UP * 18.0, 4.0, _rng.randf_range(0.92, 1.08), 20.0, 400.0)


func _land(at: Vector3) -> void:
	landed.append(at)
	_last_land_t = _clock
	var ex := Explosion.detonate(get_parent(), at, "shell")
	shell_landed.emit(at)
	# the soldiers near it get their heads down (the blast itself already hurts and flings them)
	for n in get_tree().get_nodes_in_group(&"clowns"):
		var c := n as Clown
		if c == null or c.dead:
			continue
		var d := c.global_position.distance_to(at)
		if d < 14.0:
			var b := c.get_node_or_null("Brain")
			if b and b.has_method("near_miss"):
				b.near_miss(at + Vector3.UP * 30.0, d * 0.5, at)
	if ex:
		ex.set_meta(&"artillery", true)


func _in_zone(p: Vector3) -> bool:
	return p.z > z_min - 10.0 and p.z < z_max + 10.0


## Seconds until the next salvo starts (tests, the director later).
func next_in() -> float:
	return _t if _salvo_left == 0 else 0.0
