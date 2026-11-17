class_name Rattlejack
extends Clown
## The Rattlejack: a British machine gunner in a Brodie helmet, dirty white
## greasepaint and a painted grin, with a Lewis gun. An ordinary infantry
## enemy (no tougher than a WitzSoldat) that fires in bursts.
##
## What sets him apart is how he dies. Most bodies go straight to ragdoll;
## the Rattlejack is killed at once (the kill counts, the AI stops) but his
## body plays out a short, procedural death first, then hands over to the
## ragdoll part-way through the fall, pose for pose and with every bone's
## speed, so physics finishes it:
##
##   headshot  - head snaps back (the helmet may fly), settles and hangs;
##               then he stands there with nothing driving him, the whole
##               body swaying and correcting (hips, knees, ankles, a small
##               step now and then), each correction weaker, until the
##               knees go and he falls the way he was leaning.
##   stagger   - a body shot drives him back two or three unsteady steps
##               (never through a wall), knees buckling, then down.
##   rattle    - (the Death Rattle) the dying grip clamps the trigger: the
##               Lewis gun keeps firing while he jerks and falls, the hands
##               still on it through the ragdoll, rounds going wherever the
##               muzzle points, into anything, other clowns included.
##
## The balance is a little inverted pendulum: the hips' offset from the
## middle of the feet, pulled away by gravity, pushed back by a controller
## whose strength drains as he dies, nudged by small random shoves. The
## pose (pelvis shift and drop, hip tilt, spine counter-bend, head on a
## spring) all follows from it, and two-bone IK keeps the feet planted.

@export_group("Stats")
## Multiplies max_health (set by the game before he enters the tree).
@export var health_mult := 1.0

@export_group("Hybrid deaths")
@export var enable_hybrid_deaths := true
@export var death_rattle_chance := 0.3
@export var death_rattle_min_duration := 0.2      ## seconds the gun keeps firing, at least
@export var death_rattle_max_duration := 1.2
@export var death_rattle_friendly_fire := true    ## rounds hit other clowns
@export var death_rattle_player_damage := false   ## rounds can hit the player
@export var death_rattle_damage := 22.0
@export var death_rattle_stand := Vector2(0.2, 0.5)   ## on his feet, firing, before the ragdoll
@export var enable_delayed_headshot_death := true
@export var headshot_total_delay_max := 2.0       ## longest he stays up after a headshot
@export var headshot_total_delay_min := 1.1
@export var headshot_helmet_chance := 0.75        ## the helmet flies off on the fatal headshot
@export var enable_full_body_death_sway := true
@export var enable_procedural_balance_corrections := true
@export var enable_foot_ik_during_death := true
@export var allow_corrective_foot_steps := true
@export var enable_random_collapse_direction := true
@export var enable_stagger_death := true
@export var stagger_seconds := Vector2(0.7, 1.1)        ## latest the knees go; then about half a second falling
@export var enable_pose_matched_ragdoll := true

@export_group("Death tuning")
@export var head_recoil := 1.0                    ## radians the head snaps back
@export var torso_sway := 1.0                     ## size of the random shoves
@export var hip_displacement := 1.0               ## how far the pelvis moves with the sway
@export var knee_flex := 1.0                      ## how much the knees give
@export var ankle_correction := 1.0               ## heel lift and roll on the unloaded foot
@export var foot_step_distance := 0.24            ## a corrective step (m); a stagger step is longer
@export var balance_decay := 1.0                  ## how fast the balance fails (higher: sooner)

## Tests: force a death ("headshot", "stagger", "rattle", or "ragdoll") and
## the way he falls (local, flat; zero: his own choice).
var force_death := ""
var force_fall := Vector3.ZERO

## Tests and the killcam.
var dying := ""                  ## the staged death under way, "" once the ragdoll has it
var death_kind := ""             ## which one it was
var handed_over := false         ## the ragdoll has him
var handover_at := -1.0          ## seconds after the fatal hit
var handover_pose_error := 0.0   ## largest bone move from the posed frame into the ragdoll's first
var fall_dir := Vector3.ZERO     ## world, flat: the way he went over
var steps_taken := 0
var max_lean := 0.0              ## largest balance error (m)
var foot_slip := 0.0             ## largest planted-foot drift (m)
var rattle_rounds := 0
var rattle_hits := 0             ## rounds that struck another clown
var sway_log: Array = []         ## [t, pelvis x, pelvis z, drop, left load] while swaying

var _info := {}
var _d_zone := &""
var _t := 0.0
var _T := 1.5                    # when the balance gives out at the latest
var _hit_local := Vector3.ZERO   # the fatal round's direction in his own frame (flat)
var _c := Vector3.ZERO           # pelvis offset from where it started (local, flat)
var _cv := Vector3.ZERO
var _acc := Vector3.ZERO
var _support := Vector3.ZERO     # middle of the feet (local, flat), relative to the start
var _support0 := Vector3.ZERO
var _drop := 0.0
var _k0 := 9.0
var _k1 := 3.0
var _w2 := 6.0
var _damp := 2.2
var _shove_t := 0.2
var _bias := Vector3.ZERO
var _collapsing := false
var _collapse_t := 0.0
var _collapse_len := 0.28
var _fall_local := Vector3.ZERO
var _feet := {}                  # side -> {pos: Vector3 world, basis: Basis world, lift: float}
var _step := {}                  # the corrective step under way, or {}
var _steps_left := 0
var _blocked_behind := false
var _head := Vector2.ZERO        # loose head: pitch, roll (radians)
var _head_v := Vector2.ZERO
var _twist := 0.0
var _jerk := 0.0
var _rest := {}                  # bones the base pose leaves alone: index -> rest rotation
var _snap_prev := {}
var _snap_cur := {}
var _snap_dt := 1.0 / 60.0
var _rattle_left := 0.0
var _rattle_acc := 0.0
var _rattle_n := 0
var _gun_hand: Node3D
var _pan: Node3D
var _pan_home := Vector3.ZERO
var _reload_len := 3.5
var _release_at := INF           # when the gun slips out of his hands
var _released := false
var _release_t := 0.0
var _arm_from := {}              # arm bone -> rotation as the hands let go


