class_name Marionette
extends Node3D
## The Broken Marionette: a Carnival Curse execution, played out on one clown
## as if an invisible puppeteer had him on strings. Added as a child of the
## victim (who is already dead and counted); it owns his skeleton until the
## ragdoll takes him, then cleans itself up.
##
##   seizure   irregular jerks through the shoulders, head and torso, a
##             buckle of the knees, feet planted
##   arm one   in two or three sudden jerks into a broken, right-angled shape
##             (shoulder out, upper arm wrenched round, elbow bent the wrong
##             way, wrist twisted), and it stays there
##   arm two   the other arm, into a different broken shape; both stay
##   neck      a small twitch one way, a beat, then the head snaps over to
##             the side (spread over the chest, neck and head); everything
##             stops
##   pause     utterly still
##   collapse  the knees go and the ragdoll takes him from the exact pose,
##             every bone still moving as it was, the joints' limits opened
##             just enough to hold the broken shape, so nothing snaps back
##
## Every frame the pose is rebuilt from the one he was frozen in, so nothing
## else (walking, aiming) can overwrite it. The arms are aimed in skeleton
## space (absolute directions), so the shapes are the same whatever he was
## doing; they are pulled in toward the body where a wall is in the way.
## Mechanical bodies (the Klappersoldat) spark and leak oil instead of bleed.

## Timeline (seconds), set by CarnivalCurse from its exports.
var seizure := 0.5
var arm_time := 0.6               # the first arm
var arm2_time := 0.6
var neck_time := 0.5
var pause := 0.2
var collapse := 0.32
var vary_arm_order := true
var vary_neck_dir := true
var use_strings := true
var pose_matched := true

## Tests.
var phase := "seizure"
var t := 0.0
var handed_over := false
var handover_at := -1.0
var arm_order: Array[String] = []
var neck_sign := 1.0
var cracks := 0
var handover_pose_error := 0.0

var _c: Clown
var _sk: Skeleton3D
var _frozen := {}                 # bone index -> local rotation at impact
var _bi := {}                     # name -> bone index (cached once)
var _feet := {}                   # side -> {pos, basis} world, planted
var _bursts: Array = []           # [start, length, strength, seed]
var _arm_plan := {}               # side -> {up, fore, twist, bend, shoulder, steps: [times]}
var _neck_jerk := 0.0
var _drop := 0.0
var _sway := Vector3.ZERO
var _fall_dir := Vector3.ZERO     # local, flat
var _snap_prev := {}
var _snap_cur := {}
var _snap_dt := 1.0 / 60.0
var _strings: MeshInstance3D
var _im: ImmediateMesh
var _string_alpha := 0.0
var _anchor := Vector3.ZERO       # world: where the strings go up to
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _played := {}
var _done := false

