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
@export var roll_seconds := 0.9                ## rolling over onto its back, facing the wall the whole time
@export var backup_speed := 0.32               ## m/s shuffling back on its arms until its back is against the wall
@export var settle_knees := 0.6                ## drawing its knees up once its back is to the wall
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
var _wall_hit := Vector3.ZERO                  # a point on the wall it will sit against
var _wall_n := Vector3.ZERO                    # out from that wall (flat)
var _square := false                           # crawled out to square up and is now heading straight in
var _hips_z := 0.0                             # hips along its length (crawl frame), shuffling back
var _wall_z := 0.0                             # the wall along its length (crawl frame)
var _push := 0.0                               # 0..1 cycle of the arm shoves
var _phase_t := 0.0                            # time in the current part of sitting
var _sit_part := 0                             # 0 rolling, 1 shuffling back, 2 knees up, 3 sat
var _sat_t := 0.0
var _b := 0.0                                  # how far it has sat up, eased
var _crawl_yaw := 0.0
var _gun_out := false
var _shot_t := 1.0
var _swipe_t := 0.0
var _swing := 0.0
var _leg_rest := {}
var _sit_from := {}                  # bone -> [rotation, position] as it stopped crawling
var _turned := false                 # the 180 is now in its yaw, not its model
var _lift := 0.0                     # raised this much to keep its legs out of the floor
const SIT_HIPS := 0.15
const PRONE_Z := -0.32               # hips along its length lying down (crawl frame)
const STOP_AT := 0.6                 # crawls in head first until its middle is this far from the wall
const BACK_OFF := 0.3                # hips this far from the wall, sat up against it
const REACH := 0.85                  # hips to the back of its head, leaning back as it sits               # hip height sitting
const HIPS_REST := 0.97              # hip height standing, in the model
const LEG_CLEAR := 0.06              # how far a knee or ankle (the middle of the limb) stays off the floor
const LEG_BONES := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]


## Seconds to ease out of the pose it was lying in into crawling.
@export var settle_seconds := 0.9
var _from_pose := {}                 # bone -> [rotation, position] it was lying in (crawl model space)
var _settle := 1.0                   # 0..1 through the ease from the ragdoll


func begin_last_stand(c: Clown, m: Maze, away: Vector3, gun: bool, lying: Array[Transform3D] = []) -> void:
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
	# the yaw that keeps its body roughly the way it was lying (head first),
	# so the ease out of the ragdoll is short, not a spin
	if not lying.is_empty():
		var sk2 := c.skeleton
		var hip: Vector3 = lying[sk2.find_bone("Hips")].origin
		var head: Vector3 = lying[sk2.find_bone("Neck")].origin
		var along := Vector3(head.x - hip.x, 0, head.z - hip.z)
		if along.length() > 0.2:
			_yaw = atan2(along.x, along.z)
			c.rotation = Vector3(0, _yaw, 0)
		_capture(lying)
	if _arms() == 0:
		_find_wall()                     # cannot drag itself anywhere: it stays put
		_start_sitting(false)


## Turn the ragdoll's world-space bones into bone poses under the crawl's
## model transform, to blend from.
func _capture(lying: Array[Transform3D]) -> void:
	var sk := clown.skeleton
	var model: Node3D = clown._model
	model.rotation = Vector3(PI * 0.5, 0, 0)
	model.position = Vector3(0, 0.16, -0.32) - model.basis * Vector3(0, WAIST, 0)
	var inv := sk.global_transform.affine_inverse()
	var g: Array[Transform3D] = []
	for i in lying.size():
		g.append(inv * lying[i])
	for i in lying.size():
		var p := sk.get_bone_parent(i)
		var local: Transform3D = g[p].affine_inverse() * g[i] if p >= 0 else g[i]
		_from_pose[i] = [local.basis.get_rotation_quaternion(), local.origin]
		# shown exactly as it lay, from this very frame
		sk.set_bone_pose_rotation(i, _from_pose[i][0])
		sk.set_bone_pose_position(i, _from_pose[i][1])
	_settle = 0.0
	_pause = settle_seconds                  # lies there a moment before it starts to drag itself


