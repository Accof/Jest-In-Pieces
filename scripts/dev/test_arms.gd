extends Node
## The rigged WW1 arms on the revolver: they load, have their skeletons, hold
## the gun, stay on it through firing and recoil, the support hand lets go for
## the reload and comes back, the trigger finger follows the pull, and the
## procedural pistol keeps its own hands. --render: /tmp/arms_*.png from the
## player's eye and from outside (right, left, below, front).
var render := false
var failed := 0

func _ready() -> void:
	render = "--render" in OS.get_cmdline_user_args()
	_run()

func _check(ok: bool, what: String) -> void:
	print("   %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok: failed += 1

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _shot(n: String) -> void:
	if not render: return
	await _frames(3)
	get_viewport().get_texture().get_image().save_png("/tmp/arms_%s.png" % n)

func _run() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	var p: FpsPlayer = room.player
	p.global_position = Vector3(0, 0.05, 1.5)
	p.select_weapon(FpsPlayer.REVOLVER)
	await get_tree().create_timer(ViewModel.SWAP_TIME + 0.3).timeout
	var v := p.view
	if "--dump" in OS.get_cmdline_user_args():
		p.select_weapon(ViewModel.REVOLVER)
		await get_tree().create_timer(0.6).timeout
		if FileAccess.file_exists("/tmp/grip.txt"):
			v.apply_grip(ViewModel.REVOLVER, str_to_var(FileAccess.get_file_as_string("/tmp/grip.txt")), v._rev_model)
		_dump(v)
		get_tree().quit()
		return
	if "--pinch-search" in OS.get_cmdline_user_args():
		_pinch_search(v._arms[ViewModel.REVOLVER]["R"])
		get_tree().quit()
		return
	if "--lh" in OS.get_cmdline_user_args():
		await _lh_frames(p, v)
		get_tree().quit()
		return
	if "--measure" in OS.get_cmdline_user_args():
		p.select_weapon(ViewModel.REVOLVER)
		await get_tree().create_timer(0.6).timeout
		_measure(v)
		get_tree().quit()
		return
	if "--tune" in OS.get_cmdline_user_args() and FileAccess.file_exists("/tmp/grip.txt"):
		await _tune_index(v)
		get_tree().quit()
		return
	# tuning: a grip (Variant text, as in ARM_GRIPS) in /tmp/grip.txt overrides the built-in one
	var tune := "--tune" in OS.get_cmdline_user_args()
	if (render or tune) and FileAccess.file_exists("/tmp/grip.txt"):
		var g: Variant = str_to_var(FileAccess.get_file_as_string("/tmp/grip.txt"))
		if g is Dictionary:
			v.apply_grip(ViewModel.REVOLVER, g, v._rev_model)
			print("      grip from /tmp/grip.txt")
	_check(FPArm.exists("L") and FPArm.exists("R"), "both arm assets are in the project")
	var arms: Dictionary = v._arms.get(ViewModel.REVOLVER, {})
	_check(arms.has("R") and arms.has("L"), "the revolver has a right and a left arm")
	for s: String in ["R", "L"]:
		var a: FPArm = arms[s]
		var mi := a.model.find_children("*", "MeshInstance3D", true, false)
		var m := (mi[0] as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
		_check(a.skeleton.get_bone_count() == 17 and (mi[0] as MeshInstance3D).skin != null and m.albedo_texture != null and m.normal_texture != null,
			"arm %s: skinned on a 17-bone skeleton, glove textures on" % s)
	var pistol_ok := v._guns[ViewModel.PISTOL].find_children("*", "FPArm", true, false).is_empty() and not v._arms.has(ViewModel.PISTOL)
	_check(pistol_ok, "the procedural pistol keeps its own hands")
	# the hand stays on the grip: the hand bone relative to the gun model is fixed
	var r: FPArm = arms["R"]
	var rel0 := v._rev_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
	await _shot("fp_idle")
	p.camera.rotation.x = 0.0
	p.fire()
	var worst := 0.0
	for i in 20:
		await get_tree().process_frame
		var rel := v._rev_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r._hand))
		worst = maxf(worst, rel.origin.distance_to(rel0.origin))
	_check(worst < 0.001, "the right hand stays on the grip through the shot and the recoil (moved %.5f gun units)" % worst)
	# the index fingertip on the trigger: the end of index_03, in the gun model's space
	var i3 := r.skeleton.find_bone("index_03.R")
	var tip_len := 0.0
	for c in r.skeleton.get_bone_children(i3): tip_len = r.skeleton.get_bone_rest(c).origin.length()
	var i2 := r.skeleton.find_bone("index_02.R")
	var seg := r.skeleton.get_bone_rest(i3).origin.length()
	var i3_xf := r.skeleton.global_transform * r.skeleton.get_bone_global_pose(i3)
	var tip_w := i3_xf * Vector3(0, seg * 0.9, 0)
	var tip_m := v._rev_model.global_transform.affine_inverse() * tip_w
	var trig_m := Vector3(-0.09, 0.27, 0.0)          # middle of the trigger blade (model units)
	print("      index fingertip at model %s, trigger blade at %s: %.3f apart (%.1f cm)" % [tip_m, trig_m, tip_m.distance_to(trig_m), tip_m.distance_to(trig_m) * 29.0])
	for bn in ["index_01.R", "little_01.R", "thumb_02.R", "hand.R"]:
		var bx := r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r.skeleton.find_bone(bn))
		print("      %s at model %s" % [bn, v._rev_model.global_transform.affine_inverse() * bx.origin])
	_check(tip_m.distance_to(trig_m) < 0.12, "the index finger reaches the trigger")
	# trigger finger (once the last shot's pull has let go)
	await get_tree().create_timer(0.4).timeout
	var idx := r.skeleton.find_bone("index_02.R")
	var rest_q := r.skeleton.get_bone_pose_rotation(idx)
	v._arm_pull_last = -1.0
	v._arm_trigger(ViewModel.REVOLVER, 1.0)
	var pulled_q := r.skeleton.get_bone_pose_rotation(idx)
	var pulled := pulled_q.angle_to(rest_q)
	print("      index_02 at rest %s, pulled %s" % [rest_q, pulled_q])
	v._arm_pull_last = -1.0
	v._arm_trigger(ViewModel.REVOLVER, 0.0)
	_check(rad_to_deg(pulled) > 10.0, "the trigger finger curls with the pull (%.0f deg)" % rad_to_deg(pulled))
	# reload: the left hand opens the gun and holds it by the barrel, the right
	# hand pinches the rounds in, both end back on their grips
	await get_tree().create_timer(0.6).timeout
	var l: FPArm = arms["L"]
	var hand_in := func(arm: FPArm, ref: Node3D) -> Transform3D:
		return ref.global_transform.affine_inverse() * (arm.skeleton.global_transform * arm.skeleton.get_bone_global_pose(arm._hand))
	var l_home: Transform3D = hand_in.call(l, v._rev_model)
	var r_home: Transform3D = hand_in.call(r, v._rev_model)
	p.reload()
	var on_barrel: Array[Transform3D] = []
	var pinch_worst := 0.0
	var pinch_n := 0
	var r_left_grip := 0.0
	var tk := 0.0
	var shot_load := false
	while tk < 2.9:
		await get_tree().process_frame
		tk = v._reload_t if v._reload_t >= 0.0 else 9.0
		if tk > 0.8 and tk < 2.0:
			on_barrel.append(hand_in.call(l, v._rv_barrel))
			r_left_grip = maxf(r_left_grip, (hand_in.call(r, v._rev_model) as Transform3D).origin.distance_to(r_home.origin))
			# mid-push on a round: the pinch on its base
			var step := (ViewModel.V_T_LOAD.y - ViewModel.V_T_LOAD.x) / 6.0
			var order := int((tk - ViewModel.V_T_LOAD.x) / step)
			var into := fposmod(tk - ViewModel.V_T_LOAD.x, step) / step
			if order >= 0 and order < 6 and into > 0.15 and into < 0.6:
				var rd := v._rv_rounds[(order + v.rv_index % 6) % 6] as MeshInstance3D
				var aabb := rd.mesh.get_aabb()
				var base := rd.global_transform * Vector3(aabb.position.x, aabb.get_center().y, aabb.get_center().z)
				var sk := r.skeleton
				var tipf := func(bn: String) -> Vector3:
					var i := sk.find_bone(bn)
					return sk.global_transform * sk.get_bone_global_pose(i) * Vector3(0, sk.get_bone_rest(i).origin.length() * 0.85, 0)
				var mid: Vector3 = ((tipf.call("index_03.R") as Vector3) + (tipf.call("thumb_03.R") as Vector3)) * 0.5
				pinch_worst = maxf(pinch_worst, mid.distance_to(base) * 100.0 / ViewModel.SHRINK)
				pinch_n += 1
			if render and not shot_load and tk > 1.25:
				shot_load = true
				await _shot("fp_reload")
	var drift := 0.0
	for x in on_barrel:
		drift = maxf(drift, x.origin.distance_to(on_barrel[0].origin))
	_check(on_barrel.size() > 5 and drift < 0.002, "the left hand holds the open gun by the barrel while it is loaded (moved %.4f)" % drift)
	_check(r_left_grip > 0.1, "the right hand leaves the grip to load")
	_check(pinch_n > 3 and pinch_worst < 1.5, "the right hand pinches each round by its base as it goes in (worst %.1f cm, %d frames)" % [pinch_worst, pinch_n])
	await get_tree().create_timer(0.3).timeout
	var l_back: Transform3D = hand_in.call(l, v._rev_model)
	var r_back: Transform3D = hand_in.call(r, v._rev_model)
	_check(l_back.origin.distance_to(l_home.origin) < 0.001 and r_back.origin.distance_to(r_home.origin) < 0.001, "both hands end exactly back on their grips")
	_check(p.ammo[FpsPlayer.REVOLVER] == 6, "the revolver reloaded (6)")
	# switching away and back
	p.select_weapon(FpsPlayer.PISTOL)
	await get_tree().create_timer(ViewModel.SWAP_TIME + 0.2).timeout
	_check(p.weapon == FpsPlayer.PISTOL and not v._guns[ViewModel.REVOLVER].visible, "to the pistol: the revolver and its arms are hidden")
	await _shot("fp_pistol")
	p.select_weapon(FpsPlayer.REVOLVER)
	await get_tree().create_timer(ViewModel.SWAP_TIME + 0.2).timeout
	_check(p.weapon == FpsPlayer.REVOLVER and v._guns[ViewModel.REVOLVER].visible and r.is_visible_in_tree(), "and back: the arms are there again")
	if render:
		# outside views of the gun in the hand
		p.set_process(false); p.set_physics_process(false); v.set_process(false)
		var cam := Camera3D.new(); add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.42 * ViewModel.SHRINK
		var g := v._rev_model.global_transform
		var centre := g * Vector3(-0.25, 0.3, 0.0)
		var size := 0.45 * ViewModel.SHRINK
		for k: Array in [["right", Vector3(0, 0, 1)], ["left", Vector3(0, 0, -1)], ["below", Vector3(0, -1, 0.3)], ["front", Vector3(1, 0.2, 0.3)], ["back", Vector3(-1, 0.4, 0.4)]]:
			var dir: Vector3 = (g.basis * k[1]).normalized()
			cam.global_position = centre + dir * 0.6
			cam.look_at(centre, g.basis.y.normalized() if absf(dir.dot(g.basis.y.normalized())) < 0.9 else g.basis.x.normalized())
			cam.near = 0.005
			cam.make_current()
			await _shot("out_" + String(k[0]))
	print("ARMS: %d failed" % failed)
	get_tree().quit()


