class_name FrontMg
extends Node3D
## An enemy machine-gun emplacement on the Drowned Front (M6, package C5): a
## Maxim on their parapet with a gunner behind it, a traverse it cannot swing
## past, an elevation it cannot depress below (dead ground close under it),
## real sightlines through the fog, bursts and pauses, a belt that runs out,
## a water jacket that boils, and a gunner who can be shot. Every round is a
## real ray: what it hits is what it hits (the player, by `take_damage`; the
## world, by `Impacts`); a round that passes close cracks past the player and
## presses on him (`FpsPlayer.suppress`). Nothing is rolled against the player
## without a ray. It is not omniscient: it fires at what it can see, or at
## where it last saw you, or now and then at nothing.

signal fired(from: Vector3, to: Vector3)

enum State { IDLE, SEARCH, TRACK, RELOAD, OVERHEAT, SILENT }

const TRAVERSE := MountedGun.TRAVERSE
const ELEVATION := MountedGun.ELEVATION
const RANGE := 115.0
const ROUND_DT := 0.085
const BURST := Vector2i(7, 14)
const PAUSE := Vector2(0.8, 2.2)
const BELT := 100
const RELOAD_T := Vector2(5.0, 7.5)
const DAMAGE := Vector2(14.0, 8.0)          ## per round at ≤40 m .. at RANGE
const ERR_ACQUIRE := deg_to_rad(3.2)         ## aim cone when first on target
const ERR_SETTLED := deg_to_rad(0.9)         ## after a couple of seconds of tracking
const SETTLE_T := 2.6
const MECHANISM_HP := 420.0

var maze: TrenchMaze
var player: FpsPlayer
var facing := Vector3.FORWARD                ## straight ahead, horizontal
var gun: MountedGun
var gunner: Clown
var state := State.IDLE
var heat := 0.0
var belt := BELT
var jammed := false
var rounds_fired := 0
var bursts := 0
var hits_on_player := 0
var reloads := 0
var overheats := 0
var longest_pause := 0.0                     ## seconds between bursts while a target was there
var last_seen := Vector3.INF
var last_seen_t := -100.0
var tracked_for := 0.0
var _rng := RandomNumberGenerator.new()
var _t := 0.0                                ## time to the next thing in this state
var _in_burst := 0                           ## rounds left in the burst
var _round_t := 0.0
var _walk := Vector3.ZERO                    ## the burst's starting offset, walked in
var _since_burst := 0.0
var _mech_hp := MECHANISM_HP
var _fog: Node
var _idle_t := 0.0
var _clock := 0.0                            ## game seconds (not the wall clock: tests run fast)


func setup(m: TrenchMaze, p: FpsPlayer, at: Vector3, face: Vector3, seed_: int) -> void:
	maze = m
	player = p
	_rng.seed = seed_
	facing = Vector3(face.x, 0, face.z).normalized()
	global_position = at
	look_at(at + facing, Vector3.UP)
	gun = MountedGun.new()
	gun.name = "Gun"
	add_child(gun)
	gun.position = Vector3.ZERO               # look_at above put this node's -z along `facing`, which is where MountedGun's muzzle points
	gun.floor_y = at.y - 0.3
	gun.active = false
	gun.set_meta(&"front_mg", self)
	gun.set_meta(&"surface", "metal")
	_t = _rng.randf_range(20.0, 50.0)
	_idle_t = _rng.randf_range(25.0, 70.0)


func set_gunner(c: Clown) -> void:
	gunner = c
	var brain := c.get_node_or_null("Brain")
	if brain:
		brain.set_physics_process(false)      # at the gun, not his own counsel
	c.set_meta(&"mg_gunner", true)


func alive() -> bool:
	return gunner != null and is_instance_valid(gunner) and not gunner.dead and not jammed


func muzzle() -> Vector3:
	return gun._muzzle.global_position if gun and gun._muzzle else global_position + Vector3.UP * 0.42


## The mechanism takes a hit (the player's rounds into the gun itself).
func shot(pos: Vector3, dir: Vector3, dmg: float) -> void:
	_mech_hp -= dmg
	MechFx.sparks(self, pos, -dir, 0.4)
	if _mech_hp <= 0.0 and not jammed:
		jammed = true
		SfxSynth.play(self, "metal_snap", pos, 2.0, 0.8, 8.0, 60.0)
		_go(State.SILENT)