## Ease every bone from the pose it was lying in to the one just set.
func _blend_from_lying(delta: float) -> void:
	if _settle >= 1.0 or _from_pose.is_empty():
		return
	_settle = minf(_settle + delta / settle_seconds, 1.0)
	var e := _settle * _settle * (3.0 - 2.0 * _settle)
	var sk := clown.skeleton
	for i: int in _from_pose:
		var f: Array = _from_pose[i]
		sk.set_bone_pose_rotation(i, (f[0] as Quaternion).slerp(sk.get_bone_pose_rotation(i), e))
		sk.set_bone_pose_position(i, (f[1] as Vector3).lerp(sk.get_bone_pose_position(i), e))


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
	var goal := _target
	var heading_err := 0.0
	if stage == Phase.TO_WALL:
		# out to a spot square in front of the wall, then straight in at it,
		# head first, turned to face it squarely while still crawling
		var out := _wall_hit + _wall_n * 1.0
		var flat := out - clown.global_position
		flat.y = 0.0
		if not _square and (flat.length() < 0.3 or _crawl_t > 10.0):
			_square = true
		goal = out if not _square else clown.global_position - _wall_n
		if _square:
			heading_err = absf(angle_difference(_yaw, atan2(-_wall_n.x, -_wall_n.z)))
			if _wall_dist() <= STOP_AT + 0.01 and heading_err < 0.08:
				_start_sitting(true)
				return
			if _crawl_t > 15.0:
				_start_sitting(_wall_dist() < STOP_AT + 0.15)
				return
	var to := goal - clown.global_position
	to.y = 0.0
	var moving := _pause <= 0.0 or stage == Phase.TO_WALL

	var surge := 0.0
	if moving:
		_yaw = rotate_toward(_yaw, atan2(to.x, to.z), delta * 1.4)
		var v := speed * (1.0 if arms == 2 else 0.5)
		_cycle = fposmod(_cycle + delta * v * STANCE / STROKE, 1.0)
		phase = _cycle * TAU
		surge = 0.25
		for off: float in [0.0, 0.5]:
			var q := fposmod(_cycle + off, 1.0)
			if q < STANCE:
				surge = maxf(surge, 0.25 + 1.35 * sin(PI * q / STANCE))
		var step := _forward() * v * surge * delta
		if stage == Phase.TO_WALL and not _square:
			# turns rather than circling the spot it wants
			step *= clampf(cos(angle_difference(_yaw, atan2(to.x, to.z))), 0.0, 1.0)
		if stage == Phase.TO_WALL and _square:
			# turning on the spot until it faces the wall, then in no further than it should
			step *= clampf(1.0 - heading_err / 0.6, 0.0, 1.0)
			step = step.limit_length(maxf(_wall_dist() - STOP_AT, 0.0))
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
			_wall_n = Vector3(n.x, 0, n.z).normalized()
			_wall_hit = Vector3(hit.position.x, clown.global_position.y, hit.position.z)
	wall_found = best < INF
	return wall_found


## How far its middle (the clown's origin) is from the wall it is making for.
func _wall_dist() -> float:
	return (clown.global_position - _wall_hit).dot(_wall_n)


func _start_sitting(at_wall: bool) -> void:
	stage = Phase.SIT
	_sit_t = 0.0
	_phase_t = 0.0
	_sit_part = 0
	_crawl_yaw = _yaw
	clown.velocity = Vector3.ZERO
	_hips_z = PRONE_Z
	# the wall, along its length: it crawled in head first, square to it
	_wall_z = _wall_dist() if at_wall and wall_found else INF
	# the pose it is in now, to ease out of
	_sit_from.clear()
	var sk := clown.skeleton
	for i in sk.get_bone_count():
		_sit_from[i] = [sk.get_bone_pose_rotation(i), sk.get_bone_pose_position(i)]


## How far it has sat up (0 lying, 1 upright), from how close its hips are to
## the wall: the back of its head is against the wall from the moment it gets
## there, and slides up it as the hips come in.
func _sit_amount() -> float:
	if _sit_part >= 2:
		return 1.0
	if _wall_z == INF:
		return smoothstep(0.0, 1.0, _phase_t / 1.2) if _sit_part == 1 else 0.0
	var d := _wall_z - _hips_z
	var up := acos(clampf(d / REACH, 0.0, 1.0))                       # angle off the floor
	var end := acos(clampf(BACK_OFF / REACH, 0.0, 1.0))
	return clampf(up / end, 0.0, 1.0)


