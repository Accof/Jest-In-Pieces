extends Node
## The MP 18 (Tripo Bergmann MP 18/I, key 9): model and textures, shouldered with
## the rigged arms, fully automatic at an exact 500 rounds a minute while the
## trigger is held, stopping when let go or empty (a dry click), recoil that builds
## through a burst and settles, the side drum changed by hand (out sideways, a
## full one in), damage, switching, and the other guns as they were.
## --render: /tmp/mp18_*.png; --grip: /tmp/grip_m.txt; --dump --side=R|L: fitting;
## --seq: a stepped burst and reload at 30 fps (/tmp/mp18_seq_*.png).
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
	get_viewport().get_texture().get_image().save_png("/tmp/mp18_%s.png" % name_)


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


## Hold the trigger for `ticks` physics ticks (what the held button does each tick).
## Returns the physics tick of every shot.
func _hold(p: FpsPlayer, ticks: int) -> Array[int]:
	var shots: Array[int] = []
	for i in ticks:
		var before := p.ammo[FpsPlayer.MP18]
		p.fire()
		if p.ammo[FpsPlayer.MP18] < before:
			shots.append(i)
		await get_tree().physics_frame
	return shots


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
	var clowns: Array[Clown] = []
	for c: Clown in room.clowns:
		clowns.append(c)
	for i in clowns.size():
		var c := clowns[i]
		c.global_position = Vector3(-0.5 + i * 1.0, 0, -3.5) if i < 2 else Vector3(7, 0, -9 - i)
		c.rotation.y = 0.0
	p.global_position = Vector3(0, 0.05, 1.5)
	p.rotation.y = 0.0
	await _frames(30)

	var pw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	_check(pw.name == "Pistol" and pw.damage == 34.0 and pw.mag == 17 and not pw.has("rpm"), "pistol unchanged")
	var rw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.REVOLVER]
	_check(rw.name == "Revolver" and rw.damage == 80.0 and rw.mag == 6, "revolver unchanged")
	var tw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.TRENCH]
	_check(tw.name == "Trench Shotgun" and tw.mag == 6 and tw.pump, "trench shotgun unchanged")
	var sw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.SMG]
	_check(sw.name == "SMG" and sw.cooldown == 0.085 and sw.mag == 32 and not sw.has("rpm"), "the old SMG unchanged")
	var mw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.MP18]
	_check(mw.name == "MP 18" and mw.mag == 32 and mw.rpm == 500.0 and mw.damage < rw.damage and not mw.get("semi", false), "MP 18: 32 rounds, 500 rpm, automatic, less per round than the Webley (%.0f vs %.0f)" % [mw.damage, rw.damage])
	_check(p.ammo.size() == FpsPlayer.WEAPONS.size() and p.ammo[FpsPlayer.MP18] == 32, "its own ammunition, full (32)")

	_key(KEY_9)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.MP18 and v.weapon == ViewModel.MP18, "9 selects the MP 18")
	var shown := 0
	for gi in v._guns.size():
		shown += int(v._guns[gi].visible)
	_check(shown == 1 and v._guns[ViewModel.MP18].visible, "only the MP 18 is shown")
	if "--grip" in OS.get_cmdline_user_args() and FileAccess.file_exists("/tmp/grip_m.txt"):
		v.apply_grip(ViewModel.MP18, str_to_var(FileAccess.get_file_as_string("/tmp/grip_m.txt")), v._mp_model)
		print("      grip from /tmp/grip_m.txt")
	if "--dump" in OS.get_cmdline_user_args():
		_dump(v, OS.get_cmdline_user_args())
		get_tree().quit()
		return
	if "--seq" in OS.get_cmdline_user_args():
		await _seq_mode(p, v)
		get_tree().quit()
		return
	var names := {}
	var tex_ok := false
	for mi: MeshInstance3D in v._mp_model.find_children("*", "MeshInstance3D", true, false):
		names[String(mi.name)] = true
		if String(mi.name) == "Body":
			var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
			tex_ok = m != null and m.albedo_texture != null and m.normal_texture != null and m.metallic_texture != null
	_check(names.has("Body") and names.has("Drum"), "the model is in parts: body and the drum")
	_check(tex_ok, "the body keeps the Tripo colour, normal and metal/rough textures")
	var arms: Dictionary = v._arms.get(ViewModel.MP18, {})
	_check(arms.has("R") and arms.has("L"), "the rigged arms hold it (right and left)")
	var cam := p.camera
	var muzzle_cam := cam.to_local(v._mp_muzzle.global_position)
	var dir := cam.global_basis.inverse() * (v._mp_model.global_basis * Vector3.RIGHT).normalized()
	print("      muzzle in camera space %s, barrel direction %s" % [muzzle_cam, dir])
	_check(muzzle_cam.x > 0.0 and muzzle_cam.y < 0.0 and muzzle_cam.z < -0.15, "shouldered low on the right, the muzzle out in front")
	_check(dir.dot(Vector3.FORWARD) > 0.99, "the barrel points where the player looks")
	await _shot("0_idle")

	# --- automatic fire at an exact rate
	var target: Clown = clowns[0]
	cam.look_at(target.ragdoll.bones[&"Chest"].global_position)
	var pitch0 := cam.rotation.x
	var h0 := target.health
	var r: FPArm = arms["R"]
	var rel0 := v._mp_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
	var ticks := 150                                  # 2.5 s of physics
	_pitch0 = cam.rotation.x
	var shots := await _hold_measured(p, v, r, rel0, ticks)
	var tick_s := 1.0 / Engine.physics_ticks_per_second
	var n: int = shots.size()
	var gaps: Array[float] = []
	for i in range(1, n):
		gaps.append((shots[i] - shots[i - 1]) * tick_s)
	var rate := (n - 1) / ((shots[-1] - shots[0]) * tick_s) * 60.0 if n > 1 else 0.0
	print("      %d shots in %.2f s held: %.0f rounds a minute; shortest gap %.3f s" % [n, ticks * tick_s, rate, gaps.min() if gaps else 0.0])
	_timed(n >= 19 and n <= 22 and absf(rate - 500.0) < 15.0, "fires continuously while held, at about 500 rounds a minute (%.0f)" % rate)
	_timed(gaps.min() >= 0.12 - tick_s * 0.5, "never faster than the set rate (shortest %.3f s)" % gaps.min())
	_check(_hold_worst < 0.001, "the right hand stays on the gun through the burst (moved %.5f)" % _hold_worst)
	_timed(_climb_late > _climb_early * 1.5 and _climb_late < 12.0, "recoil builds through the burst (the view %.1f deg up after 3 rounds, %.1f by the end)" % [_climb_early, _climb_late])
	var after := p.ammo[FpsPlayer.MP18]
	await _frames(30)
	_check(p.ammo[FpsPlayer.MP18] == after, "letting go stops it at once")
	await _wait(1.0)
	_check(absf(cam.rotation.x - pitch0) < deg_to_rad(1.5), "and the muzzle comes back down (%.2f deg off)" % rad_to_deg(cam.rotation.x - pitch0))
	await _frames(10)
	var dmg := h0 - target.health if not target.dead else h0
	_check(dmg > 0.0, "the rounds hurt the clown (%.0f%s)" % [dmg, ", killed" if target.dead else ""])
	_check(get_tree().get_nodes_in_group("spent_brass").size() > 5, "spent cases thrown out")

	# --- empty: no shots, a dry click, the drum changed
	cam.rotation.x = 0.0
	cam.look_at(cam.global_position + Vector3(0, 0, -1))
	p.ammo[FpsPlayer.MP18] = 0
	p.ammo_changed.emit()
	var dry := await _hold(p, 6)
	_check(dry.is_empty() and p.ammo[FpsPlayer.MP18] == 0, "an empty drum fires nothing")
	_check(v.reloading(), "and the drum change starts")
	var l: FPArm = arms["L"]
	var drums0 := v.mp_drums.size()
	var drum_moved := 0.0
	var l_on_drum := 0
	var fired_in_reload := false
	var t := 0.0
	var shot_out := false
	var shot_in := false
	while v.reloading() and t < 4.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		var rt := v._reload_t
		if rt > 0.5 and rt < 0.95:
			drum_moved = maxf(drum_moved, v._mp_drum.transform.origin.distance_to(v._mp_drum_rest.origin))
		if rt > 0.62 and rt < 0.95:
			var hd := v._mp_model.global_transform.affine_inverse() * (l.skeleton.global_transform * l.skeleton.get_bone_global_pose(l._hand))
			var want := v._mp_drum.transform * v._mp_drum_hand
			if hd.origin.distance_to(want.origin) < 0.002:
				l_on_drum += 1
			if render and not shot_out and rt > 0.85:
				shot_out = true
				v.set_process(false); await _shot("2_drum_out"); v.set_process(true)
		if rt > 1.8 and rt < 2.3 and render and not shot_in:
			shot_in = true
			v.set_process(false); await _shot("3_drum_in"); v.set_process(true)
		if rt > 1.0 and rt < 2.0 and not fired_in_reload:
			fired_in_reload = true
			var b := p.ammo[FpsPlayer.MP18]
			p.fire()
			_check(p.ammo[FpsPlayer.MP18] == b, "no firing while the drum is off")
	_timed(drum_moved > 0.1, "the drum is drawn out sideways (%.0f cm)" % (drum_moved * 100.0))
	_timed(l_on_drum > 3, "the left hand holds the drum while it comes out (%d frames)" % l_on_drum)
	_timed(v.mp_drums.size() == drums0 + 1, "the empty drum drops off as a body")
	_check(p.ammo[FpsPlayer.MP18] == 32, "a full drum: 32 rounds")
	await _frames(5)
	_check(v._mp_drum.visible and v._mp_drum.transform.origin.distance_to(v._mp_drum_rest.origin) < 0.0005, "the new drum sits home on the housing")
	await _wait(0.3)
	var lh := v._mp_model.global_transform.affine_inverse() * (l.skeleton.global_transform * l.skeleton.get_bone_global_pose(l._hand))
	var g: Dictionary = ViewModel.ARM_GRIPS[ViewModel.MP18]["L"]
	var lwant := l.frame_from_knuckles(g.index_k, g.little_k, g.palm)
	_check(lh.origin.distance_to(lwant.origin) < 0.002, "the left hand is back on the wood")
	var dropped := v.mp_drums[-1]
	_check(is_instance_valid(dropped) and dropped.global_position.y < 0.4, "the empty drum is on the floor")

	# --- switching
	_key(KEY_7)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.REVOLVER and v._guns[ViewModel.REVOLVER].visible and not v._guns[ViewModel.MP18].visible, "7: the revolver")
	_key(KEY_8)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.TRENCH and v._guns[ViewModel.TRENCH].visible, "8: the trench gun")
	_key(KEY_1)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.PISTOL and v._guns[ViewModel.PISTOL].visible, "1: the pistol")
	_key(KEY_3)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.SMG and v._guns[ViewModel.SMG].visible, "3: the old SMG")
	_key(KEY_9)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.MP18 and r.is_visible_in_tree() and l.is_visible_in_tree() and p.ammo[FpsPlayer.MP18] == 32, "9: back to the MP 18, arms and its 32 rounds")
	if render:
		p.set_process(false); p.set_physics_process(false); v.set_process(false)
		var oc := Camera3D.new(); add_child(oc)
		oc.projection = Camera3D.PROJECTION_ORTHOGONAL
		var gx := v._mp_model.global_transform
		for k: Array in [["right", Vector3(0, 0, 1), Vector3(0.0, 0.09, 0), 0.9], ["left", Vector3(0, 0, -1), Vector3(0.0, 0.09, 0), 0.9],
				["rhand", Vector3(0, 0.2, 1), Vector3(-0.17, 0.09, 0), 0.25], ["rhand_l", Vector3(0, 0.2, -1), Vector3(-0.17, 0.09, 0), 0.25],
				["lhand", Vector3(0, -0.4, -1), Vector3(-0.03, 0.09, 0), 0.25], ["lhand_r", Vector3(0, -0.3, 1), Vector3(-0.03, 0.09, 0), 0.25]]:
			var d_: Vector3 = (gx.basis * k[1]).normalized()
			var centre: Vector3 = gx * k[2]
			oc.size = float(k[3]) * ViewModel.SHRINK
			oc.global_position = centre + d_ * 0.8
			oc.look_at(centre, gx.basis.y.normalized())
			oc.near = 0.005
			oc.make_current()
			await _shot("out_" + String(k[0]))
	print("MP18: %d failed" % failed)
	get_tree().quit()


