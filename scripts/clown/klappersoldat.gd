class_name Klappersoldat
extends Clown
## Der Klappersoldat: a WW1 German infantryman built out of clockwork by a
## deranged carnival engineer. Slow, a little tougher than a soldier, deadly
## up close with a heavy, telegraphed blow. Never runs.
##
## Built on the same skeleton, ragdoll, gore and AI as every other enemy:
## - Body: Andrew's Tripo model, rigged to the shared skeleton and cut into
##   the 15 gore segments with stump caps by tools/build_klappersoldat.py
##   (art/klappersoldat/). Only the glowing eyes are added in code.
## - Movement: the shared walk cycle (knees, hips, ankles, counter-turn), but
##   driven by a clockwork clock instead of by distance travelled: each step
##   catches, drives and settles, steps differ in length, the body surges and
##   stops with the legs (so the feet do not skate), the escapement sometimes
##   jams for a moment, the head snaps toward things in stages, the body
##   turns in segments, the arms lag the legs, and it twitches.
## - Gore: ClownGore with `mechanical` set: gears, springs, pistons and
##   wires instead of organs and bones, oil instead of blood, sparks.
## - Death: the shared ragdoll (heavier), a burst of sparks, oil spray, a few
##   seconds of shorting out, gears winding down, and a permanent oil puddle.

@export_group("Stats")
## Multiplies the health the game gives an ordinary enemy on this floor.
## High, to make up for how slowly it comes: about 13 pistol rounds to the
## body, or 4 to the head.
@export var health_mult := 4.0
## Multiplies an ordinary soldier's walking speed.
@export var speed_mult := 0.45
## Multiplies an ordinary soldier's melee damage.
@export var melee_mult := 1.25
## Always false for this enemy; kept so the setting is visible.
@export var sprint := false

@export_group("Clockwork gait")
## Metres covered by one step at full intent.
@export var step_length := 0.5
## Each step's length in time varies by this factor (slightly irregular).
@export var step_jitter := Vector2(0.85, 1.25)
## How long the escapement jams when it catches (seconds), and how often.
@export var hesitation := Vector2(0.1, 0.3)
@export var hesitation_every := Vector2(2.5, 6.0)
## Seconds the head holds still between snaps.
@export var head_hold := Vector2(0.35, 1.1)

@export_group("Combat")
## Seconds for the whole blow: wind-up, the strike, the slow recovery.
@export var attack_seconds := 1.5
## Chance a hit of at least `stagger_damage` makes it stagger.
@export var stagger_chance := 0.2
@export var stagger_damage := 20.0

@export_group("Turning")
## It only ever faces (and walks) north, south, east or west, and turns in
## clicks of this many degrees, pausing between them. Turning to face the
## player after noticing them is slower: smaller clicks, longer pauses.
@export var turn_click := 45.0
@export var turn_click_time := 0.16
@export var turn_pause := Vector2(0.06, 0.14)
@export var notice_click := 30.0
@export var notice_pause := Vector2(0.18, 0.3)
## A new way to go must be wanted this long before it turns for it (so it
## does not swing round for every wobble of the route).
@export var turn_settle := 0.25
## Noticing the player: how long it stares once its head has come round,
## before the body follows.
@export var notice_stare := Vector2(0.5, 0.8)
## How far the neck can turn (degrees either way) while it is fixed on you.
@export var notice_neck := 110.0

@export_group("Death")
## Seconds of the fatal spark burst, of oil spraying, and of twitching after.
@export var fatal_sparks := Vector2(0.2, 0.4)
@export var oil_spray := Vector2(0.3, 0.6)
@export var residual := Vector2(3.0, 5.0)
## Shot dead through the head: seconds it stays on its feet, neck broken and
## shorting out, before it topples over backwards.
@export var stand_seconds := Vector2(1.0, 2.0)
## Overwhelmed: this share of its full health taken in the last second puts it
## into a full-body seizure (limbs wrenched the wrong way, head spinning)
## for this many seconds, then it drops in a heap.
@export var malfunction_damage := 0.5
@export var malfunction_seconds := Vector2(1.6, 2.2)
## Smoke and intermittent arcing from its wounds go on this long after death.
@export var smoke_seconds := 60.0
## At most this many wounds smoke.
@export var smoke_wounds := 3
## Radius of the oil puddle left where the body settles (metres).
@export var puddle_radius := Vector2(0.45, 0.75)
## Heavier than flesh: ragdoll bone masses are multiplied by this.
@export var mass_mult := 1.45

var brain: ClownBrain
var puddled := false             # the oil puddle has been laid (tests)
var staggers := 0                # times it staggered (tests)
var hesitations := 0             # times the escapement caught (tests)
var test_intent := 0.0           # without a brain: how fast it wants to walk (tests)
var test_dir := Vector3.ZERO     # without a brain: which way it wants to walk (tests)
var turning := false             # stopped, turning on the spot (tests)
var dying := ""                  # "head", "torso" or "malfunction" until it falls (tests)
var smoking: Array = []          # smoke emitters on its wounds (tests)

# gait clock
var _step_t := 0.0
var _step_d := 0.5
var _step_from := PI * 0.5
var _halt := 0.0
var _next_hesitate := 4.0
var _moving := false
# head
var _head_yaw := 0.0
var _head_roll := 0.0
var _head_from := Vector2.ZERO
var _head_to := Vector2.ZERO
var _head_t := 1.0
var _head_wait := 0.5
var _glance := 0.0
# facing: always a right angle, turned in clicks
var _shown_yaw := 0.0
var _heading_goal := 0.0
var _click_from := 0.0
var _click_to := 0.0
var _click_t := 1.0
var _click_wait := 0.0
var _pending_goal := 0.0
var _pending_t := 0.0
# noticing the player: 0 no, 1 head coming round, 2 staring, 3 body following
var notice := 0
var _notice_t := 0.0
var _notice_stare := 0.6
var _last_mind := 0
# wounds (bone, local point) and recent damage, for the death
var _wounds: Array = []
var _recent: Array = []
# a scripted death before the ragdoll
var _dying_t := 0.0
var _dying_len := 1.5
var _dying_info := {}
var _dying_zone := &""
var _jerk_t := 0.0
var _jerk_from := {}
var _jerk_to := {}
var _jerk_blend := 1.0
var _kneel_thud := false
var _head_side := 1.0
var _death_kind := ""            # which of the deaths it died (kept after `dying` clears)
var _head_bounced := false
var _last_head_vy := 0.0
# twitches: {bone, axis, angle, t, dur}
var _twitches: Array = []
var _idle_next := 2.0
var _tick_t := 0.0
var _tock := false
var _jaw_t := -1.0
# attack sounds already played this swing
var _atk_marks := {}
# eyes
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _eyes: Array = []
var _flicker_t := 0.0
var _eye_level := 1.0
# dressing, by the body segment it moves with
var _dress_parts := {}
var _eye_side := {}              # 1.0 / -1.0 (left / right of the face) -> eye
var _face_broken := {}           # sides whose porcelain has been shot away
var _spinners: Array = []        # [node, axis, speed]
var _motor := 1.0                # how hard the works are turning (0 when run down)
var _head_dmg := 0.0
# death
var _dead_t := -1.0
var _dead_for := 4.0
var _spark_for := 0.3
var _spray_for := 0.45
var _residual_next := 0.0
var _fatal_at := Vector3.ZERO
var _fatal_dir := Vector3.UP
var _last_chest_speed := 0.0


