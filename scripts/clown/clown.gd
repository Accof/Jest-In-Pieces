class_name Clown
extends Node3D
## One clown enemy: model, hit zones, health, and what happens when it is shot.

signal died(clown: Clown)
## Emitted every time this clown is shot, fatal or not.
signal hurt(clown: Clown)

## Every enemy body shares the clown's skeleton names and segment layout, so
## the ragdoll, deaths and gore all work on each of them.
const BODIES := {
	"clown": {
		model = "res://art/clown/clown.glb", gibs = "res://art/clown/clown_gibs.glb",
		rest_min = Vector3(-0.953, -0.005, -0.15493), rest_size = Vector3(1.906, 1.88737, 0.35291),
		shapes = {},
	},
	"witzsoldat": {
		model = "res://art/witzsoldat/witzsoldat.glb", gibs = "res://art/witzsoldat/witzsoldat_gibs.glb",
		rest_min = Vector3(-0.91675, -0.005, -0.28225), rest_size = Vector3(1.83328, 1.91, 0.56441),
		helmet = "res://art/witzsoldat/witzsoldat_helmet.glb",
		helmet_center = Vector3(0.0, 1.80985, 0.04376), helmet_size = Vector3(0.268, 0.232, 0.288),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.25, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
	},
}

## Which body this enemy wears (a key of BODIES). Set before adding to the tree.
@export var body := "clown"
## Chance a headshot knocks the helmet off (bodies with a helmet only).
@export var helmet_pop_chance := 0.5

var spec: Dictionary

@export var max_health := 100.0
## Damage one shot must do to a limb or the head before it can be blown off.
@export var dismember_damage := 55.0
## Damage one shot must do to the torso or head to blow a hole in it.
@export var blast_damage := 44.0
## Seconds a settled corpse keeps simulating before it is frozen in place.
@export var freeze_after := 6.0
## Chance that a clown caught close to an explosion is torn in half and lives,
## crawling away on its arms until it bleeds out.
@export var crawl_chance := 0.4
## True while this clown is a torso dragging itself along the floor.
var crawling := false

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
	add_to_group(&"clowns")
	health = max_health
	spec = BODIES[body]
	var model := (load(spec.model) as PackedScene).instantiate()
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
	ragdoll.build(skeleton, spec.shapes)
	for pb: PhysicalBone3D in ragdoll.bones.values():
		pb.set_meta(&"clown", self)
	if spec.has("helmet"):
		_put_on_helmet()
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

	# A headshot may knock the helmet clean off; it still goes through.
	if zone == &"Neck" and has_helmet and randf() < helmet_pop_chance:
		knock_off_helmet(dir, info.position)
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
				knock_off_helmet(dir, info.position)
				gore.blast(bone, info.position, dir, clampf(0.045 + total * 0.0006, 0.05, 0.085))
		elif gore.can_sever(bone) and total >= dismember_damage:
			severed = true

	# Bullets add up: enough rounds into one part slowly tears it open.
	if not info.get("can_dismember", false) and not info.get("stake", false):
		_wear(zone, bone, info.position, dir, raw)

	var was_dead := dead
	if not dead:
		health -= dmg
		if health <= 0.0 or _head_open or (severed and zone in [&"UpperLeg", &"LowerLeg", &"Neck"]):
			_die(info, zone)
	hurt.emit(self)
	if not dead and not crawling:
		_flinch_from(info.position, dir, raw * (1.8 if severed else 1.0))
	if dead:
		var impulse: Vector3 = dir * float(info.get("impulse", 12.0))
		if was_dead:
			impulse *= 0.6              # a corpse soaks up a shot, it does not leap
		elif zone == &"Neck" and not info.get("heavy", false):
			impulse = dir * 27.0 + Vector3.UP * 3.0   # a sharp whip of the head, not a launch
		ragdoll.apply_hit(bone, impulse, info.position)
	if severed:
		if zone == &"Neck":
			knock_off_helmet(dir, info.position)
		gore.sever(bone, dir * float(info.get("impulse", 12.0)))