const ARM_PARTS := ["UpperArm", "LowerArm", "Hand"]
## The broken shapes pulled in against the body, for an arm with a wall
## beside it (the left arm's; mirrored for the right): the upper arm down
## and back, the forearm wrenched up behind the back.
const TUCK_UP := Vector3(0.12, -0.9, -0.35)
const TUCK_FORE := Vector3(-0.35, 0.55, -0.75)
const STRING_BONES := ["LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "LeftUpperArm", "RightUpperArm", "Neck"]


## Take `c` over. Returns the node (already in the tree).
static func start(c: Clown, cfg: Dictionary, hit_at: Vector3) -> Marionette:
	var m := Marionette.new()
	for k: String in cfg:
		m.set(k, cfg[k])
	m.name = "Marionette"
	c.add_child(m)
	m._begin(hit_at)
	return m


func _begin(hit_at: Vector3) -> void:
	_c = get_parent() as Clown
	_sk = _c.skeleton
	_rng.randomize()
	for i in _sk.get_bone_count():
		_frozen[i] = _sk.get_bone_pose_rotation(i)
	for n: String in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftShoulder", "RightShoulder",
			"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		_bi[n] = _sk.find_bone(n)
	_c._model.position = Vector3(_c._model.position.x, 0.0, _c._model.position.z)
	for side: String in ["Left", "Right"]:
		var g := _sk.global_transform * _sk.get_bone_global_pose(_bi[side + "Foot"])
		_feet[side] = {pos = g.origin, basis = g.basis}
	# irregular bursts of convulsion, thickest in the seizure, thinning out,
	# none once the neck has gone
	var stop := seizure + arm_time + arm2_time + neck_time * 0.45
	var tt := 0.0
	while tt < stop:
		var length := _rng.randf_range(0.05, 0.16)
		var strength := _rng.randf_range(0.5, 1.0) * (1.0 if tt < seizure else 0.55)
		_bursts.append([tt, length, strength, _rng.randf() * 100.0])
		tt += length + _rng.randf_range(0.03, 0.22) * (1.0 if tt < seizure else 1.6)
	# which arm first, which shapes: room to each side decides who gets the
	# shape that reaches out
	var left_room := _room(Vector3(1, 0, 0))
	var right_room := _room(Vector3(-1, 0, 0))
	var first := "Left" if left_room > right_room else "Right"
	if vary_arm_order and absf(left_room - right_room) < 0.4 and _rng.randf() < 0.5:
		first = "Right" if first == "Left" else "Left"
	var second := "Right" if first == "Left" else "Left"
	arm_order = [first, second]
	_arm_plan[first] = _plan_arm(first, "wing", _room(Vector3(1 if first == "Left" else -1, 0, 0)))
	_arm_plan[second] = _plan_arm(second, "hang", _room(Vector3(1 if second == "Left" else -1, 0, 0)))
	neck_sign = (1.0 if _rng.randf() < 0.5 else -1.0) if vary_neck_dir else 1.0
	# fall: a way with room, a little random
	var best := Vector3.BACK * -1.0
	var best_room := -1.0
	for i in 8:
		var dl := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0 + _rng.randf_range(-0.2, 0.2))
		var r := _room(dl) + _rng.randf_range(0.0, 0.4)
		if r > best_room:
			best_room = r
			best = dl
	_fall_dir = best
	# the strings hang from the ceiling (or two and a half metres up)
	var top := _c.global_position + Vector3.UP * 1.7
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.UP * 1.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_anchor = (hit.position as Vector3) if not hit.is_empty() else top + Vector3.UP * 1.0
	if use_strings:
		_im = ImmediateMesh.new()
		_strings = MeshInstance3D.new()
		_strings.mesh = _im
		_strings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = false
		_strings.material_override = mat
		_strings.top_level = true
		add_child(_strings)
		_strings.global_transform = Transform3D.IDENTITY
	# a faint violet light that flickers over him while it lasts
	_light = OmniLight3D.new()
	_light.light_color = Color(0.75, 0.25, 0.85)
	_light.omni_range = 3.2
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.top_level = true
	add_child(_light)
	_light.global_position = hit_at
	add_to_group(&"curse_vfx")
	_impact_fx(hit_at)
	set_process(true)


## Room (m) from the chest along a local direction, up to 1.6 m.
func _room(dir_local: Vector3) -> float:
	var from := _c.global_transform * Vector3(0, 1.35, 0)
	var dw := (_c.global_basis * dir_local).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dw * 1.6, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return 1.6 if hit.is_empty() else from.distance_to(hit.position)


