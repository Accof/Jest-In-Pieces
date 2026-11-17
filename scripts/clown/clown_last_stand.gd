class_name ClownLastStand
extends ClownCrawler
## Both legs broken: it is not getting up again. It drags itself away from
## the player on its arms (on one, slowly, if the other is broken; not at
## all with neither), legs trailing, smearing blood; finds a wall and hauls
## itself round to sit with its back against it, legs out in front at wrong
## angles. One that carried a gun pulls a pistol from its belt with its
## good hand and makes a last-ditch stand from there; one that did not
## swipes at you if you come within reach. It stays until it is finished off.

enum Phase { CRAWL, TO_WALL, SIT }

@export var crawl_for := Vector2(1.2, 2.2)     ## how far it drags itself away before looking for a wall (m)
@export var sit_seconds := 1.3                 ## hauling round onto its backside
@export var draw_after := 0.7                  ## seconds after sitting before the pistol comes out
@export var shot_gap := Vector2(1.3, 2.3)
@export var shot_damage := 7.0
@export var shot_range := 18.0
@export var accuracy := Vector2(0.55, 0.025)   ## chance to hit, minus this per metre
@export var swipe_damage := 6.0

var stage := Phase.CRAWL
var shooter := false
var shots := 0                                 ## tests
var sat := false                               ## tests: sitting against the wall
var wall_found := false

var _crawl_left := 2.5
var _crawl_t := 0.0
var _sit_t := 0.0
var _sit_at := Vector3.ZERO
var _sit_yaw := 0.0
var _crawl_yaw := 0.0
var _gun_out := false
var _shot_t := 1.0
var _swipe_t := 0.0
var _swing := 0.0
var _leg_rest := {}
const LEG_BONES := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]


func begin_last_stand(c: Clown, m: Maze, away: Vector3, gun: bool) -> void:
	clown = c
	maze = m
	shooter = gun
	var flat := Vector3(away.x, 0, away.z)
	_yaw = atan2(flat.x, flat.z) if flat.length() > 0.01 else c.rotation.y
	c.rotation = Vector3(0, _yaw, 0)
	_y = c.global_position.y
	var sk := c.skeleton
	for b: String in BONES:
		var bi := sk.find_bone(b)
		if bi >= 0:
			_rest[bi] = sk.get_bone_rest(bi).basis.get_rotation_quaternion()
	for b: String in LEG_BONES:
		var bi := sk.find_bone(b)
		if bi >= 0:
			_leg_rest[bi] = c._base_rot.get(bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion())
	_fall = 1.0                          # already on the floor
	_trail_from = _waist_point()
	_crawl_left = randf_range(crawl_for.x, crawl_for.y)
	_next_pause = randf_range(3.0, 6.0)
	life = INF
	c.died.connect(_on_died)
	if _arms() == 0:
		_find_wall()                     # cannot drag itself anywhere: it stays put
		_start_sitting(false)


## How many arms it can pull with.
func _arms() -> int:
	return int(not clown.arm_out("Left")) + int(not clown.arm_out("Right"))


func _physics_process(delta: float) -> void:
	if clown == null or not is_instance_valid(clown) or _dead:
		return
	t += delta
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	match stage:
		Phase.CRAWL, Phase.TO_WALL:
			_crawl_step(delta, player)
		Phase.SIT:
			_sit_step(delta, player)
	if maze:
		_y = move_toward(_y, maze.floor_height(clown.global_position), delta * 3.0)
		clown.global_position.y = _y
	clown.rotation = Vector3(0, _yaw, 0)