## Search the index finger's angles that put the fingertip pad on the trigger blade.
func _tune_index(v: ViewModel) -> void:
	var g: Dictionary = str_to_var(FileAccess.get_file_as_string("/tmp/grip.txt"))
	v.apply_grip(ViewModel.REVOLVER, g, v._rev_model)
	var r: FPArm = v._arms[ViewModel.REVOLVER]["R"]
	var i3 := r.skeleton.find_bone("index_03.R")
	var seg := r.skeleton.get_bone_rest(i3).origin.length()
	var target := Vector3(-0.07, 0.275, 0.0)           # the trigger blade's face, where the pad goes
	var base: Dictionary = g.R.pose.duplicate()
	var best := [999.0, Vector3.ZERO, 0.0, 0.0, Vector3.ZERO]
	for spread in range(-24, 25, 4):
		for c1 in range(-30, 21, 4):
			for c2 in range(10, 81, 5):
				for c3 in range(0, 61, 10):
					var pose := base.duplicate()
					pose["index_01"] = Vector3(c1, 0, spread)
					pose["index_02"] = Vector3(c2, 0, 0)
					pose["index_03"] = Vector3(c3, 0, 0)
					r.set_pose(pose)
					var x3 := r.skeleton.global_transform * r.skeleton.get_bone_global_pose(i3)
					var tip := v._rev_model.global_transform.affine_inverse() * (x3 * Vector3(0, seg * 0.8, 0))
					var d := tip.distance_to(target)
					if d < best[0]:
						best = [d, Vector3(c1, 0, spread), c2, c3, tip]
	print("TUNE best %.3f model units (%.1f cm): index_01 %s index_02 %d index_03 %.0f, tip at %s" % [best[0], best[0] * 29.0, best[1], best[2], best[3], best[4]])
	var x1 := r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r.skeleton.find_bone("index_01.R"))
	print("TUNE index knuckle at model %s" % (v._rev_model.global_transform.affine_inverse() * x1.origin))