## A broken shape for one arm, in skeleton space (+X his left, +Z forward).
##   wing: shoulder hiked out, upper arm straight out to the side, the elbow
##         bent the wrong way so the forearm points back: a right angle
##   hang: shoulder wrenched back, upper arm down and behind him, the forearm
##         bent the wrong way, up and out
## Each varies a little; with little room to that side the arm keeps closer in.
func _plan_arm(side: String, shape: String, room: float) -> Dictionary:
	var s := 1.0 if side == "Left" else -1.0
	var r := _rng
	var up: Vector3
	var fore: Vector3
	if shape == "wing":
		# straight out to the side, then the forearm snapped back behind it
		# (the elbow folded the way it cannot go), hanging back and down
		up = Vector3(s * 1.0, r.randf_range(0.25, 0.45), r.randf_range(-0.15, 0.05))
		fore = Vector3(s * r.randf_range(-0.15, 0.05), r.randf_range(-0.85, -0.55), -1.0)
	else:
		# wrenched back and down behind him, the forearm bent out sideways and up
		up = Vector3(s * r.randf_range(0.3, 0.45), -0.75, r.randf_range(-0.8, -0.6))
		fore = Vector3(s * r.randf_range(0.9, 1.0), r.randf_range(0.35, 0.6), r.randf_range(0.05, 0.3))
	# a wall close on that side: keep it in
	if room < 1.1:
		var k := clampf((1.1 - room) / 0.6, 0.0, 1.0)
		up = up.lerp(TUCK_UP * Vector3(s, 1, 1), k * 0.8)
		fore = fore.lerp(TUCK_FORE * Vector3(s, 1, 1), k * 0.8)
	var steps: Array[float] = []
	var n := 3 if r.randf() < 0.65 else 2
	for i in n:
		steps.append(r.randf_range(0.04, 0.12) + i * r.randf_range(0.12, 0.17))
	return {
		up = up.normalized(), fore = fore.normalized(), steps = steps,
		twist = r.randf_range(0.6, 1.1) * (1.0 if r.randf() < 0.5 else -1.0),       # forearm twisted about itself
		roll = r.randf_range(1.0, 1.4) * s * (1.0 if shape == "wing" else -0.7),   # the upper arm wrenched round in its socket: the elbow faces the wrong way
		bend = r.randf_range(0.5, 0.9) * (1.0 if r.randf() < 0.5 else -1.0),        # wrist bent
		shoulder = r.randf_range(0.18, 0.32) * (1.0 if shape == "wing" else -0.8),
	}


func _process(delta: float) -> void:
	if _done:
		return
	if _c == null or not is_instance_valid(_c) or not _c.is_inside_tree():
		_finish()
		return
	var d := minf(delta, 1.0 / 30.0)
	t += d
	var t_arm1 := seizure
	var t_arm2 := seizure + arm_time
	var t_neck := t_arm2 + arm2_time
	var t_pause := t_neck + neck_time
	var t_fall := t_pause + pause
	if handed_over:
		# the ragdoll has him: only the effects run out
		phase = "ragdoll"
		_vfx(d, t_neck, t_pause, t_fall)
		if t > handover_at + 0.7:
			_finish()
		return
	phase = "seizure" if t < t_arm1 else ("arm1" if t < t_arm2 else ("arm2" if t < t_neck else ("neck" if t < t_pause else ("pause" if t < t_fall else "collapse"))))
	_pose(d, t_arm1, t_arm2, t_neck, t_pause, t_fall)
	_snapshot(d)
	_vfx(d, t_neck, t_pause, t_fall)
	if phase == "collapse" and (t >= t_fall + collapse or _touching_wall()):
		_handover()


