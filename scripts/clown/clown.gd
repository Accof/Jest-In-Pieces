class_name Clown
extends Node3D
## One clown enemy: model, hit zones, health, and what happens when it is shot.

signal died(clown: Clown)
## Emitted every time this clown is shot, fatal or not.
signal hurt(clown: Clown)

const MODEL := preload("res://art/clown/clown.glb")

@export var max_health := 100.0
## Damage one shot must do to a limb or the head before it can be blown off.
@export var dismember_damage := 55.0
## Damage one shot must do to the torso or head to blow a hole in it.
@export var blast_damage := 44.0
## Seconds a settled corpse keeps simulating before it is frozen in place.
@export var freeze_after := 6.0

## Damage multiplier for each hit zone (keyed by physical bone).
const ZONE_DAMAGE := {
	&"Neck": 4.0, &"Chest": 1.0, &"Spine": 1.0, &"Hips": 0.9,
	&"UpperArm": 0.55, &"LowerArm": 0.45, &"Hand": 0.3,
	&"UpperLeg": 0.7, &"LowerLeg": 0.55, &"Foot": 0.35,
}

var health := 0.0
var dead := false
var last_hit_zone := &""         # where the killing shot landed
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var ragdoll: ClownRagdoll
var gore: ClownGore

## Leave empty for a random fall each time, or name one to force it
## ("back", "back_flat", "stagger_flat", "sit", "spin", "side", "crumple", "knees",
## "knees_flat", "knees_hang", "stumble", "wall_slide" for headshots;
## "stagger", "blown_back", "double", "double_flat" for body shots).
@export var force_variant := ""
## How hard non-lethal hits knock the clown about. 0 turns flinching off.
@export var flinch_strength := 1.0

var _shot_id := -1
var _shot_damage := {}      # segment -> damage taken from the current shot
var _shot_blasted := {}     # segments already blown open by the current shot
var _head_open := false     # part of the skull is already gone


func _ready() -> void:
	health = max_health
	var model := MODEL.instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	mesh = model.find_children("*", "MeshInstance3D", true, false)[0]
	mesh.layers = 2                     # keeps floor/wall decals off the body
	_model = model
	_idle_pose()
	for b: String in POSED_BONES:
		var bi := skeleton.find_bone(b)
		_base_rot[bi] = skeleton.get_bone_pose_rotation(bi)
	set_process(false)
	ragdoll = ClownRagdoll.new()
	add_child(ragdoll)
	ragdoll.build(skeleton)
	for pb: PhysicalBone3D in ragdoll.bones.values():
		pb.set_meta(&"clown", self)
	gore = ClownGore.new()
	add_child(gore)
	gore.setup(self)
	ragdoll.settled.connect(_on_settled)


## Called by weapons. `info` keys:
##   collider (PhysicalBone3D), position, direction (bullet travel), damage,
##   impulse (N*s), heavy (bool), can_dismember (bool), shot_id (int)
func hit(info: Dictionary) -> void:
	var pb := info.collider as PhysicalBone3D
	if pb == null:
		return
	var bone := StringName(pb.bone_name)
	var zone := _zone(bone)
	var dir: Vector3 = info.direction.normalized()
	var raw: float = info.damage
	var dmg: float = raw * ZONE_DAMAGE.get(zone, 1.0)
	var amount := clampf(raw / 35.0, 0.3, 1.6) * float(info.get("blood", 1.0))

	gore.add_wound(bone, info.position, raw)
	Blood.spawn_hit(info.position, dir, amount)

	# Shotgun-class shots add up across their pellets. Enough of them on one
	# part blows it open; on a limb or (sometimes) the head, takes it off.
	var severed := false
	if info.get("can_dismember", false):
		var sid: int = info.get("shot_id", -1)
		if sid != _shot_id:
			_shot_id = sid
			_shot_damage.clear()
			_shot_blasted.clear()
		var seg := gore.segment_of(bone)
		_shot_damage[seg] = _shot_damage.get(seg, 0.0) + raw
		var total: float = _shot_damage[seg]
		if zone in [&"Chest", &"Spine", &"Hips"]:
			if total >= blast_damage and not _shot_blasted.has(seg):
				_shot_blasted[seg] = true
				gore.blast(bone, info.position, dir, clampf(0.07 + total * 0.0006, 0.08, 0.13))
		elif zone == &"Neck":
			if total >= dismember_damage and gore.can_sever(bone) and (_head_open or randf() < 0.5) and not _shot_blasted.has(&"off"):
				severed = true
			elif total >= blast_damage * 0.6 and not _shot_blasted.has(seg):
				# Part of the skull goes instead of the whole head.
				_shot_blasted[seg] = true
				_shot_blasted[&"off"] = true
				_head_open = true
				gore.blast(bone, info.position, dir, clampf(0.045 + total * 0.0006, 0.05, 0.085))
		elif gore.can_sever(bone) and total >= dismember_damage:
			severed = true

	var was_dead := dead
	if not dead:
		health -= dmg
		if health <= 0.0 or _head_open or (severed and zone in [&"UpperLeg", &"LowerLeg", &"Neck"]):
			_die(info, zone)
	hurt.emit(self)
	if not dead:
		_flinch_from(info.position, dir, raw * (1.8 if severed else 1.0))
	if dead:
		var impulse: Vector3 = dir * float(info.get("impulse", 12.0))
		if was_dead:
			impulse *= 0.6              # a corpse soaks up a shot, it does not leap
		elif zone == &"Neck" and not info.get("heavy", false):
			impulse = dir * 27.0 + Vector3.UP * 3.0   # a sharp whip of the head, not a launch
		ragdoll.apply_hit(bone, impulse, info.position)
	if severed:
		gore.sever(bone, dir * float(info.get("impulse", 12.0)))


