class_name ClownBrain
extends Node
## Drives a living clown through the maze: hunts the player, closes in to hit,
## or (for gunmen) stops in sight of the player and shoots.

const LAYER_WORLD := 1

@export var move_speed := 3.0
## Speed when it has the player in sight and breaks into a run.
@export var run_speed := 5.4
## Seconds it can keep a run up, and the breather it then needs.
@export var run_burst := 3.5
@export var run_rest := 1.4
## False: never breaks into a run or lunges (the Klappersoldat).
@export var can_run := true
## Melee swing: its length, when in it the blow lands, and the wait after.
@export var attack_time := 0.55
@export var attack_hit_at := 0.3
@export var attack_recover := 0.95
## Multiplies every step the body takes (a clockwork gait surges and stops).
var speed_scale := 1.0
## A crossbow bolt: pinned to a wall (cannot move or turn), an arm put out of
## use for a moment, a leg slowed for a while.
var pinned := false
var _arm_out_t := 0.0
var _slow := 1.0
var _slow_t := 0.0
## How fast it meant to move on its last step, before speed_scale (m/s).
var intended_speed := 0.0
## Which way it meant to go on its last step (flat, unit; zero when not moving).
var intended_dir := Vector3.ZERO
## Only ever walks along the maze's axes: north, south, east or west. It keeps
## to one axis (sidestepping a little to stay on line) until the way it wants
## to go is mostly across it, then switches. The Klappersoldat.
var axis_moves := false
var _axis_x := true
var _axis_pushing := 0.0
## Range a gunman tries to hold.
@export var keep_distance := 6.5
@export var weave_rate := 2.0
@export var melee_range := 1.35
@export var melee_damage := 10.0
@export var gun_damage := 7.0
@export var gun_range := 15.0
## Seconds spent lining up a shot, and the wait between shots.
@export var aim_time := 0.65
@export var shot_gap := Vector2(1.0, 1.7)
## Hit chance at point blank, how much it falls per metre, and the floor.
@export var accuracy := Vector3(0.7, 0.03, 0.2)
## How far it can see, and how wide (degrees either side of straight ahead).
@export var sight_range := 16.0
@export var sight_half_angle := 60.0
## Anything this close is noticed whichever way the clown is facing.
@export var sense_range := 2.2
## How many corridor cells away a gunshot is heard (pistol; the shotgun carries one more).
@export var hearing_cells := 4
## How close another clown must be to notice this one being shot.
@export var witness_range := 7.0
## Seconds it keeps hunting after losing sight of the player before giving up.
@export var give_up_after := 7.0

enum Mind { IDLE, HUNT, SEARCH }
var mind := Mind.IDLE

## Became aware of the player (from IDLE or SEARCH). `firsthand`: it saw or was
## hit; otherwise it only heard it or was told.
signal alerted(where: Vector3, firsthand: bool)
## A battlefield duty (BattleDuty, the trench floors): while unaware it does
## that instead of wandering, and goes back to it after a search.
var duty: BattleDuty = null
## Seconds between looks for the player while unaware (0: every frame). Once
## hunting it looks every frame.
var perceive_every := 0.0
var _perceive_t := 0.0
var _fog: Node = null           # TrenchFog on a trench floor (fog banks), else none
var _seen_last := false

var clown: Clown
var maze: Maze
var player: FpsPlayer
var others: Array = []          # every living clown on the floor, for spacing

var _path: Array[Vector3] = []
var _repath := 0.0
var _attack_t := -1.0           # >= 0 while a melee swing is in progress
var _attack_hit := false
var _cooldown := 0.0
var _aim_t := -1.0              # >= 0 while lining up a shot
var _last_known := Vector3.ZERO  # where it last saw or heard the player
var _unseen := 0.0              # seconds since it last saw the player
var _notice := 0.0              # builds while the player is in view
var _react := 0.0               # startled pause before it gets moving
var _strafe_dir := 1.0
var _strafe_left := 0.0
var _strafe_vel := Vector3.ZERO     # eased, so a side-step starts and stops like a person
var _burst := 0.0
var _weave := 0.0
var _weave_offset := randf() * TAU
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _search_left := 0.0
## Riflemen fight from cover: duck behind something, pop out to a firing
## spot beside it, take one aimed shot, duck back.
var use_cover := false
var debug_cover := false
var _cover := Vector3.INF          # where it hides (floor point)
var _peek := Vector3.INF           # where it steps out to shoot from
var _cover_state := 0              # 0 none, 1 going to cover, 2 hiding, 3 peeking
var _cover_t := 0.0
var _cover_cooldown := 0.0
var _hide_for := 2.0
## No good arm left: it gives up fighting and hides (tests read it too).
var hiding := false
var hidden := false                  ## crouched in its hiding place
var _hide_to := Vector3.INF
var _hide_t := 0.0
## A machine gunner (the Rattlejack): once on aim it fires in bursts instead
## of single shots, then pauses; a pan of rounds, then a reload.
var lmg := false
## The officer (Zornhauptmann): slow, a pistol raised in plain sight, a sabre
## up close (the clown poses the swing and says whether it landed).
var is_officer := false
var aim_times := Vector2(0.8, 1.3)                ## officer: a fresh aim time per shot
var misses := 0                                   ## tests
@export var fire_rate := 9.0                      ## rounds a second in a burst
@export var burst_seconds := Vector2(0.8, 1.8)
@export var burst_pause := Vector2(1.5, 3.0)
@export var pan_rounds := 47                      ## a Lewis gun's pan
@export var reload_seconds := 3.5
var rounds := 47                                  ## left in the pan
var bursts := 0                                   ## tests
var shots_fired := 0                              ## tests
var rounds_fired := 0                             ## tests: every round at the player
var _lmg_t := 0.0                                 ## > 0 while a burst is going
var _lmg_acc := 0.0
var _backoff := -2.0              # > 0 while stepping back from a player too close; < 0 resting from it

# --- weight (the human soldiers: WitzSoldats of both looks, the officer, the
# gunner; not the clockwork men) ---------------------------------------------------
## Moves like a man carrying his kit: builds up speed, slows before stopping,
## cannot turn on the spot at any speed, reverses through a stop.
var weighty := false
const ACCEL_WALK := 3.2          ## m/s^2 picking up to a walk
const ACCEL_RUN := 4.0           ## ... to a run
const BRAKE := 6.0               ## m/s^2 slowing
const TURN_IDLE := 2.6           ## rad/s, turning on the spot (feet shuffling round)
const TURN_WALK := 3.4           ## rad/s at a walk
const TURN_RUN := 2.2            ## rad/s flat out (wide arcs)
const TURN_ACCEL := 14.0         ## rad/s^2: a turn starts and stops, it does not snap
var _vel := Vector3.ZERO         ## the body's actual way on (eased)
var _yaw_rate := 0.0
var _yaw_want := INF             ## where _face asked it to turn this frame
var _yaw_urgency := 1.0
var yaw_rate_max := 0.0          ## tests: the fastest it has turned
## How crouched it wants to be this frame (the states set it; applied once).
var crouch_want := 0.0
## Under fire: 0 calm .. 1.5 pinned down. Rises with near misses and hits,
## falls off over a few seconds.
var suppression := 0.0
var near_misses := 0             ## tests
var _near_t := 0.0
var _duck_t := 0.0               ## a flinching duck under a near miss
var _look_t := 0.0               ## idle glances
var _peeks := 0                  ## shots from this cover so far
var _peek_rise := false          ## this cover is low: rise up behind it to shoot
var _linger := 0.0               ## after a shot from cover: hold the aim a moment
var strafe_flips := 0            ## tests: changes of side-step direction
var backing := false              # test hook: stepping back this frame


func _ready() -> void:
	clown = get_parent() as Clown
	clown.always_pose = true
	clown.set_process(true)
	clown.hurt.connect(_on_hurt)
	_wander_to = Vector3.INF          # taken on the first frame, once it has been put in place
	weighty = clown.spec.get("soldier", false) and not axis_moves and clown.drive_phase
	_wander_wait = randf_range(0.5, 5.0)