func _init() -> void:
	body = "klappersoldat"
	mechanical = true
	drive_phase = false
	flinch_strength = 0.8
	head_open_kills = false


func _ready() -> void:
	max_health *= health_mult
	super._ready()
	always_pose = true
	walk_phase = _step_from
	# legs swing exactly far enough for each step to cover step_length
	var hip := skeleton.get_bone_global_rest(skeleton.find_bone("LeftUpperLeg")).origin
	var ankle := skeleton.get_bone_global_rest(skeleton.find_bone("LeftFoot")).origin
	stride_override = rad_to_deg(asin(clampf(step_length / (2.0 * hip.distance_to(ankle)), 0.0, 0.9)))
	for pb: PhysicalBone3D in ragdoll.bones.values():
		pb.mass *= mass_mult
	_dress()
	gore.part_severed.connect(_on_part_severed)
	ragdoll.settled.connect(_on_corpse_settled)
	ragdoll.landed.connect(func(speed: float) -> void:
		MechFx.sound(self, "clatter", _chest_pos(), clampf(-12.0 + speed, -12.0, 2.0)))
	_next_hesitate = randf_range(hesitation_every.x, hesitation_every.y)
	# it stands square to the maze from the start
	rotation.y = snappedf(rotation.y, PI * 0.5)
	_shown_yaw = rotation.y
	_heading_goal = _shown_yaw
	# scripted deaths do their own arms and twitching
	ragdoll.arm_fling = 0.0
	ragdoll.twitch_chance = 0.0
	ragdoll.variation = 0.05
	set_process(true)


## Give a fresh brain the Klappersoldat's settings. Call after the game has
## set it up as for an ordinary soldier, before adding it to the clown.
func setup_brain(b: ClownBrain) -> void:
	b.move_speed *= speed_mult
	b.run_speed = b.move_speed
	b.can_run = sprint
	b.melee_damage *= melee_mult
	b.attack_time = attack_seconds
	b.attack_hit_at = attack_seconds * 0.71
	b.attack_recover = 1.25
	b.weave_rate = 0.0
	b.axis_moves = true
	# it sees a long way round to the side (it notices you crossing in front)
	b.sight_half_angle = 95.0


# --- the body ----------------------------------------------------------------------
func _holder(bone: String, segment: StringName) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var h := Node3D.new()
	att.add_child(h)
	h.transform = skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse()
	if not _dress_parts.has(segment):
		_dress_parts[segment] = []
	_dress_parts[segment].append(h)
	return h


func _dress() -> void:
	# The model has the face, ruff, key and joints. What it cannot have is
	# light: two dim amber eyes, glowing from inside the porcelain sockets.
	var head := _holder("Head", &"Head")
	_eye_mat = Clockwork.mat("amber").duplicate()
	for e: Vector3 in spec.get("eyes", []):
		var eye := Clockwork.part(head, Clockwork.ball(), _eye_mat, e + Vector3(0, 0, -0.004), Vector3.ONE * 0.016)
		_eyes.append(eye)
		_eye_side[signf(e.x)] = eye
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.55, 0.18)
	_eye_light.omni_range = 0.45
	_eye_light.light_energy = 0.06
	_eye_light.shadow_enabled = false
	var eyes: Array = spec.get("eyes", [Vector3(0, 1.74, 0.1)])
	_eye_light.position = (eyes[0] as Vector3) * Vector3(0, 1, 1) + Vector3(0, 0, 0.2)
	head.add_child(_eye_light)


# --- every frame -------------------------------------------------------------------
func _process(delta: float) -> void:
	if dead:
		if dying != "":
			_dying_process(minf(delta, 1.0 / 30.0))
		_dead_process(delta)
		return
	if crawling or downed:
		super._process(delta)
		return
	if brain == null:
		brain = get_node_or_null("Brain") as ClownBrain
	var d := minf(delta, 1.0 / 30.0)
	var attacking := brain != null and brain._attack_t >= 0.0
	_notice_update(d)
	_heading_update(d)
	_gait_clock(d, attacking)
	if attacking:
		attack_amount = 0.0              # the blow is posed below, not by the shared code
	super._process(delta)
	if dead:
		return
	_arms(d)
	if attacking:
		_attack_pose(d)
	else:
		_atk_marks.clear()
	_head(d)
	_twitch_update(d)
	_idle(d, attacking)
	_eyes_update(d)
	_spin(d)


## The stride is driven here, not by distance: each step catches (feet both
## planted, body still), drives through, then settles; the body is moved at
## the rate the legs are moving it, so the feet stay put on the floor.
func _gait_clock(d: float, attacking: bool) -> void:
	var want := brain.intended_speed if brain else test_intent
	_moving = want > 0.05 and not attacking and stagger_time <= 0.0 and not turning and notice == 0
	if brain:
		brain.speed_scale = 1.0 if _moving else 0.0
		if notice != 0:
			brain._cooldown = maxf(brain._cooldown, 0.3)    # no swinging until it has faced you
	if not _moving:
		return
	if _halt > 0.0:
		_halt -= d
		if brain:
			brain.speed_scale = 0.0
		return
	_step_t += d
	var u := _step_t / _step_d
	if u >= 1.0:
		_step_from += PI
		_step_t = 0.0
		u = 0.0
		_step_d = step_length / maxf(want, 0.25) * randf_range(step_jitter.x, step_jitter.y)
		_footfall()
	walk_amount = 1.0                      # a full step every time: the clock sets the pace
	walk_phase = _step_from + _leg_phase(_warp(u))
	if brain:
		# the body surges with the legs; the brain's speed is the average
		brain.speed_scale = maxf(_warp_rate(u), 0.0)
	_next_hesitate -= d
	if _next_hesitate <= 0.0 and u > 0.3 and u < 0.6:
		_next_hesitate = randf_range(hesitation_every.x, hesitation_every.y)
		_halt = randf_range(hesitation.x, hesitation.y)
		hesitations += 1
		MechFx.sound(self, "grind", _chest_pos(), -6.0, randf_range(0.9, 1.1))
		# a jolt to put itself right: a shoulder, or the head
		if randf() < 0.5:
			_add_twitch("Chest", Vector3.BACK, deg_to_rad(randf_range(-7.0, 7.0)), _halt + 0.12)
		else:
			_add_twitch("Neck", Vector3.RIGHT, deg_to_rad(randf_range(-10.0, 6.0)), _halt + 0.1)


## Progress through one step (0..1) at time-fraction u: the escapement holds
## (both feet planted), the drive takes it through (a short spin-up, an even
## push, a short brake) a little past the mark, and it settles back.
const HOLD := 0.12
const SETTLE := 0.1
const RAMP := 0.22            # spin-up and brake, as a share of the drive

## Where in the leg cycle the body is when it is `p` of the way through a step.
## The planted leg's foot sits at sin(phase) ahead of the hip; for it to stay
## put, the body must have moved (1 - sin(phase)) / 2 of the step. So the legs
## pass quickly through double support and slowly through mid-stance.
static func _leg_phase(p: float) -> float:
	return PI * 0.5 - asin(clampf(1.0 - 2.0 * p, -1.0, 1.0)) + maxf(p - 1.0, 0.0) * PI


