extends Node
## Animation reference check: drives a WitzSoldat through the states the
## Mixamo reference clips cover (stand, aim, walk, run, crouch idle, crouch
## walk, crouched run, side-step left/right, turn on the spot) and records the
## skeleton each frame (skeleton space, with the model's hip offset) to
## /tmp/anim_ours.json, in the same shape as the reference dump, so the same
## measurements can be run over both (tools/anim_ref/analyse.py).
## Headless: godot --headless --fixed-fps 60 scenes/test_anim_ref.tscn [-- state ...]
## With a window, `-- film` also saves /tmp/ar_<state>_NN.png side views.

var room: Node3D
var s: Clown
var vel := Vector3.ZERO
var moving := false
var cam: Camera3D
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


## Which clip should be carrying each state.
const EXPECT := {"walk": "run", "walk_slow": "walk", "run": "run", "walk_back": "walk_back", "stand": "stand", "aim": "stand", "crouch_idle": "kneel", "crouch_walk": "crouch_walk",
		"crouch_run": "crouch_run", "strafe_left": "strafe", "strafe_right": "strafe", "turn_right": "turn",
		"turn_slow": "turn", "kneel_hit": "kneel", "cower": "cower", "crouch_turn": "turn"}


func _check_weights(state: String, w: Dictionary) -> void:
	if EXPECT.has(state):
		var want: String = EXPECT[state]
		var best := ""
		for k: String in w:
			if k != "share" and (best == "" or float(w[k]) > float(w[best])):
				best = k
		_check(best == want and float(w.get("share", 0.0)) > 0.9, "%s: carried by the %s clip (%s %.2f, share %.2f)" % [state, want, best, float(w.get(best, 0.0)), float(w.get("share", 0.0))])

const MAP := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine2", "Neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}


func _ready() -> void:
	_run()


func _physics_process(delta: float) -> void:
	if s and moving and is_instance_valid(s) and not s.dead:
		s.velocity = vel
		s.global_position += vel * delta


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _record(secs: float, film: String = "") -> Array:
	var out := []
	var n := int(secs * 30.0)
	var sk := s.skeleton
	for k in n:
		await get_tree().process_frame
		await get_tree().process_frame
		var fr := {}
		var model: Node3D = s._model
		var off := model.position
		for ours: String in MAP:
			var bi := sk.find_bone(ours)
			var g := sk.get_bone_global_pose(bi)
			var q := g.basis.get_rotation_quaternion()
			var l := sk.get_bone_pose_rotation(bi)
			var o := g.origin + off
			fr["mixamorig_" + MAP[ours]] = [o.x, o.y, o.z, l.x, l.y, l.z, l.w, q.x, q.y, q.z, q.w]
		for foot: String in ["LeftFoot", "RightFoot"]:
			var wp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(foot)).origin
			fr["world_" + foot] = [wp.x, wp.y, wp.z]
		out.append(fr)
		if film != "" and cam and k % 3 == 0:
			var side_dir := s.global_basis.x if not film.begins_with("strafe") else s.global_basis.z
			cam.global_position = s.global_position + side_dir * 3.4 + Vector3.UP * 1.0
			cam.look_at(s.global_position + Vector3.UP * 0.8)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/tmp/ar_%s_%02d.png" % [film, k / 3])
	return out


