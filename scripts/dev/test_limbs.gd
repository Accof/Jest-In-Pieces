extends Node3D
## Broken legs and arms, checked on a real floor. Sections (user args; none = all):
##   legshots  pistol rounds into the legs: they break, they do not kill
##   last      both legs broken: it goes down, cannot get up, drags itself
##             away, finds a wall and sits against it; a gunman pulls a
##             pistol and shoots from there, a clown without one swipes
##   klapper   the same for a Klappersoldat
##   arms      an arm broken: it dangles with bone showing; a rifleman drops
##             the rifle for a pistol in the good hand; both arms out: it
##             stops fighting and hides out of sight
##   blast     clowns caught close to an explosion: several bones at once
## Add "render" (with a window) for /tmp/limbs_*.png.

var render := false
var fails := 0
var game: Node3D


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name_: String, at: Vector3, from: Vector3) -> void:
	if not render:
		return
	var cam := get_viewport().get_camera_3d()
	var own := Camera3D.new()
	add_child(own)
	own.global_position = from
	own.look_at(at)
	own.make_current()
	var lamp := OmniLight3D.new()
	own.add_child(lamp)
	lamp.light_energy = 2.5
	lamp.omni_range = 6.0
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/limbs_%s.png" % name_)
	if cam:
		cam.make_current()
	own.queue_free()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["legshots", "last", "klapper", "arms", "blast"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("LIMBS: %d failed" % fails)
	get_tree().quit()


func _new_game(seed_: int) -> void:
	if game:
		game.queue_free()
		await _frames(2)
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(1)
	seed(seed_)
	game.rng.seed = seed_
	game.start_run()
	await _frames(5)
	game.kill_cam.enabled = false
	FpsPlayer.god_mode = true


## One enemy of the kind asked for, alone on the floor a few cells along the
## route, with the player a cell away.
func _alone(kind: String) -> Clown:
	for c: Clown in game.clowns:
		if is_instance_valid(c):
			c.queue_free()
	game.clowns.clear()
	await _frames(1)
	var c: Clown
	match kind:
		"klapper": c = game.spawn_klapper()
		"rifle": c = game._spawn_clown(true, false)
		"gun": c = game._spawn_clown(false, true)
		_: c = game._spawn_clown(false, false)
	if kind == "rifle" and not c.has_rifle:
		c.queue_free()
		return await _alone(kind)
	var m: Maze = game.maze
	var cell: Vector2i = m.route[mini(5, m.route.size() - 1)]
	c.global_position = m.cell_center(cell)
	game.remaining = 1
	var p: FpsPlayer = game.player
	var prev: Vector2i = m.route[mini(4, m.route.size() - 2)]
	p.global_position = m.cell_center(prev) + Vector3.UP * 0.05
	await _frames(3)
	return c


func _hit(c: Clown, bone: StringName, dmg: float, extra := {}) -> void:
	var pb: PhysicalBone3D = c.ragdoll.bones.get(bone)
	if pb == null:
		return
	var from: Vector3 = game.player.camera.global_position
	var info := {collider = pb, position = pb.global_position, direction = (pb.global_position - from).normalized(), damage = dmg, impulse = 8.0, shot_id = randi(), weapon = "Pistol"}
	info.merge(extra, true)
	c.hit(info)


func _legshots() -> void:
	print("-- legshots")
	await _new_game(111)
	var deaths := 0
	var both := 0
	for i in 8:
		var c := await _alone("clown")
		for k in 12:
			if c.dead or c.broken_legs.size() >= 2:
				break
			_hit(c, [&"LeftUpperLeg", &"RightLowerLeg", &"LeftLowerLeg", &"RightUpperLeg"][k % 4], 34.0)
			await _frames(4)
		if c.dead:
			deaths += 1
		if c.broken_legs.size() >= 2:
			both += 1
	_check(deaths <= 1, "pistol rounds into the legs till both break rarely kill (%d of 8 dead)" % deaths)
	_check(both >= 6, "and break both legs (%d of 8)" % both)


func _last() -> void:
	print("-- last")
	await _new_game(222)
	for kind: String in ["gun", "clown"]:
		var c := await _alone(kind)
		var start := c.global_position
		for i in 6:
			if c.leg_out("Left"):
				break
			_hit(c, &"LeftLowerLeg", 34.0)
			await _frames(2)
		var was_down: bool = c.downed
		for i in 6:
			if c.leg_out("Right"):
				break
			_hit(c, &"RightLowerLeg", 34.0)
			await _frames(1)
		_check(was_down and c.broken_legs.size() == 2 and not c.dead, "%s: both legs broken, still alive (%s)" % [kind, c.broken_legs])
		var t := 0.0
		var ls: ClownLastStand = null
		var crawled := 0.0
		var sat_at := -1.0
		var shots_by := -1.0
		var getup := false
		var ls_at := -1.0
		var last_pts: Array[Vector3] = []
		var jump_at_start := 0.0
		var jumps: Array = []
		var worst_leg := 9.0
		var sit_jump := 0.0
		var sit_done := false
		var sit_yaw0 := INF
		var sat_yaw := INF
		var sit_spin := 0.0
		var head_wall := 9.0
		var hips_wall := -1.0
		var facing := 0.0
		while t < 30.0:
			await _frames(1)
			t += 1.0 / 60.0
			if c.dead:
				break
			if c._down_stage == 1:
				getup = true
			# how far any bone moves in one frame around the switch to crawling
			var pts: Array[Vector3] = []
			var sk := c.skeleton
			for bn: String in ["Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Hips"]:
				var bi := sk.find_bone(bn)
				pts.append(sk.global_transform * (c.ragdoll.bone_pose(bi).origin if c.ragdoll.active else sk.get_bone_global_pose(bi).origin))
			# legs below the floor (knee/ankle centres need ~5 cm, the limb's own thickness)
			if ls and not c.dead:
				var fy: float = game.maze.floor_height(c.global_position)
				for bn: String in ["LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]:
					var gy: float = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin).y
					worst_leg = minf(worst_leg, gy - fy)
			# no turning once it is down on its back or sat, and the wall behind it
			if ls and ls.stage == ClownLastStand.Phase.SIT:
				if sit_yaw0 == INF:
					sit_yaw0 = c.rotation.y
				var expect := sit_yaw0 + (PI if ls.sat else 0.0)
				if ls.sat:
					if sat_yaw == INF:
						sat_yaw = c.rotation.y
					expect = sat_yaw
				sit_spin = maxf(sit_spin, absf(angle_difference(c.rotation.y, expect)))
				if ls.wall_found:
					var hd: float = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin - ls._wall_hit).dot(ls._wall_n)
					head_wall = minf(head_wall, hd)
					if ls.sat:
						hips_wall = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin - ls._wall_hit).dot(ls._wall_n)
						var fwd := Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
						facing = fwd.dot(ls._wall_n)
			if ls and ls.stage == ClownLastStand.Phase.SIT and not ls.sat and not last_pts.is_empty():
				for k in pts.size():
					sit_jump = maxf(sit_jump, pts[k].distance_to(last_pts[k]))
			if ls and ls.sat and sit_jump >= 0.0 and not sit_done:
				sit_done = true
				for k in pts.size():
					sit_jump = maxf(sit_jump, pts[k].distance_to(last_pts[k]))
			if not last_pts.is_empty() and (ls_at < 0.0 or t < ls_at + 1.2):
				var jmp := 0.0
				for k in pts.size():
					jmp = maxf(jmp, pts[k].distance_to(last_pts[k]))
				jumps.append([t, jmp])
			last_pts = pts
			if false:
				await _shot("switch_%03d" % int(t * 10.0), c.global_position, c.global_position + Vector3(0, 2.0, 0) + Vector3(1.4, 0, 1.0))
			if ls == null:
				ls = c.get_node_or_null("LastStand") as ClownLastStand
				if ls:
					ls_at = t
					if not last_pts.is_empty():
						pass
			if ls:
				crawled = maxf(crawled, Vector2(c.global_position.x - start.x, c.global_position.z - start.z).length())
				if render and kind == "gun" and (ls.stage == ClownLastStand.Phase.TO_WALL or (ls.stage == ClownLastStand.Phase.SIT and not ls.sat)) and int(t * 60.0) % 12 == 0:
					await _shot("situp_%05d" % int(t * 100.0), c.global_position + Vector3.UP * 0.3, c.global_position + (ls._wall_n * 1.3 + ls._wall_n.cross(Vector3.UP) * 1.7 + Vector3.UP * 1.0) if ls.wall_found else c.global_position + Vector3(1.6, 1.0, 1.0))
				if ls.sat and sat_at < 0.0:
					sat_at = t
					await _shot("%s_sat" % kind, c.global_position + Vector3.UP * 0.5, c.global_position + (c.global_basis.z * 2.2) + Vector3.UP * 1.2)
				if ls.shots > 0 and shots_by < 0.0:
					shots_by = t
					await _shot("%s_firing" % kind, c.global_position + Vector3.UP * 0.6, c.global_position + (c.global_basis.z * 1.8 + c.global_basis.x * 0.8) + Vector3.UP * 0.9)
				if false:
					await _shot("switch_%03d" % int((t - ls_at) * 100.0 + 50), c.global_position, c.global_position + Vector3(0, 2.0, 0) + Vector3(1.4, 0, 1.0))
				if (kind == "gun" and shots_by > 0.0 and t > shots_by + 2.0) or (kind == "clown" and sat_at > 0.0 and t > sat_at + 2.0):
					break
		print("      %s: timeline: last stand began %.1fs" % [kind, ls_at])
		print("      %s: last stand %s, crawled %.1f m, wall found %s, sat at %.1fs, first shot at %.1fs" % [kind, ls != null, crawled, ls.wall_found if ls else false, sat_at, shots_by])
		_check(not getup and c.last_stand and ls != null, "%s: it does not get up; a last stand" % kind)
		for jv: Array in jumps:
			if ls_at > 0.0 and float(jv[0]) >= ls_at - 0.1 and float(jv[0]) <= ls_at + 1.2:
				jump_at_start = maxf(jump_at_start, float(jv[1]))
		_check(jump_at_start < 0.12, "%s: no snap from the ragdoll into the crawl (largest move in a frame %.2f m)" % [kind, jump_at_start])
		print("      %s: lowest knee/ankle centre %.3f m above the floor; largest move in a frame while sitting up %.3f m" % [kind, worst_leg, sit_jump])
		_check(worst_leg > 0.04, "%s: the legs never go into the floor (lowest knee/ankle %.3f m up)" % [kind, worst_leg])
		print("      %s: turned %.3f rad once on its back; head centre %.2f m from the wall at closest; hips %.2f m from it sat; facing out %.2f" % [kind, sit_spin, head_wall, hips_wall, facing])
		_check(sit_spin < 0.02, "%s: no spinning on its back or its backside (%.3f rad)" % [kind, sit_spin])
		_check(head_wall > 0.08 and hips_wall > 0.15 and hips_wall < 0.45 and facing > 0.97, "%s: sat with its back to the wall, square, head not in it (head %.2f, hips %.2f, facing %.2f)" % [kind, head_wall, hips_wall, facing])
		_check(render or sit_jump < 0.1, "%s: rolls over and sits up smoothly (largest move in a frame %.3f m)" % [kind, sit_jump])
		_check(crawled > 0.6, "%s: drags itself away (%.1f m)" % [kind, crawled])
		_check(sat_at > 0.0, "%s: sits up against something (%.1fs)" % [kind, sat_at])
		if kind == "gun":
			_check(shots_by > 0.0 and c.has_gun, "gun: a pistol out and shooting (%d shots)" % (ls.shots if ls else 0))
		else:
			_check(ls != null and ls.shots == 0, "clown without a gun: no shooting")
		# still killable, and it counts
		_hit(c, &"Chest", 400.0)
		await _frames(30)
		_check(c.dead and c.ragdoll.active, "%s: finished off, it goes limp" % kind)


