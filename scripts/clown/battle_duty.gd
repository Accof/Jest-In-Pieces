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

##   TOP_RIFLE  up on the open ground in front of the fire trench, behind what
##              cover there is: kneels, comes up to fire out across No Man's
##              Land. Seen from the fire step and from the trench below.
##   SENTRY     up on the top where he can see down a trench or over a stretch
##              of ground: watches, turning slowly.
##   MARKSMAN   up on the top well away from the start, watching: when he can
##              see the player's head (the fire step, a ramp, the top, a
##              bridge) for long enough he fires, a carefully aimed round every
##              few seconds, the flash and the crack showing where he is. He
##              misses more than he hits at range. Close in, or hit, he fights
##              like any other.
##   TRENCH_PATROL  walks a beat of three or four places along the trenches,
##              round the bends, stopping to listen.
enum Kind { FRONTLINE, GUARD, RUNNER, PATROL, TOP_RIFLE, SENTRY, MARKSMAN, TRENCH_PATROL }

const NAMES := ["frontline", "guard", "runner", "patrol", "top_rifle", "sentry", "marksman", "trench_patrol"]

## MARKSMAN: how far he will shoot, how long he must see the head first, the
## wait between rounds, the damage of a hit, and his chance (at 0 m, lost per
## metre, the least).
const MARK_RANGE := 75.0
const MARK_NOTICE := 1.6
const MARK_GAP := Vector2(4.0, 7.0)
const MARK_DAMAGE := 14.0
const MARK_CHANCE := Vector3(0.3, 0.005, 0.06)

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
## The second man of a pair on a beat: walks a step or two behind `leader`.
## Sent across the player's way (TrenchBattle._encounter): the places to
## walk through first, then back to his duty.
var detour: Array[Vector3] = []
var crossed := 0
var leader: BattleDuty = null
var follower: BattleDuty = null
## MARKSMAN: other places he could watch from (TrenchBattle picks the one with
## the most ground in view once the world's collision is in place).
var candidates: Array = []
var view := -1             ## MARKSMAN: how many of the sampled places he can see
var follow_delay := 0.0
var mark_shots := 0        ## MARKSMAN: rounds at the player
var mark_hits := 0
var _spot := 0.0           # MARKSMAN: how long he has had the player's head in view
var _sweep := 0.0

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


## (M9) A new post: he walks there (the duties' own `_go_back`) and takes it
## up. A shell near his bay, a squad's word to withdraw.
func relocate(new_post: Vector3, new_face := Vector3.INF, new_kind := -1) -> void:
	post = new_post
	if new_face != Vector3.INF:
		face = new_face
		face_b = new_face.rotated(Vector3.UP, 2.4)
	if new_kind >= 0:
		kind = new_kind as Kind
		_on_duty_senses()
	route.clear()
	detour.clear()
	_phase = 0
	_t = 0.0
	_stuck = 0.0
	relocations += 1


var relocations := 0


## Extra corridor cells of hearing: the frontline is deafened by the guns, a
## guard is listening for it.
func hearing_bonus() -> int:
	match kind:
		Kind.FRONTLINE, Kind.TOP_RIFLE:
			return -2
		Kind.GUARD, Kind.SENTRY, Kind.TRENCH_PATROL:
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
	if not detour.is_empty():
		if _flat(detour[0] - clown.global_position).length() < 0.5:
			detour.remove_at(0)
			if detour.is_empty():
				crossed += 1
		else:
			_walk_to(detour[0], delta, brain.move_speed * (1.0 if kind == Kind.RUNNER else 0.8))
			# not getting there: give it up
			if _last_pos != Vector3.INF and clown.global_position.distance_to(_last_pos) < 0.2 * delta:
				_stuck += delta
			else:
				_stuck = maxf(_stuck - delta, 0.0)
			_last_pos = clown.global_position
			if _stuck > 5.0:
				_stuck = 0.0
				detour.clear()
			return true
	match kind:
		Kind.FRONTLINE, Kind.TOP_RIFLE:
			_frontline(delta)
		Kind.GUARD, Kind.SENTRY:
			_guard(delta)
		Kind.RUNNER:
			_travel(delta, brain.run_speed * 0.8, 2.5, 6.0)
		Kind.PATROL:
			_travel(delta, brain.move_speed * 0.58, 3.0, 8.0)
		Kind.TRENCH_PATROL:
			if leader != null and is_instance_valid(leader) and is_instance_valid(leader.clown) and not leader.clown.dead and leader.brain.mind == ClownBrain.Mind.IDLE:
				_follow(delta)
			else:
				_travel(delta, brain.move_speed * 0.55, 2.0, 6.0)
		Kind.MARKSMAN:
			_marksman(delta)
	return true


# (the fractions of move_speed here are set for a ~2 m/s walk: a patrol
# ambles at ~1.2 m/s)
# --- the duties ----------------------------------------------------------------
func _go_back(delta: float) -> bool:
	if _flat(post - clown.global_position).length() > 0.35:
		clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 3.0)
		_walk_to(post, delta, brain.move_speed * 0.75)
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
			if kind == Kind.TOP_RIFLE:
				brain.crouch_want = 1.0     # down behind his cover
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
			brain.crouch_want = 0.0
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
	if brain.lmg:
		# a Lewis gun: a short burst out across No Man's Land
		for i in randi_range(4, 9):
			get_tree().create_timer(i * 0.11).timeout.connect(_one_round)
		return
	_one_round()


