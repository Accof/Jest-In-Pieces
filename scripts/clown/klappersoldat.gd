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
@export var health_mult := 1.75
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

@export_group("Death")
## Seconds of the fatal spark burst, of oil spraying, and of shorting out after.
@export var fatal_sparks := Vector2(0.2, 0.4)
@export var oil_spray := Vector2(0.3, 0.6)
@export var residual := Vector2(3.0, 5.0)
## Radius of the oil puddle left where the body settles (metres).
@export var puddle_radius := Vector2(0.45, 0.75)
## Heavier than flesh: ragdoll bone masses are multiplied by this.
@export var mass_mult := 1.45

var brain: ClownBrain
var puddled := false             # the oil puddle has been laid (tests)
var staggers := 0                # times it staggered (tests)
var hesitations := 0             # times the escapement caught (tests)
var test_intent := 0.0           # without a brain: how fast it wants to walk (tests)

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
# body turning in stages
var _shown_yaw := 0.0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 1.0
var _turn_wait := 0.0
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
	_shown_yaw = rotation.y
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
		_dead_process(delta)
		return
	if crawling or downed:
		super._process(delta)
		return
	if brain == null:
		brain = get_node_or_null("Brain") as ClownBrain
	var d := minf(delta, 1.0 / 30.0)
	var attacking := brain != null and brain._attack_t >= 0.0
	_gait_clock(d, attacking)
	if attacking:
		attack_amount = 0.0              # the blow is posed below, not by the shared code
	_body_turn(d)
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
	_moving = want > 0.05 and not attacking and stagger_time <= 0.0
	if brain:
		brain.speed_scale = 1.0
	if not _moving:
		if _turn_t < 1.0:
			# turning on the spot: shuffle the feet round with the body
			walk_amount = maxf(walk_amount, 0.55)
			walk_phase = _step_from + _leg_phase(_warp(_turn_t))
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


## The body (the model) follows the way the brain faces in stages: a quick
## turn of up to 35 degrees, a pause, the next.
func _body_turn(d: float) -> void:
	var facing := rotation.y
	if _turn_t < 1.0:
		_turn_t = minf(_turn_t + d / 0.16, 1.0)
		var e := _turn_t * _turn_t * (3.0 - 2.0 * _turn_t)
		_shown_yaw = lerp_angle(_turn_from, _turn_to, e)
		if _turn_t >= 1.0:
			_turn_wait = randf_range(0.1, 0.28)
			if not _moving:
				_step_from += PI       # the shuffle step is done
	else:
		_turn_wait -= d
		var gap := wrapf(facing - _shown_yaw, -PI, PI)
		if absf(gap) > deg_to_rad(11.0) and _turn_wait <= 0.0:
			_turn_from = _shown_yaw
			_turn_to = _shown_yaw + clampf(gap, -deg_to_rad(35.0), deg_to_rad(35.0))
			_turn_t = 0.0
			MechFx.sound(self, "tick", _chest_pos(), -14.0, 0.8)
	_model.rotation.y = wrapf(_shown_yaw - facing, -PI, PI)


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
	var want := 0.0
	if brain and brain.mind == ClownBrain.Mind.HUNT and brain.player:
		var to := brain.player.global_position - global_position
		var fwd := Vector3(sin(_shown_yaw), 0, cos(_shown_yaw))
		want = atan2(fwd.cross(Vector3(to.x, 0, to.z)).y, fwd.dot(Vector3(to.x, 0, to.z)))
	else:
		want = _glance
	want = clampf(want, -deg_to_rad(65.0), deg_to_rad(65.0))
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
			_head_wait = randf_range(head_hold.x, head_hold.y)
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
func _die(info: Dictionary, zone: StringName) -> void:
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
	_flicker(0.6)
	set_process(true)
	# a body that never settles still leaves its oil once it has stopped
	get_tree().create_timer(9.0).timeout.connect(func() -> void:
		if is_instance_valid(self) and not puddled:
			_lay_puddle())


## After the fatal hit: the spark burst, the oil spraying out, then a few
## seconds of shorting out (spits of sparks, crackle, small jerks of the
## limbs) while the eyes fade and the works wind down. Then nothing.
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
		if _residual_next <= 0.0 and t < _dead_for:
			_residual_next = randf_range(0.2, 0.6) * (1.0 + t / _dead_for)
			var bones := ragdoll.bones.values()
			if not bones.is_empty():
				var picked: Variant = bones.pick_random()
				if is_instance_valid(picked):
					var pb := picked as PhysicalBone3D
					MechFx.sparks(self, pb.global_position, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), 0.5 * (1.0 - t / _dead_for) + 0.2)
					if randf() < 0.45:
						MechFx.sound(self, "spark", pb.global_position, -8.0)
					if randf() < 0.5 and ragdoll.active and not ragdoll.is_settled:
						ragdoll.apply_hit(StringName(pb.bone_name), Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)) * 2.5, pb.global_position)
	# the works run down, the eyes go out
	_motor = clampf(1.0 - t / minf(2.6, _dead_for), 0.0, 1.0)
	_eye_level = clampf(1.0 - t / _dead_for, 0.0, 1.0) * (0.3 if fmod(t, 0.23) < 0.05 else 1.0)
	_eyes_update(delta)
	_spin(delta)
	# a heavy body hitting the floor clatters
	var cb: PhysicalBone3D = ragdoll.bones.get(&"Chest")
	if cb and is_instance_valid(cb):
		var v: float = (PhysicsServer3D.body_get_state(cb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).length()
		if _last_chest_speed > 2.2 and v < _last_chest_speed * 0.45:
			MechFx.sound(self, "clatter", cb.global_position, clampf(-10.0 + _last_chest_speed * 2.0, -10.0, 3.0))
		_last_chest_speed = v
	if t >= _dead_for and _motor <= 0.0:
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