func _init() -> void:
	body = "rattlejack"


func _ready() -> void:
	max_health *= health_mult
	super._ready()
	for b: String in ["Head", "LeftShoulder", "RightShoulder", "Hips"]:
		var bi := skeleton.find_bone(b)
		if bi >= 0:
			_rest[bi] = skeleton.get_bone_pose_rotation(bi)


## Give a fresh brain the machine gunner's settings.
func setup_brain(b: ClownBrain) -> void:
	b.gunner()


# --- the Lewis gun -----------------------------------------------------------------------
## The rifle's carry, aim and recoil, with a Lewis gun in place of the rifle:
## a fat finned barrel shroud, a flat pan magazine on top, a wooden butt and
## pistol grip. No bolt to work between rounds.
func give_rifle() -> void:
	super.give_rifle()
	bolt_seconds = 0.0
	hip_fire = true
	hold_grip = Vector3(0.0, -0.075, 0.31)      # the pistol grip
	hold_fore = Vector2(0.6, 0.6)               # the left hand under the shroud
	hold_fore_y = -0.03
	for ch in _rifle.get_children():
		ch.free()
	_bolt = null
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.12, 0.06)
	wood.roughness = 0.65
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.07, 0.07, 0.075)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var dull := StandardMaterial3D.new()
	dull.albedo_color = Color(0.12, 0.12, 0.11)
	dull.metallic = 0.6
	dull.roughness = 0.55
	# butt at the origin, barrel along +Z (as the rifle)
	_rifle_part(_rifle, Vector3(0.045, 0.11, 0.26), Vector3(0, -0.035, 0.12), wood)       # butt
	_rifle_part(_rifle, Vector3(0.05, 0.05, 0.1), Vector3(0, 0.0, 0.27), wood)           # wrist
	_rifle_part(_rifle, Vector3(0.035, 0.09, 0.045), Vector3(0, -0.07, 0.31), wood)      # pistol grip
	_rifle_part(_rifle, Vector3(0.065, 0.075, 0.2), Vector3(0, 0.02, 0.42), steel)       # receiver
	_cyl(_rifle, 0.045, 0.5, Vector3(0, 0.025, 0.77), Vector3.BACK, dull)                # the finned shroud
	for k in 7:
		_cyl(_rifle, 0.05, 0.012, Vector3(0, 0.025, 0.56 + k * 0.06), Vector3.BACK, dull)    # fins
	_cyl(_rifle, 0.018, 0.09, Vector3(0, 0.025, 1.06), Vector3.BACK, steel)              # muzzle
	_rifle_part(_rifle, Vector3(0.012, 0.03, 0.03), Vector3(0.0, 0.07, 0.98), steel)    # foresight
	_pan = Node3D.new()
	_pan.position = Vector3(0, 0.085, 0.44)
	_rifle.add_child(_pan)
	_cyl(_pan, 0.125, 0.035, Vector3.ZERO, Vector3.UP, dull)                            # the pan
	_cyl(_pan, 0.035, 0.05, Vector3(0, 0.01, 0), Vector3.UP, steel)                     # its hub
	_pan_home = _pan.position
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.025, 1.11)
	_rifle.add_child(_muzzle)


func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3, axis: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 14
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	if axis != Vector3.UP:
		mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	mi.layers = 2
	parent.add_child(mi)


## A round: the flash, the report, the kick, a case out every other round.
## (The brain's _fire does the aiming and the damage.)
func fired() -> void:
	_shot_t = 0.0
	var at := muzzle_position()
	var dir := _muzzle.global_basis.z if _muzzle and is_instance_valid(_muzzle) else global_basis.z
	MuzzleFlash.burst(get_parent(), at, dir, 0.85)
	play_sfx("shot_%d" % (randi() % 3), at, 1.0, randf_range(1.15, 1.3))
	_rattle_n += 1
	if _rattle_n % 2 == 0 and _rifle and is_instance_valid(_rifle) and skeleton:
		_eject_case(skeleton.global_transform.affine_inverse() * _rifle.global_transform)


## The pan comes off and a fresh one goes on (the brain set reload_t).
func start_reload() -> void:
	_reload_len = maxf(reload_t, 0.1)
	play_sfx("bolt_open", muzzle_position(), -6.0, 0.8)
	get_tree().create_timer(_reload_len * 0.75).timeout.connect(func() -> void:
		if is_instance_valid(self) and not dead:
			play_sfx("bolt_close", muzzle_position(), -4.0, 0.85))


# --- every frame ---------------------------------------------------------------------
func _process(delta: float) -> void:
	if dying != "":
		_shot_t += delta
		_dying_process(minf(delta, 1.0 / 30.0))
		return
	if _rattle_left > 0.0:
		_shot_t += delta
		_rattle_update(delta)
		return
	if dead:
		set_process(false)
		return
	if reload_t > 0.0:
		reload_t = maxf(reload_t - delta, 0.0)
		aim_amount = minf(aim_amount, 0.35)
	super._process(delta)
	if reload_t > 0.0 and _pan and has_rifle and not dead and main_arm() != "":
		_reload_pose()
	elif _pan:
		_pan.position = _pan_home
		_pan.visible = true


