class_name ClownCrawler
extends Node
## What is left of a clown torn in half: a torso dragging itself along the floor
## on its hands, guts trailing, leaving a smear of blood. It crawls away from
## the player and bleeds out after `life` seconds, unless finished off first.

@export var life := 60.0
@export var speed := 0.55          ## metres per second at full strength

var clown: Clown
var maze: Maze
var t := 0.0
var phase := 0.0
var _fall := 0.0                   # 0..1 as the torso drops to the floor
var _yaw := 0.0
var _target := Vector3.ZERO
var _has_target := false
var _trail_from := Vector3.ZERO
var _pause := 0.0
var _next_pause := 6.0
var _anchor: AnimatableBody3D
var _rest := {}                    # bone index -> rest rotation
var _dead := false
var _after := 0.0
var _y := 0.0
var _cycle := 0.0                  # 0..1 per full stroke of both arms
var _hands := {}                   # side -> {pos, planted, from, to}
const STROKE := 0.42               # how far the body travels on one pull
const STANCE := 0.56               # part of the cycle a hand spends planted

const BONES := ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand"]
const WAIST := 0.95                # height of the cut on the standing body


func begin(c: Clown, m: Maze, dir: Vector3) -> void:
	clown = c
	maze = m
	var flat := Vector3(dir.x, 0, dir.z)
	_yaw = atan2(flat.x, flat.z) if flat.length() > 0.01 else clown.rotation.y
	clown.rotation = Vector3(0, _yaw, 0)
	_y = clown.global_position.y
	var sk := clown.skeleton
	for b: String in BONES:
		var bi := sk.find_bone(b)
		if bi >= 0:
			_rest[bi] = sk.get_bone_rest(bi).basis.get_rotation_quaternion()
	# the guts drag along behind on a body that follows the cut
	_anchor = AnimatableBody3D.new()
	_anchor.sync_to_physics = false
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.02
	cs.shape = sp
	cs.disabled = true
	_anchor.add_child(cs)
	clown.get_parent().add_child(_anchor)
	_anchor.global_position = _waist_point()
	clown.gore._hang_guts(_anchor, _anchor.global_position, -_forward() + Vector3.DOWN * 0.3, 9, true)
	_trail_from = _waist_point()
	clown.died.connect(_on_died)
	_next_pause = randf_range(4.0, 8.0)


func _forward() -> Vector3:
	return Vector3(sin(_yaw), 0, cos(_yaw))


## Where the torso ends, on the floor behind it.
func _waist_point() -> Vector3:
	return clown.global_position - _forward() * 0.32 + Vector3.UP * 0.1


func _on_died(_c: Clown) -> void:
	_dead = true


func _physics_process(delta: float) -> void:
	if clown == null or not is_instance_valid(clown):
		return
	if _dead:
		# keep the guts with the body as it goes limp, then let go
		_after += delta
		var hips: PhysicalBone3D = clown.ragdoll.bones.get(&"Hips")
		if hips and is_instance_valid(_anchor):
			_anchor.global_position = hips.global_position
		if _after > 4.0:
			set_physics_process(false)
		return
	t += delta
	var strength := clampf(1.0 - pow(t / life, 3.0), 0.0, 1.0)
	if t >= life:
		# the last of it runs out on the floor
		Blood.spawn_pool(_floor_at(_waist_point()), Vector3.UP, 0.9)
		clown.bleed_out()
		return
	_fall = minf(_fall + delta / 0.45, 1.0)

	# Where to: away from the player, a cell at a time.
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if maze and (not _has_target or Vector2(_target.x - clown.global_position.x, _target.z - clown.global_position.z).length() < 0.45):
		_pick_target(player)
	var moving := _fall >= 1.0 and _pause <= 0.0 and strength > 0.08
	var surge := 0.0
	if moving:
		var to := _target - clown.global_position if _has_target else _forward()
		var want := atan2(to.x, to.z)
		_yaw = rotate_toward(_yaw, want, delta * 1.6)
		# hand over hand: each planted hand hauls the body forward, hardest
		# halfway through the pull
		var v := speed * lerpf(0.3, 1.0, strength)
		_cycle = fposmod(_cycle + delta * v * STANCE / STROKE, 1.0)
		phase = _cycle * TAU
		surge = 0.25
		for off: float in [0.0, 0.5]:
			var q := fposmod(_cycle + off, 1.0)
			if q < STANCE:
				surge = maxf(surge, 0.25 + 1.35 * sin(PI * q / STANCE))
		var step := _forward() * v * surge * delta
		# never drag into a wall
		var q := PhysicsRayQueryParameters3D.create(clown.global_position + Vector3.UP * 0.2, clown.global_position + Vector3.UP * 0.2 + _forward() * 0.75, 1)
		if clown.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			clown.global_position += step
	else:
		_pause = maxf(_pause - delta, 0.0)
	# every so often it stops, gasping, and the blood pools under it
	_next_pause -= delta
	if _next_pause <= 0.0 and _fall >= 1.0:
		_pause = randf_range(1.2, 2.4) * lerpf(1.0, 2.0, 1.0 - strength)
		_next_pause = randf_range(5.0, 9.0)
		Blood.spawn_pool(_floor_at(_waist_point()), Vector3.UP, randf_range(0.3, 0.45))
	if maze:
		_y = move_toward(_y, maze.floor_height(clown.global_position), delta * 3.0)
		clown.global_position.y = _y
	clown.rotation = Vector3(0, _yaw, 0)
	clown.velocity = _forward() * speed * surge if moving else Vector3.ZERO
	_trail()
	if is_instance_valid(_anchor):
		_anchor.global_position = _waist_point()