# --- awareness ------------------------------------------------------------------
## Become aware of the player. `where` is the best guess at their position.
func alert(where: Vector3, startled: bool = true, firsthand: bool = true) -> void:
	_last_known = where
	# heard or told: it knows where to go, not where the player is now (it
	# hunts "blind" to that spot until it sees them for itself)
	_unseen = 0.0 if firsthand else maxf(_unseen, 1.6)
	if mind != Mind.HUNT:
		mind = Mind.HUNT
		_repath = 0.0
		if startled:
			_react = randf_range(0.25, 0.6)
		alerted.emit(where, firsthand)


## A gunshot went off at `where`. Heard if it is close enough along the corridors.
func hear(where: Vector3, extra_cells: int = 0) -> void:
	if clown.dead or mind == Mind.HUNT:
		return
	var cells := maze.path_cells(maze.cell_of(clown.global_position), maze.cell_of(where)) - 1
	if duty:
		extra_cells += duty.hearing_bonus()
	if cells <= maze.span(hearing_cells + extra_cells):
		alert(where, true, duty == null)


## This clown was shot: it knows, and so does any clown close enough to see it happen.
func _on_hurt(_c: Clown) -> void:
	if player == null:
		return
	if weighty:
		suppression = minf(suppression + 0.5, 1.5)
		if _aim_t > 0.0:
			_aim_t = minf(_aim_t, aim_time * 0.3)      # knocked off his aim
	if not clown.dead:
		alert(player.global_position, false)
	for o in others:
		if not is_instance_valid(o) or o == clown or o.dead:
			continue
		var b := o.get_node_or_null("Brain") as ClownBrain
		if b == null or b.mind == Mind.HUNT:
			continue
		if o.global_position.distance_to(clown.global_position) <= witness_range and _clear(o.global_position + Vector3.UP * 1.5, clown.global_position + Vector3.UP * 1.0):
			b.alert(player.global_position)


func _can_see_player() -> bool:
	var to := player.global_position - clown.global_position
	var dist := to.length()
	if dist > sight_range:
		return false
	if dist > sense_range:
		var facing := clown.global_basis.z
		var flat := Vector3(to.x, 0, to.z).normalized()
		if Vector3(facing.x, 0, facing.z).normalized().dot(flat) < cos(deg_to_rad(sight_half_angle)):
			return false
	# a fog bank between them hides the player from him as it hides him from
	# the player (only past a few metres: close by he can still make him out)
	if dist > 6.0:
		if _fog == null or not is_instance_valid(_fog):
			_fog = get_tree().get_first_node_in_group(&"fog")
		if _fog and _fog.visibility(clown.global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.5) < 0.3:
			return false
	return _sees_player()


func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return clown.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Unaware: shuffle about the nearby corridors, standing idle in between.
func _idle(delta: float) -> void:
	clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
	clown.attack_amount = 0.0
	if _wander_to == Vector3.INF or maze.cell_of(_wander_to) == maze.cell_of(_wander_to) and not maze.is_open(maze.cell_of(_wander_to)):
		_wander_to = clown.global_position    # (a brain added before its clown was placed must not walk "home" to the origin)
	var gap := Vector3(_wander_to.x - clown.global_position.x, 0, _wander_to.z - clown.global_position.z)
	if gap.length() < 0.3:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(2.0, 7.0)
			var here := maze.cell_of(clown.global_position)
			var options: Array[Vector2i] = []
			for dir in Maze.DIRS:
				if maze.in_bounds(here + dir) and maze.linked(here, here + dir):
					options.append(here + dir)
			if not options.is_empty():
				_wander_to = _free_spot(options.pick_random())
		_settle(delta)
		return
	var aim := _through_opening(_wander_to)
	var vel := Vector3(aim.x - clown.global_position.x, 0, aim.z - clown.global_position.z).normalized() * move_speed * 0.38
	if clown.spec.get("soldier", false):
		# turn to face the way before strolling off that way
		var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
		vel *= lerpf(0.1, 1.0, smoothstep(0.0, 0.8, facing.dot(vel.normalized())))
	_step(vel, delta)
	# Pressing on something it cannot get round: stop there and think again,
	# rather than walking into it for ever.
	_blocked_t = _blocked_t + delta if _was_blocked else maxf(_blocked_t - delta * 2.0, 0.0)
	if _blocked_t > 0.8:
		_blocked_t = 0.0
		_wander_to = clown.global_position
		_wander_wait = randf_range(0.5, 2.0)
	_face(vel, delta, 4.0)
	clown.walk_amount = move_toward(clown.walk_amount, 0.45, delta * 3.0)
	clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)


func pinned_now() -> void:
	pinned = true
	_path.clear()
	_attack_t = -1.0
	_aim_t = -1.0
	_strafe_vel = Vector3.ZERO
	_cover_state = 0
	hiding = false
	clown.crouch_amount = 0.0
	if player:
		alert(player.global_position, false)


func unpinned_now() -> void:
	pinned = false


func impair_arm(seconds: float) -> void:
	_arm_out_t = maxf(_arm_out_t, seconds)
	_aim_t = -1.0
	_attack_t = -1.0
	clown.aim_amount = 0.0
	clown.attack_amount = 0.0


func slow_for(scale: float, seconds: float) -> void:
	_slow = minf(_slow if _slow_t > 0.0 else 1.0, scale)
	_slow_t = maxf(_slow_t, seconds)


## Pinned: it stays where it is (the clown holds it at the pin) and fights what
## is in front of it: a swing at arm's length, a shot if it has a gun and the
## player is not behind it.
func _pinned(delta: float) -> void:
	# nothing to fight with and no wish to: it is busy with the bolt
	intended_speed = 0.0
	intended_dir = Vector3.ZERO
	clown.velocity = Vector3.ZERO
	clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 6.0)
	clown.run_amount = 0.0
	clown.aim_amount = 0.0
	clown.attack_amount = 0.0
	_attack_t = -1.0
	_aim_t = -1.0


func _physics_process(delta: float) -> void:
	if clown.dead:
		set_physics_process(false)
		return
	crouch_want = 1.0 if _cover_state == 2 else 0.0
	_think(delta)
	if clown.dead:
		return
	_after(delta)


## Once a frame after the thinking: the crouch it settled on, the turn it
## asked for (at a man's rate), where its eyes are, the fading of fright.
func _after(delta: float) -> void:
	suppression = maxf(suppression - delta * 0.18, 0.0)
	_near_t = maxf(_near_t - delta, 0.0)
	if _duck_t > 0.0:
		_duck_t -= delta
		crouch_want = maxf(crouch_want, 0.65)
	if weighty and suppression > 0.6 and mind == Mind.HUNT and _cover_state != 3 and not backing:
		crouch_want = maxf(crouch_want, 0.45)            # keeping his head down
	if not hiding and not pinned:
		clown.crouch_amount = move_toward(clown.crouch_amount, crouch_want, delta * (2.6 if crouch_want > clown.crouch_amount else 2.0))
	if weighty:
		_apply_turn(delta)
		_look(delta)
		# under fire this heavy he curls up behind the rifle, head down
		clown.cower = suppression > 0.8 and _cover_state != 3 and not pinned


