extends Node
## The rifle slot's Lee-Enfield SMLE Mk III (key 6): the model in its parts (body,
## sliding bolt, turning handle, cocking piece) and no second rifle; ten rounds; one
## round per pull through a line of clowns; the bolt worked by the right hand after
## every shot (up, back, the case out, forward, down) and no shot until it is; dry
## when empty; charger reloads (two chargers from empty, loose rounds to top up, a
## live round out when opening on one) with the rounds counted only as they go in;
## aiming down the iron sights (notch and blade on the camera's axis, narrower view,
## no scatter); switching to and from the other guns mid-cycle and mid-reload.
## --render: /tmp/rifle_*.png; --grip: /tmp/grip_r.txt; --dump --side=R|L: fitting;
## --seq: a shot, the bolt and a reload at 30 fps (/tmp/rifle_seq_*.png).
var render := false
var failed := 0
var _player: FpsPlayer


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()


func _timed(ok: bool, what: String) -> void:
	if render:
		print("   --    %s (not timed when rendering)" % what)
		return
	_check(ok, what)


func _check(ok: bool, what: String) -> void:
	print("   %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/rifle_%s.png" % name_)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	_player._unhandled_input(e)


func _hand(arm: FPArm, v: ViewModel) -> Transform3D:
	return v._le_model.global_transform.affine_inverse() * (arm.skeleton.global_transform * arm.skeleton.get_bone_global_pose(arm._hand))


## The pinch point (between thumb and index tips) of an arm, in world space.
func _pinch(arm: FPArm) -> Vector3:
	var sk := arm.skeleton
	var tipf := func(bn: String) -> Vector3:
		var bi := sk.find_bone(bn)
		return sk.global_transform * sk.get_bone_global_pose(bi) * Vector3(0, sk.get_bone_rest(bi).origin.length() * 0.85, 0)
	return ((tipf.call("index_03.R") as Vector3) + (tipf.call("thumb_03.R") as Vector3)) * 0.5


func _knob_world(v: ViewModel) -> Vector3:
	var b := v._le_bolt.transform
	return v._le_model.global_transform * (b * (v._le_turn.transform.basis * v._knob_local()))