## Changing the pan: off with the left hand, a fresh one on.
func _reload_pose() -> void:
	var u := 1.0 - reload_t / _reload_len
	var off := smoothstep(0.05, 0.3, u) * (1.0 - smoothstep(0.65, 0.85, u))
	_pan.position = _pan_home + Vector3(0.12, 0.25, -0.05) * off
	_pan.visible = not (u > 0.38 and u < 0.55)          # the empty dropped, the full one not yet up
	var to_skel := skeleton.global_transform.affine_inverse()
	var at := to_skel * _pan.global_position
	var ls := skeleton.get_bone_global_pose(skeleton.find_bone("LeftUpperArm")).origin
	reach("Left", at + Vector3(0, 0.03, 0), ls + Vector3(0.3, -0.5, 0.1))


# --- dying ---------------------------------------------------------------------------
func _die(info: Dictionary, zone: StringName) -> void:
	var staged: bool = enable_hybrid_deaths and not (info.get("blast", false) or info.get("stake", false) or info.has("profile") \
		or crawling or downed or last_stand or ragdoll.active or _halved or info.get("heavy", false) \
		or (info.get("can_dismember", false) and float(info.damage) >= dismember_damage) or broken_leg != "")
	var kind := ""
	if staged:
		var can_rattle := has_rifle and _rifle != null and is_instance_valid(_rifle) and main_arm() != "" and reload_t <= 0.0
		if can_rattle and randf() < death_rattle_chance:
			kind = "rattle"
		elif zone == &"Neck":
			kind = "headshot" if enable_delayed_headshot_death else ""
		elif zone in [&"Chest", &"Spine", &"Hips", &"UpperArm", &"LowerArm", &"Hand"]:
			kind = "stagger" if enable_stagger_death else ""
	if force_death != "":
		kind = "" if force_death == "ragdoll" else force_death
		staged = kind != ""
	if not staged or kind == "":
		death_kind = "ragdoll"
		handed_over = true
		handover_at = 0.0
		super._die(info, zone)
		return
	dead = true
	_record_death(info, zone)
	_begin(kind, info, zone)


func _begin(kind: String, info: Dictionary, zone: StringName) -> void:
	dying = kind
	death_kind = kind
	_info = info.duplicate()
	_d_zone = zone
	_t = 0.0
	_c = Vector3.ZERO
	_cv = Vector3.ZERO
	_drop = 0.0
	_head = Vector2.ZERO
	_head_v = Vector2.ZERO
	_jerk = 0.0
	_collapsing = false
	_step = {}
	walk_amount = 0.0
	run_amount = 0.0
	attack_amount = 0.0
	crouch_amount = 0.0
	aim_point = Vector3.INF
	_model.position = Vector3.ZERO
	var d: Vector3 = info.get("direction", -global_basis.z)
	d.y = 0.0
	_hit_local = (global_basis.inverse() * d).normalized() if d.length() > 0.01 else Vector3.BACK * -1.0
	_hit_local.y = 0.0
	_plant_feet()
	_support0 = _feet_mid()
	_support = Vector3.ZERO
	# a lean that favours open floor and the way the round was going
	_bias = _free_bias() * 0.5 + _hit_local * 0.35
	match kind:
		"headshot":
			_T = randf_range(headshot_total_delay_min, maxf(headshot_total_delay_max, headshot_total_delay_min))
			_k0 = 9.5
			_k1 = 2.0
			_damp = 2.0
			_cv = _hit_local * 0.12
			_steps_left = 2 if allow_corrective_foot_steps else 0
			_collapse_len = randf_range(0.5, 0.62)
			if has_helmet and randf() < headshot_helmet_chance:
				knock_off_helmet(d.normalized() if d.length() > 0.01 else -global_basis.z, info.get("position", global_position + Vector3.UP * 1.75))
		"stagger":
			_T = randf_range(stagger_seconds.x, stagger_seconds.y)
			_k0 = 3.2
			_k1 = 1.0
			_damp = 1.4
			_cv = (_hit_local * 0.7 + Vector3(0, 0, -0.55)).limit_length(1.0)
			_steps_left = randi_range(2, 3)
			_collapse_len = randf_range(0.4, 0.5)
		"rattle":
			_T = randf_range(death_rattle_stand.x, death_rattle_stand.y)
			_k0 = 2.5
			_k1 = 0.5
			_damp = 1.5
			_cv = _hit_local * 0.35
			_steps_left = 0
			_collapse_len = 0.22
			# on his feet firing, then on into the fall for 0.2-1.2 s more
			_rattle_left = _T + _collapse_len + randf_range(death_rattle_min_duration, death_rattle_max_duration)
			_rattle_acc = 1.0 / 9.0 * 0.5
	if not enable_procedural_balance_corrections:
		_k0 *= 0.6
		_k1 *= 0.6
	_k1 /= maxf(balance_decay, 0.05)
	_shove_t = randf_range(0.12, 0.3)
	_twist = randf_range(-1.0, 1.0)
	_released = false
	_arm_from = {}
	match kind:
		"headshot":
			_release_at = randf_range(0.18, 0.32)     # the grip goes with the head snap
		"stagger":
			_release_at = randf_range(0.12, 0.25)
		_:
			_release_at = INF                         # the Rattle keeps hold until the firing stops
	set_process(true)


