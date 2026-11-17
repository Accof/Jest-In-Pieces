extends Node
## Der Zornhauptmann, checked. Sections (user args; none = all):
##   model     the body, the Pickelhaube (comes off), pistol and sabre, height,
##             a quarter more health than a WitzSoldat
##   combat    on a real floor: slow; the pistol raised in sight for 0.8-1.3 s;
##             a shot every 2-3 s; accurate; losing sight or a stagger stops
##             the aim; about one miss in seven makes him furious
##   sabre     a wind-up you can see; standing there you are cut, stepping
##             back or round him during the wind-up you are not; he is open
##             afterwards
##   odds      Last Defiance on about 80% of eligible deaths (300 kills);
##             never on headshots, explosions, a lost pistol arm, a shotgun
##             that takes limbs; the outcome weights, normalised
##   outcomes  each outcome forced several times: dead and counted at once,
##             1.8-2.5 s on his feet, the sideways slump, the pistol raised,
##             the trigger, the hand-over; what each one leaves behind;
##             nothing lingers
##   interrupt shot again before and after the trigger
##   floors    floors 2-6 of a real run: how many officers turn up; ten
##             seconds of each floor with them hunting the player
##   crowd     three officers dying at once, each his own way; a plain clown
##             and a Rattlejack beside them untouched
## Add "render" (with a window) for frames in /tmp/zh_*.png, "film" for the
## five outcomes filmed.

var render := false
var fails := 0
var game: Node3D


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
	get_viewport().get_texture().get_image().save_png("/tmp/zh_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["model", "combat", "sabre", "odds", "outcomes", "interrupt", "crowd", "floors", "film"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if s == "film" and not args.has("film"):
			continue
		if not any or args.has(s):
			await call("_" + s)
	print("ZORNHAUPTMANN: %d failed" % fails)
	get_tree().quit()


func _sandbox() -> Node3D:
	if game:
		game.queue_free()
		game = null
		await get_tree().process_frame
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


func _officer(room: Node3D, at: Vector3, yaw := 0.0) -> Zornhauptmann:
	var z := Zornhauptmann.new()
	z.max_health = 100.0
	room.add_child(z)
	z.give_officer_kit()
	z.position = at
	z.rotation.y = yaw
	return z


func _model() -> void:
	print("-- model")
	var room := await _sandbox()
	var z := _officer(room, Vector3(0, 0, -3))
	for i in 5:
		await get_tree().physics_frame
	var sk := z.skeleton
	_check(z.spec.model.ends_with("zornhauptmann.glb"), "wears the Zornhauptmann model")
	_check(sk.get_bone_count() >= 21 and sk.find_bone("Head") >= 0, "on the shared skeleton (%d bones)" % sk.get_bone_count())
	_check(z.has_helmet, "Pickelhaube on")
	_check(z.has_gun and z.gun_side == "Right" and z._muzzle != null, "pistol in the right hand, with a muzzle")
	_check(z.has_sabre() and z._sabre_side == "Left", "sabre in the left hand")
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var foot := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
	print("      head %.2f m up, ankle %.2f m; health %.0f; sabre tip %.2f m up" % [head.y - z.global_position.y, foot.y - z.global_position.y, z.max_health,
		(z._sabre.global_transform * Vector3(0, 0, 0.85)).y])
	_check(head.y > 1.45 and foot.y < 0.25, "stands about 1.9 m, feet on the floor")
	_check(absf(z.max_health - 125.0) < 0.5, "a quarter tougher than a WitzSoldat (%.0f)" % z.max_health)
	_check((z._sabre.global_transform * Vector3(0, 0, 0.85)).y > 0.02, "the sabre's point clears the floor")
	if render:
		var cam := Camera3D.new()
		add_child(cam)
		cam.make_current()
		cam.global_position = Vector3(1.4, 1.3, -1.2)
		cam.look_at(Vector3(0, 1.0, -3.0))
		await _shot("model")
		z.aim_point = z.global_position + z.global_basis.z * 5.0 + Vector3.UP * 1.3
		z.always_pose = true
		z.set_process(true)
		for f in 40:
			z.aim_amount = 1.0
			await get_tree().process_frame
		await _shot("model_aim")
		for k in 3:
			var a: float = [0.9, -0.6, 2.4][k]
			var sp := z.global_position + Vector3.UP * 1.35 + z.global_basis.x * -0.35
			cam.global_position = sp + Vector3(sin(a), 0.15, cos(a)).normalized() * 1.1
			cam.look_at(sp)
			for f in 5:
				z.aim_amount = 1.0
				await get_tree().process_frame
			await _shot("arm_%d" % k)
		cam.queue_free()
	# temper tantrums, one after another: the shoulders must come back each time
	var furious_was := z.furious_miss_chance
	z.furious_miss_chance = 1.0
	z.always_pose = true
	z.set_process(true)
	for k in 6:
		z._fury_t = -1.0
		z.missed()
		for f in 55:
			await get_tree().process_frame
	z.furious_miss_chance = furious_was
	var drift := 0.0
	for bi: int in z._rest:
		if z.skeleton.get_bone_name(bi).ends_with("Shoulder"):
			drift = maxf(drift, z.skeleton.get_bone_pose_rotation(bi).angle_to(z._rest[bi]))
	_check(drift < 0.02, "six tempers later the shoulders are back where they were (%.3f rad)" % drift)
	var neck: PhysicalBone3D = z.ragdoll.bones[&"Neck"]
	z.knock_off_helmet(Vector3(0, 0, -1), neck.global_position)
	_check(not z.has_helmet, "the Pickelhaube can be shot off")
	# the brain, when the skull is opened, inside it
	z.gore._show_innards(&"head")
	await get_tree().process_frame
	var holder: Node3D = z.gore._innards[&"head"]
	var top := -INF
	for mi in holder.get_children():
		var aabb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		top = maxf(top, aabb.end.y)
	var crown := z.global_position.y + 1.692
	print("      opened skull: insides reach %.3f m, the skull's crown %.3f m" % [top - z.global_position.y, crown - z.global_position.y])
	_check(top <= crown + 0.005, "the brain fits inside his skull")
	if render:
		var cam2 := Camera3D.new()
		add_child(cam2)
		cam2.make_current()
		cam2.fov = 30.0
		for k in 3:
			var a: float = [0.5, 1.6, 3.0][k]
			var hp := z.global_position + Vector3.UP * 1.62
			cam2.global_position = hp + Vector3(sin(a), 0.25, cos(a)).normalized() * 1.0
			cam2.look_at(hp)
			for f in 30:
				await get_tree().process_frame
			await _shot("bare_%d" % k)
		cam2.queue_free()
	z.queue_free()
	await get_tree().physics_frame


func _floor() -> Array:
	if game == null:
		for n in get_children():
			if n.name == "Room":
				n.queue_free()
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
	game.start_run()
	game.floor_number = 2
	game.next_floor()
	await get_tree().physics_frame
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await get_tree().physics_frame
	var player: FpsPlayer = game.player
	var maze: Maze = game.maze
	var spot := Vector3.INF
	for c: Vector2i in maze.cells_far_from(maze.start_cell, 1):
		var p := maze.cell_center(c)
		var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.3, p + Vector3.UP * 1.3, 1)
		var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		if get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty() and d > 5.0 and d < 10.0:
			spot = p
			break
	if spot == Vector3.INF:
		spot = player.global_position + Vector3(0, 0, 6)
	return [player, spot]


