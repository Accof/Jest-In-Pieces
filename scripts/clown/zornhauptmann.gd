class_name Zornhauptmann
extends Rattlejack
## Der Zornhauptmann: a porcelain-faced clown officer in a charcoal tunic and
## a Pickelhaube. A common elite: a quarter tougher than a WitzSoldat, slow
## and deliberate. He walks up with a pistol held low, raises it in plain
## sight (0.8-1.3 s), fires one accurate round every two or three seconds,
## and draws back to the sabre in his other hand when you get close: a
## readable wind-up, a slash or a thrust, then a moment where he is open.
## Now and then a miss makes him furious for a beat (a stamp, a shake of the
## head, a snarl through the teeth).
##
## His death, one time in five, is the Last Defiance. The kill counts at once;
## the body plays it out (1.8-2.5 s) before the ragdoll takes it:
##   0.0-0.4  the round lands: thrown back, twisted, a shoulder drops, the
##            knees bend;
##   0.4-1.0  a heavy slump to one side, head hanging, the whole body (hips,
##            knees, ankles, planted feet) fighting to stay up, trembling;
##   1.0-1.8  the pistol comes up, shaking, wavering, the head lifting;
## and then the trigger: one real (and badly aimed) round, a dry click, a
## "BANG!" flag on a rod, a puff of confetti, or a few soap bubbles. He goes
## down. Nothing gives away which it will be until the trigger is pulled.
##
## The staged-death machinery (balance, foot IK, pose-matched hand-over to
## the ragdoll, every bone's speed carried over) is the Rattlejack's.

@export_group("Officer")
## Health against a WitzSoldat's (multiplies max_health in _ready).
@export var officer_health_multiplier := 1.25
@export var pistol_damage := 14.0
@export var furious_miss_chance := 0.15          ## of his misses, how many make him furious for a beat
@export var sabre_slash_damage := 28.0
@export var sabre_thrust_damage := 34.0
@export var sabre_windup := 0.55                 ## seconds the blade goes back (the tell)
@export var sabre_strike := 0.14
@export var sabre_recover := 0.65                ## seconds he is open after it

@export_group("Last Defiance")
@export var enable_last_defiance := true
@export var last_defiance_chance := 0.6
@export var real_shot_weight := 0.55
@export var fail_to_fire_weight := 0.2
@export var bang_flag_weight := 0.15
@export var confetti_weight := 0.07
@export var bubbles_weight := 0.03
@export var last_defiance_min_duration := 1.8    ## from the fatal hit to the ragdoll
@export var last_defiance_max_duration := 2.5
@export var last_defiance_interruptible := true  ## another hit sends him straight to the ragdoll
@export var last_defiance_interrupt_grace := 0.45  ## seconds after the fatal hit when more rounds only rock him (the trigger finger is still going)
@export var max_real_shots := 1
@export var real_shot_spread := 9.0              ## degrees: a dying man's aim
@export var bang_flag_visible_duration := 0.0    ## seconds before the flag is taken away; 0: as long as the pistol
@export var confetti_particle_count := 70
@export var bubble_count_min := 3
@export var bubble_count_max := 7

const OUTCOMES := ["real_shot", "fail_to_fire", "bang_flag", "confetti", "bubbles"]

## Testing (the L key): every eligible death is a Last Defiance.
static var always_defiance := false

## Tests: force the outcome ("" to roll it).
var force_outcome := ""
## Tests and the killcam.
var defiance_outcome := ""
var defiance_rolled := false        ## an eligible death rolled for it
var defiance_eligible := false
var defiance_fired_at := -1.0       ## seconds after the fatal hit the trigger went
var defiance_interrupted := false
var defiance_events: Array = []     ## [seconds, what]
var real_shots := 0
var real_shot_result := ""          ## "", "player", "player_spared" (killcam), "clown", "world", "nothing"
var flag: Node3D                    ## the BANG! flag, while it is out
var furious := 0                    ## times he lost his temper
var sabre_swings := 0
var pistol_shots := 0               ## rounds fired alive
var swing_kind := ""                ## "slash" or "thrust", the swing under way

var _gun_node: Node3D
var _gun_up_h := Vector3(0, 0, 1)   # the pistol's top, in the hand bone's frame
var _sabre: Node3D
var _sabre_att: BoneAttachment3D
var _sabre_side := "Left"
var _blade_h := Vector3.BACK        # the blade's direction in the hand bone's frame
var _slump := 1.0                   # +1 slumps to his left (+X), -1 to his right
var _r0 := 1.0
var _t_fire := 1.6
var _collapse_at := 2.0
var _flag_pause := 0.5
var _fired := false
var _target_world := Vector3.INF
var _seed := 0.0
var _fury_t := -1.0
var _stamped := false
var _swing_prev := -1.0
var _whooshed := false
var _breath_t := 4.0
var _step_k := 0
var _breathed := false


func _init() -> void:
	body = "zornhauptmann"
	enable_hybrid_deaths = false              # his other deaths go straight to the ragdoll
	enable_random_collapse_direction = false  # the Last Defiance picks its own fall


func _ready() -> void:
	health_mult = officer_health_multiplier
	super._ready()
	_breath_t = randf_range(2.0, 5.0)


## A fresh brain gets the officer's settings.
func setup_brain(b: ClownBrain) -> void:
	b.officer()
	b.gun_damage = pistol_damage
	b.attack_time = sabre_windup + sabre_strike + sabre_recover
	b.attack_hit_at = sabre_windup + sabre_strike * 0.6
	b.attack_recover = 0.5


## Pistol in the right hand, sabre in the left.
func give_officer_kit() -> void:
	give_gun("Right")
	give_sabre("Left")


