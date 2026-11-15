class_name ClownRagdoll
extends Node
## Physical skeleton for the clown, plus the "active ragdoll" controller.
##
## Every bone has a muscle-tone value from 0 (limp) to 1 (holds its pose).
## A death reaction is a set of tone curves over time: the body keeps some
## strength for a moment after the hit, then the curves fade and gravity wins.
## Joints use 6DOF limits so knees, elbows, wrists and ankles only bend the
## way real ones do.

signal went_limp          ## all muscle tone has reached zero
signal settled            ## the body has come to rest on the ground

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 1 << 2

# --- feel tuning --------------------------------------------------------------
## Overall muscle strength at full tone. 1.0 is a firm living body.
@export var muscle_strength := 1.0
## Resistance left in a dead joint (cartilage, clothing, muscle mass).
## This is the main "not too floppy, not too stiff" control: raise it for a
## heavier, stiffer corpse, lower it for a looser one.
@export var dead_joint_friction := 0.8
## How firmly the pelvis is held up while the clown still carries its weight.
@export var support_stiffness := 120.0
@export var support_damping := 20.0
## How firmly the chest is kept over the pelvis while the spine has strength.
@export var upright_stiffness := 90.0
@export var upright_damping := 16.0
## Extra gravity on a body that is going down. Above 1 it drops with more
## weight; 1.0 is real gravity.
@export var fall_weight := 1.7
## Plays every death profile faster. 1.0 is the original timing.
@export var fall_speed := 1.35
## How much each death is randomly varied in timing and reach (0 = identical every time).
@export var variation := 0.15
## How far the arms are thrown out by reflex at the moment of death (0 = they
## stay where they were, 1 = full flail).
@export var arm_fling := 1.0
## Chance that a body twitches for a second or two after it goes limp.
@export var twitch_chance := 0.3
## Air drag on the body.
@export var limp_angular_damp := 0.45
@export var limp_linear_damp := 0.08
## No bone may move faster than this, so a big hit cannot launch the body.
@export var max_bone_speed := 9.0
@export var max_bone_spin := 24.0

## Degrees the knees and hips fold as the legs lose strength. Without this a
## dying clown would balance on locked knees like a statue.
@export var knee_buckle := 42.0
@export var hip_buckle := 16.0

## Muscle per joint: [spring stiffness N*m/rad at full tone, damping at full
## tone, damping left when dead]. Sized to the weight each joint carries.
const MUSCLE := {
	&"Spine": [1800.0, 220.0, 7.0], &"Chest": [1500.0, 160.0, 8.0], &"Neck": [160.0, 14.0, 2.5],
	&"UpperArm": [160.0, 18.0, 1.1], &"LowerArm": [50.0, 4.0, 0.45], &"Hand": [6.0, 0.4, 0.08],
	&"UpperLeg": [1500.0, 130.0, 10.0], &"LowerLeg": [1200.0, 70.0, 6.0], &"Foot": [350.0, 18.0, 1.5],
}

var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bones := {}                 # StringName -> PhysicalBone3D
var active := false
var limp := false
var is_settled := false
var time := 0.0

var _order: Array = []          # bone defs, parent first
var _info := {}                 # StringName -> {parent, group, frame, tone}
var _profile := {}
var _root_target := Vector3.ZERO
var _chest_offset := Vector3.ZERO
var _root_drift := Vector3.ZERO
var _root_drift_time := 0.0
var _fwd := Vector3.BACK
var _left := Vector3.RIGHT
var _level_axis := Vector3.RIGHT
var _tone_scale := {}           # per-bone multiplier (a shot leg goes weak)
var _still_time := 0.0
var _twitch_left := 0.0
var _twitch_next := 0.0
var _twitch_bone := &""
var _gravity := 9.8


# --- skeleton definition ------------------------------------------------------
# Positions are in skeleton space (x = clown's left, y = up, z = forward).
# Limits are degrees of rotation of the bone relative to its parent, about the
# skeleton axes, measured from the T-pose with the right-hand rule.
static func defs() -> Array:
	var d: Array = [
		{n = &"Hips", p = &"", m = 11.0, box = Vector3(.34, .22, .22), c = Vector3(0, .965, 0), j = Vector3(0, .97, 0), g = &"root"},
		{n = &"Spine", p = &"Hips", m = 9.0, box = Vector3(.31, .18, .21), c = Vector3(0, 1.17, 0), j = Vector3(0, 1.08, 0),
			x = [-25, 58], y = [-22, 22], z = [-28, 28], g = &"spine"},
		{n = &"Chest", p = &"Spine", m = 16.0, box = Vector3(.32, .27, .23), c = Vector3(0, 1.395, 0), j = Vector3(0, 1.26, 0),
			x = [-14, 34], y = [-16, 16], z = [-18, 18], g = &"spine"},
		{n = &"Neck", p = &"Chest", m = 5.0, sphere = .105, c = Vector3(0, 1.73, .012), j = Vector3(0, 1.53, .004),
			x = [-40, 38], y = [-50, 50], z = [-22, 22], g = &"neck"},
	]
	for s: float in [1.0, -1.0]:
		var sd := "Left" if s > 0.0 else "Right"
		d.append({n = StringName(sd + "UpperArm"), p = &"Chest", m = 2.2, cap = [.055, .30, "x"], c = Vector3(s * .3475, 1.455, -.004), j = Vector3(s * .205, 1.455, 0),
			x = [-60, 60], y = _mir([-115, 40], s), z = _mir([-85, 55], s), g = &"arms", arm = true})
		d.append({n = StringName(sd + "LowerArm"), p = StringName(sd + "UpperArm"), m = 1.4, cap = [.047, .28, "x"], c = Vector3(s * .6225, 1.455, -.004), j = Vector3(s * .49, 1.455, -.008),
			x = [-50, 50], y = _mir([-145, 0], s), z = [0, 0], g = &"arms", arm = true})
		d.append({n = StringName(sd + "Hand"), p = StringName(sd + "LowerArm"), m = 0.5, box = Vector3(.17, .035, .09), c = Vector3(s * .845, 1.455, 0), j = Vector3(s * .755, 1.455, 0),
			x = [-8, 8], y = _mir([-25, 25], s), z = _mir([-60, 60], s), g = &"arms", arm = true})
		d.append({n = StringName(sd + "UpperLeg"), p = &"Hips", m = 8.0, cap = [.08, .45, "y"], c = Vector3(s * .1, .735, .004), j = Vector3(s * .1, .95, 0),
			x = [-110, 20], y = _mir([-22, 22], s), z = _mir([-20, 38], s), g = &"legs"})
		d.append({n = StringName(sd + "LowerLeg"), p = StringName(sd + "UpperLeg"), m = 3.8, cap = [.058, .43, "y"], c = Vector3(s * .1, .31, .004), j = Vector3(s * .1, .52, .008),
			x = [0, 140], y = [0, 0], z = [0, 0], g = &"legs"})
		d.append({n = StringName(sd + "Foot"), p = StringName(sd + "LowerLeg"), m = 1.2, box = Vector3(.105, .095, .27), c = Vector3(s * .1, .05, .055), j = Vector3(s * .1, .10, 0),
			x = [-20, 45], y = _mir([-6, 6], s), z = _mir([-15, 15], s), g = &"legs"})
	return d