func _combat() -> void:
	print("-- combat")
	var fp := await _floor()
	var player: FpsPlayer = fp[0]
	var spot: Vector3 = fp[1]
	player.god_mode = false
	player.health = 100000.0
	var z: Zornhauptmann = game.spawn_zornhauptmann()
	var brain := z.get_node("Brain") as ClownBrain
	z.global_position = spot
	z.look_at(Vector3(player.global_position.x, spot.y, player.global_position.z), Vector3.UP, true)
	var h0 := player.health
	var t := 0.0
	var shots: Array = []
	var raise_start := -1.0
	var raises: Array = []
	var last_shot := -1.0
	var was_aiming := false
	var max_speed := 0.0
	var last_pos := z.global_position
	var furious0 := z.furious
	var shot_count := 0
	while t < 40.0:
		brain.alert(player.global_position)
		player.velocity = Vector3.ZERO
		var shots_before := z.pistol_shots
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if OS.get_cmdline_user_args().has("dbg") and int(t * 60) % 20 == 0:
			print("        t %.2f mind %d seen %s aim_t %.2f aim %.2f cool %.2f dist %.2f backing %s backoff %.2f unseen %.2f attack %.2f" % [t, brain.mind, brain._can_see_player(), brain._aim_t, z.aim_amount, brain._cooldown, Vector2(player.global_position.x - z.global_position.x, player.global_position.z - z.global_position.z).length(), brain.backing, brain._backoff, brain._unseen, brain._attack_t])
		var sp := Vector2(z.global_position.x - last_pos.x, z.global_position.z - last_pos.z).length() / dt
		last_pos = z.global_position
		if t > 1.0:
			max_speed = maxf(max_speed, sp)
		if z.aim_amount > 0.1 and not was_aiming:
			raise_start = t
		was_aiming = z.aim_amount > 0.1
		if z.pistol_shots > shots_before:
			shot_count += 1
			if raise_start >= 0.0:
				raises.append(t - raise_start)
			if last_shot >= 0.0:
				shots.append(t - last_shot)
			last_shot = t
	var dmg := h0 - player.health
	var mean_gap := 0.0
	for g: float in shots:
		mean_gap += g
	mean_gap /= maxf(shots.size(), 1)
	var mean_raise := 0.0
	for r: float in raises:
		mean_raise += r
	mean_raise /= maxf(raises.size(), 1)
	var hits := roundi(dmg / z.pistol_damage)
	print("      %d shots in 40 s, gaps %s (mean %.2f s); raise-to-shot %s (mean %.2f s); %d hits (%.0f%%), %d misses, furious %d; top speed %.2f m/s" % [
		shot_count, str(shots.map(func(x: float) -> String: return "%.1f" % x)), mean_gap, str(raises.map(func(x: float) -> String: return "%.2f" % x)), mean_raise,
		hits, 100.0 * hits / maxf(shot_count, 1), brain.misses, z.furious - furious0, max_speed])
	_check(shot_count >= 10, "fires steadily (%d shots)" % shot_count)
	# (the median: a gap where he lost sight of the player, or a raise that
	# ran across a broken aim, is not the rhythm)
	var sg := shots.duplicate()
	sg.sort()
	var med: float = sg[sg.size() / 2] if not sg.is_empty() else 0.0
	_check(med >= 2.0 and med <= 3.2, "a shot every 2-3 seconds (median %.2f)" % med)
	var good := 0
	for r: float in raises:
		if r >= 0.7 and r <= 1.4:          # from the first visible lift
			good += 1
	_check(not raises.is_empty() and good >= 0.8 * raises.size(), "the pistol is up in sight 0.8-1.3 s before the shot (%d of %d)" % [good, raises.size()])
	_check(float(hits) / maxf(shot_count, 1) > 0.4, "accurate (%d of %d; 70-80%% expected at this range)" % [hits, shot_count])
	_check(max_speed < 2.3, "slow and deliberate (top %.2f m/s)" % max_speed)
	# losing sight stops the aim
	var stopped_sight := 0
	var stopped_stagger := 0
	for trial in 2:
		for k in 2:
			brain._cooldown = 0.0
			var n := 0
			while brain._aim_t < 0.3 and n < 400:
				brain.alert(player.global_position)
				await get_tree().physics_frame
				n += 1
			var aim_shots := z._shot_t
			if k == 0:
				var keep := player.global_position
				player.global_position = keep + Vector3(0, 40.0, 0)        # out of sight
				for f in 90:
					await get_tree().physics_frame
				if z._shot_t >= aim_shots + 1.0 and brain._aim_t < 0.0:
					stopped_sight += 1
				player.global_position = keep
			else:
				z.stagger_time = 0.6
				for f in 20:
					await get_tree().physics_frame
				if z._shot_t >= aim_shots + 0.3 and brain._aim_t < 0.0:
					stopped_stagger += 1
			for f in 30:
				await get_tree().physics_frame
	_check(stopped_sight == 2, "breaking line of sight stops the shot (%d of 2)" % stopped_sight)
	_check(stopped_stagger == 2, "a stagger stops the shot (%d of 2)" % stopped_stagger)
	# temper: of many misses, about 15% make him furious
	var n_f := 0
	var n_m := 0
	for i in 400:
		z._fury_t = -1.0
		var d := z.missed()
		n_m += 1
		if d > 0.0:
			n_f += 1
	z._fury_t = -1.0
	print("      furious on %d of %d misses" % [n_f, n_m])
	_check(n_f > 0.09 * n_m and n_f < 0.21 * n_m, "furious on about 15%% of misses (%.1f%%)" % (100.0 * n_f / n_m))
	z.queue_free()
	await get_tree().physics_frame