var _hold_worst := 0.0
var _climb_early := 0.0
var _climb_late := 0.0
var _pitch0 := 0.0


## Hold, and watch the hand on the gun and how much each shot lifts the muzzle
## (the pitch rise over the 3 ticks after a shot, early shots against late ones).
func _hold_measured(p: FpsPlayer, v: ViewModel, r: FPArm, rel0: Transform3D, ticks: int) -> Array[int]:
	var shots: Array[int] = []
	var rises: Array[float] = []
	var last_pitch := p.camera.rotation.x
	var shot_fire := false
	for i in ticks:
		var before := p.ammo[FpsPlayer.MP18]
		var pitch_before := p.camera.rotation.x
		p.fire()
		if p.ammo[FpsPlayer.MP18] < before:
			shots.append(i)
		await get_tree().physics_frame
		await get_tree().process_frame
		if not shots.is_empty() and shots[-1] == i:
			rises.append(rad_to_deg(p.camera.rotation.x - _pitch0))   # how far the view has climbed by this shot
		var rel := v._mp_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
		_hold_worst = maxf(_hold_worst, rel.origin.distance_to(rel0.origin))
		if render and not shot_fire and shots.size() == 6:
			shot_fire = true
			v.set_process(false)
			v._flash_mesh.visible = true
			await _shot("1_firing")
			v.set_process(true)
	if rises.size() >= 8:
		_climb_early = rises[2]
		_climb_late = rises.slice(rises.size() - 4).reduce(func(a: float, b: float) -> float: return a + b) / 4.0
	return shots