func _think(delta: float) -> void:
	_cooldown -= delta
	_arm_out_t = maxf(_arm_out_t - delta, 0.0)
	_slow_t = maxf(_slow_t - delta, 0.0)
	if pinned:
		_pinned(delta)
		return
	_cover_cooldown -= delta
	if player == null or player.dead:
		_settle(delta)
		return

	if hiding:
		_hide(delta)
		return
	# Noticing: the player has to stay in view for a moment before it registers.
	var seen := false
	if perceive_every <= 0.0 or mind == Mind.HUNT:
		seen = _can_see_player()
	else:
		_perceive_t -= delta
		if _perceive_t <= 0.0:
			_perceive_t = perceive_every
			_seen_last = _can_see_player()
		seen = _seen_last
	if seen:
		_notice += delta
		if _notice > 0.3 or mind == Mind.HUNT:
			alert(player.global_position)
	else:
		_notice = maxf(_notice - delta, 0.0)
		_unseen += delta

	if mind == Mind.IDLE:
		if duty and duty.tick(delta):
			return
		_idle(delta)
		return
	if _react > 0.0:
		# Startled: turns toward the disturbance before it moves.
		_react -= delta
		_face(_last_known - clown.global_position, delta, 9.0)
		_settle(delta)
		return
	if mind == Mind.SEARCH:
		_search_left -= delta
		if _search_left <= 0.0:
			mind = Mind.IDLE
			_wander_to = clown.global_position
		else:
			_idle(delta)
		return
	# Hunting on old information: go to where the player was, then give up.
	var hunting_blind := _unseen > 1.5
	var goal := _last_known if hunting_blind else player.global_position
	if hunting_blind:
		var reached := Vector3(goal.x - clown.global_position.x, 0, goal.z - clown.global_position.z).length() < 1.0
		if _unseen > give_up_after or (reached and _unseen > 3.0):
			mind = Mind.SEARCH
			_search_left = randf_range(5.0, 9.0)
			_wander_to = clown.global_position
			_wander_wait = 0.0
			return
	var to_player := player.global_position - clown.global_position
	var flat := Vector3(to_player.x, 0, to_player.z)
	var dist := flat.length()

	# Knocked off its stride by a hit.
	if clown.stagger_time > 0.0:
		_attack_t = -1.0
		_aim_t = -1.0
		_settle(delta)
		return

	# A swing already under way plays out where it stands.
	if _attack_t >= 0.0:
		_attack_t += delta
		if is_officer:
			# he tracks you through the wind-up, then is committed: step aside
			if _attack_t < attack_hit_at - 0.2:
				_face(flat, delta, 5.0)
		else:
			_face(flat, delta, 6.0)
			clown.attack_amount = sin(clampf(_attack_t / attack_time, 0.0, 1.0) * PI)
		if not _attack_hit and _attack_t > attack_hit_at:
			_attack_hit = true
			if is_officer and clown.has_method("melee_hits"):
				var dmg: float = clown.melee_hits(player)
				if dmg > 0.0:
					player.take_damage(dmg, flat.normalized())
			elif dist < melee_range + 0.35 and absf(to_player.y) < 1.6:
				player.take_damage(melee_damage, flat.normalized())
		if _attack_t > attack_time:
			_attack_t = -1.0
			_cooldown = attack_recover
			clown.attack_amount = 0.0
		_settle(delta, false)
		return

	if dist < melee_range and absf(to_player.y) < 1.4 and _cooldown <= 0.0 and not hunting_blind and _arm_out_t <= 0.0:
		_attack_t = 0.0
		_attack_hit = false
		_settle(delta, false)
		return

	if use_cover and _cover_state != 0:
		if _cover_fight(delta, dist, seen, flat):
			return
	# Gunmen fight on the move: sidestep while lining up a shot, back off if the
	# player closes in, push up if they are too far to hit much.
	if clown.has_gun and dist < gun_range and dist > melee_range and seen and _arm_out_t <= 0.0:
		_face(flat, delta, 7.0)
		clown.aim_point = player.global_position + Vector3.UP * 1.3
		# Too close for a rifle. Get out: run for cover if there is some, or
		# lower the rifle and step back a few paces, then turn and shoot again.
		var close := dist < keep_distance * 0.6
		_backoff -= delta
		if close and _backoff < -1.2 and _cooldown <= 0.0 and not clown.cycling():
			if use_cover and _cover_cooldown <= 0.0 and dist > 3.0 and randf() < 0.6:
				_find_cover()
				if _cover_state == 1:
					_aim_t = -1.0
					return
			_backoff = randf_range(1.0, 1.8)
		backing = _backoff > 0.0 and close
		if backing:
			_aim_t = -1.0
			clown.aim_amount = move_toward(clown.aim_amount, 0.25, delta * 3.0)    # rifle down to low ready
		elif is_officer:
			# the pistol comes up only to shoot, slowly enough to see it coming
			clown.aim_amount = move_toward(clown.aim_amount, 1.0 if _aim_t >= 0.0 else 0.0, delta * (1.9 if _aim_t >= 0.0 else 1.4))
		else:
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 4.0)
		if lmg and _lmg_t > 0.0:
			_burst_step(delta, dist)
		if not backing and _aim_t < 0.0 and _cooldown <= 0.0 and not clown.cycling() and _lmg_t <= 0.0:
			_aim_t = 0.0
			if is_officer:
				aim_time = randf_range(aim_times.x, aim_times.y)
		if _aim_t >= 0.0:
			_aim_t += delta
			if lmg and _aim_t > aim_time and clown.aim_amount > 0.9:
				_aim_t = -1.0
				_lmg_t = randf_range(burst_seconds.x, burst_seconds.y)
				_lmg_acc = 1.0 / fire_rate              # the first round goes at once
				bursts += 1
				_burst_step(0.0, dist)
			elif _aim_t > aim_time * (1.0 + 0.5 * suppression) and clown.aim_amount > 0.9 and (not weighty or _muzzle_clear()):
				var landed := _fire(dist)
				_aim_t = -1.0
				_cooldown = randf_range(shot_gap.x, shot_gap.y)
				if not landed:
					misses += 1
					if clown.has_method("missed"):
						_cooldown += clown.missed()
				# after a shot in the open, a rifleman looks for something to get behind
				if use_cover and _cover_cooldown <= 0.0 and dist > 4.5 and randf() < 0.7:
					_find_cover()
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			var was := _strafe_dir
			if weighty:
				# a man holds his ground to shoot more often than he side-steps,
				# and keeps to a step once he has taken it
				_strafe_left = randf_range(2.5, 5.0)
				_strafe_dir = [-1.0, 1.0, 0.0, 0.0, 0.0].pick_random()
				if suppression > 0.3:
					_strafe_dir = 0.0
			else:
				_strafe_left = randf_range(1.4, 3.0)
				_strafe_dir = [-1.0, 1.0, 0.0, 0.0].pick_random()
			if was != 0.0 and _strafe_dir == -was:
				strafe_flips += 1
		var toward := flat.normalized()
		var side := Vector3(toward.z, 0, -toward.x) * _strafe_dir
		var want := side
		if backing:
			want = (side * 0.3 - toward).normalized()          # careful steps straight back
		elif close:
			want = side * 0.6                                   # holding ground to shoot
		elif dist > keep_distance * 1.6:
			want = (side * 0.5 + toward).normalized()          # too far: close up
		if want.length() > 0.05 and not _free(want):
			if weighty:
				_strafe_dir = 0.0                               # wall or ledge: stops there, stands and shoots
			else:
				_strafe_dir = -_strafe_dir                      # wall or ledge: go the other way
				strafe_flips += 1
			want = Vector3.ZERO
			if backing:
				_backoff = 0.0                                  # backed into a wall: stand and fight
		var gvel := want * move_speed * ((0.24 if backing else 0.27) if weighty else (0.27 if backing else 0.42))
		if weighty:
			_step(gvel, delta)                                  # (the weight eases it in and out)
		else:
			_strafe_vel = _strafe_vel.move_toward(gvel, delta * 2.5)
			gvel = _strafe_vel
			_step(gvel, delta)
		clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)
		clown.walk_amount = move_toward(clown.walk_amount, clampf(gvel.length() / move_speed, 0.0, 1.0), delta * 5.0)
		return
	_aim_t = -1.0
	if _lmg_t > 0.0:
		_lmg_t = 0.0                    # lost sight: the burst stops
		_cooldown = maxf(_cooldown, 0.6)
	backing = false
	clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)

	# Hunt. Head straight for the player when in the same or an open neighbouring
	# cell on the same level, otherwise follow the corridors.
	_repath -= delta
	if _repath <= 0.0:
		_repath = randf_range(0.35, 0.6)
		_path = maze.path(clown.global_position, goal)
	var target := goal
	var my_cell := maze.cell_of(clown.global_position)
	var his_cell := maze.cell_of(goal)
	var direct := my_cell == his_cell or (_path.size() <= 1 and maze.linked(my_cell, his_cell) and maze.level[maze.idx(my_cell)] == maze.level[maze.idx(his_cell)])
	if not direct and not _path.is_empty():
		target = _path[0]
		if Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z).length() < 0.35:
			_path.pop_front()
	var move := Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z)
	if move.length() > 0.05:
		move = move.normalized()
	# Runs when it has the player in sight (or only just lost them), in bursts:
	# it cannot sprint forever. Otherwise it stalks at a walk.
	_burst -= delta
	if _burst <= -run_rest:
		_burst = randf_range(run_burst * 0.7, run_burst * 1.3)
	var running := can_run and not hunting_blind and _burst > 0.0 and dist > 1.6
	# A melee clown charging down a straight line of fire jinks from side to side.
	if running and seen and not clown.has_gun and dist > 3.0:
		_weave += delta
		var jink := Vector3(move.z, 0, -move.x) * sin(_weave * weave_rate + _weave_offset) * 0.35
		if _free(jink.normalized()):
			move = (move + jink).normalized()
	# Keep a little room between clowns so they do not merge in a corridor.
	for o in others:
		if not is_instance_valid(o) or o == clown or o.dead:
			continue
		var away: Vector3 = clown.global_position - o.global_position
		away.y = 0.0
		if away.length() < 0.75 and away.length() > 0.01:
			move += away.normalized() * (0.75 - away.length()) * 2.0
	# Close enough to swing: hold ground instead of walking through the player.
	if dist < melee_range * 0.75 and absf(to_player.y) < 1.4:
		move = Vector3.ZERO
	var speed := run_speed if running else move_speed
	# The last couple of metres are a lunge.
	if can_run and not clown.has_gun and seen and dist < 2.8 and _cooldown <= 0.0:
		speed = run_speed * 1.25
	# Nobody runs backwards: when the way on swings round behind it, it turns
	# first and puts on speed as it comes round.
	if clown.spec.get("soldier", false) and move.length() > 0.05:
		var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
		speed *= lerpf(0.2, 1.0, smoothstep(-0.3, 0.6, facing.dot(move.normalized())))
	if weighty:
		# going to where he last heard or saw the player: the last few metres
		# careful, low, at a walk; under fire, low and slower
		if hunting_blind and Vector3(goal.x - clown.global_position.x, 0, goal.z - clown.global_position.z).length() < 6.0:
			crouch_want = maxf(crouch_want, 0.45)
			speed = minf(speed, move_speed * 0.5)
		if suppression > 0.6:
			crouch_want = maxf(crouch_want, 0.55)
			speed = minf(speed, move_speed * 0.6)
	var vel := move.limit_length(1.0) * speed
	_step(vel, delta)
	_face(vel, delta, 8.0)
	clown.run_amount = move_toward(clown.run_amount, 1.0 if speed > move_speed * 1.2 else 0.0, delta * 4.0)
	clown.walk_amount = move_toward(clown.walk_amount, clampf(vel.length() / move_speed, 0.0, 1.0), delta * 5.0)