func _sabre() -> void:
	print("-- sabre")
	var fp := await _floor()
	var player: FpsPlayer = fp[0]
	var spot: Vector3 = fp[1]
	player.god_mode = false
	var results := {}
	for mode: String in ["stand", "step_back", "step_round"]:
		player.health = 1000.0
		var z: Zornhauptmann = game.spawn_zornhauptmann()
		var brain := z.get_node("Brain") as ClownBrain
		var fwd := Vector3(player.global_position.x - spot.x, 0, player.global_position.z - spot.z).normalized()
		z.global_position = player.global_position - fwd * 1.5
		z.global_position.y = spot.y
		z.look_at(Vector3(player.global_position.x, z.global_position.y, player.global_position.z), Vector3.UP, true)
		var p0 := player.global_position
		var h0 := player.health
		var t := 0.0
		var started := -1.0
		var hand_rise := 0.0
		var hand0 := -1.0
		var dodged := false
		var hits := 0.0
		var swung := 0
		while t < 3.0:
			brain.alert(player.global_position)
			player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var state := "t %.2f mind %d react %.2f attack %.2f cool %.2f dist %.2f dy %.2f aim %.2f unseen %.2f stagger %.2f dead %s pdead %s" % [t, brain.mind, brain._react, brain._attack_t, brain._cooldown, Vector2(player.global_position.x - z.global_position.x, player.global_position.z - z.global_position.z).length(), player.global_position.y - z.global_position.y, brain._aim_t, brain._unseen, z.stagger_time, z.dead, player.dead]
			if started < 0.0 and t > 1.4 and t < 1.42:
				print("        stuck? " + state)
			if OS.get_cmdline_user_args().has("dbg") and int(t * 60) % 15 == 0:
				print("        t %.2f mind %d react %.2f attack %.2f cool %.2f dist %.2f dy %.2f aim %.2f unseen %.2f stagger %.2f" % [t, brain.mind, brain._react, brain._attack_t, brain._cooldown, Vector2(player.global_position.x - z.global_position.x, player.global_position.z - z.global_position.z).length(), player.global_position.y - z.global_position.y, brain._aim_t, brain._unseen, z.stagger_time])
			if brain._attack_t >= 0.0 and started < 0.0:
				started = t
				swung = z.sabre_swings
			if started >= 0.0:
				var hb := z.skeleton.find_bone("LeftHand")
				var hp := z.skeleton.global_transform * z.skeleton.get_bone_global_pose(hb).origin
				if hand0 < 0.0:
					hand0 = hp.y
				if z.swing_kind == "slash":
					hand_rise = maxf(hand_rise, hp.y - hand0)
				else:
					var back := (z.global_basis.inverse() * (hp - z.global_position)).z
					hand_rise = maxf(hand_rise, -back)
				# dodge half-way through the wind-up
				if not dodged and t - started > z.sabre_windup * 0.5 and mode != "stand":
					dodged = true
					if mode == "step_back":
						player.global_position = p0 + fwd * 1.6
					else:
						player.global_position = p0 + Vector3(fwd.z, 0, -fwd.x) * 1.7
				if t - started > z.sabre_windup + z.sabre_strike + 0.2:
					break
		hits = h0 - player.health
		results[mode] = hits
		print("      %s: swing %s (%s), tell %.2f m, damage %.0f" % [mode, "started" if started >= 0.0 else "never", z.swing_kind, hand_rise, hits])
		_check(started >= 0.0 and z.sabre_swings > 0, "%s: he swings at close range" % mode)
		_check(hand_rise > 0.15, "%s: a wind-up you can see (%.2f m)" % [mode, hand_rise])
		if mode == "stand":
			_check(hits > 0.0, "stand there: cut (%.0f)" % hits)
		else:
			_check(hits <= 0.0, "%s during the wind-up: missed" % mode)
		player.global_position = p0
		z.queue_free()
		await get_tree().physics_frame
	# the recovery: open for a while after the swing
	var b := ClownBrain.new()
	var zz := Zornhauptmann.new()
	zz.setup_brain(b)
	_check(b.attack_time - b.attack_hit_at > 0.5, "open after the swing (%.2f s from the cut to the end)" % (b.attack_time - b.attack_hit_at))
	_check(b.attack_hit_at >= 0.55, "the cut lands no sooner than %.2f s after the wind-up starts" % b.attack_hit_at)
	b.free()
	zz.free()