func _die(info: Dictionary, zone: StringName) -> void:
	dead = true
	var profile: Dictionary
	var wall_gap := _wall_behind(info.direction)
	if force_variant == "wall_slide" and wall_gap < 0.0:
		wall_gap = 0.5
	if not info.get("heavy", false) and wall_gap >= 0.0 and (force_variant == "wall_slide" or (force_variant == "" and randf() < 0.8)):
		profile = ClownRagdoll.profile_wall_slide(wall_gap)
	elif info.get("heavy", false):
		profile = ClownRagdoll.profile_heavy(force_variant == "heavy_flat" or (force_variant == "" and randf() < 0.45))
	elif force_variant == "" and velocity.length() > 1.5 and randf() < 0.6:
		profile = ClownRagdoll.profile_tumble()
	elif zone == &"Neck":
		profile = ClownRagdoll.profile_headshot(force_variant)
	else:
		# A gut shot usually folds the clown forward; a chest shot throws it back.
		var v := force_variant
		if v == "":
			v = ("double" if randf() < 0.15 else "double_flat") if (zone in [&"Spine", &"Hips"] and randf() < 0.7) or randf() < 0.2 else ["stagger", "blown_back"].pick_random()
		profile = ClownRagdoll.profile_bodyshot(v)
	if zone in [&"UpperLeg", &"LowerLeg", &"Foot"]:
		var side := "Left" if String(info.collider.bone_name).begins_with("Left") else "Right"
		for part in ["UpperLeg", "LowerLeg", "Foot"]:
			ragdoll.weaken(StringName(side + part), 0.15)
	ragdoll.start(profile, info.direction, velocity)
	gore.start_bleeding()
	last_hit_zone = zone
	died.emit(self)


func _on_settled() -> void:
	await get_tree().create_timer(freeze_after).timeout
	if is_instance_valid(self) and ragdoll.is_settled:
		ragdoll.freeze()


# --- living pose ----------------------------------------------------------------
# There are no animation clips yet. A living clown is posed in code every frame:
# a walk cycle, an attack or aiming arm, and flinches from hits, layered on top
# of the standing pose.
const POSED_BONES := ["Spine", "Chest", "Neck", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
	"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm"]
const FLINCH_BONES := [["Spine", 0.4], ["Chest", 0.45], ["Neck", 0.55]]

## Set by the AI: how far through a stride (radians), how much it is walking
## (0..1), and how far the right arm is into a swing or raised to aim (0..1).
var walk_phase := 0.0
var walk_amount := 0.0
var run_amount := 0.0               # 0 = shambling walk, 1 = flat-out run
var attack_amount := 0.0
var aim_amount := 0.0
## Movement of the whole clown, so a death carries its momentum.
var velocity := Vector3.ZERO
var has_gun := false
var always_pose := false            # true while an AI is driving this clown

var _model: Node3D
var _base_rot := {}
var _flinch := Vector3.ZERO         # upper-body rotation, skeleton space (axis * angle)
var _flinch_vel := Vector3.ZERO
var _stagger := Vector3.ZERO        # model offset, metres
var _stagger_vel := Vector3.ZERO
var stagger_time := 0.0             # seconds the AI should stay knocked off its stride


func _flinch_from(world_pos: Vector3, dir: Vector3, damage: float) -> void:
	if flinch_strength <= 0.0:
		return
	var inv := skeleton.global_transform.affine_inverse()
	var p := inv * world_pos
	var d := (inv.basis * dir).normalized()
	var power := clampf(damage / 34.0, 0.35, 1.8) * flinch_strength
	# The hit turns the body about its middle, the way a real shove would:
	# high hits rock it back, low hits fold it forward, side hits spin it.
	var kick := (p - Vector3(0, 1.1, 0)).cross(d)
	if kick.length() < 0.05:
		kick = Vector3(-0.2, 0, 0)
	_flinch_vel += (kick * 22.0 * power).limit_length(11.0)
	_stagger_vel += Vector3(d.x, 0, d.z) * 1.3 * power
	stagger_time = maxf(stagger_time, 0.18 + 0.12 * power)
	set_process(true)


