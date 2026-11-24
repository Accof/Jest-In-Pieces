class_name Clown
extends Node3D
## One clown enemy: model, hit zones, health, and what happens when it is shot.

signal died(clown: Clown)
## Emitted every time this clown is shot, fatal or not.
signal hurt(clown: Clown)

## Every enemy body shares the clown's skeleton names and segment layout, so
## the ragdoll, deaths and gore all work on each of them.
const BODIES := {
	# The trench clown (24 Nov 2026): Andrew's Tripo model, rigged and segmented
	# by tools/build_trench_clown.py on the WitzSoldat's skeleton at his height.
	# Black leather greatcoat, a Stahlhelm with a riveted eye-slit visor over the
	# face, a bloody grin under it; a trench club in his hand (Game._spawn_clown).
	# His helmet stays on (no separate helmet: the visor is riveted to it and
	# nothing is modelled behind it; the tool says why). PBR maps kept; the gibs
	# carry no images and take the body's material. The old blockout
	# (art/clown/) is only the carved face over dugout doors now.
	"clown": {
		model = "res://art/trench_clown/trench_clown.glb", gibs = "res://art/trench_clown/trench_clown_gibs.glb",
		rest_min = Vector3(-0.79689, -0.005, -0.24182), rest_size = Vector3(1.59838, 1.90498, 0.49089),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.2, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
		muddy = true,
		grime_cap = 2,                            # leather: splashed at worst, never caked (it would read as khaki)
		pbr = true,
		share_material = true,
		mocap_legs = true,                        # walks on the motion-captured legs (SoldierClips), arms its own
	},
	"witzsoldat": {
		muddy = true,
		model = "res://art/witzsoldat/witzsoldat.glb", gibs = "res://art/witzsoldat/witzsoldat_gibs.glb",
		rest_min = Vector3(-0.91675, -0.005, -0.28225), rest_size = Vector3(1.83328, 1.91, 0.56441),
		helmet = "res://art/witzsoldat/witzsoldat_helmet.glb",
		helmet_center = Vector3(0.0, 1.80985, 0.04376), helmet_size = Vector3(0.268, 0.232, 0.288),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.25, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
		soldier = true,
		# two looks, one soldier: each WitzSoldat wears one of these, chosen at
		# random when it is made (see `look`); everything it does is the same
		looks = ["witzsoldat", "witzsoldat_dark"],
	},
	# The dark WitzSoldat: a second look for the WitzSoldat, not an enemy of its own
	# (only model, gibs, helmet and their fit; the rest is the WitzSoldat's).
	# Rigged and segmented from the Tripo model by tools/build_witzsoldat_dark.py
	# on the WitzSoldat's own skeleton, at his height. It keeps the model's PBR
	# maps (pbr); its gibs and helmet carry no images and take the body's
	# material (share_material). Its Stahlhelm is steel: no roughness override.
	"witzsoldat_dark": {
		muddy = true,
		model = "res://art/witzsoldat_dark/witzsoldat_dark.glb", gibs = "res://art/witzsoldat_dark/witzsoldat_dark_gibs.glb",
		rest_min = Vector3(-0.96070, -0.00508, -0.20810), rest_size = Vector3(1.92620, 1.89495, 0.42203),
		helmet = "res://art/witzsoldat_dark/witzsoldat_dark_helmet.glb",
		helmet_center = Vector3(-0.00017, 1.80238, 0.01264), helmet_size = Vector3(0.31034, 0.25523, 0.34894),
		pbr = true,
		share_material = true,
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
		muddy = true,
		surface = Vector2(0.93, 0.22),            # wool serge and webbing: roughness, specular
		helmet_roughness = 0.72,
		helmet_center = Vector3(-0.00046, 1.80501, 0.04647), helmet_size = Vector3(0.312, 0.210, 0.325),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.25, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
		soldier = true,
	},
	# Der Zornhauptmann (tools/build_zornhauptmann.py, zornhauptmann.json): the
	# officer, his Pickelhaube cut off the Tripo model on its brim line
	"zornhauptmann": {
		model = "res://art/zornhauptmann/zornhauptmann.glb", gibs = "res://art/zornhauptmann/zornhauptmann_gibs.glb",
		rest_min = Vector3(-0.95944, -0.00494, -0.21322), rest_size = Vector3(1.92491, 1.81963, 0.43054),
		helmet = "res://art/zornhauptmann/zornhauptmann_helmet.glb",
		muddy = true,
		grime_cap = 1,                            # an officer: dusty at worst, never caked
		surface = Vector2(0.82, 0.3),             # wool tunic, leather belts and boots
		helmet_roughness = 0.32,                  # boiled, lacquered leather
		innards_scale = {&"head": 0.75},          # a smaller skull under the Pickelhaube (crown at 1.69 m)
		helmet_center = Vector3(-0.00027, 1.73536, 0.04043), helmet_size = Vector3(0.242, 0.349, 0.287),
		shapes = {&"UpperLeg": 1.3, &"LowerLeg": 1.12, &"UpperArm": 1.25, &"LowerArm": 1.05,
			&"Hips": 1.2, &"Spine": 1.2, &"Chest": 1.2, &"Neck": 1.12, &"Foot": 1.15},
		soldier = true,
	},
}

## Which body this enemy wears (a key of BODIES). Set before adding to the tree.
@export var body := "clown"
## Which look it wears, for a body that has more than one (BODIES[body].looks):
## left empty, it is picked at random when the enemy is made, each look as
## likely, each enemy on its own roll; then it stays for the enemy's life,
## corpse and gibs included. A look changes only the model, gibs and helmet
## (their keys in its BODIES entry): `body` still decides everything it does.
@export var look := ""
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
	if look == "":
		look = pick_look(body)
	if look != body:
		spec = spec.merged(BODIES[look], true)
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
	_roll_grime()
	if spec.has("helmet"):
		_put_on_helmet()
	gore = ClownGore.new()
	add_child(gore)
	gore.setup(self)
	ragdoll.settled.connect(_on_settled)
	_snap_fingers.call_deferred()
	gore.part_severed.connect(func(seg: StringName, _gib: Node3D) -> void:
		var sn := String(seg)
		if sn.contains("Arm") or sn.ends_with("Hand"):
			_arm_lost("Left" if sn.begins_with("Left") else "Right"))


## A look for a new enemy of `body`: one of its looks, each as likely (the
## body itself if it has only the one). Its own roll every time.
static func pick_look(of_body: String) -> String:
	var looks: Array = BODIES[of_body].get("looks", [of_body])
	return looks[randi() % looks.size()]


## The body model's own (imported) material: its textures, for the gibs and
## helmet of a look that shares them.
func body_material() -> Material:
	var m := mesh.mesh
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		if mat and mat.resource_name == "Material":
			return mat
	return m.surface_get_material(0)


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
	if bleeding_out:
		_throat_hit(info)
	if executing and (info.get("blast", false) or info.get("stake", false)):
		var m := get_node_or_null("Marionette") as Marionette
		if m:
			m.release_now()
	var bone := StringName(pb.bone_name)
	var zone := _zone(bone)
	var dir: Vector3 = info.direction.normalized()
	var raw: float = info.damage
	# how hard the body reacts (flinch, stagger, arms): the damage, unless the
	# weapon says otherwise (the revolver reacts like the pistol)
	var react: float = float(info.get("react", raw))
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
			if zone != &"Hips" and info.get("weapon", "") in ["Shotgun", "Trench Shotgun"] and float(info.get("dist", 99.0)) < punch_range \
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
	if not info.get("can_dismember", false) and not info.get("stake", false) and not info.get("crossbow", false):
		_wear(zone, bone, info.position, dir, raw)

	var was_dead := dead
	_fatal_severed = severed
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
		_flinch_from(info.position, dir, react * (1.8 if severed else 1.0) * (0.35 if pinned else 1.0))
	if info.get("crossbow", false) and not dead:
		_bolt_impair(zone, limb_side)
	if not dead and not broken_arms.is_empty():
		_kick_arms(clampf(react / 10.0, 1.0, 6.0))
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
		elif zone == &"Neck" and not info.get("heavy", false) and not info.get("crossbow", false):
			impulse = dir * 27.0 + Vector3.UP * 3.0   # a sharp whip of the head, not a launch
		ragdoll.apply_hit(bone, impulse, info.position)
	if severed:
		if zone == &"Neck":
			knock_off_helmet(dir, info.position)
		gore.sever(bone, dir * float(info.get("impulse", 12.0)))


# --- Carnival Curse ------------------------------------------------------------------
## Under the Carnival Curse (a Marionette child has his skeleton): the
## killcam waits for it, and nothing else poses him.
var executing := false
## Some enemies (a boss) shrug the curse off.
var curse_immune := false


## Why this one cannot be cursed now ("" if it can).
func curse_block() -> String:
	if dead or executing:
		return "dead"
	if curse_immune:
		return "immune"
	if crawling or downed or last_stand or _halved or ragdoll.active:
		return "down"
	if skeleton == null or skeleton.find_bone("Neck") < 0 or skeleton.find_bone("LeftUpperArm") < 0:
		return "body"
	return ""


## The Carnival Curse lands: dead and counted now, his weapons dropped,
## everything he was doing stopped, and the Marionette takes him over.
## Returns false (nothing happens) if he cannot be cursed.
func begin_curse(cfg: Dictionary, at: Vector3, from_dir: Vector3) -> bool:
	if curse_block() != "":
		return false
	executing = true
	dead = true
	reload_t = 0.0
	attack_amount = 0.0
	aim_amount = 0.0
	walk_amount = 0.0
	run_amount = 0.0
	crouch_amount = 0.0
	velocity = Vector3.ZERO
	aim_point = Vector3.INF
	_record_death({position = at, direction = from_dir, weapon = "Carnival Curse", curse = true}, &"Chest")
	_drop_weapons()
	_curse_prepare()
	set_process(false)
	Marionette.start(self, cfg, at)
	return true


## A subclass stops whatever staged business it had (the Rattlejack's).
func _curse_prepare() -> void:
	pass


## The Marionette has let go (the ragdoll has him).
func curse_released() -> void:
	executing = false


func _die(info: Dictionary, zone: StringName) -> void:
	if _throat_ok(info, zone):
		_begin_throat(info, zone)
		return
	dead = true
	_end_living_pin()
	if not pins.is_empty() or info.get("pinned", false):
		info = info.duplicate()
		info["profile"] = ClownRagdoll.profile_pinned()
		info["impulse"] = minf(float(info.get("impulse", 2.0)), 2.0)
	_start_ragdoll(info, zone)
	_pin_corpse()
	_record_death(info, zone)


# --- shot through the throat ----------------------------------------------------------
## A fatal round through the neck (not the head): the weapon drops, both
## hands go to the throat, the knees go, and it writhes on the floor while
## the artery pumps blood out in spurts that weaken with every beat, over
## the floor and up the walls. Then it is still. The kill counts at once;
## another round (after the first moment) ends it there and then.
@export_group("Throat")
@export var enable_throat_death := true
@export var throat_death_chance := 1.0           ## of fatal throat shots
@export var throat_bleed_seconds := Vector2(5.0, 7.5)
@export var throat_interrupt_grace := 0.35       ## rounds this soon after the fatal one (a held trigger) do not end it
@export var throat_spurt_strength := 1.0
var throat_hold_y := -0.1                         # tuning: where the arms' muscles aim the hands, up/down from the throat
@export_group("")
var bleeding_out := false                        ## a throat death playing out (the killcam waits for it)
var throat_death := false                        ## tests: how this one died
var throat_spurts := 0
var throat_interrupted := false
var force_throat := false                        ## tests: a neck hit counts as the throat wherever it lands
var _thr := {}
var _fatal_severed := false


## Whether a round landed in the neck itself: under the chin on the neck
## bone, or on the very top of the chest, in the middle.
func is_throat_hit(info: Dictionary, zone: StringName) -> bool:
	if not info.has("position"):
		return false
	var p := skeleton.global_transform.affine_inverse() * (info.position as Vector3)
	var head := skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	var neck := skeleton.get_bone_global_pose(skeleton.find_bone("Neck")).origin
	if zone == &"Neck":
		return force_throat or p.y <= head.y + 0.035
	if zone == &"Chest":
		# the top of the chest box, in the middle: the base of the neck (and
		# never the chest itself, on a body whose neck bone sits low)
		var chest_pb: PhysicalBone3D = ragdoll.bones.get(&"Chest")
		var chest_c := (skeleton.global_transform.affine_inverse() * chest_pb.global_position).y if chest_pb else -INF
		return p.y >= maxf(neck.y - 0.03, chest_c + 0.09) and absf(p.x - neck.x) < 0.1
	return false


func _throat_ok(info: Dictionary, zone: StringName) -> bool:
	if not enable_throat_death or mechanical or skeleton == null:
		return false
	if info.get("blast", false) or info.get("stake", false) or info.has("profile") or pinned or info.get("pinned", false):
		return false
	if _fatal_severed or _head_open or crawling or downed or last_stand or _halved or ragdoll.active:
		return false
	if not is_throat_hit(info, zone):
		return false
	return randf() < throat_death_chance


## Let go of whatever it was holding.
func _drop_weapons() -> void:
	_drop_rifle()
	has_rifle = false
	if has_gun:
		_drop_gun()
		has_gun = false
	_drop_club()
	has_club = false