static func _warp(u: float) -> float:
	if u < HOLD:
		return 0.0
	var drive := 1.0 - HOLD - SETTLE
	if u < 1.0 - SETTLE:
		return 1.04 * _trap((u - HOLD) / drive)
	var y := (u - 1.0 + SETTLE) / SETTLE
	return lerpf(1.04, 1.0, y * y * (3.0 - 2.0 * y))


## How fast the step is moving at u, relative to an even pace (averages 1).
static func _warp_rate(u: float) -> float:
	if u < HOLD:
		return 0.0
	var drive := 1.0 - HOLD - SETTLE
	if u < 1.0 - SETTLE:
		return 1.04 * _trap_rate((u - HOLD) / drive) / drive
	var y := (u - 1.0 + SETTLE) / SETTLE
	return -0.04 * 6.0 * y * (1.0 - y) / SETTLE


## Distance along a move with linear spin-up and brake (0..1 over x 0..1).
static func _trap(x: float) -> float:
	var vmax := 1.0 / (1.0 - RAMP)
	if x < RAMP:
		return 0.5 * vmax * x * x / RAMP
	if x < 1.0 - RAMP:
		return vmax * (0.5 * RAMP + (x - RAMP))
	var r := 1.0 - x
	return 1.0 - 0.5 * vmax * r * r / RAMP


static func _trap_rate(x: float) -> float:
	var vmax := 1.0 / (1.0 - RAMP)
	if x < RAMP:
		return vmax * x / RAMP
	if x < 1.0 - RAMP:
		return vmax
	return vmax * (1.0 - x) / RAMP


func _footfall() -> void:
	var foot := "LeftFoot" if int(round((_step_from - PI * 0.5) / PI)) % 2 == 0 else "RightFoot"
	var at := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(foot)).origin
	MechFx.sound(self, "step", at, -4.0, randf_range(0.85, 1.0))
	if randf() < 0.25:
		MechFx.sound(self, "squeak", at + Vector3.UP * 0.5, -10.0)
	if randf() < 0.15:
		MechFx.sound(self, "rattle", _chest_pos(), -12.0)


## It only ever faces north, south, east or west. A new way to go means stop,
## then turn on the spot in clicks (shuffling the feet round with each), and
## only then walk on. Its facing is set here every frame, whatever the brain
## would have done.
func _heading_update(d: float) -> void:
	var dir := brain.intended_dir if brain else test_dir
	if notice == 3 and brain and brain.player:
		dir = brain.player.global_position - global_position
	elif notice != 0:
		dir = Vector3.ZERO
	if Vector2(dir.x, dir.z).length() > 0.3:
		var g := snappedf(atan2(dir.x, dir.z), PI * 0.5)
		if notice == 3 or absf(wrapf(g - _heading_goal, -PI, PI)) < 0.01:
			_heading_goal = g
			_pending_t = 0.0
		else:
			if absf(wrapf(g - _pending_goal, -PI, PI)) > 0.01:
				_pending_goal = g
				_pending_t = 0.0
			_pending_t += d
			if _pending_t >= turn_settle:
				_heading_goal = g
				_pending_t = 0.0
	var gap := wrapf(_heading_goal - _shown_yaw, -PI, PI)
	if _click_t < 1.0:
		_click_t = minf(_click_t + d / turn_click_time, 1.0)
		var e := _click_t * _click_t * (3.0 - 2.0 * _click_t)
		_shown_yaw = lerp_angle(_click_from, _click_to, e)
		# a shuffle step with each click
		walk_amount = maxf(walk_amount, 0.6)
		walk_phase = _step_from + _leg_phase(_warp(_click_t))
		if _click_t >= 1.0:
			_step_from += PI
			var pause := notice_pause if notice != 0 else turn_pause
			_click_wait = randf_range(pause.x, pause.y)
			_shown_yaw = wrapf(_shown_yaw, -PI, PI)
			MechFx.sound(self, "step", global_position, -10.0, 0.9)
	elif absf(gap) > 0.01:
		_click_wait -= d
		if _click_wait <= 0.0:
			_click_from = _shown_yaw
			var step := deg_to_rad(notice_click if notice != 0 else turn_click)
			_click_to = _shown_yaw + clampf(gap, -step, step)
			_click_t = 0.0
			MechFx.sound(self, "tick", _chest_pos(), -12.0, 0.8)
			if randf() < 0.3:
				MechFx.sound(self, "squeak", _chest_pos(), -14.0, 0.9)
	else:
		_shown_yaw = _heading_goal
	turning = _click_t < 1.0 or absf(wrapf(_heading_goal - _shown_yaw, -PI, PI)) > 0.01 or _pending_t > 0.0
	rotation.y = _shown_yaw
	_model.rotation.y = 0.0


## It has just noticed the player (the brain has started hunting): it stops
## dead, its head comes round to you in jerks, stares, then the body ratchets
## round underneath the still head, and only then does it come for you.
func _notice_update(d: float) -> void:
	if brain == null:
		return
	var mind := int(brain.mind)
	if mind == ClownBrain.Mind.HUNT and _last_mind != ClownBrain.Mind.HUNT:
		notice = 1
		_notice_t = 0.0
		_head_wait = randf_range(0.05, 0.15)
		MechFx.sound(self, "grind", _chest_pos() + Vector3.UP * 0.4, -8.0, 1.2)
	_last_mind = mind
	if notice == 0:
		return
	if mind != ClownBrain.Mind.HUNT or brain.player == null:
		notice = 0
		return
	_notice_t += d
	var aim := _player_angle()
	match notice:
		1:
			if (absf(_head_yaw - clampf(aim, -deg_to_rad(notice_neck), deg_to_rad(notice_neck))) < deg_to_rad(6.0) and _head_t >= 1.0) or _notice_t > 1.8:
				notice = 2
				_notice_t = 0.0
				_notice_stare = randf_range(notice_stare.x, notice_stare.y)
		2:
			if _notice_t > _notice_stare:
				notice = 3
				_notice_t = 0.0
		3:
			if not turning and _notice_t > 0.2:
				notice = 0


## Where the player is, as a turn of the head from straight ahead (radians).
func _player_angle() -> float:
	if brain == null or brain.player == null:
		return 0.0
	var to := brain.player.global_position - global_position
	var fwd := Vector3(sin(_shown_yaw), 0, cos(_shown_yaw))
	return atan2(fwd.cross(Vector3(to.x, 0, to.z)).y, fwd.dot(Vector3(to.x, 0, to.z)))


func _gait() -> float:
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	return maxf(walk_amount, clampf(speed / 0.9, 0.0, 1.0)) if speed > 0.05 else walk_amount


