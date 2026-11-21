class_name FieldSoldier
extends Node
## One of the men out in No Man's Land (TrenchField): holds a post (a shell
## hole, a wrecked sandbag post), kneels in its cover, comes up to aim and fire
## at the enemy line across the way, ducks when something lands near, dashes to
## other cover now and then, and sometimes goes back along the line into the
## mist. No brain, no maze: he walks the open ground by its height.

enum State { HOLD, MOVE, DUCK, LEAVE }

var field: TrenchField
var clown: Clown
var state := State.HOLD
var post: Dictionary = {}

# counters (tests)
var shots := 0
var moves := 0
var ducks := 0

var _t := 0.0
var _phase := 0          # HOLD: 0 down in cover, 1 coming up, 2 aiming, 3 the bolt, 4 standing still, looking
var _cycles := 0
var _shots_left := 0
var _aim_at := Vector3.ZERO
var _to := Vector3.ZERO
var _delay := 0.0
var _jog := false
var _weave := randf() * TAU
var _after_duck := State.HOLD
var _stuck := 0.0
var _speed := 0.0          # his way on, eased (he carries his weight like the trench men)
var _yaw_rate := 0.0


func _ready() -> void:
	_t = randf_range(0.5, 4.0)


## Make `p` his post and hold it.
func take(p: Dictionary) -> void:
	if not post.is_empty() and post.man == self:
		post.man = null
	post = p
	p.man = self
	state = State.HOLD
	_phase = 0
	_t = randf_range(1.0, 4.0)
	_cycles = randi_range(2, 4)


## Run (or jog) to post `p`, after `delay` seconds.
func go_to(p: Dictionary, delay := 0.0, dash := true) -> void:
	if not post.is_empty() and post.man == self:
		post.man = null
	post = p
	p.man = self
	_to = p.pos
	_delay = delay
	_jog = not dash
	state = State.MOVE
	_stuck = 0.0
	moves += 1


## Get down for a moment (a shell landed near, a round went by).
func duck(seconds: float) -> void:
	if clown == null or clown.dead or state == State.LEAVE:
		return
	if state != State.DUCK:
		_after_duck = State.MOVE if state == State.MOVE else State.HOLD
		_t = seconds
	else:
		_t = maxf(_t, seconds)
	state = State.DUCK
	ducks += 1


## Someone hit him or shot at him: down, and then off to other cover.
func shot_at() -> void:
	if clown == null or clown.dead:
		return
	duck(randf_range(0.8, 1.8))
	_after_duck = State.MOVE
	var p := field.post_near(clown.global_position, 5.0, 16.0)
	if not p.is_empty():
		if not post.is_empty() and post.man == self:
			post.man = null
		post = p
		p.man = self
		_to = p.pos
		_jog = false


func _physics_process(delta: float) -> void:
	if clown == null or clown.dead:
		if not post.is_empty() and post.get("man") == self:
			post.man = null
		set_physics_process(false)
		return
	_yaw_rate = move_toward(_yaw_rate, 0.0, 14.0 * delta)      # (unless he turns this frame)
	clown.turn_rate = _yaw_rate
	match state:
		State.HOLD:
			_hold(delta)
		State.MOVE:
			_move(delta, _to, 1.6 if _jog else 4.3)
		State.DUCK:
			_duck(delta)
		State.LEAVE:
			_move(delta, _to, 1.5)
	_ground(delta)


func _hold(delta: float) -> void:
	_speed = move_toward(_speed, 0.0, delta * 6.0)
	clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 4.0)
	clown.run_amount = move_toward(clown.run_amount, 0.0, delta * 4.0)
	_t -= delta
	match _phase:
		0:   # down in cover
			clown.crouch_amount = move_toward(clown.crouch_amount, 1.0, delta * 2.5)
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 3.0)
			_face(Vector3(0, 0, -1), delta, 2.0)
			if _t <= 0.0:
				_cycles -= 1
				if _cycles <= 0:
					_next()
					return
				if randf() < 0.22:
					_phase = 4                    # stands up and looks out, quite still
					_t = randf_range(4.0, 9.0)
					_aim_at = clown.global_position + Vector3(randf_range(-20, 20), 1.5, -60.0)
				else:
					_phase = 1
					_t = randf_range(0.5, 0.9)
					_shots_left = randi_range(1, 3)
					_aim_at = clown.global_position + Vector3(randf_range(-25.0, 25.0), randf_range(0.8, 2.0), -randf_range(70.0, 110.0))
		1, 2:  # up, aiming
			clown.crouch_amount = move_toward(clown.crouch_amount, 0.35 if post.get("kind", "") == "bags" else 0.0, delta * 2.5)
			_face(_aim_at - clown.global_position, delta, 4.0)
			clown.aim_amount = move_toward(clown.aim_amount, 1.0, delta * 3.0)
			clown.aim_point = _aim_at
			if _phase == 1 and _t <= 0.0:
				_phase = 2
				_t = randf_range(0.9, 2.6)
			elif _phase == 2 and _t <= 0.0:
				_fire()
				_phase = 3
				_t = 0.3 + clown.bolt_seconds + randf_range(0.1, 0.6)
		3:
			clown.aim_point = _aim_at
			if _t <= 0.0:
				_shots_left -= 1
				if _shots_left > 0:
					_phase = 2
					_t = randf_range(0.8, 2.2)
				else:
					_phase = 0
					_t = randf_range(2.5, 8.0)
		4:   # standing in the mist, looking out
			clown.crouch_amount = move_toward(clown.crouch_amount, 0.0, delta * 1.5)
			clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 2.0)
			_face(_aim_at - clown.global_position, delta, 0.8)
			if _t <= 0.0:
				_phase = 0
				_t = randf_range(2.0, 5.0)


