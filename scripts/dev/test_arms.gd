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
	# reload: the support hand lets go and comes back; the gun still works
	await get_tree().create_timer(0.6).timeout
	var l: FPArm = arms["L"]
	var home: Vector3 = l.position
	p.reload()
	await get_tree().create_timer(1.2).timeout
	await _shot("fp_reload")
	_check(l.position.distance_to(home) > 0.1 or not l.visible, "the left hand lets go for the reload")
	await get_tree().create_timer(2.2).timeout
	_check(l.visible and l.position.distance_to(home) < 0.005, "and takes hold again when it is shut")
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