# --- cover -------------------------------------------------------------------------
## Fight from cover. Returns true while it is handling this frame.
func _cover_fight(delta: float, dist: float, seen: bool, flat: Vector3) -> bool:
	var eye := player.global_position + Vector3.UP * 1.5
	# Too close, or the hiding place can be seen from where the player is now:
	# give it up and fight in the open.
	if dist < 4.0 or (_cover_state == 2 and _clear(eye, _cover + Vector3.UP * 0.95)):
		_drop_cover()
		return false
	_cover_t += delta
	match _cover_state:
		1:   # running for it
			if _go_to(_cover, delta, run_speed):
				_cover_state = 2
				_cover_t = 0.0
				_hide_for = randf_range(2.2, 4.5) * (1.0 + suppression) if weighty else randf_range(1.4, 2.8)
				_aim_t = -1.0
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
			return true
		2:   # crouched behind it, working the bolt
			_settle(delta)
			_face(flat, delta, 4.0)
			if weighty and suppression > 0.5:
				_cover_t = minf(_cover_t, _hide_for - 0.5)   # pinned down: stays down
			if _cover_t > _hide_for and _cooldown <= 0.0 and not clown.cycling():
				if weighty and _peeks >= randi_range(3, 5):
					_peeks = 0
					_drop_cover()                           # been shooting from here long enough: move
					_cover_cooldown = randf_range(1.0, 2.0)
					return false
				_cover_state = 3
				_cover_t = 0.0
				_linger = 0.0
			return true
		3:   # step out (or rise up behind low cover), aim, fire, hold a moment, back in
			_face(flat, delta, 8.0)
			clown.aim_point = player.global_position + Vector3.UP * 1.3
			if weighty:
				crouch_want = 0.0 if _peek_rise else 0.25
				clown.lean = _lean_side() * 0.8 if not _peek_rise else 0.0
			if not _peek_rise and not _go_to(_peek, delta, move_speed * (0.55 if weighty else 1.0)):
				clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
				return true
			if _peek_rise:
				_settle(delta, false)
			_face(flat, delta, 8.0)
			clown.aim_point = player.global_position + Vector3.UP * 1.3
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 5.0)
			if not seen:
				if _cover_t > 1.5:
					_drop_cover()                 # nothing to shoot at from here
					return false
				return true
			if _linger > 0.0:
				# the shot gone: holds the aim a moment, then ducks back
				_linger -= delta
				if _linger <= 0.0:
					_cover_state = 1
					_cover_t = 0.0
					clown.lean = 0.0
				return true
			if _aim_t < 0.0:
				_aim_t = 0.0
			_aim_t += delta
			if _aim_t > aim_time * 0.85 * (1.0 + 0.5 * suppression) and clown.aim_amount > 0.9 and not clown.cycling():
				if not _muzzle_clear():
					_aim_t = aim_time * 0.5               # the wall is in the way: edge out further / wait
					if not _peek_rise:
						_peek = _peek.lerp(_peek + (_peek - _cover).normalized() * 0.3, 0.5)
					return true
				_fire(dist)
				_peeks += 1
				_aim_t = -1.0
				_cooldown = randf_range(shot_gap.x, shot_gap.y)
				if weighty:
					_linger = randf_range(0.5, 1.1)
				else:
					_cover_state = 1                  # back in
					_cover_t = 0.0
			return true
	return false


func _drop_cover() -> void:
	_cover_state = 0
	_cover = Vector3.INF
	_peek = Vector3.INF
	_peeks = 0
	_peek_rise = false
	clown.lean = 0.0
	_cover_cooldown = randf_range(5.0, 9.0) if weighty else randf_range(3.0, 6.0)


## Which way he leans out to shoot from cover: toward the side his peek step
## takes him (round the corner), -1 left .. 1 right.
func _lean_side() -> float:
	if _peek == Vector3.INF or _cover == Vector3.INF or player == null:
		return 0.0
	var to_p := player.global_position - clown.global_position
	var right := Vector3(to_p.z, 0, -to_p.x).normalized()
	var out := _peek - _cover
	out.y = 0.0
	return clampf(out.normalized().dot(right) * -1.0, -1.0, 1.0)


## The muzzle has a clear line to the player (no firing through the wall he is
## leaning round).
func _muzzle_clear() -> bool:
	if player == null:
		return false
	return _clear(clown.muzzle_position(), player.global_position + Vector3.UP * 1.25)


