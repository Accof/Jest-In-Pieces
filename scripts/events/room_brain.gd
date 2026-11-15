class_name RoomBrain
extends Node
## A simple mind for clowns inside event rooms, which are not part of the
## maze: open floors, straight lines. Modes:
##   "room"    - stands still until it sees or hears the player, then hunts
##   "charge"  - runs at `target`, weaving, then goes for the player
##   "rifle"   - runs from cover point to cover point toward `target`,
##               crouching to take shots at the player
##   "static"  - never moves; shoots if it has a gun

var clown: Clown
var player: FpsPlayer
var maze: Maze = null              # always null: kept for code that asks
var mode := "room"
var floor_y := 0.0
var target := Vector3.ZERO
var bounds := AABB()               # keeps it inside the room (if set)
var move_speed := 3.0
var run_speed := 5.0
var melee_range := 1.35
var melee_damage := 10.0
var gun_damage := 8.0
var shot_gap := Vector2(1.6, 2.4)
var accuracy := 0.45
var sight_range := 25.0
var hunting := false
var waypoints: Array[Vector3] = []  # rifle mode: cover points, far to near
var on_arrive: Callable            # charge mode: called once on reaching `target`
var _attack_t := -1.0
var _cooldown := 0.0
var _weave := randf() * TAU
var _wp := 0
var _hold := 0.0
var _arrived := false


func _ready() -> void:
	clown = get_parent()
	clown.always_pose = true
	clown.set_process(true)
	clown.hurt.connect(func(_c: Clown) -> void: alert(player.global_position if player else clown.global_position))


func alert(_where: Vector3, _startled := true) -> void:
	hunting = true


func hear(_where: Vector3, _extra := 0) -> void:
	hunting = true


func limp() -> void:
	move_speed *= 0.4
	run_speed = move_speed
	hunting = true


func _physics_process(delta: float) -> void:
	if clown.dead or player == null:
		set_physics_process(false)
		return
	_cooldown -= delta
	var to := player.global_position - clown.global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	if player.dead:
		_move(Vector3.ZERO, delta)
		return
	if mode == "static":
		_face(flat, delta, 5.0)
		if clown.has_gun:
			_shoot(dist, delta)
		_move(Vector3.ZERO, delta)
		return
	if mode == "room" and not hunting:
		if dist < sight_range and _sees():
			hunting = true
		_move(Vector3.ZERO, delta)
		return
	# a swing in progress
	if _attack_t >= 0.0:
		_attack_t += delta
		_face(flat, delta, 6.0)
		clown.attack_amount = sin(clampf(_attack_t / 0.55, 0.0, 1.0) * PI)
		if _attack_t > 0.3 and _attack_t - delta <= 0.3 and dist < melee_range + 0.35 and absf(to.y) < 1.6:
			player.take_damage(melee_damage, flat.normalized())
		if _attack_t > 0.55:
			_attack_t = -1.0
			_cooldown = 0.9
			clown.attack_amount = 0.0
		_move(Vector3.ZERO, delta)
		return
	if dist < melee_range and _cooldown <= 0.0 and absf(to.y) < 1.4:
		_attack_t = 0.0
		return
	var goal := player.global_position
	var speed := run_speed
	if mode == "charge" and not _arrived:
		goal = target
		var left := Vector3(target.x - clown.global_position.x, 0, target.z - clown.global_position.z)
		if left.length() < 0.6:
			_arrived = true
			if on_arrive.is_valid():
				on_arrive.call(clown)
	elif mode == "rifle" and _wp < waypoints.size():
		goal = waypoints[_wp]
		var left := Vector3(goal.x - clown.global_position.x, 0, goal.z - clown.global_position.z)
		if left.length() < 0.5:
			# in cover: crouch, take a shot or two, then on to the next
			clown.crouch_amount = move_toward(clown.crouch_amount, 0.7, delta * 3.0)
			_face(flat, delta, 6.0)
			clown.aim_point = player.global_position + Vector3.UP * 1.3
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
			_hold += delta
			_shoot(dist, delta)
			if _hold > randf_range(4.0, 6.0):
				_hold = 0.0
				_wp += 1
			_move(Vector3.ZERO, delta)
			return
		clown.crouch_amount = move_toward(clown.crouch_amount, 0.0, delta * 3.0)
		clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
	elif clown.has_gun and dist > 5.0 and dist < 22.0 and _sees():
		# a gunman in a room keeps its distance and shoots
		_face(flat, delta, 7.0)
		clown.aim_point = player.global_position + Vector3.UP * 1.3
		clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 4.0)
		_shoot(dist, delta)
		_move(Vector3.ZERO, delta)
		return
	var dir := Vector3(goal.x - clown.global_position.x, 0, goal.z - clown.global_position.z)
	if dir.length() > 0.05:
		dir = dir.normalized()
	if mode == "charge" and dist > 4.0:
		_weave += delta * 2.6
		dir = (dir + Vector3(dir.z, 0, -dir.x) * sin(_weave) * 0.45).normalized()
	if dist < melee_range * 0.8:
		dir = Vector3.ZERO
	_move(dir * speed, delta)
	_face(dir if dir.length() > 0.1 else flat, delta, 8.0)


func _move(vel: Vector3, delta: float) -> void:
	var p := clown.global_position + vel * delta
	if bounds.size != Vector3.ZERO:
		p.x = clampf(p.x, bounds.position.x, bounds.end.x)
		p.z = clampf(p.z, bounds.position.z, bounds.end.z)
	p.y = move_toward(clown.global_position.y, floor_y, delta * 5.0)
	clown.velocity = (p - clown.global_position) / maxf(delta, 0.001)
	clown.global_position = p
	clown.walk_amount = move_toward(clown.walk_amount, clampf(vel.length() / move_speed, 0.0, 1.0), delta * 5.0)
	clown.run_amount = move_toward(clown.run_amount, 1.0 if vel.length() > move_speed * 1.2 else 0.0, delta * 4.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.05:
		return
	clown.rotation.y = lerp_angle(clown.rotation.y, atan2(dir.x, dir.z), clampf(delta * rate, 0.0, 1.0))


func _sees() -> bool:
	var q := PhysicsRayQueryParameters3D.create(clown.global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.3, 1)
	return clown.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(dist: float, _delta: float) -> void:
	if _cooldown > 0.0 or not _sees():
		return
	_cooldown = randf_range(shot_gap.x, shot_gap.y)
	var from := clown.muzzle_position()
	var aim_at := player.global_position + Vector3.UP * 1.25
	var hit := randf() < clampf(accuracy - dist * 0.008, 0.12, accuracy)
	var end := aim_at if hit else aim_at + Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.7), randf_range(-0.8, 0.8))
	if hit:
		player.take_damage(gun_damage, (aim_at - from).normalized())
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(from + (end - from).normalized() * (dist + 2.0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	clown.get_parent().add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)