func _die(info: Dictionary, zone: StringName) -> void:
	dead = true
	var profile: Dictionary
	var wall_gap := -1.0 if crawling or info.get("blast", false) or info.get("stake", false) else _wall_behind(info.direction)
	if force_variant == "wall_slide" and wall_gap < 0.0:
		wall_gap = 0.5
	if info.get("blast", false) or info.get("stake", false):
		profile = ClownRagdoll.profile_blast()      # no fight left: it goes where it is carried
	elif crawling:
		profile = ClownRagdoll.profile_limp()
	elif not info.get("heavy", false) and wall_gap >= 0.0 and (force_variant == "wall_slide" or (force_variant == "" and randf() < 0.8)):
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
	if zone in [&"UpperLeg", &"LowerLeg", &"Foot"] and not info.get("blast", false):
		var side := "Left" if String(info.collider.bone_name).begins_with("Left") else "Right"
		for part in ["UpperLeg", "LowerLeg", "Foot"]:
			ragdoll.weaken(StringName(side + part), 0.15)
	ragdoll.start(profile, info.direction, info.get("fling", velocity))
	_drop_rifle()
	gore.start_bleeding()
	last_hit_zone = zone
	died.emit(self)


func _on_settled() -> void:
	await get_tree().create_timer(freeze_after).timeout
	if is_instance_valid(self) and ragdoll.is_settled:
		ragdoll.freeze()


# --- worn down by bullets --------------------------------------------------------------
## Damage a part must have soaked up (across any number of pistol or SMG
## rounds, alive or dead) for each further stage of it to be torn open.
## Head: cracked open, then more skull gone, then mostly gone.
## Chest: ribs showing, then a wider cavity. Belly: guts out, then more.
const WEAR_STAGES := {
	&"Head": [[55.0, 0.045], [115.0, 0.065], [190.0, 0.088]],
	&"Chest": [[75.0, 0.06], [155.0, 0.085], [250.0, 0.115]],
	&"Belly": [[65.0, 0.06], [145.0, 0.085], [235.0, 0.115]],
}
var _wear_dmg := {}
var _wear_stage := {}


func _wear(zone: StringName, bone: StringName, at: Vector3, dir: Vector3, raw: float) -> void:
	var region := &""
	var blast_bone := bone
	if zone == &"Neck":
		region = &"Head"
	elif bone == &"Chest":
		region = &"Chest"
	elif bone == &"Spine" or bone == &"Hips":
		region = &"Belly"
		blast_bone = &"Spine"
	if region == &"" or not ragdoll.bones.has(blast_bone):
		return
	if region == &"Head" and (gore.hidden_mask >> ClownGore.SEGMENTS.find(&"Head")) & 1 == 1:
		return
	_wear_dmg[region] = _wear_dmg.get(region, 0.0) + raw
	var stages: Array = WEAR_STAGES[region]
	var done: int = _wear_stage.get(region, 0)
	while done < stages.size() and _wear_dmg[region] >= stages[done][0]:
		var size: float = stages[done][1]
		done += 1
		if region == &"Head":
			_head_open = true
			knock_off_helmet(dir, at)
			if done == stages.size():
				Blood.mist(at, dir, 2.0)          # the last of the skull goes in a burst
		gore.blast(blast_bone, at, dir, size)
	_wear_stage[region] = done


# --- explosions ---------------------------------------------------------------------
const BLAST_LIMBS := [&"LeftUpperArm", &"RightUpperArm", &"LeftLowerArm", &"RightLowerArm",
	&"LeftUpperLeg", &"RightUpperLeg", &"LeftLowerLeg", &"RightLowerLeg", &"LeftHand", &"RightHand"]


func _bone_world(bone: StringName) -> Vector3:
	var pb: PhysicalBone3D = ragdoll.bones.get(bone)
	return pb.global_position if pb else global_position + Vector3.UP * 1.2