func _begin_throat(info: Dictionary, zone: StringName) -> void:
	dead = true
	throat_death = true
	bleeding_out = true
	throat_interrupted = false
	throat_spurts = 0
	_record_death(info, zone)
	_drop_weapons()
	var sk := skeleton
	var to_skel := sk.global_transform.affine_inverse()
	var neck_pb: PhysicalBone3D = ragdoll.bones[&"Neck"]
	var wound: Vector3 = info.get("position", neck_pb.global_position)
	var p := to_skel * wound
	var nb := sk.get_bone_global_pose(sk.find_bone("Neck")).origin
	# the hole faces out from the middle of the neck, mostly forward
	var out := Vector3(p.x - nb.x, 0, p.z - nb.z)
	out = (out.normalized() if out.length() > 0.01 else Vector3.BACK) + Vector3.BACK * 0.6
	var out_w := sk.global_basis * out.normalized()
	# the wound sits on the throat's surface, not wherever the round went in
	var surface := sk.global_transform * Vector3(nb.x, clampf(p.y, nb.y + 0.02, nb.y + 0.12), nb.z) + out_w * 0.055
	_thr = {
		t = 0.0, T = randf_range(throat_bleed_seconds.x, maxf(throat_bleed_seconds.y, throat_bleed_seconds.x)),
		local = neck_pb.global_transform.affine_inverse() * surface,
		dir = (neck_pb.global_basis.orthonormalized().inverse() * out_w).normalized(),
		beat = 0.05, writhe = 0.3, gurgle = randf_range(0.2, 0.5), shot = info.get("shot_id", -1),
		pool_t = 0.9, rate = randf_range(1.5, 1.9),
	}
	# the arms' muscles are set to hold the hands at the throat; they get
	# there on their own (the arms come up), not by a jump in the pose
	var keep := {}
	for side: String in ["Left", "Right"]:
		for part: String in ["UpperArm", "LowerArm", "Hand"]:
			var bi := sk.find_bone(side + part)
			keep[bi] = sk.get_bone_pose_rotation(bi)
	var throat := to_skel * surface + Vector3(0, 0.03 + throat_hold_y, 0.02)
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		var sh := sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
		reach(side, throat + Vector3(0.035 * s, -0.01 if s > 0.0 else 0.02, 0.02), sh + Vector3(0.3 * s, -0.4, 0.15))
		point_bone(side + "Hand", Vector3(-s, 0.25, -0.2))
	for side: String in ["Left", "Right"]:
		for part: String in ["UpperArm", "LowerArm", "Hand"]:
			var bi := sk.find_bone(side + part)
			var pbn := StringName(side + part)
			var parent_bone: StringName = &"Chest" if part == "UpperArm" else StringName(side + ("UpperArm" if part == "LowerArm" else "LowerArm"))
			var pi := sk.find_bone(parent_bone)
			# the joint's angle as the physical bones measure it (body = pose * rest^-1)
			var rel := sk.get_bone_global_rest(pi).basis * sk.get_bone_global_pose(pi).basis.inverse() \
				* sk.get_bone_global_pose(bi).basis * sk.get_bone_global_rest(bi).basis.inverse()
			ragdoll.eq_override[pbn] = rel.orthonormalized()
	for bi: int in keep:
		sk.set_bone_pose_rotation(bi, keep[bi])
	# hands and forearms pressed to the neck and chest must not be held off them
	for side: String in ["Left", "Right"]:
		for part: String in ["Hand", "LowerArm"]:
			var a: PhysicalBone3D = ragdoll.bones.get(StringName(side + part))
			for other: StringName in [&"Neck", &"Chest"]:
				var b: PhysicalBone3D = ragdoll.bones.get(other)
				if a and b:
					PhysicsServer3D.body_add_collision_exception(a.get_rid(), b.get_rid())
					PhysicsServer3D.body_add_collision_exception(b.get_rid(), a.get_rid())
	var fling := ragdoll.arm_fling
	ragdoll.arm_fling = 0.0
	var d: Vector3 = info.get("direction", Vector3.ZERO)
	ragdoll.start(ClownRagdoll.profile_throat(_thr.T, ragdoll.fall_speed), Vector3(d.x, 0, d.z), velocity * 0.3)
	ragdoll.arm_fling = fling
	gore.start_bleeding()
	set_process(true)


## Every frame of the bleed-out: the heart pumps, the body fights, the hands
## press on the wound.
func _throat_process(delta: float) -> void:
	var d := minf(delta, 1.0 / 30.0)
	_thr.t += d
	var t: float = _thr.t
	var T: float = _thr.T
	var life := clampf(1.0 - t / T, 0.0, 1.0)
	var neck_pb: PhysicalBone3D = ragdoll.bones.get(&"Neck")
	if neck_pb == null or not is_instance_valid(neck_pb):
		_end_throat()
		return
	# the heartbeat: a spurt each beat, weaker and slower as the blood runs out
	if not throat_interrupted and life > 0.0:
		_thr.beat -= d
		if _thr.beat <= 0.0:
			_thr.beat = 1.0 / (float(_thr.rate) * lerpf(0.55, 1.0, life))
			_spurt(neck_pb, pow(life, 0.6) * throat_spurt_strength)
	# and between the beats it never stops: a steady run of blood from the wound
	if not throat_interrupted and life > 0.0:
		_thr.flow = float(_thr.get("flow", 0.0)) - d
		if _thr.flow <= 0.0:
			_thr.flow = 0.045
			var at := neck_pb.global_transform * (_thr.local as Vector3)
			var dir := (neck_pb.global_basis.orthonormalized() * (_thr.dir as Vector3)).normalized()
			var pulse := 0.5 + 0.5 * clampf(float(_thr.beat) * float(_thr.rate), 0.0, 1.0)   # strongest just after a beat
			Blood.add_droplet(at, (dir + Vector3.UP * 0.1) * randf_range(0.6, 1.8) * (0.35 + 0.65 * life) * pulse + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.2), randf_range(-0.2, 0.2)), randf_range(0.035, 0.07))
	# writhing: twisting, kicking, the back arching; weaker as it dies
	if not throat_interrupted and life > 0.0:
		_thr.writhe -= d
		if _thr.writhe <= 0.0:
			_thr.writhe = randf_range(0.12, 0.4)
			var parts := [&"Spine", &"Chest", &"Hips", &"LeftUpperLeg", &"RightUpperLeg", &"LeftLowerLeg", &"RightLowerLeg", &"Neck"]
			var pb: PhysicalBone3D = ragdoll.bones.get(parts.pick_random())
			if pb and is_instance_valid(pb):
				var kick := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				var on_floor := t > 1.4
				PhysicsServer3D.body_apply_torque_impulse(pb.get_rid(), kick * pb.mass * randf_range(0.4, 1.0) * (0.35 + 0.65 * life) * (1.0 if on_floor else 0.45))
				# and a knee drawn up, now one side, now the other
				if on_floor and randf() < 0.45:
					var leg: PhysicalBone3D = ragdoll.bones.get([&"LeftUpperLeg", &"RightUpperLeg"].pick_random())
					var hips_pb: PhysicalBone3D = ragdoll.bones.get(&"Hips")
					if leg and hips_pb:
						PhysicsServer3D.body_apply_torque_impulse(leg.get_rid(), hips_pb.global_basis.x.normalized() * leg.mass * randf_range(-0.9, -0.4) * (0.4 + 0.6 * life))
	# the hands clamp onto the wound and stay there (a spring on each hand
	# and forearm toward the throat, weakening only at the very end)
	if not throat_interrupted:
		var grip := clampf((float(_thr.T) + 0.8 - t) / 1.6, 0.0, 1.0)
		var wound: Vector3 = neck_pb.global_transform * (_thr.local as Vector3)
		var across := neck_pb.global_basis.x.normalized()
		var out := (neck_pb.global_basis.orthonormalized() * (_thr.dir as Vector3)).normalized()
		for side: String in ["Left", "Right"]:
			var s := 1.0 if side == "Left" else -1.0
			for spec: Array in [["Hand", across * 0.035 * s + out * 0.02, 320.0], ["LowerArm", across * 0.1 * s + out * 0.06 + Vector3.DOWN * 0.12, 160.0]]:
				var pb: PhysicalBone3D = ragdoll.bones.get(StringName(side + String(spec[0])))
				if pb == null or not is_instance_valid(pb):
					continue
				var v: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				var f: Vector3 = ((wound + (spec[1] as Vector3)) - pb.global_position) * float(spec[2]) - v * 14.0
				# a constant force, re-set every frame (so the frame rate does not change it)
				PhysicsServer3D.body_set_constant_force(pb.get_rid(), (f * pb.mass).limit_length(110.0 * pb.mass) * grip)
	if not throat_interrupted and life > 0.0:
		_thr.gurgle -= d
		if _thr.gurgle <= 0.0:
			_thr.gurgle = randf_range(1.2, 2.4)
			SfxSynth.play(get_parent(), "gurgle" if randf() < 0.7 else "choke", neck_pb.global_position, lerpf(-16.0, -3.0, life), randf_range(0.85, 1.05))
	if t > T + 1.5 or (throat_interrupted and t > float(_thr.get("stop", t)) + 0.5):
		_end_throat()


## One beat of the artery: a jet out of the wound (it reaches the walls), a
## mist, drops arcing onto the floor, and the pool under the neck fed.
func _spurt(neck_pb: PhysicalBone3D, strength: float) -> void:
	throat_spurts += 1
	var at := neck_pb.global_transform * (_thr.local as Vector3)
	var dir := (neck_pb.global_basis.orthonormalized() * (_thr.dir as Vector3)).normalized()
	var jet := (dir + Vector3.UP * 0.2 + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.15), randf_range(-0.15, 0.15))).normalized()
	Blood.spawn_hit(at, jet, clampf(0.35 + 1.1 * strength, 0.3, 1.5))
	for i in 3 + int(9.0 * strength):
		var v := jet * randf_range(1.2, 4.4) * (0.4 + 0.6 * strength) + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.6), randf_range(-0.3, 0.3))
		Blood.add_droplet(at, v, randf_range(0.05, 0.11))
	# and onto whatever is close in front of it
	var space := get_world_3d().direct_space_state
	for i in 2:
		var dd := (jet + Vector3(randf_range(-0.3, 0.3), randf_range(-0.25, 0.25), randf_range(-0.3, 0.3))).normalized()
		var q := PhysicsRayQueryParameters3D.create(at, at + dd * (1.2 + 2.0 * strength), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			Blood.spawn_decal(hit.position, hit.normal, randf_range(0.25, 0.5) * (0.6 + 0.6 * strength), "impact" if absf(dd.dot(hit.normal)) > 0.5 else "streak", dd - (hit.normal as Vector3) * dd.dot(hit.normal))
	# the pool under the neck grows as long as it pumps (once he is down
	# there: a pool started while he stood would end up at his feet)
	_thr.pool_t -= 1.0 / float(_thr.rate)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * 1.8, 1)
	var under := space.intersect_ray(q)
	if _thr.pool_t <= 0.0 and not under.is_empty() and at.y - (under.position as Vector3).y < 0.4:
		_thr.pool_t = 1.0
		Blood.spawn_pool(under.position, under.normal, 0.4 + 0.5 * clampf(float(_thr.t) / float(_thr.T), 0.0, 1.0))


## Where the hole in the throat is now (world), while bleeding out.
func throat_wound_position() -> Vector3:
	var neck_pb: PhysicalBone3D = ragdoll.bones.get(&"Neck")
	if neck_pb == null or _thr.is_empty():
		return Vector3.INF
	return neck_pb.global_transform * (_thr.local as Vector3)


## Shot again while bleeding out: that one finishes it (after a short grace
## for rounds still coming from the same trigger pull).
func _throat_hit(info: Dictionary) -> void:
	if throat_interrupted:
		return
	if info.get("shot_id", -2) == _thr.get("shot", -1) or float(_thr.get("t", 0.0)) < throat_interrupt_grace:
		return
	throat_interrupted = true
	_thr["stop"] = _thr.t
	_release_throat()
	ragdoll.restart(ClownRagdoll.profile_limp())


## Let go of the throat (no more pull on the hands).
func _release_throat() -> void:
	for side: String in ["Left", "Right"]:
		for part: String in ["Hand", "LowerArm"]:
			var pb: PhysicalBone3D = ragdoll.bones.get(StringName(side + part))
			if pb and is_instance_valid(pb):
				PhysicsServer3D.body_set_constant_force(pb.get_rid(), Vector3.ZERO)


func _end_throat() -> void:
	_release_throat()
	bleeding_out = false
	set_process(false)


## The body goes over: picks how it falls (or takes info.profile) and hands it
## to the ragdoll. A subclass can call this some time after the death itself
## (the Klappersoldat stands, kneels or seizes up first).
func _start_ragdoll(info: Dictionary, zone: StringName) -> void:
	# the hands lose their grip as it goes (a hand on a bolt keeps a little of it)
	if ClownHands.has_fingers(skeleton):
		for side: String in ["Left", "Right"]:
			var keep := 0.62 if _pin_hand_grip.has(side) else 0.45
			ClownHands.pose(skeleton, side, keep, keep * 0.8)
	var profile: Dictionary
	var wall_gap := -1.0 if crawling or info.get("blast", false) or info.get("stake", false) else _wall_behind(info.direction)
	if force_variant == "wall_slide" and wall_gap < 0.0:
		wall_gap = 0.5
	# the ground falls away behind it (the edge of a trench, a footbridge's
	# side): thrown back, it goes over
	var drop := false
	if not (crawling or last_stand or ragdoll.active or info.has("profile")) and info.has("direction"):
		drop = _drop_behind(info.direction)
	if info.has("profile"):
		profile = info.profile                      # the caller knows best (an event room)
	elif info.get("blast", false) or info.get("stake", false):
		profile = ClownRagdoll.profile_blast()      # no fight left: it goes where it is carried
	elif crawling or last_stand:
		profile = ClownRagdoll.profile_limp()
	elif not info.get("heavy", false) and wall_gap >= 0.0 and (force_variant == "wall_slide" or (force_variant == "" and randf() < WALL_SLIDE_CHANCE)):
		profile = ClownRagdoll.profile_wall_slide(wall_gap)
	elif info.get("heavy", false):
		profile = ClownRagdoll.profile_heavy(force_variant == "heavy_flat" or (force_variant == "" and randf() < 0.45))
	elif force_variant == "" and velocity.length() > 1.5 and randf() < 0.6 and not drop:
		profile = ClownRagdoll.profile_tumble()
	elif zone == &"Neck":
		profile = ClownRagdoll.profile_headshot(force_variant)
	else:
		# A gut shot usually folds the clown forward; a chest shot throws it back.
		var v := force_variant
		if v == "" and drop and randf() < 0.85:
			v = ["blown_back", "stagger"].pick_random()
		if v == "":
			v = ("double" if randf() < 0.15 else "double_flat") if (zone in [&"Spine", &"Hips"] and randf() < 0.7) or randf() < 0.2 else ["stagger", "blown_back"].pick_random()
		profile = ClownRagdoll.profile_bodyshot(v)
	if zone in [&"UpperLeg", &"LowerLeg", &"Foot"] and not info.get("blast", false):
		var side := "Left" if String(info.collider.bone_name).begins_with("Left") else "Right"
		for part in ["UpperLeg", "LowerLeg", "Foot"]:
			ragdoll.weaken(StringName(side + part), 0.15)
	if has_rifle and not profile.is_empty():
		# The hands come off the rifle: the dying arm muscles let the arms
		# fall half-way from the grip toward hanging at the sides - not a
		# pull all the way there, and not thrown wide (23 Nov: that read as
		# the arms springing up out of an aim or a crouch).
		profile = profile.duplicate()
		profile["fling_scale"] = rifle_arm_fling
		if rifle_arms_wide:
			profile["arms_wide"] = true
		for side: String in ["Left", "Right"]:
			for part: String in ["UpperArm", "LowerArm", "Hand"]:
				var bi := skeleton.find_bone(side + part)
				# and with little strength left in them: they drop, they are
				# not driven there (full arm tone snapped them in a tenth of a second)
				ragdoll.weaken(StringName(side + part), rifle_arm_tone)
				if _base_rot.has(bi):
					var now := skeleton.get_bone_pose_rotation(bi)
					ragdoll.eq_override[StringName(side + part)] = Basis(now.slerp(_base_rot[bi], rifle_arm_settle))
	if ragdoll.active:
		ragdoll.restart(profile)          # already on the floor (shot while down)
	else:
		var fling: Vector3 = info.get("fling", velocity)
		if drop:
			fling += Vector3(info.direction.x, 0, info.direction.z).normalized() * 1.4
		ragdoll.start(profile, info.direction, fling)
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
		zone = zone, blast = info.get("blast", false), stake = info.get("stake", false) or not pins.is_empty() or info.get("pinned", false),
		head_open = _head_open, limbs = limbs, broken_leg = broken_leg != "",
		crawler = crawling or _halved, through = gore._tunnels.size() > 0,
		friendly = info.get("friendly", false), curse = info.get("curse", false),
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
## Caught by a blast at `center` reaching `radius`. `power` scales the damage
## and how badly bones break (1: a fuel drum), `fling` how hard bodies are
## thrown and how often a body is torn in half; `weapon` names it for the records.
func caught_in_blast(center: Vector3, radius: float, power: float = 1.0, fling_k: float = 1.0, weapon: String = "") -> void:
	if executing and _bone_world(&"Chest").distance_to(center) < radius:
		var m := get_node_or_null("Marionette") as Marionette
		if m:
			m.release_now()           # the blast takes him from the strings
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
	if not dead and not crawling and s > 0.5 and s < 0.86 and cover.is_empty() and randf() < halve_chance * fling_k:
		if randf() < crawl_share:
			_tear_in_half(center, dir, s)
		else:
			_halve_dead(center, dir, s)
		return
	var was_dead := dead
	var limbs := _blast_gore(center, dir, s)
	if not dead:
		health -= 320.0 * power * pow(s, 1.3)
		var tears := limbs.filter(func(l: StringName) -> bool: return not String(l).ends_with("Leg"))
		if health <= 0.0 or tears.size() > 0:
			last_hit_zone = &"Chest"
			var fling := dir * lerpf(2.0, 15.0, s * s) * randf_range(0.85, 1.1) * fling_k
			ragdoll.max_bone_speed = 26.0
			var info := {direction = dir, heavy = true, blast = true, collider = ragdoll.bones[&"Chest"], fling = fling}
			if weapon != "":
				info["weapon"] = weapon
			_die(info, &"Chest")
			_throw_bones(dir, s * fling_k)
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
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, dir * lerpf(1.5, 11.0, s * s) * fling_k)
		_throw_bones(dir, s * fling_k)
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
			if randf() < s * 0.9 * power:
				_break_leg(side, _bone_world(StringName(side + "LowerLeg")), dir)
			if randf() < s * 0.8 * power:
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