func _klapper() -> void:
	print("-- klapper")
	await _new_game(333)
	var k := await _alone("klapper")
	for i in 14:
		if k.broken_legs.size() >= 2:
			break
		_hit(k, [&"LeftLowerLeg", &"RightLowerLeg"][i % 2], 40.0)
		await _frames(3)
	_check(k.broken_legs.size() == 2 and not k.dead, "Klappersoldat: both legs, still going (%s)" % [k.broken_legs])
	var t := 0.0
	var ls: ClownLastStand = null
	while t < 25.0 and not (ls and ls.sat):
		await _frames(1)
		t += 1.0 / 60.0
		if ls == null:
			ls = k.get_node_or_null("LastStand") as ClownLastStand
	_check(ls != null and ls.sat, "Klappersoldat: drags itself to a wall and sits (%.1fs)" % t)
	await _shot("klapper_sat", k.global_position + Vector3.UP * 0.5, k.global_position + k.global_basis.z * 2.4 + Vector3.UP * 1.2)


func _arms() -> void:
	print("-- arms")
	await _new_game(444)
	var c := await _alone("rifle")
	for i in 8:
		if c.broken_arms.has("Right"):
			break
		_hit(c, &"RightLowerArm", 34.0)
		await _frames(3)
	await _frames(20)
	var sk := c.skeleton
	var hand: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	var shoulder: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	print("      right arm %s; hand %.2f m below the shoulder; rifle %s, pistol in %s" % [c.broken_arms, shoulder.y - hand.y, c.has_rifle, c.gun_side])
	_check(c.broken_arms.has("Right"), "an arm breaks from rounds into it")
	_check(shoulder.y - hand.y > 0.35, "and dangles (hand %.2f m below the shoulder)" % (shoulder.y - hand.y))
	_check(not c.has_rifle and c.has_gun and c.gun_side == "Left", "the rifleman drops the rifle and draws a pistol left-handed")
	# it moves about: the dangling arm should swing well
	var lo := 9.0
	var hi := -9.0
	var b0: ClownBrain = c.get_node("Brain")
	b0.alert(game.player.global_position)
	for f in 240:
		await _frames(1)
		if f % 60 == 30:
			c.velocity = Vector3.ZERO           # pull up short now and then
		var hnd: Vector3 = c.global_basis.inverse() * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin - c.global_position)
		var sh: Vector3 = c.global_basis.inverse() * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin - c.global_position)
		var ang := atan2(hnd.z - sh.z, sh.y - hnd.y)
		lo = minf(lo, ang)
		hi = maxf(hi, ang)
	print("      dangling arm swung through %.0f deg while it moved about" % rad_to_deg(hi - lo))
	_check(rad_to_deg(hi - lo) > 30.0, "the broken arm swings with its movement (%.0f deg)" % rad_to_deg(hi - lo))
	await _shot("arm_dangle", c.global_position + Vector3.UP * 1.1, c.global_position + c.global_basis.z * 1.6 - c.global_basis.x * 0.9 + Vector3.UP * 1.3)
	for i in 8:
		if c.broken_arms.has("Left"):
			break
		_hit(c, &"LeftUpperArm", 34.0)
		await _frames(3)
	var b: ClownBrain = c.get_node("Brain")
	_check(c.broken_arms.size() == 2 and b.hiding and not c.has_gun, "both arms out: it stops fighting and goes to hide")
	var t := 0.0
	var start := c.global_position
	while t < 15.0 and not b.hidden:
		await _frames(1)
		t += 1.0 / 60.0
	var eye: Vector3 = game.player.global_position + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(eye, c.global_position + Vector3.UP * 0.8, 1)
	var out_of_sight := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	await _frames(40)
	print("      hidden after %.1fs, %.1f m from where it was, out of sight %s, crouched %.2f" % [t, c.global_position.distance_to(start), out_of_sight, c.crouch_amount])
	_check(b.hidden and c.global_position.distance_to(start) > 1.5, "it gets away to a hiding place (%.1f m)" % c.global_position.distance_to(start))
	_check(out_of_sight, "out of the player's sight")
	_check(c.crouch_amount > 0.8, "and cowers there")
	await _shot("hiding", c.global_position + Vector3.UP * 0.6, c.global_position - c.global_basis.z * 2.0 + Vector3.UP * 1.4)


func _blast() -> void:
	print("-- blast")
	await _new_game(555)
	var counts: Array[int] = []
	for i in 10:
		var c := await _alone("clown")
		c.caught_in_blast(c.global_position + c.global_basis.z * 1.3 + Vector3.UP * 0.6, 6.0)
		await _frames(10)
		if c._halved or c.crawling:
			counts.append(-1)                 # torn in half: the legs went with the bottom half
		else:
			counts.append(c.broken_legs.size() + c.broken_arms.size())
	var whole := counts.filter(func(n: int) -> bool: return n >= 0).size()
	var multi := counts.filter(func(n: int) -> bool: return n >= 2).size()
	print("      broken bones per clown 1.3 m from the blast (-1 = torn in half): %s" % [counts])
	_check(multi >= whole * 0.5, "an explosion close by usually breaks several bones at once (%d of %d in one piece)" % [multi, whole])