## Kill one officer with a chest round; returns whether it was a Last Defiance.
func _kill(z: Zornhauptmann, zone: StringName = &"Chest", extra := {}) -> void:
	var pb: PhysicalBone3D = z.ragdoll.bones[zone]
	var front := z.global_basis.z
	var info := {collider = pb, position = pb.global_position + front * 0.1, direction = -front + z.global_basis.x * 0.3, damage = 30.0, impulse = 10.0, weapon = "Pistol", shot_id = randi()}
	info.merge(extra, true)
	z.health = 1.0
	z.hit(info)


func _odds() -> void:
	print("-- odds")
	var room := await _sandbox()
	var n := 300
	var act := 0
	var eligible := 0
	for i in n:
		var z := _officer(room, Vector3(0, 0, -3))
		await get_tree().physics_frame
		_kill(z)
		if z.defiance_eligible:
			eligible += 1
		if z.dying == "defiance":
			act += 1
		z.queue_free()
		if i % 20 == 19:
			await get_tree().physics_frame
	print("      Last Defiance on %d of %d eligible kills (%.1f%%)" % [act, eligible, 100.0 * act / maxf(eligible, 1)])
	_check(eligible == n, "every chest kill on his feet is eligible (%d)" % eligible)
	var want := Zornhauptmann.new()
	var ch := want.last_defiance_chance
	want.free()
	_check(act > (ch - 0.08) * n and act < (ch + 0.08) * n, "about %.0f%% (%.1f%%)" % [ch * 100.0, 100.0 * act / n])
	# never on these
	var cases := {
		"headshot": [&"Neck", {}],
		"explosion": [&"Chest", {blast = true}],
		"shotgun dismemberment": [&"Chest", {can_dismember = true, damage = 80.0}],
	}
	for name_: String in cases:
		var z := _officer(room, Vector3(0, 0, -3))
		await get_tree().physics_frame
		z.force_death = "defiance"
		var c: Array = cases[name_]
		_kill(z, c[0], c[1])
		_check(z.dead and z.dying == "" and z.ragdoll.active, "%s: never a Last Defiance (straight to the ragdoll)" % name_)
		z.queue_free()
	# what the player's own guns send: rifle and shotgun rounds are heavy, still fine
	for gun: Array in [["Rifle", {heavy = true, damage = 180.0}], ["Shotgun pellet", {heavy = true, can_dismember = true, damage = 16.0}], ["SMG", {damage = 21.0}]]:
		var zg := _officer(room, Vector3(0, 0, -3))
		await get_tree().physics_frame
		zg.force_death = "defiance"
		_kill(zg, &"Chest", gun[1])
		_check(zg.dying == "defiance", "%s kill: can be a Last Defiance" % gun[0])
		if gun[0] == "SMG":
			# the trigger is still held: three more rounds in the next quarter second
			for k in 3:
				for f in 5:
					await get_tree().physics_frame
				var pb: PhysicalBone3D = zg.ragdoll.bones[&"Chest"]
				zg.hit({collider = pb, position = pb.global_position, direction = -zg.global_basis.z, damage = 21.0, impulse = 8.0, weapon = "SMG", shot_id = randi()})
			_check(zg.dying == "defiance" and not zg.defiance_interrupted, "SMG: the rounds right after the kill do not cut it short")
		zg.queue_free()
	Zornhauptmann.always_defiance = true
	var za := _officer(room, Vector3(0, 0, -3))
	await get_tree().physics_frame
	_kill(za)
	_check(za.dying == "defiance", "the L key (always_defiance) makes every eligible kill one")
	Zornhauptmann.always_defiance = false
	za.queue_free()
	var z2 := _officer(room, Vector3(0, 0, -3))
	await get_tree().physics_frame
	z2._arm_lost("Right")
	z2.force_death = "defiance"
	_kill(z2)
	_check(z2.dead and z2.dying == "" and not z2.has_gun, "pistol arm gone: never a Last Defiance")
	z2.queue_free()
	var z3 := _officer(room, Vector3(0, 0, -3))
	await get_tree().physics_frame
	z3.enable_last_defiance = false
	z3.force_death = "defiance"
	_kill(z3)
	_check(z3.dying == "", "switched off: never")
	z3.queue_free()
	# the weights, normalised
	var w := Zornhauptmann.new()
	var counts := {}
	var N := 40000
	for i in N:
		var o := w._pick_outcome()
		counts[o] = counts.get(o, 0) + 1
	var odds := w.outcome_odds()
	var worst := 0.0
	for k: String in Zornhauptmann.OUTCOMES:
		worst = maxf(worst, absf(float(counts.get(k, 0)) / N - float(odds[k])))
	print("      outcomes over %d: %s" % [N, str(Zornhauptmann.OUTCOMES.map(func(k: String) -> String: return "%s %.1f%%" % [k, 100.0 * counts.get(k, 0) / N]))])
	_check(worst < 0.01, "outcomes follow the weights (worst %.3f off)" % worst)
	w.real_shot_weight = 2.0
	w.fail_to_fire_weight = 2.0
	w.bang_flag_weight = 0.0
	w.confetti_weight = 0.0
	w.bubbles_weight = 0.0
	var o2 := w.outcome_odds()
	_check(absf(o2.real_shot - 0.5) < 0.001 and o2.bang_flag == 0.0, "weights are normalised (2:2:0:0:0 -> 50/50)")
	w.free()