func _process(_delta: float) -> void:
	if _dead or clown == null:
		return
	_pose(clampf(1.0 - pow(t / life, 3.0), 0.0, 1.0))


## A smear of blood behind the cut, laid down as it drags itself along.
func _trail() -> void:
	var w := _waist_point()
	var moved := w - _trail_from
	moved.y = 0.0
	if moved.length() < 0.16:
		return
	var floor_p := _floor_at(w - moved * 0.5)
	Blood.spawn_decal(floor_p, Vector3.UP, randf_range(0.34, 0.46), "streak", moved, 1.0, 1.5)
	if randf() < 0.5:
		Blood.add_droplet(w, Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)), randf_range(0.04, 0.08))
	_trail_from = w


func _floor_at(p: Vector3) -> Vector3:
	var y := maze.floor_height(p) if maze else p.y - 0.1
	return Vector3(p.x, y, p.z)


func _pick_target(player: Node3D) -> void:
	var here := maze.cell_of(clown.global_position)
	var pc := maze.cell_of(player.global_position) if player else here
	var best := here
	var best_score := float(maze.path_cells(pc, here))
	for dir in Maze.DIRS:
		var n := here + dir
		if not maze.in_bounds(n) or not maze.linked(here, n):
			continue
		var score := float(maze.path_cells(pc, n)) + randf() * 0.5
		if score > best_score:
			best_score = score
			best = n
	_target = maze.cell_center(best)        # a dead end: it stays in the middle of it
	_has_target = true


## Lay the torso down on its front. The arms reach out, plant a hand on the
## floor, and that hand stays put while the body is dragged up to it.
func _pose(strength: float) -> void:
	var sk := clown.skeleton
	for bi: int in _rest:
		sk.set_bone_pose_rotation(bi, _rest[bi])
	var k := _fall * _fall * (3.0 - 2.0 * _fall)
	var drop := minf(_fall * 1.6, 1.0)
	var theta := PI * 0.5 * k
	var dying := clampf((0.25 - strength) / 0.25, 0.0, 1.0)
	# which hand is pulling, and how hard (rolls the shoulders toward it)
	var pull_l := _pull(0.0)
	var pull_r := _pull(0.5)
	var roll := (pull_l - pull_r) * 0.07 * strength
	var model: Node3D = clown._model
	model.rotation = Vector3(theta, 0, roll)
	var waist_world := Vector3(0, lerpf(WAIST, 0.16, drop * drop), lerpf(0.0, -0.32, k))
	model.position = waist_world - model.basis * Vector3(0, WAIST, 0)
	var gasp := sin(t * 5.0) * 0.04 if _pause > 0.0 else 0.0
	# chest up off the floor on the arms, head lifted to see where it is going
	_turn("Spine", Vector3.RIGHT, (-0.1 + 0.08 * dying) * k + gasp)
	_turn("Chest", Vector3.RIGHT, (-0.22 + 0.2 * dying) * k)
	_turn("Chest", Vector3.UP, (pull_l - pull_r) * 0.16 * strength * k)
	_turn("Neck", Vector3.RIGHT, (-0.55 + 0.85 * dying) * k)
	_turn("Head", Vector3.RIGHT, (-0.25 + 0.25 * dying) * k)
	var to_skel := sk.global_transform.affine_inverse()
	for s: float in [1.0, -1.0]:
		var side := "Left" if s > 0.0 else "Right"
		var hand := _hand_target(side, s, 0.0 if s > 0.0 else 0.5, strength)
		_reach(side, to_skel * hand, to_skel * (hand + Vector3.UP * 0.5 + _side_dir(s) * 0.35 - _forward() * 0.15))