func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for n in room.get_children():
		if n is ExplosiveBarrel:
			n.queue_free()
	var p: FpsPlayer = room.player
	_player = p
	var v := p.view
	var pierced := [0]
	p.pierced.connect(func(n: int) -> void: pierced[0] = n)
	for i in room.clowns.size():
		var c: Clown = room.clowns[i]
		if i < 4:
			c.global_position = Vector3(0.05 * (i % 2), 0, -2.5 - i * 1.4)
			c.rotation.y = 0.0
		else:
			c.global_position = Vector3(6, 0, -9)
	p.global_position = Vector3(0, 0.05, 1.5)
	p.rotation.y = 0.0
	await _frames(30)

	# --- one rifle, in the rifle slot
	var rifles := FpsPlayer.WEAPONS.filter(func(w: Dictionary) -> bool: return w.get("bolt", false) or w.name == "Rifle" or String(w.get("label", "")).contains("SMLE"))
	_check(rifles.size() == 1 and FpsPlayer.WEAPONS[FpsPlayer.RIFLE] == rifles[0], "one rifle in the list, in the rifle slot (index %d)" % FpsPlayer.RIFLE)
	var w: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.RIFLE]
	_check(w.name == "Rifle" and w.label == "SMLE Mk III" and w.mag == 10 and w.damage >= 180.0 and w.get("semi", false), "SMLE Mk III: 10 rounds, %.0f damage a round, one shot a pull" % w.damage)
	_check(p.ammo[FpsPlayer.RIFLE] == 10 and p.rifle_chambered, "starts full, a round chambered")
	var pw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	_check(pw.name == "Pistol" and pw.damage == 34.0 and pw.mag == 17, "pistol unchanged")
	var rw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.REVOLVER]
	_check(rw.name == "Revolver" and rw.damage == 80.0 and rw.mag == 6, "revolver unchanged")
	var tw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.TRENCH]
	_check(tw.name == "Trench Shotgun" and tw.mag == 6 and tw.pump, "trench shotgun unchanged")
	var mw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.MP18]
	_check(mw.name == "MP 18" and mw.mag == 20 and mw.rpm == 500.0, "MP 18 unchanged")

	_key(KEY_6)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.RIFLE and v.weapon == ViewModel.RIFLE and v._guns[ViewModel.RIFLE].visible, "6 selects it")
	var shown := 0
	for gi in v._guns.size():
		shown += int(v._guns[gi].visible)
	_check(shown == 1, "only the rifle is shown")
	if "--grip" in OS.get_cmdline_user_args() and FileAccess.file_exists("/tmp/grip_r.txt"):
		v.apply_grip(ViewModel.RIFLE, str_to_var(FileAccess.get_file_as_string("/tmp/grip_r.txt")), v._le_model)
		print("      grip from /tmp/grip_r.txt")
	if "--dump" in OS.get_cmdline_user_args():
		_dump(v, OS.get_cmdline_user_args())
		get_tree().quit()
		return
	if "--seq" in OS.get_cmdline_user_args():
		await _seq_mode(p, v)
		get_tree().quit()
		return

	# --- the model
	var names := {}
	for n in v._le_model.find_children("*", "", true, false):
		names[String(n.name)] = true
	var parts_ok := true
	for n in ["Body", "Bolt", "BoltTurn", "CockingPiece", "Muzzle", "SightRear", "SightFront", "Ejection", "ChargerGuide", "MagMouth", "Knob"]:
		parts_ok = parts_ok and names.has(n)
	_check(parts_ok, "the model is in parts: body, bolt (turning handle, cocking piece) and the markers")
	var body := v._le_model.find_child("Body", true, false) as MeshInstance3D
	var bm := body.mesh.surface_get_material(0) as StandardMaterial3D
	_check(bm != null and bm.albedo_texture != null and bm.normal_texture != null, "the wood and steel textures are on it (Sketchfab model, CC-BY: art/weapons/smle/CREDITS.txt)")
	var ab := body.get_aabb()
	_check(absf(ab.size.x - 1.132) < 0.01, "real length: %.3f m (an SMLE is 1.132)" % ab.size.x)
	var strap := false
	for n in names:
		strap = strap or String(n).to_lower().contains("strap") or String(n).to_lower().contains("sling")
	_check(not strap, "no sling or strap")
	var arms: Dictionary = v._arms.get(ViewModel.RIFLE, {})
	_check(arms.has("R") and arms.has("L"), "the rigged arms hold it")
	_check(v._le_bolt.position.distance_to(v._le_bolt_rest) < 0.0001 and absf(v._le_turn.rotation.x) < 0.001, "the bolt starts closed and locked")
	var cam := p.camera
	var muzzle_cam := cam.to_local(v._le_muzzle.global_position)
	var dir := cam.global_basis.inverse() * (v._le_model.global_basis * Vector3.RIGHT).normalized()
	_check(muzzle_cam.x > 0.0 and muzzle_cam.y < 0.0 and muzzle_cam.z < -0.2 and dir.dot(Vector3.FORWARD) > 0.99, "shouldered on the right, pointing where the player looks")
	await _shot("0_idle")

	# --- a round through a line of four; the bolt must be worked before the next
	var target: Clown = room.clowns[0]
	cam.look_at(target.ragdoll.bones[&"Chest"].global_position)
	var r: FPArm = arms["R"]
	var l: FPArm = arms["L"]
	var rest_r := _hand(r, v)
	var rest_l := _hand(l, v)
	var hip_r := rest_r                                # the right hand at the hip (aimed, its wrist drops)
	var spent0 := v.le_spent.size()
	p.aim_override = 1.0                               # down the sights (from the hip it scatters 1.6 deg)
	await _wait(0.5)
	cam.look_at(target.ragdoll.bones[&"Chest"].global_position)
	rest_r = _hand(r, v)
	rest_l = _hand(l, v)
	p.fire()
	_check(p.ammo[FpsPlayer.RIFLE] == 9 and not p.rifle_chambered, "fired: 9 left, the chamber holds the case")
	await _frames(1)
	var before := p.ammo[FpsPlayer.RIFLE]
	p.fire()
	_check(p.ammo[FpsPlayer.RIFLE] == before, "no second shot until the bolt is worked")
	var max_lift := 0.0
	var max_draw := 0.0
	var on_knob := 0
	var l_moved := 0.0
	var thrown_at := -1.0
	var tried_mid := false
	var t := 0.0
	var shot_up := false
	var shot_back := false
	while t < 1.3:
		await get_tree().process_frame
		t += get_process_delta_time()
		max_lift = maxf(max_lift, v.le_lift)
		max_draw = maxf(max_draw, v.le_draw)
		if v.le_lift > 0.9 and _pinch(r).distance_to(_knob_world(v)) * 100.0 / ViewModel.SHRINK < 1.5:
			on_knob += 1
		l_moved = maxf(l_moved, _hand(l, v).origin.distance_to(rest_l.origin))
		if thrown_at < 0.0 and v.le_spent.size() > spent0:
			thrown_at = v.le_draw
		if not tried_mid and v.le_draw > 0.5:
			tried_mid = true
			var b2 := p.ammo[FpsPlayer.RIFLE]
			p.fire()
			_check(p.ammo[FpsPlayer.RIFLE] == b2, "no shot with the bolt open")
		if render and not shot_up and v.le_lift > 0.95 and v.le_draw < 0.2:
			shot_up = true
			v.set_process(false); await _shot("1_bolt_up"); v.set_process(true)
		if render and not shot_back and v.le_draw > 0.97:
			shot_back = true
			v.set_process(false); await _shot("2_bolt_back"); v.set_process(true)
	var dead := 0
	for i in 4:
		dead += int((room.clowns[i] as Clown).dead)
	_check(dead >= 3 and pierced[0] >= 3, "one round: %d of 4 in the line dead (pierced %d)" % [dead, pierced[0]])
	_timed(max_lift > 0.99 and max_draw > 0.99, "the bolt: handle up %.0f%%, back %.0f%%" % [max_lift * 100.0, max_draw * 100.0])
	_timed(on_knob > 3, "the right hand works it by the knob (%d frames pinching it)" % on_knob)
	_check(v.le_spent.size() == spent0 + 1, "the case flies out")
	_timed(thrown_at > 0.7, "as the bolt comes back (%.0f%% of the way)" % (thrown_at * 100.0))
	_check(l_moved < 0.001, "the left hand stays on the fore-end (moved %.4f)" % l_moved)
	_check(p.rifle_chambered and v.le_draw < 0.001 and absf(v._le_turn.rotation.x) < 0.001, "closed and locked on the next round")
	_check(_hand(r, v).origin.distance_to(rest_r.origin) < 0.001, "the right hand is back on the wrist")
	var case: RigidBody3D = v.le_spent[-1]
	p.aim_override = -1.0
	await _wait(0.8)
	_check(is_instance_valid(case) and case.global_position.y < 0.3, "the case is on the floor")

	# --- every shot after the first ejects a case and plays the whole bolt cycle too
	# (a shot once restarted the cycle without clearing what the last one had done)
	var cases_ok := 0
	var sounds_ok := 0
	for i in 3:
		var spent_before := v.le_spent.size()
		p.fire()
		var fresh := not v._le_done.has("s_up") and not v._le_done.has("s_back")
		await _wait(1.25)
		if v.le_spent.size() == spent_before + 1:
			cases_ok += 1
		if fresh and v._le_done.has("s_up") and v._le_done.has("s_back") and v._le_done.has("s_fwd") and v._le_done.has("s_down"):
			sounds_ok += 1
	_check(cases_ok == 3, "three more shots, a case out each time (%d of 3)" % cases_ok)
	_check(sounds_ok == 3, "three more shots, the bolt's four sounds each time (%d of 3)" % sounds_ok)

	# --- the left hand stays put on the fore-end through idle, walking, aiming,
	# firing and the bolt cycle (measured on the rifle, so sway and bob don't count)
	p.aim_override = -1.0
	await _wait(0.8)
	var l_ref := _hand(l, v)
	var l_worst := {}
	for phase: String in ["idle", "walk", "aim", "fire+bolt"]:
		var worst := 0.0
		var worst_deg := 0.0
		if phase == "aim":
			p.aim_override = 1.0
		if phase == "fire+bolt":
			p.fire()
		var tt := 0.0
		while tt < 1.25:
			if phase == "walk":
				v._bob_amount = 1.2
			await get_tree().process_frame
			tt += get_process_delta_time()
			var h := _hand(l, v)
			worst = maxf(worst, h.origin.distance_to(l_ref.origin))
			worst_deg = maxf(worst_deg, rad_to_deg(h.basis.get_rotation_quaternion().angle_to(l_ref.basis.get_rotation_quaternion())))
		l_worst[phase] = "%.2f mm %.2f deg" % [worst * 1000.0 / ViewModel.SHRINK, worst_deg]
		_check(worst * 1000.0 / ViewModel.SHRINK < 0.5 and worst_deg < 0.5, "left hand on the fore-end while %s (moved %s)" % [phase, l_worst[phase]])
	p.aim_override = -1.0
	await _wait(0.5)

	# --- empty: dry, and the reload: two chargers, counted as they go in
	cam.rotation.x = 0.0
	p.ammo[FpsPlayer.RIFLE] = 1
	p.rifle_chambered = true
	p.fire()
	await _wait(1.1)
	_check(p.ammo[FpsPlayer.RIFLE] == 0 and not p.rifle_chambered, "the last round: the bolt shuts on an empty chamber")
	p.fire()
	await _frames(2)
	_check(v.reloading() and p._rifle_reload_t >= 0.0, "empty: a dry click and the reload starts")
	var total := p._rifle_reload_total
	var counts: Array = []
	var charger_seen := false
	var opened := false
	var fired_in := false
	var shot_ch := false
	var shot_press := false
	var on_charger := 0
	t = 0.0
	while v.reloading() and t < total + 1.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var rt := p._rifle_reload_t
		if counts.is_empty() or counts[-1][1] != p.ammo[FpsPlayer.RIFLE]:
			counts.append([rt, p.ammo[FpsPlayer.RIFLE]])
		opened = opened or v.le_draw > 0.99
		charger_seen = charger_seen or v._le_charger.visible
		if v._le_charger.visible and _pinch(r).distance_to(v._le_charger.global_transform * Vector3(0.0, 0.05, 0)) * 100.0 / ViewModel.SHRINK < 3.0:
			on_charger += 1
		if not fired_in and rt > 1.0:
			fired_in = true
			var b3 := p.ammo[FpsPlayer.RIFLE]
			p.fire()
			_check(p.ammo[FpsPlayer.RIFLE] == b3, "no firing while reloading")
		if render and not shot_ch and v._reload_t > 0.9 and v._le_charger.visible:
			shot_ch = true
			v.set_process(false); await _shot("3_charger"); v.set_process(true)
		if render and not shot_press and v._le_charger.visible and v._le_plan.any(func(s: Dictionary) -> bool: return s.kind == "press" and v._reload_t > s.t0 + 0.25 and v._reload_t < s.t1):
			shot_press = true
			v.set_process(false); await _shot("4_press"); v.set_process(true)
	print("      ammo over the reload: %s" % [counts.map(func(c: Array) -> String: return "%d@%.2f" % [c[1], c[0]])])
	_check(opened, "the bolt opens for it")
	_check(charger_seen, "chargers are pressed in through the top")
	_timed(on_charger > 5, "by the right hand (%d frames)" % on_charger)
	var steps := counts.map(func(c: Array) -> int: return c[1])
	_check(steps == [0, 5, 10], "two chargers: 0, then 5, then 10 (%s)" % [steps])
	_timed(counts.size() == 3 and counts[1][0] > 1.0 and counts[2][0] > counts[1][0] + 1.0, "each five counted only when its charger is pressed home")
	_check(p.ammo[FpsPlayer.RIFLE] == 10 and p.rifle_chambered and not v.reloading() and v.le_draw < 0.001, "full, the bolt shut on a round (%.2f s)" % total)
	_check(absf(total - (ViewModel.L_STEP.open + 2 * (ViewModel.L_STEP.fetch + ViewModel.L_STEP.seat + ViewModel.L_STEP.press + ViewModel.L_STEP.strip) + ViewModel.L_STEP.close + ViewModel.L_STEP.settle)) < 0.001, "the reload is the sum of its steps")

	# --- topping up: 7 in (one chambered): the live round comes out, 4 loose rounds go in
	await _wait(0.3)
	p.ammo[FpsPlayer.RIFLE] = 7
	p.rifle_chambered = true
	var spent1 := v.le_spent.size()
	p.reload()
	_check(p.ammo[FpsPlayer.RIFLE] == 6 and p._rifle_events.size() == 4, "opening on a live round throws it out (6 left); four loose rounds to go")
	t = 0.0
	var seen: Array[int] = [p.ammo[FpsPlayer.RIFLE]]
	while v.reloading() and t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if seen[-1] != p.ammo[FpsPlayer.RIFLE]:
			seen.append(p.ammo[FpsPlayer.RIFLE])
	_check(seen == [6, 7, 8, 9, 10], "one at a time: %s" % [seen])
	_check(v.le_spent.size() > spent1, "the live round flew out")
	_check(p.ammo[FpsPlayer.RIFLE] == 10 and p.rifle_chambered, "full again")
	p.reload()
	_check(not v.reloading(), "full: no reload")
	# 3 in: one charger and two loose
	p.ammo[FpsPlayer.RIFLE] = 3
	p.rifle_chambered = false
	p.reload()
	_check(p._rifle_events.map(func(e: Array) -> int: return e[1]) == [5, 1, 1], "3 left, none chambered: a charger and two loose rounds")
	await _wait(p._rifle_reload_total + 0.2)
	_check(p.ammo[FpsPlayer.RIFLE] == 10 and p.rifle_chambered, "full")

	# --- aiming down the sights
	p.aim_override = 1.0
	await _wait(0.6)
	var sr := cam.to_local(v._le_model.global_transform * (v._le_mark.SightRear as Vector3))
	var sf := cam.to_local(v._le_model.global_transform * (v._le_mark.SightFront as Vector3))
	print("      aimed: rear notch %s, blade %s (camera space)" % [sr, sf])
	_check(p.ads > 0.99 and absf(sr.x) < 0.0006 and absf(sr.y) < 0.0006 and absf(sf.x) < 0.0006 and absf(sf.y) < 0.0006 and sr.z < 0.0 and sf.z < sr.z,
		"aimed: the notch and the blade on the camera's axis, one behind the other")
	_check(cam.fov < 60.0, "the view narrows (%.0f deg)" % cam.fov)
	await _shot("5_aimed")
	# where the shots go: aimed none off the line, from the hip some
	var spreads := []
	for aimed in [true, false]:
		p.aim_override = 1.0 if aimed else 0.0
		await _wait(0.5)
		var worst := 0.0
		for i in 12:
			var dirs: Array[Vector3] = []
			var w2: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.RIFLE]
			var spread: float = w2.spread + float(w2.get("hip_spread", 0.0)) * (1.0 - p.ads)
			worst = maxf(worst, spread)
		spreads.append(worst)
	_check(spreads[0] < 0.01 and spreads[1] > 1.0, "aimed: no scatter (%.2f deg); from the hip: %.1f deg" % [spreads[0], spreads[1]])
	# a shot from the aim: the bolt is worked from there, the sights come back on
	p.aim_override = 1.0
	await _wait(0.5)
	p.fire()
	await _wait(1.2)
	sr = cam.to_local(v._le_model.global_transform * (v._le_mark.SightRear as Vector3))
	_check(p.rifle_chambered and absf(sr.x) < 0.001 and absf(sr.y) < 0.001, "worked from the aim, back on the sights")
	p.reload()
	await _frames(3)
	_check(p.ads < 0.95, "reloading takes it off the aim")
	await _wait(p._rifle_reload_total + 0.3)
	p.aim_override = -1.0
	await _wait(0.4)

	# --- switching, mid-cycle and mid-reload
	p.fire()
	await _wait(0.3)
	_key(KEY_7)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.REVOLVER and v._guns[ViewModel.REVOLVER].visible and not v._guns[ViewModel.RIFLE].visible, "7 mid-bolt: the revolver")
	_key(KEY_6)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.RIFLE and p.rifle_chambered and p.ammo[FpsPlayer.RIFLE] == 9 and v.le_draw < 0.001, "back: 9 rounds, the bolt closed on one")
	p.ammo[FpsPlayer.RIFLE] = 2
	p.rifle_chambered = false
	p.reload()
	await _wait(1.85)                                   # the first charger is in
	var mid := p.ammo[FpsPlayer.RIFLE]
	_key(KEY_8)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.TRENCH and v._guns[ViewModel.TRENCH].visible, "8 mid-reload: the trench gun")
	_key(KEY_9)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.MP18 and v._guns[ViewModel.MP18].visible, "9: the MP 18")
	_key(KEY_1)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.PISTOL and v._guns[ViewModel.PISTOL].visible, "1: the pistol")
	_key(KEY_6)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.ammo[FpsPlayer.RIFLE] == mid and mid == 7 and p.rifle_chambered and not v.reloading() and not v._le_charger.visible,
		"back to the rifle: the 5 that went in are kept (%d), the bolt closed on one, no reload half-done" % mid)
	_check(r.is_visible_in_tree() and l.is_visible_in_tree() and _hand(r, v).origin.distance_to(hip_r.origin) < 0.001, "both hands back on it")
	p.fire()
	_check(p.ammo[FpsPlayer.RIFLE] == mid - 1, "and it fires")

	if render:
		await _wait(1.2)
		p.set_process(false); p.set_physics_process(false); v.set_process(false)
		var oc := Camera3D.new(); add_child(oc)
		oc.projection = Camera3D.PROJECTION_ORTHOGONAL
		var gx := v._le_model.global_transform
		for k: Array in [["right", Vector3(0, 0, 1), Vector3(-0.1, 0.15, 0), 1.25], ["action", Vector3(0, 0.2, 1), Vector3(-0.25, 0.15, 0), 0.4],
				["rhand_l", Vector3(0, 0.2, -1), Vector3(-0.30, 0.12, 0), 0.25], ["lhand", Vector3(0, -0.4, 1), Vector3(0.10, 0.17, 0), 0.3], ["lhand_l", Vector3(0, -0.3, -1), Vector3(0.10, 0.17, 0), 0.3],
				["lhand_under", Vector3(0.1, -1, 0.15), Vector3(0.09, 0.15, 0), 0.25], ["lhand_end", Vector3(1, -0.15, 0.05), Vector3(0.09, 0.15, 0), 0.2]]:
			var d_: Vector3 = (gx.basis * k[1]).normalized()
			var centre: Vector3 = gx * k[2]
			oc.size = float(k[3]) * ViewModel.SHRINK
			oc.global_position = centre + d_ * 0.8
			oc.look_at(centre, gx.basis.y.normalized())
			oc.near = 0.005
			oc.make_current()
			await _shot("out_" + String(k[0]))
	print("RIFLE: %d failed" % failed)
	get_tree().quit()


