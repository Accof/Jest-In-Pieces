extends Node
## Shot through the throat, checked. Sections (user args; none = all):
##   aim     where a round counts as the throat on each body (the neck itself
##           and the top of the chest; not the face, not the belly)
##   deaths  a clown, a WitzSoldat with a rifle, a Rattlejack, a Zornhauptmann:
##           dead and counted at once, the weapon dropped, both hands at the
##           throat, down on the floor, writhing, the artery spurting (weaker
##           each beat) onto the floor and the walls, a pool under the neck,
##           then still; the Klappersoldat (clockwork) never
##   interrupt  shot again: it ends there; a held trigger's next rounds do not
## Add "render" (with a window) for frames in /tmp/th_*.png.

var render := false
var fails := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/th_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["aim", "deaths", "interrupt"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("THROAT: %d failed" % fails)
	get_tree().quit()


func _sandbox() -> Node3D:
	for n in get_children():
		if n.name == "Room":
			n.queue_free()
	await get_tree().process_frame
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	room.name = "Room"
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	return room


func _make(room: Node3D, kind: String, at: Vector3) -> Clown:
	var c: Clown
	match kind:
		"rattlejack":
			c = Rattlejack.new()
		"zornhauptmann":
			c = Zornhauptmann.new()
		"klappersoldat":
			c = Klappersoldat.new()
		_:
			c = Clown.new()
			if kind == "witzsoldat":
				c.body = "witzsoldat"
	room.add_child(c)
	c.position = at
	match kind:
		"witzsoldat", "rattlejack":
			c.give_rifle()
		"zornhauptmann":
			(c as Zornhauptmann).give_officer_kit()
		"clown":
			c.give_gun()
	return c


## A round fired straight at the clown at height `h` (m above its feet), from
## 4 m in front: what it hits, through the real physics.
func _fire_at(c: Clown, h: float, damage := 40.0) -> Dictionary:
	var front := c.global_basis.z
	var to := c.global_position + Vector3.UP * h
	var from := to + front * 1.2        # (inside any wall set up in front of him)
	var q := PhysicsRayQueryParameters3D.create(from, to - front * 1.0, 1 | (1 << 2))
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is PhysicalBone3D):
		return {}
	var info := {collider = hit.collider, position = hit.position, direction = -front, damage = damage, impulse = 12.0, weapon = "Pistol", shot_id = randi()}
	c.hit(info)
	return info


## A height (above the feet) where a round from the front lands in the throat.
func _throat_height(c: Clown, neck_y: float, head_y: float) -> float:
	var y := neck_y - 0.1
	var found: Array = []
	while y < head_y + 0.1:
		var front := c.global_basis.z
		var to := c.global_position + Vector3.UP * y
		var q := PhysicsRayQueryParameters3D.create(to + front * 1.2, to - front, 1 | (1 << 2))
		var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider is PhysicalBone3D:
			var zone := Clown._zone(StringName((hit.collider as PhysicalBone3D).bone_name))
			if c.is_throat_hit({position = hit.position}, zone):
				found.append(y)
		y += 0.01
	return found[found.size() / 2] if not found.is_empty() else (neck_y + head_y) * 0.5


func _aim() -> void:
	print("-- aim")
	var room := await _sandbox()
	for kind: String in ["clown", "witzsoldat", "rattlejack", "zornhauptmann"]:
		var c := _make(room, kind, Vector3(0, 0, -3))
		for i in 5:
			await get_tree().physics_frame
		var sk := c.skeleton
		var neck_y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Neck")).origin).y - c.global_position.y
		var head_y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin).y - c.global_position.y
		var rows: Array = []
		var throat_hits := 0
		var y := neck_y - 0.12
		while y < head_y + 0.25:
			var front := c.global_basis.z
			var to := c.global_position + Vector3.UP * y
			var q := PhysicsRayQueryParameters3D.create(to + front * 4.0, to - front, 1 | (1 << 2))
			var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
			var tag := "-"
			if not hit.is_empty() and hit.collider is PhysicalBone3D:
				var zone := Clown._zone(StringName((hit.collider as PhysicalBone3D).bone_name))
				var th := c.is_throat_hit({position = hit.position}, zone)
				tag = "%s%s" % [zone, "*" if th else ""]
				if th:
					throat_hits += 1
			rows.append("%.2f %s" % [y, tag])
			y += 0.025
		print("      %s (neck %.2f, chin %.2f): %s" % [kind, neck_y, head_y, ", ".join(rows)])
		_check(throat_hits >= 2, "%s: the neck can be hit, and counts as the throat" % kind)
		# the face is still a headshot, the belly still a body shot
		var face := {position = c.global_position + Vector3.UP * (head_y + 0.12) + c.global_basis.z * 0.1}
		var belly := {position = c.global_position + Vector3.UP * 1.1 + c.global_basis.z * 0.1}
		_check(not c.is_throat_hit(face, &"Neck") and not c.is_throat_hit(belly, &"Chest"), "%s: the face and the belly are not the throat" % kind)
		c.queue_free()
		await get_tree().physics_frame