## Each foot where it is, flat on the floor, turned the way it points now.
func _plant_feet() -> void:
	var space := get_world_3d().direct_space_state
	for side: String in ["Left", "Right"]:
		var fb := skeleton.find_bone(side + "Foot")
		var w := skeleton.global_transform * skeleton.get_bone_global_pose(fb)
		var rest := skeleton.global_basis * skeleton.get_bone_global_rest(fb).basis
		var ankle_h := skeleton.get_bone_global_rest(fb).origin.y
		# level: the rest foot, turned to point where this one points
		var f_now := Vector3(w.basis.z.x, 0, w.basis.z.z)
		var f_rest := Vector3(rest.z.x, 0, rest.z.z)
		var yaw := 0.0
		if f_now.length() > 0.05 and f_rest.length() > 0.05:
			yaw = f_rest.normalized().signed_angle_to(f_now.normalized(), Vector3.UP)
		var floor_y := global_position.y
		var q := PhysicsRayQueryParameters3D.create(w.origin + Vector3.UP * 0.4, w.origin + Vector3.DOWN * 0.8, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			floor_y = hit.position.y
		_feet[side] = {pos = Vector3(w.origin.x, floor_y + ankle_h, w.origin.z), basis = Basis(Vector3.UP, yaw) * rest, lift = 0.0,
			ankle_h = ankle_h, start = Vector3(w.origin.x, floor_y + ankle_h, w.origin.z)}


func _feet_mid() -> Vector3:
	var inv := global_transform.affine_inverse()
	var m := (inv * (_feet.Left.pos as Vector3) + inv * (_feet.Right.pos as Vector3)) * 0.5
	return Vector3(m.x, 0, m.z)


## Which way there is room to fall (local, flat, unit or zero): the open
## directions, weighted by how much room each has.
func _free_bias() -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.9
	var sum := Vector3.ZERO
	for i in 8:
		var dl := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
		var dw := global_basis * dl
		var q := PhysicsRayQueryParameters3D.create(from, from + dw * 1.6, 1)
		var hit := space.intersect_ray(q)
		var room := 1.6 if hit.is_empty() else from.distance_to(hit.position)
		sum += dl * (room / 1.6 - 0.6)
	return sum.limit_length(1.0)


## Room (m) from the pelvis along a local direction, up to `reach`.
func _room(dir_local: Vector3, reach: float) -> float:
	var space := get_world_3d().direct_space_state
	var dw := (global_basis * dir_local).normalized()
	var best := reach
	for h: float in [0.35, 0.95]:
		var from := global_transform * (Vector3(_c.x, h, _c.z))
		var q := PhysicsRayQueryParameters3D.create(from, from + dw * reach, 1)
		q.exclude = _own_rids()
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.distance_to(hit.position))
	return best


func _own_rids() -> Array[RID]:
	var out: Array[RID] = []
	for pb: PhysicalBone3D in ragdoll.bones.values():
		if is_instance_valid(pb):
			out.append(pb.get_rid())
	return out


func _dying_process(d: float) -> void:
	_t += d
	if dying == "rattle":
		_rattle_fire(d)
	_balance(d)
	_pose_dying(d)
	_snapshot(d)
	if _collapsing:
		_collapse_t += d
		if _collapse_t >= _collapse_len:
			_handover()


## The balance: an inverted pendulum about the feet, the controller weakening.
func _balance(d: float) -> void:
	var u := clampf(_t / _T, 0.0, 1.0)
	var k := lerpf(_k0, _k1, pow(u, 0.8)) if enable_procedural_balance_corrections else _k1
	if _collapsing:
		k = 0.0
	# the opening blow: the head shot hardly moves the feet; the body shot
	# drives him back
	var e := _c - _support
	_acc = e * _w2 - e * k - _cv * _damp + _bias * (0.25 + 0.6 * u)
	if _collapsing:
		var cx := _collapse_t / _collapse_len
		_acc += _fall_local * (1.6 + 3.2 * cx * cx)          # tipping, slowly at first
	# little random shoves, irregular in time and size
	_shove_t -= d
	if _shove_t <= 0.0 and enable_full_body_death_sway and not _collapsing:
		_shove_t = randf_range(0.14, 0.38)
		var a := randf() * TAU
		_cv += Vector3(cos(a), 0, sin(a)) * randf_range(0.04, 0.13) * torso_sway * (0.7 + 0.6 * u)
	_cv += _acc * d
	_c += _cv * d
	_c.y = 0.0
	_cv.y = 0.0
	e = _c - _support
	max_lean = maxf(max_lean, e.length())
	# a step to catch himself, while he still can
	if _step.is_empty() and _steps_left > 0 and not _collapsing and _t > (0.06 if dying == "stagger" else 0.35):
		var thresh := 0.06 if dying == "stagger" else 0.085
		if e.length() > thresh:
			_try_step(e)
	if not _step.is_empty():
		_advance_step(d)
	# knees: a slow sag, small dips where they nearly go, then they go
	var sag := 0.0
	match dying:
		"headshot":
			sag = 0.015 + 0.04 * u + 0.025 * maxf(sin(_t * 7.3 + 1.1) * sin(_t * 3.1), 0.0) * u
		"stagger":
			sag = 0.03 + 0.06 * u
		"rattle":
			sag = 0.02 + 0.09 * u
	if _collapsing:
		var cx := clampf(_collapse_t / _collapse_len, 0.0, 1.0)
		sag += 0.34 * cx * cx                                  # the knees fold, faster and faster
	_drop = move_toward(_drop, sag * knee_flex, d * (1.1 if _collapsing else 0.35))
	# over: too far out to come back, or out of time
	var limit := 0.14
	if dying == "stagger":
		limit = 0.3 if (_steps_left > 0 or not _step.is_empty()) else 0.13
	elif not _step.is_empty():
		limit = 0.22                       # mid-step: give the foot a chance to land
	if not _collapsing and (e.length() > limit or _t >= _T or (dying == "stagger" and _blocked_behind and _t > 0.25)):
		_start_collapse(e)