func _aabb_in(n: Node, ref: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a: AABB = (ref.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Sizes in metres as the player sees them (undoing the view model's SHRINK).
func _measure(v: ViewModel) -> void:
	var ref: Node3D = v._rev_model.get_parent()
	var k := ref.global_transform.basis.get_scale().x / ViewModel.SHRINK     # pose-space units -> eye-scale metres
	var g := _aabb_in(v._rev_model, ref)
	print("MEASURE pose scale %.3f, SHRINK %.2f" % [ref.global_transform.basis.get_scale().x, ViewModel.SHRINK])
	print("MEASURE gun box (pose space) %s -> length %.3f m, height %.3f m" % [g.size, maxf(g.size.x, g.size.z) * k, g.size.y * k])
	var r: FPArm = v._arms[ViewModel.REVOLVER]["R"]
	var sk := r.skeleton
	var inv := ref.global_transform.affine_inverse()
	var at := func(b: String) -> Vector3: return inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin
	var seg := 0.0
	for b in ["middle_02.R", "middle_03.R"]:
		seg += sk.get_bone_rest(sk.find_bone(b)).origin.length()
	seg += sk.get_bone_rest(sk.find_bone("middle_03.R")).origin.length() * 0.8
	var sks := (inv.basis * sk.global_transform.basis).get_scale().x
	var hand_len: float = at.call("hand.R").distance_to(at.call("middle_01.R")) + seg * sks
	print("MEASURE palm width (index-little knuckles) %.3f m" % (at.call("index_01.R").distance_to(at.call("little_01.R")) * k))
	print("MEASURE hand length wrist->middle tip %.3f m" % (hand_len * k))
	print("MEASURE arm box (pose space) %s" % _aabb_in(r, ref).size)
	var gm := _aabb_in(v._rev_model, v._rev_model)
	print("MEASURE gun box in model space: from %s to %s" % [gm.position, gm.end])
	var li := r.skeleton.find_bone("little_01.R")
	print("MEASURE little knuckle at model %s, index knuckle %s" % [v._rev_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(li)).origin, v._rev_model.global_transform.affine_inverse() * (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(r.skeleton.find_bone("index_01.R"))).origin])
	for m in v._rev_model.find_children("*", "MeshInstance3D", true, false):
		var a := _aabb_in(m, v._rev_model)
		if a.position.y < 0.0:
			print("MEASURE low part %s: y %.3f..%.3f x %.3f..%.3f" % [m.name, a.position.y, a.end.y, a.position.x, a.end.x])


## The gun's triangles and the right arm's skinned vertices (with each one's
## strongest bone), both in gun-model space, for the clipping check in Python.
func _dump(v: ViewModel) -> void:
	var to_model := v._rev_model.global_transform.affine_inverse()
	var f := FileAccess.open("/tmp/gun_tris.txt", FileAccess.WRITE)
	for m in v._rev_model.find_children("*", "MeshInstance3D", true, false):
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
	var r: FPArm = v._arms[ViewModel.REVOLVER]["R"]
	var sk := r.skeleton
	var o := FileAccess.open("/tmp/hand_verts.txt", FileAccess.WRITE)
	for m in r.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var skin := mi.skin
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
		var gb := g.basis
		j.store_line("%s %d %f %f %f %f %f %f %f %s %s %s %s" % [sk.get_bone_name(b), sk.get_bone_parent(b), q.x, q.y, q.z, q.w, rest.origin.x, rest.origin.y, rest.origin.z,
			var_to_str(gb.x).replace(" ", ""), var_to_str(gb.y).replace(" ", ""), var_to_str(gb.z).replace(" ", ""), var_to_str(g.origin).replace(" ", "")])
	j.close()
	print("DUMP done")


## The left hand through the reload, frozen at moments of it: first person, and
## from the left (outside, orthographic). /tmp/lh_<t>_fp.png, /tmp/lh_<t>_out.png
func _lh_frames(p: FpsPlayer, v: ViewModel) -> void:
	p.camera.rotation.x = 0.0
	await get_tree().create_timer(0.3).timeout
	p.set_process(false); p.set_physics_process(false); v.set_process(false)
	v.start_reload()
	var oc := Camera3D.new()
	add_child(oc)
	oc.projection = Camera3D.PROJECTION_ORTHOGONAL
	oc.size = 0.5 * ViewModel.SHRINK
	oc.near = 0.005
	var times: Array = [0.1, 0.35, 0.56, 0.72, 0.95, 1.4, 2.0, 2.15, 2.3, 2.55]
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--times="):
			times = Array(a.trim_prefix("--times=").split(",")).map(func(x: String) -> float: return float(x))
	for t: float in times:
		v._reload_t = t
		v.animate(0.0, 0.0, Vector2.ZERO)
		_lh_report(v, t)
		if not render:
			continue
		p.camera.make_current()
		await _shot("lh_%04d_fp" % int(t * 1000))
		if "--fp-only" in OS.get_cmdline_user_args():
			continue
		var g := v._rev_model.global_transform
		var centre := g * Vector3(-0.05, 0.45, 0.0)
		for k: Array in [["left", Vector3(0.15, 0.25, -1)], ["top", Vector3(-0.3, 1, -0.3)]]:
			var d: Vector3 = (g.basis * k[1]).normalized()
			oc.global_position = centre + d * 0.6
			oc.look_at(centre, g.basis.y.normalized() if k[0] == "left" else g.basis.x.normalized())
			oc.make_current()
			await _shot("lh_%04d_%s" % [int(t * 1000), k[0]])
	print("LH frames done")


## Where the left index and thumb tips are against the round going in (cm, real size).
func _lh_report(v: ViewModel, t: float) -> void:
	var l: FPArm = v._arms[ViewModel.REVOLVER]["R"]
	var sk := l.skeleton
	var tip := func(b: String) -> Vector3:
		var i := sk.find_bone(b)
		var x := sk.global_transform * sk.get_bone_global_pose(i)
		return x * Vector3(0, sk.get_bone_rest(i).origin.length() * 0.85, 0)
	var first := v.rv_index % 6
	var step := (ViewModel.V_T_LOAD.y - ViewModel.V_T_LOAD.x) / 6.0
	var order := clampi(int((t - ViewModel.V_T_LOAD.x) / step), 0, 5)
	var rd := v._rv_rounds[(order + first) % 6] as MeshInstance3D
	var aabb := rd.mesh.get_aabb()
	var base := rd.global_transform * Vector3(aabb.position.x, aabb.get_center().y, aabb.get_center().z)
	var k := 100.0 / ViewModel.SHRINK                        # world (shrunk view) -> real cm
	print("RH t=%.2f index tip %.1f cm, thumb tip %.1f cm from the round's base; tips %.1f cm apart" % [t,
		(tip.call("index_03.R") as Vector3).distance_to(base) * k, (tip.call("thumb_03.R") as Vector3).distance_to(base) * k,
		(tip.call("index_03.R") as Vector3).distance_to(tip.call("thumb_03.R")) * k])


## Thumb and index angles that bring the tips together about a round's width
## apart (1.4 cm), with the other fingers tucked; prints the best few.
func _pinch_search(arm: FPArm) -> void:
	var sk := arm.skeleton
	var tip := func(b: String) -> Vector3:
		var i := sk.find_bone(b + ".R")
		return sk.get_bone_global_pose(i) * Vector3(0, sk.get_bone_rest(i).origin.length() * 0.85, 0)
	var k := 100.0 * FPArm.SIZE                     # skeleton units -> real cm
	var tucked := {"middle_01": Vector3(80, 0, 0), "middle_02": Vector3(95, 0, 0), "middle_03": Vector3(55, 0, 0),
		"ring_01": Vector3(82, 0, 0), "ring_02": Vector3(95, 0, 0), "ring_03": Vector3(55, 0, 0),
		"little_01": Vector3(84, 0, 0), "little_02": Vector3(92, 0, 0), "little_03": Vector3(55, 0, 0)}
	var res := []
	for tx in range(0, 91, 10):
		for tz in range(-60, 31, 10):
			for t2 in range(0, 61, 15):
				for i1 in range(10, 81, 10):
					for i2 in range(10, 81, 14):
						var pose := tucked.duplicate()
						pose["thumb_01"] = Vector3(tx, 0, tz)
						pose["thumb_02"] = Vector3(t2, 0, 0)
						pose["thumb_03"] = Vector3(t2 * 0.6, 0, 0)
						pose["index_01"] = Vector3(i1, 0, 0)
						pose["index_02"] = Vector3(i2, 0, 0)
						pose["index_03"] = Vector3(i2 * 0.6, 0, 0)
						arm.set_pose(pose)
						var d: float = (tip.call("index_03") as Vector3).distance_to(tip.call("thumb_03")) * k
						# the pinch a little way out from the palm, fingers not crushed into it
						var mid: Vector3 = ((tip.call("index_03") as Vector3) + (tip.call("thumb_03") as Vector3)) * 0.5
						var hb := sk.get_bone_global_pose(sk.find_bone("hand.R"))
						var out_of_palm := (hb.affine_inverse() * mid).y * k
						res.append([absf(d - 1.4) + maxf(0.0, 7.0 - out_of_palm) * 0.3, d, out_of_palm, [tx, tz, t2, i1, i2]])
	res.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for r in res.slice(0, 5):
		print("PINCH tips %.1f cm apart, %.1f cm out along the hand: thumb_01 (%d,0,%d) thumb_02 %d index_01 %d index_02 %d" % [r[1], r[2], r[3][0], r[3][1], r[3][2], r[3][3], r[3][4]])

