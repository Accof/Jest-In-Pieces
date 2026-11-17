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
		soldier = true,
	},
	# Der Klappersoldat: rigged and segmented from the Tripo model by
	# tools/build_klappersoldat.py (klappersoldat.json). No separate helmet.
	"klappersoldat": {
		model = "res://art/klappersoldat/klappersoldat.glb", gibs = "res://art/klappersoldat/klappersoldat_gibs.glb",
		rest_min = Vector3(-0.96347, -0.0051, -0.20856), rest_size = Vector3(1.93163, 1.9251, 0.42104),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.2, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.15, &"Chest": 1.15, &"Neck": 1.12, &"Foot": 1.15},
		eyes = [Vector3(0.04738, 1.74246, 0.1074), Vector3(-0.04738, 1.74246, 0.1074)],
	},
	# The Rattlejack: British machine gunner, rigged and segmented from the
	# Tripo model by tools/build_rattlejack.py (rattlejack.json), the Brodie
	# helmet cut off the head into its own mesh.
	"rattlejack": {
		model = "res://art/rattlejack/rattlejack.glb", gibs = "res://art/rattlejack/rattlejack_gibs.glb",
		rest_min = Vector3(-0.94802, -0.00508, -0.24266), rest_size = Vector3(1.90023, 1.89008, 0.48997),
		helmet = "res://art/rattlejack/rattlejack_helmet.glb",
		helmet_center = Vector3(-0.00046, 1.80501, 0.04647), helmet_size = Vector3(0.312, 0.210, 0.325),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.25, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
		soldier = true,
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
## Close to a blast (but not on top of it): the chance it is torn in half at
## the waist, and of those, the share that live a while and crawl. The rest
## are dead: the legs go one way, the top half the other.
@export var halve_chance := 0.4
@export var crawl_share := 0.5
## A clockwork body (the Klappersoldat): oil instead of blood, gears instead
## of guts. Set before it enters the tree.
var mechanical := false
## A blow that opens the skull kills outright (false for the Klappersoldat:
## there is only clockwork in there, so it takes damage like any other).
var head_open_kills := true
## True while this clown is a torso dragging itself along the floor.
var crawling := false
## "Left" or "Right" once that leg is broken: it limps, and the knee bends wrong.
var broken_leg := ""             # the first leg broken ("Left"/"Right"); the limp is on this side
var broken_legs: Array[String] = []   # every broken leg
var broken_arms: Array[String] = []   # every broken arm (dangling, bone showing)
## Both legs gone: dragging itself to a wall to sit and make its last stand.
var last_stand := false
## Shots to the legs break them rather than kill: leg damage to health is
## scaled by this, a leg shot never kills while a leg is still unbroken (it
## breaks one instead), and the break chances below decide when a leg goes.
@export var leg_damage_scale := 0.4
@export var leg_break_damage := 26.0       ## one round this strong may break the leg ...
@export var leg_break_chance := 0.5        ## ... with this chance
@export var leg_break_total := 60.0        ## enough rounds in one leg always do
@export var arm_break_damage := 28.0
@export var arm_break_chance := 0.4
@export var arm_break_total := 55.0
var _arm_dmg := {}
var _gun_att: Node3D
var gun_side := ""
## On the floor after a knee shot, writhing, then getting back up.
var downed := false

## Damage multiplier for each hit zone (keyed by physical bone).
const ZONE_DAMAGE := {
	&"Neck": 4.0, &"Chest": 1.0, &"Spine": 1.0, &"Hips": 0.9,
	&"UpperArm": 0.55, &"LowerArm": 0.45, &"Hand": 0.3,
	&"UpperLeg": 0.7, &"LowerLeg": 0.55, &"Foot": 0.35,
}

var health := 0.0
var dead := false
var last_hit_zone := &""         # where the killing shot landed
var hit_log: Array = []            # every hit taken: bone, zone, rest-space point, damage, weapon (injury report)
var blasts: Array[float] = []      # strength (0..1) of every explosion it was caught in
var fatal_pos := Vector3.ZERO      # where it landed (world), and which way it was going
var fatal_dir := Vector3.ZERO
## How it died, for the lifetime stats: weapon name, zone, and flags
## (blast, stake, seated...). Filled in by _die before `died` goes out.
var death := {}
var _halved := false                 # torn in half by a blast (dead or crawling)
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
	ragdoll.oil = mechanical
	ragdoll.build(skeleton, spec.shapes)
	for pb: PhysicalBone3D in ragdoll.bones.values():
		pb.set_meta(&"clown", self)
	if spec.has("helmet"):
		_put_on_helmet()
	gore = ClownGore.new()
	add_child(gore)
	gore.setup(self)
	ragdoll.settled.connect(_on_settled)
	gore.part_severed.connect(func(seg: StringName, _gib: Node3D) -> void:
		var sn := String(seg)
		if sn.contains("Arm") or sn.ends_with("Hand"):
			_arm_lost("Left" if sn.begins_with("Left") else "Right"))


## Whether a leg is broken (or gone).
func leg_out(side: String) -> bool:
	return broken_legs.has(side) or _segment_gone(side + "UpperLeg") or _segment_gone(side + "LowerLeg")


## Whether an arm is useless: broken, or (any part of it) blown off.
func arm_out(side: String) -> bool:
	return broken_arms.has(side) or _segment_gone(side + "UpperArm") or _segment_gone(side + "LowerArm") or _segment_gone(side + "Hand")


func _segment_gone(seg: String) -> bool:
	var i := ClownGore.SEGMENTS.find(StringName(seg))
	return i >= 0 and gore != null and (gore.hidden_mask >> i) & 1 == 1


## The arm it fights with: the right, or the left if the right is out, or "".
func main_arm() -> String:
	if not arm_out("Right"):
		return "Right"
	return "Left" if not arm_out("Left") else ""


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
	var break_leg := false

	# every hit, where it landed on the body, for the injury report
	if hit_log.size() < 80:
		hit_log.append({bone = bone, zone = zone, rest = gore.rest_point(bone, info.position), raw = raw,
			weapon = info.get("weapon", ""), stake = info.get("stake", false), heavy = info.get("heavy", false),
			pellet = info.get("can_dismember", false), after = dead})
	# A headshot may knock the helmet clean off; it still goes through.
	if zone == &"Neck" and has_helmet and randf() < helmet_pop_chance:
		knock_off_helmet(dir, info.position)
	gore.add_wound(bone, info.position, raw)
	Blood.spawn_hit(info.position, dir, amount, mechanical)

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
			# Point blank, most of the charge in the chest or belly: it goes
			# straight through and leaves a hole you can see through.
			if zone != &"Hips" and info.get("weapon", "") == "Shotgun" and float(info.get("dist", 99.0)) < punch_range \
					and total >= punch_damage and not _shot_blasted.has(&"through"):
				_shot_blasted[&"through"] = true
				gore.punch_through(bone, info.position, dir, punch_radius)
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
			var leg := zone in [&"UpperLeg", &"LowerLeg"]
			if not leg:
				severed = true
			elif not _shot_blasted.has(&"leg"):
				# decided once per blast: usually the bone goes and the leg stays on
				_shot_blasted[&"leg"] = true
				if randf() < leg_off_chance:
					severed = true
				elif not leg_out("Left" if String(bone).begins_with("Left") else "Right"):
					break_leg = true

	# A round in the knee, a strong one anywhere on the leg (sometimes), or
	# enough of them in one leg breaks it; the other leg too, the same way.
	var limb_side := "Left" if String(bone).begins_with("Left") else "Right"
	if not info.get("can_dismember", false) and zone in [&"UpperLeg", &"LowerLeg", &"Foot"] and not leg_out(limb_side):
		_leg_dmg[limb_side] = _leg_dmg.get(limb_side, 0.0) + raw
		var knee := _bone_world(StringName(limb_side + "LowerLeg"))
		var kb := skeleton.find_bone(limb_side + "LowerLeg")
		knee = skeleton.global_transform * skeleton.get_bone_global_pose(kb).origin if not dead else knee
		if (raw >= knee_damage and info.position.distance_to(knee) < KNEE_RADIUS) or _leg_dmg[limb_side] >= leg_break_total \
				or (raw >= leg_break_damage and randf() < leg_break_chance):
			break_leg = true
	# Arms the same: the bone goes and the arm hangs useless.
	var break_arm := false
	if zone in [&"UpperArm", &"LowerArm", &"Hand"] and not arm_out(limb_side):
		_arm_dmg[limb_side] = _arm_dmg.get(limb_side, 0.0) + raw
		if _arm_dmg[limb_side] >= arm_break_total or (raw >= arm_break_damage and randf() < arm_break_chance):
			break_arm = true

	# Bullets add up: enough rounds into one part slowly tears it open.
	if not info.get("can_dismember", false) and not info.get("stake", false):
		_wear(zone, bone, info.position, dir, raw)

	var was_dead := dead
	if not dead:
		var leg_hit := zone in [&"UpperLeg", &"LowerLeg", &"Foot"]
		if leg_hit:
			dmg *= leg_damage_scale
		health -= dmg
		# a leg shot breaks the leg rather than killing, until both are gone
		if leg_hit and health <= 0.0 and not severed and not (leg_out("Left") and leg_out("Right") and randf() < 0.25):
			health = 1.0
			if not leg_out(limb_side):
				break_leg = true
		if health <= 0.0 or (_head_open and head_open_kills) or (severed and zone in [&"UpperLeg", &"LowerLeg", &"Neck"]):
			_die(info, zone)
	hurt.emit(self)
	if not dead and not crawling and not downed and not last_stand:
		_flinch_from(info.position, dir, raw * (1.8 if severed else 1.0))
	if not dead and not broken_arms.is_empty():
		_kick_arms(clampf(raw / 10.0, 1.0, 6.0))
	if downed and not dead and ragdoll.active:
		ragdoll.apply_hit(bone, dir * float(info.get("impulse", 12.0)) * 0.5, info.position)
	if break_leg and not severed:
		_break_leg(limb_side, info.position, dir)
	if break_arm and not severed:
		_break_arm(limb_side, info.position, dir)
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
	_start_ragdoll(info, zone)
	_record_death(info, zone)


## The body goes over: picks how it falls (or takes info.profile) and hands it
## to the ragdoll. A subclass can call this some time after the death itself
## (the Klappersoldat stands, kneels or seizes up first).
func _start_ragdoll(info: Dictionary, zone: StringName) -> void:
	var profile: Dictionary
	var wall_gap := -1.0 if crawling or info.get("blast", false) or info.get("stake", false) else _wall_behind(info.direction)
	if force_variant == "wall_slide" and wall_gap < 0.0:
		wall_gap = 0.5
	if info.has("profile"):
		profile = info.profile                      # the caller knows best (an event room)
	elif info.get("blast", false) or info.get("stake", false):
		profile = ClownRagdoll.profile_blast()      # no fight left: it goes where it is carried
	elif crawling or last_stand:
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
	if has_rifle and not profile.is_empty():
		# The hands come off the rifle: the dying arm muscles pull toward arms
		# hanging at the sides (then thrown wide), not the grip they died in.
		profile = profile.duplicate()
		profile["arms_wide"] = true
		for side: String in ["Left", "Right"]:
			for part: String in ["UpperArm", "LowerArm", "Hand"]:
				var bi := skeleton.find_bone(side + part)
				if _base_rot.has(bi):
					ragdoll.eq_override[StringName(side + part)] = Basis(_base_rot[bi])
	if ragdoll.active:
		ragdoll.restart(profile)          # already on the floor (shot while down)
	else:
		ragdoll.start(profile, info.direction, info.get("fling", velocity))
	downed = false
	if broken_leg != "":
		ragdoll.break_knee(broken_leg, info.direction)
	_drop_rifle()
	_drop_club()
	gore.start_bleeding()


## What killed it, for the stats, and `died` goes out (the kill counts now).
func _record_death(info: Dictionary, zone: StringName) -> void:
	last_hit_zone = zone
	fatal_pos = info.get("position", global_position + Vector3.UP * 1.2)
	fatal_dir = info.get("direction", Vector3.ZERO)
	var limbs := 0
	var m := int(gore.hidden_mask)
	while m:
		limbs += m & 1
		m >>= 1
	death = {
		weapon = info.get("weapon", "Stake Gun" if info.get("stake", false) else ""),
		zone = zone, blast = info.get("blast", false), stake = info.get("stake", false),
		head_open = _head_open, limbs = limbs, broken_leg = broken_leg != "",
		crawler = crawling or _halved, through = gore._tunnels.size() > 0,
	}
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
				Blood.mist(at, dir, 2.0, mechanical)          # the last of the skull goes in a burst
		gore.blast(blast_bone, at, dir, size)
	_wear_stage[region] = done


# --- broken legs, and going down ----------------------------------------------------
## One round this strong landing this close to a knee breaks the leg.
@export var knee_damage := 28.0
## Chance a shotgun blast that would take a leg off does so; otherwise it breaks it.
@export var leg_off_chance := 0.25
## A shotgun inside this range (m) that puts at least `punch_damage` into the
## chest or belly in one blast punches a hole clean through (radius in m).
@export var punch_range := 3.0
@export var punch_damage := 95.0
@export var punch_radius := 0.085
const KNEE_RADIUS := 0.17
var _leg_dmg := {}
var _down_t := 0.0
var _down_stage := 0                # 0 writhing on the floor, 1 getting up
var _writhe_for := 3.0
var _writhe_next := 0.0
var _getup_from := {}
var _getup_kneel := {}
var _getup_stand := {}
const GETUP_KNEEL := 0.75
const GETUP_STAND := 0.95


func _break_leg(side: String, at: Vector3, dir: Vector3) -> void:
	if leg_out(side) or crawling:
		return
	broken_legs.append(side)
	if broken_leg == "":
		broken_leg = side
	Blood.spawn_hit(at, dir, 1.4, mechanical)
	gore.add_wound(StringName(side + "LowerLeg"), at, 40.0)
	gore.show_broken_knee(side)
	if dead:
		if ragdoll.active:
			ragdoll.break_knee(side, dir)
	elif last_stand:
		pass                               # already down for good
	elif downed:
		if ragdoll.active:
			ragdoll.break_knee(side, dir)
		elif _down_stage == 1:
			_go_down(side, dir)            # was getting up on the good one: back down
	else:
		_go_down(side, dir)


## The arm breaks: it drops and dangles, a splinter of bone out through the
## skin. Whatever was in that hand goes; an enemy with no good arm left
## stops fighting and tries to hide.
func _break_arm(side: String, at: Vector3, dir: Vector3) -> void:
	if arm_out(side):
		return
	broken_arms.append(side)
	Blood.spawn_hit(at, dir, 1.2, mechanical)
	gore.add_wound(StringName(side + "LowerArm"), at, 35.0)
	gore.show_broken_arm(side)
	for part in ["UpperArm", "LowerArm", "Hand"]:
		ragdoll.weaken(StringName(side + part), 0.0)
	if not dead:
		_arm_lost(side)


## An arm out of use (broken or blown off): weapons it held are dropped, a
## rifleman carries on with a pistol in the good hand; with neither, it hides.
func _arm_lost(side: String) -> void:
	if dead:
		return
	var good := main_arm()
	var b := get_node_or_null("Brain")
	if has_rifle:
		_drop_rifle()
		has_rifle = false
		has_gun = false
		if good != "" and not last_stand:
			give_gun(good)
			if b and b.has_method("pistol_mode"):
				b.pistol_mode()
	elif has_club and side == "Right":
		_drop_club()
		has_club = false
	elif has_gun and gun_side == side:
		_drop_gun()
		if good != "":
			give_gun(good)
	if good == "":
		_drop_gun()
		has_gun = false
		if b and b.has_method("start_hiding") and not last_stand:
			b.start_hiding()


func _drop_gun() -> void:
	if _gun_att and is_instance_valid(_gun_att):
		var gun := _gun_att.get_child(0) as Node3D
		if gun:
			var xf := gun.global_transform
			var body_ := RigidBody3D.new()
			body_.collision_layer = 1 << 3
			body_.collision_mask = 1 | (1 << 3)
			body_.mass = 1.0
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.2, 0.05, 0.035)
			cs.shape = box
			body_.add_child(cs)
			gun.get_parent().remove_child(gun)
			body_.add_child(gun)
			gun.transform = Transform3D.IDENTITY
			get_parent().add_child(body_)
			body_.global_transform = xf
			body_.linear_velocity = velocity + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		_gun_att.queue_free()
	_gun_att = null
	gun_side = ""