func _start_collapse(e: Vector3) -> void:
	_collapsing = true
	_collapse_t = 0.0
	var dir := e
	if force_fall != Vector3.ZERO:
		dir = force_fall
	elif enable_random_collapse_direction:
		# mostly the way he is already going, pulled toward open floor, a little luck
		var a := randf() * TAU
		var luck := 0.12 if dying == "stagger" else 0.3      # a stagger goes the way it was driven
		dir = e.normalized() * 1.0 + _free_bias() * (0.2 if dying == "stagger" else 0.45) + Vector3(cos(a), 0, sin(a)) * luck
		if dying == "stagger":
			dir += Vector3(0, 0, -0.9) + _hit_local * 0.3          # still going the way the round drove him
		if dying == "headshot" and randf() < 0.35:
			dir += Vector3(0, 0, 1.2)                               # knees first, pitching forward (+Z is his front)
	elif dir.length() < 0.01:
		dir = -_hit_local
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.BACK * -1.0
	# no falling into a wall a hand's breadth away: turn toward where there is room
	if _room(dir.normalized(), 0.9) < 0.35:
		var best := dir
		var best_room := 0.0
		for i in 8:
			var dl := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
			var r := _room(dl, 1.2) + dl.dot(dir.normalized()) * 0.3
			if r > best_room:
				best_room = r
				best = dl
		dir = best
	_fall_local = dir.normalized()
	fall_dir = (global_basis * _fall_local)
	fall_dir.y = 0.0
	fall_dir = fall_dir.normalized()
	_step = {}


