extends SceneTree
func _init() -> void:
	var out := {}
	for f in DirAccess.get_files_at("res://art/anim_ref"):
		if not f.ends_with(".fbx"):
			continue
		var ps: PackedScene = load("res://art/anim_ref/" + f)
		var root: Node = ps.instantiate()
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var anim_name := ""
		for nm in ap.get_animation_list():
			if nm != "RESET":
				anim_name = nm
		var an: Animation = ap.get_animation(anim_name)
		var rot := {}
		var pos := {}
		var last_key := 0.0
		for t in an.get_track_count():
			var path := str(an.track_get_path(t))
			var bn := path.get_slice(":", 1)
			if an.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot[bn] = t
			elif an.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pos[bn] = t
			if an.track_get_key_count(t) > 0:
				last_key = maxf(last_key, an.track_get_key_time(t, an.track_get_key_count(t) - 1))
		var n := int(round(last_key * 30.0))
		var frames := []
		for k in n + 1:
			var tt := k / 30.0
			var glob := {}
			var fr := {}
			for i in sk.get_bone_count():
				var bn := sk.get_bone_name(i)
				var rest := sk.get_bone_rest(i)
				var o := rest.origin
				var q := rest.basis.get_rotation_quaternion()
				if pos.has(bn):
					o = an.position_track_interpolate(pos[bn], tt)
				if rot.has(bn):
					q = an.rotation_track_interpolate(rot[bn], tt)
				var local := Transform3D(Basis(q), o)
				var p := sk.get_bone_parent(i)
				var g: Transform3D = (glob[p] * local) if p >= 0 else local
				glob[i] = g
				var gq := g.basis.get_rotation_quaternion()
				fr[bn] = [g.origin.x, g.origin.y, g.origin.z, q.x, q.y, q.z, q.w, gq.x, gq.y, gq.z, gq.w]
			frames.append(fr)
		var rest := {}
		for i in sk.get_bone_count():
			var r := sk.get_bone_rest(i)
			var rq := r.basis.get_rotation_quaternion()
			rest[sk.get_bone_name(i)] = [sk.get_bone_parent(i), r.origin.x, r.origin.y, r.origin.z, rq.x, rq.y, rq.z, rq.w]
		out[f] = {"anim": anim_name, "length": last_key, "bones": Array(range(sk.get_bone_count())).map(func(i): return sk.get_bone_name(i)), "rest": rest, "frames": frames, "pos_tracks": pos.keys(), "skel_xform": str(sk.transform), "root_path": str(root.get_path_to(sk))}
		print(f, " ", anim_name, " keys to ", last_key, "s, pos tracks ", pos.keys().size(), " ", pos.keys().slice(0, 3), " skel ", sk.transform.basis.get_scale(), " path ", root.get_path_to(sk))
		root.free()
	var fa := FileAccess.open("/tmp/anim_ref_dump.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	quit()