## The knee gives: the body drops, writhes on the floor clutching it, then
## drags itself back up and limps on.
func _go_down(side: String, dir: Vector3) -> void:
	downed = true
	_down_stage = 0
	_down_t = 0.0
	_writhe_for = randf_range(2.4, 3.8)
	attack_amount = 0.0
	aim_amount = 0.0
	crouch_amount = 0.0
	var b := get_node_or_null("Brain")
	if b:
		b.process_mode = Node.PROCESS_MODE_DISABLED
	ragdoll.start(ClownRagdoll.profile_kneecapped(), dir, velocity * 0.5)
	for leg: String in broken_legs:
		for part in ["UpperLeg", "LowerLeg", "Foot"]:
			ragdoll.weaken(StringName(leg + part), 0.1 if part == "UpperLeg" else 0.0)
		ragdoll.break_knee(leg, dir)
	gore.start_bleeding()
	set_process(true)


func _downed_process(delta: float) -> void:
	_down_t += delta
	if _down_stage == 0:
		# writhing: the body twists, the good leg kicks, a hand goes to the knee
		_writhe_next -= delta
		if _writhe_next <= 0.0:
			_writhe_next = randf_range(0.18, 0.5)
			var good := "Right" if broken_leg == "Left" else "Left"
			var parts := [&"Spine", &"Chest", &"Neck", StringName(good + "UpperLeg"), StringName(good + "LowerLeg"), &"LeftUpperArm", &"RightUpperArm"]
			var pb: PhysicalBone3D = ragdoll.bones.get(parts.pick_random())
			if pb:
				var kick := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				PhysicsServer3D.body_apply_torque_impulse(pb.get_rid(), kick * pb.mass * randf_range(0.25, 0.6))
		var hand: PhysicalBone3D = ragdoll.bones.get(StringName(broken_leg + "Hand"))
		var knee: PhysicalBone3D = ragdoll.bones.get(StringName(broken_leg + "LowerLeg"))
		if hand and knee:
			PhysicsServer3D.body_apply_central_impulse(hand.get_rid(), (knee.global_position - hand.global_position).limit_length(0.5) * hand.mass * 6.0 * delta)
		var chest: PhysicalBone3D = ragdoll.bones.get(&"Chest")
		var slow := chest == null or (PhysicsServer3D.body_get_state(chest.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).length() < 1.2
		if _down_t > _writhe_for and slow:
			if leg_out("Left") and leg_out("Right"):
				_begin_last_stand()
			else:
				_begin_getup()
	else:
		_getup()


func _begin_getup() -> void:
	var sk := skeleton
	var count := sk.get_bone_count()
	var world := []
	for i in count:
		world.append(sk.global_transform * ragdoll.bone_pose(i))
	ragdoll.stop()
	# stand up where the hips came to rest, facing the player
	var hips: Vector3 = (world[sk.find_bone("Hips")] as Transform3D).origin
	var b := get_node_or_null("Brain")
	var floor_y := global_position.y
	if b and b.maze:
		floor_y = b.maze.floor_height(hips)
	global_position = Vector3(hips.x, floor_y, hips.z)
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player:
		var to := player.global_position - global_position
		rotation = Vector3(0, atan2(to.x, to.z), 0)
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	var inv := sk.global_transform.affine_inverse()
	var g := []
	for i in count:
		g.append(inv * (world[i] as Transform3D))
	_getup_from = {}
	for i in count:
		var p := sk.get_bone_parent(i)
		var local: Transform3D = (g[p] as Transform3D).affine_inverse() * g[i] if p >= 0 else g[i]
		_getup_from[i] = [local.basis.get_rotation_quaternion(), local.origin]
	_getup_kneel = _capture_pose(_kneel_pose)
	_getup_stand = _capture_pose(_broken_knee_pose)
	_apply_pose(_getup_from, _getup_from, 0.0)
	_down_stage = 1
	_down_t = 0.0


## Both legs broken: it will not get up again. Off the ragdoll and into the
## last stand: it drags itself away on its arms to a wall, sits against it,
## and (if it carried a gun) pulls a pistol for a last few shots.
func _begin_last_stand() -> void:
	var sk := skeleton
	var hips: Vector3 = sk.global_transform * ragdoll.bone_pose(sk.find_bone("Hips")).origin
	# where every bone lies on the floor right now: the crawl blends out of it
	var lying: Array[Transform3D] = []
	for i in sk.get_bone_count():
		lying.append(sk.global_transform * ragdoll.bone_pose(i))
	ragdoll.stop()
	downed = false
	last_stand = true
	var b := get_node_or_null("Brain")
	var floor_y := global_position.y
	if b and b.maze:
		floor_y = b.maze.floor_height(hips)
	global_position = Vector3(hips.x, floor_y, hips.z)
	var shooter := has_gun or has_rifle
	_drop_rifle()
	has_rifle = false
	_drop_club()
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	var ls := ClownLastStand.new()
	ls.name = "LastStand"
	add_child(ls)
	var away := Vector3.FORWARD
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player:
		away = global_position - player.global_position
	ls.begin_last_stand(self, b.maze if b else null, away, shooter, lying)


## The pose a function leaves the skeleton in, starting from standing.
func _capture_pose(pose: Callable) -> Dictionary:
	var sk := skeleton
	for i in sk.get_bone_count():
		sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
		sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin)
	for bi: int in _base_rot:
		sk.set_bone_pose_rotation(bi, _base_rot[bi])
	pose.call()
	var out := {}
	for i in sk.get_bone_count():
		out[i] = [sk.get_bone_pose_rotation(i), sk.get_bone_pose_position(i)]
	return out