func _process(delta: float) -> void:
	if dead:
		set_process(false)
		return
	stagger_time = maxf(stagger_time - delta, 0.0)
	_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 13.0) * delta
	_flinch = (_flinch + _flinch_vel * delta).limit_length(0.6)
	_stagger_vel += (-_stagger * 70.0 - _stagger_vel * 13.0) * delta
	_stagger += _stagger_vel * delta
	for bi: int in _base_rot:
		skeleton.set_bone_pose_rotation(bi, _base_rot[bi])
	# Walk: a heavy-footed shamble, leaning into it.
	if walk_amount > 0.01:
		var sw := sin(walk_phase)
		var stride := lerpf(30.0, 50.0, run_amount)
		var knee := lerpf(48.0, 85.0, run_amount)
		var arm := lerpf(22.0, 48.0, run_amount)
		_turn("Spine", Vector3.RIGHT, deg_to_rad(lerpf(7.0, 20.0, run_amount)) * walk_amount)
		_turn("Spine", Vector3.BACK, deg_to_rad(3.0) * sw * walk_amount)
		_turn("LeftUpperLeg", Vector3.RIGHT, deg_to_rad(-stride) * sw * walk_amount)
		_turn("RightUpperLeg", Vector3.RIGHT, deg_to_rad(stride) * sw * walk_amount)
		_turn("LeftLowerLeg", Vector3.RIGHT, deg_to_rad(knee) * maxf(0.0, cos(walk_phase)) * walk_amount)
		_turn("RightLowerLeg", Vector3.RIGHT, deg_to_rad(knee) * maxf(0.0, -cos(walk_phase)) * walk_amount)
		_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(arm) * sw * walk_amount)
		_turn("LeftLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * walk_amount)
		if attack_amount < 0.01 and aim_amount < 0.01:
			_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-arm) * sw * walk_amount)
			_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * walk_amount)
	# Right arm: swung overhead to hit, or held out to aim.
	if attack_amount > 0.01:
		_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-135.0) * attack_amount)
		_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-35.0) * attack_amount)
		_turn("Chest", Vector3.RIGHT, deg_to_rad(12.0) * attack_amount)
	elif aim_amount > 0.01:
		_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-84.0) * aim_amount)
	if _flinch.length() > 0.0005:
		for b: Array in FLINCH_BONES:
			_turn(b[0], _flinch.normalized(), _flinch.length() * b[1])
	_model.position = _stagger
	if not always_pose and _flinch.length() < 0.002 and _flinch_vel.length() < 0.02 and _stagger.length() < 0.002 and _stagger_vel.length() < 0.02:
		_flinch = Vector3.ZERO
		_stagger = Vector3.ZERO
		_model.position = Vector3.ZERO
		set_process(false)


## Put a pistol in the clown's right hand.
func give_gun() -> void:
	has_gun = true
	var att := BoneAttachment3D.new()
	att.bone_name = "RightHand"
	skeleton.add_child(att)
	var gun := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.05, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.metallic = 0.8
	mat.roughness = 0.35
	box.material = mat
	gun.mesh = box
	gun.layers = 2
	att.add_child(gun)
	# Sit it in the palm, barrel along the fingers, whatever the bone's own axes are.
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("RightHand"))
	gun.transform = hand.affine_inverse() * Transform3D(Basis.IDENTITY, hand.origin + Vector3(-0.1, -0.02, 0.0))


## World position of the gun's muzzle (roughly the right hand).
func muzzle_position() -> Vector3:
	var hand: PhysicalBone3D = ragdoll.bones.get(&"RightHand")
	return hand.global_position if hand else global_position + Vector3.UP * 1.3


## Distance to a wall close behind the clown along the shot, or -1 if there is
## none or the clown was not shot from the front.
func _wall_behind(shot_dir: Vector3) -> float:
	var back := Vector3(shot_dir.x, 0, shot_dir.z)
	if back.length() < 0.01:
		return -1.0
	back = back.normalized()
	if global_basis.z.dot(back) > -0.3:          # not facing the shooter
		return -1.0
	var from := global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + back * 1.25, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or absf(hit.normal.y) > 0.3:
		return -1.0
	return from.distance_to(hit.position)


static func _zone(bone: StringName) -> StringName:
	var s := String(bone)
	return StringName(s.trim_prefix("Left").trim_prefix("Right"))


## Temporary standing pose until there are animations: arms down by the sides.
func _idle_pose() -> void:
	for s: float in [1.0, -1.0]:
		var side := "Left" if s > 0.0 else "Right"
		_turn(side + "UpperArm", Vector3.BACK, deg_to_rad(-76.0) * s)
		_turn(side + "LowerArm", Vector3.RIGHT, deg_to_rad(-14.0))
	_turn("Head", Vector3.RIGHT, deg_to_rad(6.0))


## Rotate a bone about a skeleton-space axis, keeping its children attached.
func _turn(bone_name: String, axis: Vector3, angle: float) -> void:
	var i := skeleton.find_bone(bone_name)
	var parent := skeleton.get_bone_parent(i)
	var parent_global := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var current := skeleton.get_bone_global_pose(i).basis
	var wanted := Basis(axis, angle) * current
	skeleton.set_bone_pose_rotation(i, (parent_global.inverse() * wanted).get_rotation_quaternion())
