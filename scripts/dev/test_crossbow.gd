extends Node
## The crossbow (the old stake gun's slot) and its bolts, in the gore sandbox:
## headshots, torso, arm and leg hits, no wall and a wall close behind,
## living and dead pins, struggling free, several bolts in one body, several
## pinned bodies, death after being pinned, the cap on loose bolts, and the
## weapon itself (fire, span and load, switching away and back).
## Pass --render for images in /tmp/xbow_*.png.
var render := false
var failed := 0
var room: Node3D


func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	seed(1918)
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		failed += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _shot(name: String, at: Vector3 = Vector3.INF, from: Vector3 = Vector3.INF) -> void:
	if not render:
		return
	var cam: Camera3D = null
	if at != Vector3.INF:
		cam = Camera3D.new()
		room.add_child(cam)
		cam.global_position = from
		cam.look_at(at)
		cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/xbow_%s.png" % name)
	if cam:
		cam.queue_free()
		(room.player as FpsPlayer).camera.make_current()


## A clown standing at `pos`, facing +Z (toward the player's end of the room).
func _clown(pos: Vector3) -> Clown:
	var c := Clown.new()
	room.add_child(c)
	c.global_position = pos
	room.clowns.append(c)
	return c


func _bone_pos(c: Clown, b: StringName) -> Vector3:
	return (c.ragdoll.bones[b] as PhysicalBone3D).global_position


## Loose a bolt from 3 m in front of `c` straight at bone `b` (+ `off`).
func _fire_at(c: Clown, b: StringName, off := Vector3.ZERO) -> CrossbowBolt:
	var to := _bone_pos(c, b) + off
	var from := to + Vector3(0, 0.05, 3.0)
	return CrossbowBolt.launch(room, from, to - from, randi())


var fastest := &""


func _max_speed(c: Clown) -> float:
	var m := 0.0
	for pb: PhysicalBone3D in c.ragdoll.bones.values():
		if pb.linear_velocity.length() > m:
			m = pb.linear_velocity.length()
			fastest = StringName(pb.bone_name)
	return m