## Done holding here: another post (most often), or back along the line.
func _next() -> void:
	if randf() < 0.12:
		state = State.LEAVE
		if not post.is_empty() and post.man == self:
			post.man = null
		var left := clown.global_position.x < field.maze.w * field.maze.cell * 0.5
		_to = Vector3(field._left_x - 8.0 if left else field._right_x + 8.0, 0, clown.global_position.z + randf_range(-6.0, 6.0))
		return
	var p := field.post_near(clown.global_position, 5.0, 18.0)
	if p.is_empty():
		take(post)
		return
	go_to(p, randf_range(0.0, 0.5), true)


func _move(delta: float, to: Vector3, speed: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		clown.crouch_amount = move_toward(clown.crouch_amount, 0.6, delta * 2.0)
		return
	var flat := Vector3(to.x - clown.global_position.x, 0, to.z - clown.global_position.z)
	var d := flat.length()
	if d < 0.35:
		if state == State.LEAVE:
			clown.queue_free()
			return
		take(post)
		return
	if state == State.LEAVE and field.player and clown.global_position.distance_to(field.player.global_position) > 55.0 and (clown.global_position.x < -30.0 or clown.global_position.x > field.maze.w * field.maze.cell + 30.0):
		clown.queue_free()                   # gone into the mist along the line
		return
	var dir := flat / d
	if speed > 3.0:
		# a dash: bent low, weaving a little
		_weave += delta * 2.3
		dir = (dir + dir.cross(Vector3.UP) * sin(_weave) * 0.25).normalized()
	clown.crouch_amount = move_toward(clown.crouch_amount, 0.25 if speed > 3.0 else 0.0, delta * 3.0)
	clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 4.0)
	_face(dir, delta, 7.0)
	var facing := Vector3(clown.global_basis.z.x, 0, clown.global_basis.z.z).normalized()
	var want_v := minf(speed * smoothstep(0.1, 0.8, facing.dot(dir)), sqrt(2.0 * 5.0 * d) + 0.3)
	_speed = move_toward(_speed, want_v, delta * (4.0 if want_v > _speed else 6.0))
	var v := _speed
	clown.global_position += dir * minf(v * delta, d)
	clown.walk_amount = move_toward(clown.walk_amount, clampf(v / 2.5, 0.0, 1.0), delta * 4.0)
	clown.run_amount = move_toward(clown.run_amount, 1.0 if speed > 3.0 else 0.0, delta * 3.0)
	clown.velocity = dir * v


func _duck(delta: float) -> void:
	clown.crouch_amount = move_toward(clown.crouch_amount, 1.0, delta * 6.0)
	clown.aim_amount = move_toward(clown.aim_amount, 0.0, delta * 5.0)
	clown.walk_amount = move_toward(clown.walk_amount, 0.0, delta * 6.0)
	clown.run_amount = 0.0
	_t -= delta
	if _t <= 0.0:
		if _after_duck == State.MOVE and not post.is_empty():
			state = State.MOVE
			_to = post.pos
			_jog = false
			moves += 1
		else:
			state = State.HOLD
			_phase = 0
			_t = randf_range(1.0, 3.0)


func _fire() -> void:
	if not clown.has_rifle:
		return
	shots += 1
	var from := clown.muzzle_position()
	clown.fired()
	# (the round goes out across No Man's Land: never at the player)
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(from + (_aim_at - from).normalized() * 60.0)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.05:
		return
	# at a man's pace: limited, building up and easing off (as ClownBrain)
	var diff := wrapf(atan2(dir.x, dir.z) - clown.rotation.y, -PI, PI)
	var cap := (2.6 if _speed < 0.4 else (3.4 if _speed < 3.0 else 2.2)) * clampf(rate / 6.0, 0.5, 1.3)
	_yaw_rate = move_toward(_yaw_rate, clampf(diff * 6.0, -cap, cap), 14.0 * delta)
	clown.rotation.y = wrapf(clown.rotation.y + _yaw_rate * delta, -PI, PI)
	clown.turn_rate = _yaw_rate


func _ground(delta: float) -> void:
	var p := clown.global_position
	var y := field.art.height_at(p.x, p.z)
	clown.global_position.y = move_toward(p.y, y, delta * 8.0) if absf(p.y - y) < 1.0 else y