## Arms: the swing lags the legs, the elbows stay bent like a machine's, and
## the swing comes in the same jerky stages as the step.
func _arms(_d: float) -> void:
	var g := _gait()
	var sw := sin(walk_phase)
	var lag := sin(walk_phase - 0.55)
	var arm := deg_to_rad(20.0)
	_turn("LeftUpperArm", Vector3.RIGHT, arm * (lag - sw) * g)
	_turn("LeftLowerArm", Vector3.RIGHT, deg_to_rad(-16.0 - 16.0 * maxf(0.0, -lag) * g))
	if brain == null or brain._attack_t < 0.0:
		_turn("RightUpperArm", Vector3.RIGHT, -arm * (lag - sw) * g)
		_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-16.0 - 16.0 * maxf(0.0, lag) * g))
	# knees and ankles give a hard little lock as each foot plants
	var u := _step_t / maxf(_step_d, 0.01)
	if _moving and u < HOLD:
		var k := (1.0 - u / HOLD) * deg_to_rad(4.0) * g
		_turn("Spine", Vector3.RIGHT, k)


## The heavy blow: the arm is wound up in three ratchet clicks, held cocked,
## then snaps down in one abrupt strike, and is slowly cranked back.
func _attack_pose(_d: float) -> void:
	var t: float = brain._attack_t
	var T: float = brain.attack_time
	var u := clampf(t / T, 0.0, 1.0)
	var rest := [0.0, -16.0, 0.0, 0.0, 0.0]
	var cocked := [-150.0, -78.0, 24.0, -7.0, -20.0]
	var struck := [-38.0, -6.0, -20.0, 16.0, 25.0]
	var pose: Array
	if u < 0.6:
		# three clicks, each quick, then a hold
		var a := 0.0
		for k in 3:
			var c0 := 0.05 + k * 0.18
			a += clampf((u - c0) / 0.05, 0.0, 1.0) / 3.0
			if u >= c0 and not _atk_marks.has(k):
				_atk_marks[k] = true
				MechFx.sound(self, "windup" if k == 0 else "tick", _chest_pos(), -4.0 if k == 0 else -8.0)
		pose = _lerp_pose(rest, cocked, a)
		# a shiver in the cocked arm while it waits
	elif u < 0.68:
		pose = cocked.duplicate()
		pose[0] += sin(t * 70.0) * 1.5
	elif u < 0.73:
		var e := (u - 0.68) / 0.05
		pose = _lerp_pose(cocked, struck, e * e)
		if not _atk_marks.has("strike"):
			_atk_marks["strike"] = true
			MechFx.sound(self, "strike", _chest_pos() + global_basis.z * 0.6, 2.0)
	else:
		# cranked back in two steps
		var r := (u - 0.73) / 0.27
		var a := clampf(r / 0.35, 0.0, 1.0) * 0.5 + clampf((r - 0.55) / 0.3, 0.0, 1.0) * 0.5
		pose = _lerp_pose(struck, rest, a)
	_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(pose[0]))
	_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(pose[1]))
	_turn("Chest", Vector3.UP, deg_to_rad(pose[2]))
	_turn("Spine", Vector3.RIGHT, deg_to_rad(pose[3]))
	_turn("RightHand", Vector3.RIGHT, deg_to_rad(pose[4]))


static func _lerp_pose(a: Array, b: Array, w: float) -> Array:
	var out := []
	for i in a.size():
		out.append(lerpf(a[i], b[i], w))
	return out


## The head holds unnaturally still, then snaps part of the way toward what
## it wants to look at, pauses, and snaps the rest; now and then at a tilt.
func _head(d: float) -> void:
	if notice >= 2:
		# fixed on you: the body turns beneath a head that does not move
		var lock := clampf(_player_angle(), -deg_to_rad(notice_neck), deg_to_rad(notice_neck))
		_head_yaw = lock
		_head_t = 1.0
		_turn("Neck", Vector3.UP, _head_yaw)
		_turn("Neck", Vector3.BACK, _head_roll)
		return
	var want := 0.0
	if brain and brain.mind == ClownBrain.Mind.HUNT and brain.player:
		var to := brain.player.global_position - global_position
		var fwd := Vector3(sin(_shown_yaw), 0, cos(_shown_yaw))
		want = atan2(fwd.cross(Vector3(to.x, 0, to.z)).y, fwd.dot(Vector3(to.x, 0, to.z)))
	else:
		want = _glance
	var limit := notice_neck if notice == 1 else 65.0
	want = clampf(want, -deg_to_rad(limit), deg_to_rad(limit))
	if _head_t < 1.0:
		_head_t = minf(_head_t + d / 0.075, 1.0)
		var e := _head_t * _head_t * (3.0 - 2.0 * _head_t)
		var over := sin(_head_t * PI) * 0.06          # a hair past, then back
		_head_yaw = lerpf(_head_from.x, _head_to.x, e) + (_head_to.x - _head_from.x) * over
		_head_roll = lerpf(_head_from.y, _head_to.y, e)
	else:
		_head_wait -= d
		if _head_wait <= 0.0:
			var gap := want - _head_yaw
			if absf(gap) > deg_to_rad(4.0) or randf() < 0.2:
				_head_from = Vector2(_head_yaw, _head_roll)
				var roll := deg_to_rad(randf_range(-16.0, 16.0)) if randf() < 0.22 else 0.0
				_head_to = Vector2(_head_yaw + gap * (0.6 if absf(gap) > deg_to_rad(25.0) else 1.0), roll)
				_head_t = 0.0
				MechFx.sound(self, "tick", _chest_pos() + Vector3.UP * 0.4, -16.0, 1.2)
			_head_wait = randf_range(head_hold.x, head_hold.y) * (0.45 if notice == 1 else 1.0)
	_turn("Neck", Vector3.UP, _head_yaw)
	_turn("Neck", Vector3.BACK, _head_roll)


func _add_twitch(bone: String, axis: Vector3, angle: float, dur: float) -> void:
	_twitches.append({bone = bone, axis = axis, angle = angle, t = 0.0, dur = maxf(dur, 0.12)})


## Twitches snap in, hold, and snap out: never a smooth wave.
func _twitch_update(d: float) -> void:
	for tw: Dictionary in _twitches:
		tw.t += d
		var t: float = tw.t
		var dur: float = tw.dur
		var w := clampf(t / 0.04, 0.0, 1.0) * clampf((dur - t) / 0.05, 0.0, 1.0)
		_turn(tw.bone, tw.axis, tw.angle * w)
	_twitches = _twitches.filter(func(tw: Dictionary) -> bool: return tw.t < tw.dur)
	if _jaw_t >= 0.0:
		# the jaw is moulded in, so the clack is a snap of the head
		_jaw_t += d
		if _jaw_t < 0.1:
			_turn("Neck", Vector3.RIGHT, deg_to_rad(-4.0))
		else:
			_jaw_t = -1.0