## The snapped knee: shin bent back past straight and out to the side.
func _broken_knee_pose() -> void:
	var s := 1.0 if broken_leg == "Left" else -1.0
	_turn(broken_leg + "LowerLeg", Vector3.RIGHT, deg_to_rad(-48.0))
	_turn(broken_leg + "LowerLeg", Vector3.FORWARD, deg_to_rad(-30.0) * s)


## Down on the broken leg's knee, the good foot planted, a hand on the thigh.
func _kneel_pose() -> void:
	var sk := skeleton
	var hips := sk.find_bone("Hips")
	sk.set_bone_pose_position(hips, sk.get_bone_rest(hips).origin + Vector3(0, -0.42, -0.08))
	var good := "Right" if broken_leg == "Left" else "Left"
	_turn(good + "UpperLeg", Vector3.RIGHT, deg_to_rad(-80.0))
	_turn(good + "LowerLeg", Vector3.RIGHT, deg_to_rad(85.0))
	_turn(broken_leg + "UpperLeg", Vector3.RIGHT, deg_to_rad(35.0))
	_broken_knee_pose()
	_turn("Spine", Vector3.RIGHT, deg_to_rad(28.0))
	_turn("Neck", Vector3.RIGHT, deg_to_rad(-20.0))


func _apply_pose(a: Dictionary, b: Dictionary, w: float) -> void:
	var sk := skeleton
	var hips := sk.find_bone("Hips")
	for i: int in a:
		var qa: Quaternion = a[i][0]
		var qb: Quaternion = b[i][0]
		sk.set_bone_pose_rotation(i, qa.slerp(qb, w))
		if i == hips:
			sk.set_bone_pose_position(i, (a[i][1] as Vector3).lerp(b[i][1], w))