## An explosion went off at `center`. How badly this clown comes apart depends
## on how close it was and whether anything stood in the way.
func caught_in_blast(center: Vector3, radius: float) -> void:
	var chest := _bone_world(&"Chest")
	var to := chest - center
	var d := to.length()
	if d >= radius:
		return
	var s := 1.0 - d / radius
	var q := PhysicsRayQueryParameters3D.create(center, chest, 1)
	var cover := get_world_3d().direct_space_state.intersect_ray(q)
	if not cover.is_empty():
		s *= 0.35                       # round a corner or behind a crate
	if s < 0.04:
		return
	var away := to / maxf(d, 0.01)
	var dir := (Vector3(away.x, 0, away.z).normalized() + Vector3.UP * lerpf(0.25, 0.6, s)).normalized()
	# Close, but not right on top of it: sometimes torn in half and still alive.
	if not dead and not crawling and s > 0.5 and s < 0.86 and cover.is_empty() and randf() < crawl_chance:
		_tear_in_half(center, dir, s)
		return
	var was_dead := dead
	var limbs := _blast_gore(center, dir, s)
	if not dead:
		health -= 320.0 * pow(s, 1.3)
		if health <= 0.0 or limbs.size() > 0:
			last_hit_zone = &"Chest"
			var fling := dir * lerpf(2.0, 15.0, s * s) * randf_range(0.85, 1.1)
			ragdoll.max_bone_speed = 26.0
			_die({direction = dir, heavy = true, blast = true, collider = ragdoll.bones[&"Chest"], fling = fling}, &"Chest")
			_throw_bones(dir, s)
		else:
			# Survived: knocked about, half deaf, and now it knows.
			_flinch_from(chest - dir * 0.2, dir, 90.0 * s)
			var b := get_node_or_null("Brain")
			if b and b.has_method("alert"):
				b.alert(center)
	elif was_dead:
		ragdoll.wake()
		ragdoll.max_bone_speed = 26.0
		for pb: PhysicalBone3D in ragdoll.bones.values():
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, dir * lerpf(1.5, 11.0, s * s))
		_throw_bones(dir, s)
	for limb: StringName in limbs:
		if gore.can_sever(limb):
			gore.sever(limb, dir * lerpf(10.0, 30.0, s) + Vector3(randf_range(-4, 4), randf_range(0, 6), randf_range(-4, 4)))
	gore.watch_impacts(2.2)
	gore.start_bleeding()


## After the fling: each part tumbles its own way, so no two land alike.
func _throw_bones(dir: Vector3, s: float) -> void:
	for pb: PhysicalBone3D in ragdoll.bones.values():
		var rid := pb.get_rid()
		var v: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		v += Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)) * 2.0 * s
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * s)
	var cap := ragdoll
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(cap):
			cap.max_bone_speed = 9.0)