static func _mir(lim: Array, s: float) -> Array:
	return lim if s > 0.0 else [-lim[1], -lim[0]]


# --- build --------------------------------------------------------------------
## The bone each capsule runs to: its length and direction come from the skeleton.
const CAPSULE_TO := {&"UpperArm": &"LowerArm", &"LowerArm": &"Hand", &"UpperLeg": &"LowerLeg", &"LowerLeg": &"Foot"}

## Where each physical bone's collision shape sits, in skeleton space (rest pose).
var centres := {}


## Build the physical skeleton. Joint positions are read from `skel`, so any
## body using these bone names works. `shape_scale` thickens shapes per body
## part (keyed without Left/Right, for example {&"UpperLeg": 1.3}).
func build(skel: Skeleton3D, shape_scale: Dictionary = {}) -> void:
	skeleton = skel
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	skel.add_child(simulator)
	# Arm joints use a frame whose X axis is the skeleton's up axis, so the
	# elbow's big hinge range sits on the joint's twist axis (the stable one).
	var arm_frame := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	for d: Dictionary in defs():
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + String(d.n)
		pb.bone_name = d.n
		pb.mass = d.m
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.collision_layer = LAYER_RAGDOLL
		pb.collision_mask = LAYER_WORLD | LAYER_RAGDOLL
		pb.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
		pb.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
		pb.linear_damp = limp_linear_damp
		pb.angular_damp = limp_angular_damp
		pb.can_sleep = true
		var part := StringName(String(d.n).trim_prefix("Left").trim_prefix("Right"))
		var k: float = shape_scale.get(part, 1.0)
		var bone_rest := skel.get_bone_global_rest(skel.find_bone(d.n))
		var j := bone_rest.origin
		var c: Vector3 = j + (d.c - d.j) * k
		var cs := CollisionShape3D.new()
		if d.has("box"):
			var b := BoxShape3D.new()
			b.size = d.box * k
			cs.shape = b
		elif d.has("sphere"):
			var sp := SphereShape3D.new()
			sp.radius = d.sphere * k
			cs.shape = sp
		else:
			# Capsules run from this joint to the next one down the limb.
			var side := String(d.n).trim_suffix(String(part))
			var to := skel.get_bone_global_rest(skel.find_bone(side + String(CAPSULE_TO[part]))).origin
			var length := j.distance_to(to)
			c = (j + to) * 0.5
			var cp := CapsuleShape3D.new()
			cp.radius = d.cap[0] * k
			cp.height = maxf(d.cap[1] * length / (2.0 * d.c.distance_to(d.j)), cp.radius * 2.0 + 0.01)
			cs.shape = cp
			var y := (to - j).normalized()
			var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
			cs.basis = Basis(x, y, x.cross(y))
		pb.add_child(cs)
		centres[d.n] = c
		pb.body_offset = bone_rest.affine_inverse() * Transform3D(Basis.IDENTITY, c)
		var frame: Basis = arm_frame if d.get("arm", false) else Basis.IDENTITY
		pb.joint_offset = Transform3D(frame, j - c)
		simulator.add_child(pb)
		if d.p != &"":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			var lims: Array = [d.x, d.y, d.z]
			if d.get("arm", false):
				lims = [d.y, d.z, d.x]      # joint x/y/z = skeleton y/z/x
			var axes := ["x", "y", "z"]
			for i in 3:
				var pre: String = "joint_constraints/%s/" % axes[i]
				pb.set(pre + "linear_limit_enabled", true)
				pb.set(pre + "linear_limit_upper", 0.0)
				pb.set(pre + "linear_limit_lower", 0.0)
				pb.set(pre + "angular_limit_enabled", true)
				# Godot's 6DOF angular limits are measured the opposite way
				# round to the right-hand rule, so the range is negated.
				pb.set(pre + "angular_limit_upper", -float(lims[i][0]))
				pb.set(pre + "angular_limit_lower", -float(lims[i][1]))
				pb.set(pre + "angular_limit_softness", 0.5)
				pb.set(pre + "angular_damping", 1.0)
				pb.set(pre + "angular_restitution", 0.0)
			# Jointed neighbours must not collide, or the joint cannot bend.
			var parent_pb: PhysicalBone3D = bones[d.p]
			PhysicsServer3D.body_add_collision_exception(pb.get_rid(), parent_pb.get_rid())
			PhysicsServer3D.body_add_collision_exception(parent_pb.get_rid(), pb.get_rid())
		bones[d.n] = pb
		_order.append(d)
		_info[d.n] = {parent = d.p, group = d.g, frame = frame, tone = -1.0, eq_x = 0.0}
		_tone_scale[d.n] = 1.0
	set_physics_process(false)


