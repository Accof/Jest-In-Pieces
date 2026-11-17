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
		while t < 30.0:
			await _frames(1)
			t += 1.0 / 60.0
			if c.dead:
				break
			if c._down_stage == 1:
				getup = true
			if ls == null:
				ls = c.get_node_or_null("LastStand") as ClownLastStand
				if ls:
					ls_at = t
			if ls:
				crawled = maxf(crawled, Vector2(c.global_position.x - start.x, c.global_position.z - start.z).length())
				if ls.sat and sat_at < 0.0:
					sat_at = t
					await _shot("%s_sat" % kind, c.global_position + Vector3.UP * 0.5, c.global_position + (c.global_basis.z * 2.2) + Vector3.UP * 1.2)
				if ls.shots > 0 and shots_by < 0.0:
					shots_by = t
					await _shot("%s_firing" % kind, c.global_position + Vector3.UP * 0.6, c.global_position + (c.global_basis.z * 1.8 + c.global_basis.x * 0.8) + Vector3.UP * 0.9)
				if render and int(t * 60.0) % 90 == 0 and not ls.sat:
					await _shot("%s_crawl_%02d" % [kind, int(t)], c.global_position, c.global_position + Vector3(0, 2.4, 0) + c.global_basis.x * 1.6)
				if (kind == "gun" and shots_by > 0.0 and t > shots_by + 2.0) or (kind == "clown" and sat_at > 0.0 and t > sat_at + 2.0):
					break
		print("      %s: timeline: last stand began %.1fs" % [kind, ls_at])
		print("      %s: last stand %s, crawled %.1f m, wall found %s, sat at %.1fs, first shot at %.1fs" % [kind, ls != null, crawled, ls.wall_found if ls else false, sat_at, shots_by])
		_check(not getup and c.last_stand and ls != null, "%s: it does not get up; a last stand" % kind)
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