## Almost perfectly still, then: a head tilt, a shoulder jerking, fingers
## clenching, the jaw clacking, the eyes guttering. Ticking all the while.
func _idle(d: float, attacking: bool) -> void:
	_tick_t -= d
	if _tick_t <= 0.0:
		_tick_t = 0.5
		_tock = not _tock
		MechFx.sound(self, "tock" if _tock else "tick", _chest_pos(), -18.0)
	if attacking:
		return
	_idle_next -= d * (0.4 if _moving else 1.0)
	if _idle_next > 0.0:
		return
	_idle_next = randf_range(1.2, 4.5)
	match randi() % 6:
		0:
			_glance = deg_to_rad(randf_range(-50.0, 50.0)) if randf() < 0.7 else 0.0
		1:
			var s := "Left" if randf() < 0.5 else "Right"
			_add_twitch(s + "UpperArm", Vector3.BACK, deg_to_rad(randf_range(6.0, 12.0)) * (1.0 if s == "Left" else -1.0), randf_range(0.12, 0.3))
			MechFx.sound(self, "squeak", _chest_pos(), -14.0, 1.3)
		2:
			var s := "Left" if randf() < 0.5 else "Right"
			_add_twitch(s + "Hand", Vector3.RIGHT, deg_to_rad(randf_range(-25.0, 25.0)), randf_range(0.15, 0.4))
		3:
			_jaw_t = 0.0
			MechFx.sound(self, "jaw", _chest_pos() + Vector3.UP * 0.4, -10.0)
		4:
			_flicker(randf_range(0.15, 0.35))
		5:
			_add_twitch("Neck", Vector3.BACK, deg_to_rad(randf_range(-14.0, 14.0)), randf_range(0.2, 0.5))


func _flicker(seconds: float) -> void:
	_flicker_t = maxf(_flicker_t, seconds)


func _eyes_update(d: float) -> void:
	var lit := _eye_level
	if _flicker_t > 0.0:
		_flicker_t -= d
		lit *= 0.15 if fmod(Time.get_ticks_msec() / 45.0, 2.0) < 1.0 and randf() < 0.7 else 1.0
	_eye_mat.emission_energy_multiplier = 2.2 * lit
	_eye_mat.albedo_color = Color(1.0, 0.6, 0.2).lerp(Color(0.15, 0.1, 0.05), 1.0 - lit)
	if _eye_light and is_instance_valid(_eye_light):
		_eye_light.light_energy = 0.06 * lit


func _spin(d: float) -> void:
	var rate := _motor * (1.4 if _moving else 0.7)
	# gears can be destroyed (a shot through the chest frees the ones in its
	# path), so check before touching them and forget the ones that are gone
	_spinners = _spinners.filter(func(sp: Array) -> bool: return is_instance_valid(sp[0]))
	gore.spin_parts = gore.spin_parts.filter(func(sp: Array) -> bool: return is_instance_valid(sp[0]))
	for sp: Array in _spinners + gore.spin_parts:
		(sp[0] as Node3D).rotate_object_local(Vector3.BACK, float(sp[2]) * rate * d)


func _chest_pos() -> Vector3:
	var pb: PhysicalBone3D = ragdoll.bones.get(&"Chest") if ragdoll else null
	if dead and pb:
		return pb.global_position
	return global_position + Vector3.UP * 1.3


# --- being shot -------------------------------------------------------------------------
func hit(info: Dictionary) -> void:
	var pb := info.collider as PhysicalBone3D
	if pb == null:
		return
	var pos: Vector3 = info.position
	var dir: Vector3 = (info.direction as Vector3).normalized()
	var raw: float = info.damage
	MechFx.sparks(self, pos, (-dir + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.5), randf_range(-0.4, 0.4))).normalized(), clampf(raw / 40.0, 0.4, 1.6))
	MechFx.sound(self, "ping", pos, -3.0, randf_range(0.9, 1.15))
	if not dead and randf() < 0.3:
		_flicker(randf_range(0.1, 0.3))
	var zone := _zone(StringName(pb.bone_name))
	# where it was hit (for the smoke and arcing when it dies), and how much
	# it has taken lately (enough at once and it seizes up)
	_wounds.append({bone = StringName(pb.bone_name), local = pb.global_transform.affine_inverse() * pos})
	if _wounds.size() > 8:
		_wounds.pop_front()
	var now := Time.get_ticks_msec() / 1000.0
	_recent.append([now, raw * float(ZONE_DAMAGE.get(zone, 1.0))])
	_recent = _recent.filter(func(e: Array) -> bool: return now - float(e[0]) < 1.0)
	if dying != "":
		# shot again while it stands there dying: it arcs, and goes over sooner
		MechFx.arc(self, pos, 0.2)
		_dying_len = maxf(_dying_t + 0.15, _dying_len - 0.25)
	super.hit(info)
	if zone == &"Neck":
		_head_damage(raw, pos, dir)


## Strong hits sometimes make it stagger (the upper body snapping back, arms
## jerking, a grind of gears and a pause); otherwise it only jolts and keeps
## coming.
func _flinch_from(world_pos: Vector3, dir: Vector3, damage: float) -> void:
	if damage >= stagger_damage and randf() < stagger_chance:
		super._flinch_from(world_pos, dir, damage * 1.5)
		stagger_time = maxf(stagger_time, randf_range(0.45, 0.7))
		staggers += 1
		for s: String in ["Left", "Right"]:
			_add_twitch(s + "UpperArm", Vector3.RIGHT, deg_to_rad(randf_range(-35.0, 10.0)), randf_range(0.18, 0.35))
			_add_twitch(s + "LowerArm", Vector3.RIGHT, deg_to_rad(randf_range(-30.0, 0.0)), randf_range(0.15, 0.3))
		MechFx.sound(self, "grind", world_pos, 0.0, 0.85)
		MechFx.sound(self, "squeak", world_pos, -6.0, 0.8)
		_flicker(0.3)
		return
	if flinch_strength <= 0.0:
		return
	var inv := skeleton.global_transform.affine_inverse()
	var p := inv * world_pos
	var dd := (inv.basis * dir).normalized()
	var kick := (p - Vector3(0, 1.1, 0)).cross(dd)
	_flinch_vel += (kick * 7.0 * clampf(damage / 34.0, 0.3, 1.2)).limit_length(3.5)


## Shots to the face chip the porcelain; enough on one side shoots that side
## of it away, showing the iron skull and its works behind, and the eye on
## that side gutters out. Both sides gone takes the rest of the face.
func _head_damage(raw: float, pos: Vector3, dir: Vector3) -> void:
	_head_dmg += raw
	if (gore.hidden_mask >> ClownGore.SEGMENTS.find(&"Head")) & 1 == 1:
		return
	_shards(pos, -dir, 1 if raw < 30.0 else 2)
	var local := skeleton.global_transform.affine_inverse() * pos
	var side := 1.0 if local.x >= 0.0 else -1.0
	var need := 75.0 if _face_broken.is_empty() else 140.0
	if _head_dmg >= need and not _face_broken.has(side) or (_head_open and not _face_broken.has(side)):
		_face_broken[side] = true
		gore.blast(&"Neck", pos, dir, 0.055)
		MechFx.sound(self, "clatter", pos, -2.0, 1.3)
		var eye: Variant = _eye_side.get(side)
		if is_instance_valid(eye):
			(eye as MeshInstance3D).material_override = Clockwork.mat("iron")


func _shards(pos: Vector3, dir: Vector3, count: int) -> void:
	for i in count:
		var g := GoreBit.make(Clockwork.shard(randi() % 6), 0.012, 0.03)
		g.marks = false
		var mi := g.get_child(0) as MeshInstance3D
		mi.material_override = Clockwork.mat("porcelain")
		mi.scale = Vector3.ONE * randf_range(0.035, 0.06)
		get_parent().add_child(g)
		g.global_position = pos + Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), randf_range(-0.03, 0.03))
		g.linear_velocity = dir.normalized() * randf_range(1.5, 3.5) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1))
		g.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))