func bone_for_segment(seg_bone: StringName) -> PhysicalBone3D:
	return bones.get(seg_bone)


# --- death reactions ----------------------------------------------------------
## Each profile is a set of curves: lists of (time, value) points, smoothly
## interpolated.
##   support  how much of its own weight the clown still carries (0..1)
##   sink     how far the pelvis has been let down, metres
##   legs, spine, neck, arms   muscle tone per body area (0..1)
##   lean     how far the chest is pulled ahead of the pelvis, metres
##            (positive = the way the clown faces, negative = backwards)
##   side     the same, sideways
## and a few numbers:
##   fold       degrees the spine curls forward as it weakens (negative arches back)
##   drift      metres the pelvis moves along the bullet's path
##   drift_fwd  metres the pelvis moves the way the clown faces
##   square     0..1, how firmly the shoulders and hips are kept level, so a
##              forward fall lands flat instead of rolling onto one hip
##   twist      turning speed given to the upper body as it goes (spin falls)
##   arms_wide  true = arms are thrown out sideways, to land spread flat
##   even       true = both knees give together, so the body does not roll
##   buckle     scales how much the knees fold (0 = legs stay straight)
const HEADSHOT_VARIANTS := ["back", "back_flat", "stagger_flat", "sit", "spin", "side", "crumple", "knees", "knees_flat", "knees_hang", "stumble"]
const BODYSHOT_VARIANTS := ["stagger", "blown_back", "double", "double_flat"]