## Wounds, blood and torn-open parts from a blast of strength `s` (0..1).
## Returns the limbs that should come off once the body is moving.
func _blast_gore(center: Vector3, dir: Vector3, s: float) -> Array:
	var near := func(bone: StringName) -> Vector3:
		var p := _bone_world(bone)
		return p + (center - p).normalized() * 0.11
	# shrapnel and burns all over the side facing the blast
	var bones := [&"Chest", &"Spine", &"Hips", &"Neck", &"LeftUpperArm", &"RightUpperArm", &"LeftUpperLeg", &"RightUpperLeg", &"LeftLowerLeg", &"RightLowerLeg"]
	for i in int(2 + s * 9):
		var b: StringName = bones.pick_random()
		if ragdoll.bones.has(b):
			gore.add_wound(b, near.call(b) + Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06)), 20.0 + 45.0 * s)
	# a lot of blood, every way
	var chest := _bone_world(&"Chest")
	for i in int(2 + s * 7):
		Blood.spawn_hit(chest + Vector3(randf_range(-0.2, 0.2), randf_range(-0.4, 0.3), randf_range(-0.2, 0.2)), (dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.8), randf_range(-0.8, 0.8))).normalized(), 0.9 + s * 1.1)
	if s > 0.38 and ragdoll.bones.has(&"Spine") and randf() < 0.35 + s * 0.6:
		gore.blast(&"Spine", near.call(&"Spine"), dir, clampf(0.08 + s * 0.06, 0.08, 0.14))      # belly open, guts out
	if s > 0.5 and randf() < s * 0.9:
		gore.blast(&"Chest", near.call(&"Chest"), dir, clampf(0.08 + s * 0.05, 0.08, 0.13))      # ribs showing
	if s > 0.45 and not _head_open and randf() < 0.2 + s * 0.45:
		_head_open = true                                                                       # a piece of skull gone
		knock_off_helmet(dir, _bone_world(&"Neck"))
		gore.blast(&"Neck", near.call(&"Neck"), dir, clampf(0.05 + s * 0.035, 0.055, 0.085))
	elif has_helmet and randf() < s:
		knock_off_helmet(dir, _bone_world(&"Neck"))
	var count := 0
	if s > 0.8:
		count = randi_range(1, 3)
	elif s > 0.6:
		count = randi_range(0, 2)
	elif s > 0.4 and randf() < 0.3:
		count = 1
	var limbs := BLAST_LIMBS.duplicate()
	limbs.shuffle()
	var out: Array = []
	for limb: StringName in limbs:
		if out.size() >= count:
			break
		# one limb per side chain is enough (an upper arm takes the forearm with it)
		var chain := String(limb).replace("Lower", "").replace("Upper", "").replace("Hand", "Arm")
		var clash := false
		for o: StringName in out:
			if String(o).replace("Lower", "").replace("Upper", "").replace("Hand", "Arm") == chain:
				clash = true
		if not clash and gore.can_sever(limb):
			out.append(limb)
	if s > 0.88 and not _head_open and randf() < 0.2 and gore.can_sever(&"Neck"):
		out.append(&"Neck")
	return out


## Torn apart at the waist: the legs go flying, the rest of it lives on for a
## minute, dragging itself away on its hands.
func _tear_in_half(center: Vector3, dir: Vector3, s: float) -> void:
	var b := get_node_or_null("Brain")
	if b:
		b.process_mode = Node.PROCESS_MODE_DISABLED
	_drop_rifle()
	has_gun = false
	attack_amount = 0.0
	aim_amount = 0.0
	if has_helmet and randf() < 0.5:
		knock_off_helmet(dir, _bone_world(&"Neck"))
	gore.cut_waist(dir * lerpf(4.0, 7.0, s) + Vector3.UP * 1.5)
	var torso_hits := [&"Chest", &"Spine", &"LeftUpperArm", &"RightUpperArm", &"Neck"]
	for i in 5:
		var bn: StringName = torso_hits.pick_random()
		gore.add_wound(bn, _bone_world(bn) + (center - _bone_world(bn)).normalized() * 0.1, 30.0)
	health = minf(health, 40.0)
	crawling = true
	set_process(false)
	var crawler := ClownCrawler.new()
	crawler.name = "Crawler"
	add_child(crawler)
	crawler.begin(self, b.maze if b else null, dir)