## The whole pose, rebuilt from the frozen one every frame.
func _pose(d: float, t_arm1: float, t_arm2: float, t_neck: float, t_pause: float, t_fall: float) -> void:
	for bi: int in _frozen:
		_sk.set_bone_pose_rotation(bi, _frozen[bi])
	# --- convulsions: short, irregular bursts; stopped dead when the neck goes
	var neck_snap_t := t_neck + neck_time * 0.45
	var conv := Vector3.ZERO
	var jerk := 0.0
	if t < neck_snap_t:
		for b: Array in _bursts:
			var st: float = b[0]
			var ln: float = b[1]
			if t >= st and t < st + ln:
				var u: float = (t - st) / ln
				var env := sin(u * PI)
				var sd: float = b[3]
				var k: float = b[2] * env
				conv = Vector3(sin(t * 61.0 + sd), sin(t * 47.0 + sd * 1.7), sin(t * 73.0 + sd * 2.3)) * k
				jerk = k
	# the torso and head
	_c._turn("Spine", Vector3.UP, 0.18 * conv.x)
	_c._turn("Spine", Vector3.BACK, 0.08 * conv.y)
	_c._turn("Chest", Vector3.RIGHT, 0.12 * conv.z)
	_c._turn("Chest", Vector3.BACK, 0.1 * conv.x)
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		_c._turn(side + "Shoulder", Vector3.BACK, -0.22 * s * absf(conv.y) * (1.0 if side == "Left" else 0.8))
	# the knees buckle in the seizure, sag a little after, and go at the end
	var buckle := 0.05 * _pulse(t, 0.12, 0.2, 0.42) + 0.025 * smoothstep(0.0, t_arm1, t) + 0.012 * absf(conv.z)
	if t >= t_fall:
		var cu := clampf((t - t_fall) / collapse, 0.0, 1.0)
		buckle += 0.38 * cu * cu
	_drop = buckle
	_sway = Vector3(0.025 * conv.x, 0.0, 0.02 * conv.z) if t < neck_snap_t else _sway
	var lean := Vector3.ZERO
	if t >= t_fall:
		var cu := clampf((t - t_fall) / collapse, 0.0, 1.0)
		lean = _fall_dir * 0.12 * cu * cu
	_c._model.position = Vector3(_sway.x + lean.x, -_drop, _sway.z + lean.z)
	# --- the arms: each one jerks into its broken shape, and stays there
	for i in arm_order.size():
		var side: String = arm_order[i]
		var start := t_arm1 if i == 0 else t_arm2
		var f := _arm_amount(side, t - start)
		var twitch := conv * (0.25 if f < 0.01 else 0.05)
		_arm(side, f, twitch)
	# --- the head: twitching, then a little jerk one way, a beat, and over
	var head_tw := conv * 0.35
	var roll := 0.0
	if t >= t_neck:
		var u := t - t_neck
		var pre := _pulse(u, 0.0, 0.05, 0.16) * 0.14            # the small jerk the other way
		var snap := 0.0
		var snap_at := neck_time * 0.45
		if u >= snap_at:
			var v := clampf((u - snap_at) / 0.07, 0.0, 1.0)
			snap = v * v * (3.0 - 2.0 * v) + 0.08 * _pulse(u - snap_at, 0.05, 0.08, 0.22)   # a slight overshoot as it lands
		roll = neck_sign * (snap * 1.38 - pre)
		if u >= snap_at:
			head_tw = Vector3.ZERO
	_c._turn("Chest", Vector3.BACK, -roll * 0.12)                 # the shoulders follow a little
	_c._turn("Neck", Vector3.BACK, -roll * 0.55)
	_c._turn("Head", Vector3.BACK, -roll * 0.33)
	_c._turn("Neck", Vector3.RIGHT, 0.15 * absf(roll) + 0.12 * head_tw.y)
	_c._turn("Head", Vector3.UP, 0.25 * head_tw.x + 0.18 * absf(roll) * neck_sign)
	_c._turn("Head", Vector3.RIGHT, 0.2 * head_tw.z)
	# --- the feet stay where they were
	_legs()
	# sounds on the beats
	if t > 0.0 and not _played.has("seize"):
		_played["seize"] = true
		_sfx("musicbox", _bone_pos("Chest"), -6.0, _rng.randf_range(0.92, 1.0))
		_sfx("strain", _bone_pos("Head"), -10.0, _rng.randf_range(0.9, 1.1))
	if jerk > 0.7 and not _played.has("creak%d" % int(t * 3.0)):
		_played["creak%d" % int(t * 3.0)] = true
		_sfx("metal_snap" if _c.mechanical else "creak", _bone_pos("Chest"), -14.0, _rng.randf_range(0.8, 1.2))