func _decal_count() -> int:
	var n := 0
	for d: Decal in Blood._decals:
		if d.visible:
			n += 1
	return n


## One throat death; returns what was measured.
func _one(room: Node3D, kind: String, at: Vector3, name_ := "", interrupt_at := -1.0) -> Dictionary:
	Blood.clear()
	var c := _make(room, kind, at)
	for i in 12:
		await get_tree().physics_frame
	var deaths := [0]
	c.died.connect(func(_x: Clown) -> void: deaths[0] += 1)
	var sk := c.skeleton
	var neck_y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Neck")).origin).y - c.global_position.y
	var head_y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin).y - c.global_position.y
	var armed := c.has_gun or c.has_rifle or c.has_club
	var drops_before := room.get_children().filter(func(n: Node) -> bool: return n is RigidBody3D).size()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("hold="):
			c.throat_hold_y = float(a.substr(5))
	c.health = 1.0
	var info := _fire_at(c, _throat_height(c, neck_y, head_y))
	var out := {hit = not info.is_empty(), dead = c.dead, throat = c.throat_death, bleeding = c.bleeding_out, deaths = 0}
	out.dropped = not (c.has_gun or c.has_rifle or c.has_club) and (not armed or room.get_children().filter(func(n: Node) -> bool: return n is RigidBody3D).size() > drops_before)
	var t := 0.0
	var hands_best := 9.0
	var hips_low := 9.0
	var move_total := 0.0
	var last := Vector3.ZERO
	var spurts_at: Array = []
	var last_spurts := 0
	var frame := 0
	var interrupted := false
	var spurts_after_stop := 0
	var stop_t := -1.0
	var ended_at := -1.0
	while t < 10.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		frame += 1
		if interrupt_at > 0.0 and not interrupted and t >= interrupt_at:
			interrupted = true
			var pb: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
			c.hit({collider = pb, position = pb.global_position, direction = -c.global_basis.z, damage = 30.0, impulse = 10.0, weapon = "Pistol", shot_id = randi()})
			stop_t = t
			last_spurts = c.throat_spurts
		if c.ragdoll.active:
			var neck: PhysicalBone3D = c.ragdoll.bones[&"Neck"]
			var hips: PhysicalBone3D = c.ragdoll.bones[&"Hips"]
			if OS.get_cmdline_user_args().has("dbg") and frame % 15 == 0 and t < 3.0:
				var wp := c.throat_wound_position()
				print("        t %.2f  L %.2f R %.2f  neck-h %.2f hips-h %.2f" % [t, (c.ragdoll.bones[&"LeftHand"] as PhysicalBone3D).global_position.distance_to(wp), (c.ragdoll.bones[&"RightHand"] as PhysicalBone3D).global_position.distance_to(wp), wp.y - at.y, hips.global_position.y - at.y])
			if t > 0.7 and t < 3.0:
				var hd := 0.0
				for side: String in ["Left", "Right"]:
					hd += (c.ragdoll.bones[StringName(side + "Hand")] as PhysicalBone3D).global_position.distance_to(c.throat_wound_position()) * 0.5
				hands_best = minf(hands_best, hd)
			hips_low = minf(hips_low, hips.global_position.y - at.y)
			if t > 2.5 and t < 5.0 and last != Vector3.ZERO:
				move_total += hips.global_position.distance_to(last) + (c.ragdoll.bones[&"LeftLowerLeg"] as PhysicalBone3D).global_position.distance_to(last) * 0.0
			last = hips.global_position
		if c.throat_spurts > spurts_at.size():
			spurts_at.append(t)
		if stop_t > 0.0 and t > stop_t + 0.1:
			spurts_after_stop = c.throat_spurts - last_spurts
		if ended_at < 0.0 and not c.bleeding_out:
			ended_at = t
		if render and name_ != "" and frame % 6 == 0 and t < 7.0:
			await _shot("%s_%03d" % [name_, frame])
	out.deaths = deaths[0]
	out.hands = hands_best
	out.hips_low = hips_low
	out.writhe = move_total
	out.spurts = c.throat_spurts
	out.gaps = []
	for i in range(1, spurts_at.size()):
		out.gaps.append(spurts_at[i] - spurts_at[i - 1])
	out.decals = _decal_count()
	out.pools = Blood.pools().size()
	out.ended = ended_at
	out.interrupted = c.throat_interrupted
	out.after_stop = spurts_after_stop
	# where the decals are: on the floor, and up a wall
	var walls := 0
	for d: Decal in Blood._decals:
		if d.visible and absf(d.global_basis.y.y) < 0.5:
			walls += 1
	out.walls = walls
	c.queue_free()
	await get_tree().physics_frame
	return out