## Look nearby (this cell and the next two along the corridors) for a spot
## the player cannot see a crouched head at, with a spot within a step or two
## from which it can see the player standing.
func _find_cover() -> void:
	var eye := player.global_position + Vector3.UP * 1.5
	var start := maze.cell_of(clown.global_position)
	var cells := {start: 0}
	var frontier := [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if cells[c] >= 2:
			continue
		for dir in Maze.DIRS:
			var n: Vector2i = c + dir
			if maze.in_bounds(n) and maze.linked(c, n) and not cells.has(n):
				cells[n] = cells[c] + 1
				frontier.append(n)
	var best := INF
	var offs := [Vector3.ZERO, Vector3(0.85, 0, 0.85), Vector3(-0.85, 0, 0.85), Vector3(0.85, 0, -0.85), Vector3(-0.85, 0, -0.85)]
	var steps := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for c: Vector2i in cells:
		var centre := maze.cell_center(c)
		for o: Vector3 in offs:
			var p := centre + o
			p.y = maze.floor_height(p)
			if p.distance_to(player.global_position) < 5.0:
				continue
			if _clear(eye, p + Vector3.UP * 0.95):
				continue                          # it would be seen crouching here
			# low cover (sandbags, a parapet): crouched he is hidden, standing he
			# can see over it: he rises up behind it to shoot
			if weighty and _clear(eye, p + Vector3.UP * 1.55) and p.distance_to(player.global_position) > 5.0:
				var score0 := clown.global_position.distance_to(p) + randf() * 0.5 - 0.6
				if score0 < best:
					best = score0
					_cover = p
					_peek = p
					_peek_rise = true
				continue
			for st: Vector3 in steps:
				var q := p + st * 1.0
				q.y = maze.floor_height(q)
				if absf(q.y - p.y) > 0.3 or not _clear(p + Vector3.UP * 0.9, q + Vector3.UP * 0.9):
					continue
				if not _clear(eye, q + Vector3.UP * 1.5):
					continue                      # no shot from there either
				var score := clown.global_position.distance_to(p) + randf() * 0.5
				if score < best:
					best = score
					_cover = p
					_peek = q
					_peek_rise = false
	if OS.is_debug_build() and debug_cover:
		print("find_cover: %d cells, found=%s" % [cells.size(), best < INF])
	if best < INF:
		_cover_state = 1
		_cover_t = 0.0


## Move toward `to` (by the corridors if need be). True once it is there.
func _go_to(to: Vector3, delta: float, speed: float) -> bool:
	var flat := Vector3(to.x - clown.global_position.x, 0, to.z - clown.global_position.z)
	if flat.length() < 0.2:
		_settle(delta, false)
		return true
	var target := to
	if maze.cell_of(to) != maze.cell_of(clown.global_position):
		var p := maze.path(clown.global_position, to)
		if p.size() > 1 or not _clear(clown.global_position + Vector3.UP * 0.9, to + Vector3.UP * 0.9):
			target = p[0] if not p.is_empty() else to
	target = _through_opening(target)
	target = _onto_bridge(target)
	var move := Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z)
	var dir := move.normalized()
	var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
	var face_player := _cover_state == 3 or (_cover_state == 1 and flat.length() < 1.6 and player != null)
	if face_player:
		# ducking back the step or two into cover: eyes on the player, rifle
		# coming down, stepping back and sideways at a walk
		speed = minf(speed, move_speed * (0.26 if facing.dot(dir) < -0.3 else 0.5))
		var pf := player.global_position - clown.global_position
		if _cover_state == 1:
			_face(Vector3(pf.x, 0, pf.z), delta, 6.0)
	else:
		# a soldier does not run backwards: turn toward where it is going
		# first, and only put on speed once it is facing that way
		_face(dir, delta, 10.0)
		var lined := smoothstep(0.2, 0.85, facing.dot(dir))
		if weighty:
			# a man rounds a traverse walking, turning as he goes; he only
			# all but stops for a real about-turn
			lined = smoothstep(-0.3, 0.75, facing.dot(dir))
			speed = lerpf(move_speed * 0.3, speed, lined)
		else:
			speed = lerpf(move_speed * 0.15, speed, lined)
	if weighty and clown.transit_state() == 2:
		# pulling up (the stop clip has the pace): on toward the spot
		_step(dir * maxf(clown.transit_speed, 0.01), delta)
		return false
	if weighty and _cover_state == 0 and not face_player and target == to and _vel.length() > 0.6 \
			and dir.dot(_vel.normalized()) > 0.9:
		# near enough that the stop clip, met now, ends on the spot: pull up
		var sd := clown.stop_distance(_vel.length())
		if sd > 0.0 and flat.length() <= sd + 0.1 and clown.begin_stop(_vel.length()):
			_step(dir * clown.transit_speed, delta)
			return false
	if weighty:
		# eases up as it comes in, so it stops on the spot instead of skidding in
		speed = minf(speed, sqrt(2.0 * BRAKE * 0.7 * flat.length()) + 0.25)
		if _cover_state == 1 and flat.length() < 5.0:
			# eases off coming up to it (he can brake 6 m/s/s), then the last
			# few metres crouched at a walk
			speed = minf(speed, move_speed * 0.6 + maxf(flat.length() - 2.5, 0.0) * 1.6)
			if flat.length() < 3.0:
				crouch_want = maxf(crouch_want, 0.7)
	var vel := dir * minf(speed, move.length() / maxf(delta, 0.001))
	_step(vel, delta)
	clown.run_amount = move_toward(clown.run_amount, 1.0 if speed > move_speed * 1.2 else 0.0, delta * 4.0)
	clown.walk_amount = move_toward(clown.walk_amount, clampf(vel.length() / move_speed, 0.0, 1.0), delta * 5.0)
	return false


## True if it can take a step that way: no wall in the way and no ledge to walk off.
func _free(dir: Vector3) -> bool:
	if dir.length() < 0.05:
		return true
	var from := clown.global_position + Vector3.UP * 0.9
	if not _clear(from, from + dir * 0.75):
		return false
	return absf(maze.floor_height(clown.global_position + dir * 0.6) - clown.global_position.y) < 0.35


## Every move a clown makes goes through here. It is swept as a capsule
## against the level (walls, pillars, crates, drums, tables) and slides along
## whatever it meets; near a staircase it is kept on the stair, out of the
## low strip beside it. (Clowns are not physics bodies; before this they
## could be steered into walls, sink out of sight, or wedge beside a stair.)
## How close two living clowns may stand, centre to centre.
const BODY_GAP := 0.6


## Living clowns are solid to each other: a step that would take this one into
## another stops at touching distance and slides round it, and two that already
## overlap (spawned together, shoved by a blast) ease apart, half each.
func _keep_apart(want: Vector3, delta: float) -> Vector3:
	var me := clown.global_position
	for o in others:
		if not is_instance_valid(o) or o == clown or o.dead:
			continue
		var op: Vector3 = (o as Node3D).global_position
		if absf(op.y - me.y) > 1.2:
			continue                      # on another level (a stair, a landing)
		var d := Vector3(me.x - op.x, 0.0, me.z - op.z)
		var l := d.length()
		if l > BODY_GAP + want.length() + 0.05:
			continue
		var out := d / l if l > 0.001 else Vector3(cos(get_instance_id()), 0, sin(get_instance_id()))
		if l < BODY_GAP:
			want += out * minf(BODY_GAP - l, 2.0 * delta) * 0.5
			l = BODY_GAP
		var toward := -want.dot(out)      # how much of this step heads into the other
		var room := l - BODY_GAP
		if toward > room:
			want += out * (toward - room)
	return want