func _crawl_step(delta: float, player: Node3D) -> void:
	_crawl_t += delta
	var arms := _arms()
	if arms == 0:
		_start_sitting(false)
		return
	if stage == Phase.CRAWL:
		if maze and (not _has_target or Vector2(_target.x - clown.global_position.x, _target.z - clown.global_position.z).length() < 0.45):
			_pick_target(player)
		if _crawl_left <= 0.0 or _crawl_t > 5.0:
			if _find_wall():
				stage = Phase.TO_WALL
			else:
				_start_sitting(false)
				return
	var goal := _sit_at if stage == Phase.TO_WALL else _target
	var to := goal - clown.global_position
	to.y = 0.0
	if stage == Phase.TO_WALL and (to.length() < 0.2 or _crawl_t > 11.0):
		_start_sitting(true)
		return
	var moving := _pause <= 0.0
	var surge := 0.0
	if moving:
		_yaw = rotate_toward(_yaw, atan2(to.x, to.z), delta * 1.8)
		var v := speed * (1.0 if arms == 2 else 0.5)
		_cycle = fposmod(_cycle + delta * v * STANCE / STROKE, 1.0)
		phase = _cycle * TAU
		surge = 0.25
		for off: float in [0.0, 0.5]:
			var q := fposmod(_cycle + off, 1.0)
			if q < STANCE:
				surge = maxf(surge, 0.25 + 1.35 * sin(PI * q / STANCE))
		var step := _forward() * v * surge * delta
		if stage == Phase.TO_WALL:
			step = step.limit_length(to.length())
		var q2 := PhysicsRayQueryParameters3D.create(clown.global_position + Vector3.UP * 0.2, clown.global_position + Vector3.UP * 0.2 + _forward() * 0.6, 1)
		if clown.get_world_3d().direct_space_state.intersect_ray(q2).is_empty() or stage == Phase.TO_WALL:
			clown.global_position += step
			_crawl_left -= step.length()
	else:
		_pause = maxf(_pause - delta, 0.0)
	_next_pause -= delta
	if _next_pause <= 0.0:
		_pause = randf_range(0.8, 1.6)
		_next_pause = randf_range(4.0, 7.0)
		Blood.spawn_pool(_floor_at(_waist_point()), Vector3.UP, randf_range(0.2, 0.32), clown.mechanical)
	clown.velocity = _forward() * speed * surge if moving else Vector3.ZERO
	_trail()


## The nearest wall within a couple of metres, best one away from the player:
## where it will sit (with its back to it) and which way it will face.
func _find_wall() -> bool:
	var space := clown.get_world_3d().direct_space_state
	var from := clown.global_position + Vector3.UP * 0.35
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var best := INF
	for i in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 16.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 2.2, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.4:
			continue
		var dist := from.distance_to(hit.position)
		var score := dist
		if player:
			var to_p := player.global_position - clown.global_position
			to_p.y = 0.0
			if to_p.length() > 0.1:
				score += d.dot(to_p.normalized()) * 0.8      # rather away from the player
		if score < best:
			best = score
			var wall_n := Vector3(n.x, 0, n.z).normalized()
			_sit_at = Vector3(hit.position.x, clown.global_position.y, hit.position.z) + wall_n * 0.36
			_sit_yaw = atan2(wall_n.x, wall_n.z)              # facing out from the wall
	wall_found = best < INF
	return wall_found


func _start_sitting(at_wall: bool) -> void:
	stage = Phase.SIT
	_sit_t = 0.0
	_crawl_yaw = _yaw
	if not at_wall or not wall_found:
		_sit_yaw = _yaw + PI                                  # rolls over where it is
		_sit_at = clown.global_position
	clown.velocity = Vector3.ZERO


func _sit_step(delta: float, player: Node3D) -> void:
	_sit_t += delta
	var k := clampf(_sit_t / sit_seconds, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	_yaw = lerp_angle(_crawl_yaw, _sit_yaw, e)
	clown.global_position = clown.global_position.lerp(Vector3(_sit_at.x, clown.global_position.y, _sit_at.z), minf(delta * 4.0, 1.0))
	if k < 1.0:
		return
	sat = true
	if player == null or not is_instance_valid(player) or (player as Object).get("dead") == true:
		return
	var arm := clown.main_arm()
	var to := player.global_position - clown.global_position
	# a gun: out from the belt, then a shot every second or two while it can see you
	if shooter and arm != "":
		if not _gun_out and _sit_t > sit_seconds + draw_after:
			_gun_out = true
			if not clown.has_gun:
				clown.give_gun(arm)
			clown.play_sfx("bolt_close", clown.global_position + Vector3.UP * 0.6, -14.0, 1.6)
		if _gun_out:
			_shot_t -= delta
			if _shot_t <= 0.0:
				_shot_t = randf_range(shot_gap.x, shot_gap.y)
				if to.length() < shot_range and _sees(player):
					_shoot(player, to.length())
	elif arm != "":
		# no gun: a swipe at anything that comes close
		_swipe_t -= delta
		if to.length() < 1.4 and _swipe_t <= 0.0:
			_swipe_t = 1.5
			_swing = 1.0
			if player.has_method("take_damage"):
				player.take_damage(swipe_damage, Vector3(to.x, 0, to.z).normalized())
	_swing = maxf(_swing - delta * 3.0, 0.0)


func _sees(player: Node3D) -> bool:
	var from := clown.global_position + Vector3.UP * 0.75
	var q := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3.UP * 1.3, 1)
	return clown.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(player: Node3D, dist: float) -> void:
	shots += 1
	var from := clown.muzzle_position()
	clown.fired()
	var aim_at := player.global_position + Vector3.UP * 1.25
	var hit := randf() < clampf(accuracy.x - dist * accuracy.y, 0.1, accuracy.x)
	var end := aim_at if hit else aim_at + Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.7), randf_range(-0.8, 0.8))
	if hit and player.has_method("take_damage"):
		player.take_damage(shot_damage, (aim_at - from).normalized())
	var brain := clown.get_node_or_null("Brain")
	if brain and brain.has_method("_tracer"):
		brain._tracer(from, from + (end - from).normalized() * (dist + 2.0))