## How far into its broken shape an arm is, `u` seconds into its phase:
## two or three sudden jerks, each held, the last one the crack.
func _arm_amount(side: String, u: float) -> float:
	if u <= 0.0:
		return 0.0
	var plan: Dictionary = _arm_plan[side]
	var steps: Array = plan.steps
	var f := 0.0
	for k in steps.size():
		var at: float = steps[k]
		var target := float(k + 1) / steps.size()
		if u >= at:
			var v := clampf((u - at) / 0.045, 0.0, 1.0)              # each jerk takes a few frames
			f = lerpf(float(k) / steps.size(), target, v * v * (3.0 - 2.0 * v))
			if k == steps.size() - 1 and v >= 1.0 and not _played.has("crack" + side) and not _c._segment_gone(side + "UpperArm"):
				_played["crack" + side] = true
				_crack(side + "LowerArm", false)
	return f


## Pose one arm: `f` 0 its frozen pose, 1 fully broken.
func _arm(side: String, f: float, twitch: Vector3) -> void:
	var s := 1.0 if side == "Left" else -1.0
	if _c.arm_out(side) and _c._segment_gone(side + "UpperArm"):
		return                                   # nothing there to break
	var plan: Dictionary = _arm_plan[side]
	var ua: int = _bi[side + "UpperArm"]
	var la: int = _bi[side + "LowerArm"]
	var hb: int = _bi[side + "Hand"]
	# the shoulder jerks first
	var sh_amt := clampf(f * 2.5, 0.0, 1.0)
	_c._turn(side + "Shoulder", Vector3.BACK, float(plan.shoulder) * s * sh_amt)
	if f > 0.0:
		var sh := _sk.get_bone_global_pose(ua).origin
		var el := _sk.get_bone_global_pose(la).origin
		var wr := _sk.get_bone_global_pose(hb).origin
		var a := sh.distance_to(el)
		var b := el.distance_to(wr)
		var up0 := (el - sh).normalized()
		var fore0 := (wr - el).normalized()
		var fu := clampf((f - 0.15) / 0.55, 0.0, 1.0)             # the upper arm swings round
		var ff := clampf((f - 0.5) / 0.5, 0.0, 1.0)              # then the elbow goes
		var up := up0.slerp(plan.up, fu).normalized()
		_c.aim_bone(ua, la, sh + up * a)
		_c._rotate_global(ua, Quaternion(up, float(plan.roll) * fu))
		el = _sk.get_bone_global_pose(la).origin
		fore0 = (_sk.get_bone_global_pose(hb).origin - el).normalized()
		var fore := fore0.slerp(plan.fore, ff).normalized()
		_c.aim_bone(la, hb, el + fore * b)
		# the posed arm is not physics: if this shape reaches into a wall, the
		# shape is pulled in for good (next frame on), not pushed through it
		if not plan.get("tucked", false) and _arm_in_wall(side):
			plan["tucked"] = true
			plan["up"] = (TUCK_UP * Vector3(s, 1, 1)).normalized()
			plan["fore"] = (TUCK_FORE * Vector3(s, 1, 1)).normalized()
			plan["roll"] = 0.0
		# the forearm twisted round itself, the wrist bent
		var fa := (_sk.get_bone_global_pose(hb).origin - el).normalized()
		_c._rotate_global(la, Quaternion(fa, float(plan.twist) * ff))
		var hp := _sk.get_bone_global_pose(hb)
		var side_axis := fa.cross(Vector3.UP).normalized() if absf(fa.y) < 0.95 else Vector3.RIGHT
		_c._rotate_global(hb, Quaternion(side_axis, float(plan.bend) * ff))
	if twitch.length() > 0.001:
		_c._turn(side + "UpperArm", Vector3.RIGHT, twitch.x * 0.3)
		_c._turn(side + "LowerArm", Vector3.RIGHT, twitch.z * 0.25)