## One forced Last Defiance; returns what was measured.
func _one(room: Node3D, outcome: String, at: Vector3, name_ := "", interrupt_at := -1.0) -> Dictionary:
	var z := _officer(room, at)
	for i in 12:
		await get_tree().physics_frame
	var deaths := [0]
	z.died.connect(func(_c: Clown) -> void: deaths[0] += 1)
	z.force_death = "defiance"
	z.force_outcome = outcome
	_kill(z)
	var out := {dead = z.dead, ragdoll_at_once = z.ragdoll.active, dying = z.dying, outcome = z.defiance_outcome}
	var sk := z.skeleton
	var hips0 := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var t := 0.0
	var max_side := 0.0
	var hand_low := 9.0
	var hand_high := -9.0
	var hand_at_fire := -9.0
	var head_drop := 0.0
	var head0 := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin).y
	var flag_drift := 0.0
	var flag_seen := false
	var vfx_peak := 0
	var interrupted := false
	var frame := 0
	var shots0 := z._shot_t
	var flashes := 0
	var last_shot_t := z._shot_t
	while t < 4.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		frame += 1
		if interrupt_at > 0.0 and not interrupted and t >= interrupt_at:
			interrupted = true
			var pb: PhysicalBone3D = z.ragdoll.bones[&"Chest"]
			z.hit({collider = pb, position = pb.global_position, direction = -z.global_basis.z, damage = 20.0, impulse = 8.0, weapon = "Pistol", shot_id = randi()})
		if z._shot_t < last_shot_t:
			flashes += 1
		last_shot_t = z._shot_t
		if not z.handed_over:
			var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
			var side := (z.global_basis.inverse() * (hips - hips0)).x * z._slump
			max_side = maxf(max_side, side)
			var hp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
			if t > 0.4 and t < 0.9:
				hand_low = minf(hand_low, hp.y)
			if z.defiance_fired_at >= 0.0 and hand_at_fire < -1.0:
				hand_at_fire = hp.y
			hand_high = maxf(hand_high, hp.y)
			var hy := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin).y
			head_drop = maxf(head_drop, head0 - hy)
		if z.flag and is_instance_valid(z.flag):
			flag_seen = true
			if z.handed_over and z._muzzle and is_instance_valid(z._muzzle):
				flag_drift = maxf(flag_drift, z.flag.global_position.distance_to(z._muzzle.global_position))
		vfx_peak = maxi(vfx_peak, get_tree().get_nodes_in_group(&"zorn_vfx").size())
		if render and name_ != "" and frame % 3 == 0 and t < 3.4:
			await _shot("%s_%03d" % [name_, frame])
	out.deaths = deaths[0]
	out.handover = z.handover_at
	out.fired_at = z.defiance_fired_at
	out.events = z.defiance_events.map(func(e: Array) -> String: return "%s@%.2f" % [e[1], e[0]])
	out.side = max_side
	out.raise = hand_at_fire - hand_low if hand_at_fire > -1.0 else 0.0
	out.head_drop = head_drop
	out.real_shots = z.real_shots
	out.real_result = z.real_shot_result
	out.flashes = flashes
	out.flag = flag_seen
	out.flag_on = z.flag != null and is_instance_valid(z.flag)
	out.flag_drift = flag_drift
	out.vfx_peak = vfx_peak
	out.pose_error = z.handover_pose_error
	out.interrupted = z.defiance_interrupted
	out.foot_slip = z.foot_slip
	var flag_ref := z.flag
	z.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	out.flag_freed = flag_ref == null or not is_instance_valid(flag_ref)
	# what was spawned runs out its life and goes (confetti 3 s, bubbles under 4 s)
	var w := 0.0
	while w < 4.0 and get_tree().get_nodes_in_group(&"zorn_vfx").size() > 0:
		await get_tree().physics_frame
		w += get_physics_process_delta_time()
	out.vfx_left = get_tree().get_nodes_in_group(&"zorn_vfx").size()
	out.vfx_gone_after = w
	return out