func _physics_process(delta: float) -> void:
	if player == null or maze == null:
		return
	_clock += delta
	_since_burst += delta
	heat = maxf(heat - delta * MountedGun.COOL_RATE * (0.5 if _in_burst > 0 else 1.4), 0.0)
	if not alive():
		if state != State.SILENT:
			_go(State.SILENT)
		_silent_gun()
		return
	if state == State.SILENT:
		_go(State.IDLE)                            # back in action (a jam cleared by the tests/director)
	var sees := _sees_target()
	if sees:
		last_seen = player.global_position
		last_seen_t = _clock
		tracked_for += delta
	else:
		tracked_for = maxf(tracked_for - delta * 2.0, 0.0)
	match state:
		State.IDLE:
			if sees:
				_go(State.TRACK)
			elif _engage_left > 0:
				# (M9) the director's: working over a sector away from the player
				if _in_burst == 0:
					_t -= delta
					if _t <= 0.0:
						_engage_left -= 1
						_t = _rng.randf_range(PAUSE.x, PAUSE.y) * 1.3
						var spread := Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-3.0, 3.0))
						_start_burst(_engage_at + spread, 0.7)
						engaged += 1
			else:
				_idle_t -= delta
				if _idle_t <= 0.0:
					# a burst across the field at nothing in particular: it keeps heads down
					_idle_t = _rng.randf_range(35.0, 90.0)
					_start_burst(_random_field_point(), 0.5)
		State.SEARCH:
			if sees:
				_go(State.TRACK)
			else:
				_t -= delta
				if _t <= 0.0:
					_t = _rng.randf_range(5.0, 11.0)
					if _clock - last_seen_t > 25.0:
						_go(State.IDLE)
					elif last_seen != Vector3.INF:
						var spread := last_seen + Vector3(_rng.randf_range(-4.0, 4.0), 0, _rng.randf_range(-4.0, 4.0))
						_start_burst(spread, 0.6)
		State.TRACK:
			if not sees and _in_burst == 0:
				_t = _rng.randf_range(2.0, 4.0)
				_go(State.SEARCH)
			elif _in_burst == 0:
				_t -= delta
				if _t <= 0.0:
					_start_burst(player.global_position + Vector3.UP * player.chest_height(), 1.0)
		State.RELOAD:
			_t -= delta
			if _t <= 0.0:
				belt = BELT
				SfxSynth.play(self, "metal_rattle", muzzle(), -2.0, 1.0, 6.0, 50.0)
				_go(State.TRACK if sees else State.SEARCH)
		State.OVERHEAT:
			if heat <= MountedGun.OVERHEAT_RESUME:
				_go(State.TRACK if sees else State.SEARCH)
		State.SILENT:
			pass
	# the rounds of a burst
	if _in_burst > 0:
		_round_t -= delta
		while _round_t <= 0.0 and _in_burst > 0:
			_round_t += ROUND_DT
			_round()
	_point_gun(delta)
	if sees and _in_burst == 0 and state == State.TRACK:
		longest_pause = maxf(longest_pause, _since_burst)


func _go(s: State) -> void:
	state = s
	match s:
		State.TRACK:
			_t = _rng.randf_range(0.25, 0.7)
		State.RELOAD:
			_t = _rng.randf_range(RELOAD_T.x, RELOAD_T.y)
			reloads += 1
			SfxSynth.play(self, "mag_out", muzzle(), -4.0, 0.9, 6.0, 50.0)
		State.OVERHEAT:
			overheats += 1
		State.SILENT:
			_in_burst = 0