# --- the pistol ----------------------------------------------------------------------------
## A long-barrelled officer's pistol in the hand: barrel along the fingers,
## grip in the palm. Its own muzzle, so flashes and the Last Defiance's
## flag, confetti and bubbles come from the real barrel.
func give_gun(side: String = "Right") -> void:
	has_gun = true
	gun_side = side
	var att := BoneAttachment3D.new()
	att.bone_name = side + "Hand"
	skeleton.add_child(att)
	_gun_att = att
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.06, 0.06, 0.065)
	steel.metallic = 0.85
	steel.roughness = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.13, 0.06)
	wood.roughness = 0.6
	# laid out with the grip's top at the origin, barrel along +Z, up +Y
	var gun := Node3D.new()
	_rifle_part(gun, Vector3(0.026, 0.034, 0.13), Vector3(0, 0.03, 0.02), steel)        # frame and toggle
	_cyl(gun, 0.008, 0.12, Vector3(0, 0.038, 0.14), Vector3.BACK, steel)               # barrel
	_rifle_part(gun, Vector3(0.008, 0.012, 0.008), Vector3(0, 0.05, 0.19), steel)     # foresight
	_cyl(gun, 0.009, 0.026, Vector3(0, 0.05, -0.04), Vector3.RIGHT, steel)             # toggle knobs
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.028, 0.095, 0.036)
	gm.material = wood
	grip.mesh = gm
	grip.transform = Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, -0.035, -0.025))
	grip.layers = 2
	gun.add_child(grip)
	var guard := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.014
	tm.outer_radius = 0.018
	tm.material = steel
	guard.mesh = tm
	guard.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.0, 0.025))
	guard.layers = 2
	gun.add_child(guard)
	att.add_child(gun)
	# in the hand: barrel along the bone (the fingers), its top on the thumb
	# side (forward in the T-pose the rig was built in, palms down), so a
	# hand held thumb-up holds it upright with the wrist straight; the grip
	# sits in the palm
	var hr := skeleton.get_bone_global_rest(skeleton.find_bone(side + "Hand")).basis.orthonormalized()
	var along := Vector3(0, 1, 0)
	var thumb := hr.inverse() * Vector3(0, 0, 1)
	thumb = (thumb - along * thumb.dot(along)).normalized()
	var palm := hr.inverse() * Vector3(0, -1, 0)
	_gun_up_h = thumb
	gun.transform = Transform3D(Basis(thumb.cross(along), thumb, along), along * 0.055 + thumb * 0.035 + palm * 0.02)
	_gun_node = gun
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.038, 0.205)
	gun.add_child(_muzzle)


## A pistol round: the kick, the flash, a sharp report (the Rattlejack's
## Lewis-gun version is not wanted here).
func fired() -> void:
	_shot_t = 0.0
	var at := muzzle_position()
	var dir := _muzzle.global_basis.z if _muzzle and is_instance_valid(_muzzle) else global_basis.z
	MuzzleFlash.burst(get_parent(), at, dir, 0.6)
	play_sfx("shot_%d" % (randi() % 3), at, 0.0, 1.5)
	if not dead:
		pistol_shots += 1


## Keep the pistol upright (by `w`) by turning the whole arm about the line
## from the shoulder to the hand, as a man does, rather than wringing the
## wrist: the hand stays straight on the forearm.
func _upright_gun(side: String, w: float) -> void:
	if w <= 0.001:
		return
	var ua := skeleton.find_bone(side + "UpperArm")
	var hb := skeleton.find_bone(side + "Hand")
	var sh := skeleton.get_bone_global_pose(ua).origin
	var hp := skeleton.get_bone_global_pose(hb)
	var axis := hp.origin - sh
	if axis.length() < 0.05:
		return
	axis = axis.normalized()
	var up := hp.basis.orthonormalized() * _gun_up_h
	var want := Vector3.UP - axis * axis.dot(Vector3.UP)
	var have := up - axis * axis.dot(up)
	if want.length() < 0.05 or have.length() < 0.05:
		return
	var ang := have.normalized().signed_angle_to(want.normalized(), axis)
	_rotate_global(ua, Quaternion(axis, ang * w))


# --- the sabre -----------------------------------------------------------------------------
## A curved cavalry sabre: a steel blade with a slight curve, a brass D-guard,
## a dark grip. Held point down and forward by his side.
func give_sabre(side: String = "Left") -> void:
	_sabre_side = side
	var att := BoneAttachment3D.new()
	att.bone_name = side + "Hand"
	skeleton.add_child(att)
	_sabre_att = att
	_sabre = Node3D.new()
	att.add_child(_sabre)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.7, 0.72)
	steel.metallic = 0.85
	steel.roughness = 0.3
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.55, 0.4, 0.16)
	brass.metallic = 0.8
	brass.roughness = 0.4
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.06, 0.04, 0.03)
	grip_mat.roughness = 0.7
	# laid out with the grip at the origin, the blade along +Z, the edge down (-Y)
	_cyl(_sabre, 0.014, 0.11, Vector3(0, 0, -0.01), Vector3.BACK, grip_mat)
	_rifle_part(_sabre, Vector3(0.012, 0.05, 0.012), Vector3(0, -0.01, 0.05), brass)    # quillon
	_rifle_part(_sabre, Vector3(0.008, 0.008, 0.13), Vector3(0, -0.045, 0.0), brass)     # knuckle bow
	var n := 8
	var seg := 0.8 / n
	var pos := Vector3(0, 0, 0.06)
	var ang := 0.0
	for k in n:
		var dir := Vector3(0, sin(ang), cos(ang))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var taper := lerpf(1.0, 0.45, float(k) / (n - 1))
		bm.size = Vector3(0.006 * taper + 0.002, 0.034 * taper + 0.005, seg + 0.004)
		bm.material = steel
		mi.mesh = bm
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -ang), pos + dir * seg * 0.5)
		mi.layers = 2
		_sabre.add_child(mi)
		pos += dir * seg
		ang += 0.022                   # the curve: the point rises a little (edge down)
	# in the fist, pointing forward and down with the arm hanging
	var hand := skeleton.find_bone(side + "Hand")
	var hx := skeleton.get_bone_global_pose(hand)
	var fore := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerArm")).origin
	var along := (hx.origin - fore).normalized()
	var held := Transform3D(_basis_along(Vector3(0.05, -1.0, 0.75).normalized(), Vector3(0, 0, 1)), hx.origin + along * 0.07)
	_sabre.transform = hx.affine_inverse() * held
	_blade_h = (hx.basis.orthonormalized().inverse() * held.basis.z).normalized()