# --- crossbow bolts ---------------------------------------------------------------
## A bolt that stays in rides on its bone (a BoneAttachment3D, so it follows
## the posed body and, dead, the ragdoll). A bolt through the body into a wall
## behind pins it there: a living clown stays where it stands, held at the pin
## (it cannot walk or turn), and struggles: it thrashes, its free arm grabs at
## the shaft, it can still swing or shoot at what is in front of it. Pinned
## through a limb it tears itself free after a while (more damage, more blood,
## the bolt stays in it); through the body it cannot, and bleeds. Dead, the
## ragdoll hangs from the pin: a joint holds the pinned bone at the bolt (a
## little swing allowed) and gravity does the rest. Nothing is moved to the wall.
@export_group("Crossbow")
## Living clowns can be pinned: they drop what they hold, stop fighting, and
## heave at the bolt with whatever hands they have free until they die there.
@export var can_be_pinned_alive := true
## Off: every pin holds until death. On: a limb pin tears free after
## `pin_free_after` seconds (costing `pin_free_damage`).
@export var pinned_tear_free := false
@export var pin_free_after := Vector2(5.0, 9.0)     ## seconds before a limb pin tears free (if allowed)
@export var pin_free_damage := 16.0
@export var pin_bleed := 2.5                        ## health a second, pinned through the body
@export var pin_bleed_limb := 1.0                   ## health a second, pinned through a limb
@export var bolt_arm_impair := 2.5                  ## seconds a bolted arm cannot aim or swing
@export var bolt_leg_slow := Vector2(0.45, 4.0)     ## speed scale and seconds after a bolt in the leg
## Each pin: {bolt, bone, local (the pinned point in the bone's frame), wall, normal, joint}.
var pins: Array = []
var pinned := false
## How far behind the entry wound the wall ends up once the bolt has driven a
## body back onto it: about the body's depth there (its back against the wall).
const PIN_SEAT := {&"Neck": 0.14, &"Chest": 0.22, &"Spine": 0.22, &"Hips": 0.2, &"UpperArm": 0.1,
	&"LowerArm": 0.07, &"Hand": 0.04, &"UpperLeg": 0.13, &"LowerLeg": 0.09, &"Foot": 0.07}
const PIN_DRIVE_SPEED := 5.0          ## m/s the bolt drives a body back onto the wall
var _pin_drive := 0.0                 ## still to go back (living)
var _pin_bleed_rate := 0.0            ## health a second while pinned alive
var _pin_tug := 0.0                   ## 1 at a heave on the bolt, dying away
var _pin_slip := {}                   ## side -> seconds until that hand slips and grabs again
var _pin_off := {}                    ## side -> seconds that hand is off the shaft
var _pin_hand_grip := {}              ## side -> how firmly that hand is on the bolt (only the grabbing ones)
var _pin_drive_dir := Vector3.ZERO
var _pin_root := Vector3.ZERO
var _pin_t := 0.0
var _pin_free_at := INF
var _pin_jerk_at := 0.0
var _pin_grab := 0.0
var _pin_grab_v := 0.0
var _pin_grab_want := 0.0
var _bolt_atts := {}


func _bolt_attachment(b: StringName) -> BoneAttachment3D:
	if _bolt_atts.has(b) and is_instance_valid(_bolt_atts[b]):
		return _bolt_atts[b]
	var att := BoneAttachment3D.new()
	att.bone_name = b
	skeleton.add_child(att)
	_bolt_atts[b] = att
	return att


## A bolt that stays in this body: it goes where the bone goes.
func bolt_embed(bolt: Node3D, pb: PhysicalBone3D) -> void:
	var b := StringName(pb.bone_name)
	if skeleton == null or skeleton.find_bone(b) < 0:
		return
	var att := _bolt_attachment(b)
	var xf := bolt.global_transform
	bolt.get_parent().remove_child(bolt)
	att.add_child(bolt)
	bolt.global_transform = xf


## A bolt through this body into a wall. Returns false if it cannot pin it
## (then the caller leaves the bolt in the body instead).
func bolt_pin(bolt: Node3D, pb: PhysicalBone3D, at: Vector3, wall: Vector3, normal: Vector3) -> bool:
	var b := StringName(pb.bone_name)
	var bi := skeleton.find_bone(b) if skeleton else -1
	if bi < 0:
		return false
	var living := not dead and not ragdoll.active
	if living and (not can_be_pinned_alive or crawling or downed or last_stand or executing or bleeding_out):
		return false
	if dead and not ragdoll.active:
		return false                      # a staged death still playing: no physics to hold
	# the wall further back than the body is deep: the bolt drives them back onto
	# it (along the ground: a body is shoved, not lifted), unless it is coming
	# down too steeply to shove anyone anywhere
	var to_wall := wall - at
	var flat := Vector3(to_wall.x, 0.0, to_wall.z)
	var drive := maxf(0.0, flat.length() - float(PIN_SEAT.get(Clown._zone(b), 0.15)))
	if drive > 0.12 and flat.length() < to_wall.length() * 0.6:
		return false
	var bone_xf := skeleton.global_transform * skeleton.get_bone_global_pose(bi)
	var pin := {bolt = bolt, bone = b, local = bone_xf.affine_inverse() * at, at = at, wall = wall, normal = normal, joint = RID(), anchor = null,
		dir = to_wall.normalized()}
	pins.append(pin)
	bolt.tree_exiting.connect(_unpin_bolt.bind(bolt), CONNECT_ONE_SHOT)
	if living:
		_begin_living_pin(b)
		if drive > 0.02:
			_pin_drive = maxf(_pin_drive, drive)
			_pin_drive_dir = flat.normalized()
			_place_pin_bolt(pin)
	elif drive > 0.04:
		_drive_corpse(pin, flat.normalized(), drive)
	else:
		_pin_ragdoll(pin)
	return true


## While the body is driven back the bolt goes with it, its point just out of
## the back; once there, the point is in the wall.
func _place_pin_bolt(p: Dictionary) -> void:
	var bolt := p.bolt as Node3D
	if not is_instance_valid(bolt):
		return
	var dir: Vector3 = p.dir
	var seat := float(PIN_SEAT.get(Clown._zone(p.bone), 0.15))
	var left := ((p.wall as Vector3) - (p.at as Vector3)).dot(dir)
	bolt.global_position = (p.at as Vector3) + dir * (minf(left, seat + 0.02) + CrossbowBolt.WALL_BITE)


## Dead (a ragdoll): shoved back along the bolt until the pinned point gets to
## the wall (or stops getting closer), then held there.
func _drive_corpse(p: Dictionary, flat: Vector3, drive: float) -> void:
	var pb: PhysicalBone3D = ragdoll.bones.get(p.bone)
	if pb == null:
		_pin_ragdoll(p)
		return
	p.pending = true
	var on_bone := pb.global_transform.affine_inverse() * (p.at as Vector3)
	var v := clampf(drive * 5.0, 1.5, PIN_DRIVE_SPEED)
	for b: PhysicalBone3D in ragdoll.bones.values():
		if is_instance_valid(b):
			b.linear_velocity += flat * v * (1.0 if b == pb else 0.8)
	var seat := float(PIN_SEAT.get(Clown._zone(p.bone), 0.15))
	var t := 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(pb) or not pins.has(p):
			return
		p.at = pb.global_transform * on_bone
		_place_pin_bolt(p)
		var left := Vector3((p.wall as Vector3).x - (p.at as Vector3).x, 0.0, (p.wall as Vector3).z - (p.at as Vector3).z).dot(flat) - seat
		if left <= 0.03 or (t > 0.1 and pb.linear_velocity.dot(flat) < 0.3):
			break
	p.pending = false
	_place_pin_bolt(p)
	_pin_ragdoll(p)


func _begin_living_pin(b: StringName) -> void:
	var first := not pinned
	pinned = true
	_pin_root = global_position
	velocity = Vector3.ZERO
	walk_amount = 0.0
	run_amount = 0.0
	if first:
		_pin_t = 0.0
		_pin_jerk_at = randf_range(0.25, 0.5)
		_pin_grab = 0.0
		_pin_grab_v = 0.0
		_pin_tug = 0.0
		_pin_slip = {"Left": randf_range(1.2, 2.6), "Right": randf_range(1.8, 3.4)}
		# whatever it was holding goes: both hands are wanted for the bolt
		_drop_weapons()
		attack_amount = 0.0
		aim_amount = 0.0
		aim_point = Vector3.INF
	var zone := Clown._zone(b)
	if zone in [&"UpperArm", &"LowerArm", &"Hand", &"UpperLeg", &"LowerLeg", &"Foot"]:
		if pinned_tear_free and _pin_free_at == INF:
			_pin_free_at = _pin_t + randf_range(pin_free_after.x, pin_free_after.y)
	else:
		_pin_free_at = INF                # through the body: it is not getting off that
	_pin_bleed_rate = maxf(_pin_bleed_rate if not first else 0.0, pin_bleed if zone in [&"Chest", &"Spine", &"Hips", &"Neck"] else pin_bleed_limb)
	var br := get_node_or_null("Brain") as ClownBrain
	if br:
		br.pinned_now()
	set_process(true)


## Held at the pin: the body cannot go anywhere, and it fights it.
func _pinned_pose(delta: float) -> void:
	_pin_t += delta
	# heaves: it throws its weight against the bolt, now this way, now that
	if _pin_t >= _pin_jerk_at:
		_pin_jerk_at = _pin_t + randf_range(0.45, 1.2)
		var n: Vector3 = pins[0].normal if not pins.is_empty() else -global_basis.z
		var inv := skeleton.global_transform.affine_inverse().basis
		var pull := (inv * (n + Vector3(randf_range(-0.6, 0.6), randf_range(-0.2, 0.4), randf_range(-0.6, 0.6)))).normalized()
		_flinch_vel += Vector3(pull.z, randf_range(-0.6, 0.6), -pull.x) * randf_range(2.5, 4.5)
		_pin_tug = 1.0
	_pin_tug = move_toward(_pin_tug, 0.0, delta * 3.0)
	_pin_grab = minf(_pin_grab + delta * 3.5, 1.0)       # the hands go to the bolt at once
	# head down over it, shaking with the effort
	var g := smoothstep(0.0, 1.0, _pin_grab)
	_turn("Neck", Vector3.RIGHT, deg_to_rad(12.0 + 7.0 * _pin_tug + 3.0 * sin(_pin_t * 31.0)) * g)
	_turn("Chest", Vector3.RIGHT, deg_to_rad(8.0 * _pin_tug) * g)


