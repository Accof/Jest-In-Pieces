class_name BattleDuty
extends Node
## A soldier's job on the trench floors while he does not know the player is
## there (ClownBrain asks it to drive him while unaware, and he goes back to
## it after a search). Set up by TrenchBattle.
##
##   FRONTLINE  on a fire step, rifle over the parapet at No Man's Land: aims,
##              fires now and then (effects only), works the bolt, lowers it,
##              rests. Eyes on the enemy: a narrow cone to the front, the din
##              of the guns in his ears. Can be taken from behind.
##   GUARD      at a dugout door or a junction: looks up and down the trench;
##              a wide cone, sharp ears. A noise brings him to look.
##   RUNNER     carries messages: runs between two places (often over a
##              footbridge or along the top), stops, catches his breath, back.
##   PATROL     walks a line up on the top among the wire and the mist,
##              stopping to look out.
##
## Alerts are local: a man who sees the player himself, or is shot at, calls
## out, and the men near enough to hear him (or in sight of him) come for the
## place he called, not for where the player is now. That call is passed on
## once at most.

enum Kind { FRONTLINE, GUARD, RUNNER, PATROL }

const NAMES := ["frontline", "guard", "runner", "patrol"]

var kind := Kind.GUARD
## Where he stands (FRONTLINE, GUARD) and which way he faces.
var post := Vector3.ZERO
var face := Vector3.FORWARD
## The second way a guard looks (up and down the trench).
var face_b := Vector3.BACK
## RUNNER / PATROL: the places he goes between, in turn.
var route: Array[Vector3] = []
## How far a shout carries (m), and how far in plain sight.
var shout_range := 7.0
var sight_call_range := 14.0

var brain: ClownBrain
var clown: Clown

# test counters
var shots := 0
var legs := 0              ## RUNNER/PATROL: route legs finished
var shouted := 0
var told_hops := 0         ## set by whoever told him (0: saw it himself)
var returned := 0          ## times he took up his duty again after an alert

var _leg := 0
var _wait := 0.0
var _phase := 0            # FRONTLINE: 0 rest, 1 raising, 2 aiming, 3 the bolt; GUARD: which way
var _t := 0.0
var _aim_at := Vector3.ZERO
var _shots_left := 0
var _stuck := 0.0
var _last_pos := Vector3.INF
var _was_alert := false
var _senses := {}          # the brain's own, restored while alert


func _init(k: Kind = Kind.GUARD) -> void:
	kind = k


func attach(b: ClownBrain) -> void:
	brain = b
	clown = b.clown if b.clown else b.get_parent() as Clown
	brain.duty = self
	brain.perceive_every = randf_range(0.15, 0.25)
	brain._perceive_t = randf() * brain.perceive_every     # not all on the same frame
	_senses = {sight_half_angle = brain.sight_half_angle, sense_range = brain.sense_range, sight_range = brain.sight_range}
	brain.alerted.connect(_on_alerted)
	_wait = randf_range(0.0, 3.0)
	_t = randf_range(0.0, 4.0)
	_on_duty_senses()


## Extra corridor cells of hearing: the frontline is deafened by the guns, a
## guard is listening for it.
func hearing_bonus() -> int:
	match kind:
		Kind.FRONTLINE:
			return -2
		Kind.GUARD:
			return 1
	return 0


func name_of() -> String:
	return NAMES[kind]


## Called by the brain every physics frame while it is unaware. True: done.
func tick(delta: float) -> bool:
	if _was_alert:
		_was_alert = false
		returned += 1
		_on_duty_senses()
		_phase = 0
		_t = 0.0
	match kind:
		Kind.FRONTLINE:
			_frontline(delta)
		Kind.GUARD:
			_guard(delta)
		Kind.RUNNER:
			_travel(delta, brain.run_speed * 0.8, 2.5, 6.0)
		Kind.PATROL:
			_travel(delta, brain.move_speed * 0.42, 3.0, 8.0)
	return true


# --- the duties ----------------------------------------------------------------
func _go_back(delta: float) -> bool:
	if _flat(post - clown.global_position).length() > 0.35:
		clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 3.0)
		_walk_to(post, delta, brain.move_speed * 0.55)
		return true
	return false