func _sit_step(delta: float, player: Node3D) -> void:
	_sit_t += delta
	_phase_t += delta
	match _sit_part:
		0:
			if _phase_t >= roll_seconds:
				_sit_part = 1
				_phase_t = 0.0
		1:
			# shoves itself back along the floor on its elbows, a heave at a time
			_push = fposmod(_push + delta * 1.3, 1.0)
			var heave := 0.35 + 1.3 * maxf(sin(TAU * _push), 0.0)
			var done := false
			if _wall_z == INF:
				done = _phase_t >= 1.2
			else:
				_hips_z = minf(_hips_z + backup_speed * heave * delta, _wall_z - BACK_OFF)
				done = _hips_z >= _wall_z - BACK_OFF - 0.001 or _phase_t > 6.0
			if done:
				_sit_part = 2
				_phase_t = 0.0
		2:
			if _phase_t >= settle_knees and _b >= 0.999:
				_sit_part = 3
				_phase_t = 0.0
	if _sit_part < 3:
		return
	if not sat:
		sat = true
		# its origin moves under its hips and its yaw takes the half-turn the
		# model made, so nothing on screen changes: it already faces out
		var hz := _hips_z if _wall_z != INF else PRONE_Z
		clown.global_position += clown.global_basis * Vector3(0, 0, hz)
		_y = clown.global_position.y
		_yaw = _crawl_yaw + PI
		clown.rotation = Vector3(0, _yaw, 0)
		_turned = true
	_sat_t += delta
	if player == null or not is_instance_valid(player) or (player as Object).get("dead") == true:
		return
	var arm := clown.main_arm()
	var to := player.global_position - clown.global_position
	# a gun: out from the belt, then a shot every second or two while it can see you
	if shooter and arm != "":
		if not _gun_out and _sat_t > draw_after:
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
	if _settle < 1.0:
		# every bone back to its rest first, so the target pose is complete
		var sk := clown.skeleton
		for i: int in _from_pose:
			sk.set_bone_pose_rotation(i, clown._base_rot.get(i, sk.get_bone_rest(i).basis.get_rotation_quaternion()))
			sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin)
	if stage == Phase.SIT:
		_pose_sitting()
	else:
		_pose(1.0)
		_pose_legs(0.0)
		for side: String in ["Left", "Right"]:
			if clown.arm_out(side):
				clown.dangle_arm(side)        # dragged along limp beside it
	_blend_from_lying(_delta)
	if stage != Phase.SIT:
		_keep_off_floor(_delta)


## The legs, broken: lying flat they trail behind; sitting they stick out in
## front, knees and feet at wrong angles.
func _pose_legs(sit: float, knees := 0.0) -> void:
	var sk := clown.skeleton
	for bi: int in _leg_rest:
		sk.set_bone_pose_rotation(bi, _leg_rest[bi])
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		_turn(side + "UpperLeg", Vector3.RIGHT, -1.45 * sit - 0.55 * knees)     # along the floor, then knees up
		_turn(side + "UpperLeg", Vector3.BACK, (0.1 + 0.12 * sit) * s)
		_turn(side + "LowerLeg", Vector3.RIGHT, 0.35 * (1.0 - sit) + 0.12 * sit + 0.98 * knees)
		_turn(side + "LowerLeg", Vector3.UP, 0.45 * s)
		_turn(side + "Foot", Vector3.RIGHT, 0.6)