## Both free hands on the bolt where it comes out of the body (one behind the
## other), heaving at it on every jerk; now and then a hand slips off and
## grabs again. A hand is free if its arm is there, not broken and not itself
## pinned. Run after all the other arm posing, so nothing else moves them.
func _pinned_arms(delta: float) -> void:
	if pins.is_empty():
		return
	# the pin to fight: one through the body first, else the first
	var p: Dictionary = pins[0]
	for q: Dictionary in pins:
		if Clown._zone(q.bone) in [&"Chest", &"Spine", &"Hips", &"Neck"]:
			p = q
			break
	if not is_instance_valid(p.bolt as Node3D):
		return
	var free: Array[String] = []
	for side: String in ["Right", "Left"]:
		var pinned_arm := false
		for q: Dictionary in pins:
			pinned_arm = pinned_arm or String(q.bone).begins_with(side)
		if not arm_out(side) and not pinned_arm:
			free.append(side)
	_pin_hand_grip.clear()
	if free.is_empty():
		return
	var to_skel := skeleton.global_transform.affine_inverse()
	var out: Vector3 = -(p.get("dir", -(p.normal as Vector3)) as Vector3)      # back along the bolt, toward the shooter
	var entry: Vector3 = p.at
	var chest := skeleton.get_bone_global_pose(skeleton.find_bone("Chest")).origin
	var g := smoothstep(0.0, 1.0, _pin_grab)
	for k in free.size():
		var side := free[k]
		# slips: off the shaft for a moment, then back on it hard
		_pin_slip[side] = float(_pin_slip.get(side, 2.0)) - delta
		if _pin_slip[side] <= 0.0:
			_pin_slip[side] = randf_range(1.4, 3.2)
			_pin_off[side] = randf_range(0.18, 0.32)
		var off := maxf(float(_pin_off.get(side, 0.0)) - delta, 0.0)
		_pin_off[side] = off
		# one hand near the wound, the other further out along the shaft; the
		# side the hand is on keeps it to that side of the shaft
		var along := (0.07 if free.size() == 1 or k == 0 else 0.15) + 0.035 * _pin_tug
		var shake := Vector3(sin(_pin_t * 27.0 + k * 2.0), sin(_pin_t * 23.0 + k), 0.0) * 0.006
		var grip := to_skel * (entry + out * along) + shake
		# which way is this hand's side (from the shoulder, not assumed): the
		# wrist sits just outboard of the shaft, a little under it, so the hand
		# wraps in over it; the elbow out and down
		var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperArm")).origin
		var outward := Vector3(shoulder.x - chest.x, 0.0, shoulder.z - chest.z)
		outward = outward.normalized() if outward.length() > 0.01 else Vector3.RIGHT
		var out_sk := (to_skel.basis * out).normalized()
		var wrist := grip + outward * 0.07 + Vector3(0, -0.04, 0)
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
		var w := g * (1.0 - smoothstep(0.0, 0.12, off))
		if off > 0.0:
			wrist += out_sk * 0.06 + outward * 0.06 + Vector3(0, -0.05, 0)   # torn off it, coming back
		var pole := shoulder + outward * 0.55 + Vector3(0, -0.3, 0) - out_sk * 0.15     # elbows out: forearms come in level
		reach(side, hand.lerp(wrist, maxf(w, g * 0.6)), pole)
		_pin_hand_grip[side] = w

## The fingers (bodies built with them: see ClownHands): each hand eases to
## the grip of what it is doing, every frame.
var _finger_cur := {}                 ## side -> Vector3(curl, thumb, index)

## Straight to the grip it should have (on spawning, on being given a weapon):
## a clown standing idle does not pose itself every frame.
func _snap_fingers() -> void:
	if skeleton == null or not ClownHands.has_fingers(skeleton):
		return
	for side: String in ["Left", "Right"]:
		var want := _grip_for(side)
		if want.z < 0.0:
			want.z = want.x
		_finger_cur[side] = want
		ClownHands.pose(skeleton, side, want.x, want.y, want.z, maxf(0.0, 0.3 - want.x))


func _pose_fingers(delta: float) -> void:
	if not ClownHands.has_fingers(skeleton):
		return
	for side: String in ["Left", "Right"]:
		var want := _grip_for(side)
		var cur: Vector3 = _finger_cur.get(side, Vector3(0.28, 0.2, 0.28))
		if want.z < 0.0:
			want.z = want.x                      # the index follows the rest
		# closing is quick (a grab), opening slower
		var rate := Vector3(1, 1, 1) * delta * 7.0
		for i in 3:
			cur[i] = move_toward(cur[i], want[i], rate[i] * (1.6 if want[i] > cur[i] else 1.0))
		_finger_cur[side] = cur
		ClownHands.pose(skeleton, side, cur.x, cur.y, cur.z, maxf(0.0, 0.3 - cur.x))


## What one hand's fingers should be doing: Vector3(curl, thumb, index), the
## index -1 to go with the rest. Subclasses add what only they carry.
func _grip_for(side: String) -> Vector3:
	if arm_out(side):
		return Vector3(0.4, 0.3, -1.0)                # limp
	if pinned:
		if _pin_hand_grip.has(side):
			var g: float = _pin_hand_grip[side]
			# clamped on the shaft; harder on a heave; open as it slips off
			return Vector3(lerpf(0.15, 0.86 + 0.08 * _pin_tug, g), lerpf(0.1, 0.8 + 0.1 * _pin_tug, g), -1.0)
		return Vector3(0.5, 0.35, -1.0)              # a pinned arm: half-clenched
	if attack_amount > 0.05 and side == main_arm() and not has_club and not has_rifle:
		return Vector3(0.95, 0.9, -1.0)              # a fist to swing
	if has_rifle and _rifle != null and is_instance_valid(_rifle):
		return Vector3(0.7, 0.6, rifle_index_curl if side == "Right" else -1.0)   # round the wrist and the fore-end; the trigger finger in
	if has_gun and gun_side == side:
		return Vector3(0.78, 0.65, 0.35)             # round the pistol's grip, the index on the trigger
	if has_club and side == "Right":
		return Vector3(0.9, 0.85, -1.0)
	return Vector3(0.28, 0.2, -1.0)                  # at rest: a little curled, as hands hang