func _try_step(e: Vector3) -> void:
	var dirl := e.normalized()
	var inv := global_transform.affine_inverse()
	var side := ""
	if absf(dirl.x) > 0.6:
		side = "Left" if dirl.x > 0.0 else "Right"          # +X is his left
	else:
		# the foot that is behind the way he is going steps through
		var l := (inv * (_feet.Left.pos as Vector3)).dot(dirl)
		var r := (inv * (_feet.Right.pos as Vector3)).dot(dirl)
		side = "Left" if l < r else "Right"
	var dist := foot_step_distance * (1.45 if dying == "stagger" else 1.0) * randf_range(0.85, 1.15)
	var from: Vector3 = _feet[side].pos
	var from_l := inv * from
	var to_l := from_l + dirl * dist
	# never cross the feet
	var other_l := inv * (_feet["Right" if side == "Left" else "Left"].pos as Vector3)
	var sgn := 1.0 if side == "Left" else -1.0
	if (to_l.x - other_l.x) * sgn < 0.12:
		to_l.x = other_l.x + 0.12 * sgn
	# room for the foot and the body behind it
	var room := _room(dirl, dist + 0.4)
	if room < dist + 0.3:
		if dying == "stagger" and dirl.z < 0.0:
			_blocked_behind = true
		dist = room - 0.3
		if dist < 0.08:
			_steps_left = 0
			return
		to_l = from_l + dirl * dist
	var to := global_transform * to_l
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(to + Vector3.UP * 0.5, to + Vector3.DOWN * 0.9, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_steps_left = 0                                       # nothing to put the foot on
		return
	to.y = hit.position.y + float(_feet[side].ankle_h)
	if absf(to.y - from.y) > 0.25:
		_steps_left = 0
		return
	_step = {side = side, from = from, to = to, t = 0.0, len = randf_range(0.22, 0.3) if dying != "stagger" else randf_range(0.17, 0.22)}
	_steps_left -= 1


func _advance_step(d: float) -> void:
	_step.t += d
	var u := clampf(float(_step.t) / float(_step.len), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	var p: Vector3 = (_step.from as Vector3).lerp(_step.to, e)
	_feet[_step.side].pos = p
	_feet[_step.side].lift = sin(u * PI) * (0.07 if dying == "stagger" else 0.05)
	if u >= 1.0:
		_feet[_step.side].lift = 0.0
		_feet[_step.side].start = _step.to
		steps_taken += 1
		# he caught some of it: the feet are under him again, a little
		_support = _feet_mid() - _support0
		_cv *= 0.5 if dying != "stagger" else 0.65
		_step = {}


## The whole body from the balance state.
func _pose_dying(d: float) -> void:
	var sk := skeleton
	for bi: int in _base_rot:
		sk.set_bone_pose_rotation(bi, _base_rot[bi])
	for bi: int in _rest:
		sk.set_bone_pose_rotation(bi, _rest[bi])
	var u := clampf(_t / _T, 0.0, 1.0)
	var e := _c - _support
	var cf := 1.0 if enable_full_body_death_sway else 0.3
	# pelvis: where the balance has it, dropped as the knees give
	_model.position = Vector3(_c.x * hip_displacement * cf, -_drop, _c.z * hip_displacement * cf)
	# the body leans with the pendulum from the hips up; the spine bends back
	# against it (the hip strategy), harder the more he fights it
	var lean := e * cf
	if _collapsing:
		lean += _fall_local * 0.25 * smoothstep(0.0, 1.0, _collapse_t / _collapse_len)
	_tilt("Hips", lean, atan2(lean.length(), 0.9) * 0.9)
	var fight := (-_acc).limit_length(4.0) * 0.02 * cf
	_tilt("Spine", fight, fight.length())
	# --- what each death does to the upper body
	var recoil := 0.0
	var slump := 0.0
	var droop := 0.0
	var aim := 0.0
	match dying:
		"headshot":
			recoil = _pulse(_t, 0.0, 0.05, 0.28)
			slump = smoothstep(0.1, 0.6, _t)
			droop = -0.25 * recoil + 0.75 * smoothstep(0.12, 0.7, _t)
			aim = 0.9 * (1.0 - smoothstep(0.05, 0.5, _t))
			_turn("Chest", Vector3.RIGHT, -0.22 * recoil * head_recoil + 0.16 * slump)
			_turn("Spine", Vector3.RIGHT, 0.08 * slump)
		"stagger":
			recoil = _pulse(_t, 0.0, 0.07, 0.4)
			slump = smoothstep(0.2, 1.0, u)
			droop = -0.45 * recoil + 0.6 * smoothstep(0.25, 1.0, u)
			aim = 0.6 * (1.0 - smoothstep(0.0, 0.3, _t))
			_turn("Chest", Vector3.RIGHT, -0.38 * recoil + 0.12 * slump)
			_turn("Spine", Vector3.RIGHT, -0.12 * recoil)
			_turn("Spine", Vector3.UP, 0.3 * _twist * smoothstep(0.1, 0.8, u))     # twisting as he goes
		"rattle":
			recoil = _pulse(_t, 0.0, 0.04, 0.2)
			slump = smoothstep(0.1, 0.5, _t) * 0.5
			droop = -0.15 * recoil + 0.25 * smoothstep(0.1, 0.5, _t) + 0.1 * sin(_t * 41.0) * _jerk
			aim = 0.85
			_turn("Chest", Vector3.RIGHT, -0.3 * recoil - 0.12 * _jerk)
	_jerk = maxf(_jerk - d * 9.0, 0.0)
	if _collapsing:
		var cu := smoothstep(0.0, 1.0, _collapse_t / _collapse_len)
		_tilt("Chest", _fall_local, 0.25 * cu)
		droop += 0.4 * cu
		slump = maxf(slump, cu)
	# shoulders round and drop
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		_turn(side + "Shoulder", Vector3.BACK, -0.14 * s * slump)
		_turn(side + "Shoulder", Vector3.RIGHT, 0.1 * slump)
	# the head: snapped back, then hanging, swinging on its own as the body moves
	var tgt := Vector2(0.55 * slump if dying == "headshot" else 0.3 * slump, 0.0)
	tgt.x -= head_recoil * recoil * (1.15 if dying == "headshot" else 0.5)
	var accl := Vector2(_acc.z, _acc.x).limit_length(5.0)
	var stiff := 30.0 if _t < 0.3 else 14.0
	_head_v += (Vector2(tgt.x - _head.x, tgt.y - _head.y) * stiff - _head_v * 3.2 - accl * 0.9) * d
	_head += _head_v * d
	if _t < 0.06:
		_head.x = lerpf(_head.x, tgt.x, 0.7)                  # the snap itself is instant
	_turn("Neck", Vector3.RIGHT, _head.x * 0.6)
	_turn("Head", Vector3.RIGHT, _head.x * 0.4)
	_turn("Neck", Vector3.BACK, -_head.y * 0.5)
	_turn("Head", Vector3.BACK, -_head.y * 0.3 + 0.12 * slump * signf(_twist))
	# the gun, in the hands, sagging; then it slips out of them and the arms
	# hang dead, swinging with the body
	aim_amount = aim
	rifle_droop = droop
	if not _released and _t >= _release_at:
		_release_grip()
	velocity = global_basis * _cv                        # what the dangling arms swing with
	if not _released and has_rifle and _rifle and is_instance_valid(_rifle) and main_arm() != "":
		_hold_rifle()
		for side: String in broken_arms:
			dangle_arm(side, 0.0)
	else:
		for side: String in ["Left", "Right"]:
			dangle_arm(side, 0.0, not (side in broken_arms))
		if _released:
			_release_t += d
			var w := smoothstep(0.0, 0.35, _release_t)
			if w < 1.0:
				for bi: int in _arm_from:
					skeleton.set_bone_pose_rotation(bi, (_arm_from[bi] as Quaternion).slerp(skeleton.get_bone_pose_rotation(bi), w))
	# legs: feet planted, knees and ankles taking up the rest
	if enable_foot_ik_during_death:
		_legs(e)
	sway_log.append([_t, _model.position.x, _model.position.z, _drop, e.x])


## The fingers open: the gun slides out of his hands and falls, the arms go
## from holding it to hanging (eased over a third of a second).
func _release_grip() -> void:
	_released = true
	_release_t = 0.0
	_arm_from = {}
	for side: String in ["Left", "Right"]:
		for part: String in ["UpperArm", "LowerArm", "Hand"]:
			var bi := skeleton.find_bone(side + part)
			_arm_from[bi] = skeleton.get_bone_pose_rotation(bi)
	_swing.clear()
	if _rifle and is_instance_valid(_rifle):
		var parent := get_parent()
		var before := parent.get_child_count()
		_drop_rifle()
		if parent.get_child_count() > before:
			var body_ := parent.get_child(parent.get_child_count() - 1) as RigidBody3D
			if body_:
				# it slips and drops, it is not thrown
				body_.linear_velocity = global_basis * _cv + Vector3(0, -0.3, 0)
				body_.angular_velocity = global_basis * Vector3(randf_range(-1.5, 1.5), randf_range(-0.8, 0.8), randf_range(-0.6, 0.6))
	has_rifle = false


func _tilt(bone: String, dir: Vector3, angle: float) -> void:
	var f := Vector3(dir.x, 0, dir.z)
	if f.length() < 0.0001 or absf(angle) < 0.00001:
		return
	f = f.normalized()
	_turn(bone, Vector3(f.z, 0, -f.x), angle)


## A quick rise and a slower fall back (0..1).
static func _pulse(t: float, start: float, peak: float, end: float) -> float:
	if t < start or t > end:
		return 0.0
	if t < peak:
		return smoothstep(start, peak, t)
	return 1.0 - smoothstep(peak, end, t)


## Two-bone IK for each leg onto its planted foot; the unloaded foot rolls
## onto its toes a little; the foot that loses the ground in the fall lifts.
func _legs(e: Vector3) -> void:
	var sk := skeleton
	var to_skel := sk.global_transform.affine_inverse()
	var inv_b := sk.global_basis.inverse()
	var load_left := clampf(0.5 + e.x * 5.0, 0.0, 1.0)         # +X is his left: leaning left loads the left foot
	for side: String in ["Left", "Right"]:
		var f: Dictionary = _feet[side]
		var s := 1.0 if side == "Left" else -1.0
		var unloaded := clampf(((1.0 - load_left) if side == "Left" else load_left) * 2.0 - 1.0, 0.0, 1.0) * ankle_correction
		var p: Vector3 = f.pos + Vector3.UP * (float(f.lift) + 0.018 * unloaded)
		var b: Basis = f.basis
		if _collapsing:
			# the foot on the far side from the fall comes off the floor
			var away := -(global_basis * _fall_local)
			var mine := (p - global_position)
			if Vector3(mine.x, 0, mine.z).dot(away) > 0.02 or (s * _fall_local.x < -0.4):
				var cu := smoothstep(0.3, 1.0, _collapse_t / _collapse_len)
				p += Vector3.UP * 0.08 * cu + (global_basis * _fall_local) * 0.1 * cu
		var target := to_skel * p
		var ul := sk.find_bone(side + "UpperLeg")
		var ll := sk.find_bone(side + "LowerLeg")
		var ft := sk.find_bone(side + "Foot")
		var knee := sk.get_bone_global_pose(ll).origin
		_two_bone(ul, ll, ft, target, knee + Vector3(0.06 * s, 0, 0.5))
		# the foot flat on the floor (toe down a little when unloaded)
		var want := inv_b * b
		if unloaded > 0.0:
			want = Basis(want.x.normalized(), 0.22 * unloaded) * want
		var parent := sk.get_bone_global_pose(ll).basis
		sk.set_bone_pose_rotation(ft, (parent.inverse() * want).get_rotation_quaternion())
		# how far the solved ankle is from its planted spot (a foot that
		# slides or floats); not while it steps or once he is going over
		if not _collapsing and (_step.is_empty() or _step.side != side):
			var got := sk.global_transform * sk.get_bone_global_pose(ft).origin
			foot_slip = maxf(foot_slip, got.distance_to(p))


func _two_bone(ua: int, la: int, hb: int, target: Vector3, pole: Vector3) -> void:
	var sk := skeleton
	var s_pos := sk.get_bone_global_pose(ua).origin
	var e_pos := sk.get_bone_global_pose(la).origin
	var w_pos := sk.get_bone_global_pose(hb).origin
	var a := s_pos.distance_to(e_pos)
	var b := e_pos.distance_to(w_pos)
	var to_t := target - s_pos
	var d := clampf(to_t.length(), absf(a - b) + 0.01, (a + b) * 0.999)
	var dir := to_t.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := (pole - s_pos) - dir * (pole - s_pos).dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.BACK
	bend = bend.normalized()
	var mid := s_pos + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	aim_bone(ua, la, mid)
	aim_bone(la, hb, s_pos + dir * d)


## Every physical bone's world transform this frame and last, for the speeds
## the ragdoll starts with.
func _snapshot(d: float) -> void:
	_snap_prev = _snap_cur
	_snap_cur = {}
	_snap_dt = maxf(d, 0.001)
	for pb: PhysicalBone3D in ragdoll.bones.values():
		if not is_instance_valid(pb):
			continue
		var bi := skeleton.find_bone(pb.bone_name)
		if bi >= 0:
			_snap_cur[bi] = skeleton.global_transform * skeleton.get_bone_global_pose(bi)


## The ragdoll takes him from exactly this pose, every bone already moving
## the way it was. The gun goes with the arms (or, firing, stays in the hand).
func _handover() -> void:
	var info := _info.duplicate()
	info["direction"] = fall_dir if fall_dir != Vector3.ZERO else Vector3(info.get("direction", -global_basis.z))
	info["fling"] = Vector3.ZERO
	var keep_gun := dying == "rattle" and _rattle_left > 0.0 and _rifle != null and is_instance_valid(_rifle)
	info["profile"] = _profile_rattle() if keep_gun else _profile_collapse()
	var gun := _rifle
	if keep_gun:
		_rifle = null                     # _start_ragdoll would drop it
	has_rifle = false                     # and fling the arms off it
	var arm_was := ragdoll.arm_fling
	ragdoll.arm_fling = 0.0
	dying = ""
	handed_over = true
	handover_at = _t
	# the pose the ragdoll will start from, to check it does not jump
	var posed := {}
	for pb: PhysicalBone3D in ragdoll.bones.values():
		if is_instance_valid(pb):
			posed[pb] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(pb.bone_name))
	_start_ragdoll(info, _d_zone)
	ragdoll.arm_fling = arm_was
	if enable_pose_matched_ragdoll and not _snap_prev.is_empty():
		_match_velocities()
	for pb: PhysicalBone3D in posed:
		if is_instance_valid(pb):
			var now := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(pb.bone_name))
			handover_pose_error = maxf(handover_pose_error, now.origin.distance_to((posed[pb] as Transform3D).origin))
	if keep_gun:
		_rifle = gun
		# locked to the hand's own physics body, so it goes exactly where the hand goes
		var hand: PhysicalBone3D = ragdoll.bones.get(StringName((main_arm() if main_arm() != "" else "Right") + "Hand"))
		var g := _rifle.global_transform
		_rifle.get_parent().remove_child(_rifle)
		if hand and is_instance_valid(hand):
			hand.add_child(_rifle)
			_gun_hand = hand
		else:
			skeleton.add_child(_rifle)
		_rifle.global_transform = g
	set_process(_rattle_left > 0.0)