## Whether an arm, as posed this frame, reaches a wall: shoulder to elbow to
## hand, a hand's breadth past it.
func _arm_in_wall(side: String) -> bool:
	var space := get_world_3d().direct_space_state
	var g := _sk.global_transform
	var sh := g * _sk.get_bone_global_pose(_bi[side + "UpperArm"]).origin
	var el := g * _sk.get_bone_global_pose(_bi[side + "LowerArm"]).origin
	var wr := g * _sk.get_bone_global_pose(_bi[side + "Hand"]).origin
	var tip := wr + (wr - el).normalized() * 0.16
	for seg: Array in [[sh, el], [el, tip]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var q := PhysicsRayQueryParameters3D.create(a, b + (b - a).normalized() * 0.05, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.6:
			return true
	return false


## Two-bone IK for each leg back onto its planted foot (stairs and all).
func _legs() -> void:
	var to_skel := _sk.global_transform.affine_inverse()
	var inv_b := _sk.global_basis.orthonormalized().inverse()
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		var ul: int = _bi[side + "UpperLeg"]
		var ll: int = _bi[side + "LowerLeg"]
		var ft: int = _bi[side + "Foot"]
		var target := to_skel * (_feet[side].pos as Vector3)
		var s_pos := _sk.get_bone_global_pose(ul).origin
		var e_pos := _sk.get_bone_global_pose(ll).origin
		var w_pos := _sk.get_bone_global_pose(ft).origin
		var a := s_pos.distance_to(e_pos)
		var b := e_pos.distance_to(w_pos)
		var to_t := target - s_pos
		var dd := clampf(to_t.length(), absf(a - b) + 0.01, (a + b) * 0.999)
		var dir := to_t.normalized()
		var cos_a := clampf((a * a + dd * dd - b * b) / (2.0 * a * dd), -1.0, 1.0)
		var pole := e_pos + Vector3(0.05 * s, 0, 0.5)
		var bend := (pole - s_pos) - dir * (pole - s_pos).dot(dir)
		bend = bend.normalized() if bend.length() > 0.001 else Vector3.BACK
		var mid := s_pos + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
		_c.aim_bone(ul, ll, mid)
		_c.aim_bone(ll, ft, s_pos + dir * dd)
		var want := inv_b * (_feet[side].basis as Basis)
		var parent := _sk.get_bone_global_pose(ll).basis
		_sk.set_bone_pose_rotation(ft, (parent.orthonormalized().inverse() * want.orthonormalized()).get_rotation_quaternion())


## The posed body is not physics: if a hand or the head reaches a wall while
## he falls, physics takes him then (as the Rattlejack's staged deaths).
func _touching_wall() -> bool:
	var hips: PhysicalBone3D = _c.ragdoll.bones.get(&"Hips")
	if hips == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := hips.global_position
	for n: StringName in [&"Neck", &"Chest", &"LeftHand", &"RightHand", &"LeftLowerArm", &"RightLowerArm"]:
		var pb: PhysicalBone3D = _c.ragdoll.bones.get(n)
		if pb == null or not is_instance_valid(pb):
			continue
		var to := pb.global_position
		var dv := to - from
		var q := PhysicsRayQueryParameters3D.create(from, to + dv.normalized() * 0.08, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.6:
			return true
	return false


func _snapshot(d: float) -> void:
	_snap_prev = _snap_cur
	_snap_cur = {}
	_snap_dt = maxf(d, 0.001)
	for pb: PhysicalBone3D in _c.ragdoll.bones.values():
		if is_instance_valid(pb):
			_snap_cur[pb] = pb.global_transform


## The strings are cut: the ragdoll takes him from exactly this pose.
func _handover() -> void:
	if handed_over:
		return
	handed_over = true
	handover_at = t
	_sfx("chime", _bone_pos("Chest"), -12.0, 0.7)
	var posed := {}
	for pb: PhysicalBone3D in _c.ragdoll.bones.values():
		if is_instance_valid(pb):
			posed[pb] = pb.global_transform
	var fling := _c.ragdoll.arm_fling
	_c.ragdoll.arm_fling = 0.0
	var dw := _c.global_basis * _fall_dir
	_c.ragdoll.start(_profile(), Vector3(dw.x, 0, dw.z), Vector3.ZERO)
	_c.ragdoll.arm_fling = fling
	_open_limits()
	if pose_matched and not _snap_prev.is_empty():
		_match_velocities()
	for pb: PhysicalBone3D in posed:
		if is_instance_valid(pb):
			handover_pose_error = maxf(handover_pose_error, pb.global_position.distance_to((posed[pb] as Transform3D).origin))
	_c.gore.start_bleeding()
	_c.curse_released()
	_strings_cut_at = t


var _strings_cut_at := -1.0


## The joints' limits, opened (for this body only) just far enough to hold
## the broken pose it starts in, or the ragdoll would wrench every broken limb
## straight back at once. Stable: the springs and the damping are untouched.
func _open_limits() -> void:
	for pb: PhysicalBone3D in _c.ragdoll.bones.values():
		if not is_instance_valid(pb):
			continue
		var n := String(pb.bone_name)
		if not (n.contains("Arm") or n.ends_with("Hand") or n == "Neck" or n == "Chest"):
			continue
		for ax: String in ["x", "y", "z"]:
			var pre := "joint_constraints/%s/" % ax
			var eq := rad_to_deg(float(pb.get(pre + "angular_equilibrium_point")))
			var lo := float(pb.get(pre + "angular_limit_lower"))
			var hi := float(pb.get(pre + "angular_limit_upper"))
			var mn := minf(lo, hi)
			var mx := maxf(lo, hi)
			if eq < mn + 4.0 or eq > mx - 4.0:
				mn = minf(mn, eq - 12.0)
				mx = maxf(mx, eq + 12.0)
				if lo <= hi:
					pb.set(pre + "angular_limit_lower", mn)
					pb.set(pre + "angular_limit_upper", mx)
				else:
					pb.set(pre + "angular_limit_lower", mx)
					pb.set(pre + "angular_limit_upper", mn)


## A puppet with its strings cut: the legs and hips gone, the broken arms and
## neck held for a moment by what is left of the muscles, then slack.
func _profile() -> Dictionary:
	return {
		support = [Vector2(0, 0.0)],
		legs = [Vector2(0, 0.08), Vector2(0.3, 0)],
		spine = [Vector2(0, 0.35), Vector2(0.6, 0.1), Vector2(1.2, 0)],
		neck = [Vector2(0, 0.9), Vector2(1.0, 0.6), Vector2(2.4, 0.15), Vector2(3.4, 0)],
		arms = [Vector2(0, 0.8), Vector2(1.0, 0.55), Vector2(2.4, 0.15), Vector2(3.4, 0)],
		fold = 8.0, drift = 0.0, drift_time = 0.1, buckle = 1.0,
	}


func _match_velocities() -> void:
	for pb: PhysicalBone3D in _c.ragdoll.bones.values():
		if not (is_instance_valid(pb) and _snap_cur.has(pb) and _snap_prev.has(pb)):
			continue
		var cur: Transform3D = _snap_cur[pb]
		var prev: Transform3D = _snap_prev[pb]
		var v := (cur.origin - prev.origin) / _snap_dt
		var dq := (cur.basis.orthonormalized() * prev.basis.orthonormalized().inverse()).get_rotation_quaternion()
		if dq.w < 0.0:
			dq = -dq
		var ang := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
		var w := Vector3.ZERO
		if ang > 0.0001:
			w = Vector3(dq.x, dq.y, dq.z).normalized() * ang / _snap_dt
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v.limit_length(4.0))
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w.limit_length(8.0))


## Something else takes him now (an explosion): straight to the ragdoll.
func release_now() -> void:
	if not handed_over and not _done:
		_handover()


# --- effects ---------------------------------------------------------------------------
func _impact_fx(at: Vector3) -> void:
	_sfx("porcelain", at, -2.0, 1.0)
	_sfx("chime", at, -6.0, randf_range(0.85, 0.95))
	_light.light_energy = 1.8
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 26
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.9, 0.86)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.roughness = 0.4
	q.material = m
	p.mesh = q
	p.add_to_group(&"curse_vfx")
	_c.get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	_c.get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## A crack at a joint: the sound, a little blood (or sparks and oil).