static func profile_headshot(variant: String = "") -> Dictionary:
	if variant == "":
		# "knees" (ends curled on one hip) is left out of the random mix; ask for it by name.
		variant = ["back", "back_flat", "back_flat", "stagger_flat", "sit", "spin", "side", "crumple", "knees_flat", "knees_flat", "knees_flat", "knees_hang", "knees_hang", "stumble", "stumble"].pick_random()
	# Shared opening: the head whips back with no resistance, then the neck
	# catches it and it rebounds while the body still stands on reflex.
	var p := {
		neck = [Vector2(0, 0), Vector2(0.05, 0), Vector2(0.15, 0.7), Vector2(0.45, 0.35), Vector2(0.9, 0.1), Vector2(1.3, 0)],
		arms = [Vector2(0, 0.6), Vector2(0.3, 0.5), Vector2(0.7, 0.15), Vector2(1.0, 0)],
	}
	match variant:
		"knees":
			# Drops hard onto its knees, hangs there a beat, pitches onto its face.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.5, 0.7), Vector2(0.85, 0.65), Vector2(1.2, 0.5), Vector2(1.45, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.45, 0.07), Vector2(0.75, 0.44), Vector2(1.4, 0.5)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.5), Vector2(0.55, 0.1), Vector2(1.0, 0.04), Vector2(1.45, 0)],
				spine = [Vector2(0, 1), Vector2(0.8, 0.7), Vector2(1.15, 0.35), Vector2(1.5, 0.05), Vector2(1.7, 0)],
				lean = [Vector2(0, 0), Vector2(0.75, 0.05), Vector2(1.1, 0.16), Vector2(1.45, 0.36)],
				fold = 22.0, drift = 0.0, drift_fwd = 0.52, drift_time = 1.45,
			})
		"knees_flat":
			# Onto its knees, then straight over: the hips carry on forward and
			# down so it ends stretched out flat on its face.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.45, 0.7), Vector2(0.7, 0.65), Vector2(1.0, 0.5), Vector2(1.2, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.42, 0.08), Vector2(0.66, 0.46), Vector2(0.8, 0.5), Vector2(1.15, 0.82)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.45), Vector2(0.5, 0.08), Vector2(1.2, 0)],
				spine = [Vector2(0, 1), Vector2(0.7, 0.7), Vector2(0.95, 0.4), Vector2(1.2, 0.1), Vector2(1.35, 0)],
				lean = [Vector2(0, 0), Vector2(0.65, 0.06), Vector2(0.85, 0.3), Vector2(1.1, 0.6)],
				square = [Vector2(0, 1), Vector2(1.5, 1), Vector2(1.9, 0)],
				fold = 16.0, drift = 0.0, drift_fwd = 0.95, drift_time = 1.2, even = true,
			})
		"knees_hang":
			# Onto its knees and stays there, swaying, torso sagging, before it
			# finally tips over onto its face.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.45, 0.7), Vector2(0.7, 0.65), Vector2(1.45, 0.55), Vector2(1.7, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.42, 0.08), Vector2(0.66, 0.46), Vector2(1.3, 0.5), Vector2(1.65, 0.82)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.45), Vector2(0.5, 0.08), Vector2(1.7, 0)],
				spine = [Vector2(0, 1), Vector2(0.6, 0.6), Vector2(1.1, 0.3), Vector2(1.6, 0.08), Vector2(1.8, 0)],
				lean = [Vector2(0, 0), Vector2(0.7, 0.04), Vector2(1.25, 0.12), Vector2(1.45, 0.35), Vector2(1.65, 0.6)],
				square = [Vector2(0, 1), Vector2(2.0, 1), Vector2(2.4, 0)],
				fold = 30.0, drift = 0.0, drift_fwd = 0.95, drift_time = 1.7, even = true,
			})
		"stumble":
			# Lurches a step forward on dead legs, drops to its knees, then over.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.5, 0.9), Vector2(0.75, 0.65), Vector2(1.05, 0.5), Vector2(1.25, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0.03), Vector2(0.5, 0.12), Vector2(0.75, 0.46), Vector2(0.9, 0.5), Vector2(1.2, 0.82)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.5), Vector2(0.6, 0.1), Vector2(1.25, 0)],
				spine = [Vector2(0, 1), Vector2(0.5, 0.65), Vector2(0.95, 0.3), Vector2(1.3, 0)],
				lean = [Vector2(0, 0), Vector2(0.3, 0.08), Vector2(0.75, 0.14), Vector2(0.95, 0.35), Vector2(1.2, 0.6)],
				square = [Vector2(0, 1), Vector2(1.6, 1), Vector2(2.0, 0)],
				fold = 20.0, drift = 0.0, drift_fwd = 1.35, drift_time = 1.25, even = true,
			})
		"sit":
			# Legs fold and it drops straight onto its backside, then flops back.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.5, 0.55), Vector2(0.75, 0.4), Vector2(1.0, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.42, 0.1), Vector2(0.7, 0.72)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.3), Vector2(0.5, 0.04), Vector2(1.0, 0)],
				spine = [Vector2(0, 1), Vector2(0.7, 0.75), Vector2(1.1, 0.5), Vector2(1.5, 0.1), Vector2(1.7, 0)],
				lean = [Vector2(0, 0), Vector2(0.7, 0.04), Vector2(1.1, -0.05), Vector2(1.5, -0.3)],
				fold = 30.0, drift = 0.22, drift_time = 0.7, even = true,
			})
		"side":
			# One leg goes: keels over sideways onto its shoulder.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.55, 0.6), Vector2(0.8, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.55, 0.1), Vector2(0.8, 0.4)],
				legs = [Vector2(0, 1), Vector2(0.4, 0.6), Vector2(0.8, 0.2), Vector2(1.0, 0)],
				spine = [Vector2(0, 1), Vector2(0.5, 0.7), Vector2(0.9, 0.3), Vector2(1.2, 0)],
				side = [Vector2(0, 0), Vector2(0.3, 0.04), Vector2(0.55, 0.3), Vector2(0.8, 0.6)],
				fold = 14.0, drift = 0.05, drift_time = 0.8, buckle = 0.5,
			})
		"spin":
			# The shot turns it: twists round as the legs go and lands half on its back.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.6, 0.7), Vector2(0.95, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.55, 0.1), Vector2(0.95, 0.6)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.6), Vector2(0.6, 0.15), Vector2(0.95, 0)],
				spine = [Vector2(0, 1), Vector2(0.4, 0.7), Vector2(0.9, 0.3), Vector2(1.25, 0)],
				lean = [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.95, -0.22)],
				side = [Vector2(0, 0), Vector2(0.25, 0.1), Vector2(0.6, 0.26), Vector2(0.95, 0.1)],
				fold = -4.0, drift = 0.1, drift_time = 0.9, twist = 5.0,
			})
		"back_flat":
			# Goes straight over backwards and ends laid out flat: legs straight,
			# arms thrown wide. A trace of muscle is kept for a few seconds after
			# landing so the limbs settle flat instead of staying bent.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.6, 0.7), Vector2(0.9, 0.2), Vector2(1.0, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.6, 0.1), Vector2(0.95, 0.5)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.6), Vector2(0.6, 0.2), Vector2(1.0, 0.06), Vector2(3.4, 0.06), Vector2(4.0, 0)],
				spine = [Vector2(0, 1), Vector2(0.5, 0.7), Vector2(0.9, 0.3), Vector2(1.2, 0.07), Vector2(3.4, 0.05), Vector2(4.0, 0)],
				arms = [Vector2(0, 0.7), Vector2(0.9, 0.6), Vector2(1.25, 0.25), Vector2(3.4, 0.12), Vector2(4.0, 0)],
				lean = [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.95, -0.3)],
				fold = -4.0, drift = 0.35, drift_time = 0.9, buckle = 0.2, even = true, arms_wide = true,
			}, true)
		"stagger_flat":
			# Reels backwards a few paces on its heels before it goes over and lands flat.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.9, 0.95), Vector2(1.2, 0.6), Vector2(1.45, 0.15), Vector2(1.55, 0)],
				sink = [Vector2(0, 0), Vector2(0.9, 0.06), Vector2(1.2, 0.14), Vector2(1.5, 0.5)],
				legs = [Vector2(0, 1), Vector2(0.9, 0.5), Vector2(1.2, 0.2), Vector2(1.55, 0.06), Vector2(3.9, 0.06), Vector2(4.5, 0)],
				spine = [Vector2(0, 1), Vector2(0.9, 0.7), Vector2(1.4, 0.3), Vector2(1.7, 0.07), Vector2(3.9, 0.05), Vector2(4.5, 0)],
				arms = [Vector2(0, 0.7), Vector2(1.5, 0.6), Vector2(1.85, 0.25), Vector2(3.9, 0.12), Vector2(4.5, 0)],
				lean = [Vector2(0, 0), Vector2(0.3, -0.06), Vector2(0.9, -0.1), Vector2(1.5, -0.32)],
				fold = -6.0, drift = 1.15, drift_time = 1.3, buckle = 0.25, even = true, arms_wide = true,
			}, true)
		"crumple":
			# Legs go at once: straight down in a heap, tipping to one side.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.55, 0.65), Vector2(0.8, 0.25), Vector2(0.95, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.45, 0.07), Vector2(0.7, 0.32), Vector2(0.95, 0.62)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.45), Vector2(0.5, 0.08), Vector2(0.95, 0)],
				spine = [Vector2(0, 1), Vector2(0.4, 0.6), Vector2(0.8, 0.2), Vector2(1.15, 0)],
				side = [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.95, 0.22)],
				fold = 32.0, drift = 0.03, drift_time = 0.8,
			})
		_:
			# Sinks back onto its heels and goes over backwards.
			p.merge({
				support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.65, 0.8), Vector2(0.95, 0.35), Vector2(1.15, 0)],
				sink = [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.5, 0.05), Vector2(0.78, 0.22), Vector2(1.05, 0.5)],
				legs = [Vector2(0, 1), Vector2(0.3, 0.7), Vector2(0.6, 0.22), Vector2(1.0, 0.04), Vector2(1.15, 0)],
				spine = [Vector2(0, 1), Vector2(0.4, 0.8), Vector2(0.9, 0.4), Vector2(1.25, 0.1), Vector2(1.5, 0)],
				lean = [Vector2(0, 0), Vector2(0.5, 0), Vector2(1.1, -0.2)],
				fold = -14.0, drift = 0.12, drift_time = 1.0,
			})
	return p