func _getup() -> void:
	var t := _down_t
	if t < GETUP_KNEEL:
		var w := smoothstep(0.0, 1.0, t / GETUP_KNEEL)
		_apply_pose(_getup_from, _getup_kneel, w)
	else:
		var w := smoothstep(0.0, 1.0, (t - GETUP_KNEEL) / GETUP_STAND)
		_apply_pose(_getup_kneel, _getup_stand, w)
	if t >= GETUP_KNEEL + GETUP_STAND:
		downed = false
		_flinch = Vector3.ZERO
		_flinch_vel = Vector3.ZERO
		_stagger = Vector3.ZERO
		_stagger_vel = Vector3.ZERO
		velocity = Vector3.ZERO
		var b := get_node_or_null("Brain")
		if b:
			b.process_mode = Node.PROCESS_MODE_INHERIT
			if b.has_method("limp"):
				b.limp()
		always_pose = true


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
	blasts.append(s)
	var away := to / maxf(d, 0.01)
	var dir := (Vector3(away.x, 0, away.z).normalized() + Vector3.UP * lerpf(0.25, 0.6, s)).normalized()
	# Close, but not right on top of it: sometimes torn in half; some of
	# those are still alive.
	if not dead and not crawling and s > 0.5 and s < 0.86 and cover.is_empty() and randf() < halve_chance:
		if randf() < crawl_share:
			_tear_in_half(center, dir, s)
		else:
			_halve_dead(center, dir, s)
		return
	var was_dead := dead
	var limbs := _blast_gore(center, dir, s)
	if not dead:
		health -= 320.0 * pow(s, 1.3)
		var tears := limbs.filter(func(l: StringName) -> bool: return not String(l).ends_with("Leg"))
		if health <= 0.0 or tears.size() > 0:
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
		var ls := String(limb)
		if (ls.ends_with("UpperLeg") or ls.ends_with("LowerLeg")) and randf() < 0.7:
			# more often the leg is smashed than torn off
			_break_leg("Left" if ls.begins_with("Left") else "Right", _bone_world(limb), dir)
			continue
		if gore.can_sever(limb):
			gore.sever(limb, dir * lerpf(10.0, 30.0, s) + Vector3(randf_range(-4, 4), randf_range(0, 6), randf_range(-4, 4)))
	# and it breaks bones: often several at once, more the closer it was
	if s > 0.2:
		for side: String in ["Left", "Right"]:
			if randf() < s * 0.9:
				_break_leg(side, _bone_world(StringName(side + "LowerLeg")), dir)
			if randf() < s * 0.8:
				_break_arm(side, _bone_world(StringName(side + "LowerArm")), dir)
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
		Blood.spawn_hit(chest + Vector3(randf_range(-0.2, 0.2), randf_range(-0.4, 0.3), randf_range(-0.2, 0.2)), (dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.8), randf_range(-0.8, 0.8))).normalized(), 0.9 + s * 1.1, mechanical)
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


## Torn in half and killed outright: the legs fly off as one piece, the top
## half is thrown, dead, trailing its guts.
func _halve_dead(center: Vector3, dir: Vector3, s: float) -> void:
	if has_helmet and randf() < 0.6:
		knock_off_helmet(dir, _bone_world(&"Neck"))
	gore.cut_waist(dir * lerpf(4.0, 7.0, s) + Vector3.UP * 1.5)
	for i in 4:
		var bn: StringName = [&"Chest", &"Spine", &"LeftUpperArm", &"RightUpperArm", &"Neck"].pick_random()
		gore.add_wound(bn, _bone_world(bn) + (center - _bone_world(bn)).normalized() * 0.1, 30.0)
	health = 0.0
	last_hit_zone = &"Spine"
	var fling := dir * lerpf(3.0, 9.0, s) * randf_range(0.85, 1.1)
	ragdoll.max_bone_speed = 26.0
	_halved = true
	_die({direction = dir, heavy = true, blast = true, collider = ragdoll.bones[&"Chest"], fling = fling}, &"Spine")


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
## Bones put back to their base rotation at the start of every posed frame.
## Anything the living pose turns must be here, or the turns add up frame
## after frame (the feet once ended up twisted toe-up this way).
const POSED_BONES := ["Hips", "Spine", "Chest", "Neck", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand"]
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
## When false the stride is not advanced here from the body's speed: a subclass
## sets walk_phase itself (the Klappersoldat's clockwork gait).
var drive_phase := true
## Thigh swing either way of upright, degrees, if set (> 0): a subclass that
## knows its own step length sizes the swing to match, so the planted foot
## stays put. Otherwise it follows walk/run speed.
var stride_override := 0.0

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
	_shot_t += delta
	if dead or crawling or last_stand:
		set_process(false)
		return
	if downed:
		_downed_process(delta)
		return
	delta = minf(delta, 1.0 / 30.0)         # the springs below go unstable on a long frame
	stagger_time = maxf(stagger_time - delta, 0.0)
	_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 13.0) * delta
	_flinch = (_flinch + _flinch_vel * delta).limit_length(0.6)
	_stagger_vel += (-_stagger * 70.0 - _stagger_vel * 13.0) * delta
	_stagger += _stagger_vel * delta
	for bi: int in _base_rot:
		skeleton.set_bone_pose_rotation(bi, _base_rot[bi])
	# Feet: the stride follows how fast and which way the body is really
	# moving, so the feet do not skate. Backing off steps backwards; moving
	# sideways is a side-step.
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	var fwd_amt := 1.0
	var side_amt := 0.0
	var back := 1.0
	if speed > 0.05 and drive_phase:
		var f := flat.dot(global_basis.z.normalized()) / speed
		var sd := flat.dot(global_basis.x.normalized()) / speed
		fwd_amt = absf(f)
		side_amt = absf(sd)
		back = -1.0 if f < -0.25 else 1.0
		# slower walking takes shorter steps rather than slower ones
		var stride_len := lerpf(lerpf(0.85, 1.3, clampf(speed / 1.5, 0.0, 1.0)), 1.9, run_amount) * (0.55 if broken_leg != "" else 1.0)
		if back < 0.0 and spec.get("soldier", false):
			stride_len *= 0.6               # stepping back: short, careful steps
		walk_phase += speed * delta * TAU / stride_len * back
	elif walk_amount > 0.01 and drive_phase:
		walk_phase += delta * 4.0            # marking time
	if speed > 0.05 and not drive_phase:
		var f2 := flat.dot(global_basis.z.normalized()) / speed
		var sd2 := flat.dot(global_basis.x.normalized()) / speed
		fwd_amt = absf(f2)
		side_amt = absf(sd2)
		back = -1.0 if f2 < -0.25 else 1.0
	var bob := 0.0
	# How much the legs swing: any real movement gets a full step (the step
	# rate already follows the speed), so a slow side-step still lifts its feet.
	var gait := maxf(walk_amount, clampf(speed / 0.9, 0.0, 1.0)) if speed > 0.05 else walk_amount
	if gait > 0.01:
		var sw := sin(walk_phase)
		var stride := (stride_override if stride_override > 0.0 else lerpf(27.0, 44.0 if has_rifle else 50.0, run_amount)) * clampf(fwd_amt + 0.3, 0.0, 1.0)
		var knee := lerpf(62.0, 75.0 if has_rifle else 90.0, run_amount)
		var arm := lerpf(22.0, 48.0, run_amount)
		_turn("Spine", Vector3.RIGHT, deg_to_rad(lerpf(4.0, 9.0 if has_rifle else 20.0, run_amount)) * gait * fwd_amt * (back if back > 0.0 else 0.25))
		_turn("Spine", Vector3.BACK, deg_to_rad(3.0) * sw * gait)
		_turn("Spine", Vector3.UP, deg_to_rad(5.0) * sw * gait * fwd_amt)        # hips and shoulders counter-turn
		var legs := {"Left": 1.0, "Right": -1.0}
		if spec.get("soldier", false):
			_soldier_legs(gait, fwd_amt, side_amt, back)
			legs = {}
		for side: String in legs:
			var s: float = legs[side]
			var limp := side == broken_leg
			var k := 0.35 if limp else 1.0
			var swing := maxf(0.0, cos(walk_phase) * s)          # this leg is coming through
			var stance := maxf(0.0, -cos(walk_phase) * s)        # this leg is carrying the body
			var behind := maxf(0.0, -sw * s)                      # trailing, about to push off
			# thigh forward and back; out to the side when side-stepping
			_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-stride) * sw * s * gait * k)
			_turn(side + "UpperLeg", Vector3.BACK, deg_to_rad(15.0) * sw * side_amt * gait)
			# knee: folds high as the foot comes through, gives a little under the
			# weight, never quite locks straight
			var knee_deg := knee * pow(swing, 1.4) + 9.0 * stance + 5.0
			_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(knee_deg) * gait * (0.3 if limp else 1.0))
			# ankle: toe pushes off behind, lifts clear coming through, lands heel first
			# (positive turns the toe down)
			_turn(side + "Foot", Vector3.RIGHT, deg_to_rad(20.0 * pow(behind, 2.0) * stance - 12.0 * swing) * gait * k)
		if not has_rifle:
			_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(arm) * sw * gait)
			_turn("LeftLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * gait)
		if attack_amount < 0.01 and aim_amount < 0.01 and not has_rifle:
			_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-arm) * sw * gait)
			_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * gait)
		# the body drops a little onto each foot as it lands
		bob = (0.5 + 0.5 * cos(walk_phase * 2.0)) * lerpf(0.035, 0.07, run_amount) * gait
	# A broken leg: knee bent the wrong way, and the body lurches down onto it.
	if broken_leg != "":
		var s := 1.0 if broken_leg == "Left" else -1.0
		_broken_knee_pose()
		var on_bad := maxf(0.0, sin(walk_phase) * (-s)) * walk_amount
		bob += on_bad * 0.09
		_turn("Spine", Vector3.BACK, deg_to_rad(-10.0) * s * (0.4 + on_bad))
		_turn("Spine", Vector3.RIGHT, deg_to_rad(12.0))
	# Crouched behind cover.
	if crouch_amount > 0.01:
		var c := crouch_amount
		for side: String in ["Left", "Right"]:
			_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-80.0) * c)
			_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(120.0) * c)
		_turn("Spine", Vector3.RIGHT, deg_to_rad(14.0) * c)
	# A soldier taking aim stands bladed: left foot forward, right foot back.
	_stance_w = 0.0
	if spec.get("soldier", false) and has_rifle and aim_amount > 0.01:
		_aim_stance(aim_amount * (1.0 - clampf(gait * 1.6, 0.0, 1.0)))
	# The fighting arm (the right, or the left if the right is out): swung
	# overhead to hit, or held out to aim (pistol gunmen).
	var arm := main_arm()
	if attack_amount > 0.01 and arm != "":
		_turn(arm + "UpperArm", Vector3.RIGHT, deg_to_rad(-135.0) * attack_amount)
		_turn(arm + "LowerArm", Vector3.RIGHT, deg_to_rad(-35.0) * attack_amount)
		_turn("Chest", Vector3.RIGHT, deg_to_rad(12.0) * attack_amount)
	elif aim_amount > 0.01 and not has_rifle and arm != "":
		_turn(arm + "UpperArm", Vector3.RIGHT, deg_to_rad(-84.0) * aim_amount)
	if _flinch.length() > 0.0005:
		for b: Array in FLINCH_BONES:
			_turn(b[0], _flinch.normalized(), _flinch.length() * b[1])
	_model.position = _stagger + Vector3.DOWN * (bob + 0.47 * crouch_amount + 0.025 * _stance_w)
	if extra_pose.is_valid():
		extra_pose.call()
	if has_rifle and _rifle and is_instance_valid(_rifle):
		_hold_rifle()
	for side: String in broken_arms:
		dangle_arm(side, gait)
	if not always_pose and _flinch.length() < 0.002 and _flinch_vel.length() < 0.02 and _stagger.length() < 0.002 and _stagger_vel.length() < 0.02:
		_flinch = Vector3.ZERO
		_stagger = Vector3.ZERO
		_model.position = Vector3.ZERO
		set_process(false)