func _match_velocities() -> void:
	for pb: PhysicalBone3D in ragdoll.bones.values():
		if not is_instance_valid(pb):
			continue
		var bi := skeleton.find_bone(pb.bone_name)
		if not (_snap_cur.has(bi) and _snap_prev.has(bi)):
			continue
		var cur: Transform3D = _snap_cur[bi]
		var prev: Transform3D = _snap_prev[bi]
		var v := (cur.origin - prev.origin) / _snap_dt
		var dq := (cur.basis.orthonormalized() * prev.basis.orthonormalized().inverse()).get_rotation_quaternion()
		if dq.w < 0.0:
			dq = -dq
		var ang := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
		var w := Vector3.ZERO
		if ang > 0.0001:
			w = Vector3(dq.x, dq.y, dq.z).normalized() * ang / _snap_dt
		w = w.limit_length(12.0)
		var lin := (v + w.cross(pb.global_position - cur.origin)).limit_length(6.0)
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lin)
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)


## Knees gone, nothing left holding him: physics does the rest.
static func _profile_collapse() -> Dictionary:
	# a little life left in the legs and back, draining over half a second,
	# so the ragdoll carries on the buckle the animation started instead of
	# dropping like a sack; the arms already dead
	return {
		support = [Vector2(0, 0.12), Vector2(0.25, 0)],
		legs = [Vector2(0, 0.35), Vector2(0.25, 0.18), Vector2(0.6, 0)],
		spine = [Vector2(0, 0.45), Vector2(0.5, 0.12), Vector2(1.2, 0)],
		neck = [Vector2(0, 0.08), Vector2(0.35, 0)],
		arms = [Vector2(0, 0.04), Vector2(0.3, 0)],
		fold = 4.0, drift = 0.0, drift_time = 0.1,
	}