## A part came off: anything added to it in code (the eyes, on the head) goes
## with the gib rather than staying in the air where the bone was.
func _on_part_severed(segment: StringName, gib: Node3D) -> void:
	for h: Variant in _dress_parts.get(segment, []):
		if is_instance_valid(h) and is_instance_valid(gib):
			(h as Node3D).reparent(gib, true)
	_dress_parts.erase(segment)
	if segment == &"Head":
		_eye_level = 0.0
		_eyes_update(0.0)


# --- death --------------------------------------------------------------------------------
## Dead. It does not simply ragdoll:
## - shot through the head: the head snaps back and drops on a broken neck;
##   it stays on its feet a second or two, arms and shoulders jerking, then
##   topples over backwards like a felled post (or against a wall);
## - shot through the body (or a limb): it stops, arms drop, it falls hard onto
##   its knees, kneels there a second, then pitches forward onto its face;
## - overwhelmed (half its health gone in a second): a full-body seizure,
##   limbs wrenched the wrong way, the head spinning round and cocking over,
##   a dead stop, then it drops in a heap.
## Blasts, the stake and a body already on the floor go straight to the
## ragdoll as for anything else. Every death smokes and arcs from the wounds.
func _die(info: Dictionary, zone: StringName) -> void:
	var scripted: bool = not (info.get("blast", false) or info.get("stake", false) or info.has("profile") \
		or crawling or downed or ragdoll.active or _halved)
	if scripted:
		dead = true
		_record_death(info, zone)
		dying = "malfunction" if _recent_damage() >= malfunction_damage * max_health else ("head" if zone == &"Neck" else "torso")
		_dying_t = 0.0
		_dying_info = info.duplicate()
		_dying_zone = zone
		_twitches.clear()
		match dying:
			"head":
				_dying_len = randf_range(stand_seconds.x, stand_seconds.y)
			"torso":
				_dying_len = KNEEL_HIT + KNEEL_LIMP
				_kneel_thud = false
			"malfunction":
				_dying_len = randf_range(malfunction_seconds.x, malfunction_seconds.y) + 0.35
				_jerk_t = 0.0
				_jerk_to = {}
				MechFx.sound(self, "grind", _chest_pos(), 2.0, 0.8)
		gore.start_bleeding()
	else:
		super._die(info, zone)
	_twitches.clear()
	_fatal_at = info.get("position", _chest_pos())
	_fatal_dir = (info.get("direction", Vector3.FORWARD) as Vector3).normalized()
	_dead_t = 0.0
	_dead_for = randf_range(residual.x, residual.y)
	_spark_for = randf_range(fatal_sparks.x, fatal_sparks.y)
	_spray_for = randf_range(oil_spray.x, oil_spray.y)
	_residual_next = _spark_for
	MechFx.sound(self, "failure", _fatal_at, 2.0)
	MechFx.sound(self, "winddown", _chest_pos(), -2.0)
	MechFx.sparks(self, _fatal_at, -_fatal_dir + Vector3.UP * 0.3, 2.0)
	MechFx.arc(self, _fatal_at, 0.3)
	_flicker(0.6)
	_start_smoke()
	set_process(true)
	# a body that never settles still leaves its oil once it has stopped
	get_tree().create_timer(9.0 + _dying_len).timeout.connect(func() -> void:
		if is_instance_valid(self) and not puddled:
			_lay_puddle())


func _recent_damage() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var total := 0.0
	for e: Array in _recent:
		if now - float(e[0]) < 1.0:
			total += float(e[1])
	return total


## Thin smoke rising from the last few wounds (the fatal one first), riding
## on the body as it falls. Each one goes out after smoke_seconds.
func _start_smoke() -> void:
	var used := 0
	for k in range(_wounds.size() - 1, -1, -1):
		if used >= smoke_wounds:
			break
		var w: Dictionary = _wounds[k]
		var pb: PhysicalBone3D = ragdoll.bones.get(w.bone)
		if pb == null or not is_instance_valid(pb):
			continue
		var g := MechFx.smoke(pb, w.local, smoke_seconds)
		if g:
			smoking.append(g)
			used += 1


## A random wound's place in the world now (for the arcs), or the chest.
func _wound_point() -> Vector3:
	for k in 4:
		if _wounds.is_empty():
			break
		var w: Dictionary = _wounds.pick_random()
		var pb: Variant = ragdoll.bones.get(w.bone)
		if is_instance_valid(pb):
			return (pb as PhysicalBone3D).global_transform * (w.local as Vector3)
	return _chest_pos()


## The scripted part of a death, posed every frame until it falls.
func _dying_process(d: float) -> void:
	_dying_t += d
	var t := _dying_t
	for bi: int in _base_rot:
		skeleton.set_bone_pose_rotation(bi, _base_rot[bi])
	var hips := skeleton.find_bone("Hips")
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin)
	_model.position = Vector3.ZERO
	match dying:
		"head":
			_pose_broken_neck(t)
		"torso":
			_pose_knees(t)
		"malfunction":
			_pose_seizure(t, d)
	_twitch_update(d)
	# the wounds short out while it stands there
	if randf() < d * 5.0:
		MechFx.arc(self, _wound_point(), randf_range(0.15, 0.3))
		if randf() < 0.5:
			MechFx.sound(self, "zap", _wound_point(), -6.0)
	if t >= _dying_len:
		_fall()


## The head snaps back, then drops forward and to one side on a broken neck
## and hangs there; arms and shoulders jerk as the works short out.
func _pose_broken_neck(t: float) -> void:
	var neck := 0.0
	if t < 0.07:
		neck = -40.0 * t / 0.07
		_turn("Spine", Vector3.RIGHT, deg_to_rad(-6.0) * t / 0.07)
	else:
		var x := t - 0.07
		neck = 48.0 - 88.0 * exp(-5.5 * x) * cos(9.0 * x)
	_turn("Neck", Vector3.RIGHT, deg_to_rad(neck))
	_turn("Neck", Vector3.BACK, deg_to_rad(24.0) * smoothstep(0.05, 0.5, t))
	_turn("Spine", Vector3.BACK, deg_to_rad(2.0) * sin(t * 2.3))
	_jerk_t -= get_process_delta_time()
	if _jerk_t <= 0.0:
		_jerk_t = randf_range(0.1, 0.3)
		var side := "Left" if randf() < 0.5 else "Right"
		var sg := 1.0 if side == "Left" else -1.0
		match randi() % 4:
			0:
				_add_twitch(side + "UpperArm", Vector3.BACK, deg_to_rad(randf_range(12.0, 35.0)) * sg, randf_range(0.08, 0.18))
			1:
				_add_twitch(side + "LowerArm", Vector3.RIGHT, deg_to_rad(randf_range(-50.0, -12.0)), randf_range(0.08, 0.2))
			2:
				_add_twitch("Chest", Vector3.UP, deg_to_rad(randf_range(-12.0, 12.0)), randf_range(0.1, 0.2))
			3:
				_add_twitch(side + "Hand", Vector3.RIGHT, deg_to_rad(randf_range(-45.0, 45.0)), randf_range(0.1, 0.25))
		if randf() < 0.4:
			MechFx.sound(self, "squeak", _chest_pos(), -10.0, randf_range(0.8, 1.3))