## A shot, the bolt worked, then a reload from empty, stepped at 30 fps of game time.
func _seq_mode(p: FpsPlayer, v: ViewModel) -> void:
	p.camera.rotation.x = 0.0
	if "--aim" in OS.get_cmdline_user_args():
		v.ads = 1.0
	await _wait(0.3)
	p.set_process(false); p.set_physics_process(false); v.set_process(false)
	var n := 0
	var dt := 1.0 / 30.0
	v.fire()
	v._kick = 1.0
	while v._cycle_t >= 0.0:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	for i in 4:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.start_rifle_reload(1, 2, false)
	v.le_rounds_in_mag = 0
	while v._reload_t < v.rifle_reload_total():
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.stop_reload()
	print("SEQ %d frames" % n)


## For the grip fitting (art/arms/source/fit): the gun's triangles and one arm's
## skinned vertices and bones, all in the gun-model's space.
func _dump(v: ViewModel, args: PackedStringArray) -> void:
	var side := "L" if "--side=L" in args else "R"
	var to_model := v._le_model.global_transform.affine_inverse()
	var f := FileAccess.open("/tmp/gun_tris.txt", FileAccess.WRITE)
	for m in v._le_model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.get_parent() == v._le_charger or mi.get_parent() == v._le_round or mi.get_parent() == v._le_top:
			continue
		var xf := to_model * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if ix.is_empty():
				ix = PackedInt32Array(range(vs.size()))
			for i in ix.size():
				var q := xf * vs[ix[i]]
				f.store_line("%s %f %f %f" % [mi.name, q.x, q.y, q.z])
	f.close()
	var r: FPArm = v._arms[ViewModel.RIFLE][side]
	var sk := r.skeleton
	var o := FileAccess.open("/tmp/hand_verts.txt", FileAccess.WRITE)
	for m in r.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var skin := mi.skin
		if skin == null:
			continue
		var bind_xf := []
		var bind_bone := []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(b))
			bind_bone.append(bi)
			bind_xf.append(to_model * sk.global_transform * sk.get_bone_global_pose(bi) * skin.get_bind_pose(b))
		for si in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var nn := wts.size() / vs.size()
			for i in vs.size():
				var q := Vector3.ZERO
				var best := 0
				var bw := -1.0
				for k in nn:
					var wt := wts[i * nn + k]
					if wt <= 0.0:
						continue
					var bind: int = bones[i * nn + k]
					q += (bind_xf[bind] as Transform3D) * vs[i] * wt
					if wt > bw:
						bw = wt
						best = bind_bone[bind]
				o.store_line("%s %f %f %f" % [sk.get_bone_name(best), q.x, q.y, q.z])
	o.close()
	var j := FileAccess.open("/tmp/hand_bones.txt", FileAccess.WRITE)
	for b in sk.get_bone_count():
		var rest := sk.get_bone_rest(b)
		var q := rest.basis.get_rotation_quaternion()
		var g := to_model * sk.global_transform * sk.get_bone_global_pose(b)
		j.store_line("%s %d %f %f %f %f %f %f %f %s %s %s %s" % [sk.get_bone_name(b), sk.get_bone_parent(b), q.x, q.y, q.z, q.w, rest.origin.x, rest.origin.y, rest.origin.z,
			var_to_str(g.basis.x).replace(" ", ""), var_to_str(g.basis.y).replace(" ", ""), var_to_str(g.basis.z).replace(" ", ""), var_to_str(g.origin).replace(" ", "")])
	j.close()
	print("DUMP done (%s)" % side)