func _step(vel: Vector3, delta: float) -> void:
	if weighty:
		# the way on changes no faster than a man can change it: up to speed,
		# down to a stop, through a stop to reverse
		var want := Vector3(vel.x, 0, vel.z)
		# Starting off and pulling up are motion-captured: while one plays he
		# goes at its pace, so his feet stay where the clip puts them.
		var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
		if clown.transit_state() == 0 and _vel.length() < 0.1 and want.length() > 0.3 \
				and want.normalized().dot(facing) > 0.85 and _cover_state == 0:
			clown.begin_start(want.length())
		elif clown.transit_state() == 0 and want.length() < 0.05 and _vel.length() > 0.6 \
				and _vel.normalized().dot(facing) > 0.85 and _cover_state == 0:
			clown.begin_stop(_vel.length())
		var tr := clown.transit_state()
		if tr == 1 and (want.length() < 0.05 or want.normalized().dot(facing) < 0.5):
			clown.end_transit()                      # stopped short, or turning off
			tr = 0
		elif tr == 2 and want.length() > 0.3:
			clown.end_transit()                      # moving on after all
			tr = 0
		if tr != 0:
			var way := want.normalized() if want.length() > 0.05 else (_vel.normalized() if _vel.length() > 0.01 else facing)
			_vel = way * clown.transit_speed
			vel = _vel
			want = _vel
		var rate := BRAKE
		if want.length() > _vel.length() + 0.01:
			rate = ACCEL_RUN if want.length() > move_speed * 1.15 else ACCEL_WALK
		if want.length() > 0.05 and _vel.length() > 0.05 and want.normalized().dot(_vel.normalized()) < -0.2:
			rate = BRAKE                              # doubling back: braking first
		elif want.length() > 0.05 and _vel.length() > 0.05:
			rate = maxf(rate, ACCEL_RUN)              # rounding a corner: the way on swings round
		_vel = _vel.move_toward(want, rate * delta)
		vel = _vel
	intended_speed = Vector2(vel.x, vel.z).length()
	if axis_moves and intended_speed > 0.01:
		var along := vel.x if _axis_x else vel.z
		var across := vel.z if _axis_x else vel.x
		# pressing into a wall along this axis (a corner to get round): try the other
		_axis_pushing = _axis_pushing + delta if _was_blocked else 0.0
		if absf(along) < absf(across) * 0.5 or (_axis_pushing > 0.4 and absf(across) > 0.05):
			_axis_pushing = 0.0
			_axis_x = not _axis_x
			var t := along
			along = across
			across = t
		var spd := intended_speed
		var step := signf(along) * spd
		var side := clampf(across, -0.3 * spd, 0.3 * spd)
		vel = Vector3(step, 0, side) if _axis_x else Vector3(side, 0, step)
		intended_dir = Vector3(signf(along), 0, 0) if _axis_x else Vector3(0, 0, signf(along))
	else:
		intended_dir = Vector3(vel.x, 0, vel.z).normalized() if intended_speed > 0.01 else Vector3.ZERO
	var want := Vector3(vel.x, 0.0, vel.z) * delta * speed_scale * (_slow if _slow_t > 0.0 else 1.0)
	want = _keep_apart(want, delta)
	var move := _collide(clown.global_position, want)
	if want.length() > 0.004:
		moves += 1
		_was_blocked = move.dot(want.normalized()) < want.length() * 0.4
		if _was_blocked:
			blocked += 1                  # pushing at something it should have gone round
	var free := clown.global_position + move
	var pos := maze.keep_walkable(free)
	var lifted := pos.distance_squared_to(free) > 1e-6    # put back onto a stair from beside it
	vel = Vector3(pos.x - clown.global_position.x, 0.0, pos.z - clown.global_position.z) / maxf(delta, 0.001)
	var floor_y := maze.floor_height(pos)
	# Never walk up a drop: ledges beside a staircase are a wall to a clown.
	# (Unless it is being put back onto the stair: then it climbs on.)
	if floor_y - clown.global_position.y > 0.45 and not lifted:
		# a ledge across the way: slide along it (one axis or the other) if
		# that is level, as it would along a wall, rather than stopping dead
		var here := clown.global_position
		pos = here
		floor_y = here.y
		vel = Vector3.ZERO
		for along: Vector3 in [Vector3(move.x, 0, 0), Vector3(0, 0, move.z)]:
			if along.length() < 0.002:
				continue
			var p2 := maze.keep_walkable(here + along)
			var f2 := maze.floor_height(p2)
			if f2 - here.y <= 0.45 and _collide(here, along).length() > along.length() * 0.8:
				pos = p2
				floor_y = f2
				vel = Vector3(p2.x - here.x, 0, p2.z - here.z) / maxf(delta, 0.001)
				break
	var new_y := floor_y if lifted else move_toward(clown.global_position.y, floor_y, delta * 6.0)
	clown.velocity = Vector3(vel.x, (new_y - clown.global_position.y) / maxf(delta, 0.001), vel.z)
	clown.global_position = Vector3(pos.x, new_y, pos.z)
	if weighty:
		# held up by something (a wall, a post, another man): loses its way on as
		# fast as it could brake, not all at once (sliding along a wall it keeps it)
		var got := Vector3(vel.x, 0, vel.z)
		# (never below a walking pace: a tiny first step can be swallowed by the
		# sweep's margin, and a man pushing off from a standstill must still go)
		if got.length() < _vel.length() * 0.5 and _vel.length() > 0.8:
			_vel = _vel.move_toward(got, BRAKE * delta)
			if _vel.length() < 0.8:
				_vel = _vel.normalized() * 0.8