func _deaths() -> void:
	print("-- deaths")
	var room := await _sandbox()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(2.3, 1.5, -2.0)
	cam.look_at(Vector3(0, 0.7, -3.2))
	var kinds := ["clown", "witzsoldat", "rattlejack", "zornhauptmann"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			kinds = [a.substr(5)]
	for kind: String in kinds:
		# with a wall a metre and a half in front of him, for the spray to reach
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(3, 2.6, 0.2)
		cs.shape = bx
		wall.add_child(cs)
		var wm := MeshInstance3D.new()
		var wbm := BoxMesh.new()
		wbm.size = bx.size
		wm.mesh = wbm
		wall.add_child(wm)
		room.add_child(wall)
		wall.global_position = Vector3(0, 1.3, -1.4)
		var o := await _one(room, kind, Vector3(0, 0, -3), kind if render else "")
		wall.queue_free()
		print("      %s: hit %s, throat %s, deaths %d, weapon dropped %s; hands to the neck %.2f m; hips down to %.2f m; writhing %.2f m; %d spurts, gaps %s; %d decals (%d on walls), %d pools; ended at %.1f s" % [
			kind, o.hit, o.throat, o.deaths, o.dropped, o.hands, o.hips_low, o.writhe, o.spurts, str(o.gaps.slice(0, 8).map(func(g: float) -> String: return "%.2f" % g)), o.decals, o.walls, o.pools, o.ended])
		_check(o.hit and o.dead and o.throat and o.bleeding, "%s: a fatal round through the neck is the throat death" % kind)
		_check(o.deaths == 1, "%s: counted at once, once (%d)" % [kind, o.deaths])
		_check(o.dropped, "%s: drops what it was holding" % kind)
		_check(o.hands < 0.22, "%s: both hands go to the throat (%.2f m)" % [kind, o.hands])
		_check(o.hips_low < 0.45, "%s: goes down to the floor (hips %.2f m)" % [kind, o.hips_low])
		_check(o.writhe > 0.05, "%s: writhes there (%.2f m)" % [kind, o.writhe])
		_check(o.spurts >= 6, "%s: the artery spurts, again and again (%d)" % [kind, o.spurts])
		var slowing: bool = o.gaps.size() > 3 and float(o.gaps[o.gaps.size() - 1]) > float(o.gaps[0])
		_check(slowing, "%s: the beats slow as he bleeds out" % kind)
		_check(o.decals >= 25 and o.walls >= 2, "%s: blood over the floor and up the wall (%d, %d)" % [kind, o.decals, o.walls])
		_check(o.pools >= 1, "%s: a pool under him" % kind)
		_check(o.ended > 4.0 and o.ended < 9.5, "%s: then still (%.1f s)" % [kind, o.ended])
	# clockwork: no throat to cut
	var k := _make(room, "klappersoldat", Vector3(0, 0, -3))
	for i in 10:
		await get_tree().physics_frame
	var sk := k.skeleton
	var ny := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Neck")).origin).y - k.global_position.y
	var hy := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin).y - k.global_position.y
	k.health = 1.0
	_fire_at(k, (ny + hy) * 0.5, 400.0)
	_check(not k.throat_death, "the Klappersoldat (clockwork) never")
	k.queue_free()
	# a headshot is still a headshot
	var h := _make(room, "witzsoldat", Vector3(0, 0, -3))
	for i in 10:
		await get_tree().physics_frame
	var sk2 := h.skeleton
	var hy2 := (sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("Head")).origin).y - h.global_position.y
	h.health = 1.0
	_fire_at(h, hy2 + 0.13)
	_check(h.dead and not h.throat_death, "a round in the face is not the throat")
	h.queue_free()
	cam.queue_free()
	await get_tree().physics_frame


func _interrupt() -> void:
	print("-- interrupt")
	var room := await _sandbox()
	var o := await _one(room, "witzsoldat", Vector3(0, 0, -3), "", 2.0)
	print("      shot again at 2.0 s: interrupted %s, %d spurts after, ended %.1f s, deaths %d" % [o.interrupted, o.after_stop, o.ended, o.deaths])
	_check(o.interrupted and o.after_stop == 0 and o.ended < 3.0, "shot again: it ends there, no more spurts")
	_check(o.deaths == 1, "counted once (%d)" % o.deaths)
	var o2 := await _one(room, "clown", Vector3(0, 0, -3), "", 0.15)
	print("      shot again at 0.15 s (a held trigger): interrupted %s, ended %.1f s" % [o2.interrupted, o2.ended])
	_check(not o2.interrupted and o2.ended > 4.0, "the next round of a held trigger does not cut it short")