## After the pose: the pinned point stays on the bolt. The body is moved (a
## little: the struggle only bends the chain) so the pinned point is where it
## was pinned; a pin through the body bleeds it; a limb pin may tear free.
func _pinned_hold(delta: float) -> void:
	if dead:
		return
	var off := Vector3.ZERO
	if _pin_drive > 0.0:
		# driven back by the bolt: along the ground, stopping short of anything
		# else in the way (a crate, a doorframe)
		var step := minf(_pin_drive, PIN_DRIVE_SPEED * delta)
		var move := _pin_drive_dir * step
		var q := PhysicsRayQueryParameters3D.create(_pin_root + Vector3.UP * 0.5, _pin_root + Vector3.UP * 0.5 + _pin_drive_dir * (step + 0.04), 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			move = Vector3.ZERO
		_pin_root += move
		_pin_drive = 0.0 if move == Vector3.ZERO else _pin_drive - step
		for p: Dictionary in pins:
			p.at = (p.at as Vector3) + move
			_place_pin_bolt(p)
	if not pins.is_empty():
		var p: Dictionary = pins[0]
		var bi := skeleton.find_bone(p.bone)
		if bi >= 0:
			# where the pinned point is with the body standing at its root
			var now := skeleton.global_transform * skeleton.get_bone_global_pose(bi) * (p.local as Vector3) - (global_position - _pin_root)
			off = (p.at as Vector3) - now
			# mostly sideways: the feet stay on the floor (a body is not hoisted up the wall)
			off = Vector3(off.x, clampf(off.y, -0.02, 0.02), off.z).limit_length(0.1)
	global_position = _pin_root + off
	velocity = Vector3.ZERO
	if _pin_free_at == INF:
		health -= _pin_bleed_rate * delta
		if health <= 0.0:
			_die({position = pins[0].at if not pins.is_empty() else global_position + Vector3.UP, direction = Vector3.DOWN,
				collider = ragdoll.bones.get(pins[0].bone if not pins.is_empty() else &"Chest"), weapon = "Crossbow", crossbow = true}, Clown._zone(pins[0].bone if not pins.is_empty() else &"Chest"))
	elif _pin_t >= _pin_free_at:
		_tear_free()


## A limb pin: it rips the limb off the bolt. The bolt stays in it.
func _tear_free() -> void:
	var dir := Vector3.ZERO
	for p: Dictionary in pins.duplicate():
		var bolt: Node3D = p.bolt
		dir = -(p.normal as Vector3)
		if is_instance_valid(bolt) and bolt is CrossbowBolt:
			(bolt as CrossbowBolt).torn_free(self)
		var pb: PhysicalBone3D = ragdoll.bones.get(p.bone)
		Blood.spawn_hit(p.at, p.normal, 1.2, mechanical)
		if pb:
			gore.add_wound(p.bone, p.at, 40.0)
	pins.clear()
	_end_living_pin()
	SfxSynth.play(self, "bolt_flesh", global_position + Vector3.UP * 1.2, 1.0, 0.8)
	health -= pin_free_damage
	if health <= 0.0:
		_die({position = global_position + Vector3.UP * 1.2, direction = dir, collider = ragdoll.bones.get(&"Chest"), weapon = "Crossbow", crossbow = true}, &"Chest")
		return
	_flinch_from(global_position + Vector3.UP * 1.2, -dir, 80.0)


func _end_living_pin() -> void:
	if not pinned:
		return
	pinned = false
	_pin_drive = 0.0
	_pin_free_at = INF
	_pin_bleed_rate = 0.0
	_pin_grab = 0.0
	var br := get_node_or_null("Brain") as ClownBrain
	if br:
		br.unpinned_now()


## The bolt holding a pin has gone (tidied away, torn free): let go of that pin.
func _unpin_bolt(bolt: Node3D) -> void:
	for p: Dictionary in pins.duplicate():
		if p.bolt == bolt:
			for key: String in ["joint", "joint2"]:
				if (p.get(key, RID()) as RID).is_valid():
					PhysicsServer3D.free_rid(p[key])
					p[key] = RID()
			if is_instance_valid(p.anchor):
				(p.anchor as Node).queue_free()
			pins.erase(p)
	if pins.is_empty():
		_end_living_pin()


## Dead (now, or long since): the ragdoll hangs from each pin.
func _pin_corpse() -> void:
	if not ragdoll.active:
		return
	for p: Dictionary in pins:
		if not (p.joint as RID).is_valid():
			_pin_ragdoll(p)


## Hold one ragdoll bone at the bolt: an anchor at the pinned point (fixed in
## the world, as the bolt is) and a 6DOF joint that keeps the point there and
## lets the bone swing a little about it. The joint is made on the physics
## server from the bodies' real transforms (a PhysicalBone3D's body is offset
## from its node, and a Joint3D node would anchor the wrong point and hoist the
## body): the point held is exactly where the bolt went in, so nothing jumps.
func _pin_ragdoll(p: Dictionary) -> void:
	var pb: PhysicalBone3D = ragdoll.bones.get(p.bone)
	if pb == null or not is_instance_valid(pb) or p.get("pending", false):
		return
	# the pinned point, on the bone as it is now; the ragdoll may only just have
	# started (the physics server still has the bodies where they were): wait
	# for it to take over, then hold that point where it has got to
	var on_bone := pb.global_transform.affine_inverse() * (p.at as Vector3)
	p.pending = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	p.pending = false
	if not is_instance_valid(pb) or not pb.is_inside_tree() or not pins.has(p) or not is_instance_valid(p.bolt):
		return
	var at: Vector3 = pb.global_transform * on_bone
	# a static anchor, placed before it enters the tree (a kinematic one moved
	# into place counts as moving fast, and drags the body with it)
	var anchor := StaticBody3D.new()
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.01
	cs.shape = sp
	cs.disabled = true
	anchor.add_child(cs)
	var holder: Node3D = get_parent() as Node3D
	anchor.transform = Transform3D(Basis(), holder.global_transform.affine_inverse() * at if holder else at)
	if holder:
		holder.add_child(anchor)
	else:
		get_parent().add_child(anchor)
	var ps := PhysicsServer3D
	var along := (p.wall as Vector3) - at
	var fwd := along.normalized() if along.length() > 0.01 else Vector3.FORWARD
	# the node's position reaches the physics server only on the next step: put
	# the anchor there now, or the joints are built against the world origin
	ps.body_set_state(anchor.get_rid(), ps.BODY_STATE_TRANSFORM, Transform3D(Basis(), at))
	var xb: Transform3D = ps.body_get_state(pb.get_rid(), ps.BODY_STATE_TRANSFORM)
	# two pins along the bolt's line, 6 cm apart: together an axle, as a shaft
	# through the body is (it can turn about the bolt, not swing off it)
	var joints: Array[RID] = []
	for d: float in [0.0, 0.06]:
		var q := at + fwd * d
		var jr := ps.joint_create()
		ps.joint_make_pin(jr, anchor.get_rid(), q - at, pb.get_rid(), xb.affine_inverse() * q)
		joints.append(jr)
	var j := joints[0]
	p.joint2 = joints[1]
	p.joint = j
	p.anchor = anchor
	var bolt: Node3D = p.bolt
	var release := func() -> void:
		for key: String in ["joint", "joint2"]:
			if (p.get(key, RID()) as RID).is_valid():
				ps.free_rid(p[key])
				p[key] = RID()
		if is_instance_valid(anchor):
			anchor.queue_free()
	pb.tree_exiting.connect(release, CONNECT_ONE_SHOT)
	tree_exiting.connect(release, CONNECT_ONE_SHOT)
	if is_instance_valid(bolt):
		bolt.tree_exiting.connect(release, CONNECT_ONE_SHOT)


## A bolt in an arm: it cannot aim or swing with it for a moment. In a leg:
## it goes slower for a while.
func _bolt_impair(zone: StringName, side: String) -> void:
	var br := get_node_or_null("Brain") as ClownBrain
	if br == null:
		return
	if zone in [&"UpperArm", &"LowerArm", &"Hand"]:
		br.impair_arm(bolt_arm_impair)
		_kick_arms(3.0)
	elif zone in [&"UpperLeg", &"LowerLeg", &"Foot"]:
		br.slow_for(bolt_leg_slow.x, bolt_leg_slow.y)


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

# --- a soldier's body language (set by ClownBrain for the human soldiers) -----
## How fast the body is turning (rad/s, + to the left): standing, the feet
## shuffle round; the shoulders lead the turn a little.
var turn_rate := 0.0
## Leaning out round a corner to shoot: -1 left .. 1 right.
var lean := 0.0
var _lean_now := 0.0
## Where the eyes are going (Vector3.INF: straight ahead) and how much.
var look_point := Vector3.INF
var look_weight_want := 0.0
var _look_w := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _sway_t := randf() * 100.0
var _shuffle := 0.0           # a little step to reset the feet, standing about
var _shuffle_t := randf_range(6.0, 14.0)


## Turn the head (and a little of the shoulders) toward `at`, weight 0..1.
func look_at_point(at: Vector3, weight: float) -> void:
	look_point = at
	look_weight_want = weight if at != Vector3.INF else 0.0


## A near miss: a sharp, small flinch away from the round and a dip.
func flinch_away(away: Vector3, power: float) -> void:
	if flinch_strength <= 0.0 or dead:
		return
	var inv := skeleton.global_transform.affine_inverse()
	var d := (inv.basis * away).normalized()
	var kick := Vector3(0, 1, 0).cross(d) * -1.0 + Vector3(-0.4, 0, 0)
	_flinch_vel += (kick * 9.0 * power).limit_length(6.0)
	_stagger_vel += Vector3(d.x, 0, d.z) * 0.5 * power
	set_process(true)

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
## Motion-captured movement (SoldierClips) under the procedural animation:
## kneeling, crouch walk/run, side-steps, the rifle stance and raise, turns
## on the spot, recoil and a kneeling hit. Off: all procedural, as before.
@export var use_clips := not OS.has_environment("NO_CLIPS")
var _mix := SoldierClips.Mix.new()
var _clip_rest_g := {}
var _clip_idx := {}
var _lod_acc := 0.0
static var pose_lod := not OS.has_environment("NO_LOD")          ## far / unseen enemies posed less often (tests that measure feet turn it off)
var _lod_slot := randi() % 12
var _clip_share := 0.0               # how much of the pose the clips have this frame (0..1)
var _clip_phase := 0.0               # moving cycles, in cycles
var _kneel_t := 0.0
var _recoil_clip_t := 99.0
var _khit_t := 99.0
var clip_weights := {}               # last frame's weights, for tests
var _clip_legs_only := false
var _clip_peek := false              # the corner lean comes from the clip         # this frame the clips have only the legs (no rifle)
var cower := false                   ## curled up under heavy fire (the brain sets it)
var _cower_t := 0.0
var _cower_w := 0.0
var _turn_w := 0.0                   # turning on the spot (the pivot clip's share)
var _turn_clip := ""
var turn_goal := 0.0                 ## how far he still means to turn (the brain sets it), radians
## Starting off and pulling up (motion-captured): while one plays, the clip's
## own pace is the man's (the brain reads transit_speed), so his feet stay
## where they are put. 1 starting, 2 stopping, 0 neither.
var _tr_state := 0
var _tr_clip := ""
var _tr_f := 0.0
var _tr_rate := 1.0
var _tr_w := 0.0
var transit_speed := 0.0
var _dodge_t := 99.0
var _dodge_side := 1.0
var _idle_t := 0.0
var _prev_crouch := 0.0
var _stance_dir := 0.0
var _trans_w := 0.0
var _turn_acc := 0.0                 # how far round this turn has come (radians, signed)
var _prev_yaw := INF
var _flinch := Vector3.ZERO         # upper-body rotation, skeleton space (axis * angle)
var _flinch_vel := Vector3.ZERO
var _stagger := Vector3.ZERO        # model offset, metres
var _stagger_vel := Vector3.ZERO
var stagger_time := 0.0             # seconds the AI should stay knocked off its stride


## The human soldier's small movements on top of the stride and the aim:
## shoulders leading a turn, a lean out round a corner, the slow shift of
## weight standing about, and the head (then the shoulders) turning to look.
## Returns the model's sideways shift for the lean.
func _soldier_body_language(delta: float, gait: float) -> Vector3:
	var still := 1.0 - clampf(gait * 2.5, 0.0, 1.0)
	# the shoulders lead a turn
	var tr := clampf(turn_rate, -3.0, 3.0)
	_turn("Spine", Vector3.UP, tr * 0.05)
	_turn("Chest", Vector3.UP, tr * 0.06)
	# Leaning out to shoot round a corner (lean > 0: the opening is on his
	# right). The upper body tips out over the outside foot and the hips give
	# a little the other way. (Before, the hips went 12 cm toward the opening
	# and the body tipped back the other way: the head barely moved.) A
	# rifleman with the clips takes the lean from the captured look round a
	# corner (in _clip_layer); otherwise it is done here.
	_lean_now = move_toward(_lean_now, lean, delta * 2.2)
	if absf(_lean_now) > 0.01 and not _clip_peek:
		_turn("Spine", Vector3.BACK, deg_to_rad(11.0) * _lean_now)
		_turn("Chest", Vector3.BACK, deg_to_rad(8.0) * _lean_now)
	# standing about: the weight drifts from foot to foot, slowly
	_sway_t += delta
	if still > 0.01 and aim_amount < 0.6:
		var w := sin(_sway_t * 0.9) * 0.7 + sin(_sway_t * 0.37 + 1.3) * 0.3
		_turn("Hips", Vector3.BACK, deg_to_rad(2.2) * w * still)
		_turn("Spine", Vector3.BACK, deg_to_rad(-2.6) * w * still)
		_turn("Chest", Vector3.RIGHT, deg_to_rad(1.2) * sin(_sway_t * 0.53) * still)
	# looking: the head first, the shoulders a share of it; not past what a neck does
	_look_w = move_toward(_look_w, look_weight_want, delta * 1.8)
	if look_point != Vector3.INF and _look_w > 0.01:
		var inv := skeleton.global_transform.affine_inverse()
		var lp := inv * look_point
		var head := Vector3(0, 1.6 - 0.47 * crouch_amount, 0)
		var rel := lp - head
		var yaw := clampf(atan2(rel.x, rel.z), -1.25, 1.25)
		var pitch := clampf(-atan2(rel.y, Vector2(rel.x, rel.z).length()), -0.5, 0.6)
		_look_yaw = move_toward(_look_yaw, yaw, delta * 5.0)
		_look_pitch = move_toward(_look_pitch, pitch, delta * 3.0)
	else:
		_look_yaw = move_toward(_look_yaw, 0.0, delta * 2.5)
		_look_pitch = move_toward(_look_pitch, 0.0, delta * 2.0)
	var lw := _look_w
	if absf(_look_yaw) > 0.005 or absf(_look_pitch) > 0.005:
		var aimed := clampf(aim_amount, 0.0, 1.0)        # aiming, the rifle sets the shoulders: the head only
		_turn("Spine", Vector3.UP, _look_yaw * 0.12 * lw * (1.0 - aimed))
		_turn("Chest", Vector3.UP, _look_yaw * 0.2 * lw * (1.0 - aimed))
		_turn("Neck", Vector3.UP, _look_yaw * 0.6 * lw * (1.0 - 0.7 * aimed))
		_turn("Neck", Vector3.RIGHT, _look_pitch * 0.6 * lw * (1.0 - 0.7 * aimed))
	return Vector3(0.03 * _lean_now, 0, 0)


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
	if spec.get("soldier", false):
		_stagger_vel.y -= 0.3 * power        # the knees give (3 cm or so in the references)
	stagger_time = maxf(stagger_time, 0.18 + 0.12 * power)
	if crouch_amount > 0.6 and use_clips and has_rifle:
		_khit_t = 0.0                        # kneeling: the motion-captured hit plays over it
		_flinch_vel *= 0.5                   # (and the spring takes less of it)
	set_process(true)


func _process(delta: float) -> void:
	_shot_t += delta
	if executing:
		return
	if spec.get("soldier", false) and not dead and body != "klappersoldat":
		_soldier_footsteps(delta)          # (the Klappersoldat's steps are its own clockwork)
	if bleeding_out:
		_throat_process(delta)
		return
	if dead or crawling or last_stand:
		set_process(false)
		return
	if downed:
		_downed_process(delta)
		return
	# Far from the camera the pose is worked out every second or third frame
	# (held between): 25 m and 45 m; out of view, every fourth. Each man on
	# his own beat, so the work is spread over the frames.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and pose_lod:
		var d2 := cam.global_position.distance_squared_to(global_position)
		var every := 1 if d2 < 625.0 else (2 if d2 < 2025.0 else 3)
		if d2 > 36.0 and not cam.is_position_in_frustum(global_position + Vector3.UP):
			every = 4                       # out of sight (and not right beside you)
		_lod_acc += delta
		if every > 1 and (Engine.get_process_frames() + _lod_slot) % every != 0:
			return
		delta = _lod_acc
	_lod_acc = 0.0
	delta = minf(delta, 1.0 / 30.0)         # the springs below go unstable on a long frame
	stagger_time = maxf(stagger_time - delta, 0.0)
	# (soldiers: tuned to the Mixamo hit reactions: snapped back in about a
	# tenth of a second, swung through and back the other way about a third
	# of a second later, settled by about a second)
	var fk := 90.0 if spec.get("soldier", false) else 120.0
	var fc := 6.7 if spec.get("soldier", false) else 13.0
	_flinch_vel += (-_flinch * fk - _flinch_vel * fc) * delta
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
	var human: bool = spec.get("soldier", false) and drive_phase
	if human:
		# no running stride at a walking pace (the body builds up to a run)
		run_amount = minf(run_amount, smoothstep(2.3, 4.3, speed))
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
		if human:
			# measured (test_motion "feet"): at a brisk walk the old stride let the
			# planted foot skate forward at ~40% of the body's speed; ~0.8 of it
			# brings that under 30% (the run was already right)
			stride_len *= lerpf(0.8, 1.0, run_amount)
		if back < 0.0 and spec.get("soldier", false):
			stride_len *= 0.6               # stepping back: short, careful steps
		walk_phase += speed * delta * TAU / stride_len * back
	elif human and absf(turn_rate) > 0.6:
		# turning on the spot: the feet step him round
		walk_phase += delta * (3.0 + absf(turn_rate) * 1.6)
	elif walk_amount > 0.01 and drive_phase:
		walk_phase += delta * 4.0            # marking time
	if speed > 0.05 and not drive_phase:
		var f2 := flat.dot(global_basis.z.normalized()) / speed
		var sd2 := flat.dot(global_basis.x.normalized()) / speed
		fwd_amt = absf(f2)
		side_amt = absf(sd2)
		back = -1.0 if f2 < -0.25 else 1.0
	_model_sway = Vector3.ZERO
	_clip_legs_only = false
	_clip_peek = false
	_clip_layer(delta, flat, speed, side_amt, back)
	var bob := 0.0
	# How much the legs swing: any real movement gets a full step (the step
	# rate already follows the speed), so a slow side-step still lifts its feet.
	var gait := maxf(walk_amount, clampf(speed / 0.9, 0.0, 1.0)) if speed > 0.05 else walk_amount
	if human and speed < 0.3:
		# shuffling round on a turn, or the odd little step standing about
		gait = maxf(gait, clampf((absf(turn_rate) - 0.4) * 0.35, 0.0, 0.45))
		if _shuffle > 0.0:
			_shuffle -= delta
			walk_phase += delta * TAU / 0.9
			gait = maxf(gait, 0.3 * sin(clampf(_shuffle / 0.9, 0.0, 1.0) * PI))
		elif aim_amount < 0.3 and crouch_amount < 0.3:
			_shuffle_t -= delta
			if _shuffle_t <= 0.0:
				_shuffle_t = randf_range(7.0, 16.0)
				_shuffle = 0.9
	var lg := gait * (1.0 - _clip_share)      # the legs the clips leave to the procedural walk
	var ag := gait if _clip_legs_only else lg  # and the arms (a man without a rifle still swings them)
	if gait > 0.01:
		var sw := sin(walk_phase)
		var stride := (stride_override if stride_override > 0.0 else lerpf(27.0, 44.0 if has_rifle else 50.0, run_amount)) * clampf(fwd_amt + 0.3, 0.0, 1.0)
		var knee := lerpf(62.0, 75.0 if has_rifle else 90.0, run_amount)
		var arm := lerpf(22.0, 48.0, run_amount)
		if not human:
			_turn("Spine", Vector3.RIGHT, deg_to_rad(lerpf(4.0, 9.0 if has_rifle else 20.0, run_amount)) * lg * fwd_amt * (back if back > 0.0 else 0.25))
		_turn("Spine", Vector3.BACK, deg_to_rad(3.0) * sw * lg)
		_turn("Spine", Vector3.UP, deg_to_rad(5.0) * sw * lg * fwd_amt)        # hips and shoulders counter-turn
		var legs := {"Left": 1.0, "Right": -1.0}
		if spec.get("soldier", false):
			_soldier_legs(lg, fwd_amt, side_amt, back)
			legs = {}
			if human:
				bob += _soldier_walk_body(delta, lg, fwd_amt, back, flat)
		for side: String in legs:
			var s: float = legs[side]
			var limp := side == broken_leg
			var k := 0.35 if limp else 1.0
			var swing := maxf(0.0, cos(walk_phase) * s)          # this leg is coming through
			var stance := maxf(0.0, -cos(walk_phase) * s)        # this leg is carrying the body
			var behind := maxf(0.0, -sw * s)                      # trailing, about to push off
			# thigh forward and back; out to the side when side-stepping
			_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-stride) * sw * s * lg * k)
			_turn(side + "UpperLeg", Vector3.BACK, deg_to_rad(15.0) * sw * side_amt * lg)
			# knee: folds high as the foot comes through, gives a little under the
			# weight, never quite locks straight
			var knee_deg := knee * pow(swing, 1.4) + 9.0 * stance + 5.0
			_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(knee_deg) * lg * (0.3 if limp else 1.0))
			# ankle: toe pushes off behind, lifts clear coming through, lands heel first
			# (positive turns the toe down)
			_turn(side + "Foot", Vector3.RIGHT, deg_to_rad(20.0 * pow(behind, 2.0) * stance - 12.0 * swing) * lg * k)
		if not has_rifle:
			_turn("LeftUpperArm", Vector3.RIGHT, deg_to_rad(arm) * sw * ag)
			_turn("LeftLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * ag)
		if attack_amount < 0.01 and aim_amount < 0.01 and not has_rifle:
			_turn("RightUpperArm", Vector3.RIGHT, deg_to_rad(-arm) * sw * ag)
			_turn("RightLowerArm", Vector3.RIGHT, deg_to_rad(-55.0) * run_amount * ag)
		# the body drops a little onto each foot as it lands
		bob = (0.5 + 0.5 * cos(walk_phase * 2.0)) * lerpf(0.035, 0.07, run_amount) * lg
	# A broken leg: knee bent the wrong way, and the body lurches down onto it.
	if broken_leg != "":
		var s := 1.0 if broken_leg == "Left" else -1.0
		_broken_knee_pose()
		var on_bad := maxf(0.0, sin(walk_phase) * (-s)) * walk_amount
		bob += on_bad * 0.09
		_turn("Spine", Vector3.BACK, deg_to_rad(-10.0) * s * (0.4 + on_bad))
		_turn("Spine", Vector3.RIGHT, deg_to_rad(12.0))
	# Crouched behind cover.
	if crouch_amount * (1.0 - _clip_share) > 0.01:
		var c := crouch_amount * (1.0 - _clip_share)
		for side: String in ["Left", "Right"]:
			_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-80.0) * c)
			_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(120.0) * c)
		_turn("Spine", Vector3.RIGHT, deg_to_rad(14.0) * c)
	# A soldier taking aim stands bladed: left foot forward, right foot back.
	_stance_w = 0.0
	if spec.get("soldier", false) and has_rifle and aim_amount > 0.01:
		_aim_stance(aim_amount * (1.0 - clampf(gait * 1.6, 0.0, 1.0)) * (1.0 - _clip_share))
	# The fighting arm (the right, or the left if the right is out): swung
	# overhead to hit, or held out to aim (pistol gunmen).
	var arm := main_arm()
	if attack_amount > 0.01 and arm != "":
		_turn(arm + "UpperArm", Vector3.RIGHT, deg_to_rad(-135.0) * attack_amount)
		_turn(arm + "LowerArm", Vector3.RIGHT, deg_to_rad(-35.0) * attack_amount)
		_turn("Chest", Vector3.RIGHT, deg_to_rad(12.0) * attack_amount)
	elif aim_amount > 0.01 and not has_rifle and arm != "":
		_turn(arm + "UpperArm", Vector3.RIGHT, deg_to_rad(-84.0) * aim_amount)
	if pinned:
		_pinned_pose(delta)
		bob = 0.0
		_stagger = Vector3.ZERO
		_stagger_vel = Vector3.ZERO
	if _flinch.length() > 0.0005:
		for b: Array in FLINCH_BONES:
			_turn(b[0], _flinch.normalized(), _flinch.length() * b[1])
	var lean_shift := Vector3.ZERO
	if human:
		lean_shift = _soldier_body_language(delta, gait)
	_model.position = _stagger + lean_shift + _model_sway + Vector3.DOWN * (bob + 0.47 * crouch_amount * (1.0 - _clip_share) + 0.025 * _stance_w) + _mix.off
	if extra_pose.is_valid():
		extra_pose.call()
	if has_rifle and _rifle and is_instance_valid(_rifle):
		_hold_rifle()
	for side: String in broken_arms:
		dangle_arm(side, gait)
	if pinned:
		_pinned_arms(delta)
		_pose_fingers(delta)
		_pinned_hold(delta)
		return
	_pose_fingers(delta)
	if not always_pose and _flinch.length() < 0.002 and _flinch_vel.length() < 0.02 and _stagger.length() < 0.002 and _stagger_vel.length() < 0.02:
		_flinch = Vector3.ZERO
		_stagger = Vector3.ZERO
		_model.position = Vector3.ZERO
		set_process(false)