func has_sabre() -> bool:
	return _sabre != null and is_instance_valid(_sabre)


func _drop_sabre() -> void:
	if not has_sabre():
		return
	var xf := _sabre.global_transform
	var body_ := RigidBody3D.new()
	body_.collision_layer = 1 << 3
	body_.collision_mask = 1 | (1 << 3)
	body_.mass = 1.2
	body_.continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.08, 0.9)
	cs.shape = box
	cs.position = Vector3(0, 0, 0.4)
	body_.add_child(cs)
	_sabre.get_parent().remove_child(_sabre)
	body_.add_child(_sabre)
	_sabre.transform = Transform3D.IDENTITY
	get_parent().add_child(body_)
	body_.global_transform = xf
	body_.linear_velocity = velocity + Vector3(randf_range(-0.5, 0.5), 0.2, randf_range(-0.5, 0.5))
	body_.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	_sabre = null
	if _sabre_att and is_instance_valid(_sabre_att):
		_sabre_att.queue_free()
	_sabre_att = null


## Turn the hand so the blade points along `dir` (skeleton space).
func _point_blade(dir: Vector3, w: float = 1.0) -> void:
	var hb := skeleton.find_bone(_sabre_side + "Hand")
	var gp := skeleton.get_bone_global_pose(hb)
	var cur := (gp.basis.orthonormalized() * _blade_h).normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.9999:
		return
	_rotate_global(hb, Quaternion(cur, cur.slerp(want, w).normalized()))


## The swing (brain's clock `t`, seconds): the blade goes back where you can
## see it, comes through fast, and stays out while he recovers.
func _sabre_pose(t: float) -> void:
	var W := sabre_windup
	var S := sabre_strike
	var R := sabre_recover
	if t < _swing_prev or (_swing_prev < 0.0 and t >= 0.0):
		swing_kind = "thrust" if randf() < 0.4 else "slash"
		sabre_swings += 1
		_whooshed = false
	_swing_prev = t
	var sk := skeleton
	var side := _sabre_side
	var s := 1.0 if side == "Left" else -1.0
	var sh := sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
	var hb := sk.find_bone(side + "Hand")
	var rest_hand := sk.get_bone_global_pose(hb).origin
	var rest_blade := (sk.get_bone_global_pose(hb).basis.orthonormalized() * _blade_h).normalized()
	var wind: Vector3
	var wind_blade: Vector3
	var end: Vector3
	var end_blade: Vector3
	var pole_w: Vector3
	if swing_kind == "thrust":
		wind = sh + Vector3(0.1 * s, -0.28, -0.24)
		wind_blade = Vector3(-0.05 * s, 0.05, 1.0)
		end = sh + Vector3(-0.1 * s, -0.08, 0.64)
		end_blade = Vector3(-0.08 * s, 0.0, 1.0)
		pole_w = sh + Vector3(0.45 * s, -0.4, -0.3)
	else:
		wind = sh + Vector3(0.14 * s, 0.36, -0.2)
		wind_blade = Vector3(0.2 * s, 0.75, -0.6)
		end = sh + Vector3(-0.44 * s, -0.4, 0.4)
		end_blade = Vector3(-0.85 * s, -0.3, 0.45)
		pole_w = sh + Vector3(0.5 * s, 0.25, -0.25)
	var hand: Vector3
	var blade: Vector3
	var pole := pole_w
	var twist := 0.0
	if t < W:
		var u := smoothstep(0.0, 1.0, t / W)
		hand = rest_hand.lerp(wind, u)
		blade = rest_blade.slerp(wind_blade.normalized(), u)
		twist = 0.32 * u
	elif t < W + S:
		var v := (t - W) / S
		v = v * v * (3.0 - 2.0 * v)
		hand = wind.lerp(end, v)
		blade = wind_blade.normalized().slerp(end_blade.normalized(), v)
		twist = lerpf(0.32, -0.38, v)
		if not _whooshed:
			_whooshed = true
			_play("whoosh", global_position + Vector3.UP * 1.3, -2.0, 1.0)
	else:
		var r := smoothstep(W + S + R * 0.45, W + S + R, t)
		hand = end.lerp(rest_hand, r)
		blade = end_blade.normalized().slerp(rest_blade, r)
		twist = lerpf(-0.38, 0.0, r)
	_turn("Spine", Vector3.UP, twist * s)
	reach(side, hand, pole)
	_point_blade(blade)


## Whether the swing under way reaches the player now (the brain asks at the
## moment it lands): damage, or 0 for a miss. A thrust reaches further but
## only straight ahead; a slash covers a wide arc but not as far. Stepping
## back or round him during the wind-up beats both.
func melee_hits(target: Node3D) -> float:
	var b := get_node_or_null("Brain") as ClownBrain
	var mr := b.melee_range if b else 1.9
	var to := target.global_position - global_position
	var dy := to.y
	to.y = 0.0
	var fwd := Vector3(global_basis.z.x, 0, global_basis.z.z).normalized()
	var ang := rad_to_deg(fwd.angle_to(to.normalized())) if to.length() > 0.01 else 0.0
	var thrust := swing_kind == "thrust"
	var reach_ := mr + (0.5 if thrust else 0.3)
	var cone := 22.0 if thrust else 62.0
	if to.length() > reach_ or absf(dy) > 1.4 or ang > cone:
		return 0.0
	if not has_sabre():
		return 8.0                     # a fist
	return sabre_thrust_damage if thrust else sabre_slash_damage