## A broken arm hangs from the shoulder and swings with the body: the
## elbow bent the wrong way, the forearm twisted, the hand limp.
## It swings like a dead weight: each arm is a damped double pendulum (the
## upper arm from the shoulder, the forearm flopping from the broken elbow)
## pushed about by the body: thrown back when it sets off, forward when it
## stops, out to the side when it turns, kicked by every footfall and by
## every hit.
@export var arm_swing_freq := 0.85           ## the hanging arm's own swing (Hz)
@export var arm_swing_damping := 0.11        ## 0 swings for ever, 1 hardly swings
@export var arm_swing_push := 3.2            ## how hard the body's movement throws it
var _swing := {}                             # side -> [pitch, v, roll, v, fore, v]
var _swing_frame := -1
var _swing_prev_vel := Vector3.ZERO
var _swing_prev_yaw := 0.0
var _swing_acc := Vector3.ZERO               # body acceleration, in the body's own space
var _swing_turn := 0.0


func dangle_arm(side: String, swing: float = 0.0) -> void:
	var s := 1.0 if side == "Left" else -1.0
	for part in ["UpperArm", "LowerArm", "Hand"]:
		var bi := skeleton.find_bone(side + part)
		if _base_rot.has(bi):
			skeleton.set_bone_pose_rotation(bi, _base_rot[bi])
	var dt := clampf(get_process_delta_time(), 0.001, 1.0 / 30.0)
	# what the body did this frame (worked out once, whichever arm asks first)
	if _swing_frame != Engine.get_process_frames():
		_swing_frame = Engine.get_process_frames()
		var acc := (velocity - _swing_prev_vel) / dt
		_swing_prev_vel = velocity
		_swing_acc = _swing_acc.lerp(global_basis.inverse() * acc, 0.5)
		var yaw := global_rotation.y
		_swing_turn = lerpf(_swing_turn, angle_difference(_swing_prev_yaw, yaw) / dt, 0.5)
		_swing_prev_yaw = yaw
	if not _swing.has(side):
		_swing[side] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var st: Array = _swing[side]
	var w := TAU * arm_swing_freq
	var c := 2.0 * arm_swing_damping * w
	# pitch (+ = back): thrown back as it speeds up, forward as it stops; each
	# step kicks it, harder at a run
	var step := cos(walk_phase * 2.0) * swing * (5.0 + 9.0 * run_amount)
	var stride := sin(walk_phase + (0.0 if side == "Left" else PI)) * swing * 6.0
	var fp: float = -w * w * st[0] - c * st[1] + _swing_acc.z * arm_swing_push + step + stride
	# roll (+ = out from the body): flung out to the outside of a turn, and by
	# sideways moves
	var fr: float = -w * w * st[2] - c * st[3] - _swing_acc.x * arm_swing_push * s + _swing_turn * absf(_swing_turn) * 0.6 * s * -1.0
	st[1] += fp * dt
	st[0] = clampf(st[0] + st[1] * dt, -1.2, 1.3)
	st[3] += fr * dt
	st[2] = clampf(st[2] + st[3] * dt, -0.12, 0.7)
	if st[2] <= -0.12 or st[2] >= 0.7:
		st[3] *= -0.3                       # it hits the body (or the end of its reach) and bounces
	# the forearm flops from the broken elbow, lagging the upper arm
	var w2 := TAU * arm_swing_freq * 1.6
	var ff: float = -w2 * w2 * (st[4] + st[0] * 0.45) - 2.0 * 0.14 * w2 * st[5]
	st[5] += ff * dt
	st[4] = clampf(st[4] + st[5] * dt, -1.0, 1.0)
	_turn(side + "UpperArm", Vector3.RIGHT, st[0])
	_turn(side + "UpperArm", Vector3.BACK, (deg_to_rad(6.0) + st[2]) * s)
	_turn(side + "LowerArm", Vector3.BACK, deg_to_rad(-26.0) * s)
	_turn(side + "LowerArm", Vector3.UP, deg_to_rad(38.0) * s)
	_turn(side + "LowerArm", Vector3.RIGHT, st[4])
	_turn(side + "Hand", Vector3.RIGHT, deg_to_rad(48.0) + st[4] * 0.5)


## A hit jolts a dangling arm.
func _kick_arms(strength: float) -> void:
	for side: String in broken_arms:
		if _swing.has(side):
			var st: Array = _swing[side]
			st[1] += randf_range(-1.0, 1.0) * strength
			st[3] += randf_range(0.0, 1.0) * strength * 0.6