func _crack(bone: String, big: bool) -> void:
	cracks += 1
	var at := _bone_pos(bone)
	_sfx(("metal_snap" if _c.mechanical else ("crack_big" if big else "crack")), at, 0.0 if big else -4.0, _rng.randf_range(0.9, 1.08))
	if _c.mechanical:
		MechFx.sparks(_c, at, Vector3.UP, 0.4 if big else 0.25)
		if big:
			Blood.spawn_hit(at, (_c.global_basis.z + Vector3.UP * 0.3).normalized(), 0.5, true)
	else:
		Blood.mist(at, Vector3.UP, 0.25 if big else 0.15)
	# a broken bone through the skin (or a burst seam on the clockwork one):
	# a wound the gore system shows, and that bleeds (or leaks) once he is down
	_c.gore.add_wound(StringName(bone), at, 30.0 if big else 20.0)
	_light.light_energy = 1.4 if big else 0.9


func _vfx(d: float, t_neck: float, t_pause: float, t_fall: float) -> void:
	# the neck's crack lands with the snap
	if t >= t_neck + neck_time * 0.45 + 0.05 and not _played.has("neck"):
		_played["neck"] = true
		_crack("Neck", true)
	# a carnival light's flicker, dying away
	var fl := 0.55 + 0.45 * sin(t * 23.0) * sin(t * 7.3 + 1.0)
	var target := (0.5 * fl) if t < t_fall else 0.0
	if t >= t_pause and t < t_fall:
		target = 0.25                                  # the silence: a steady, low glow
	_light.light_energy = move_toward(_light.light_energy, target, d * 6.0)
	_light.global_position = _bone_pos("Chest") + Vector3.UP * 0.4
	# the strings: faint, following his wrists, elbows, shoulders and neck;
	# cut (they spring up and fade) as he falls
	if _im == null:
		return
	var want := 0.0 if t < 0.15 else (0.32 if _strings_cut_at < 0.0 else 0.0)
	_string_alpha = move_toward(_string_alpha, want, d * (2.5 if want > 0.0 else 6.0))
	_im.clear_surfaces()
	if _string_alpha <= 0.005:
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var cut := 0.0 if _strings_cut_at < 0.0 else clampf((t - _strings_cut_at) / 0.25, 0.0, 1.0)
	for k in STRING_BONES.size():
		var n: String = STRING_BONES[k]
		if not _bi.has(n) and n != "Neck":
			continue
		var p := _bone_pos(n)
		var top := _anchor + Vector3(sin(k * 1.7) * 0.25, 0, cos(k * 2.3) * 0.25)
		var low := p.lerp(top, cut * 0.85)                 # cut: the lower end flies up the string
		var col := Color(0.55, 0.22, 0.7, _string_alpha * (0.5 if n.contains("Upper") else 0.8))
		_im.surface_set_color(col)
		_im.surface_add_vertex(top)
		_im.surface_set_color(Color(col.r, col.g, col.b, col.a * 0.4))
		_im.surface_add_vertex(low)
	_im.surface_end()


func _bone_pos(bone: String) -> Vector3:
	var bi: int = _bi.get(bone, _sk.find_bone(bone))
	if handed_over and _c.ragdoll.active:
		return _sk.global_transform * _c.ragdoll.bone_pose(bi).origin
	return _sk.global_transform * _sk.get_bone_global_pose(bi).origin


func _sfx(name_: String, at: Vector3, db: float, pitch: float) -> void:
	SfxSynth.play(_c.get_parent(), name_, at, db, pitch)


static func _pulse(x: float, a: float, peak: float, b: float) -> float:
	if x < a or x > b:
		return 0.0
	if x < peak:
		return smoothstep(a, peak, x)
	return 1.0 - smoothstep(peak, b, x)


## All done: take every effect away (what happened is left on the clown,
## as meta "curse", for tests).
func _finish() -> void:
	if _done:
		return
	_done = true
	if _c and is_instance_valid(_c):
		_c.set_meta(&"curse", {handover_at = handover_at, pose_error = handover_pose_error, cracks = cracks, order = arm_order, neck_sign = neck_sign})
	if _c and is_instance_valid(_c) and not handed_over:
		_handover()
	set_process(false)
	queue_free()