## Called by the crawler when the minute is up.
func bleed_out() -> void:
	if dead:
		return
	last_hit_zone = &"Spine"
	_die({direction = Vector3.DOWN, collider = ragdoll.bones.get(&"Chest")}, &"Spine")


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
	if dead or crawling:
		set_process(false)
		return
	delta = minf(delta, 1.0 / 30.0)         # the springs below go unstable on a long frame
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
		if not has_rifle:
			_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(arm) * sw * walk_amount)
		_turn("LeftLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * walk_amount)
		if attack_amount < 0.01 and aim_amount < 0.01 and not has_rifle:
			_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-arm) * sw * walk_amount)
			_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * walk_amount)
	# Right arm: swung overhead to hit, or held out to aim.
	if attack_amount > 0.01:
		_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-135.0) * attack_amount)
		_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-35.0) * attack_amount)
		_turn("Chest", Vector3.RIGHT, deg_to_rad(12.0) * attack_amount)
	elif aim_amount > 0.01:
		_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-84.0) * aim_amount)
		if has_rifle:
			# Rifle shouldered: right hand at the grip, left hand out under the fore-end.
			_turn("RightUpperArm", Vector3.UP, deg_to_rad(14.0) * aim_amount)
			_turn("RightLowerArm", Vector3.UP, deg_to_rad(38.0) * aim_amount)
			_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(-82.0) * aim_amount)
			_turn("LeftUpperArm", Vector3.UP, deg_to_rad(-22.0) * aim_amount)
			_turn("LeftLowerArm", Vector3.UP, deg_to_rad(-12.0) * aim_amount)
			_turn("Neck", Vector3.UP, deg_to_rad(-8.0) * aim_amount)
	if has_rifle and aim_amount < 0.99:
		# Carrying: both hands on the rifle across the chest.
		var carry := 1.0 - aim_amount
		_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-30.0) * carry)
		_turn("RightLowerArm", Vector3.UP, deg_to_rad(70.0) * carry)
		_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(-40.0) * carry)
		_turn("LeftLowerArm", Vector3.UP, deg_to_rad(-95.0) * carry)
	if _rifle and is_instance_valid(_rifle):
		_rifle.transform = _rifle_carried.interpolate_with(_rifle_aimed, aim_amount)
	if _flinch.length() > 0.0005:
		for b: Array in FLINCH_BONES:
			_turn(b[0], _flinch.normalized(), _flinch.length() * b[1])
	_model.position = _stagger
	if not always_pose and _flinch.length() < 0.002 and _flinch_vel.length() < 0.02 and _stagger.length() < 0.002 and _stagger_vel.length() < 0.02:
		_flinch = Vector3.ZERO
		_stagger = Vector3.ZERO
		_model.position = Vector3.ZERO
		set_process(false)


# --- helmet -----------------------------------------------------------------------
var has_helmet := false
var _helmet: MeshInstance3D
var _helmet_hitbox: CollisionShape3D


func _put_on_helmet() -> void:
	var src := (load(spec.helmet) as PackedScene).instantiate()
	var found := src.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		src.free()
		return
	_helmet = MeshInstance3D.new()
	_helmet.mesh = (found[0] as MeshInstance3D).mesh
	_helmet.layers = 2
	src.free()
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	skeleton.add_child(att)
	att.add_child(_helmet)
	var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Head"))
	_helmet.transform = head_rest.affine_inverse() * Transform3D(Basis.IDENTITY, spec.helmet_center)
	# Bullets that hit the helmet count as headshots.
	var neck: PhysicalBone3D = ragdoll.bones.get(&"Neck")
	if neck:
		_helmet_hitbox = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec.helmet_size * 0.92
		_helmet_hitbox.shape = box
		_helmet_hitbox.position = spec.helmet_center - ragdoll.centres[&"Neck"]
		neck.add_child(_helmet_hitbox)
	has_helmet = true


## Send the helmet spinning off. `dir` is the way the bullet was travelling.
func knock_off_helmet(dir: Vector3, at: Vector3) -> void:
	if not has_helmet:
		return
	has_helmet = false
	var xf := _helmet.global_transform
	var flying := RigidBody3D.new()
	flying.collision_layer = 1 << 3
	flying.collision_mask = 1 | (1 << 3)
	flying.mass = 1.1
	flying.continuous_cd = true
	flying.angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.35
	flying.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.helmet_size * Vector3(0.95, 0.8, 0.95)
	cs.shape = box
	flying.add_child(cs)
	_helmet.get_parent().remove_child(_helmet)
	flying.add_child(_helmet)
	_helmet.transform = Transform3D.IDENTITY
	get_parent().add_child(flying)
	flying.global_transform = xf
	var away := Vector3(dir.x, 0, dir.z).normalized()
	flying.linear_velocity = away * randf_range(3.0, 5.0) + Vector3.UP * randf_range(3.2, 4.6) + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	# Spin end over end about an axis across the shot, with some wobble.
	var spin_axis := away.cross(Vector3.UP).normalized() + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
	flying.angular_velocity = spin_axis.normalized() * randf_range(16.0, 26.0)
	if _helmet_hitbox and is_instance_valid(_helmet_hitbox):
		_helmet_hitbox.queue_free()
	Blood.spawn_hit(at, dir, 0.4)