func _one_round() -> void:
	if not is_instance_valid(clown) or clown.dead or brain.mind != ClownBrain.Mind.IDLE:
		return
	var from := clown.muzzle_position()
	clown.fired()
	var spread := Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 0.8), 0)
	brain._tracer(from, from + (_aim_at + spread - from).normalized() * 60.0)


func _marksman(delta: float) -> void:
	if _go_back(delta):
		return
	brain._settle(delta, false)
	clown.attack_amount = 0.0
	var pl := brain.player
	var head := pl.global_position + Vector3.UP * 1.55
	var eye := clown.global_position + Vector3.UP * 1.5
	var to := head - eye
	var d := to.length()
	var in_cone := Vector3(face.x, 0, face.z).normalized().dot(Vector3(to.x, 0, to.z).normalized()) > cos(deg_to_rad(75.0))
	var sees := d < MARK_RANGE and in_cone and brain._clear(eye, head)
	var fog := get_tree().get_first_node_in_group(&"fog")
	if sees and fog and fog.visibility(eye, head) < 0.3:
		sees = false                              # lost in a fog bank
	if sees and d < 14.0:
		brain.alert(pl.global_position)          # close: he fights like the rest
		return
	_spot = minf(_spot + delta, 6.0) if sees else maxf(_spot - delta * 0.6, 0.0)
	_t -= delta
	if _spot > MARK_NOTICE:
		# on him: the rifle up, tracking him
		brain._face(to, delta, 4.0)
		brain.crouch_want = 0.3
		clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
		clown.aim_point = head
		if _t <= 0.0 and sees and clown.aim_amount > 0.9:
			_mark_fire(head, d)
			_t = randf_range(MARK_GAP.x, MARK_GAP.y)
	else:
		# watching his ground: kneeling, the rifle half up, turning slowly
		_t = maxf(_t, randf_range(1.0, 2.0))
		brain.crouch_want = 0.6
		clown.aim_amount = move_toward(clown.aim_amount, 0.35, delta * 1.5)
		_sweep += delta * 0.25
		brain._face(face.rotated(Vector3.UP, sin(_sweep) * 0.6), delta, 1.2)


func _mark_fire(head: Vector3, d: float) -> void:
	if not clown.has_rifle:
		return
	mark_shots += 1
	var from := clown.muzzle_position()
	clown.fired()
	# the crack carries a long way (where it came from is how you find him)
	SfxSynth.play(clown, "rifle_shot", from, 4.0, randf_range(0.92, 1.05), 18.0, 220.0)
	var pl := brain.player
	var chance := clampf(MARK_CHANCE.x - d * MARK_CHANCE.y, MARK_CHANCE.z, MARK_CHANCE.x)
	if pl.velocity.length() > 2.0:
		chance *= 0.5
	var end := head + Vector3(randf_range(-0.9, 0.9), randf_range(-0.3, 0.8), randf_range(-0.9, 0.9))
	if randf() < chance:
		mark_hits += 1
		end = head
		pl.take_damage(MARK_DAMAGE, (head - from).normalized())
	else:
		brain._miss_lands(from, (end - from).normalized(), d + 12.0)
	brain._tracer(from, from + (end - from).normalized() * (d + 3.0))


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
	# leading a pair: wait for the other to catch up
	if follower != null and is_instance_valid(follower) and is_instance_valid(follower.clown) and not follower.clown.dead and follower.brain.mind == ClownBrain.Mind.IDLE and follower.follow_delay <= 0.0:
		if clown.global_position.distance_to(follower.clown.global_position) > 3.0:
			brain._settle(delta)
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


func _follow(delta: float) -> void:
	var lc := leader.clown
	var back := Vector3(lc.global_basis.z.x, 0, lc.global_basis.z.z).normalized()
	var spot := lc.global_position - back * 1.3
	if follow_delay > 0.0:
		follow_delay -= delta
		brain._settle(delta)
		return
	var gap := _flat(spot - clown.global_position).length()
	if gap > 0.6:
		# falling behind: hurry
		_walk_to(spot, delta, brain.move_speed * (0.7 if gap < 2.5 else 1.25))
	else:
		brain._settle(delta)
		brain._face(back, delta, 2.0)


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
		Kind.TOP_RIFLE:
			brain.sight_half_angle = 40.0
			brain.sense_range = 1.2
		Kind.SENTRY:
			brain.sight_half_angle = 80.0
			brain.sense_range = 2.5
			brain.sight_range = maxf(float(_senses.sight_range), 22.0)
		Kind.MARKSMAN:
			brain.sight_half_angle = 60.0
		Kind.TRENCH_PATROL:
			brain.sight_half_angle = 60.0
			brain.sense_range = 2.0


func _on_alerted(where: Vector3, firsthand: bool) -> void:
	_was_alert = true
	detour.clear()
	for k: String in _senses:
		brain.set(k, _senses[k])
	brain.crouch_want = 0.0
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