# --- temper ---------------------------------------------------------------------------------
## The brain tells him he missed. Now and then it gets to him: a stamp, a
## shake of the head, a snarl, over in under a second. Returns how long he
## is busy with it (the brain waits that long before aiming again).
func missed() -> float:
	if dead or _fury_t >= 0.0 or randf() >= furious_miss_chance:
		return 0.0
	_fury_t = 0.0
	_stamped = false
	furious += 1
	_play("snarl", _head_pos(), -4.0, randf_range(0.85, 1.0))
	return 0.75


func _fury_pose(delta: float) -> void:
	_fury_t += delta
	var f := _fury_t
	if f > 0.8:
		_fury_t = -1.0
		return
	var k := sin(clampf(f / 0.8, 0.0, 1.0) * PI)
	# a short shake of the head, the shoulders hunched, the pistol jerked down
	_turn("Neck", Vector3.UP, 0.16 * sin(f * 24.0) * k)
	_turn("Chest", Vector3.RIGHT, 0.07 * k)
	for side: String in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		_turn(side + "Shoulder", Vector3.BACK, 0.08 * s * k)
	# the stamp: the right foot comes up and down hard
	var lift := _pulse(f, 0.1, 0.24, 0.36)
	_turn("RightUpperLeg", Vector3.RIGHT, -0.32 * lift)
	_turn("RightLowerLeg", Vector3.RIGHT, 0.55 * lift)
	if not _stamped and f > 0.34:
		_stamped = true
		_play("stamp", global_position + global_basis * Vector3(-0.15, 0.05, 0.1), -2.0, 1.0)


# --- every frame ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if dying != "" or dead:
		super._process(delta)
		return
	super._process(delta)
	if dead or dying != "":
		return
	var d := minf(delta, 1.0 / 30.0)
	# the shoulders are not among the bones the base pose resets each frame:
	# put them back, or the temper's shrug adds up frame after frame until an
	# arm sticks out sideways
	for bi: int in _rest:
		if skeleton.get_bone_name(bi).ends_with("Shoulder"):
			skeleton.set_bone_pose_rotation(bi, _rest[bi])
	# the pistol: low, then raised at the player where he can see it coming
	var arm := gun_side if has_gun and gun_side != "" and not arm_out(gun_side) else ""
	if arm != "":
		_pistol_arm(arm, smoothstep(0.0, 1.0, aim_amount), Vector3.ZERO, _recoil())
	var b := get_node_or_null("Brain") as ClownBrain
	var swing: float = b._attack_t if b else -1.0
	if swing >= 0.0 and has_sabre() and not arm_out(_sabre_side):
		_sabre_pose(swing)
	else:
		_swing_prev = -1.0
	if _fury_t >= 0.0:
		_fury_pose(d)
	_sounds(d)


## Boots on the floor, and his breathing.
func _sounds(d: float) -> void:
	var k := int(floor(walk_phase / PI))
	if k != _step_k:
		_step_k = k
		if walk_amount > 0.1 or Vector3(velocity.x, 0, velocity.z).length() > 0.3:
			var side := 1.0 if k % 2 == 0 else -1.0
			_play("step", global_position + global_basis * Vector3(0.12 * side, 0.03, 0.0), -10.0, randf_range(0.9, 1.05))
	_breath_t -= d
	if _breath_t <= 0.0:
		_breath_t = randf_range(3.5, 6.0)
		_play("breath", _head_pos(), -14.0, randf_range(0.85, 1.0))


func _head_pos() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin


## The pistol arm (skeleton space): `w` 0 is low ready (pistol down and
## forward), 1 aimed at aim_point with the arm nearly straight; `waver` bends
## the line; `kick` is the recoil.
func _pistol_arm(side: String, w: float, waver: Vector3, kick: float, target_world := Vector3.INF) -> Vector3:
	var sk := skeleton
	var s := 1.0 if side == "Left" else -1.0
	var ua := sk.find_bone(side + "UpperArm")
	var la := sk.find_bone(side + "LowerArm")
	var hb := sk.find_bone(side + "Hand")
	var sh := sk.get_bone_global_pose(ua).origin
	var length := sh.distance_to(sk.get_bone_global_pose(la).origin) + sk.get_bone_global_pose(la).origin.distance_to(sk.get_bone_global_pose(hb).origin)
	var tw := target_world if target_world != Vector3.INF else aim_point
	var tgt := Vector3(0, -0.05, 1).normalized()
	if tw != Vector3.INF:
		var v := sk.global_transform.affine_inverse() * tw - sh
		if v.length() > 0.3:
			tgt = v.normalized()
	var low := Vector3(0.12 * s, -0.92, 0.4).normalized()
	var dir := (low.slerp(tgt, clampf(w, 0.0, 1.0)) + waver).normalized()
	dir = (dir + Vector3.UP * 0.3 * kick * w).normalized()
	reach(side, sh + dir * length * lerpf(0.9, 0.97, w), sh + Vector3(0.4 * s, -0.5, -0.1))     # elbow out and down
	point_bone(side + "Hand", dir)
	_upright_gun(side, w)
	return dir


# --- dying ---------------------------------------------------------------------------------
func _die(info: Dictionary, zone: StringName) -> void:
	if _throat_ok(info, zone):
		death_kind = "throat"
		handed_over = true
		handover_at = 0.0
		_begin_throat(info, zone)
		return
	defiance_eligible = _defiance_ok(info, zone)
	var forced := force_death == "defiance"
	var go := false
	if defiance_eligible and (forced or force_death == ""):
		defiance_rolled = not forced
		go = forced or always_defiance or randf() < last_defiance_chance
	if not go:
		var was := force_death
		if force_death == "defiance":
			force_death = ""
		super._die(info, zone)
		force_death = was
		_fury_t = -1.0
		return
	dead = true
	_record_death(info, zone)
	_begin("defiance", info, zone)