## Stops dead, arms dropping; drops onto its knees (slow to start, hard at the
## end); the head and shoulders bend and bounce with the jolt; it kneels there
## slumped a moment, then tips slowly forward until it goes over.
const KNEEL_HIT := 0.55          # when the knees hit the floor
const KNEEL_LIMP := 0.4          # slumped on its knees, going slack, before the ragdoll takes it

func _pose_knees(t: float) -> void:
	_turn("Spine", Vector3.RIGHT, deg_to_rad(-7.0) * clampf(1.0 - t / 0.15, 0.0, 1.0))
	# the drop: eases in, lands hard
	var x := clampf((t - 0.12) / (KNEEL_HIT - 0.12), 0.0, 1.0)
	var k := 1.0 - cos(x * PI * 0.5)
	var since := maxf(t - KNEEL_HIT, 0.0)
	var jolt := 0.0
	var slack := 0.0
	if t >= KNEEL_HIT:
		if not _kneel_thud:
			_kneel_thud = true
			_head_side = 1.0 if randf() < 0.5 else -1.0
			MechFx.sound(self, "thud", global_position + Vector3.UP * 0.1, 3.0)
			MechFx.sparks(self, global_position + global_basis.z * 0.1 + Vector3.UP * 0.05, Vector3.UP, 0.8)
		jolt = exp(-4.0 * since) * sin(11.0 * since)       # the whole body rings with the impact
		slack = smoothstep(0.0, KNEEL_LIMP, since)          # and the last of the strength goes out of it
		k = 1.0 + 0.035 * jolt
	var hips := skeleton.find_bone("Hips")
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin + Vector3(0, -0.48 * k, -0.03 * k))
	for side: String in ["Left", "Right"]:
		_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-6.0) * k)
		_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(96.0) * k)
		_turn(side + "Foot", Vector3.RIGHT, deg_to_rad(-25.0) * k)
	# the trunk sags as it goes slack
	_turn("Spine", Vector3.RIGHT, deg_to_rad(12.0 * k + 9.0 * jolt + 10.0 * slack))
	_turn("Chest", Vector3.RIGHT, deg_to_rad(8.0 * k + 6.0 * jolt + 6.0 * slack))
	_turn("Spine", Vector3.BACK, deg_to_rad(4.0) * _head_side * slack)
	# the head: drooping as it drops, then thrown about by the impact like a
	# weight on a string (down, back up, over to one side) and left to hang
	var head := 26.0 * smoothstep(0.0, KNEEL_HIT, t) + 40.0 * jolt + 14.0 * slack
	_turn("Neck", Vector3.RIGHT, deg_to_rad(head))
	var roll := exp(-3.0 * since) * sin(7.0 * since + 0.6) * 22.0 + 16.0 * slack
	_turn("Neck", Vector3.BACK, deg_to_rad(roll) * _head_side * signf(since))
	# arms dangle, flung forward with the jolt and swinging back
	var swing := 10.0 * k + 26.0 * jolt
	for side: String in ["Left", "Right"]:
		_turn(side + "UpperArm", Vector3.RIGHT, deg_to_rad(-swing * 0.6))
		_turn(side + "LowerArm", Vector3.RIGHT, deg_to_rad(-8.0 - 14.0 * jolt))


## Every joint wrenched to a new wrong angle in a jerk, again and again; the
## head spins right round and cocks over; then a dead stop.
func _pose_seizure(t: float, d: float) -> void:
	var seize := _dying_len - 0.35
	var frozen := t >= seize
	if not frozen:
		_jerk_t -= d
		if _jerk_t <= 0.0:
			_jerk_t = randf_range(0.09, 0.2)
			_jerk_from = _jerk_now()
			_jerk_to = _wrench()
			_jerk_blend = 0.0
			if randf() < 0.5:
				MechFx.sound(self, "squeak" if randf() < 0.5 else "rattle", _chest_pos(), -4.0, randf_range(0.7, 1.4))
			if randf() < 0.5:
				MechFx.sparks(self, _wound_point(), Vector3.UP, 0.8)
		_jerk_blend = minf(_jerk_blend + d / 0.035, 1.0)
	var pose := _jerk_now()
	for key: String in pose:
		var bone := key.get_slice(":", 0)
		var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][int(key.get_slice(":", 1))]
		_turn(bone, axis, deg_to_rad(pose[key]))
	# the head: a full spin, then cocked right over to one side, looking back
	var spin0 := seize * 0.3
	var spin1 := seize * 0.55
	var yaw := 0.0
	if t > spin0:
		yaw = TAU * smoothstep(spin0, spin1, t)
	if t > spin1:
		yaw = TAU + deg_to_rad(150.0) * smoothstep(spin1, spin1 + 0.12, t)
	_turn("Neck", Vector3.UP, yaw)
	_turn("Neck", Vector3.BACK, deg_to_rad(42.0) * smoothstep(spin1, spin1 + 0.15, t))
	if t > spin0 and t - d <= spin0:
		MechFx.sound(self, "grind", _chest_pos() + Vector3.UP * 0.4, 3.0, 1.5)


func _jerk_now() -> Dictionary:
	var out := {}
	for key: String in _jerk_to:
		out[key] = lerpf(float(_jerk_from.get(key, 0.0)), float(_jerk_to[key]), _jerk_blend)
	return out


## A new set of wrong angles for every joint ("Bone:axis" -> degrees; axis
## 0 = across, 1 = up, 2 = forward, in skeleton space).
func _wrench() -> Dictionary:
	var w := {}
	for side: String in ["Left", "Right"]:
		w[side + "UpperArm:0"] = randf_range(-130.0, 60.0)
		w[side + "UpperArm:2"] = randf_range(-70.0, 70.0)
		# elbows bent back the wrong way as often as not
		w[side + "LowerArm:0"] = randf_range(25.0, 70.0) if randf() < 0.5 else randf_range(-120.0, -50.0)
		w[side + "Hand:0"] = randf_range(-80.0, 80.0)
		# the legs keep their footing: only a buckle at the knee now and then
		w[side + "LowerLeg:0"] = randf_range(0.0, 9.0)
	w["Spine:1"] = randf_range(-38.0, 38.0)
	w["Spine:0"] = randf_range(-18.0, 22.0)
	w["Chest:2"] = randf_range(-26.0, 26.0)
	return w


## The end of the scripted part: the ragdoll takes over with a fall to suit.
func _fall() -> void:
	var info := _dying_info
	var fwd := Vector3(global_basis.z.x, 0, global_basis.z.z).normalized()
	match dying:
		"head":
			info["profile"] = _profile_topple_back()
			info["direction"] = -fwd
			info["fling"] = -fwd * 0.35
		"torso":
			info["profile"] = _profile_kneel_forward()
			info["direction"] = fwd
			info["fling"] = fwd * 0.55 + Vector3.DOWN * 0.1
		_:
			info["profile"] = _profile_heap()
			info["direction"] = Vector3.DOWN
			info["fling"] = Vector3.ZERO
	_death_kind = dying
	dying = ""
	_model.position = Vector3.ZERO
	_start_ragdoll(info, _dying_zone)
	if info.profile.get("neck_broken", false):
		ragdoll.weaken(&"Neck", 0.0)
	if _death_kind == "torso":
		# the head keeps swinging as the ragdoll takes over
		var nb: PhysicalBone3D = ragdoll.bones.get(&"Neck")
		if nb:
			nb.apply_central_impulse((global_basis.x * _head_side * 0.6 + fwd * 0.4) * nb.mass)