func _run() -> void:
	if "--dump" in OS.get_cmdline_user_args() or "--fp" in OS.get_cmdline_user_args():
		await _view_modes()
		get_tree().quit()
		return
	room = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	var p: FpsPlayer = room.player
	p.god_mode = true
	await _frames(5)
	var wall_z := -9.25

	print("== in the open (no wall within reach)")
	# torso: hurt, not dead, the bolt stays in, nobody is thrown about
	var a := _clown(Vector3(-3.0, 0, -3.0))
	await _frames(10)
	var hips0 := a.global_position
	var bolt_a := _fire_at(a, &"Chest")
	await _wait(0.5)
	_check(not a.dead and a.health < a.max_health and a.health > 0.0, "torso: hurt (%.0f/%.0f), alive" % [a.health, a.max_health])
	_check(bolt_a.state == "in_body" and bolt_a.get_parent() is BoneAttachment3D, "torso: the bolt stays in, on the chest (%s)" % bolt_a.state)
	_check(a.global_position.distance_to(hips0) < 0.05 and not a.pinned, "torso: not moved, not pinned")
	await _shot("1_torso", _bone_pos(a, &"Chest"), _bone_pos(a, &"Chest") + Vector3(0.9, 0.2, 1.2))
	# a second and third bolt into the same body: they all stay
	var bolt_a2 := _fire_at(a, &"Spine", Vector3(0.06, 0, 0))
	await _wait(0.4)
	var bolt_a3 := _fire_at(a, &"Chest", Vector3(-0.07, 0.05, 0))
	await _wait(0.6)
	var in_a := 0
	for bb: CrossbowBolt in [bolt_a, bolt_a2, bolt_a3]:
		if is_instance_valid(bb) and bb.state == "in_body":
			in_a += 1
	_check(in_a == 3, "three bolts in one body, all still in it (%d), dead now: %s" % [in_a, a.dead])
	await _wait(1.5)
	var in_corpse := 0
	for bb: CrossbowBolt in [bolt_a, bolt_a2, bolt_a3]:
		if is_instance_valid(bb) and bb.global_position.distance_to(_bone_pos(a, bb.bone)) < 0.4:
			in_corpse += 1
	_check(in_corpse == 3, "and they go down with the body (%d within 0.4 m of their bones)" % in_corpse)
	await _shot("2_three_bolts", _bone_pos(a, &"Chest"), _bone_pos(a, &"Chest") + Vector3(1.0, 0.8, 1.0))

	# headshot: dead, the bolt in the head, the body falls where it stood
	var h := _clown(Vector3(-1.5, 0, -3.0))
	await _frames(10)
	var h_hips0 := _bone_pos(h, &"Hips")
	var bolt_h := _fire_at(h, &"Neck", Vector3(0, 0.06, 0))
	# a launch shows at once: fast bones and the hips gone in the first moment
	# (the headshot deaths that follow may stumble a step or two: that is theirs)
	var peak := 0.0
	var t_hit := -1.0
	var early := 0.0
	var tt := 0.0
	while tt < 1.6:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		if h.dead and t_hit < 0.0:
			t_hit = tt
		if t_hit >= 0.0 and tt - t_hit < 0.25:
			early = maxf(early, Vector2(_bone_pos(h, &"Hips").x - h_hips0.x, _bone_pos(h, &"Hips").z - h_hips0.z).length())
		peak = maxf(peak, _max_speed(h))
	var h_moved := early
	_check(h.dead and h.last_hit_zone == &"Neck", "headshot: dead")
	_check(bolt_h.state == "in_body", "headshot: the bolt stays in the head (%s)" % bolt_h.state)
	_check(h_moved < 0.2 and peak < 9.0, "headshot: no launch (hips moved %.2f m in the first 0.25 s, fastest bone %.1f m/s)" % [h_moved, peak])

	# arm: through the hand or forearm and on (seeded), a reduced wound
	var r := _clown(Vector3(0.0, 0, -3.0))
	await _frames(10)
	var bolt_r := _fire_at(r, &"LeftLowerArm")
	await _wait(0.5)
	var arm_hit := false
	for hl: Dictionary in r.hit_log:
		arm_hit = arm_hit or hl.zone == &"LowerArm"
	_check(arm_hit and not r.dead, "arm: hit in the forearm, alive (%.0f)" % r.health)
	_check(not is_instance_valid(bolt_r) or bolt_r.state != "flying", "arm: the bolt went on / stuck (%s)" % (bolt_r.state if is_instance_valid(bolt_r) else "gone"))
	# leg: hurt less, still up
	var l := _clown(Vector3(1.5, 0, -3.0))
	await _frames(10)
	_fire_at(l, &"RightUpperLeg")
	await _wait(0.5)
	_check(not l.dead and l.health > 40.0, "leg: hurt less (%.0f), alive" % l.health)

	print("== a wall close behind")
	# torso, back to the wall: pinned alive, held there, struggling
	var w := _clown(Vector3(-2.5, 0, wall_z + 0.22))
	await _frames(10)
	var w0 := w.global_position
	var hand0 := w.skeleton.get_bone_global_pose(w.skeleton.find_bone("LeftHand")).origin
	var bolt_w := _fire_at(w, &"Chest")
	await _wait(0.3)
	_check(bolt_w.state == "pinned" and w.pinned and not w.dead, "torso into the wall: pinned, alive (%s, %.0f)" % [bolt_w.state, w.health])
	_check(bolt_w.global_position.z < wall_z, "the point is in the wall (tip z %.3f, wall %.2f)" % [bolt_w.global_position.z, wall_z])
	var hand_moved := 0.0
	var drift := 0.0
	var pin_err := 0.0
	for i in 150:
		await get_tree().physics_frame
		drift = maxf(drift, Vector2(w.global_position.x - w0.x, w.global_position.z - w0.z).length())
		var hb := w.skeleton.get_bone_global_pose(w.skeleton.find_bone("LeftHand")).origin
		hand_moved = maxf(hand_moved, hb.distance_to(hand0))
		if w.pins.size() > 0 and not w.dead:
			var pin: Dictionary = w.pins[0]
			var now: Vector3 = w.skeleton.global_transform * w.skeleton.get_bone_global_pose(w.skeleton.find_bone(pin.bone)) * (pin.local as Vector3)
			pin_err = maxf(pin_err, now.distance_to(pin.at))
	_check(drift < 0.13, "held where it stood (moved at most %.3f m)" % drift)
	_check(pin_err < 0.06, "the pinned point stays on the bolt (off by at most %.3f m)" % pin_err)
	_check(hand_moved > 0.05, "it struggles: the free hand moves (%.2f m)" % hand_moved)
	await _shot("3_pinned_alive", _bone_pos(w, &"Chest"), _bone_pos(w, &"Chest") + Vector3(1.1, 0.1, 1.5))
	# then it dies there (a second bolt, the head): the ragdoll hangs from the pin
	var bolt_w2 := _fire_at(w, &"Neck", Vector3(0, 0.05, 0))
	await _wait(0.3)
	_check(w.dead and not w.pinned, "killed while pinned: dead (%s)" % [w.death.get("weapon", "")])
	var peak_w := 0.0
	var pin_err_dead := 0.0
	var peak_bone := &""
	var peak_t := 0
	for i in 180:
		await get_tree().physics_frame
		var sp := _max_speed(w)
		if sp > peak_w:
			peak_w = sp
			peak_bone = fastest
			peak_t = i
		var pin: Dictionary = w.pins[0] if w.pins.size() > 0 else {}
		if not pin.is_empty():
			pin_err_dead = maxf(pin_err_dead, _bone_pos(w, pin.bone).distance_to(pin.at) - 0.0)
	var chest_w := _bone_pos(w, &"Chest")
	_check(w.pins.size() >= 1 and (w.pins[0].joint as RID).is_valid(), "the ragdoll is held at the pin (a joint)")
	_check(chest_w.distance_to(bolt_w.global_position) < 0.45, "hanging on the bolt (chest %.2f m from it)" % chest_w.distance_to(bolt_w.global_position))
	print("      pinned corpse: chest %.2f m, hips %.2f m, feet %.2f / %.2f m (standing hips were %.2f m)" % [chest_w.y, _bone_pos(w, &"Hips").y, _bone_pos(w, &"LeftFoot").y, _bone_pos(w, &"RightFoot").y, w0.y + 0.96])
	_check(_bone_pos(w, &"Hips").y < chest_w.y - 0.15, "the rest hangs under gravity (hips %.2f m below the chest)" % (chest_w.y - _bone_pos(w, &"Hips").y))
	_check(peak_w < 8.0, "no explosive physics (fastest bone %.1f m/s: %s, frame %d)" % [peak_w, peak_bone, peak_t])
	_check(w.death.get("stake", false), "counted as pinned up (records)")
	await _shot("4_pinned_dead", chest_w, chest_w + Vector3(1.2, 0.2, 1.6))

	# a fatal pin: through the head into the wall
	var f := _clown(Vector3(-0.6, 0, wall_z + 0.2))
	await _frames(10)
	var f_nc0 := _bone_pos(f, &"Neck").distance_to(_bone_pos(f, &"Chest"))
	var bolt_f := _fire_at(f, &"Neck", Vector3(0, 0.05, 0))
	await _wait(0.3)
	_check(f.dead and bolt_f.state == "pinned", "head into the wall: dead and pinned (%s)" % bolt_f.state)
	var peak_f := 0.0
	for i in 180:
		await get_tree().physics_frame
		peak_f = maxf(peak_f, _max_speed(f))
	var head_f := _bone_pos(f, &"Neck")
	print("      fatal pin: neck-chest %.3f m (standing %.3f), hips %.2f, feet %.2f/%.2f, chest %.2f" % [_bone_pos(f, &"Neck").distance_to(_bone_pos(f, &"Chest")), f_nc0,
		_bone_pos(f, &"Hips").y, _bone_pos(f, &"LeftFoot").y, _bone_pos(f, &"RightFoot").y, _bone_pos(f, &"Chest").y])
	_check(head_f.distance_to(bolt_f.global_position) < 0.4 and peak_f < 8.0, "the head stays at the bolt (%.2f m), calm (%.1f m/s)" % [head_f.distance_to(bolt_f.global_position), peak_f])
	await _shot("5_fatal_pin", head_f + Vector3.DOWN * 0.4, head_f + Vector3(1.3, -0.2, 1.6))

	# a limb pin: through the upper arm into the wall; it tears itself free
	var g := _clown(Vector3(1.4, 0, wall_z + 0.16))
	g.pin_free_after = Vector2(2.0, 2.0)
	await _frames(10)
	var bolt_g: CrossbowBolt = null
	for attempt in 4:
		bolt_g = _fire_at(g, &"LeftUpperArm")
		await _wait(0.3)
		if bolt_g.state == "pinned":
			break
	_check(g.pinned, "upper arm into the wall: pinned (%s)" % bolt_g.state)
	await _wait(2.6)
	_check(not g.pinned and not g.dead and is_instance_valid(bolt_g) and bolt_g.state == "in_body", "it tears its arm off the bolt: free, alive (%.0f), the bolt in its arm" % g.health)

	# two pinned at once
	var m1 := _clown(Vector3(3.0, 0, wall_z + 0.22))
	var m2 := _clown(Vector3(4.4, 0, wall_z + 0.22))
	await _frames(10)
	_fire_at(m1, &"Spine")
	_fire_at(m2, &"Chest")
	await _wait(0.5)
	_check(m1.pinned and m2.pinned, "two pinned at once")
	# left pinned through the body, it bleeds and dies there (no stuck state)
	m1.health = 3.0
	await _wait(2.0)
	_check(m1.dead and m1.pins.size() > 0 and (m1.pins[0].joint as RID).is_valid(), "a body pin bleeds it out, and the corpse stays pinned")

	print("== loose bolts")
	var before := get_tree().get_nodes_in_group(&"__none").size()
	for i in 50:
		CrossbowBolt.launch(room, Vector3(-5.0 + i * 0.2, 1.6, -6.0), Vector3(0, -0.05, -1), 100 + i)
		await _frames(1)
	await _wait(0.6)
	var loose := 0
	for n in room.get_children():
		if n is CrossbowBolt and (n as CrossbowBolt).state == "in_world":
			loose += 1
	_check(loose <= CrossbowBolt.MAX_LOOSE and loose >= 20, "bolts in the wall are capped (%d left of 50, cap %d)" % [loose, CrossbowBolt.MAX_LOOSE])

	print("== the crossbow")
	p.select_weapon(FpsPlayer.STAKE)
	await _wait(0.8)
	_check(p.ammo[FpsPlayer.STAKE] == 1 and FpsPlayer.WEAPONS[FpsPlayer.STAKE].name == "Crossbow", "slot 4 is the crossbow, loaded")
	var t := _clown(Vector3(0.0, 0, -1.5))
	await _frames(10)
	p.camera.look_at(_bone_pos(t, &"Chest"))
	p.fire()
	await _frames(2)
	_check(p.ammo[FpsPlayer.STAKE] == 0, "fires one bolt")
	await _wait(0.6)
	_check(t.health < t.max_health, "the player's bolt hit (%.0f)" % t.health)
	_check(p.view.reloading(), "and spans and loads again by itself")
	await _wait(0.6)
	p.select_weapon(FpsPlayer.PISTOL)
	await _wait(0.8)
	p.select_weapon(FpsPlayer.STAKE)
	await _wait(ViewModel.STAKE_RELOAD + 1.2)
	_check(p.ammo[FpsPlayer.STAKE] == 1, "switched away mid-load and back: spans and loads by itself (%d)" % p.ammo[FpsPlayer.STAKE])

	print("XBOW: %d failed" % failed)
	get_tree().quit()