# --- a soldier's walk and stance ---------------------------------------------------
## Joint angles through one stride of a real walk, from heel strike (0) to the
## next heel strike of the same foot (1): hip flexion (+ = thigh forward),
## knee flexion, ankle (+ = toe down). Clinical gait averages, a touch
## exaggerated for a soldier marching with a load: the thigh comes well up
## through the swing (that is what lifts the knee), extends only a little
## behind, and the knee bends most just after the foot leaves the ground.
const WALK_HIP := [[0.0, 25.0], [0.15, 18.0], [0.3, 6.0], [0.5, -9.0], [0.6, -12.0], [0.7, 2.0], [0.82, 24.0], [0.9, 31.0], [1.0, 25.0]]
const WALK_KNEE := [[0.0, 4.0], [0.12, 17.0], [0.3, 7.0], [0.45, 5.0], [0.6, 38.0], [0.72, 63.0], [0.85, 34.0], [0.95, 6.0], [1.0, 4.0]]
const WALK_ANKLE := [[0.0, 0.0], [0.08, 7.0], [0.3, -7.0], [0.5, -10.0], [0.62, 17.0], [0.7, 9.0], [0.85, -3.0], [1.0, 0.0]]
const RUN_HIP := [[0.0, 32.0], [0.2, 10.0], [0.4, -16.0], [0.5, -6.0], [0.7, 38.0], [0.85, 48.0], [1.0, 32.0]]
const RUN_KNEE := [[0.0, 18.0], [0.15, 38.0], [0.4, 14.0], [0.55, 70.0], [0.7, 105.0], [0.88, 55.0], [1.0, 18.0]]
const RUN_ANKLE := [[0.0, -2.0], [0.15, -12.0], [0.4, 22.0], [0.6, 10.0], [0.85, -4.0], [1.0, -2.0]]


## A smooth periodic curve through [t, value] keys (Catmull-Rom).
static func _gait_curve(keys: Array, c: float) -> float:
	c = fposmod(c, 1.0)
	var n := keys.size()
	var i := 0
	while i < n - 2 and c > float(keys[i + 1][0]):
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var u := (c - t0) / maxf(t1 - t0, 0.0001)
	var p1: float = keys[i][1]
	var p2: float = keys[i + 1][1]
	var p0: float = keys[i - 1][1] if i > 0 else keys[n - 2][1]
	var p3: float = keys[i + 2][1] if i + 2 < n else keys[1][1]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


## A soldier's legs through the stride (walk blending into run). The left
## foot strikes when the left arm is back, as in any walk.
func _soldier_legs(gait: float, fwd_amt: float, side_amt: float, back := 1.0) -> void:
	var sw := sin(walk_phase)
	var r := run_amount
	var reach := clampf(fwd_amt + 0.3, 0.0, 1.0)
	# Stepping backwards (the cycle runs in reverse): a shorter reach behind,
	# the foot picked up with the knee and put down toe first, never a run.
	if back < 0.0:
		reach *= 0.6
		r = 0.0
	for side: String in ["Left", "Right"]:
		var c := (walk_phase - PI * 1.5) / TAU + (0.0 if side == "Left" else 0.5)
		var limp := side == broken_leg
		var k := 0.35 if limp else 1.0
		var hip := lerpf(_gait_curve(WALK_HIP, c), _gait_curve(RUN_HIP, c), r) * reach
		var knee := lerpf(_gait_curve(WALK_KNEE, c), _gait_curve(RUN_KNEE, c), r)
		var ankle := lerpf(_gait_curve(WALK_ANKLE, c), _gait_curve(RUN_ANKLE, c), r)
		var s := 1.0 if side == "Left" else -1.0
		_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-hip) * gait * k)
		_turn(side + "UpperLeg", Vector3.BACK, deg_to_rad(15.0) * sw * side_amt * gait)
		_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(knee + 4.0) * gait * (0.3 if limp else 1.0))
		_turn(side + "Foot", Vector3.RIGHT, deg_to_rad(ankle) * gait * k)


## Taking aim: hips turned a third of the way round to the right, left foot
## forward toward the target, right foot back and turned out, knees soft,
## weight a little forward; the shoulders come back round onto the target.
func _aim_stance(w: float) -> void:
	if w < 0.01:
		return
	var turn := deg_to_rad(-30.0) * w
	_turn("Hips", Vector3.UP, turn)
	_turn("Spine", Vector3.UP, -turn * 0.55)
	_turn("Chest", Vector3.UP, -turn * 0.35)
	var across := Basis(Vector3.UP, turn) * Vector3.RIGHT          # the pelvis's own left-right axis
	_turn("LeftUpperLeg", across, deg_to_rad(-17.0) * w)
	_turn("LeftLowerLeg", across, deg_to_rad(15.0) * w)
	_turn("LeftFoot", across, deg_to_rad(2.0) * w)
	_turn("RightUpperLeg", across, deg_to_rad(11.0) * w)
	_turn("RightUpperLeg", Vector3.UP, deg_to_rad(-20.0) * w)        # right foot turned out
	_turn("RightLowerLeg", across, deg_to_rad(9.0) * w)
	_turn("RightFoot", across, deg_to_rad(-8.0) * w)
	_turn("Spine", across, deg_to_rad(5.0) * w)                      # leaning into the rifle
	_stance_w = w


var _stance_w := 0.0


# --- the trench club (melee WitzSoldat) ---------------------------------------------
var has_club := false
var _club: Node3D


## A spiked trench club in the right hand: a hardwood haft swelling to a
## heavy head studded with hobnails and big square spikes, an iron band,
## a leather wrist loop.
func give_club() -> void:
	has_club = true
	var att := BoneAttachment3D.new()
	att.bone_name = "RightHand"
	skeleton.add_child(att)
	_club = Node3D.new()
	att.add_child(_club)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.18, 0.09)
	wood.roughness = 0.75
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.11)
	iron.metallic = 0.75
	iron.roughness = 0.5
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.32, 0.15, 0.07)
	rust.metallic = 0.4
	rust.roughness = 0.8
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.09, 0.05)
	leather.roughness = 0.85
	# laid out with the grip at the origin and the head along +Z
	var haft := CylinderMesh.new()
	haft.top_radius = 0.032
	haft.bottom_radius = 0.019
	haft.height = 0.5
	haft.material = wood
	var hm := MeshInstance3D.new()
	hm.mesh = haft
	hm.rotation.x = PI * 0.5
	hm.position = Vector3(0, 0, 0.2)
	hm.layers = 2
	_club.add_child(hm)
	var head := CylinderMesh.new()
	head.top_radius = 0.045
	head.bottom_radius = 0.04
	head.height = 0.2
	head.material = wood
	var hd := MeshInstance3D.new()
	hd.mesh = head
	hd.rotation.x = PI * 0.5
	hd.position = Vector3(0, 0, 0.42)
	hd.layers = 2
	_club.add_child(hd)
	var band := CylinderMesh.new()
	band.top_radius = 0.049
	band.bottom_radius = 0.049
	band.height = 0.025
	band.material = iron
	for z: float in [0.33, 0.51]:
		var b := MeshInstance3D.new()
		b.mesh = band
		b.rotation.x = PI * 0.5
		b.position = Vector3(0, 0, z)
		b.layers = 2
		_club.add_child(b)
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.009
	spike.height = 0.05
	spike.radial_segments = 4
	spike.material = rust
	var rng := RandomNumberGenerator.new()
	rng.seed = 1917
	for ring in 4:
		var z := 0.36 + ring * 0.045
		for k in 6:
			var a := TAU * (k + 0.5 * (ring % 2)) / 6.0 + rng.randf_range(-0.12, 0.12)
			var out := Vector3(cos(a), sin(a), 0)
			var sp := MeshInstance3D.new()
			sp.mesh = spike
			sp.layers = 2
			sp.transform = Transform3D(_basis_along(out, Vector3.BACK).rotated(out, 0.0) * Basis(Vector3.RIGHT, PI * 0.5), out * 0.062 + Vector3(0, 0, z))
			_club.add_child(sp)
	var loop := TorusMesh.new()
	loop.inner_radius = 0.026
	loop.outer_radius = 0.034
	loop.material = leather
	var lp := MeshInstance3D.new()
	lp.mesh = loop
	lp.position = Vector3(0, -0.01, -0.07)
	lp.rotation.x = PI * 0.5
	lp.layers = 2
	_club.add_child(lp)
	# held in the fist: across the palm, pointing forward and a little down
	# with the arm hanging, so it swings with the hand from there on
	var hand := skeleton.find_bone("RightHand")
	var hx := skeleton.get_bone_global_pose(hand)
	var fore := skeleton.get_bone_global_pose(skeleton.find_bone("RightLowerArm")).origin
	var along := (hx.origin - fore).normalized()
	var grip := hx.origin + along * 0.07
	var held := Transform3D(_basis_along(Vector3(0, -0.3, 1).normalized()), grip)
	_club.transform = hx.affine_inverse() * held