## The motion-captured layer (see SoldierClips): chooses and weights the
## clips for what the soldier is doing, poses the skeleton with them and
## leaves `_clip_share` for the procedural animation to scale itself by.
## Riflemen only (the clips' arms are not used: the hands stay on the rifle).
func _clip_layer(delta: float, flat: Vector3, speed: float, side_amt: float, back: float) -> void:
	_mix.reset()
	_clip_share = 0.0
	clip_weights.clear()
	if not use_clips or not (spec.get("soldier", false) or spec.get("mocap_legs", false)) or not drive_phase \
			or broken_leg != "" or pinned or attack_amount > 0.01 or not SoldierClips.available():
		return
	# Riflemen take the whole of every clip but the arms. A man without a
	# rifle (the officer with his pistol and sabre, a WitzSoldat with a club,
	# a clown) takes only the legs, hips and lower spine of the square-on
	# walking, running, side-stepping and turning: the rifle pack's upper
	# bodies are holding rifles, bladed behind them.
	var full: bool = has_rifle and spec.get("soldier", false)
	if _clip_rest_g.is_empty():
		# straight after the reset to the base pose: the bones' rest rotations
		for b: String in SoldierClips.BONES:
			var bi := skeleton.find_bone(b)
			if bi >= 0:
				_clip_rest_g[b] = skeleton.get_bone_global_pose(bi).basis.get_rotation_quaternion()
		_clip_idx = SoldierClips.indices(skeleton)
	var moving := smoothstep(0.05, 0.5, speed)
	var low := smoothstep(0.12, 0.55, crouch_amount) if full else 0.0    # crouched enough to move crouched
	var down := smoothstep(0.1, 0.8, crouch_amount) if full else 0.0     # down on one knee, when still
	var lateral := 0.0
	var ahead := 1.0
	if speed > 0.05:
		lateral = flat.dot(global_basis.x.normalized()) / speed
		ahead = flat.dot(global_basis.z.normalized()) / speed
	var heading := rad_to_deg(atan2(lateral, ahead))      # the way he moves: 0 ahead, +90 to his left
	var still := 1.0 - moving
	# A near miss dodged: the clip's jink down and away, over everything
	# else while it lasts.
	_dodge_t += delta
	var dodge_w := 0.0
	var dc: SoldierClips.Clip = SoldierClips.clip("dodge_left" if _dodge_side < 0.0 else "dodge_right")
	if full and dc and _dodge_t < dc.length():
		dodge_w = smoothstep(0.0, 0.08, _dodge_t) * (1.0 - smoothstep(dc.length() - 0.35, dc.length(), _dodge_t))
	var rest_w := 1.0 - dodge_w
	# Starting off or pulling up: the clip, played at its own pace (which the
	# brain follows), over the rest; handing over to the cycles (in step) or
	# to standing at its end.
	var trc: SoldierClips.Clip = SoldierClips.clip(_tr_clip) if _tr_clip != "" else null
	if trc and full and crouch_amount < 0.3 and dodge_w < 0.01:
		_tr_f = minf(_tr_f + delta * 30.0 * _tr_rate, trc.frames - 1.0)
		if _tr_state == 1 and _tr_f >= trc.frames - 9.0:
			_tr_state = 0                       # under way: the walking cycle takes him on
		if _tr_state == 2 and _tr_f >= trc.frames - 1.0:
			_tr_state = 0                       # stopped
		transit_speed = trc.speed_at(_tr_f) * _tr_rate if _tr_state != 0 else 0.0
		_tr_w = move_toward(_tr_w, 1.0 if _tr_state != 0 else 0.0, delta * (8.0 if _tr_state != 0 else (4.0 if _tr_clip.begins_with("start") else 2.5)))
		if _tr_w > 0.0005:
			_clip_phase = trc.phase_at(_tr_f) + (_clip_phase - fposmod(_clip_phase, 1.0)) if _tr_state != 0 else _clip_phase
		else:
			_tr_clip = ""
	else:
		_tr_state = 0
		_tr_w = 0.0
		_tr_clip = ""
		transit_speed = 0.0
	rest_w *= 1.0 - _tr_w
	# Turning on the spot: a pivot clip, played as far as he has turned (its
	# own turn is taken out of it, so the feet stay put while the body turns
	# over them). Chosen as the turn starts: about-turns (more than ~125
	# degrees to go) take the 180, kneeling men the crouched turns.
	var yaw := global_rotation.y
	var dyaw := 0.0 if _prev_yaw == INF else wrapf(yaw - _prev_yaw, -PI, PI)
	_prev_yaw = yaw
	var turning := absf(dyaw) > 0.25 * delta and moving < 0.3
	if turning:
		if _turn_w < 0.05 or signf(dyaw) != signf(_turn_acc) and absf(_turn_acc) > 0.05:
			_turn_acc = 0.0
			var lr := "left" if dyaw > 0.0 else "right"
			if not full:
				_turn_clip = "turn_open_" + lr
			elif low > 0.5:
				_turn_clip = "crouch_turn90_" + lr
			elif absf(turn_goal) > 2.2:
				_turn_clip = "turn180_" + lr
			else:
				_turn_clip = "turn90_" + lr
		_turn_acc += dyaw
		_turn_w = move_toward(_turn_w, 1.0, delta * 5.0)
	else:
		_turn_w = move_toward(_turn_w, 0.0, delta * 4.0)
	var tc: SoldierClips.Clip = SoldierClips.clip(_turn_clip) if _turn_clip != "" else null
	if tc and absf(_turn_acc) > absf(tc.total_turn()):
		_turn_acc -= tc.total_turn()
		if _turn_clip.begins_with("turn180"):
			_turn_clip = _turn_clip.replace("turn180", "turn90")       # carrying on round: the quarter turns
	var turn_w := 0.0
	if tc and _turn_w > 0.001:
		turn_w = _turn_w * still * rest_w
		_mix.add(tc, tc.frame_for_turn(_turn_acc), turn_w)
	var hold := still * rest_w * (1.0 - turn_w)          # what is left for standing or kneeling still
	# Moving: blended from the nearest of the eight ways at a walk, a run and a
	# sprint (crouched: eight ways at a walk, four at a run), all cycles
	# starting on the left foot's plant and sharing one phase that runs at the
	# real speed over each clip's own stride, so they blend step for step and
	# the planted foot stays planted.
	var go := moving * rest_w
	var parts: Array = []                                # [clip, weight]
	if full:
		var up := (1.0 - low) * go
		var cr := low * go
		# a slow, unhurried walk ahead (patrolling) is the relaxed rifle walk;
		# the pack's walk is the low, ready combat walk
		var relaxed := (1.0 - smoothstep(1.2, 1.8, speed)) * smoothstep(0.75, 0.95, ahead)
		var run_mix := smoothstep(2.4, 3.8, speed)
		var sprint_mix := smoothstep(5.0, 6.5, speed) * smoothstep(0.4, 0.75, ahead)
		parts.append([SoldierClips.clip("walk"), up * relaxed])
		_ways(parts, "walk8_", 45, heading, up * (1.0 - relaxed) * (1.0 - run_mix))
		_ways(parts, "run8_", 45, heading, up * (1.0 - relaxed) * run_mix * (1.0 - sprint_mix))
		_ways(parts, "sprint_", 45, clampf(heading, -45.0, 45.0), up * (1.0 - relaxed) * run_mix * sprint_mix)
		var crun := smoothstep(1.9, 2.8, speed)
		_ways(parts, "cwalk8_", 45, heading, cr * (1.0 - crun))
		_ways(parts, "crun4_", 90, heading, cr * crun)
	else:
		# square-on: the relaxed walk and run ahead, the back-walk, the side-step
		var side_w := smoothstep(0.5, 0.85, side_amt)
		var bk := clampf(-ahead * 2.0, 0.0, 1.0) * (1.0 - side_w)
		var fw := (1.0 - side_w) - bk
		var run_mix := smoothstep(1.5, 4.0, speed)
		parts.append([SoldierClips.clip("walk"), go * fw * (1.0 - run_mix)])
		parts.append([SoldierClips.clip("run"), go * fw * run_mix])
		parts.append([SoldierClips.clip("walk_back"), go * bk])
		parts.append([SoldierClips.clip("strafe_left"), go * side_w * (1.0 if lateral >= 0.0 else -1.0)])
	var rate := 0.0
	var wsum := 0.0
	for p: Array in parts:
		var c: SoldierClips.Clip = p[0]
		var w: float = p[1]
		if c == null or absf(w) < 0.0005:
			continue
		rate += w / maxf(c.stride, 0.3)                  # (a negative weight plays it backwards)
		wsum += absf(w)
	if wsum > 0.001:
		_clip_phase += speed * delta * rate / wsum
		# the procedural stride (arm swing, the rifle's sway, footstep sounds)
		# kept in step with the clips' feet: its left heel strike is at 1.5 pi
		walk_phase = lerp_angle(walk_phase, _clip_phase * TAU + PI * 1.5, clampf(wsum, 0.0, 1.0))
	var named := {}
	for p: Array in parts:
		var c: SoldierClips.Clip = p[0]
		var w := absf(float(p[1]))
		if c == null or w < 0.0005:
			continue
		_mix.add(c, _clip_phase * c.frames, w)
		var key := c.name
		if c.name.get_slice("_", c.name.get_slice_count("_") - 1).is_valid_int():
			key = c.name.substr(0, c.name.rfind("_"))
		named[key] = float(named.get(key, 0.0)) + w
	# Still: standing (breathing, shifting, raising the rifle as he takes aim)
	# or kneeling (the same, down on one knee), and between the two the clips
	# of getting down and getting up, played as far as he has gone.
	var aim := smoothstep(0.0, 1.0, aim_amount)
	var kneel_w := 0.0
	var stand_w := 0.0
	var trans_w := 0.0
	if full:
		_idle_t += delta
		var dc_rate := crouch_amount - _prev_crouch
		_prev_crouch = crouch_amount
		if absf(dc_rate) > 0.0005:
			_stance_dir = signf(dc_rate)
		# (only while he is actually getting down or up: held part way, he is
		# just crouched, the kneel and the stance blended)
		_trans_w = move_toward(_trans_w, 1.0 if absf(dc_rate) > 0.0005 else 0.0, delta * (8.0 if absf(dc_rate) > 0.0005 else 3.0))
		var mid := clampf(4.0 * crouch_amount * (1.0 - crouch_amount), 0.0, 1.0)
		trans_w = hold * mid * _trans_w
		if _stance_dir > 0.0:
			var sk2: SoldierClips.Clip = SoldierClips.clip("stand_to_kneel")
			_mix.add(sk2, crouch_amount * (sk2.frames - 1), trans_w)
		elif _stance_dir < 0.0:
			var ks: SoldierClips.Clip = SoldierClips.clip("kneel_to_stand")
			_mix.add(ks, (1.0 - crouch_amount) * (ks.frames - 1), trans_w)
		var settled := hold * (1.0 - trans_w)
		kneel_w = settled * down
		stand_w = settled * (1.0 - down)
		_cower_t += delta
		var cw_clip: SoldierClips.Clip = SoldierClips.clip("cower")
		if cower and moving < 0.5:
			if _cower_w < 0.01:
				_cower_t = 0.0
			_cower_w = move_toward(_cower_w, 1.0, delta * 4.0)
		else:
			_cower_w = move_toward(_cower_w, 0.0, delta * 2.5)
		if _cower_w > 0.001:
			var cf := _cower_t * 30.0
			if cf > cw_clip.frames - 1:
				cf = cw_clip.frames - 60.0 + fposmod(cf - (cw_clip.frames - 60.0), 59.0)
			var cww := _cower_w * still
			_mix.add(cw_clip, cf, cww * rest_w)
			stand_w *= 1.0 - cww
			kneel_w *= 1.0 - cww
		_mix.add(SoldierClips.clip("kneel"), _idle_t * 30.0, kneel_w * (1.0 - aim))
		_mix.add(SoldierClips.clip("kneel_aim"), _idle_t * 30.0, kneel_w * aim)
		_mix.add(SoldierClips.clip("idle"), _idle_t * 30.0, stand_w * (1.0 - aim))
		_mix.add(SoldierClips.clip("idle_aim"), _idle_t * 30.0, stand_w * aim)
		if dodge_w > 0.0:
			_mix.add(dc, _dodge_t * 30.0, dodge_w)
		if _tr_w > 0.0005 and trc:
			_mix.add(trc, _tr_f, _tr_w * (1.0 - dodge_w))
	_mix.apply(skeleton, _clip_rest_g, _clip_idx, SoldierClips.BONES if full else SoldierClips.LOWER)
	_clip_share = minf(_mix.total, 1.0)
	_clip_legs_only = not full
	# the look round a corner: the captured lean, as far as he leans
	_clip_peek = full
	if full and absf(_lean_now) > 0.01:
		var pk: SoldierClips.Clip = SoldierClips.clip("peek_right" if _lean_now > 0.0 else "peek_left")
		SoldierClips.add_on(skeleton, pk, absf(_lean_now) * (pk.frames - 1), 1.0)
	# the shot, absorbed through the body; a hit taken kneeling
	_recoil_clip_t += delta
	var rc: SoldierClips.Clip = SoldierClips.clip("recoil")
	if _recoil_clip_t < rc.length() and full:
		SoldierClips.add_on(skeleton, rc, _recoil_clip_t * 30.0, aim_amount)
	_khit_t += delta
	var kh: SoldierClips.Clip = SoldierClips.clip("kneel_hit")
	if _khit_t < kh.length():
		var fade := 1.0 - smoothstep(kh.length() - 0.3, kh.length(), _khit_t)
		SoldierClips.add_on(skeleton, kh, _khit_t * 30.0, kneel_w * fade)
	clip_weights = named
	if _tr_w > 0.0005 and _tr_clip != "":
		clip_weights[_tr_clip.get_slice("_", 0)] = _tr_w
	clip_weights.merge({"kneel": kneel_w, "stand": stand_w, "stance_change": trans_w, "turn": turn_w,
			"cower": _cower_w * still, "dodge": dodge_w, "share": _clip_share})