## A burst, then a drum change, stepped at 30 fps of game time.
func _seq_mode(p: FpsPlayer, v: ViewModel) -> void:
	p.camera.rotation.x = 0.0
	await _wait(0.3)
	p.set_process(false); p.set_physics_process(false); v.set_process(false)
	var n := 0
	var dt := 1.0 / 30.0
	for i in 24:
		if i < 14 and i % 4 == 0:
			v.fire()
			v._kick = 1.0
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.start_reload()
	while v._reload_t < ViewModel.MP18_RELOAD:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.stop_reload()
	for i in 6:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	print("SEQ %d frames" % n)


## For the grip fitting (art/arms/source/fit): the gun's triangles and one arm's
## skinned vertices and bones, all in gun-model space. --side=L or R.
func _dump(v: ViewModel, args: PackedStringArray) -> void:
	var side := "L" if "--side=L" in args else "R"
	var to_model := v._mp_model.global_transform.affine_inverse()
	var f := FileAccess.open("/tmp/gun_tris.txt", FileAccess.WRITE)
	for m in v._mp_model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
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
	var r: FPArm = v._arms[ViewModel.MP18][side]
	var sk := r.skeleton
	var o := FileAccess.open("/tmp/hand_verts.txt", FileAccess.WRITE)
	for m in r.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var skin := mi.skin
		if skin == null:
			continue                               # the shell in the hand, not the arm
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
			var n := wts.size() / vs.size()
			for i in vs.size():
				var q := Vector3.ZERO
				var best := 0
				var bw := -1.0
				for k in n:
					var w := wts[i * n + k]
					if w <= 0.0:
						continue
					var bind: int = bones[i * n + k]
					q += (bind_xf[bind] as Transform3D) * vs[i] * w
					if w > bw:
						bw = w
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