static func profile_bodyshot(variant: String = "") -> Dictionary:
	if variant == "":
		variant = BODYSHOT_VARIANTS.pick_random()
	if variant == "blown_back":
		# Knocked clean off its feet backwards and lands spread flat.
		return {
			support = [Vector2(0, 0.9), Vector2(0.2, 0.6), Vector2(0.45, 0)],
			sink = [Vector2(0, 0), Vector2(0.45, 0.3)],
			legs = [Vector2(0, 0.6), Vector2(0.4, 0.15), Vector2(0.8, 0.06), Vector2(3.0, 0.06), Vector2(3.6, 0)],
			spine = [Vector2(0, 0.5), Vector2(0.5, 0.2), Vector2(0.9, 0.06), Vector2(3.0, 0.05), Vector2(3.6, 0)],
			neck = [Vector2(0, 0.4), Vector2(0.9, 0)],
			arms = [Vector2(0, 0.7), Vector2(0.6, 0.6), Vector2(0.95, 0.25), Vector2(3.0, 0.12), Vector2(3.6, 0)],
			lean = [Vector2(0, 0), Vector2(0.45, -0.3)],
			fold = -6.0, drift = 0.7, drift_time = 0.45, buckle = 0.2, even = true, arms_wide = true,
		}
	if variant == "double_flat":
		# Doubles over, knees, then slides out flat on its face.
		return {
			support = [Vector2(0, 1), Vector2(0.15, 0.9), Vector2(0.4, 0.65), Vector2(0.75, 0.5), Vector2(0.95, 0)],
			sink = [Vector2(0, 0), Vector2(0.15, 0.05), Vector2(0.45, 0.46), Vector2(0.6, 0.5), Vector2(0.9, 0.82)],
			legs = [Vector2(0, 0.6), Vector2(0.3, 0.12), Vector2(0.95, 0)],
			spine = [Vector2(0, 0.5), Vector2(0.5, 0.3), Vector2(1.05, 0)],
			neck = [Vector2(0, 0.4), Vector2(1.0, 0)],
			arms = [Vector2(0, 0.45), Vector2(0.3, 0.35), Vector2(0.9, 0)],
			lean = [Vector2(0, 0), Vector2(0.2, 0.1), Vector2(0.55, 0.3), Vector2(0.9, 0.6)],
			square = [Vector2(0, 1), Vector2(1.3, 1), Vector2(1.7, 0)],
			fold = 26.0, drift = 0.0, drift_fwd = 0.9, drift_time = 0.95, even = true,
		}
	if variant == "double":
		# Doubles over the wound, drops to its knees and goes down face first.
		return {
			support = [Vector2(0, 1), Vector2(0.15, 0.9), Vector2(0.45, 0.6), Vector2(0.85, 0.4), Vector2(1.05, 0)],
			sink = [Vector2(0, 0), Vector2(0.15, 0.05), Vector2(0.5, 0.44), Vector2(1.05, 0.5)],
			legs = [Vector2(0, 0.6), Vector2(0.3, 0.15), Vector2(1.0, 0)],
			spine = [Vector2(0, 0.5), Vector2(0.5, 0.3), Vector2(1.15, 0)],
			neck = [Vector2(0, 0.4), Vector2(1.1, 0)],
			arms = [Vector2(0, 0.45), Vector2(0.3, 0.35), Vector2(0.9, 0)],
			lean = [Vector2(0, 0), Vector2(0.2, 0.08), Vector2(0.65, 0.2), Vector2(1.05, 0.36)],
			fold = 28.0, drift = 0.0, drift_fwd = 0.46, drift_time = 1.05,
		}
	# Staggers back from the hit and goes down inside a second.
	return {
		support = [Vector2(0, 1), Vector2(0.25, 0.85), Vector2(0.6, 0.4), Vector2(0.85, 0)],
		sink = [Vector2(0, 0), Vector2(0.2, 0.04), Vector2(0.8, 0.55)],
		legs = [Vector2(0, 0.7), Vector2(0.3, 0.3), Vector2(0.85, 0)],
		spine = [Vector2(0, 0.45), Vector2(0.25, 0.3), Vector2(1.0, 0)],
		neck = [Vector2(0, 0.4), Vector2(1.0, 0)],
		arms = [Vector2(0, 0.45), Vector2(0.3, 0.35), Vector2(0.8, 0)],
		lean = [Vector2(0, 0), Vector2(0.6, -0.16)],
		fold = -4.0, drift = 0.30, drift_time = 0.5,
	}


## Shot with a wall close behind: thrown back against it, then slides down it
## to end slumped at the bottom. `gap` is how far away the wall is, in metres.
static func profile_wall_slide(gap: float) -> Dictionary:
	return {
		support = [Vector2(0, 1), Vector2(0.3, 1), Vector2(0.6, 0.9), Vector2(2.1, 0.75), Vector2(2.6, 0)],
		sink = [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.7, 0.08), Vector2(2.2, 0.64)],
		legs = [Vector2(0, 1), Vector2(0.3, 0.5), Vector2(0.6, 0.12), Vector2(2.6, 0)],
		spine = [Vector2(0, 1), Vector2(0.6, 0.8), Vector2(2.2, 0.5), Vector2(3.0, 0.12), Vector2(3.6, 0)],
		neck = [Vector2(0, 0), Vector2(0.05, 0), Vector2(0.15, 0.7), Vector2(0.45, 0.3), Vector2(1.2, 0.08), Vector2(2.4, 0)],
		arms = [Vector2(0, 0.5), Vector2(0.3, 0.3), Vector2(0.8, 0.05), Vector2(1.4, 0)],
		lean = [Vector2(0, 0), Vector2(0.3, -0.12), Vector2(2.2, -0.2)],
		fold = 10.0, drift = maxf(gap - 0.3, 0.0), drift_time = 0.3, even = true,
	}