func _settle(delta: float, drop_arm: bool = true) -> void:
	if weighty and (_vel.length() > 0.05 or clown.transit_state() == 2):
		# still carrying way: slows to a stop over a step or two
		_step(Vector3.ZERO, delta)
		clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 3.0)
		clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)
		if drop_arm:
			clown.attack_amount = 0.0
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
		return
	_vel = Vector3.ZERO
	intended_speed = 0.0
	intended_dir = Vector3.ZERO
	clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 5.0)
	clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 4.0)
	clown.velocity = Vector3.ZERO
	if drop_arm:
		clown.attack_amount = 0.0
		clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
	# standing still, but still solid: ease out of anyone it is standing inside
	var push := _keep_apart(Vector3.ZERO, delta)
	if push.length_squared() > 1e-8:
		clown.global_position = maze.keep_walkable(clown.global_position + _collide(clown.global_position, push))
	var floor_y := maze.floor_height(clown.global_position)
	clown.global_position.y = move_toward(clown.global_position.y, floor_y, delta * 6.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.05:
		return
	if weighty:
		# asked for; turned once a frame in _apply_turn, at a man's pace
		_yaw_want = atan2(dir.x, dir.z)
		_yaw_urgency = clampf(rate / 8.0, 0.5, 1.3)
		return
	clown.rotation.y = lerp_angle(clown.rotation.y, atan2(dir.x, dir.z), clampf(delta * rate, 0.0, 1.0))


## The turn: no faster than he can turn at this speed (on the spot, the feet
## shuffle him round; at a run he swings wide), building up and easing off.
func _apply_turn(delta: float) -> void:
	var want_rate := 0.0
	if _yaw_want != INF:
		var diff := wrapf(_yaw_want - clown.rotation.y, -PI, PI)
		var sp := _vel.length()
		var cap: float
		if sp < 0.4:
			cap = TURN_IDLE
		elif sp < move_speed * 1.15:
			cap = TURN_WALK
		else:
			cap = lerpf(TURN_WALK, TURN_RUN, clampf((sp - move_speed) / maxf(run_speed - move_speed, 0.1), 0.0, 1.0))
		cap *= _yaw_urgency
		want_rate = clampf(diff * 6.0, -cap, cap)
	_yaw_rate = move_toward(_yaw_rate, want_rate, TURN_ACCEL * delta)
	clown.rotation.y = wrapf(clown.rotation.y + _yaw_rate * delta, -PI, PI)
	clown.turn_rate = _yaw_rate
	clown.turn_goal = wrapf(_yaw_want - clown.rotation.y, -PI, PI) if _yaw_want != INF else 0.0
	yaw_rate_max = maxf(yaw_rate_max, absf(_yaw_rate))
	_yaw_want = INF


## Where his eyes are: on the player when he is fighting, on a sound he has
## just heard (the head goes first; the body comes round after), and now and
## then, standing about, a glance off at something.
func _look(delta: float) -> void:
	if mind == Mind.HUNT and player and _unseen < 1.0:
		clown.look_at_point(player.global_position + Vector3.UP * 1.5, 1.0)
	elif mind == Mind.HUNT or _react > 0.0:
		clown.look_at_point(_last_known + Vector3.UP * 1.4, 1.0)
	else:
		_look_t -= delta
		if _look_t <= 0.0:
			if clown.look_weight_want > 0.0:
				clown.look_at_point(Vector3.INF, 0.0)
				_look_t = randf_range(3.0, 8.0)
			else:
				var a := clown.rotation.y + randf_range(-1.5, 1.5)
				var at := clown.global_position + Vector3(sin(a), 0, cos(a)) * randf_range(6.0, 30.0) + Vector3.UP * randf_range(0.8, 2.4)
				clown.look_at_point(at, 0.8)
				_look_t = randf_range(1.2, 3.0)


## A round went close by him (FpsPlayer tells every soldier near the line of a
## shot): he flinches and ducks, his aim breaks, he looks for where it came
## from, and enough of them keep his head down (suppression). Only close ones
## count, and not more than about one a second.
func near_miss(from: Vector3, closest: float, passed := Vector3.INF) -> void:
	if not weighty or clown.dead or _near_t > 0.0:
		return
	_near_t = randf_range(0.5, 0.9)
	near_misses += 1
	var power := clampf(1.2 - closest, 0.3, 1.0)
	suppression = minf(suppression + 0.3 * power + 0.1, 1.5)
	# a man standing his ground jinks down and away from it (the motion-captured
	# dodge); anyone else ducks into a crouch
	var dodged := false
	if passed != Vector3.INF and clown.crouch_amount < 0.3 and _vel.length() < 1.0:
		var side := (passed - clown.global_position).dot(clown.global_basis.x.normalized())
		dodged = clown.dodge(-1.0 if side > 0.0 else 1.0)
	if not dodged:
		_duck_t = randf_range(0.35, 0.7) * (0.6 + power)
	var away := (clown.global_position - from)
	away.y = 0.0
	clown.flinch_away(away.normalized(), 0.35 + 0.4 * power)
	if _aim_t > 0.0:
		_aim_t = minf(_aim_t, aim_time * 0.4)
	if mind != Mind.HUNT and player:
		alert(from, true, false)                 # he knows which way it came from, not where you are
	elif use_cover and _cover_state == 0 and suppression > 0.7 and _cover_cooldown <= 0.0 and player and clown.global_position.distance_to(player.global_position) > 4.5:
		_find_cover()


func _sees_player() -> bool:
	var from := clown.global_position + Vector3.UP * 1.5
	var to := player.global_position + Vector3.UP * 1.3
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return clown.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Back up on a broken leg: slow, no running, but still coming.
func limp() -> void:
	move_speed *= 0.38
	run_speed = move_speed
	run_burst = 0.0
	alert(player.global_position if player else clown.global_position, false)


## The club-carrying WitzSoldat: no gun, so it closes in and hits, harder and
## from a little further than a bare-handed clown, with a heavier swing.
func clubman() -> void:
	melee_damage = 20.0
	melee_range = 1.6
	attack_time = 0.7
	attack_hit_at = 0.42
	attack_recover = 1.1


## The rifle gone with an arm: a pistol in the good hand instead (shorter
## range, weaker, quicker), and no more fighting from cover.
func pistol_mode() -> void:
	use_cover = false
	_cover_state = 0
	gun_damage = 9.0
	gun_range = 16.0
	aim_time = 0.7
	shot_gap = Vector2(1.3, 2.0)
	accuracy = Vector3(0.6, 0.02, 0.2)
	keep_distance = 7.0


## Both arms broken or gone: it cannot fight, so it runs and hides where the
## player cannot see it, crouches there shaking, and runs again if found.
func start_hiding() -> void:
	hiding = true
	hidden = false
	_cover_state = 0
	_attack_t = -1.0
	_aim_t = -1.0
	_hide_to = Vector3.INF
	clown.attack_amount = 0.0
	clown.aim_amount = 0.0


func _hide(delta: float) -> void:
	_hide_t -= delta
	clown.attack_amount = 0.0
	clown.aim_amount = 0.0
	if player == null:
		_settle(delta)
		return
	var seen := _sees_player()
	var dist := clown.global_position.distance_to(player.global_position)
	# found (or nowhere picked yet): somewhere new, away and out of sight
	if _hide_to == Vector3.INF or (hidden and seen and dist < 7.0 and _hide_t <= 0.0):
		_pick_hiding_place()
		hidden = false
		_hide_t = 1.5
	if not hidden:
		var flat := Vector3(_hide_to.x - clown.global_position.x, 0, _hide_to.z - clown.global_position.z)
		if flat.length() < 0.35:
			hidden = true
		else:
			var target := _hide_to
			if maze.cell_of(_hide_to) != maze.cell_of(clown.global_position):
				var p := maze.path(clown.global_position, _hide_to)
				if not p.is_empty():
					target = p[0]
			target = _through_opening(target)
			var move := Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z).normalized()
			var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
			var speed := lerpf(move_speed * 0.2, run_speed if can_run else move_speed, smoothstep(0.2, 0.85, facing.dot(move)))
			var vel := move * speed
			_step(vel, delta)
			_face(vel, delta, 9.0)
			clown.run_amount = move_toward(clown.run_amount, 1.0 if speed > move_speed * 1.2 else 0.0, delta * 4.0)
			clown.walk_amount = move_toward(clown.walk_amount, clampf(vel.length() / move_speed, 0.0, 1.0), delta * 5.0)
			clown.crouch_amount = move_toward(clown.crouch_amount, 0.0, delta * 3.0)
			return
	# cowering: crouched, turned away, shaking
	_settle(delta, false)
	clown.crouch_amount = move_toward(clown.crouch_amount, 1.0, delta * 3.0)
	var away := clown.global_position - player.global_position
	_face(Vector3(away.x, 0, away.z), delta, 3.0)


