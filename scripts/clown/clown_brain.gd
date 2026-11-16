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


func _ready() -> void:
	clown = get_parent() as Clown
	clown.always_pose = true
	clown.set_process(true)
	clown.hurt.connect(_on_hurt)
	_wander_to = Vector3.INF          # taken on the first frame, once it has been put in place
	_wander_wait = randf_range(0.5, 5.0)


# --- awareness ------------------------------------------------------------------
## Become aware of the player. `where` is the best guess at their position.
func alert(where: Vector3, startled: bool = true) -> void:
	_last_known = where
	_unseen = 0.0
	if mind != Mind.HUNT:
		mind = Mind.HUNT
		_repath = 0.0
		if startled:
			_react = randf_range(0.25, 0.6)


## A gunshot went off at `where`. Heard if it is close enough along the corridors.
func hear(where: Vector3, extra_cells: int = 0) -> void:
	if clown.dead or mind == Mind.HUNT:
		return
	var cells := maze.path_cells(maze.cell_of(clown.global_position), maze.cell_of(where)) - 1
	if cells <= hearing_cells + extra_cells:
		alert(where)


## This clown was shot: it knows, and so does any clown close enough to see it happen.
func _on_hurt(_c: Clown) -> void:
	if player == null:
		return
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


func _physics_process(delta: float) -> void:
	if clown.dead:
		set_physics_process(false)
		return
	_cooldown -= delta
	_cover_cooldown -= delta
	clown.crouch_amount = move_toward(clown.crouch_amount, 1.0 if _cover_state == 2 else 0.0, delta * 3.5)
	if player == null or player.dead:
		_settle(delta)
		return

	# Noticing: the player has to stay in view for a moment before it registers.
	var seen := _can_see_player()
	if seen:
		_notice += delta
		if _notice > 0.3 or mind == Mind.HUNT:
			alert(player.global_position)
	else:
		_notice = maxf(_notice - delta, 0.0)
		_unseen += delta

	if mind == Mind.IDLE:
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
		_face(flat, delta, 6.0)
		clown.attack_amount = sin(clampf(_attack_t / attack_time, 0.0, 1.0) * PI)
		if not _attack_hit and _attack_t > attack_hit_at:
			_attack_hit = true
			if dist < melee_range + 0.35 and absf(to_player.y) < 1.6:
				player.take_damage(melee_damage, flat.normalized())
		if _attack_t > attack_time:
			_attack_t = -1.0
			_cooldown = attack_recover
			clown.attack_amount = 0.0
		_settle(delta, false)
		return

	if dist < melee_range and absf(to_player.y) < 1.4 and _cooldown <= 0.0 and not hunting_blind:
		_attack_t = 0.0
		_attack_hit = false
		_settle(delta, false)
		return

	if use_cover and _cover_state != 0:
		if _cover_fight(delta, dist, seen, flat):
			return
	# Gunmen fight on the move: sidestep while lining up a shot, back off if the
	# player closes in, push up if they are too far to hit much.
	if clown.has_gun and dist < gun_range and dist > melee_range and seen:
		_face(flat, delta, 7.0)
		clown.aim_point = player.global_position + Vector3.UP * 1.3
		clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 4.0)
		if _aim_t < 0.0 and _cooldown <= 0.0:
			_aim_t = 0.0
		if _aim_t >= 0.0:
			_aim_t += delta
			if _aim_t > aim_time:
				_fire(dist)
				_aim_t = -1.0
				_cooldown = randf_range(shot_gap.x, shot_gap.y)
				# after a shot in the open, a rifleman looks for something to get behind
				if use_cover and _cover_cooldown <= 0.0 and dist > 4.5 and randf() < 0.7:
					_find_cover()
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			_strafe_left = randf_range(1.4, 3.0)
			_strafe_dir = [-1.0, 1.0, 0.0, 0.0].pick_random()
		var toward := flat.normalized()
		var side := Vector3(toward.z, 0, -toward.x) * _strafe_dir
		var want := side
		if dist < keep_distance * 0.6:
			want = (side * 0.6 - toward).normalized()          # too close: give ground
		elif dist > keep_distance * 1.6:
			want = (side * 0.5 + toward).normalized()          # too far: close up
		if want.length() > 0.05 and not _free(want):
			_strafe_dir = -_strafe_dir                          # wall or ledge: go the other way
			want = Vector3.ZERO
		var gvel := want * move_speed * 0.42
		_strafe_vel = _strafe_vel.move_toward(gvel, delta * 2.5)
		gvel = _strafe_vel
		_step(gvel, delta)
		clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)
		clown.walk_amount = move_toward(clown.walk_amount, clampf(gvel.length() / move_speed, 0.0, 1.0), delta * 5.0)
		return
	_aim_t = -1.0
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
				_hide_for = randf_range(1.4, 2.8)
				_aim_t = -1.0
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
			return true
		2:   # crouched behind it, working the bolt
			_settle(delta)
			_face(flat, delta, 4.0)
			if _cover_t > _hide_for and _cooldown <= 0.0:
				_cover_state = 3
				_cover_t = 0.0
			return true
		3:   # step out, aim, fire, step back
			_face(flat, delta, 8.0)
			clown.aim_point = player.global_position + Vector3.UP * 1.3
			if not _go_to(_peek, delta, move_speed):
				clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
				return true
			_face(flat, delta, 8.0)
			clown.aim_point = player.global_position + Vector3.UP * 1.3
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 5.0)
			if not seen:
				if _cover_t > 1.5:
					_drop_cover()                 # nothing to shoot at from here
					return false
				return true
			if _aim_t < 0.0:
				_aim_t = 0.0
			_aim_t += delta
			if _aim_t > aim_time * 0.85:
				_fire(dist)
				_aim_t = -1.0
				_cooldown = randf_range(shot_gap.x, shot_gap.y)
				_cover_state = 1                  # back in
				_cover_t = 0.0
			return true
	return false


