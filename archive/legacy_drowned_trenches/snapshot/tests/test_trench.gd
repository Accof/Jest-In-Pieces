extends Node
## The Trench Shotgun (Tripo Winchester 1897, key 8): the model and its textures
## load, it sits shouldered on the right with the rigged arms (right hand on the
## wrist of the stock, left on the pump), fires nine pellets that hurt a lot up
## close and much less far off, kicks hard, works the pump after every shot
## (pump back and forward, hammer re-cocked, a hull thrown out of the port),
## loads shell by shell and can fire part-way through, and leaves the other
## guns alone. --render writes /tmp/trench_*.png; --grip uses /tmp/grip_t.txt.
var render := false
var failed := 0


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
	get_viewport().get_texture().get_image().save_png("/tmp/trench_%s.png" % name_)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


var _player: FpsPlayer


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	_player._unhandled_input(e)


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
		if i == 0:
			c.global_position = Vector3(-0.6, 0, -1.5)       # close: 3 m from the player
		elif i == 1:
			c.global_position = Vector3(0.6, 0, -7.5)        # far: 9 m
		else:
			c.global_position = Vector3(7, 0, -9 - i)
		c.rotation.y = 0.0
	p.global_position = Vector3(0, 0.05, 1.5)
	p.rotation.y = 0.0
	await _frames(30)

	# --- the others as they were
	var pw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.PISTOL]
	_check(pw.name == "Pistol" and pw.damage == 34.0 and pw.mag == 17 and not pw.has("shells"), "pistol unchanged")
	var rw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.REVOLVER]
	_check(rw.name == "Revolver" and rw.damage == 80.0 and rw.mag == 6 and rw.pull == 0.12, "revolver unchanged")
	_check(v._arms.has(ViewModel.REVOLVER) and not v._arms.has(ViewModel.PISTOL), "the revolver keeps its arms; the pistol its own hands")
	var tw: Dictionary = FpsPlayer.WEAPONS[FpsPlayer.TRENCH]
	_check(tw.name == "Trench Shotgun" and tw.mag == 6 and tw.pellets > 1 and tw.shells and tw.pump, "Trench Shotgun: six shells, %d pellets, shell by shell, pump" % tw.pellets)
	_check(p.ammo.size() == FpsPlayer.WEAPONS.size() and p.ammo[FpsPlayer.TRENCH] == 6, "it starts full (6)")

	# --- 8 selects it
	_key(KEY_8)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.TRENCH and v.weapon == ViewModel.TRENCH, "8 selects the trench gun")
	var shown := 0
	for gi in v._guns.size():
		shown += int(v._guns[gi].visible)
	_check(shown == 1 and v._guns[ViewModel.TRENCH].visible, "only the trench gun is shown")
	if "--grip" in OS.get_cmdline_user_args() and FileAccess.file_exists("/tmp/grip_t.txt"):
		v.apply_grip(ViewModel.TRENCH, str_to_var(FileAccess.get_file_as_string("/tmp/grip_t.txt")), v._sg_model)
		print("      grip from /tmp/grip_t.txt")
	if "--seq" in OS.get_cmdline_user_args():
		await _seq_mode(p, v)
		get_tree().quit()
		return
	if "--frames" in OS.get_cmdline_user_args():
		await _frames_mode(p, v)
		get_tree().quit()
		return
	if "--dump" in OS.get_cmdline_user_args():
		_dump(v, OS.get_cmdline_user_args())
		get_tree().quit()
		return
	# model, parts, textures
	var names := {}
	var tex_ok := false
	for mi: MeshInstance3D in v._sg_model.find_children("*", "MeshInstance3D", true, false):
		names[String(mi.name)] = true
		if String(mi.name) == "Body":
			var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
			tex_ok = m != null and m.albedo_texture != null and m.normal_texture != null and m.metallic_texture != null
	_check(names.has("Body") and names.has("Pump") and names.has("Hammer"), "the model is in parts: body, pump, hammer")
	_check(tex_ok, "the body keeps the Tripo colour, normal and metal/rough textures")
	var arms: Dictionary = v._arms.get(ViewModel.TRENCH, {})
	_check(arms.has("R") and arms.has("L"), "the rigged arms hold it (right and left)")
	# placement
	var cam := p.camera
	var muzzle_cam := cam.to_local(v._sg_muzzle.global_position)
	var dir := cam.global_basis.inverse() * (v._sg_model.global_basis * Vector3.RIGHT).normalized()
	print("      muzzle in camera space %s, barrel direction %s" % [muzzle_cam, dir])
	_check(muzzle_cam.x > 0.0 and muzzle_cam.y < 0.0 and muzzle_cam.z < -0.15, "shouldered low on the right, the muzzle well out in front")
	_check(dir.dot(Vector3.FORWARD) > 0.99, "the barrel points where the player looks")
	await _shot("0_idle")

	# --- a shot at the near clown, then at the far one
	var near: Clown = clowns[0]
	var far: Clown = clowns[1]
	cam.look_at(near.ragdoll.bones[&"Chest"].global_position)
	var pitch0 := cam.rotation.x
	var h0 := near.health
	var r: FPArm = arms["R"]
	var l: FPArm = arms["L"]
	var rel0 := v._sg_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
	var lhome := l.position
	p.fire()
	var kicked := v._kick
	var flash_ok := v._flash_mesh.visible and v._flash_mesh.global_position.distance_to(v._sg_muzzle.global_position) < 0.003
	if render:
		v._since_shot = -20.0
		v._flash.light_energy = 11.0
		v._flash_mesh.visible = true
		await _shot("1_fired")
		v._since_shot = 0.0
	_check(p.ammo[FpsPlayer.TRENCH] == 5, "one shell fired (5 left)")
	_timed(flash_ok, "the flash is at its muzzle")
	_timed(kicked > 0.9, "it kicks back into the shoulder")
	# the pump stroke: watch it
	var max_s := 0.0
	var hammer_down := 0.0
	var left_moved := 0.0
	var hand_worst := 0.0
	var hulls0 := v.sg_hulls.size()
	var climbed := 0.0
	var t := 0.0
	var fired_again := false
	var pump_start := -1.0
	var shot_pump := false
	while t < 0.9:
		await get_tree().process_frame
		t += get_process_delta_time()
		max_s = maxf(max_s, v._sg_pump_s)
		if v._sg_pump_s > 0.02 and pump_start < 0.0:
			pump_start = t
		if t < 0.1:
			hammer_down = minf(hammer_down, rad_to_deg(v._sg_hammer.rotation.z))
		left_moved = maxf(left_moved, l.position.distance_to(lhome))
		climbed = maxf(climbed, cam.rotation.x - pitch0)
		var rel := v._sg_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
		hand_worst = maxf(hand_worst, rel.origin.distance_to(rel0.origin))
		if v._sg_pump_s > 0.5 and not shot_pump and render:
			shot_pump = true
			v.set_process(false)
			await _shot("2_pump")
			v.set_process(true)
		if t > 0.3 and t < 0.4 and not fired_again:
			fired_again = true
			p.fire()                                   # mid-stroke: must not fire
	await _frames(10)
	var near_dmg := h0 - near.health if not near.dead else h0
	print("      near clown: %.0f damage%s" % [near_dmg, " (killed)" if near.dead else ""])
	_check(near_dmg > 60.0 or near.dead, "up close it hits very hard (%.0f)" % near_dmg)
	_timed(max_s > 0.98, "the pump comes right back after the shot (%.2f)" % max_s)
	_timed(pump_start > 0.25, "and only once the kick has settled (starts %.2f s after the shot)" % pump_start)
	_check(ViewModel.T_PUMP_TRAVEL > 0.06, "a full stroke (%.1f cm)" % (ViewModel.T_PUMP_TRAVEL * 100.0))
	_check(v._sg_pump_s < 0.01 and v._sg_pump.position.distance_to(v._sg_pump_rest) < 0.0005, "and goes forward again")
	_timed(hammer_down < -15.0, "the hammer falls on the shot (%.0f deg)" % hammer_down)
	_check(absf(v._sg_hammer.rotation.z) < 0.01, "and the pump cocks it again")
	_timed(v.sg_hulls.size() == hulls0 + 1, "one spent hull thrown out")
	_timed(left_moved > 0.02, "the left hand rides the pump (%.3f)" % left_moved)
	_check(hand_worst < 0.001, "the right hand stays on the stock through the kick (moved %.5f)" % hand_worst)
	_timed(climbed > deg_to_rad(2.5), "the view kicks up hard (%.1f deg)" % rad_to_deg(climbed))
	_check(p.ammo[FpsPlayer.TRENCH] == 5, "no second shot while the pump is being worked")
	if v.sg_hulls.size() > 0:
		await _wait(1.0)
		var hull := v.sg_hulls[-1]
		print("      hull at %s (player at %s)" % [hull.global_position, p.global_position])
		_check(is_instance_valid(hull) and hull.global_position.y < 0.3 and hull.global_position.distance_to(p.global_position) < 4.0, "the hull lands on the floor nearby")
	# far: much less per pellet
	await _wait(0.3)
	cam.look_at(far.ragdoll.bones[&"Chest"].global_position)
	var hf := far.health
	p.fire()
	await _frames(12)
	var far_dmg := hf - far.health if not far.dead else hf
	print("      far clown (9 m): %.0f damage" % far_dmg)
	_check(far_dmg > 0.0 and far_dmg < near_dmg * 0.6, "at 9 m it still hits but does far less (%.0f vs %.0f up close)" % [far_dmg, near_dmg])
	# the falloff itself, per pellet, as the game works it out
	var per := func(d: float) -> float: return clampf(1.0 - maxf(d - tw.falloff * 0.4, 0.0) / tw.falloff, 0.2, 1.0) * tw.damage
	print("      per pellet: %.1f at 2 m, %.1f at 6 m, %.1f at 9 m, %.1f at 15 m" % [per.call(2.0), per.call(6.0), per.call(9.0), per.call(15.0)])
	_check(per.call(15.0) <= per.call(2.0) * 0.25, "falloff: a pellet at 15 m does a fifth of what it does at 2 m")
	await _wait(1.0)

	# --- shell-by-shell reload, interrupted by a shot
	cam.rotation.x = 0.0
	cam.look_at(cam.global_position + Vector3(-0.3, -0.05, -1.0))
	await _wait(1.0)
	p.fire()                                           # down to 2 or 3, room to load
	await _wait(1.0)
	var a0 := p.ammo[FpsPlayer.TRENCH]
	p.reload()
	_check(v.reloading(), "R starts loading (%d in)" % a0)
	var steps: Array[float] = []
	var last := a0
	var tt := 0.0
	var shot_loading := false
	var shell_seen := 0
	var pinch_worst := 0.0
	var home_gap := 9.0
	var left_off := 0.0
	while tt < v.shell_intro() + v.shell_time() * 1.9:
		await get_tree().process_frame
		tt += get_process_delta_time()
		if v._sg_load_shell and v._sg_load_shell.visible:
			shell_seen += 1
			var arm_l: FPArm = v._arms[ViewModel.TRENCH]["L"]
			var sk := arm_l.skeleton
			var tipf := func(bn: String) -> Vector3:
				var bi := sk.find_bone(bn)
				return sk.global_transform * sk.get_bone_global_pose(bi) * Vector3(0, sk.get_bone_rest(bi).origin.length() * 0.85, 0)
			var mid: Vector3 = ((tipf.call("index_03.L") as Vector3) + (tipf.call("thumb_03.L") as Vector3)) * 0.5
			var base := v._sg_load_shell.global_transform * Vector3(-ViewModel.T_SHELL_BASE, 0, 0)
			pinch_worst = maxf(pinch_worst, mid.distance_to(base) * 100.0 / ViewModel.SHRINK)
			var bm := v._sg_model.global_transform.affine_inverse() * base
			home_gap = minf(home_gap, bm.distance_to(ViewModel.T_SHELL_HOME))
		left_off = maxf(left_off, l.position.distance_to(lhome))
		var now := p.ammo[FpsPlayer.TRENCH]
		if now != last:
			steps.append(float(now - last))
			last = now
		if render and not shot_loading and tt > v.shell_intro() + v.shell_time() * 0.55:
			shot_loading = true
			v.set_process(false)
			await _shot("3_loading")
			v.set_process(true)
	var a1 := p.ammo[FpsPlayer.TRENCH]
	print("      shells went in one by one: %s (%d -> %d)" % [steps, a0, a1])
	_timed(steps.size() >= 1 and steps.max() == 1.0 and a1 < 6, "one shell at a time (%d -> %d)" % [a0, a1])
	_check(left_off > 0.1, "the left hand leaves the pump to load")
	_check(shell_seen > 5, "a shell is seen going in (%d frames)" % shell_seen)
	_check(pinch_worst < 1.5, "held by its base between thumb and index (worst %.1f cm)" % pinch_worst)
	_check(home_gap < 0.005, "and pushed up through the loading port and forward into the tube (%.1f mm from home)" % (home_gap * 1000.0))
	p.fire()
	await _frames(3)
	_check(not v.reloading() and p.ammo[FpsPlayer.TRENCH] == a1 - 1, "a shot breaks off the loading and goes")
	_check(v._sg_load_shell == null or not v._sg_load_shell.visible, "no shell left hanging when the shot breaks off the loading")
	await _wait(1.0)
	_check(l.position.distance_to(lhome) < 0.002, "the left hand is back on the pump")
	p.reload()
	await _wait(v.shell_intro() + v.shell_time() * 7)
	_timed(p.ammo[FpsPlayer.TRENCH] == 6 and not v.reloading(), "loads up to six and stops (%d)" % p.ammo[FpsPlayer.TRENCH])

	# --- switching
	_key(KEY_1)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.PISTOL and not v._guns[ViewModel.TRENCH].visible and v._guns[ViewModel.PISTOL].visible, "1: the pistol, the trench gun put away")
	_key(KEY_7)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.REVOLVER and v._guns[ViewModel.REVOLVER].visible and v._rev_model != null, "7: the revolver")
	await _shot("4_revolver")
	_key(KEY_8)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.TRENCH and r.is_visible_in_tree() and l.is_visible_in_tree(), "8: back to the trench gun, arms and all")
	_key(KEY_2)
	await _wait(ViewModel.SWAP_TIME + 0.15)
	_check(p.weapon == FpsPlayer.SHOTGUN and p.ammo[FpsPlayer.SHOTGUN] == 6, "2: the old shotgun is still there, its own ammunition")

	if render:
		_key(KEY_8)
		await _wait(ViewModel.SWAP_TIME + 0.3)
		p.set_process(false); p.set_physics_process(false); v.set_process(false)
		var oc := Camera3D.new(); add_child(oc)
		oc.projection = Camera3D.PROJECTION_ORTHOGONAL
		var g := v._sg_model.global_transform
		for k: Array in [["right", Vector3(0, 0, 1), Vector3(-0.02, 0.10, 0), 1.15], ["left", Vector3(0, 0, -1), Vector3(-0.02, 0.10, 0), 1.15],
				["rhand", Vector3(0, 0.2, 1), Vector3(-0.21, 0.10, 0), 0.30], ["rhand_l", Vector3(0, 0.2, -1), Vector3(-0.21, 0.10, 0), 0.30],
				["lhand", Vector3(0, -0.4, -1), Vector3(0.20, 0.11, 0), 0.30], ["lhand_r", Vector3(0, -0.3, 1), Vector3(0.20, 0.11, 0), 0.30],
				["shield", Vector3(0.1, 0.6, 1), Vector3(0.24, 0.15, 0), 0.32]]:
			var dir_: Vector3 = (g.basis * k[1]).normalized()
			var centre: Vector3 = g * k[2]
			oc.size = float(k[3]) * ViewModel.SHRINK
			oc.global_position = centre + dir_ * 0.8
			oc.look_at(centre, g.basis.y.normalized())
			oc.near = 0.005
			oc.make_current()
			await _shot("out_" + String(k[0]))
	print("TRENCH: %d failed" % failed)
	get_tree().quit()