## Stiff as a post, tipping over backwards, neck slack.
static func _profile_topple_back() -> Dictionary:
	return {
		support = [Vector2(0, 0.85), Vector2(0.3, 0.45), Vector2(0.65, 0)],
		legs = [Vector2(0, 0.95), Vector2(1.8, 0.8), Vector2(2.8, 0.1), Vector2(3.4, 0)],
		spine = [Vector2(0, 0.95), Vector2(1.8, 0.8), Vector2(2.8, 0.1), Vector2(3.4, 0)],
		neck = [Vector2(0, 0)],
		arms = [Vector2(0, 0.1), Vector2(0.5, 0)],
		lean = [Vector2(0, -0.05), Vector2(0.5, -0.4), Vector2(1.0, -0.7)],
		fold = -2.0, drift = 0.15, drift_time = 0.7, even = true, neck_broken = true,
	}


## Ragdoll from its knees: the hips held up a moment longer while the slack
## trunk, head and arms hang and swing under their own weight; then the
## knees let go too and it goes over forward onto its face.
static func _profile_kneel_forward() -> Dictionary:
	return {
		support = [Vector2(0, 0.9), Vector2(0.5, 0.8), Vector2(1.0, 0.35), Vector2(1.4, 0)],
		legs = [Vector2(0, 0.9), Vector2(1.4, 0.6), Vector2(2.4, 0)],
		spine = [Vector2(0, 0.32), Vector2(0.6, 0.15), Vector2(1.2, 0)],
		neck = [Vector2(0, 0)],
		arms = [Vector2(0, 0)],
		lean = [Vector2(0, 0.25), Vector2(0.9, 0.7)],
		square = [Vector2(0, 1), Vector2(1.5, 1), Vector2(1.9, 0)],
		fold = 12.0, drift_fwd = 0.3, drift_time = 1.0, even = true,
	}


## No strength anywhere: it drops where it stands.
static func _profile_heap() -> Dictionary:
	return {
		support = [Vector2(0, 0)],
		legs = [Vector2(0, 0.08), Vector2(0.25, 0)],
		spine = [Vector2(0, 0.05), Vector2(0.2, 0)],
		neck = [Vector2(0, 0)],
		arms = [Vector2(0, 0)],
		fold = 24.0, drift = 0.0, drift_time = 0.1,
	}


## After the fatal hit: the spark burst and the oil spraying out; a few
## seconds of jerks once it is down while its works wind down and the eyes
## fade; and for a minute, thin smoke from the wounds and now and then an arc
## or a spit of sparks, fewer as time goes on. Then nothing.
func _dead_process(delta: float) -> void:
	if _dead_t < 0.0:
		set_process(false)
		return
	_dead_t += delta
	var t := _dead_t
	if t < _spark_for and fmod(t, 0.07) < delta:
		MechFx.sparks(self, _fatal_at + Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)), Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)), 1.5)
	if t < _spray_for and fmod(t, 0.09) < delta:
		var from := _chest_pos()
		Blood.spawn_hit(from, (_fatal_dir * 0.5 + Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.0), randf_range(-0.8, 0.8))).normalized(), 0.6, true)
		Blood.mist(from, Vector3.UP, 0.8, true)
	if t > _spark_for:
		_residual_next -= delta
		if _residual_next <= 0.0 and t < smoke_seconds:
			# frequent at first, rarer as it runs down
			_residual_next = randf_range(0.3, 0.9) * (1.0 + 6.0 * t / smoke_seconds)
			var at := _wound_point()
			if randf() < 0.55:
				MechFx.arc(self, at, randf_range(0.12, 0.28))
				MechFx.sound(self, "zap", at, -9.0)
			else:
				MechFx.sparks(self, at, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), 0.3 + 0.4 * (1.0 - t / smoke_seconds))
				if randf() < 0.4:
					MechFx.sound(self, "spark", at, -10.0)
			# small jerks of the limbs in the first seconds on the floor
			if t < _dead_for and dying == "" and ragdoll.active and not ragdoll.is_settled:
				var bones := ragdoll.bones.values()
				var picked: Variant = bones.pick_random() if not bones.is_empty() else null
				if is_instance_valid(picked):
					var pb := picked as PhysicalBone3D
					ragdoll.apply_hit(StringName(pb.bone_name), Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)) * 2.5, pb.global_position)
	# the works run down, the eyes go out
	_motor = clampf(1.0 - t / minf(2.6, _dead_for), 0.0, 1.0)
	_eye_level = clampf(1.0 - t / (_dead_for + _dying_len), 0.0, 1.0) * (0.3 if fmod(t, 0.23) < 0.05 else 1.0)
	_eyes_update(delta)
	_spin(delta)
	# falling flat on its back the head hits the floor and bounces, just a little
	if _death_kind == "head" and not _head_bounced and ragdoll.active:
		var hb: PhysicalBone3D = ragdoll.bones.get(&"Neck")
		if hb and is_instance_valid(hb):
			var vy: float = (PhysicsServer3D.body_get_state(hb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).y
			if _last_head_vy < -1.6 and vy > _last_head_vy * 0.3 and hb.global_position.y - global_position.y < 0.45:
				_head_bounced = true
				hb.apply_central_impulse(Vector3.UP * hb.mass * clampf(-_last_head_vy * 0.28, 0.5, 1.1))
				MechFx.sound(self, "clatter", hb.global_position, -8.0)
			_last_head_vy = vy
	# a heavy body hitting the floor lands with a thud
	var cb: PhysicalBone3D = ragdoll.bones.get(&"Chest")
	if cb and is_instance_valid(cb) and ragdoll.active:
		var v: float = (PhysicsServer3D.body_get_state(cb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).length()
		if _last_chest_speed > 1.8 and v < _last_chest_speed * 0.45:
			MechFx.sound(self, "thud", cb.global_position, clampf(-6.0 + _last_chest_speed * 2.0, -6.0, 4.0))
			MechFx.sound(self, "clatter", cb.global_position, clampf(-12.0 + _last_chest_speed * 2.0, -12.0, 0.0))
		_last_chest_speed = v
	if t >= smoke_seconds and _motor <= 0.0 and dying == "":
		_eye_level = 0.0
		_eyes_update(0.0)
		_dead_t = -1.0
		set_process(false)


func _on_corpse_settled() -> void:
	if not puddled:
		_lay_puddle()


## The oil puddle under the body, where it has come to rest on the floor.
## Never under a body still in the air: it needs floor just below the chest.
func _lay_puddle() -> void:
	var cb: PhysicalBone3D = ragdoll.bones.get(&"Chest")
	var at := cb.global_position if cb and is_instance_valid(cb) else global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at + Vector3.DOWN * 0.8, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.6:
		return
	puddled = true
	Blood.spawn_oil_puddle(hit.position, hit.normal, randf_range(puddle_radius.x, puddle_radius.y))