static func profile_tumble() -> Dictionary:
	# Killed mid-stride: the legs fold under it and its own momentum throws it
	# forward, which is what sends bodies rolling down stairs.
	return {
		support = [Vector2(0, 0.55), Vector2(0.12, 0.3), Vector2(0.3, 0)],
		legs = [Vector2(0, 0.35), Vector2(0.3, 0)],
		spine = [Vector2(0, 0.45), Vector2(0.5, 0)],
		neck = [Vector2(0, 0.3), Vector2(0.5, 0)],
		arms = [Vector2(0, 0.5), Vector2(0.25, 0.3), Vector2(0.6, 0)],
		fold = 18.0, drift = 0.0, drift_time = 0.1,
	}


static func profile_heavy(flat: bool = false) -> Dictionary:
	# Shotgun-class hit: thrown off its feet, almost no reflex left.
	if flat:
		# Same, but the limbs settle out straight: lands spread flat on its back.
		return {
			support = [Vector2(0, 0.35), Vector2(0.22, 0)],
			legs = [Vector2(0, 0.3), Vector2(0.3, 0.07), Vector2(3.0, 0.06), Vector2(3.6, 0)],
			spine = [Vector2(0, 0.3), Vector2(0.45, 0.06), Vector2(3.0, 0.05), Vector2(3.6, 0)],
			neck = [Vector2(0, 0.25), Vector2(0.5, 0)],
			arms = [Vector2(0, 0.7), Vector2(0.6, 0.55), Vector2(0.95, 0.25), Vector2(3.0, 0.12), Vector2(3.6, 0)],
			drift = 0.0, drift_time = 0.1, buckle = 0.15, even = true, arms_wide = true,
		}
	return {
		support = [Vector2(0, 0.35), Vector2(0.22, 0)],
		legs = [Vector2(0, 0.3), Vector2(0.3, 0)],
		spine = [Vector2(0, 0.3), Vector2(0.45, 0)],
		neck = [Vector2(0, 0.25), Vector2(0.5, 0)],
		arms = [Vector2(0, 0.15), Vector2(0.4, 0)],
		drift = 0.0, drift_time = 0.1,
	}


static func profile_blast() -> Dictionary:
	# Caught by an explosion: no balance at all, the body just goes where it is
	# thrown, arms flailing for a moment.
	return {
		support = [Vector2(0, 0.0)],
		legs = [Vector2(0, 0.12), Vector2(0.3, 0)],
		spine = [Vector2(0, 0.15), Vector2(0.35, 0.04), Vector2(2.0, 0)],
		neck = [Vector2(0, 0.1), Vector2(0.3, 0)],
		arms = [Vector2(0, 0.3), Vector2(0.5, 0.05), Vector2(1.5, 0)],
		drift = 0.0, drift_time = 0.1, arms_wide = true,
	}


static func profile_limp() -> Dictionary:
	# Already on the floor and out of strength (a crawler dying).
	return {
		support = [Vector2(0, 0.0)],
		spine = [Vector2(0, 0.2), Vector2(0.6, 0)],
		neck = [Vector2(0, 0.25), Vector2(0.9, 0)],
		arms = [Vector2(0, 0.15), Vector2(0.6, 0)],
		drift = 0.0, drift_time = 0.1,
	}


## A frozen corpse comes back to life as a ragdoll (an explosion reached it).
func wake() -> void:
	if active:
		return
	simulator.physical_bones_start_simulation()
	active = true
	limp = true
	is_settled = false
	_still_time = 0.0
	set_physics_process(true)


## Start simulating. `hit_dir` is the bullet's travel direction (world space).
func start(profile: Dictionary, hit_dir: Vector3 = Vector3.ZERO, velocity: Vector3 = Vector3.ZERO) -> void:
	if active:
		return
	_profile = _vary(profile)
	profile = _profile
	time = 0.0
	limp = false
	is_settled = false
	_still_time = 0.0
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	simulator.physical_bones_start_simulation()
	active = true
	# Each joint's muscle is a spring whose rest position is the pose the clown
	# was in when it died. Tone scales the spring; at zero only friction is left.
	for d: Dictionary in _order:
		var pb: PhysicalBone3D = bones.get(d.n)
		if pb == null or d.p == &"" or not bones.has(d.p):
			continue
		var frame: Basis = _info[d.n].frame
		var rel: Basis = (bones[d.p].global_basis.inverse() * pb.global_basis).orthonormalized()
		var eq := -(frame.inverse() * rel * frame).get_euler(EULER_ORDER_ZYX)
		var axes := ["x", "y", "z"]
		for i in 3:
			var pre: String = "joint_constraints/%s/" % axes[i]
			pb.set(pre + "angular_equilibrium_point", eq[i])
			pb.set(pre + "angular_spring_enabled", true)
		# Arms jerk out to a random pose on reflex, then go slack wherever they are,
		# so they end up thrown about instead of pinned to the sides.
		var part := String(d.n).trim_prefix("Left").trim_prefix("Right")
		if arm_fling > 0.0 and (part == "UpperArm" or part == "LowerArm"):
			var s := 1.0 if String(d.n).begins_with("Left") else -1.0
			if part == "UpperArm" and profile.get("arms_wide", false):
				eq.y -= s * deg_to_rad(randf_range(55.0, 110.0)) * arm_fling   # straight out to the side
				eq.x -= s * deg_to_rad(randf_range(0.0, 20.0)) * arm_fling
			elif part == "UpperArm":
				eq.y -= s * deg_to_rad(randf_range(30.0, 100.0)) * arm_fling   # lift out sideways
				eq.x += s * deg_to_rad(randf_range(-25.0, 60.0)) * arm_fling   # swing forward or back
			else:
				eq.x += s * deg_to_rad(randf_range(0.0, 25.0) if profile.get("arms_wide", false) else randf_range(10.0, 85.0)) * arm_fling    # bend the elbow
			pb.set("joint_constraints/x/angular_equilibrium_point", eq.x)
			pb.set("joint_constraints/y/angular_equilibrium_point", eq.y)
		_info[d.n].tone = -1.0
		_info[d.n].eq_x = eq.x
	_root_target = bones[&"Hips"].global_position
	_chest_offset = bones[&"Chest"].global_position - _root_target if bones.has(&"Chest") else Vector3.ZERO
	var flat := Vector3(hit_dir.x, 0, hit_dir.z)
	_root_drift = flat.normalized() * float(profile.get("drift", 0.0)) if flat.length() > 0.01 else Vector3.ZERO
	var hb: Basis = bones[&"Hips"].global_basis
	_fwd = Vector3(hb.z.x, 0, hb.z.z).normalized()
	_level_axis = Vector3(hb.x.x, 0, hb.x.z).normalized()
	_left = _level_axis * (1.0 if randf() < 0.5 else -1.0)
	for pb: PhysicalBone3D in bones.values():
		pb.gravity_scale = fall_weight
	var twist := float(profile.get("twist", 0.0))
	if twist != 0.0 and bones.has(&"Chest"):
		var spin_dir := -1.0 if _left.dot(_level_axis) > 0.0 else 1.0
		PhysicsServer3D.body_set_state(bones[&"Chest"].get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.UP * twist * spin_dir)
	_root_drift += _fwd * float(profile.get("drift_fwd", 0.0))
	_root_drift_time = float(profile.get("drift_time", 0.3))
	# A clown killed on the move keeps going: every bone starts with its speed.
	if velocity.length() > 0.05:
		for pb: PhysicalBone3D in bones.values():
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	_apply_tone()
	set_physics_process(true)