## Can the gun see the player: in its arc, in range, through the fog, with a
## clear line from the muzzle to his chest or his eye (crouching lowers both).
func _sees_target() -> bool:
	if player.dead:
		return false
	var from := muzzle()
	var to_chest := player.global_position + Vector3.UP * player.chest_height()
	var d := from.distance_to(to_chest)
	if d > RANGE or d < 1.5:
		return false
	if not _in_arc(to_chest):
		return false
	if _fog == null or not is_instance_valid(_fog):
		_fog = get_tree().get_first_node_in_group(&"fog")
	if _fog and _fog.has_method("visibility") and _fog.visibility(from, to_chest) < 0.3:
		return false
	var space := get_world_3d().direct_space_state
	for target in [to_chest, player.global_position + Vector3.UP * player.eye_height()]:
		var q := PhysicsRayQueryParameters3D.create(from, target, FpsPlayer.LAYER_WORLD)
		q.exclude = [gun.get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _in_arc(target: Vector3) -> bool:
	var rel := target - muzzle()
	var flat := Vector3(rel.x, 0, rel.z)
	if flat.length() < 0.01:
		return false
	var yaw := facing.signed_angle_to(flat.normalized(), Vector3.UP)
	if absf(yaw) > TRAVERSE:
		return false
	var pitch := atan2(rel.y, flat.length())
	return pitch >= ELEVATION.x and pitch <= ELEVATION.y


func _start_burst(at: Vector3, intent: float) -> void:
	if state == State.RELOAD or state == State.OVERHEAT or state == State.SILENT:
		return
	if belt <= 0:
		_go(State.RELOAD)
		return
	if heat >= 1.0:
		_go(State.OVERHEAT)
		return
	_in_burst = _rng.randi_range(BURST.x, BURST.y)
	if intent < 0.9:
		_in_burst = maxi(_in_burst / 2, 4)
	_round_t = 0.0
	bursts += 1
	_since_burst = 0.0
	_aim_at = at
	# the burst starts a little off and walks onto the mark
	var side := facing.cross(Vector3.UP)
	_walk = side * _rng.randf_range(-1.4, 1.4) * (1.0 if tracked_for < SETTLE_T else 0.4) + Vector3.UP * _rng.randf_range(-0.3, 0.2)


var _aim_at := Vector3.ZERO
var _engage_left := 0
var _engage_at := Vector3.ZERO
var engaged := 0                     ## bursts fired on the director's word


## (M9) Work over `at` with `n` bursts, when idle and the point is in the arc
## and in range. The player seen puts a stop to it (TRACK wins). Returns false
## when the gun cannot: silent, busy with him, or the point out of its reach.
func engage(at: Vector3, n: int) -> bool:
	if not alive() or state != State.IDLE or _engage_left > 0:
		return false
	if not _in_arc(at) or global_position.distance_to(at) > RANGE:
		return false
	_engage_at = at
	_engage_left = n
	_t = _rng.randf_range(0.3, 1.2)
	return true


func _round() -> void:
	if belt <= 0 or heat >= 1.0 or not alive():
		_in_burst = 0
		if belt <= 0:
			_go(State.RELOAD)
		elif heat >= 1.0:
			_go(State.OVERHEAT)
		return
	_in_burst -= 1
	if _in_burst == 0:
		_t = _rng.randf_range(PAUSE.x, PAUSE.y)    # the pause before the next burst
	belt -= 1
	rounds_fired += 1
	heat = minf(heat + MountedGun.HEAT_PER_SHOT, 1.0)
	var from := muzzle()
	# where it is going: the mark (the player, live, if we are tracking him),
	# the walk-in offset shrinking through the burst, and the cone of error
	var mark := _aim_at
	if state == State.TRACK and _sees_target_cheap():
		mark = player.global_position + Vector3.UP * player.chest_height()
	var walk_left := float(_in_burst) / float(BURST.y)
	mark += _walk * walk_left
	var err := lerpf(ERR_ACQUIRE, ERR_SETTLED, clampf(tracked_for / SETTLE_T, 0.0, 1.0))
	var dir := (mark - from).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	dir = (dir + side * _rng.randfn(0.0, err) + up * _rng.randfn(0.0, err * 0.8)).normalized()
	# the gun will not swing past its traverse or dip below its elevation
	dir = _clamp_to_arc(dir)
	var to := from + dir * RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, FpsPlayer.LAYER_WORLD | (1 << 1))
	q.exclude = [gun.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c == player:
			hits_on_player += 1
			var d := from.distance_to(hit.position)
			var dmg := lerpf(DAMAGE.x, DAMAGE.y, clampf((d - 40.0) / (RANGE - 40.0), 0.0, 1.0))
			player.take_damage(dmg, dir)
		else:
			Impacts.bullet(hit, dir, {name = "Maxim", damage = 60.0}, 1.6)
	# a round that goes close past him
	if not player.dead:
		var chest := player.global_position + Vector3.UP * player.chest_height()
		var seg := end - from
		var t := clampf((chest - from).dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
		var closest := chest.distance_to(from + seg * t)
		if closest < 2.2 and t > 0.02 and t < 0.999:
			player.suppress(clampf(1.0 - closest / 2.2, 0.15, 1.0) * 0.35, from + seg * t)
	# the soldiers out there hear it crack past too
	if rounds_fired % 2 == 0:
		for n in get_tree().get_nodes_in_group(&"clowns"):
			var cl := n as Clown
			if cl == null or cl.dead or cl == gunner:
				continue
			var chest := cl.global_position + Vector3.UP * 1.25
			var seg := end - from
			var t := clampf((chest - from).dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
			if t > 0.02 and t < 0.999 and chest.distance_to(from + seg * t) < 1.3:
				var b := cl.get_node_or_null("Brain")
				if b and b.has_method("near_miss"):
					b.near_miss(from, chest.distance_to(from + seg * t), from + seg * t)
	gun._flash.light_energy = 6.0
	gun._kick = 1.0
	SfxSynth.play(self, "mg_shot", from, 2.0, _rng.randf_range(0.95, 1.05), 14.0, 220.0)
	if rounds_fired % 3 == 0:
		gun._tracer(from, end)
	fired.emit(from, end)


func _sees_target_cheap() -> bool:
	return _clock - last_seen_t < 0.3


func _clamp_to_arc(dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0, dir.z)
	var yaw := facing.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length() > 0.001 else 0.0
	var pitch := atan2(dir.y, flat.length())
	yaw = clampf(yaw, -TRAVERSE, TRAVERSE)
	pitch = clampf(pitch, ELEVATION.x, ELEVATION.y)
	var f := facing.rotated(Vector3.UP, yaw)
	return (f * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## The gun and the gunner turn toward the mark.
func _point_gun(delta: float) -> void:
	var want := _aim_at if (_in_burst > 0 or state == State.TRACK or state == State.SEARCH) else global_position + facing * 40.0
	if state == State.TRACK and not player.dead:
		want = player.global_position + Vector3.UP * player.chest_height()
	var rel := want - muzzle()
	var flat := Vector3(rel.x, 0, rel.z)
	if flat.length() < 0.01:
		return
	var yaw := clampf(facing.signed_angle_to(flat.normalized(), Vector3.UP), -TRAVERSE, TRAVERSE)
	var pitch := clampf(atan2(rel.y, flat.length()), ELEVATION.x, ELEVATION.y)
	gun.yaw = lerp_angle(gun.yaw, yaw, minf(delta * 3.0, 1.0))
	gun.pitch = lerpf(gun.pitch, pitch, minf(delta * 3.0, 1.0))
	if gunner and is_instance_valid(gunner) and not gunner.dead:
		gunner.look_at_point(want, 0.8)
		var flat_face := Vector3(want.x - gunner.global_position.x, 0, want.z - gunner.global_position.z)
		if flat_face.length() > 0.1:
			gunner.rotation.y = lerp_angle(gunner.rotation.y, atan2(flat_face.x, flat_face.z), minf(delta * 3.0, 1.0))


func _silent_gun() -> void:
	# the gunner is down or the gun is wrecked: the piece can be taken
	if gun and not gun.active and not jammed:
		gun.active = true
		gun.leave_ok = true
		gun.player = player


func _random_field_point() -> Vector3:
	var yaw := _rng.randf_range(-TRAVERSE * 0.8, TRAVERSE * 0.8)
	var dist := _rng.randf_range(25.0, 80.0)
	var p := global_position + facing.rotated(Vector3.UP, yaw) * dist
	p.y = maze.ground_height(p.x, p.z) + 0.6 if maze.has_method("ground_height") else p.y
	return p