## Can this death be a Last Defiance: a fatal round in the body or an arm
## (not the head), any gun but the stake, nothing blown up or off, the pistol
## still in a working hand, and on his feet.
func _defiance_ok(info: Dictionary, zone: StringName) -> bool:
	if not enable_last_defiance:
		return false
	# (a heavy round, a rifle or a shotgun, is fine: only what blows him apart is not)
	if info.get("blast", false) or info.get("stake", false) or info.has("profile"):
		return false
	if info.get("can_dismember", false) and float(info.get("damage", 0.0)) >= dismember_damage:
		return false
	if zone not in [&"Chest", &"Spine", &"Hips", &"UpperArm", &"LowerArm"]:
		return false
	if not has_gun or gun_side == "" or arm_out(gun_side) or _gun_att == null or not is_instance_valid(_gun_att):
		return false
	if crawling or downed or last_stand or ragdoll.active or _halved or broken_leg != "" or not broken_legs.is_empty():
		return false
	if gore and gore.hidden_mask != 0:
		return false
	return true


func _pick_outcome() -> String:
	var w := [real_shot_weight, fail_to_fire_weight, bang_flag_weight, confetti_weight, bubbles_weight]
	var total := 0.0
	for x: float in w:
		total += maxf(x, 0.0)
	if total <= 0.0:
		return "fail_to_fire"
	var r := randf() * total
	for i in w.size():
		r -= maxf(w[i], 0.0)
		if r < 0.0:
			return OUTCOMES[i]
	return OUTCOMES[OUTCOMES.size() - 1]


## The share of each outcome after normalising the weights (tests, tuning).
func outcome_odds() -> Dictionary:
	var w := [real_shot_weight, fail_to_fire_weight, bang_flag_weight, confetti_weight, bubbles_weight]
	var total := 0.0
	for x: float in w:
		total += maxf(x, 0.0)
	var out := {}
	for i in w.size():
		out[OUTCOMES[i]] = maxf(w[i], 0.0) / total if total > 0.0 else 0.0
	return out


func _begin(kind: String, info: Dictionary, zone: StringName) -> void:
	super._begin(kind, info, zone)
	if kind != "defiance":
		return
	defiance_outcome = force_outcome if force_outcome in OUTCOMES else _pick_outcome()
	defiance_events = [[0.0, "impact"]]
	defiance_fired_at = -1.0
	defiance_interrupted = false
	real_shot_result = ""
	_fired = false
	_breathed = false
	_fury_t = -1.0
	_seed = randf() * 10.0
	# he slumps the way the round pushed him, unless there is a wall there
	_slump = signf(_hit_local.x) if absf(_hit_local.x) > 0.25 else (1.0 if randf() < 0.5 else -1.0)
	if _room(Vector3(_slump, 0, 0), 0.8) < 0.45 and _room(Vector3(-_slump, 0, 0), 0.8) > 0.6:
		_slump = -_slump
	var dur := randf_range(last_defiance_min_duration, maxf(last_defiance_max_duration, last_defiance_min_duration))
	_collapse_len = 0.14               # the ragdoll has him from the start of the final fall
	_flag_pause = randf_range(0.4, 0.7)
	var tail := _tail(defiance_outcome)
	_t_fire = clampf(dur - _collapse_len - tail, 1.3, 1.85)
	_collapse_at = _t_fire + tail
	_r0 = minf(1.0, _t_fire - 0.5)
	_T = _collapse_at
	_k0 = 8.5
	_k1 = 8.5
	_damp = 2.4
	_cv = _hit_local * 0.25
	_steps_left = 0
	_twist = randf_range(-1.0, 1.0)
	# what he will try to aim at: where the player is now
	var b := get_node_or_null("Brain") as ClownBrain
	if b and b.player and is_instance_valid(b.player):
		# roughly where the player was, no better: a dying man's aim
		_target_world = b.player.global_position + Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.3), randf_range(-0.8, 0.8))
	else:
		_target_world = global_transform * Vector3(0, 1.0, 5.0)


## Seconds from the trigger to the fall, by outcome.
func _tail(outcome: String) -> float:
	match outcome:
		"real_shot":
			return 0.07                 # the recoil puts him down
		"fail_to_fire":
			return randf_range(0.42, 0.52)
		"bang_flag":
			return 0.15 + _flag_pause + 0.15
		"confetti":
			return randf_range(0.4, 0.55)
		"bubbles":
			return randf_range(0.45, 0.6)
	return 0.3


func _dying_process(d: float) -> void:
	super._dying_process(d)
	if dying != "defiance":
		return
	if not _breathed and _t > 0.45:
		_breathed = true
		_play("breath", _head_pos(), -8.0, 0.75)
	# the pistol gone from his hand (a shotgun's later pellets): nothing to fire
	if not _fired and (not has_gun or gun_side == "" or arm_out(gun_side)):
		_fired = true
		defiance_events.append([_t, "lost_pistol"])
		if not _collapsing:
			_start_collapse(Vector3(_slump, 0, 0))
		return
	if not _fired and _t >= _t_fire and not _collapsing:
		_fired = true
		defiance_fired_at = _t
		defiance_events.append([_t, defiance_outcome])
		_trigger()
	if not _collapsing and _t >= _collapse_at:
		var dir := Vector3(_slump, 0, 0) + Vector3(0, 0, -0.25)
		if defiance_outcome == "real_shot":
			dir += Vector3(0, 0, -0.5)        # thrown back by his own shot
		_start_collapse(dir)
		defiance_events.append([_t, "collapse"])


## The trigger is pulled.
func _trigger() -> void:
	if _muzzle == null or not is_instance_valid(_muzzle):
		return
	var at := _muzzle.global_position
	match defiance_outcome:
		"real_shot":
			_real_shot()
		"fail_to_fire":
			_play("dry_click", at, -2.0, 1.0)
		"bang_flag":
			_play("pop", at, -1.0, 1.0)
			_play("spring", at, -6.0, 1.0)
			var f := BangFlag.new()
			f.life = bang_flag_visible_duration
			_muzzle.add_child(f)
			flag = f
		"confetti":
			_play("soft_pop", at, -4.0, 1.0)
			_confetti(at, _muzzle.global_basis)
		"bubbles":
			_play("squeak", at, -6.0, randf_range(0.95, 1.08))
			_bubbles(at, _muzzle.global_basis.z)