## The same, but the arms keep their grip on the gun while it fires.
static func _profile_rattle() -> Dictionary:
	var p := _profile_collapse()
	p["arms"] = [Vector2(0, 0.35), Vector2(0.6, 0.25), Vector2(1.4, 0)]
	return p


# --- the Death Rattle --------------------------------------------------------------------
func _rattle_update(d: float) -> void:
	_rattle_fire(d)
	if _rattle_left <= 0.0:
		_end_rattle()


func _rattle_fire(d: float) -> void:
	if _rattle_left <= 0.0:
		return
	_rattle_left -= d
	_rattle_acc += d
	var gap := 1.0 / 9.0
	while _rattle_acc >= gap and _rattle_left > 0.0:
		_rattle_acc -= gap
		_rattle_shot()
	if _rattle_left <= 0.0 and dying == "":
		_end_rattle()


## One round out of the muzzle, wherever it points: a real ray, the same
## damage as any other round, into whatever it meets.
func _rattle_shot() -> void:
	if _muzzle == null or not is_instance_valid(_muzzle):
		_rattle_left = 0.0
		return
	var from := _muzzle.global_position
	var dir := _muzzle.global_basis.z.normalized()
	var spread := deg_to_rad(1.6)
	dir = (dir + _muzzle.global_basis.x * randfn(0.0, spread) + _muzzle.global_basis.y * randfn(0.0, spread)).normalized()
	fired()
	rattle_rounds += 1
	_jerk = 1.0
	if not handed_over:
		_cv += Vector3(randf_range(-0.06, 0.06), 0, randf_range(-0.09, 0.0))          # each round shoves him
	else:
		var hand: PhysicalBone3D = ragdoll.bones.get(StringName((main_arm() if main_arm() != "" else "Right") + "Hand"))
		if hand and is_instance_valid(hand):
			hand.apply_central_impulse(-dir * 0.9 + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3)))
	var mask := 1 | (1 << 2)
	if death_rattle_player_damage:
		mask |= 1 << 1
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, mask)
	q.exclude = _own_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * 40.0
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c is PhysicalBone3D and c.has_meta(&"clown"):
			var other := c.get_meta(&"clown") as Clown
			if other != self and death_rattle_friendly_fire:
				rattle_hits += 1
				other.hit({collider = c, position = hit.position, direction = dir, damage = death_rattle_damage,
					impulse = 7.0, shot_id = randi(), weapon = "Lewis Gun", dist = from.distance_to(hit.position), friendly = true})
		elif c and c.has_method("take_damage") and death_rattle_player_damage:
			c.take_damage(death_rattle_damage * 0.5, dir)
		elif c and c.has_method("shot"):
			c.shot(hit.position, dir, death_rattle_damage)
		else:
			MechFx.sparks(self, hit.position, (hit.normal as Vector3), 0.35)
	_tracer(from, end)


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
	get_parent().add_child(mi)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


## The finger slips off the trigger: the gun falls out of his hand.
func _end_rattle() -> void:
	_rattle_left = 0.0
	if _rifle and is_instance_valid(_rifle):
		_drop_rifle()
	_gun_hand = null
	set_process(false)


func hit(info: Dictionary) -> void:
	if dying != "" and not _collapsing:
		# shot again on his feet: it rocks him, and a big one takes him down now
		var d: Vector3 = info.get("direction", Vector3.ZERO)
		var dl := global_basis.inverse() * Vector3(d.x, 0, d.z)
		_cv += dl.limit_length(1.0) * clampf(float(info.get("damage", 10.0)) / 60.0, 0.1, 0.6)
		if float(info.get("damage", 0.0)) >= 40.0 or info.get("heavy", false):
			_start_collapse(dl if dl.length() > 0.01 else _c - _support)
	super.hit(info)