## For the grip fitting (art/arms/source/fit): the gun's triangles and one arm's
## skinned vertices and bones, all in gun-model space. --side=L or R.
func _dump(v: ViewModel, args: PackedStringArray) -> void:
	var side := "L" if "--side=L" in args else "R"
	var to_model := v._sg_model.global_transform.affine_inverse()
	var f := FileAccess.open("/tmp/gun_tris.txt", FileAccess.WRITE)
	for m in v._sg_model.find_children("*", "MeshInstance3D", true, false):
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
	var r: FPArm = v._arms[ViewModel.TRENCH][side]
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


## Frozen moments for checking the animation: the pump after a shot
## (/tmp/trench_pump_<ms>_*.png) and the loading (/tmp/trench_load_<ms>_*.png),
## first person and from outside on the left.
func _frames_mode(p: FpsPlayer, v: ViewModel) -> void:
	p.camera.rotation.x = 0.0
	await _wait(0.3)
	p.set_process(false); p.set_physics_process(false); v.set_process(false)
	var oc := Camera3D.new()
	add_child(oc)
	oc.projection = Camera3D.PROJECTION_ORTHOGONAL
	oc.size = 0.75 * ViewModel.SHRINK
	oc.near = 0.005
	var shoot := func(tag: String) -> void:
		pass
	for ts in [0.0, 0.3, 0.4, 0.55]:
		v._sg_cocked = false
		v._sg_ejected = true
		v._since_shot = ts
		v._kick = maxf(0.0, 1.0 - ts * 2.6)
		v.animate(0.0, 0.0, Vector2.ZERO)
		await _frame_shots(p, v, oc, "pump_%04d" % int(ts * 1000))
	v._since_shot = 9.0
	v._kick = 0.0
	v.start_reload()
	var T := v.shell_intro()
	var S := v.shell_time()
	for c in [-1.0, 0.1, 0.4, 0.55, 0.7, 0.8, 0.95]:
		v._reload_t = T * 0.9 if c < 0.0 else T + S * c
		v._sg_load = 1.0
		v.animate(0.0, 0.0, Vector2.ZERO)
		await _frame_shots(p, v, oc, "load_%04d" % int(maxf(c, 0.0) * 1000 if c >= 0.0 else 9999))
	print("FRAMES done")