## The best spot within a few cells that the player cannot see from where
## they stand, as far from them along the corridors as it can manage.
func _pick_hiding_place() -> void:
	var eye := player.global_position + Vector3.UP * 1.5
	var start := maze.cell_of(clown.global_position)
	var pc := maze.cell_of(player.global_position)
	var cells := {start: 0}
	var frontier := [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if cells[c] >= 4:
			continue
		for dir in Maze.DIRS:
			var n: Vector2i = c + dir
			if maze.in_bounds(n) and maze.linked(c, n) and not cells.has(n):
				cells[n] = cells[c] + 1
				frontier.append(n)
	var best := -INF
	_hide_to = clown.global_position
	for c: Vector2i in cells:
		var centre := maze.cell_center(c)
		for o: Vector3 in [Vector3.ZERO, Vector3(0.8, 0, 0.8), Vector3(-0.8, 0, 0.8), Vector3(0.8, 0, -0.8), Vector3(-0.8, 0, -0.8)]:
			var p := centre + o
			p.y = maze.floor_height(p)
			var unseen := not _clear(eye, p + Vector3.UP * 0.8)
			var score := float(maze.path_cells(pc, c)) * 1.0 + (6.0 if unseen else 0.0) - float(cells[c]) * 0.3 + randf() * 0.4
			if score > best:
				best = score
				_hide_to = p


## WitzSoldat settings: a bolt-action rifle. Slower to aim and to work the
## bolt, but it reaches further, hits more often and hurts a lot more.
func rifleman() -> void:
	use_cover = true
	gun_damage = 24.0
	gun_range = 24.0
	aim_time = 0.95
	shot_gap = Vector2(2.0, 2.6)
	accuracy = Vector3(0.85, 0.018, 0.35)
	keep_distance = 10.0
	sight_range = 22.0


## The officer: walks (never runs), keeps a middle distance, raises the
## pistol in plain sight and fires one accurate round every two or three
## seconds; a sabre for anyone who gets close (a long, readable swing).
func officer() -> void:
	is_officer = true
	use_cover = false
	can_run = false
	move_speed = 1.8
	run_speed = 1.8
	gun_damage = 14.0
	gun_range = 20.0
	aim_time = 1.0
	shot_gap = Vector2(1.1, 1.7)               # plus the aim: a shot every 2-3 s
	accuracy = Vector3(0.8, 0.012, 0.45)
	keep_distance = 5.5
	sight_range = 20.0
	melee_range = 1.8
	melee_damage = 28.0


## Settings for a machine gunner: holds its ground at middle range and
## hoses the corridor in bursts. Poor accuracy per round, so a burst is
## dangerous but not certain death.
func gunner() -> void:
	lmg = true
	use_cover = false
	gun_damage = 6.0
	gun_range = 20.0
	aim_time = 0.7
	accuracy = Vector3(0.36, 0.014, 0.08)
	keep_distance = 9.0
	sight_range = 20.0
	rounds = pan_rounds


## Rounds out at fire_rate while the burst lasts; an empty pan ends it and
## starts the reload. Then a pause before the next.
func _burst_step(delta: float, dist: float) -> void:
	_lmg_t -= delta
	_lmg_acc += delta
	var gap := 1.0 / fire_rate
	while _lmg_acc >= gap and rounds > 0:
		_lmg_acc -= gap
		_fire(dist)
		rounds -= 1
		shots_fired += 1
	if rounds <= 0:
		_lmg_t = 0.0
		rounds = pan_rounds
		clown.reload_t = reload_seconds
		_cooldown = reload_seconds + 0.3
		if clown.has_method("start_reload"):
			clown.start_reload()
	elif _lmg_t <= 0.0:
		_lmg_t = 0.0
		_cooldown = randf_range(burst_pause.x, burst_pause.y)


func _fire(dist: float) -> bool:
	rounds_fired += 1
	if debug_cover:
		print("fire at %.1fm" % dist)
	var from := clown.muzzle_position()
	clown.fired()
	var aim_at := player.global_position + Vector3.UP * 1.25
	# Further away, or a player on the move, is harder to hit.
	var chance := clampf(accuracy.x - dist * accuracy.y, accuracy.z, accuracy.x)
	if player.velocity.length() > 2.0:
		chance *= 0.6
	var hit := randf() < chance
	var end := aim_at if hit else aim_at + Vector3(randf_range(-0.7, 0.7), randf_range(-0.4, 0.6), randf_range(-0.7, 0.7))
	if hit:
		player.take_damage(gun_damage, (aim_at - from).normalized())
	_tracer(from, from + (end - from).normalized() * (dist + 2.0))
	return hit


func _tracer(from: Vector3, to: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clown.get_parent().add_child(mi)
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(mi.queue_free)


const BODY_RADIUS := 0.28
const BODY_HEIGHT := 1.1           ## the capsule's bottom rides 0.38 m up: steps and kerbs pass under it
const BODY_LIFT := 0.38
static var _body_shape: CapsuleShape3D
var moves := 0                       ## steps it tried to take (tests)
var blocked := 0                     ## of those, steps that mostly ran into something
var _was_blocked := false
var _blocked_t := 0.0
var _detour_sign := 1.0
var _detour_t := 0.0


## How far `move` can go from `from` before the body hits the level, sliding
## along a wall rather than stopping dead; pushes out if it starts inside.
func _collide(from: Vector3, move: Vector3) -> Vector3:
	if move.length_squared() < 1e-8:
		return move
	if _body_shape == null:
		_body_shape = CapsuleShape3D.new()
		_body_shape.radius = BODY_RADIUS
		_body_shape.height = BODY_HEIGHT
	var space := clown.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _body_shape
	q.collision_mask = LAYER_WORLD
	q.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * (BODY_LIFT + BODY_HEIGHT * 0.5))
	# already overlapping something (spawned in a crate, a chair kicked into it):
	# let it move out, and nudge it along the way out
	var rest := space.get_rest_info(q)
	if not rest.is_empty():
		var n: Vector3 = rest.normal
		n.y = 0.0
		if n.length_squared() > 0.001:
			n = n.normalized()
			var into := move.dot(n)
			return (move - n * minf(into, 0.0)) + n * 0.02
		return move
	var best := Vector3.ZERO
	for m: Vector3 in [move, Vector3(move.x, 0, 0), Vector3(0, 0, move.z)]:
		if m.length_squared() < 1e-8:
			continue
		q.motion = m
		var r := space.cast_motion(q)
		var got := m * maxf(r[0] - 0.01, 0.0)
		if got.length_squared() > best.length_squared() + 1e-8:
			best = got
		if r[0] >= 1.0 and m == move:
			_detour_t = maxf(_detour_t - 0.05, 0.0)
			return move                    # clear: no need to try the slides
	# Square on to something (a pillar, a crate, a drum, a corner): angle
	# off to one side, and keep to that side for a moment so it does not
	# dither left and right.
	if best.length() < move.length() * 0.35:
		if _detour_t <= 0.0:
			_detour_sign = -_detour_sign
		_detour_t = 0.6
		for deg: float in [35.0, 70.0, 105.0]:
			var m := move.rotated(Vector3.UP, deg_to_rad(deg) * _detour_sign)
			q.motion = m
			var r := space.cast_motion(q)
			if r[0] > 0.5:
				return m * maxf(r[0] - 0.01, 0.0)
		_detour_sign = -_detour_sign      # that side is shut too: try the other next time
	return best


## Heading for a point in the next cell: if it is well off the middle of the
## opening, it lines up with the opening first (the doorways are framed by
## pillars, and a diagonal from a corner of the cell clips them).
func _through_opening(target: Vector3) -> Vector3:
	var here := maze.cell_of(clown.global_position)
	var there := maze.cell_of(target)
	var step := there - here
	if absi(step.x) + absi(step.y) != 1:
		return target                      # same cell, or not a neighbour: the path has already chosen
	var dv := Vector3(step.x, 0, step.y)
	var along := Vector3(-dv.z, 0, dv.x)
	var centre := maze.cell_center(here)
	var rel := clown.global_position - centre
	var off := rel.dot(along)
	var ahead := rel.dot(dv)
	var k := maze.scale()
	if absf(off) <= 0.45 * k or ahead > maze.cell * 0.5 - 0.35 * k:
		return target
	# a point on the middle line, short of the doorway
	return centre + dv * minf(ahead + 0.6 * k, maze.cell * 0.5 - 0.6 * k) + along * clampf(off, -0.3 * k, 0.3 * k)


## Going over a footbridge from the parapet beside its end: lines up on the
## deck first, then steps on, instead of cutting the corner at the trench lip
## (and being held at the edge there). Old: it came at the bridge on the
## diagonal; a man who swung wide at the corner stood at the lip for good.
func _onto_bridge(target: Vector3) -> Vector3:
	if not maze is TrenchMaze:
		return target
	var tm := maze as TrenchMaze
	var pos := clown.global_position
	if not tm.bridge_at(pos).is_empty():
		return target                      # on the deck already
	for br: Dictionary in tm.bridges:
		for i in 2:
			var e: Vector3 = br.a if i == 0 else br.b
			var o: Vector3 = br.b if i == 0 else br.a
			var into := Vector3(o.x - e.x, 0, o.z - e.z).normalized()
			var rel := Vector3(pos.x - e.x, 0, pos.z - e.z)
			if rel.length() > 2.5 or absf(pos.y - e.y) > 0.6 or rel.dot(into) > 0.7:
				continue
			if Vector3(target.x - e.x, 0, target.z - e.z).dot(into) < 0.5:
				continue                   # not going over it
			var side := Vector3(-into.z, 0, into.x)
			if absf(rel.dot(side)) < 0.25:
				return target              # lined up: straight on
			return e - into * 0.6 + side * clampf(rel.dot(side), -0.15, 0.15)
	return target


## A spot in a cell with room for a clown: the middle if it is clear, or
## near it (tables, beds and crates stand in the middle of some rooms).
func _free_spot(cell: Vector2i) -> Vector3:
	var centre := maze.cell_center(cell)
	if _body_shape == null:
		_body_shape = CapsuleShape3D.new()
		_body_shape.radius = BODY_RADIUS
		_body_shape.height = BODY_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _body_shape
	q.collision_mask = LAYER_WORLD
	var space := clown.get_world_3d().direct_space_state
	var offs: Array[Vector3] = [Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, 0.7), Vector3(0, 0, -0.7),
		Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, 0.7), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, -0.7)]
	offs.shuffle()
	offs.push_front(Vector3.ZERO)
	for i in offs.size():
		offs[i] *= maze.scale()
	for o: Vector3 in offs:
		var p := maze.keep_walkable(centre + o)
		p.y = maze.floor_height(p)
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (BODY_LIFT + BODY_HEIGHT * 0.5))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return centre