func _run() -> void:
	Clown.pose_lod = false
	room = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	for n in room.get_children():
		if n is ExplosiveBarrel:
			n.queue_free()
	room.clowns.clear()
	room.player.view.visible = false
	for n in room.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var args: Array = Array(OS.get_cmdline_user_args())
	var film := args.has("film") or args.has("filmref")
	if film:
		cam = Camera3D.new()
		room.add_child(cam)
		cam.make_current()
		cam.fov = 45.0
	if args.has("filmref"):
		await _film_ref()
		get_tree().quit()
		return
	s = Clown.new()
	s.body = "witzsoldat"
	room.add_child(s)
	s.global_position = Vector3(-3, 0, -4)
	s.give_rifle()
	s.always_pose = true
	s.set_process(true)
	await _frames(20)
	var states := {}
	var want := func(n: String) -> bool:
		var named: Array = args.filter(func(a: String) -> bool: return a != "film")
		return named.is_empty() or named.has(n)
	var flat_z := Vector3(0, 0, 1)
	# (name, velocity in the soldier's own frame, walk, run, crouch, aim, turn_rate, seconds)
	var plan := [
		["stand", Vector3.ZERO, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0],
		["aim", Vector3.ZERO, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0],
		["walk_slow", Vector3(0, 0, 1.4), 0.47, 0.0, 0.0, 0.0, 0.0, 2.0],
		["walk", Vector3(0, 0, 3.0), 1.0, 0.0, 0.0, 0.0, 0.0, 2.0],
		["walk_back", Vector3(0, 0, -1.2), 0.4, 0.0, 0.0, 0.0, 0.0, 2.0],
		["run", Vector3(0, 0, 5.4), 1.0, 1.0, 0.0, 0.0, 0.0, 2.0],
		["crouch_idle", Vector3.ZERO, 0.0, 0.0, 1.0, 0.0, 0.0, 3.0],
		["crouch_walk", Vector3(0, 0, 1.8), 0.6, 0.0, 0.7, 0.0, 0.0, 2.0],
		["crouch_run", Vector3(0, 0, 2.7), 0.9, 0.0, 0.55, 0.0, 0.0, 2.0],
		["strafe_left", Vector3(1.0, 0, 0), 0.33, 0.0, 0.0, 0.0, 0.0, 2.0],
		["strafe_right", Vector3(-1.0, 0, 0), 0.33, 0.0, 0.0, 0.0, 0.0, 2.0],
		["turn_right", Vector3.ZERO, 0.0, 0.0, 0.0, 0.0, -2.6, 1.5],
		["turn_slow", Vector3.ZERO, 0.0, 0.0, 0.0, 0.0, -0.66, 2.4],
		["kneel_hit", Vector3.ZERO, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0],
		["hit", Vector3.ZERO, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6],
		["cower", Vector3.ZERO, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0],
		["crouch_turn", Vector3.ZERO, 0.0, 0.0, 1.0, 0.0, -1.0, 1.5],
	]
	for p: Array in plan:
		if not want.call(p[0]):
			continue
		s.global_position = Vector3(-3, 0, -6)
		s.rotation.y = 0.0
		s.walk_amount = p[2]
		s.run_amount = p[3]
		s.crouch_amount = p[4]
		s.aim_amount = p[5]
		s.aim_point = s.global_position + Vector3(0, 1.3, 8) if p[5] > 0.0 else Vector3.INF
		s.turn_rate = p[6]
		vel = s.global_basis * (p[1] as Vector3)
		moving = vel.length() > 0.0
		s.velocity = vel
		await _frames(45)
		var spin := absf(float(p[6])) > 0.0
		var rec: Array
		if spin:
			# turn the body as the brain would while recording
			var t := create_tween()
			t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)   # as the brain turns him: before he is posed
			t.tween_property(s, "rotation:y", s.rotation.y + float(p[6]) * float(p[7]), float(p[7]))
		if p[0] == "cower":
			s.cower = true
		if p[0] in ["kneel_hit", "hit"]:
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				s._flinch_from(s.global_position + Vector3.UP * 1.3 + s.global_basis.z * 0.2, -s.global_basis.z, 40.0))
		rec = await _record(p[7], p[0] if film else "")
		s.cower = false
		states[p[0]] = {"frames": rec, "length": p[7], "speed": (p[1] as Vector3).length(), "weights": s.clip_weights.duplicate()}
		_check_weights(p[0], s.clip_weights)
		print("recorded %s: %d frames" % [p[0], rec.size()])
		moving = false
		vel = Vector3.ZERO
		s.velocity = Vector3.ZERO
		s.turn_rate = 0.0
	# the clips stay off where they do not belong
	var k: Clown = Clown.new()
	k.body = "klappersoldat"
	room.add_child(k)
	k.global_position = Vector3(2, 0, -6)
	k.always_pose = true
	k.set_process(true)
	k.velocity = Vector3(0, 0, 1.5)
	k.walk_amount = 0.5
	await _frames(20)
	_check(k.clip_weights.get("share", 0.0) == 0.0, "the Klappersoldat keeps his own clockwork (no clips)")
	k.queue_free()
	var club: Clown = Clown.new()
	club.body = "witzsoldat"
	room.add_child(club)
	club.global_position = Vector3(2, 0, -6)
	club.give_club()
	club.always_pose = true
	club.set_process(true)
	club.crouch_amount = 1.0
	await _frames(20)
	_check(club.clip_weights.get("kneel", 0.0) == 0.0, "a man without a rifle does not take the rifleman's kneel")
	club.queue_free()
	# soldiers without rifles walk on the clips' legs, arms still their own
	for kind: String in ["club", "zornhauptmann", "clown"]:
		var m: Clown
		if kind == "clown":
			m = Clown.new()
		elif kind == "club":
			m = Clown.new()
			m.body = "witzsoldat"
		else:
			m = (load("res://scripts/clown/zornhauptmann.gd") as GDScript).new()
		room.add_child(m)
		m.global_position = Vector3(2, 0, -8)
		if kind == "club":
			m.give_club()
		m.always_pose = true
		m.set_process(true)
		m.walk_amount = 0.5
		var arm0 := m.skeleton.get_bone_pose_rotation(m.skeleton.find_bone("LeftUpperArm"))
		var arm_moves := 0.0
		for i in 60:
			m.velocity = m.global_basis.z * 1.4
			m.global_position += m.velocity / 60.0
			await get_tree().physics_frame
			arm_moves = maxf(arm_moves, m.skeleton.get_bone_pose_rotation(m.skeleton.find_bone("LeftUpperArm")).angle_to(arm0))
			if cam and i % 4 == 0:
				cam.global_position = m.global_position - m.global_basis.x * 3.4 + Vector3.UP * 1.0
				cam.look_at(m.global_position + Vector3.UP * 0.8)
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("/tmp/ar_legs_%s_%02d.png" % [kind, i / 4])
		_check(float(m.clip_weights.get("walk", 0.0)) > 0.9 and m._clip_legs_only, "%s: walks on the clip's legs (walk %.2f)" % [kind, float(m.clip_weights.get("walk", 0.0))])
		_check(arm_moves > 0.1, "%s: and still swings his own arms (%.2f rad)" % [kind, arm_moves])
		m.queue_free()
		await _frames(2)
	print("ANIMREF: %d failed" % fails)
	var fa := FileAccess.open("/tmp/anim_ours.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(states))
	print("ANIMREF done")
	get_tree().quit()



## The reference clips on Mixamo's own character, filmed the same way
## (/tmp/arref_<clip>_NN.png), to set beside ours.
func _film_ref() -> void:
	var pairs := {"Rifle_Walk_1": "walk_slow", "Rifle_Run_1": "run", "Backwards_Rifle_Walk": "walk_back", "Crouch_Idle": "crouch_idle", "Walk_Crouching_Forward": "crouch_walk", "Crouched_Run": "crouch_run",
			"Strafe": "strafe_left", "Rifle_Down_To_Aim": "aim", "Turning_Right_90_Degrees": "turn_right",
			"Hit_Reaction": "kneel_hit", "Rifle_Crouch_Turn": "crouch_turn", "Rifle_Shielding_Face": "cower"}
	for f: String in pairs:
		var root: Node3D = (load("res://art/anim_ref/%s.fbx" % f) as PackedScene).instantiate()
		room.add_child(root)
		root.global_position = Vector3(-3, 0, -6)
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var an := ""
		for nm in ap.get_animation_list():
			if nm != "RESET":
				an = nm
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		ap.play(an)
		var hips := sk.find_bone("mixamorig_Hips")
		for k in 60:
			await get_tree().process_frame
			await get_tree().process_frame
			if k % 3 != 0:
				continue
			var hp := sk.global_transform * sk.get_bone_global_pose(hips).origin
			var at := Vector3(hp.x, root.global_position.y, hp.z)
			var side := Vector3.RIGHT if not f.begins_with("Strafe") else Vector3.BACK
			cam.global_position = at + side * 3.4 + Vector3.UP * 1.0
			cam.look_at(at + Vector3.UP * 0.8)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/tmp/arref_%s_%02d.png" % [pairs[f], k / 3])
		root.queue_free()
		await get_tree().process_frame