func _outcomes() -> void:
	print("-- outcomes")
	var room := await _sandbox()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(2.4, 1.4, -0.8)
	cam.look_at(Vector3(0, 1.0, -3.0))
	for outcome: String in Zornhauptmann.OUTCOMES:
		for i in 2:
			var o := await _one(room, outcome, Vector3(0, 0, -3), (outcome if i == 0 else ""))
			print("      %s %d: %s; fired %.2fs, handover %.2fs; slump %.3f m, pistol up %.2f m, head down %.2f m; shots %d (%s), flashes %d; flag %s/%s drift %.3f; vfx %d (left %d); pose error %.3f, foot slip %.3f" % [
				outcome, i, str(o.events), o.fired_at, o.handover, o.side, o.raise, o.head_drop, o.real_shots, o.real_result, o.flashes, o.flag, o.flag_on, o.flag_drift, o.vfx_peak, o.vfx_left, o.pose_error, o.foot_slip])
			_check(o.dead and not o.ragdoll_at_once and o.dying == "defiance" and o.deaths == 1, "%s %d: dead and counted at once, playing it out" % [outcome, i])
			_check(o.outcome == outcome, "%s %d: the forced outcome" % [outcome, i])
			_check(o.handover >= 1.75 and o.handover <= 2.55, "%s %d: on his feet 1.8-2.5 s (%.2f)" % [outcome, i, o.handover])
			_check(o.fired_at >= 1.25 and o.fired_at <= 1.9 and o.fired_at < o.handover, "%s %d: the trigger after the raise, before the fall (%.2f)" % [outcome, i, o.fired_at])
			_check(o.side > 0.02, "%s %d: slumps to one side (%.3f m)" % [outcome, i, o.side])
			_check(o.head_drop > 0.04, "%s %d: the head hangs (%.2f m)" % [outcome, i, o.head_drop])
			_check(o.raise > 0.25, "%s %d: the pistol comes up (%.2f m)" % [outcome, i, o.raise])
			_check(o.pose_error < 0.06, "%s %d: no snap into the ragdoll (%.3f)" % [outcome, i, o.pose_error])
			_check(o.foot_slip < 0.04, "%s %d: planted feet stay put (%.3f m)" % [outcome, i, o.foot_slip])
			match outcome:
				"real_shot":
					_check(o.real_shots == 1 and o.flashes == 1 and o.real_result != "", "real shot: exactly one round, a flash (%d, %d)" % [o.real_shots, o.flashes])
				"fail_to_fire":
					_check(o.real_shots == 0 and o.flashes == 0 and not o.flag and o.vfx_peak == 0, "fails to fire: nothing comes out")
				"bang_flag":
					_check(o.real_shots == 0 and o.flashes == 0, "flag: no round, no flash")
					_check(o.flag and o.flag_on, "flag: out, and still on the pistol at the end")
					_check(o.flag_drift < 0.02, "flag: rides the muzzle through the ragdoll (%.3f m)" % o.flag_drift)
					_check(o.flag_freed, "flag: goes with him")
				"confetti":
					_check(o.real_shots == 0 and o.vfx_peak >= 1, "confetti: a burst, no round")
				"bubbles":
					_check(o.real_shots == 0 and o.vfx_peak >= 3 and o.vfx_peak <= 7, "bubbles: 3-7 of them (%d)" % o.vfx_peak)
			_check(o.vfx_left == 0, "%s %d: nothing lingers (%d)" % [outcome, i, o.vfx_left])
	cam.queue_free()