func _frontline(delta: float) -> void:
	if _go_back(delta):
		return
	brain._settle(delta, false)
	clown.attack_amount = 0.0
	_t -= delta
	match _phase:
		0:  # resting below the parapet, now and then a glance along the trench
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 2.5)
			var look := face
			if fmod(_t, 7.0) < 1.6:
				look = face.rotated(Vector3.UP, 0.9 * signf(sin(_t * 0.37 + post.x)))
			brain._face(look, delta, 2.5)
			brain.sight_half_angle = 55.0
			if _t <= 0.0:
				_phase = 1
				_t = randf_range(0.5, 0.9)
				_shots_left = randi_range(1, 4)
				_pick_target()
		1, 2:  # up over the parapet, picking a target out there
			brain.sight_half_angle = 32.0
			brain._face(_aim_at - clown.global_position, delta, 5.0)
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
			clown.aim_point = _aim_at
			if _phase == 1 and _t <= 0.0:
				_phase = 2
				_t = randf_range(1.0, 3.2)
			elif _phase == 2 and _t <= 0.0:
				_fire()
				_phase = 3
				_t = 0.3 + clown.bolt_seconds + randf_range(0.2, 0.8)
		3:  # the bolt, then another or down again
			clown.aim_point = _aim_at
			if _t <= 0.0:
				_shots_left -= 1
				if _shots_left > 0:
					_phase = 2
					_t = randf_range(0.8, 2.6)
					if randf() < 0.4:
						_pick_target()
				else:
					_phase = 0
					_t = randf_range(3.0, 9.0)


func _pick_target() -> void:
	_aim_at = post + Vector3(randf_range(-18.0, 18.0), randf_range(1.6, 2.6), -randf_range(45.0, 95.0))


func _fire() -> void:
	if not clown.has_rifle:
		return
	shots += 1
	var from := clown.muzzle_position()
	clown.fired()
	brain._tracer(from, from + (_aim_at - from).normalized() * 60.0)


func _guard(delta: float) -> void:
	if _go_back(delta):
		return
	brain._settle(delta)
	_t -= delta
	if _t <= 0.0:
		_phase = 1 - _phase
		_t = randf_range(3.5, 8.0)
	brain._face(face if _phase == 0 else face_b, delta, 2.0)


func _travel(delta: float, speed: float, rest_min: float, rest_max: float) -> void:
	if route.is_empty():
		_guard(delta)
		return
	var goal := route[_leg % route.size()]
	if _wait > 0.0:
		_wait -= delta
		brain._settle(delta)
		if kind == Kind.PATROL:
			brain._face(Vector3(0, 0, -1), delta, 1.5)    # looking out over No Man's Land
		return
	if _flat(goal - clown.global_position).length() < 0.45:
		legs += 1
		_leg += 1
		_wait = randf_range(rest_min, rest_max)
		_stuck = 0.0
		return
	_walk_to(goal, delta, speed)
	# not getting there: on to the next place
	if _last_pos != Vector3.INF and clown.global_position.distance_to(_last_pos) < 0.2 * delta:
		_stuck += delta
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	_last_pos = clown.global_position
	if _stuck > 6.0:
		_stuck = 0.0
		_leg += 1


func _walk_to(to: Vector3, delta: float, speed: float) -> void:
	brain._go_to(to, delta, speed)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# --- senses and alerts ---------------------------------------------------------
func _on_duty_senses() -> void:
	brain.perceive_every = randf_range(0.15, 0.25)
	match kind:
		Kind.FRONTLINE:
			brain.sight_half_angle = 40.0
			brain.sense_range = 1.2
		Kind.GUARD:
			brain.sight_half_angle = 80.0
			brain.sense_range = 3.0
		Kind.RUNNER:
			brain.sight_half_angle = 55.0
			brain.sense_range = 1.8
		Kind.PATROL:
			brain.sight_half_angle = 60.0
			brain.sight_range = maxf(float(_senses.sight_range), 20.0)


func _on_alerted(where: Vector3, firsthand: bool) -> void:
	_was_alert = true
	for k: String in _senses:
		brain.set(k, _senses[k])
	clown.crouch_amount = 0.0
	var hops := 0 if firsthand else told_hops
	told_hops = 0
	if hops >= 2:
		return
	# calls out after a moment
	var t := get_tree().create_timer(randf_range(0.25, 0.7))
	t.timeout.connect(_shout.bind(where, hops))


func _shout(where: Vector3, hops: int) -> void:
	if not is_instance_valid(clown) or clown.dead:
		return
	shouted += 1
	SfxSynth.play(clown, "shout", clown.global_position + Vector3.UP * 1.6, 2.0, randf_range(0.9, 1.1), 8.0, 50.0)
	var eye := clown.global_position + Vector3.UP * 1.5
	for o in brain.others:
		if not is_instance_valid(o) or o == clown or o.dead:
			continue
		var b := o.get_node_or_null("Brain") as ClownBrain
		if b == null or b.mind == ClownBrain.Mind.HUNT:
			continue
		var d: float = o.global_position.distance_to(clown.global_position)
		var heard := d <= shout_range
		var saw := d <= sight_call_range and brain._clear(eye, o.global_position + Vector3.UP * 1.5)
		if not (heard or saw):
			continue
		if b.duty:
			b.duty.told_hops = hops + 1
		b.alert(where, true, false)