func _frame_shots(p: FpsPlayer, v: ViewModel, oc: Camera3D, tag: String) -> void:
	p.camera.make_current()
	await _shot(tag + "_fp")
	var g := v._sg_model.global_transform
	var centre := g * Vector3(-0.02, 0.10, 0.0)
	var d := (g.basis * Vector3(0.1, -0.35, -1.0)).normalized()
	oc.global_position = centre + d * 0.8
	oc.look_at(centre, g.basis.y.normalized())
	oc.make_current()
	await _shot(tag + "_left")


## A shot, the pump, then loading two shells and back to the pump, stepped at
## 30 frames a second of game time: /tmp/trench_seq_<n>.png (first person).
func _seq_mode(p: FpsPlayer, v: ViewModel) -> void:
	p.camera.rotation.x = 0.0
	await _wait(0.3)
	p.set_process(false); p.set_physics_process(false); v.set_process(false)
	var n := 0
	var dt := 1.0 / 30.0
	v.fire()
	for i in 27:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.start_reload()
	while v._reload_t < v.shell_intro() + v.shell_time() * 2.0:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	v.stop_reload()
	for i in 10:
		v.animate(dt, 0.0, Vector2.ZERO)
		await _shot("seq_%03d" % n)
		n += 1
	print("SEQ %d frames" % n)