## One real round from the real muzzle: wherever it points, not at the player.
## The killcam takes the player's controls away, so then it never hurts him.
func _real_shot() -> void:
	if real_shots >= max_real_shots:
		return
	real_shots += 1
	var from := _muzzle.global_position
	var mb := _muzzle.global_basis.orthonormalized()
	var sp := deg_to_rad(real_shot_spread)
	var dir := (mb.z + mb.x * randfn(0.0, sp) + mb.y * randfn(0.0, sp)).normalized()
	fired()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, 1 | (1 << 1) | (1 << 2))
	q.exclude = _own_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * 40.0
	real_shot_result = "nothing"
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c is PhysicalBone3D and c.has_meta(&"clown"):
			var other := c.get_meta(&"clown") as Clown
			if other != self:
				real_shot_result = "clown"
				other.hit({collider = c, position = hit.position, direction = dir, damage = pistol_damage,
					impulse = 6.0, shot_id = randi(), weapon = "Pistol", dist = from.distance_to(hit.position), friendly = true})
		elif c and c.has_method("take_damage"):
			if bool(c.get("cinematic")):
				real_shot_result = "player_spared"
			else:
				real_shot_result = "player"
				c.take_damage(pistol_damage, dir)
		elif c and c.has_method("shot"):
			real_shot_result = "world"
			c.shot(hit.position, dir, pistol_damage)
		else:
			real_shot_result = "world"
			MechFx.sparks(self, hit.position, (hit.normal as Vector3), 0.3)
	_tracer(from, end)
	var back := global_basis.inverse() * -dir
	_cv += Vector3(back.x, 0, back.z).limit_length(1.0) * 0.3


## A restrained puff of old paper confetti: out of the barrel, then down.
func _confetti(at: Vector3, basis_: Basis) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(confetti_particle_count, 1)
	p.lifetime = 2.6
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 26.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 1.4
	p.damping_max = 2.6
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	g.colors = PackedColorArray([Color(0.6, 0.17, 0.14), Color(0.82, 0.68, 0.3), Color(0.26, 0.36, 0.52), Color(0.86, 0.82, 0.68)])
	p.color_initial_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.009)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	q.material = m
	p.mesh = q
	p.add_to_group(&"zorn_vfx")
	get_parent().add_child(p)
	p.global_transform = Transform3D(basis_.orthonormalized(), at)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)


## A few soap bubbles drifting out of the barrel and up; some pop.
func _bubbles(at: Vector3, dir: Vector3) -> void:
	var n := randi_range(mini(bubble_count_min, bubble_count_max), maxi(bubble_count_min, bubble_count_max))
	for i in n:
		var bub := Bubble.new()
		bub.radius = randf_range(0.018, 0.045)
		bub.vel = dir.normalized() * randf_range(0.35, 0.8) + Vector3(randf_range(-0.12, 0.12), randf_range(0.1, 0.3), randf_range(-0.12, 0.12))
		bub.pop_at = randf_range(0.8, 2.6) if randf() < 0.6 else -1.0
		bub.life = randf_range(2.8, 3.8)
		bub.add_to_group(&"zorn_vfx")
		get_parent().add_child(bub)
		bub.global_position = at + dir.normalized() * 0.02 * i + Vector3(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), randf_range(-0.01, 0.01))


## Another round lands while he plays it out: straight to the ragdoll, any
## gag not yet fired is cancelled (what is already out runs its course; the
## flag stays on the pistol). The kill was counted already.
func hit(info: Dictionary) -> void:
	if dying == "defiance" and last_defiance_interruptible:
		var same_shot: bool = info.has("shot_id") and _info.has("shot_id") and info.shot_id == _info.shot_id
		if not same_shot and _t >= last_defiance_interrupt_grace:
			defiance_interrupted = true
			defiance_events.append([_t, "interrupted" if not _fired else "interrupted_after"])
			_fired = true
			var dd: Vector3 = info.get("direction", Vector3.ZERO)
			dd.y = 0.0
			if dd.length() > 0.01:
				fall_dir = dd.normalized()
			_handover()
	super.hit(info)


func _hit_while_dying(info: Dictionary) -> void:
	if dying != "defiance":
		super._hit_while_dying(info)
		return
	# another pellet of the shot that killed him (or interruption is off): it rocks him, no more
	var d: Vector3 = info.get("direction", Vector3.ZERO)
	var dl := global_basis.inverse() * Vector3(d.x, 0, d.z)
	_cv += dl.limit_length(1.0) * 0.12


## The balance through the Last Defiance: the Rattlejack's pendulum, but it
## holds him up (he is fighting it) with a steady lean to the slump side, and
## only the timeline lets him fall.
func _balance(d: float) -> void:
	if dying != "defiance":
		super._balance(d)
		return
	var sl := smoothstep(0.35, 1.0, _t)
	var rise := smoothstep(_r0, _t_fire, _t)
	var e := _c - _support
	var k := 0.0 if _collapsing else _k0
	_acc = e * _w2 - e * k - _cv * _damp + Vector3(_slump, 0, 0) * 0.13 * sl
	if _collapsing:
		var cx := _collapse_t / _collapse_len
		_acc += _fall_local * (1.6 + 3.2 * cx * cx)
	_shove_t -= d
	if _shove_t <= 0.0 and enable_full_body_death_sway and not _collapsing:
		_shove_t = randf_range(0.1, 0.22)
		var a := randf() * TAU
		_cv += Vector3(cos(a), 0, sin(a)) * randf_range(0.02, 0.05) * torso_sway
	_cv += _acc * d
	_c += _cv * d
	_c.y = 0.0
	_cv.y = 0.0
	e = _c - _support
	if not _collapsing and e.length() > 0.12:
		_c = _support + e.normalized() * 0.12
		_cv *= 0.5
		e = _c - _support
	max_lean = maxf(max_lean, e.length())
	var sag := 0.05 * smoothstep(0.0, 0.3, _t) + 0.075 * sl - 0.025 * rise + 0.006 * sin(_t * 31.0) * sl
	if _fired and defiance_outcome == "fail_to_fire":
		sag += 0.03 * smoothstep(defiance_fired_at + 0.1, defiance_fired_at + 0.45, _t)
	if _collapsing:
		var cx := clampf(_collapse_t / _collapse_len, 0.0, 1.0)
		sag += 0.34 * cx * cx
	_drop = move_toward(_drop, sag * knee_flex, d * (1.1 if _collapsing else 0.45))