func _drop_cover() -> void:
	_cover_state = 0
	_cover = Vector3.INF
	_peek = Vector3.INF
	_cover_cooldown = randf_range(3.0, 6.0)


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
	var move := Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z)
	var vel := move.normalized() * minf(speed, move.length() / maxf(delta, 0.001))
	_step(vel, delta)
	if _cover_state != 3:
		_face(vel, delta, 8.0)
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
	var want := Vector3(vel.x, 0.0, vel.z) * delta * speed_scale
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
		pos = clown.global_position
		floor_y = clown.global_position.y
		vel = Vector3.ZERO
	var new_y := floor_y if lifted else move_toward(clown.global_position.y, floor_y, delta * 6.0)
	clown.velocity = Vector3(vel.x, (new_y - clown.global_position.y) / maxf(delta, 0.001), vel.z)
	clown.global_position = Vector3(pos.x, new_y, pos.z)


func _settle(delta: float, drop_arm: bool = true) -> void:
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
	clown.rotation.y = lerp_angle(clown.rotation.y, atan2(dir.x, dir.z), clampf(delta * rate, 0.0, 1.0))


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


func _fire(dist: float) -> void:
	if debug_cover:
		print("fire at %.1fm" % dist)
	var from := clown.muzzle_position()
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
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.5)
	flash.light_energy = 3.0
	flash.omni_range = 4.0
	clown.get_parent().add_child(flash)
	flash.global_position = from
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(mi.queue_free)
	t.timeout.connect(flash.queue_free)


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
	if absf(off) <= 0.45 or ahead > Maze.CELL * 0.5 - 0.35:
		return target
	# a point on the middle line, short of the doorway
	return centre + dv * minf(ahead + 0.6, Maze.CELL * 0.5 - 0.6) + along * clampf(off, -0.3, 0.3)


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
	for o: Vector3 in offs:
		var p := maze.keep_walkable(centre + o)
		p.y = maze.floor_height(p)
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (BODY_LIFT + BODY_HEIGHT * 0.5))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return centre