## No two deaths the same: stretch the timing and the reach of a profile a little.
func _vary(profile: Dictionary) -> Dictionary:
	var p := profile.duplicate(true)
	if variation <= 0.0:
		return p
	var t_scale := randf_range(1.0 - variation, 1.0 + variation * 0.7)
	var reach := randf_range(1.0 - variation, 1.0 + variation)
	for key in p:
		if p[key] is Array:
			var pts: Array = p[key]
			for i in pts.size():
				var v: Vector2 = pts[i]
				# The first 0.3s (the snap and the beat of standing) keeps its timing.
				var t := v.x if v.x <= 0.3 else 0.3 + (v.x - 0.3) * t_scale
				pts[i] = Vector2(t, v.y * (reach if key in ["lean", "side"] else 1.0))
	for key in ["drift", "drift_fwd", "fold"]:
		if p.has(key):
			p[key] = float(p[key]) * randf_range(1.0 - variation, 1.0 + variation)
	if p.has("drift_time"):
		p["drift_time"] = float(p["drift_time"]) * t_scale
	return p


## Push one bone. `impulse` is in newton-seconds, `at` is a world position.
func apply_hit(bone: StringName, impulse: Vector3, at: Vector3) -> void:
	var pb: PhysicalBone3D = bones.get(bone)
	if pb == null or not active:
		return
	PhysicsServer3D.body_apply_impulse(pb.get_rid(), impulse, at - pb.global_position)
	if is_settled:
		is_settled = false
		_still_time = 0.0


## Weaken one bone's muscles (for example a leg that has just been shot).
func weaken(bone: StringName, scale: float) -> void:
	if _tone_scale.has(bone):
		_tone_scale[bone] = min(_tone_scale[bone], scale)


## Remove bones from the simulation (used when a limb is blown off).
func remove_bones(names: Array) -> void:
	for n: StringName in names:
		var pb: PhysicalBone3D = bones.get(n)
		if pb:
			bones.erase(n)
			pb.queue_free()


## Where a bone really is right now, in skeleton space. While the ragdoll is
## running the Skeleton3D itself only reports the un-simulated pose.
func bone_pose(bone_idx: int) -> Transform3D:
	if not active:
		return skeleton.get_bone_global_pose(bone_idx)
	var chain := Transform3D.IDENTITY
	var i := bone_idx
	while i >= 0:
		var pb: PhysicalBone3D = bones.get(StringName(skeleton.get_bone_name(i)))
		if pb:
			return skeleton.global_transform.affine_inverse() * pb.global_transform * pb.body_offset.affine_inverse() * chain
		chain = skeleton.get_bone_pose(i) * chain
		i = skeleton.get_bone_parent(i)
	return chain


func _apply_tone() -> bool:
	var any := false
	var axes := ["x", "y", "z"]
	for d: Dictionary in _order:
		var pb: PhysicalBone3D = bones.get(d.n)
		if pb == null or d.p == &"" or not bones.has(d.p):
			continue
		var tone: float = _sample(d.g) * _tone_scale[d.n]
		if tone > 0.001:
			any = true
		if absf(tone - _info[d.n].tone) < 0.004:
			continue
		_info[d.n].tone = tone
		var m: Array = MUSCLE[StringName(String(d.n).trim_prefix("Left").trim_prefix("Right"))]
		# A trace of stiffness is kept so the joint stays a soft spring, never a rigid motor.
		var k: float = maxf(m[0] * tone * muscle_strength, 0.4)
		var c: float = m[1] * tone * muscle_strength + m[2] * dead_joint_friction
		for i in 3:
			var pre: String = "joint_constraints/%s/" % axes[i]
			pb.set(pre + "angular_spring_stiffness", k)
			pb.set(pre + "angular_spring_damping", c)
		# Legs give way as they weaken: the knee folds and the hip follows.
		var part := String(d.n).trim_prefix("Left").trim_prefix("Right")
		if part == "LowerLeg" or part == "UpperLeg":
			# One knee normally goes first, which rolls the body; "even" keeps it square.
			var side_bias := 1.0 if String(d.n).begins_with("Left") else (0.93 if _profile.get("even", false) else 0.72)
			var give: float = (1.0 - clampf(tone, 0.0, 1.0)) * side_bias * float(_profile.get("buckle", 1.0))
			var fold := -deg_to_rad(knee_buckle) * give if part == "LowerLeg" else deg_to_rad(hip_buckle) * give
			pb.set("joint_constraints/x/angular_equilibrium_point", _info[d.n].eq_x + fold)
		# The spine curls (or arches) as it loses strength, which sets the way the body falls.
		elif part == "Spine" or part == "Chest":
			# Most of the bend is at the abdomen (the Spine joint), less at the ribs.
			var share := 1.0 if part == "Spine" else 0.45
			var curl: float = deg_to_rad(float(_profile.get("fold", 0.0))) * share * (1.0 - clampf(tone, 0.0, 1.0))
			pb.set("joint_constraints/x/angular_equilibrium_point", _info[d.n].eq_x - curl)
	return any