func _pose_dying(d: float) -> void:
	super._pose_dying(d)
	if dying == "defiance":
		_pose_defiance()


func _pose_defiance() -> void:
	var s := _slump
	var t := _t
	var imp := _pulse(t, 0.0, 0.06, 0.42)
	var sl := smoothstep(0.3, 1.0, t)
	var rise := smoothstep(_r0, _t_fire, t)
	var after := t - defiance_fired_at if defiance_fired_at >= 0.0 else -1.0
	var trem := sin(t * 37.0 + _seed) * 0.6 + sin(t * 53.0 + 1.3 * _seed) * 0.4
	var shake := 0.4 + 0.6 * rise
	# the round lands: thrown back, twisted, the knees bend (the balance drops him)
	_turn("Chest", Vector3.RIGHT, -0.3 * imp)
	_turn("Spine", Vector3.UP, 0.3 * imp * _twist)
	# the slump: heavy, to one side, hunched
	_turn("Spine", Vector3.BACK, -0.2 * sl * s)
	_turn("Chest", Vector3.BACK, -0.15 * sl * s + 0.014 * trem * shake * sl)
	_turn("Chest", Vector3.RIGHT, 0.14 * sl * (1.0 - 0.5 * rise))
	_turn(("Left" if s > 0.0 else "Right") + "Shoulder", Vector3.BACK, -0.12 * s * sl)
	# the head hangs, then comes up as the pistol does
	var hang := sl * (1.0 - 0.65 * rise)
	_turn("Neck", Vector3.RIGHT, 0.45 * hang + 0.012 * trem * sl)
	_turn("Neck", Vector3.BACK, -0.2 * hang * s)
	_defiance_arm(rise, after, trem)
	# the flag: a restrained turn of the head toward it before he goes
	if defiance_outcome == "bang_flag" and after > 0.15 and _muzzle and is_instance_valid(_muzzle):
		var look := smoothstep(0.15, 0.15 + _flag_pause * 0.7, after)
		var hb := skeleton.find_bone("Head")
		var hp := skeleton.get_bone_global_pose(hb)
		var to := skeleton.global_transform.affine_inverse() * _muzzle.global_position - hp.origin
		var face := hp.basis.orthonormalized() * Vector3(0, 0, 1)
		face.y = 0.0
		var flat := Vector3(to.x, 0, to.z)
		if face.length() > 0.01 and flat.length() > 0.01:
			var yaw := face.normalized().signed_angle_to(flat.normalized(), Vector3.UP)
			_turn("Head", Vector3.UP, clampf(yaw, -0.9, 0.9) * 0.5 * look)
		_turn("Head", Vector3.RIGHT, 0.12 * look)


## The pistol comes up: shaking, wavering, aimed (badly) where the player was.
func _defiance_arm(rise: float, after: float, trem: float) -> void:
	var side := gun_side
	if side == "" or not has_gun or arm_out(side):
		return
	var w := rise
	var kick := 0.0
	var shake := 1.0
	if after >= 0.0:
		match defiance_outcome:
			"real_shot":
				kick = _pulse(after, 0.0, 0.03, 0.3)
			"fail_to_fire":
				shake = 1.0 + 1.5 * (1.0 - smoothstep(0.0, 0.25, after))
				w *= 1.0 - smoothstep(0.12, 0.45, after)
			"bang_flag":
				w *= 1.0 - 0.18 * smoothstep(0.2, 0.9, after)
			_:
				w *= 1.0 - 0.2 * smoothstep(0.1, 0.5, after)
	if _collapsing:
		w *= 1.0 - 0.5 * smoothstep(0.0, 1.0, _collapse_t / _collapse_len)
	if w < 0.01:
		return
	var sk := skeleton
	var bones: Array[int] = []
	for part: String in ["UpperArm", "LowerArm", "Hand"]:
		bones.append(sk.find_bone(side + part))
	var from := {}
	for bi in bones:
		from[bi] = sk.get_bone_pose_rotation(bi)
	var waver := Vector3(sin(_t * 2.3 + _seed) * 0.07, sin(_t * 1.7 + _seed * 2.0) * 0.08 - 0.05, 0.0)
	waver += Vector3(trem, trem * 0.7, 0.0) * 0.022 * shake
	_pistol_arm(side, w, waver * (0.5 + 0.5 * w), kick, _target_world)
	var bw := smoothstep(0.0, 0.3, w)
	for bi in bones:
		sk.set_bone_pose_rotation(bi, (from[bi] as Quaternion).slerp(sk.get_bone_pose_rotation(bi), bw))


func _drop_weapons() -> void:
	super._drop_weapons()
	_drop_sabre()


## The ragdoll takes him: the sabre falls out of his hand (the pistol stays
## in it, with whatever came out of it).
func _start_ragdoll(info: Dictionary, zone: StringName) -> void:
	super._start_ragdoll(info, zone)
	_drop_sabre()


## Officer arms: a lost pistol arm leaves him the sabre; a lost sabre arm
## leaves him the pistol; both gone, he hides.
func _arm_lost(side: String) -> void:
	if dead:
		return
	if has_gun and side == gun_side:
		_drop_gun()
		has_gun = false
	if side == _sabre_side:
		_drop_sabre()
	if main_arm() == "":
		var b := get_node_or_null("Brain")
		if b and b.has_method("start_hiding") and not last_stand:
			b.start_hiding()