func _process(_delta: float) -> void:
	if _dead or clown == null or not is_instance_valid(clown):
		return
	if stage == Phase.SIT:
		_pose_sitting()
	else:
		_pose(1.0)
		_pose_legs(0.0)
		for side: String in ["Left", "Right"]:
			if clown.arm_out(side):
				clown.dangle_arm(side)        # dragged along limp beside it


## The legs, broken: lying flat they trail behind; sitting they stick out in
## front, knees and feet at wrong angles.
func _pose_legs(sit: float) -> void:
	var sk := clown.skeleton
	for bi: int in _leg_rest:
		sk.set_bone_pose_rotation(bi, _leg_rest[bi])
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		_turn(side + "UpperLeg", Vector3.RIGHT, -1.45 * sit)
		_turn(side + "UpperLeg", Vector3.BACK, (0.1 + 0.12 * sit) * s)
		_turn(side + "LowerLeg", Vector3.RIGHT, 0.35 * (1.0 - sit) + 0.12 * sit)
		_turn(side + "LowerLeg", Vector3.UP, 0.45 * s)
		_turn(side + "Foot", Vector3.RIGHT, 0.6)


## Sat against the wall: hips on the floor, back leaning on the wall, head
## lolling, the good arm in the lap or up with the pistol.
func _pose_sitting() -> void:
	var sk := clown.skeleton
	for bi: int in _rest:
		sk.set_bone_pose_rotation(bi, clown._base_rot.get(bi, _rest[bi]))
	var k := clampf(_sit_t / sit_seconds, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var model: Node3D = clown._model
	# from lying on its front, over and up onto its backside
	var hips_h := 0.97
	var prone_pos := Vector3(0, 0.16, -0.32) - Basis(Vector3.RIGHT, PI * 0.5) * Vector3(0, WAIST, 0)
	var sit_pos := Vector3(0, 0.2 - hips_h, 0.0)
	model.rotation = Vector3(PI * 0.5 * (1.0 - e), 0, 0)
	model.position = prone_pos.lerp(sit_pos, e)
	_pose_legs(e)
	var breath := sin(t * 2.2) * 0.02
	_turn("Spine", Vector3.RIGHT, (-0.22 + breath) * e)
	_turn("Chest", Vector3.RIGHT, -0.08 * e)
	_turn("Neck", Vector3.RIGHT, (0.38 + sin(t * 0.7) * 0.05) * e)
	_turn("Neck", Vector3.BACK, 0.15 * e)
	for side: String in ["Left", "Right"]:
		if clown.arm_out(side):
			clown.dangle_arm(side)
			continue
		_turn(side + "UpperArm", Vector3.RIGHT, -0.35 * e)
		_turn(side + "LowerArm", Vector3.RIGHT, -0.7 * e)
	var arm := clown.main_arm()
	if arm == "":
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if _gun_out and player:
		# the gun arm up, wavering, at the player
		var to_skel := sk.global_transform.affine_inverse()
		var target := to_skel * (player.global_position + Vector3.UP * 1.2) + Vector3(sin(t * 3.1), sin(t * 2.3), 0) * 0.05
		var ua := sk.find_bone(arm + "UpperArm")
		var la := sk.find_bone(arm + "LowerArm")
		var hb := sk.find_bone(arm + "Hand")
		sk.set_bone_pose_rotation(ua, clown._base_rot.get(ua, sk.get_bone_pose_rotation(ua)))
		sk.set_bone_pose_rotation(la, clown._base_rot.get(la, sk.get_bone_pose_rotation(la)))
		clown.aim_bone(ua, la, target)
		clown.aim_bone(la, hb, target)
	elif _swing > 0.0:
		_turn(arm + "UpperArm", Vector3.RIGHT, -1.4 * _swing)
