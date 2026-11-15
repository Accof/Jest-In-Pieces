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
## Range a gunman tries to hold.
@export var keep_distance := 6.5
@export var weave_rate := 3.2
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
var _burst := 0.0
var _weave := 0.0
var _weave_offset := randf() * TAU
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _search_left := 0.0


func _ready() -> void:
	clown = get_parent() as Clown
	clown.always_pose = true
	clown.set_process(true)
	clown.hurt.connect(_on_hurt)
	_wander_to = clown.global_position
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
	for o: Clown in others:
		if o == clown or not is_instance_valid(o) or o.dead:
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
				_wander_to = maze.cell_center(options.pick_random())
		_settle(delta)
		return
	var vel := gap.normalized() * move_speed * 0.38
	_step(vel, delta)
	_face(vel, delta, 4.0)
	clown.walk_amount = move_toward(clown.walk_amount, 0.45, delta * 3.0)
	clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)
	clown.walk_phase += delta * 4.2


func _physics_process(delta: float) -> void:
	if clown.dead:
		set_physics_process(false)
		return
	_cooldown -= delta
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
		clown.attack_amount = sin(clampf(_attack_t / 0.55, 0.0, 1.0) * PI)
		if not _attack_hit and _attack_t > 0.3:
			_attack_hit = true
			if dist < melee_range + 0.35 and absf(to_player.y) < 1.6:
				player.take_damage(melee_damage, flat.normalized())
		if _attack_t > 0.55:
			_attack_t = -1.0
			_cooldown = 0.95
			clown.attack_amount = 0.0
		_settle(delta, false)
		return

	if dist < melee_range and absf(to_player.y) < 1.4 and _cooldown <= 0.0 and not hunting_blind:
		_attack_t = 0.0
		_attack_hit = false
		_settle(delta, false)
		return

	# Gunmen fight on the move: sidestep while lining up a shot, back off if the
	# player closes in, push up if they are too far to hit much.
	if clown.has_gun and dist < gun_range and dist > melee_range and seen:
		_face(flat, delta, 7.0)
		clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 4.0)
		if _aim_t < 0.0 and _cooldown <= 0.0:
			_aim_t = 0.0
		if _aim_t >= 0.0:
			_aim_t += delta
			if _aim_t > aim_time:
				_fire(dist)
				_aim_t = -1.0
				_cooldown = randf_range(shot_gap.x, shot_gap.y)
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			_strafe_left = randf_range(0.7, 1.6)
			_strafe_dir = [-1.0, 1.0, 1.0, -1.0, 0.0].pick_random()
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
		var gvel := want * move_speed * 0.85
		_step(gvel, delta)
		clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 3.0)
		clown.walk_amount = move_toward(clown.walk_amount, clampf(gvel.length() / move_speed, 0.0, 1.0), delta * 5.0)
		clown.walk_phase += delta * 7.5
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
	var running := not hunting_blind and _burst > 0.0 and dist > 1.6
	# A melee clown charging down a straight line of fire jinks from side to side.
	if running and seen and not clown.has_gun and dist > 3.0:
		_weave += delta
		var jink := Vector3(move.z, 0, -move.x) * sin(_weave * weave_rate + _weave_offset) * 0.75
		if _free(jink.normalized()):
			move = (move + jink).normalized()
	# Keep a little room between clowns so they do not merge in a corridor.
	for o: Clown in others:
		if o == clown or not is_instance_valid(o) or o.dead:
			continue
		var away := clown.global_position - o.global_position
		away.y = 0.0
		if away.length() < 0.75 and away.length() > 0.01:
			move += away.normalized() * (0.75 - away.length()) * 2.0
	# Close enough to swing: hold ground instead of walking through the player.
	if dist < melee_range * 0.75 and absf(to_player.y) < 1.4:
		move = Vector3.ZERO
	var speed := run_speed if running else move_speed
	# The last couple of metres are a lunge.
	if not clown.has_gun and seen and dist < 2.8 and _cooldown <= 0.0:
		speed = run_speed * 1.25
	var vel := move.limit_length(1.0) * speed
	_step(vel, delta)
	_face(vel, delta, 8.0)
	clown.run_amount = move_toward(clown.run_amount, 1.0 if speed > move_speed * 1.2 else 0.0, delta * 4.0)
	clown.walk_amount = move_toward(clown.walk_amount, clampf(vel.length() / move_speed, 0.0, 1.0), delta * 5.0)
	clown.walk_phase += delta * (3.2 + speed * 1.6)


## True if it can take a step that way: no wall in the way and no ledge to walk off.
func _free(dir: Vector3) -> bool:
	if dir.length() < 0.05:
		return true
	var from := clown.global_position + Vector3.UP * 0.9
	if not _clear(from, from + dir * 0.75):
		return false
	return absf(maze.floor_height(clown.global_position + dir * 0.6) - clown.global_position.y) < 0.35


func _step(vel: Vector3, delta: float) -> void:
	var pos := clown.global_position + vel * delta
	var floor_y := maze.floor_height(pos)
	# Never walk up a drop: ledges beside a staircase are a wall to a clown.
	if floor_y - clown.global_position.y > 0.45:
		pos = clown.global_position
		floor_y = clown.global_position.y
		vel = Vector3.ZERO
	var new_y := move_toward(clown.global_position.y, floor_y, delta * 6.0)
	clown.velocity = Vector3(vel.x, (new_y - clown.global_position.y) / maxf(delta, 0.001), vel.z)
	clown.global_position = Vector3(pos.x, new_y, pos.z)


func _settle(delta: float, drop_arm: bool = true) -> void:
	clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 5.0)
	clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 4.0)
	clown.velocity = Vector3.ZERO
	if drop_arm:
		clown.attack_amount = 0.0
		clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
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


## WitzSoldat settings: a bolt-action rifle. Slower to aim and to work the
## bolt, but it reaches further, hits more often and hurts a lot more.
func rifleman() -> void:
	gun_damage = 24.0
	gun_range = 24.0
	aim_time = 0.95
	shot_gap = Vector2(2.0, 2.6)
	accuracy = Vector3(0.85, 0.018, 0.35)
	keep_distance = 10.0
	sight_range = 22.0


func _fire(dist: float) -> void:
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