## Drop the club where it is (on death).
func _drop_club() -> void:
	if _club == null or not is_instance_valid(_club):
		return
	var xf := _club.global_transform
	var body_ := RigidBody3D.new()
	body_.collision_layer = 1 << 3
	body_.collision_mask = 1 | (1 << 3)
	body_.mass = 2.0
	body_.continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 0.1, 0.6)
	cs.shape = box
	cs.position = Vector3(0, 0, 0.25)
	body_.add_child(cs)
	_club.get_parent().remove_child(_club)
	body_.add_child(_club)
	_club.transform = Transform3D.IDENTITY
	get_parent().add_child(body_)
	body_.global_transform = xf
	body_.linear_velocity = velocity + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1))
	body_.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_club = null


## Extra posing laid over the living pose each frame (event rooms: a
## tightrope walker's arms, a clown playing dead).
var extra_pose: Callable


## Already dead when the player finds it: a limp ragdoll, no death to count.
func make_corpse() -> void:
	dead = true
	set_process(false)
	ragdoll.start(ClownRagdoll.profile_limp(), Vector3.ZERO, Vector3.ZERO)


## Where a rifleman is aiming (world space), set by its brain while aiming.
var aim_point := Vector3.INF
var crouch_amount := 0.0


## Put the rifle where it belongs (slung across the chest at port arms, or
## shouldered with the cheek on the stock), then both hands onto it.
func _hold_rifle() -> void:
	var sk := skeleton
	var to_skel := (sk.global_transform).affine_inverse()
	var a := aim_amount
	var kick := _recoil()
	var cyc := bolt_phase()
	# off the sights while it works the bolt: rifle down a little, head up
	var low := smoothstep(0.0, 0.14, cyc) * (1.0 - smoothstep(0.84, 1.0, cyc)) if cyc >= 0.0 else 0.0
	# the shot slams back into the shoulder: chest and head knocked back
	_turn("Chest", Vector3.RIGHT, deg_to_rad(-7.0) * kick * a)
	_turn("Spine", Vector3.RIGHT, deg_to_rad(-3.0) * kick * a)
	_turn("Neck", Vector3.RIGHT, deg_to_rad(-9.0) * kick * a - deg_to_rad(9.0) * low * a)
	# head down onto the stock when aiming
	_turn("Neck", Vector3.RIGHT, deg_to_rad(14.0) * a)
	_turn("Neck", Vector3.FORWARD, deg_to_rad(-9.0) * a)
	var head := sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var eye := head + Vector3(-0.035, 0.07, 0.1)
	var dir := Vector3.BACK
	if aim_point != Vector3.INF:
		dir = (to_skel * aim_point - eye).normalized()
		var flat := Vector3(dir.x, 0, dir.z)
		if flat.length() < 0.2 or flat.normalized().dot(Vector3.BACK) < 0.5:
			dir = Vector3.BACK                   # not facing it yet: hold straight ahead
		dir.y = clampf(dir.y, -0.6, 0.6)
		dir = dir.normalized()
	var aim_xf := Transform3D(_basis_along(dir), eye + Vector3.DOWN * 0.075 - dir * 0.22)
	var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	# Low ready: butt by the right hip, muzzle forward and down across the
	# body, both arms out in front. It swings a little with each stride and
	# comes up higher when running.
	var sw := sin(walk_phase) * walk_amount
	var carry_dir := Vector3(0.45 + 0.04 * sw, -0.18 + 0.2 * run_amount, 1.0).normalized()
	var carry_at := hips + Vector3(-0.12 + 0.015 * sw, 0.32 + 0.05 * run_amount, 0.02)
	var carry_xf := Transform3D(_basis_along(carry_dir), carry_at)
	var xf := carry_xf.interpolate_with(aim_xf, a * a * (3.0 - 2.0 * a))
	# recoil: driven back into the shoulder, muzzle flipping up, pivoting at the butt
	if kick > 0.001:
		xf = Transform3D(xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-11.0) * kick), xf.origin - xf.basis.z * 0.075 * kick + Vector3.UP * 0.01 * kick)
	# a dying grip: the muzzle sags and the gun drops (negative: jerked up)
	if absf(rifle_droop) > 0.001:
		xf = Transform3D(xf.basis * Basis(Vector3.RIGHT, rifle_droop), xf.origin + Vector3(0, -0.14, 0.04) * maxf(rifle_droop, 0.0))
	# lowered off the shoulder while working the bolt: muzzle dipped, stock off the cheek
	if low > 0.001:
		xf = Transform3D(xf.basis * Basis(Vector3.RIGHT, deg_to_rad(7.0) * low), xf.origin + Vector3(0, -0.045, 0.02) * low * a)
	# a bayonet thrust when it attacks: level, driven forward from the hip
	if attack_amount > 0.01:
		var lunge := Transform3D(_basis_along(Vector3(0, 0.12, 1).normalized()), hips + Vector3(-0.08, 0.34, 0.12 + 0.22 * attack_amount))
		xf = xf.interpolate_with(lunge, smoothstep(0.0, 0.6, attack_amount))
	var chest := sk.get_bone_global_pose(sk.find_bone("Chest"))
	_rifle.transform = chest.affine_inverse() * xf
	# hands: right on the wrist of the stock, left under the fore-end, close
	# enough that the elbows stay bent
	var grip := xf * Vector3(0.0, -0.045, 0.2)
	var fore := xf * Vector3(0.0, -0.035, lerpf(0.33, 0.4, a))
	# the right hand leaves the wrist for the bolt: handle up, back, forward, down
	if cyc >= 0.0 and _bolt:
		var on_bolt := smoothstep(0.04, 0.18, cyc) * (1.0 - smoothstep(0.76, 0.9, cyc))
		var lift := smoothstep(0.18, 0.28, cyc) - smoothstep(0.66, 0.76, cyc)
		var pull := smoothstep(0.3, 0.44, cyc) - smoothstep(0.52, 0.64, cyc)
		_bolt.position = Vector3(-0.035 + 0.012 * lift, 0.04 + 0.022 * lift, 0.29 - 0.085 * pull)
		_bolt.rotation.z = -1.1 * lift
		grip = grip.lerp(xf * (_bolt.position + Vector3(-0.05 + 0.02 * lift, 0.01 + 0.02 * lift, 0.0)), on_bolt)
		if pull > 0.9 and not _cased:
			_cased = true
			_eject_case(xf)
		if cyc > 0.95:
			_bolt.position = Vector3(-0.035, 0.04, 0.29)
			_bolt.rotation.z = 0.0
	var rs := sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var ls := sk.get_bone_global_pose(sk.find_bone("LeftUpperArm")).origin
	# elbows: down and a little out when carrying; when the rifle is shouldered
	# the right one goes out to the side but stays well below the shoulder
	var ab := a * a * (3.0 - 2.0 * a)
	reach("Right", grip, rs + Vector3(-0.4, -0.55, -0.15).lerp(Vector3(-0.42, -0.5, -0.12), ab))
	reach("Left", fore, ls + Vector3(0.3, -0.6, 0.05).lerp(Vector3(0.15, -0.65, 0.0), ab))
	point_bone("RightHand", xf.basis.z)
	point_bone("LeftHand", xf.basis.z)