## Rolling over onto its back where it lies (facing the wall all the time),
## shoving itself back on its elbows until its head meets the wall and its
## back slides up it, then knees drawn up; then sat there, head lolling, the
## good arm in its lap or up with the pistol. Hip flexion is exactly how far
## the body has sat up, so the legs stay along the floor.
func _pose_sitting() -> void:
	var sk := clown.skeleton
	var dt := get_process_delta_time()
	var a := smoothstep(0.0, 1.0, clampf(_phase_t / roll_seconds, 0.0, 1.0)) if _sit_part == 0 else 1.0     # the roll
	_b = move_toward(_b, _sit_amount(), dt * 1.5)
	var b := _b                                                                                            # sitting up
	var k := 0.0                                                                                           # knees up
	if _sit_part == 2:
		k = smoothstep(0.0, 1.0, minf(_phase_t / settle_knees, _b))
	elif _sit_part >= 3:
		k = 1.0
	# every bone from its idle pose
	for i in sk.get_bone_count():
		sk.set_bone_pose_rotation(i, clown._base_rot.get(i, sk.get_bone_rest(i).basis.get_rotation_quaternion()))
		sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin)
	# the body, in the frame it crawled in (it never turns): face down ->
	# over onto its back round its own spine -> pitched up about the hips
	var model: Node3D = clown._model
	var basis: Basis
	var hips: Vector3
	if _turned:
		basis = Basis.IDENTITY
		hips = Vector3(0, SIT_HIPS, 0)
	else:
		if _sit_part == 0:
			basis = Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * a)
		else:
			basis = Basis(Vector3.RIGHT, PI * 0.5 * (1.0 - b)) * Basis(Vector3.UP, PI)
		hips = Vector3(0, lerpf(0.16, SIT_HIPS, b) + 0.04 * sin(PI * a) * float(_sit_part == 0), _hips_z if _wall_z != INF else PRONE_Z)
	model.basis = basis
	model.position = hips - basis * Vector3(0, HIPS_REST, 0)
	# legs: straight while it rolls, along the floor as it slides up the wall,
	# then knees drawn up
	_pose_legs(b, k)
	if _sit_part == 0:
		for side: String in ["Left", "Right"]:
			_turn(side + "LowerLeg", Vector3.RIGHT, -0.28 * a)       # straightens as it rolls, so the knee doesn't swing up
	var breath := sin(t * 2.2) * 0.02
	_turn("Spine", Vector3.RIGHT, (-0.22 + breath) * b)
	_turn("Chest", Vector3.RIGHT, -0.08 * b)
	_turn("Neck", Vector3.RIGHT, (0.38 + sin(t * 0.7) * 0.05) * b)
	_turn("Neck", Vector3.BACK, 0.15 * b)
	# arms: out a little to roll, then elbows down shoving it back, then the lap
	var shove := maxf(sin(TAU * _push), 0.0) if _sit_part == 1 else 0.0
	var on_elbows := 0.0
	if _sit_part == 1:
		on_elbows = (1.0 - b) * smoothstep(0.0, 0.4, _phase_t)
	elif _sit_part == 2:
		on_elbows = 1.0 - b
	for side: String in ["Left", "Right"]:
		var sd := 1.0 if side == "Left" else -1.0
		if clown.arm_out(side):
			clown.dangle_arm(side)
			continue
		_turn(side + "UpperArm", Vector3.BACK, 0.3 * sd * sin(PI * a) * float(_sit_part == 0) + 0.25 * sd * on_elbows)
		_turn(side + "UpperArm", Vector3.RIGHT, -0.35 * b + (0.5 - 0.35 * shove) * on_elbows)
		_turn(side + "LowerArm", Vector3.RIGHT, -0.7 * b - (1.0 - 0.4 * shove) * on_elbows)
	var arm := clown.main_arm()
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if arm != "" and _gun_out and player:
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
	elif arm != "" and _swing > 0.0:
		_turn(arm + "UpperArm", Vector3.RIGHT, -1.4 * _swing)
	# out of the crawl pose it stopped in, over the first part of the roll
	var w := smoothstep(0.0, roll_seconds * 0.8, _sit_t)
	if w < 1.0:
		for i: int in _sit_from:
			var f: Array = _sit_from[i]
			sk.set_bone_pose_rotation(i, (f[0] as Quaternion).slerp(sk.get_bone_pose_rotation(i), w))
			sk.set_bone_pose_position(i, (f[1] as Vector3).lerp(sk.get_bone_pose_position(i), w))
	_keep_off_floor(dt)


## Nothing of the legs below the floor: if a knee, ankle or toe would go
## through it, the body is raised just enough (and eases back down when it
## can).
func _keep_off_floor(dt: float) -> void:
	var sk := clown.skeleton
	var model: Node3D = clown._model
	# (the pose has just put the model back where it belongs, so whatever is
	# found below the floor is measured from there)
	var floor_y := (maze.floor_height(clown.global_position) if maze else clown.global_position.y)
	var low := INF
	for bn: String in ["LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperLeg", "RightUpperLeg"]:
		var gp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn))
		low = minf(low, gp.origin.y - floor_y - LEG_CLEAR)
		if bn.ends_with("Foot"):
			low = minf(low, (gp.origin + gp.basis.y.normalized() * 0.13).y - floor_y - 0.03)      # the toes
	var need := maxf(-low, 0.0)
	_lift = maxf(need, move_toward(_lift, need, dt * 0.5))
	model.position.y += _lift