func _interrupt() -> void:
	print("-- interrupt")
	var room := await _sandbox()
	var o := await _one(room, "bang_flag", Vector3(0, 0, -3), "", 0.8)
	print("      before the trigger: %s; handover %.2fs; deaths %d" % [str(o.events), o.handover, o.deaths])
	_check(o.interrupted and o.handover < 0.9 and o.fired_at < 0.0, "shot again before the trigger: straight to the ragdoll, no gag")
	_check(o.deaths == 1, "the kill still counted once (%d)" % o.deaths)
	_check(not o.flag, "no flag")
	# the trigger first, then shoot him
	var o3 := await _one(room, "bang_flag", Vector3(0, 0, -3), "", 1.95)
	print("      after the trigger: %s; handover %.2fs; flag on %s, drift %.3f" % [str(o3.events), o3.handover, o3.flag_on, o3.flag_drift])
	if o3.fired_at > 0.0 and o3.fired_at < 1.95:
		_check(o3.flag_on and o3.flag_drift < 0.02, "shot again after the flag is out: the flag stays on the pistol")
	_check(o3.deaths == 1, "counted once (%d)" % o3.deaths)
	var o4 := await _one(room, "bubbles", Vector3(0, 0, -3), "", 1.9)
	print("      bubbles then shot: %s; vfx peak %d, left %d" % [str(o4.events), o4.vfx_peak, o4.vfx_left])
	_check(o4.vfx_left == 0, "what was already out runs its course and goes")