func _physics_process(delta: float) -> void:
	if not active:
		return
	time += delta * fall_speed
	var ps := PhysicsServer3D
	var support := _sample(&"support")
	var any_tone := _apply_tone() or support > 0.001

	# Two "strings" stand in for balance while the clown can still carry itself:
	# one takes the body's weight at the pelvis, one keeps the chest over it.
	var hips: PhysicalBone3D = bones.get(&"Hips")
	if hips and support > 0.001:
		var total := 0.0
		for pb: PhysicalBone3D in bones.values():
			total += pb.mass
		var target := _root_target + _root_drift * smoothstep(0.0, _root_drift_time, time) + Vector3.DOWN * _sample(&"sink")
		var v: Vector3 = ps.body_get_state(hips.get_rid(), ps.BODY_STATE_LINEAR_VELOCITY)
		var acc := (target - hips.global_position) * support_stiffness - v * support_damping + Vector3.UP * _gravity * fall_weight
		ps.body_apply_central_force(hips.get_rid(), acc * total * support)
		var chest: PhysicalBone3D = bones.get(&"Chest")
		var upright := minf(support, _sample(&"spine"))
		if chest and upright > 0.001:
			var cv: Vector3 = ps.body_get_state(chest.get_rid(), ps.BODY_STATE_LINEAR_VELOCITY)
			var lean := _fwd * _sample(&"lean") + _left * _sample(&"side")
			var pull := (hips.global_position + _chest_offset + lean - chest.global_position) * upright_stiffness - cv * upright_damping
			pull.y = 0.0
			ps.body_apply_central_force(chest.get_rid(), pull * 32.0 * upright)

	# Keep shoulders and hips level through a forward fall so it lands flat.
	var square := _sample(&"square")
	if square > 0.001:
		for spec: Array in [[&"Chest", 150.0, 12.0], [&"Hips", 190.0, 14.0]]:
			var pb: PhysicalBone3D = bones.get(spec[0])
			if pb == null:
				continue
			var x := pb.global_basis.x.normalized()
			var w: Vector3 = ps.body_get_state(pb.get_rid(), ps.BODY_STATE_ANGULAR_VELOCITY)
			var w_off := w - x * w.dot(x)       # leave pitching forward alone
			ps.body_apply_torque(pb.get_rid(), (x.cross(_level_axis) * spec[1] - w_off * spec[2]) * square)

	var moving := 0.0
	for pb: PhysicalBone3D in bones.values():
		var rid := pb.get_rid()
		var v: Vector3 = ps.body_get_state(rid, ps.BODY_STATE_LINEAR_VELOCITY)
		if v.length() > max_bone_speed:
			ps.body_set_state(rid, ps.BODY_STATE_LINEAR_VELOCITY, v.normalized() * max_bone_speed)
		var w: Vector3 = ps.body_get_state(rid, ps.BODY_STATE_ANGULAR_VELOCITY)
		if w.length() > max_bone_spin:
			ps.body_set_state(rid, ps.BODY_STATE_ANGULAR_VELOCITY, w.normalized() * max_bone_spin)
		moving = maxf(moving, v.length())

	if not any_tone and not limp:
		limp = true
		went_limp.emit()
		if randf() < twitch_chance:
			_twitch_left = randf_range(1.0, 2.2)
			_twitch_bone = [&"LeftLowerLeg", &"RightLowerLeg", &"LeftFoot", &"RightFoot", &"LeftLowerArm", &"RightLowerArm", &"LeftHand", &"RightHand"].pick_random()
	# Dying nerves: one limb jerks a few times after the body is down.
	if _twitch_left > 0.0:
		_twitch_left -= delta
		_twitch_next -= delta
		var tb: PhysicalBone3D = bones.get(_twitch_bone)
		if tb and _twitch_next <= 0.0:
			_twitch_next = randf_range(0.1, 0.45)
			var kick := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			ps.body_apply_torque_impulse(tb.get_rid(), kick * tb.mass * randf_range(0.25, 0.6) * minf(_twitch_left, 1.0))
			_still_time = 0.0
	if limp and not is_settled:
		_still_time = _still_time + delta if moving < 0.12 else 0.0
		if _still_time > 0.6 or time > 14.0:
			is_settled = true
			settled.emit()


## Stop simulating and keep the body exactly where it lies (cheap corpse).
func freeze() -> void:
	if not active:
		return
	var poses := []
	for i in skeleton.get_bone_count():
		poses.append(bone_pose(i))
	simulator.physical_bones_stop_simulation()
	active = false
	for i in skeleton.get_bone_count():      # parents come before children
		skeleton.set_bone_global_pose(i, poses[i])
	set_physics_process(false)


func _sample(key: StringName) -> float:
	var pts: Array = _profile.get(key, [])
	if pts.is_empty():
		return 0.0
	if time <= pts[0].x:
		return pts[0].y
	for i in range(1, pts.size()):
		if time < pts[i].x:
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			return lerpf(a.y, b.y, smoothstep(a.x, b.x, time))
	return pts[-1].y


## Rotation that takes `current` to `desired`, as a world-space axis * angle.
static func _rot_error(desired: Basis, current: Basis) -> Vector3:
	var q := (desired * current.inverse()).orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	if angle < 0.0001:
		return Vector3.ZERO
	return Vector3(q.x, q.y, q.z).normalized() * angle