## Adds the clips of one set (`prefix` + angle, every `step` degrees) for
## the way he is moving: the two either side of it, by how near each is.
func _ways(parts: Array, prefix: String, step: int, heading: float, w: float) -> void:
	if w < 0.0005:
		return
	var a0 := floorf(heading / step) * step
	var t := (heading - a0) / step
	for k in 2:
		var a := int(a0) + k * step
		if a <= -180:
			a += 360
		var c: SoldierClips.Clip = SoldierClips.clip(prefix + str(a))
		if c == null and a == 180:
			c = SoldierClips.clip(prefix + "180")
		if c == null:
			# (the sprint has no back or sideways clips: the nearest it has)
			c = SoldierClips.clip(prefix + str(clampi(a, -45, 45)))
		parts.append([c, w * (t if k == 1 else 1.0 - t)])


## Whether a motion-captured start or stop can be used now.
func _transit_ok() -> bool:
	return use_clips and has_rifle and spec.get("soldier", false) and drive_phase and broken_leg == "" \
			and not pinned and attack_amount < 0.01 and crouch_amount < 0.2 and aim_amount < 0.5 \
			and _dodge_t > 1.6 and SoldierClips.available()


func transit_state() -> int:
	return _tr_state


## Starting off from standing, toward `goal_speed`: a walk start (played a
## little quicker than the capture) or a run start.
func begin_start(goal_speed: float) -> bool:
	if _tr_state != 0 or not _transit_ok():
		return false
	_tr_clip = "start_run" if goal_speed > 2.2 else "start_walk"
	_tr_rate = 1.0 if goal_speed > 2.2 else 1.5
	_tr_f = 0.0
	_tr_state = 1
	transit_speed = 0.0
	set_process(true)
	return true


func _stop_clip(speed: float) -> String:
	return "stop_run" if speed > 2.0 else "stop_walk"


## How far a stop met now, at `speed`, carries him (-1: none to be had).
func stop_distance(speed: float) -> float:
	if _tr_state != 0 or not _transit_ok():
		return -1.0
	var c: SoldierClips.Clip = SoldierClips.clip(_stop_clip(speed))
	var e := c.stop_entry(speed, fposmod(_clip_phase, 1.0), 1.0)
	return c.dist[c.frames - 1] - c.dist[e] if e >= 0 else -1.0


## Pulling up from `speed`.
func begin_stop(speed: float) -> bool:
	if _tr_state != 0 or not _transit_ok():
		return false
	var c: SoldierClips.Clip = SoldierClips.clip(_stop_clip(speed))
	var e := c.stop_entry(speed, fposmod(_clip_phase, 1.0), 1.0)
	if e < 0:
		return false
	_tr_clip = _stop_clip(speed)
	_tr_rate = 1.0
	_tr_f = e
	_tr_state = 2
	transit_speed = c.speed_at(e)
	set_process(true)
	return true


## Called off (he turns away, means to move on after all, drops down).
func end_transit() -> void:
	_tr_state = 0
	transit_speed = 0.0


## A near miss jinked away from (the brain asks): `side` -1 to his left, +1
## to his right. False if he cannot (no clips, not a rifleman, already at it).
func dodge(side: float) -> bool:
	if not use_clips or not has_rifle or not spec.get("soldier", false) or not SoldierClips.available():
		return false
	if _dodge_t < 1.2:
		return false
	_dodge_t = 0.0
	_dodge_side = side
	set_process(true)
	return true


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


func dangle_arm(side: String, swing: float = 0.0, limp := false) -> void:
	var s := 1.0 if side == "Left" else -1.0
	for part in ["UpperArm", "LowerArm", "Hand"]:
		var bi := skeleton.find_bone(side + part)
		if _base_rot.has(bi):
			skeleton.set_bone_pose_rotation(bi, _base_rot[bi])
	var dt := clampf(get_process_delta_time(), 0.001, 1.0 / 30.0)
	# what the body did this frame (worked out once, whichever arm asks first)
	if _swing_frame != Engine.get_process_frames():
		_swing_frame = Engine.get_process_frames()
		# (capped: a body that stops dead in one frame, as a crawler does
		# when it starts to sit up, should not fling the arm about)
		var acc := ((velocity - _swing_prev_vel) / dt).limit_length(6.0)
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
	if limp:
		# a dead man's arm, not a broken one: the elbow a little bent the
		# right way, the forearm swinging from it, the hand hanging
		_turn(side + "LowerArm", Vector3.RIGHT, -0.3 + clampf(st[4] * 0.6, -0.25, 0.2))
		_turn(side + "Hand", Vector3.RIGHT, deg_to_rad(18.0) + st[4] * 0.3)
		return
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
		if has_rifle and drive_phase:
			# measured (test_motion "feet"): with the soft knees and the turning
			# pelvis the old swing let the planted foot drift forward at ~40% of
			# the body's speed; a longer swing at the hip brings it to ~15%
			hip *= lerpf(1.3, 1.5, r)
		var knee := lerpf(_gait_curve(WALK_KNEE, c), _gait_curve(RUN_KNEE, c), r)
		var ankle := lerpf(_gait_curve(WALK_ANKLE, c), _gait_curve(RUN_ANKLE, c), r)
		var s := 1.0 if side == "Left" else -1.0
		if has_rifle and drive_phase:
			# under a rifle and kit the knee never straightens (the reference
			# clips' knees stay at 20-35 degrees through the stance): bend it,
			# with the hip and ankle taking up the difference so the foot stays flat
			var bend := lerpf(14.0, 8.0, r)
			knee += bend
			hip += bend * 0.5
			ankle -= bend * 0.5
		_turn(side + "UpperLeg", Vector3.RIGHT, deg_to_rad(-hip) * gait * k)
		_turn(side + "UpperLeg", Vector3.BACK, deg_to_rad(15.0) * sw * side_amt * gait)
		_turn(side + "LowerLeg", Vector3.RIGHT, deg_to_rad(knee + 4.0) * gait * (0.3 if limp else 1.0))
		_turn(side + "Foot", Vector3.RIGHT, deg_to_rad(ankle) * gait * k)


## What the reference clips' walking all share and the plain stride lacked
## (measured from the Mixamo crouch walk, crouched run and strafe): the
## pelvis turns with the leg that swings through (about 7 degrees each way)
## and dips on the side that is lifted, the hips ride over the foot that
## carries them (a centimetre or two of sway), the chest turns back against
## the pelvis while the head keeps level, the body leans into the pace and
## into a change of pace, and the rifle side drags the shoulders over a
## little. Returns how much lower the hips ride (knees soft under a load).
var _walk_prev := Vector3.ZERO
var _walk_accel := 0.0


func _soldier_walk_body(delta: float, g: float, fwd_amt: float, back: float, flat: Vector3) -> float:
	var ph := walk_phase
	var sw := sin(ph)
	var r := run_amount
	var forward := fwd_amt * (1.0 if back > 0.0 else 0.4)
	# pelvis: turns toward the leg swinging through, dips on the swinging side
	_turn("Hips", Vector3.UP, -deg_to_rad(lerpf(7.0, 5.0, r)) * sw * g * forward)
	_turn("Hips", Vector3.BACK, deg_to_rad(lerpf(3.0, 4.0, r)) * cos(ph) * g)
	# chest back the other way (more than the old spine counter-turn alone)
	_turn("Chest", Vector3.UP, deg_to_rad(lerpf(2.0, 3.0, r)) * sw * g * forward)   # with the spine's 5: the chest holds steady over the turning pelvis
	# leaning into the pace and into speeding up (back when braking)
	var fwd_v := flat.dot(global_basis.z.normalized())
	var acc := (fwd_v - _walk_prev.z) / maxf(delta, 0.001)
	_walk_prev.z = fwd_v
	_walk_accel = lerpf(_walk_accel, clampf(acc, -6.0, 6.0), clampf(delta * 6.0, 0.0, 1.0))
	var lean := deg_to_rad(lerpf(6.0, 12.0, r)) * forward + deg_to_rad(1.4) * _walk_accel
	_turn("Spine", Vector3.RIGHT, lean * g)
	# the rifle's weight on the right: shoulders over to that side a little
	_turn("Chest", Vector3.BACK, deg_to_rad(3.5) * g)
	# the head stays level over all of it
	_turn("Neck", Vector3.RIGHT, -lean * 0.7 * g)

	# hips over the foot that carries them
	_model_sway = Vector3(lerpf(0.012, 0.02, r) * cos(ph), 0, 0) * g
	return lerpf(0.012, 0.02, r) * g                 # knees soft: hips ride lower


var _model_sway := Vector3.ZERO


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
	_snap_fingers.call_deferred()


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


## (M10) A soldier's boots: a footstep sound every stride by what he walks
## on (the maze's surface_at: mud, water, duckboards, earth), only within
## earshot of the player, so a patrol is heard coming round a corner before
## it is seen. Counted in `steps_played` for the tests.
const STEP_EARSHOT := 38.0
var steps_played := 0
var _step_acc := 0.0
var _step_last := Vector3.INF
var _step_player: Node3D


func _soldier_footsteps(delta: float) -> void:
	var at := global_position
	if _step_last == Vector3.INF:
		_step_last = at
		return
	var moved := Vector2(at.x - _step_last.x, at.z - _step_last.z).length()
	_step_last = at
	if moved > 1.0 or moved < 0.0005:
		return
	_step_acc += moved
	var stride := 0.7 if moved / maxf(delta, 0.001) < 3.2 else 0.95
	if _step_acc < stride:
		return
	_step_acc = 0.0
	if _step_player == null or not is_instance_valid(_step_player):
		_step_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _step_player == null or _step_player.global_position.distance_to(at) > STEP_EARSHOT:
		return
	var surf := "earth"
	var b: Node = get_node_or_null("Brain")
	if b != null and b.get("maze") != null and b.get("maze").has_method("surface_at"):
		surf = b.get("maze").surface_at(at)
	if not surf in ["mud", "water", "wood", "earth"]:
		surf = "earth"
	steps_played += 1
	SfxSynth.play(self, "fs_" + surf, at + Vector3.UP * 0.05, -17.0 if surf != "water" else -15.0, randf_range(0.85, 1.05), 4.0, 40.0)


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
	var kc := 0.45 if hip_fire else 1.0      # from the hip it shakes the body less
	_turn("Chest", Vector3.RIGHT, deg_to_rad(-7.0) * kick * a * kc)
	_turn("Spine", Vector3.RIGHT, deg_to_rad(-3.0) * kick * a * kc)
	_turn("Neck", Vector3.RIGHT, deg_to_rad(-9.0) * kick * a * kc - deg_to_rad(9.0) * low * a)
	# head down onto the stock when aiming (not from the hip: he looks over it)
	if not hip_fire:
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
	if hip_fire:
		# butt against the right hip, under the arm; pointed from there
		var butt := hips + Vector3(-0.16, 0.14, -0.08)
		var hdir := Vector3(0.0, 0.02, 1.0).normalized()
		if aim_point != Vector3.INF:
			hdir = (to_skel * aim_point - (butt + Vector3(0, 0, 0.5))).normalized()
			var hflat := Vector3(hdir.x, 0, hdir.z)
			if hflat.length() < 0.2 or hflat.normalized().dot(Vector3.BACK) < 0.5:
				hdir = Vector3(0.0, 0.02, 1.0).normalized()
			hdir.y = clampf(hdir.y, -0.4, 0.4)
			hdir = hdir.normalized()
		aim_xf = Transform3D(_basis_along(hdir), butt)
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
		xf = Transform3D(xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-11.0 * (0.5 if hip_fire else 1.0)) * kick), xf.origin - xf.basis.z * 0.075 * kick + Vector3.UP * 0.01 * kick)
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
	# Right hand round the wrist of the stock: palm on its right side (-x),
	# thumb over the comb, the hand pointing along the barrel and a little
	# down so the index reaches the trigger. Left hand under the fore-end,
	# palm up, fingers over its right side, thumb along the left. The IK
	# puts the wrist bone where the palm's contact point says it must be,
	# then the hand's whole basis is set (not just its direction).
	var wrist_half: float = float(RIFLE_INFO.get("wrist_half", 0.03))
	var r_y: Vector3 = (xf.basis.z - xf.basis.y * rifle_hand_down).normalized()         # along the hand
	var r_x: Vector3 = xf.basis.x                                           # the palm's normal: into the stock
	var r_palm: Vector3 = xf * (hold_grip + Vector3(-(wrist_half + RIFLE_GLOVE), rifle_grip_lift, 0.0))
	var grip := r_palm - r_y * RIFLE_PALM_ALONG
	var fore_z := lerpf(hold_fore.x, hold_fore.y, a)
	var l_y: Vector3 = (-xf.basis.x + xf.basis.z * 0.35).normalized()
	var l_x: Vector3 = -xf.basis.y                                          # the left palm faces up, into the wood
	var l_palm: Vector3 = xf * Vector3(0.0, _rf_fore(fore_z) - RIFLE_GLOVE, fore_z)
	var fore := l_palm - l_y * RIFLE_PALM_ALONG
	var r_basis := _hand_basis(r_x, r_y)
	var l_basis := _hand_basis(l_x, l_y)
	# the right hand leaves the wrist for the bolt: handle up, back, forward, down
	if cyc >= 0.0 and _bolt:
		var on_bolt := smoothstep(0.04, 0.18, cyc) * (1.0 - smoothstep(0.76, 0.9, cyc))
		var lift := smoothstep(0.18, 0.28, cyc) - smoothstep(0.66, 0.76, cyc)
		var pull := smoothstep(0.3, 0.44, cyc) - smoothstep(0.52, 0.64, cyc)
		_bolt.position = _bolt_home + Vector3(0.0, 0.0, -RIFLE_BOLT_TRAVEL * pull)
		_bolt.rotation.z = -RIFLE_BOLT_LIFT * lift
		# the hand over the knob: palm down and in, thumb forward
		var knob: Vector3 = xf * _rf_knob()
		var b_x: Vector3 = (xf.basis.x * 0.5 - xf.basis.y).normalized()
		var b_y: Vector3 = xf.basis.z
		var b_wrist: Vector3 = knob - b_x * RIFLE_GLOVE - b_y * RIFLE_PALM_ALONG * 0.8 + xf.basis.y * 0.01
		grip = grip.lerp(b_wrist, on_bolt)
		r_basis = Basis(Quaternion(r_basis).slerp(Quaternion(_hand_basis(b_x, b_y)), on_bolt))
		if pull > 0.9 and not _cased:
			_cased = true
			_eject_case(xf)
		if cyc > 0.95:
			_bolt.position = _bolt_home
			_bolt.rotation.z = 0.0
	var rs := sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var ls := sk.get_bone_global_pose(sk.find_bone("LeftUpperArm")).origin
	# elbows: down and a little out when carrying; when the rifle is shouldered
	# the right one goes out to the side but stays well below the shoulder
	var ab := a * a * (3.0 - 2.0 * a)
	if hip_fire:
		# elbows loose: the right back and out, the left down under the gun
		reach("Right", grip, rs + Vector3(-0.38, -0.5, -0.4))
		reach("Left", fore, ls + Vector3(0.35, -0.6, -0.1))
	else:
		reach("Right", grip, rs + Vector3(-0.4, -0.55, -0.15).lerp(Vector3(-0.42, -0.5, -0.12), ab))
		reach("Left", fore, ls + Vector3(0.3, -0.6, 0.05).lerp(Vector3(0.15, -0.65, 0.0), ab))
	_set_hand("RightHand", r_basis)
	_set_hand("LeftHand", l_basis)