func _crowd() -> void:
	print("-- crowd")
	var room := await _sandbox()
	var zs: Array[Zornhauptmann] = []
	var outcomes := ["real_shot", "bang_flag", "bubbles"]
	for i in 3:
		var z := _officer(room, Vector3(-2.0 + 2.0 * i, 0, -3.5))
		z.force_death = "defiance"
		z.force_outcome = outcomes[i]
		zs.append(z)
	var plain := Clown.new()
	room.add_child(plain)
	plain.position = Vector3(-3.5, 0, -1.0)
	var rj := Rattlejack.new()
	room.add_child(rj)
	rj.give_rifle()
	rj.position = Vector3(3.5, 0, -1.0)
	for f in 12:
		await get_tree().physics_frame
	var deaths := [0]
	for z in zs:
		z.died.connect(func(_c: Clown) -> void: deaths[0] += 1)
		_kill(z)
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var ok := true
	var fired: Array = []
	for i in 3:
		var z := zs[i]
		ok = ok and z.defiance_outcome == outcomes[i] and z.handed_over
		fired.append("%.2f" % z.defiance_fired_at)
	print("      outcomes %s, fired at %s, deaths %d; plain clown %.0f hp dead %s, Rattlejack %.0f hp dead %s" % [str(zs.map(func(z: Zornhauptmann) -> String: return z.defiance_outcome)), str(fired), deaths[0], plain.health, plain.dead, rj.health, rj.dead])
	_check(ok and deaths[0] == 3, "three officers, each his own Last Defiance, each counted once")
	_check(zs[0].real_shots == 1 and zs[1].real_shots == 0 and zs[2].real_shots == 0, "only the one that fired a real round did")
	_check(zs[1].flag != null and is_instance_valid(zs[1].flag) and (zs[0].flag == null) and (zs[2].flag == null), "only the flag man has a flag")
	_check(not plain.dead and not rj.dead and rj.dying == "" and plain.health == plain.max_health, "a plain clown and a Rattlejack beside them carry on as before")
	for z in zs:
		z.queue_free()
	plain.queue_free()
	rj.queue_free()
	await get_tree().physics_frame


func _floors() -> void:
	print("-- floors")
	if game == null:
		for n in get_children():
			if n.name == "Room":
				n.queue_free()
		Engine.set_meta(&"test_save", true)
		game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
	seed(5190)
	game.rng.seed = 5190
	game.start_run()
	var counts: Array = []
	var total := 0
	var all := 0
	for f in range(2, 7):
		game.floor_number = f
		game.next_floor()
		await get_tree().physics_frame
		var n := 0
		for c: Clown in game.clowns:
			if c is Zornhauptmann:
				n += 1
				(c.get_node("Brain") as ClownBrain).alert(game.player.global_position)
		counts.append(n)
		total += n
		all += game.clowns.size()
		game.player.god_mode = true
		for i in 600:
			await get_tree().physics_frame
	print("      officers on floors 2-6: %s (%d of %d enemies)" % [str(counts), total, all])
	_check(total > 0, "officers turn up from floor 2")
	_check(float(total) / all < 0.25, "but not too many (%.0f%%)" % (100.0 * total / all))


func _film() -> void:
	print("-- film")
	var room := await _sandbox()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(1.7, 1.35, -1.3)
	cam.look_at(Vector3(0, 1.05, -3.0))
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	if OS.get_cmdline_user_args().has("front"):
		cam.global_position = Vector3(0.3, 1.5, -1.0)
		cam.look_at(Vector3(0, 1.2, -3.0))
	for outcome: String in Zornhauptmann.OUTCOMES:
		if only == "" or only == outcome:
			await _one(room, outcome, Vector3(0, 0, -3), "film_" + outcome)