## --dump --side=R|L: the crossbow's triangles and a hand, for the grip fitter.
## --fp: first-person pictures (/tmp/xbow_fp_*.png): held, aimed, loosed, and the
## reload's stages.
func _view_modes() -> void:
	room = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	var p: FpsPlayer = room.player
	p.god_mode = true
	p.select_weapon(FpsPlayer.STAKE)
	await _wait(1.0)
	var v := p.view
	if "--dump" in OS.get_cmdline_user_args():
		_dump(v, OS.get_cmdline_user_args())
		print("DUMP done (%s)" % ("L" if "--side=L" in OS.get_cmdline_user_args() else "R"))
		return
	render = true
	p.camera.rotation.x = -0.12
	await _shot("fp_1_held")
	p.aim_override = 1.0
	await _wait(0.6)
	await _shot("fp_2_aimed")
	p.fire()
	await get_tree().process_frame
	v.set_process(false); await _shot("fp_3_loosed"); v.set_process(true)
	p.aim_override = 0.0
	await _wait(0.5)
	for st: Array in [[0.3, "4_to_lever"], [0.75, "5_spanning"], [1.2, "6_spanned"], [1.5, "7_stowing"], [2.1, "8_bolt"], [2.45, "9_laying"], [2.7, "10_sliding"], [3.3, "11_ready"]]:
		while v._reload_t >= 0.0 and v._reload_t < float(st[0]):
			await get_tree().process_frame
		v.set_process(false); await _shot("fp_" + String(st[1])); v.set_process(true)
	print("FP done")


func _dump(v: ViewModel, args: PackedStringArray) -> void:
	var side := "L" if "--side=L" in args else "R"
	var to_model := v._xb_model.global_transform.affine_inverse()
	var f := FileAccess.open("/tmp/gun_tris.txt", FileAccess.WRITE)
	for m in v._xb_model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.get_parent() == v._xb_bolt or mi in v._xb_string:
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
	var r: FPArm = v._arms[ViewModel.STAKE][side]
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