## How a hand sits on the rifle: the glove's thickness between the palm's
## centre and the wood, and how far the palm's centre is along the hand from
## the wrist bone. The bolt: how far the handle draws back, how far it lifts.
const RIFLE_GLOVE := 0.014
const RIFLE_PALM_ALONG := 0.075
static var rifle_hand_down := 0.65          # the right hand's slope down the wrist (per unit forward)
static var rifle_index_curl := 0.4          # the trigger finger's curl
static var rifle_grip_lift := 0.0           # the right palm's centre above the wrist's mid-height
const RIFLE_BOLT_TRAVEL := 0.085
const RIFLE_BOLT_LIFT := 1.1


## A hand's basis from its palm normal (its +X: the palm faces it on the
## right hand, away from it on the left) and the direction along the hand
## (its +Y); Z follows, right-handed.
static func _hand_basis(x: Vector3, y: Vector3) -> Basis:
	var yy := y.normalized()
	var xx := (x - yy * x.dot(yy)).normalized()
	return Basis(xx, yy, xx.cross(yy))


## Set a hand bone's whole global basis (skeleton space).
func _set_hand(bone_name: String, basis: Basis) -> void:
	var bi := skeleton.find_bone(bone_name)
	var gp := skeleton.get_bone_global_pose(bi)
	_rotate_global(bi, Quaternion(basis.orthonormalized()) * Quaternion(gp.basis.orthonormalized()).inverse())


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
	if spec.get("share_material", false):
		# the helmet's shell is mapped onto the body's own textures
		for i in _helmet.mesh.get_surface_count():
			var m := _helmet.mesh.surface_get_material(i)
			if m and m.resource_name == "Material":
				_helmet.set_surface_override_material(i, body_material())
	if spec.has("helmet_roughness"):
		# painted steel, not polished: a matte copy of its material
		var hm := _helmet.mesh.surface_get_material(0) as BaseMaterial3D
		if hm:
			hm = hm.duplicate()
			hm.roughness = spec.helmet_roughness
			_helmet.set_surface_override_material(0, hm)
	src.free()
	_grime_helmet()
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


## How worn this one is: his own roll, so no two in a trench look alike.
## {helmet_dust, helmet_mud, mud, dust, fade, seed}; empty for a body that
## gets none (spec.muddy off: clowns, the Klappersoldat). Kept clean, dusty,
## splashed or caked over; an officer (spec.grime_cap) is never worse than
## dusty. Set before the helmet and the body's materials are made.
var grime := {}
## Force how worn he is (0 clean, 1 dusty, 2 splashed, 3 caked); -1 rolls it.
@export var grime_kind := -1
const GRIME_HELMET := preload("res://shaders/helmet_grime.gdshader")


func _roll_grime() -> void:
	grime = {}
	if not spec.get("muddy", false) or mechanical:
		return
	# its own dice: the game's rolls (levels, spawns) come out as they always did
	var g := RandomNumberGenerator.new()
	g.randomize()
	var cap: int = spec.get("grime_cap", 3)
	var r := g.randf()
	# clean 18%, dusty 32%, splashed 32%, caked 18%
	var kind := 0 if r < 0.18 else (1 if r < 0.5 else (2 if r < 0.82 else 3))
	if grime_kind >= 0:
		kind = grime_kind
	kind = mini(kind, cap)
	match kind:
		0:
			grime = {helmet_dust = g.randf_range(0.0, 0.15), helmet_mud = 0.0, mud = g.randf_range(0.15, 0.4), dust = g.randf_range(0.0, 0.2)}
		1:
			grime = {helmet_dust = g.randf_range(0.4, 0.85), helmet_mud = g.randf_range(0.0, 0.12), mud = g.randf_range(0.3, 0.7), dust = g.randf_range(0.35, 0.75)}
		2:
			grime = {helmet_dust = g.randf_range(0.2, 0.55), helmet_mud = g.randf_range(0.3, 0.62), mud = g.randf_range(0.55, 0.9), dust = g.randf_range(0.2, 0.5)}
		_:
			grime = {helmet_dust = g.randf_range(0.1, 0.4), helmet_mud = g.randf_range(0.88, 1.0), mud = g.randf_range(0.8, 1.0), dust = g.randf_range(0.1, 0.35)}
	grime.kind = kind
	grime.seed = g.randf_range(0.0, 100.0)
	# the cloth itself: faded by sun and washing, or still dark and new
	var f := g.randf_range(0.86, 1.1)
	grime.fade = Color(f * g.randf_range(0.97, 1.03), f, f * g.randf_range(0.94, 1.02))


## The helmet's surfaces as they are, with his dust and mud over them.
func _grime_helmet() -> void:
	if grime.is_empty() or _helmet == null:
		return
	var aabb := _helmet.mesh.get_aabb()
	for i in _helmet.mesh.get_surface_count():
		var src := _helmet.get_surface_override_material(i) as BaseMaterial3D
		if src == null:
			src = _helmet.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var sm := ShaderMaterial.new()
		sm.shader = GRIME_HELMET
		sm.set_shader_parameter("albedo_color", src.albedo_color)
		sm.set_shader_parameter("roughness", src.roughness)
		sm.set_shader_parameter("metallic", src.metallic)
		if src.albedo_texture:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("use_tex", true)
		if spec.get("pbr", false) and src.roughness_texture and not spec.has("helmet_roughness"):
			sm.set_shader_parameter("mr_tex", src.roughness_texture)
			sm.set_shader_parameter("use_mr", true)
		if src.normal_enabled and src.normal_texture:
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("use_normal", true)
		sm.set_shader_parameter("dust", grime.helmet_dust)
		sm.set_shader_parameter("mud", grime.helmet_mud)
		sm.set_shader_parameter("seed", grime.seed)
		sm.set_shader_parameter("half_height", maxf(aabb.size.y * 0.5, 0.05))
		sm.set_shader_parameter("mid_y", aabb.get_center().y)
		_helmet.set_surface_override_material(i, sm)


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
## Fires from the hip instead of the shoulder (a heavy machine gun): the butt
## tucked against the right hip under the arm, elbows loose, head up.
var hip_fire := false
## Where the hands go on the gun, in the gun's frame (butt at the origin,
## barrel along +Z): the right on the wrist or pistol grip, the left under
## the fore-end at hold_fore.x carried and hold_fore.y aimed.
var hold_grip := Vector3(0.0, -0.045, 0.2)
var hold_fore := Vector2(0.33, 0.4)
var hold_fore_y := -0.035


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
	_recoil_clip_t = 0.0
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
	# The rifle (23 Nov 2026): the Tripo bolt-action, built by
	# tools/build_enemy_rifle.py with the butt plate at the origin, the
	# barrel along +Z and the bore at y 0.025 - the frame the old box rifle
	# was laid out in. "Bolt" is the handle on its own, its origin on the
	# bore axis at the root, so a turn about its Z lifts it. enemy_rifle.json
	# carries the measured points the hands go to.
	if RIFLE_INFO.is_empty():
		var f := FileAccess.open(RIFLE_JSON, FileAccess.READ)
		if f:
			RIFLE_INFO = JSON.parse_string(f.get_as_text())
	var model: Node3D = (load(RIFLE_SCENE) as PackedScene).instantiate()
	_rifle.add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_bolt = model.find_child("Bolt", true, false) as Node3D
	if _bolt:
		_bolt_home = _bolt.position
	_muzzle = Node3D.new()
	_muzzle.position = _rf("muzzle", Vector3(0, 0.025, 1.1))
	_rifle.add_child(_muzzle)
	# where the hands go: the wrist of the stock (right), the fore-end (left)
	var wrist := _rf("wrist", Vector3(0, -0.023, 0.24))
	hold_grip = wrist + Vector3(0, 0, -0.012)        # a touch back: the index pad lands on the blade
	hold_fore = Vector2(0.55, 0.62)
	hold_fore_y = _rf_fore(hold_fore.x)
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
	_snap_fingers.call_deferred()


const RIFLE_SCENE := "res://art/weapons/enemy_rifle/enemy_rifle.glb"
const RIFLE_JSON := "res://art/weapons/enemy_rifle/enemy_rifle.json"
static var RIFLE_INFO: Dictionary = {}
var _bolt_home := Vector3(0, 0.025, 0.351)


func _rf_arr(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A point from the rifle's json (Godot axes: x, up, along the barrel).
func _rf(key: String, fallback: Vector3) -> Vector3:
	if RIFLE_INFO.has(key):
		var a: Array = RIFLE_INFO[key]
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## The fore-end's underside (y) at `z` along the barrel, from the json's samples.
func _rf_fore(z: float) -> float:
	if not RIFLE_INFO.has("fore"):
		return -0.035
	var best := INF
	var y := -0.035
	for k: String in RIFLE_INFO.fore.keys():
		var p: Array = RIFLE_INFO.fore[k]
		if absf(float(p[2]) - z) < best:
			best = absf(float(p[2]) - z)
			y = float(p[1])
	return y


## The bolt handle's knob, in the rifle's frame, where the handle is now.
func _rf_knob() -> Vector3:
	if _bolt == null:
		return Vector3(-0.065, 0.04, 0.29)
	return _bolt.transform * _rf("bolt_knob", Vector3(-0.095, 0.025, 0.009))


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
	cs.position = Vector3(0, 0, 0.55)
	if RIFLE_INFO.has("box"):
		box.size = _rf_arr(RIFLE_INFO.box.size)
		cs.position = _rf_arr(RIFLE_INFO.box.centre)
	cs.shape = box
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
	_snap_fingers.call_deferred()


## World position of the gun's muzzle (roughly the right hand).
func muzzle_position() -> Vector3:
	if _muzzle and is_instance_valid(_muzzle):
		return _muzzle.global_position
	var hand: PhysicalBone3D = ragdoll.bones.get(&"RightHand")
	return hand.global_position if hand else global_position + Vector3.UP * 1.3


## Whether the ground drops away (more than 1.2 m) within a metre behind the
## clown along the shot, with nothing in the way: the lip of a trench, the
## open side of a footbridge.
func _drop_behind(shot_dir: Vector3) -> bool:
	var back := Vector3(shot_dir.x, 0, shot_dir.z)
	if back.length() < 0.01 or not is_inside_tree():
		return false
	back = back.normalized()
	var space := get_world_3d().direct_space_state
	var feet := global_position.y
	var chest := global_position + Vector3.UP * 1.1
	for d: float in [0.55, 0.95]:
		var q := PhysicsRayQueryParameters3D.create(chest, chest + back * d, 1)
		if not space.intersect_ray(q).is_empty():
			return false
		var top := global_position + back * d + Vector3.UP * 0.5
		var down := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 4.0, 1)
		var r := space.intersect_ray(down)
		if r.is_empty() or (r.position as Vector3).y < feet - 1.2:
			return true
	return false


## Distance to a wall close behind the clown along the shot, or -1 if there is
## none or the clown was not shot from the front.
## A wall slide only with the wall right at its back (the ray from the
## chest's centre: WALL_SLIDE_REACH less the body's own half-depth is the
## gap behind the coat), and only half the time (23 Nov: it was 1.25 m and
## 80 %, which read as a lurch to a wall a stride away).
## A rifleman's arms at death: how far from the grip toward hanging the
## muscles settle (0 = they keep the grip, 1 = all the way to the sides),
## and how much of the reflex fling they get (the ragdoll's arm_fling × this).
static var rifle_arm_settle := 0.5     # (static: dev scenes compare settings)
static var rifle_arm_fling := 0.4
static var rifle_arms_wide := false
static var rifle_arm_tone := 0.3        # the arms' muscle tone at death, as a share of the profile's
const WALL_SLIDE_REACH := 0.6
const WALL_SLIDE_CHANCE := 0.5


func _wall_behind(shot_dir: Vector3) -> float:
	var back := Vector3(shot_dir.x, 0, shot_dir.z)
	if back.length() < 0.01:
		return -1.0
	back = back.normalized()
	if global_basis.z.dot(back) > -0.3:          # not facing the shooter
		return -1.0
	var from := global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + back * WALL_SLIDE_REACH, 1)
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