# --- sound -----------------------------------------------------------------------------------
func _play(sound: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	var stream := SfxSynth.stream(sound)
	if stream == null or not is_inside_tree():
		return
	one_shot(get_parent(), stream, at, db, pitch)


## A sound that plays once at `at` and frees itself (outlives whoever made it).
static func one_shot(parent: Node, stream: AudioStream, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 5.0
	p.max_distance = 45.0
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	# headless or muted: make sure it goes anyway
	var wr: WeakRef = weakref(p)
	parent.get_tree().create_timer(stream.get_length() / maxf(p.pitch_scale, 0.1) + 0.5).timeout.connect(func() -> void:
		var n: Variant = wr.get_ref()
		if n:
			(n as Node).queue_free())


# --- the gags --------------------------------------------------------------------------------
## The "BANG!" flag: a thin rod springs out of the barrel and a paper flag
## unrolls from its end, wobbling. It rides on the muzzle (through the fall
## and the ragdoll) and goes when the pistol goes.
class BangFlag extends Node3D:
	const ROD := 0.16
	var life := 0.0
	var ext := 0.0
	var ext_v := 0.0
	var wob := Vector2.ZERO
	var wob_v := Vector2(2.2, -1.4)
	var t := 0.0
	var _rod: Node3D
	var _cloth: Node3D
	var _prev := Vector3.INF
	var _prev_v := Vector3.ZERO

	func _ready() -> void:
		_rod = Node3D.new()
		add_child(_rod)
		var rm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0022
		cm.bottom_radius = 0.0022
		cm.height = ROD
		cm.radial_segments = 6
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.5, 0.5, 0.52)
		steel.metallic = 0.8
		steel.roughness = 0.35
		cm.material = steel
		rm.mesh = cm
		rm.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, ROD * 0.5))
		rm.layers = 2
		_rod.add_child(rm)
		_cloth = Node3D.new()
		add_child(_cloth)
		var paper := StandardMaterial3D.new()
		paper.albedo_color = Color(0.93, 0.85, 0.58)
		paper.roughness = 0.92
		paper.cull_mode = BaseMaterial3D.CULL_DISABLED
		var qm := QuadMesh.new()
		qm.size = Vector2(0.15, 0.085)
		qm.material = paper
		var q := MeshInstance3D.new()
		q.mesh = qm
		q.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, -0.044, -0.077))
		q.layers = 2
		_cloth.add_child(q)
		var font := FontVariation.new()
		font.base_font = ThemeDB.fallback_font
		font.variation_embolden = 1.1
		for sgn: float in [1.0, -1.0]:
			var l := Label3D.new()
			l.text = "BANG!"
			l.font = font
			l.font_size = 64
			l.pixel_size = 0.0006
			l.modulate = Color(0.72, 0.05, 0.04)
			l.outline_modulate = Color(0.05, 0.03, 0.03)
			l.outline_size = 10
			l.shaded = true
			l.double_sided = false
			l.layers = 2
			l.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * sgn), Vector3(0.0016 * sgn, -0.044, -0.077))
			_cloth.add_child(l)
		_apply()

	func _process(d: float) -> void:
		d = minf(d, 1.0 / 30.0)
		t += d
		# the spring: out in a tenth of a second or so, a little past, back
		ext_v += ((1.0 - ext) * 1100.0 - ext_v * 30.0) * d
		ext += ext_v * d
		# wobble: kicked by the spring's snap and by every move of the pistol
		var p := global_position
		var acc := Vector3.ZERO
		if _prev != Vector3.INF and d > 0.0:
			var v := (p - _prev) / d
			acc = ((v - _prev_v) / d).limit_length(60.0)
			_prev_v = v
		_prev = p
		var la := global_basis.orthonormalized().inverse() * acc
		wob_v += (-wob * 320.0 - wob_v * 5.0 + Vector2(-la.y, la.x) * 0.012) * d
		wob = (wob + wob_v * d).limit_length(0.6)
		_apply()
		if life > 0.0 and t > life:
			queue_free()

	func _apply() -> void:
		var e := maxf(ext, 0.02)
		_rod.scale = Vector3(1, 1, e)
		_cloth.position = Vector3(0, 0, ROD * e)
		var open := clampf(ext * 1.5 - 0.35, 0.03, 1.12)
		_cloth.scale = Vector3(1, open, open)
		rotation = Vector3(wob.x, wob.y, 0.0)


## A soap bubble: drifts up and away, wobbling; pops (with a tiny sound) or
## fades.
class Bubble extends MeshInstance3D:
	var radius := 0.03
	var vel := Vector3.ZERO
	var pop_at := -1.0
	var life := 3.0
	var t := 0.0
	var _ph := randf() * TAU
	static var _shader: Shader

	func _ready() -> void:
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		if _shader == null:
			_shader = load("res://shaders/bubble.gdshader")
		var m := ShaderMaterial.new()
		m.shader = _shader
		sm.material = m
		mesh = sm
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layers = 2
		set_instance_shader_parameter("swirl", randf())

	func _process(d: float) -> void:
		d = minf(d, 1.0 / 30.0)
		t += d
		vel += Vector3(0, 0.22, 0) * d
		vel *= exp(-1.1 * d)
		var drift := Vector3(sin(t * 2.1 + _ph), 0, cos(t * 1.7 + _ph)) * 0.05
		global_position += (vel + drift) * d
		var j := 1.0 + 0.04 * sin(t * 13.0 + _ph)
		scale = Vector3(j, 1.0 / j, j)
		if pop_at > 0.0 and t >= pop_at:
			var s := SfxSynth.stream("bubble_pop")
			if s:
				Zornhauptmann.one_shot(get_parent(), s, global_position, -12.0, randf_range(0.9, 1.3))
			queue_free()
			return
		var fade := 1.0 - smoothstep(life - 0.4, life, t)
		set_instance_shader_parameter("fade", fade)
		if t >= life:
			queue_free()
