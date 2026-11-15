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
	clown.gore._hang_guts(_anchor, _anchor.global_position, -_forward() + Vector3.DOWN * 0.3, 9)
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
		# hand over hand: the body lurches forward on each pull
		phase += delta * 3.4 * lerpf(0.45, 1.0, strength)
		surge = 0.35 + 0.65 * absf(cos(phase))
		var step := _forward() * speed * lerpf(0.3, 1.0, strength) * surge * delta
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


## Lay the torso down on its front and work the arms hand over hand.
func _pose(strength: float) -> void:
	var sk := clown.skeleton
	for bi: int in _rest:
		sk.set_bone_pose_rotation(bi, _rest[bi])
	var k := _fall * _fall * (3.0 - 2.0 * _fall)
	var drop := minf(_fall * 1.6, 1.0)
	var theta := PI * 0.5 * k
	var roll := sin(phase) * 0.06 * strength
	var model: Node3D = clown._model
	model.rotation = Vector3(theta, 0, roll)
	# keep the cut at the waist where it is, falling to the floor
	var waist_world := Vector3(0, lerpf(WAIST, 0.16, drop * drop), lerpf(0.0, -0.32, k))
	model.position = waist_world - model.basis * Vector3(0, WAIST, 0)
	var dying := clampf((0.25 - strength) / 0.25, 0.0, 1.0)
	var gasp := sin(t * 5.0) * 0.04 if _pause > 0.0 else 0.0
	# chest up off the floor, head lifted to see where it is going
	_turn("Spine", Vector3.RIGHT, -0.12 * k + gasp)
	_turn("Chest", Vector3.RIGHT, (-0.32 + 0.25 * dying) * k)
	_turn("Chest", Vector3.UP, 0.14 * sin(phase) * strength * k)
	_turn("Neck", Vector3.RIGHT, (-0.65 + 0.9 * dying) * k)
	_turn("Head", Vector3.RIGHT, (-0.2 + 0.2 * dying) * k)
	for s: float in [1.0, -1.0]:
		var side := "Left" if s > 0.0 else "Right"
		var ph := phase + (0.0 if s > 0.0 else PI)
		var reach := 0.5 + 0.5 * sin(ph)            # 1 = flung out ahead, 0 = pulled back under the shoulder
		var lifting := maxf(0.0, cos(ph))           # the hand comes up off the floor as it goes forward
		var ahead := lerpf(28.0, 92.0, reach) * lerpf(0.75, 1.0, strength)
		var down := lerpf(62.0, 38.0, reach) - lifting * 22.0 * strength
		ahead = lerpf(ahead, 70.0, dying)
		down = lerpf(down, 75.0, dying)
		_turn(side + "UpperArm", Vector3.BACK, deg_to_rad(ahead) * s * k + deg_to_rad(-76.0) * s * (1.0 - k))
		_turn(side + "UpperArm", Vector3.RIGHT, deg_to_rad(down) * k)
		var elbow := lerpf(78.0, 18.0, reach) * (1.0 - dying * 0.5)
		_bend(side + "LowerArm", deg_to_rad(elbow) * k)
		_bend(side + "Hand", deg_to_rad(25.0) * k)


func _turn(bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) > 0.0001:
		clown._turn(bone, axis, angle)


## Bend a forearm or hand towards the floor (the body's front).
func _bend(bone: String, angle: float) -> void:
	var sk := clown.skeleton
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var along := sk.get_bone_global_pose(i).basis.y.normalized()
	var axis := along.cross(Vector3.BACK)
	if axis.length() < 0.01:
		return
	_turn(bone, -axis.normalized(), angle)