## How hard the arm at cycle offset `off` is pulling right now (0..1).
func _pull(off: float) -> float:
	var q := fposmod(_cycle + off, 1.0)
	return sin(PI * q / STANCE) if q < STANCE else 0.0


func _side_dir(s: float) -> Vector3:
	# the clown's left is +x in its own space, which lies along the floor
	return Vector3(cos(_yaw), 0, -sin(_yaw)) * s


func _shoulder_world(side: String) -> Vector3:
	var sk := clown.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin


## Where this hand should be on the floor right now: planted while it pulls,
## swung forward in an arc while the other hand pulls.
func _hand_target(side: String, s: float, off: float, strength: float) -> Vector3:
	var shoulder := _shoulder_world(side)
	var floor_y := (_floor_at(shoulder).y if maze else clown.global_position.y) + 0.03
	var ahead := shoulder + _forward() * 0.44 * lerpf(0.7, 1.0, strength) + _side_dir(s) * 0.16
	ahead.y = floor_y
	if not _hands.has(side):
		_hands[side] = {pos = ahead, planted = true, from = ahead, to = ahead}
	var h: Dictionary = _hands[side]
	var q := fposmod(_cycle + off, 1.0)
	if q < STANCE or _pause > 0.0 or _fall < 1.0:
		if not h.planted:
			h.planted = true
			h.pos = h.to
		if _fall < 1.0:
			h.pos = ahead                    # catching itself as it drops
		return h.pos
	# swing: lift off, reach past the shoulder, put it down ahead
	if h.planted:
		h.planted = false
		h.from = h.pos
	h.to = ahead
	var u := (q - STANCE) / (1.0 - STANCE)
	var e := u * u * (3.0 - 2.0 * u)
	var p: Vector3 = (h.from as Vector3).lerp(h.to, e) + Vector3.UP * sin(u * PI) * 0.14 * strength
	h.pos = p
	return p


## Two-bone reach: point the upper arm and forearm so the wrist lands on
## `target` (skeleton space), with the elbow bowed toward `pole`.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var sk := clown.skeleton
	var ua := sk.find_bone(side + "UpperArm")
	var la := sk.find_bone(side + "LowerArm")
	var hb := sk.find_bone(side + "Hand")
	if ua < 0 or la < 0 or hb < 0:
		return
	var s_pos := sk.get_bone_global_pose(ua).origin
	var e_pos := sk.get_bone_global_pose(la).origin
	var w_pos := sk.get_bone_global_pose(hb).origin
	var a := s_pos.distance_to(e_pos)
	var b := e_pos.distance_to(w_pos)
	var to_t := target - s_pos
	var d := clampf(to_t.length(), absf(a - b) + 0.01, (a + b) * 0.995)
	var dir := to_t.normalized()
	# elbow position from the law of cosines, in the plane facing the pole
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := (pole - s_pos) - dir * (pole - s_pos).dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.UP
	bend = bend.normalized()
	var elbow := s_pos + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	_aim(ua, la, elbow)
	_aim(la, hb, s_pos + dir * d)
	# hand flat on the floor, fingers forward
	var fwd_skel := sk.global_transform.basis.inverse() * _forward()
	var wrist := sk.get_bone_global_pose(hb).origin
	var kids := sk.get_bone_children(hb)
	if kids.size() > 0:
		_aim(hb, kids[0], wrist + fwd_skel.normalized() * 0.1)


## Rotate `bone` so its child sits in the direction of `target` (skeleton space).
func _aim(bone: int, child: int, target: Vector3) -> void:
	var sk := clown.skeleton
	var gp := sk.get_bone_global_pose(bone)
	var cur := sk.get_bone_global_pose(child).origin - gp.origin
	var want := target - gp.origin
	if cur.length() < 0.0001 or want.length() < 0.0001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	var wanted := Basis(q) * gp.basis
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (pg.inverse() * wanted).get_rotation_quaternion())


func _turn(bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) > 0.0001:
		clown._turn(bone, axis, angle)