# --- weapons ----------------------------------------------------------------------
var has_rifle := false
var _muzzle: Node3D
var _rifle: Node3D
var _rifle_attach: BoneAttachment3D
var _rifle_aimed := Transform3D()
var _rifle_carried := Transform3D()


## Put a bolt-action rifle on him: carried across the chest, shouldered to aim.
func give_rifle() -> void:
	has_gun = true
	has_rifle = true
	_rifle_attach = BoneAttachment3D.new()
	_rifle_attach.bone_name = "Chest"
	skeleton.add_child(_rifle_attach)
	_rifle = Node3D.new()
	_rifle_attach.add_child(_rifle)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.13, 0.06)
	wood.roughness = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.09, 0.09, 0.1)
	steel.metallic = 0.8
	steel.roughness = 0.35
	# Laid out with the butt at the origin and the barrel along +Z.
	_rifle_part(_rifle, Vector3(0.045, 0.05, 0.62), Vector3(0, 0.0, 0.35), wood)         # stock and fore-end
	_rifle_part(_rifle, Vector3(0.04, 0.11, 0.24), Vector3(0, -0.03, 0.12), wood)        # butt
	_rifle_part(_rifle, Vector3(0.022, 0.022, 0.48), Vector3(0, 0.025, 0.86), steel)     # barrel
	_rifle_part(_rifle, Vector3(0.03, 0.035, 0.16), Vector3(0, 0.035, 0.33), steel)      # receiver
	_rifle_part(_rifle, Vector3(0.06, 0.012, 0.012), Vector3(-0.035, 0.04, 0.29), steel) # bolt handle
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.025, 1.1)
	_rifle.add_child(_muzzle)
	var chest_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Chest"))
	# Shouldered: butt against the right shoulder, barrel straight ahead.
	_rifle_aimed = chest_rest.affine_inverse() * Transform3D(Basis.IDENTITY, Vector3(-0.11, 1.47, 0.1))
	# Carried: diagonal across the chest, butt at the right hip, muzzle over the left shoulder.
	var up := Vector3(0.55, 0.82, 0.12).normalized()
	var x := Vector3.BACK.cross(up).normalized()
	_rifle_carried = chest_rest.affine_inverse() * Transform3D(Basis(x, up.cross(x), up).orthonormalized(), Vector3(-0.2, 0.98, 0.2))
	_rifle.transform = _rifle_carried


## Drop the rifle where it is (on death).
func _drop_rifle() -> void:
	if _rifle == null or not is_instance_valid(_rifle):
		return
	var xf := _rifle.global_transform
	var body_ := RigidBody3D.new()
	body_.collision_layer = 1 << 3
	body_.collision_mask = 1 | (1 << 3)
	body_.mass = 4.0
	body_.continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.1, 1.1)
	cs.shape = box
	cs.position = Vector3(0, 0, 0.55)
	body_.add_child(cs)
	_rifle.get_parent().remove_child(_rifle)
	body_.add_child(_rifle)
	_rifle.transform = Transform3D.IDENTITY
	get_parent().add_child(body_)
	body_.global_transform = xf
	body_.linear_velocity = velocity + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1))
	body_.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	_rifle = null
	_muzzle = null


func _rifle_part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	mi.layers = 2
	parent.add_child(mi)


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
	if _muzzle and is_instance_valid(_muzzle):
		return _muzzle.global_position
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