## A basis whose +Z runs along `dir`, as level as it can be.
static func _basis_along(dir: Vector3, up_hint: Vector3 = Vector3.UP) -> Basis:
	var z := dir.normalized()
	var x := up_hint.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## Two-bone reach (skeleton space): point the upper arm and forearm so the
## wrist lands on `target`, the elbow bowed toward `pole`.
func reach(side: String, target: Vector3, pole: Vector3) -> void:
	var sk := skeleton
	var ua := sk.find_bone(side + "UpperArm")
	var la := sk.find_bone(side + "LowerArm")
	var hb := sk.find_bone(side + "Hand")
	var s_pos := sk.get_bone_global_pose(ua).origin
	var e_pos := sk.get_bone_global_pose(la).origin
	var w_pos := sk.get_bone_global_pose(hb).origin
	var a := s_pos.distance_to(e_pos)
	var b := e_pos.distance_to(w_pos)
	var to_t := target - s_pos
	var d := clampf(to_t.length(), absf(a - b) + 0.01, (a + b) * 0.995)
	var dir := to_t.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := (pole - s_pos) - dir * (pole - s_pos).dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN
	bend = bend.normalized()
	var elbow := s_pos + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	aim_bone(ua, la, elbow)
	aim_bone(la, hb, s_pos + dir * d)


## Rotate `bone` so its child lies toward `target` (skeleton space).
func aim_bone(bone: int, child: int, target: Vector3) -> void:
	var sk := skeleton
	var gp := sk.get_bone_global_pose(bone)
	var cur := sk.get_bone_global_pose(child).origin - gp.origin
	var want := target - gp.origin
	if cur.length() < 0.0001 or want.length() < 0.0001:
		return
	_rotate_global(bone, Quaternion(cur.normalized(), want.normalized()))


## Turn a bone (usually a hand) so it points along `dir` (skeleton space).
func point_bone(bone_name: String, dir: Vector3) -> void:
	var bi := skeleton.find_bone(bone_name)
	var gp := skeleton.get_bone_global_pose(bi)
	var cur := gp.basis.y.normalized()
	if dir.length() < 0.0001:
		return
	_rotate_global(bi, Quaternion(cur, dir.normalized()))


func _rotate_global(bone: int, q: Quaternion) -> void:
	var sk := skeleton
	var gp := sk.get_bone_global_pose(bone)
	var wanted := Basis(q) * gp.basis
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (pg.inverse() * wanted).get_rotation_quaternion())


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
	Blood.spawn_hit(at, dir, 0.4, mechanical)


# --- weapons ----------------------------------------------------------------------
var has_rifle := false
## Seconds the bolt takes to work (lower, handle up, back, forward, down, back on aim).
@export var bolt_seconds := 1.05
var _bolt: Node3D
var _shot_t := 99.0               # seconds since the last shot
var _cased := true                # this cycle's empty case already thrown out
var _sfx: Array[AudioStreamPlayer3D] = []
var _sfx_next := 0
var _muzzle: Node3D
var _rifle: Node3D
var _rifle_attach: BoneAttachment3D
var _rifle_aimed := Transform3D()
var _rifle_carried := Transform3D()


## How far through working the bolt it is (0..1), or -1 when it is not.
func bolt_phase() -> float:
	if not has_rifle or _rifle == null or bolt_seconds <= 0.0:
		return -1.0
	var u := (_shot_t - 0.3) / bolt_seconds
	return u if u >= 0.0 and u <= 1.0 else -1.0


## True from the shot until the next round is chambered and it is back on aim.
func cycling() -> bool:
	return has_rifle and (_shot_t < 0.3 + bolt_seconds or reload_t > 0.0)


## Seconds left changing the magazine (a machine gunner); the gun is off aim.
var reload_t := 0.0
## Muzzle dipped this far (radians) and the gun sagging: a dying man's grip.
var rifle_droop := 0.0


## The recoil's kick (0..1): instant, then easing back over a quarter second.
func _recoil() -> float:
	var t := _shot_t
	if t > 0.6:
		return 0.0
	if t < 0.02:
		return t / 0.02
	return exp(-(t - 0.02) * 11.0) * (1.0 + 0.15 * sin((t - 0.02) * 30.0))


## Bang: the kick, a muzzle flash you can see, a puff of smoke, the report;
## then (on its own) the bolt is worked to chamber the next round.
func fired() -> void:
	_shot_t = 0.0
	_cased = false
	var at := muzzle_position()
	var dir := global_basis.z
	if _muzzle and is_instance_valid(_muzzle):
		dir = _muzzle.global_basis.z
	MuzzleFlash.burst(get_parent(), at, dir, 1.0 if has_rifle else 0.6)
	play_sfx("shot_%d" % (randi() % 3), at, 6.0 if has_rifle else 0.0, 1.0 if has_rifle else 1.5)
	if has_rifle:
		get_tree().create_timer(0.3 + bolt_seconds * 0.2).timeout.connect(func() -> void:
			if is_instance_valid(self) and not dead:
				play_sfx("bolt_open", muzzle_position(), -4.0))
		get_tree().create_timer(0.3 + bolt_seconds * 0.5).timeout.connect(func() -> void:
			if is_instance_valid(self) and not dead:
				play_sfx("bolt_close", muzzle_position(), -4.0))


## The spent case, spat out of the breech to the right.
func _eject_case(xf: Transform3D) -> void:
	var at := skeleton.global_transform * (xf * Vector3(0.0, 0.05, 0.27))
	var right := -(skeleton.global_basis * xf.basis.x).normalized()
	var body_ := RigidBody3D.new()
	body_.collision_layer = 1 << 3
	body_.collision_mask = 1
	body_.mass = 0.012
	var cs := CollisionShape3D.new()
	var cap := CylinderShape3D.new()
	cap.radius = 0.006
	cap.height = 0.055
	cs.shape = cap
	body_.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.005
	cm.bottom_radius = 0.0065
	cm.height = 0.055
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.52, 0.2)
	brass.metallic = 0.9
	brass.roughness = 0.3
	cm.material = brass
	mi.mesh = cm
	mi.layers = 2
	body_.add_child(mi)
	get_parent().add_child(body_)
	body_.global_position = at
	body_.linear_velocity = right * randf_range(1.6, 2.4) + Vector3.UP * randf_range(1.2, 2.0) + velocity
	body_.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if is_instance_valid(body_):
			play_sfx("casing_%d" % (randi() % 2), body_.global_position, -10.0))
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if is_instance_valid(body_):
			body_.freeze = true)


## A sound from the rifle (art/witzsoldat/sfx).
func play_sfx(sound: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if not is_inside_tree():
		return
	if _sfx.is_empty():
		for i in 3:
			var p := AudioStreamPlayer3D.new()
			p.unit_size = 6.0
			p.max_distance = 60.0
			add_child(p)
			_sfx.append(p)
	var stream: AudioStream = _sfx_cache.get(sound)
	if stream == null:
		var path := "res://art/witzsoldat/sfx/%s.wav" % sound
		if not ResourceLoader.exists(path):
			return
		stream = load(path)
		_sfx_cache[sound] = stream
	var pl := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	pl.stream = stream
	pl.global_position = at
	pl.volume_db = db
	pl.pitch_scale = pitch * randf_range(0.95, 1.05)
	pl.play()


static var _sfx_cache := {}


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
	_bolt = _rifle.get_child(_rifle.get_child_count() - 1)
	var knob := MeshInstance3D.new()                                                      # the bolt's ball knob
	var sm := SphereMesh.new()
	sm.radius = 0.011
	sm.height = 0.022
	sm.material = steel
	knob.mesh = sm
	knob.position = Vector3(-0.03, 0, 0)
	knob.layers = 2
	_bolt.add_child(knob)
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
	always_pose = true                  # the hands stay on the rifle every frame
	set_process(true)


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
func give_gun(side: String = "Right") -> void:
	has_gun = true
	gun_side = side
	var att := BoneAttachment3D.new()
	att.bone_name = side + "Hand"
	skeleton.add_child(att)
	_gun_att = att
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
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone(side + "Hand"))
	gun.transform = hand.affine_inverse() * Transform3D(Basis.IDENTITY, hand.origin + Vector3(-0.1 if side == "Right" else 0.1, -0.02, 0.0))


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
