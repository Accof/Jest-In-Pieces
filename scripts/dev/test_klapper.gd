extends Node
## Der Klappersoldat, checked. Sections (pass one or more as user args; none = all):
##   walk   hunts the player along a real floor: speed against an ordinary
##          clown's, top speed, how far the knees bend, how much the planted
##          foot slides, head snaps, hesitations, getting there (navigation)
##   fight  stands by the player: the blow's timing and damage, staggers
##   gore   in the gore sandbox: chest worn open (panel, then gears), an arm
##          blown off (mechanical gib and stump), the face broken, death,
##          the oil puddle (and that it outlives the corpse), and an ordinary
##          clown still bleeding blood and showing meat
##   crowd  six at once, for frame time
##   film   (with "render") a walk, the blow and idling, side on, in the lit
##          gore sandbox, as numbered frames /tmp/klap_film_*.png
## Add "render" (with a window) to save pictures to /tmp/klap_*.png.

var game: Node3D
var render := false
var fails := 0


func _ready() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("   ok    " if ok else "   FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/klap_%s.png" % name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var all := not (args.has("walk") or args.has("fight") or args.has("gore") or args.has("crowd") or args.has("film"))
	if args.has("film"):
		await _film()
	if all or args.has("walk"):
		await _walk()
	if all or args.has("fight"):
		await _fight()
	if all or args.has("crowd"):
		await _crowd()
	if all or args.has("gore"):
		await _gore()
	print("KLAPPER: %d failed" % fails)
	get_tree().quit()


func _floor() -> void:
	if game == null:
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


func _angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


## Walk one enemy toward the player and measure it.
func _measure(c: Clown, target: Vector3, seconds: float) -> Dictionary:
	var brain := c.get_node("Brain") as ClownBrain
	var sk := c.skeleton
	var out := {travel = 0.0, time = 0.0, top = 0.0, knee_min = 999.0, knee_max = 0.0, ankle_min = 999.0, ankle_max = 0.0,
		elbow_min = 999.0, slide = 0.0, moving_time = 0.0, snaps = 0, reached = false, still_frames = 0, frames = 0}
	var last := c.global_position
	var feet := {}
	var last_yaw := 0.0
	var fast := false
	var t := 0.0
	var speeds: Array[float] = []
	while t < seconds:
		brain.alert(target)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if not is_instance_valid(c) or c.dead:
			break
		var p := c.global_position
		var step := Vector2(p.x - last.x, p.z - last.z).length()
		last = p
		out.travel += step
		out.frames += 1
		var v := step / dt
		speeds.append(v)
		out.top = maxf(out.top, v)
		if v < 0.05:
			out.still_frames += 1
		var g := sk.global_transform
		var lowest := ""
		var low_y := 99.0
		for side: String in ["Left", "Right"]:
			var hip := g * sk.get_bone_global_pose(sk.find_bone(side + "UpperLeg")).origin
			var knee := g * sk.get_bone_global_pose(sk.find_bone(side + "LowerLeg")).origin
			var ankle := g * sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
			var foot_b := g.basis * sk.get_bone_global_pose(sk.find_bone(side + "Foot")).basis
			var shin := ankle - knee
			var ka := _angle(knee - hip, shin)
			out.knee_min = minf(out.knee_min, ka)
			out.knee_max = maxf(out.knee_max, ka)
			var aa := _angle(shin, foot_b.y)
			out.ankle_min = minf(out.ankle_min, aa)
			out.ankle_max = maxf(out.ankle_max, aa)
			if ankle.y < low_y:
				low_y = ankle.y
				lowest = side
			var sh := g * sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
			var el := g * sk.get_bone_global_pose(sk.find_bone(side + "LowerArm")).origin
			var wr := g * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
			out.elbow_min = minf(out.elbow_min, _angle(el - sh, wr - el))
			var s := 1.0 if side == "Left" else -1.0
			var stance := -cos(c.walk_phase) * s > 0.5      # well into carrying the body
			if feet.has(side) and stance and v > 0.05:
				var f: Vector3 = feet[side]
				out.slide += Vector2(ankle.x - f.x, ankle.z - f.z).length()
			feet[side] = ankle
		if v > 0.05:
			out.moving_time += dt
		if c is Klappersoldat:
			var y: float = (c as Klappersoldat)._head_yaw
			var rate := absf(y - last_yaw) / dt
			if rate > deg_to_rad(150.0) and not fast:
				out.snaps += 1
			fast = rate > deg_to_rad(150.0)
			last_yaw = y
		if Vector2(p.x - target.x, p.z - target.z).length() < 1.8:
			out.reached = true
			out.time = t
			break
	if out.time == 0.0:
		out.time = t
	out["mean"] = out.travel / maxf(out.moving_time, 0.01)
	out["avg"] = out.travel / maxf(out.time, 0.01)
	out["slide_ratio"] = out.slide / maxf(out.travel, 0.01) * 2.0    # each foot carries half the time
	speeds.sort()
	out["p95"] = speeds[int(speeds.size() * 0.95)] if not speeds.is_empty() else 0.0
	return out


func _walk() -> void:
	print("-- walk")
	await _floor()
	var m: Maze = game.maze
	var route: Array = m.route
	var start: Vector3 = m.cell_center(route[1])
	var goal_cell: Vector2i = route[mini(7, route.size() - 1)]
	var target: Vector3 = m.cell_center(goal_cell)
	FpsPlayer.god_mode = true
	game.player.global_position = target + Vector3.UP * 0.1
	var results := {}
	for kind: String in ["clown", "klapper"]:
		var c: Clown = game.spawn_klapper() if kind == "klapper" else game._spawn_clown(false, false)
		c.global_position = start
		await get_tree().physics_frame
		var r := await _measure(c, game.player.global_position, 40.0)
		results[kind] = r
		print("   %-8s reached=%s in %.1fs  avg %.2f m/s  moving %.2f m/s  top %.2f  p95 %.2f  knee %.0f-%.0f deg  ankle %.0f-%.0f  elbow bend >= %.0f  foot slide %.0f%%  still %d%%" % [kind, r.reached, r.time, r.avg, r.mean, r.top, r.p95, r.knee_min, r.knee_max, r.ankle_min, r.ankle_max, r.elbow_min, r.slide_ratio * 100.0, int(100.0 * r.still_frames / maxf(r.frames, 1))])
		if kind == "klapper":
			var k := c as Klappersoldat
			print("            head snaps %d, hesitations %d, base speed %.2f" % [r.snaps, k.hesitations, (c.get_node("Brain") as ClownBrain).move_speed])
			if render:
				await _film_walk(k)
		c.queue_free()
		game.clowns.erase(c)
		await get_tree().physics_frame
	var kl: Dictionary = results.klapper
	var cl: Dictionary = results.clown
	_check(kl.reached, "reaches the player through the corridors")
	_check(kl.avg < cl.avg * 0.6, "much slower than an ordinary clown (%.2f vs %.2f m/s)" % [kl.avg, cl.avg])
	_check(kl.p95 < 3.2, "never sprints (95th percentile speed %.2f m/s)" % kl.p95)
	_check(kl.knee_max - kl.knee_min > 35.0, "knees bend (%.0f to %.0f deg)" % [kl.knee_min, kl.knee_max])
	_check(kl.ankle_max - kl.ankle_min > 10.0, "ankles articulate (%.0f to %.0f deg)" % [kl.ankle_min, kl.ankle_max])
	_check(kl.elbow_min > 10.0, "elbows always bent (at least %.0f deg)" % kl.elbow_min)
	_check(kl.slide_ratio < cl.slide_ratio + 0.05, "planted foot slides no more than an ordinary clown's (%.0f%% vs %.0f%%)" % [kl.slide_ratio * 100.0, cl.slide_ratio * 100.0])
	_check(kl.snaps >= 2, "head moves in snaps (%d)" % kl.snaps)


func _film_walk(k: Klappersoldat) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for i in 12:
		var side := k.global_basis.x * 3.0 + Vector3.UP * 1.2
		cam.global_position = k.global_position + side
		cam.look_at(k.global_position + Vector3.UP * 0.9)
		await _shot("walk_%02d" % i)
		for f in 5:
			await get_tree().physics_frame
	cam.queue_free()


func _fight() -> void:
	print("-- fight")
	await _floor()
	var m: Maze = game.maze
	var cell: Vector2i = m.route[2]
	var k: Klappersoldat = game.spawn_klapper()
	k.global_position = m.cell_center(cell)
	FpsPlayer.god_mode = false
	game.player.health = 100.0
	game.player.global_position = k.global_position + Vector3(0, 0.1, 1.1)
	k.look_at(game.player.global_position * Vector3(1, 0, 1) + Vector3.UP * k.global_position.y, Vector3.UP, true)
	var brain := k.get_node("Brain") as ClownBrain
	brain.alert(game.player.global_position)
	var t := 0.0
	var started := -1.0
	var landed := -1.0
	var before: float = game.player.health
	var dmg := 0.0
	while t < 6.0 and landed < 0.0:
		game.player.global_position = k.global_position + k.global_basis.z * 1.1 + Vector3.UP * 0.1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if started < 0.0 and brain._attack_t >= 0.0:
			started = t
		if game.player.health < before:
			landed = t
			dmg = before - game.player.health
		if render and started >= 0.0 and landed < 0.0 and int(t * 60) % 9 == 0:
			var cam := Camera3D.new()
			add_child(cam)
			cam.global_position = k.global_position + k.global_basis.x * 2.4 + k.global_basis.z * 1.2 + Vector3.UP * 1.3
			cam.look_at(k.global_position + Vector3.UP * 1.2)
			cam.make_current()
			await _shot("strike_%03d" % int((t - started) * 100))
			cam.queue_free()
	print("   blow started %.2fs, landed %.2fs after (%.1f damage)" % [started, landed - started, dmg])
	_check(started >= 0.0 and landed > started, "swings and connects")
	_check(landed - started > 0.9, "the wind-up is slow and telegraphed (%.2fs)" % (landed - started))
	_check(absf(dmg - 12.5) < 0.01, "hits 1.25x an ordinary clown (%.1f)" % dmg)
	FpsPlayer.god_mode = true
	# staggers: only now and then, only from strong hits
	var staggers := 0
	var hits := 0
	for i in 60:
		if k.dead:
			break
		k.health = k.max_health
		var pb: PhysicalBone3D = k.ragdoll.bones[&"Chest"]
		k.hit({collider = pb, position = pb.global_position + Vector3(0, 0, 0.1), direction = Vector3(0, 0, -1), damage = 30.0, impulse = 8.0})
		hits += 1
		await get_tree().physics_frame
		await get_tree().physics_frame
	staggers = k.staggers
	print("   %d of %d strong hits staggered it" % [staggers, hits])
	_check(staggers > 3 and staggers < hits * 0.4, "staggers occasionally, not every hit")
	k.queue_free()
	game.clowns.erase(k)


func _crowd() -> void:
	print("-- crowd")
	await _floor()
	var m: Maze = game.maze
	FpsPlayer.god_mode = true
	game.player.global_position = m.cell_center(m.route[mini(8, m.route.size() - 1)]) + Vector3.UP * 0.1
	var ks: Array[Klappersoldat] = []
	for i in 6:
		var k: Klappersoldat = game.spawn_klapper()
		k.global_position = m.cell_center(m.route[i % 3]) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		ks.append(k)
	var worst := 0
	var total := 0
	for f in 300:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		for k in ks:
			(k.get_node("Brain") as ClownBrain).alert(game.player.global_position)
		var us := Time.get_ticks_usec() - t0
		total += us
		worst = maxi(worst, us)
	print("   6 Klappersoldats: %.2f ms a frame on average, worst %.2f ms (headless, whole frame)" % [total / 300.0 / 1000.0, worst / 1000.0])
	for k in ks:
		k.queue_free()
		game.clowns.erase(k)


func _gore() -> void:
	print("-- gore")
	if game:
		game.queue_free()
		game = null
		await get_tree().process_frame
	Blood.clear()
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	for b in get_tree().get_nodes_in_group(&"barrels"):
		b.queue_free()
	await get_tree().physics_frame
	var k := Klappersoldat.new()
	room.add_child(k)
	k.position = Vector3(0, 0, -3.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0.0, 1.45, -1.6)
	cam.look_at(Vector3(0, 1.3, -3.0))
	cam.make_current()
	for i in 10:
		await get_tree().physics_frame
	await _shot("0_whole")
	var front := Vector3(0, 0, 1)
	var oil_before := _oil_decals()
	# bullets wear the chest open: a panel first, then the works
	var chest: PhysicalBone3D = k.ragdoll.bones[&"Chest"]
	var stage1 := 0
	for i in 12:
		k.health = k.max_health
		k.hit({collider = chest, position = chest.global_position + Vector3(0.03, 0.06, 0.12), direction = -front, damage = 22.0, impulse = 4.0})
		await get_tree().physics_frame
		if stage1 == 0 and k.gore.mech_stage(&"chest") == 1:
			stage1 = i + 1
			await _shot("1_panel")
	print("   chest: panel after %d rounds, stage now %d" % [stage1, k.gore.mech_stage(&"chest")])
	_check(stage1 > 0, "worn chest shows a riveted panel first")
	_check(k.gore.mech_stage(&"chest") == 2, "more wear rips the panel off to show the gears")
	_check(k.gore.spin_parts.size() >= 4, "gears inside (%d turning parts)" % k.gore.spin_parts.size())
	_check(_has_flesh(k) == false, "no meat, bone or gut anywhere inside it")
	_check(_oil_decals() > oil_before and _blood_decals_since(oil_before) == 0, "it splashes oil, not blood")
	await _shot("2_gears")
	# an arm blown off
	var arm: PhysicalBone3D = k.ragdoll.bones[&"LeftLowerArm"]
	k.health = k.max_health
	k.hit({collider = arm, position = arm.global_position, direction = Vector3(1, 0, -0.3).normalized(), damage = 90.0, impulse = 10.0, can_dismember = true, shot_id = 77})
	await get_tree().physics_frame
	var gibs := room.find_children("*", "Gib", true, false)
	var mech_gib := false
	for gb: Node in gibs:
		if gb is Gib and (gb as Gib).oil:
			mech_gib = true
	_check(mech_gib, "the forearm comes off as an oily clockwork gib")
	var cover_on_gib := false
	for gb: Node in gibs:
		if gb.find_children("*", "MeshInstance3D", true, false).size() > 2:
			cover_on_gib = true
	_check(cover_on_gib, "its brass elbow cover goes with it")
	for i in 20:
		await get_tree().physics_frame
	await _shot("3_arm_off")
	# the face: cracked, then broken open on one side
	var neck: PhysicalBone3D = k.ragdoll.bones[&"Neck"]
	for i in 3:
		k.health = k.max_health
		k.hit({collider = neck, position = neck.global_position + Vector3(0.03, 0.15, 0.1), direction = -front, damage = 30.0, impulse = 3.0})
		await get_tree().physics_frame
	_check(k._face_cracked, "the porcelain face cracks")
	_check(not k._face.has("left") or not k._face.has("right"), "a piece of the face breaks away")
	await _shot("4_face")
	# dead
	var puddles := Blood.oil_puddle_count()
	k.health = 1.0
	k.hit({collider = chest, position = chest.global_position + Vector3(0, 0, 0.12), direction = -front, damage = 40.0, impulse = 14.0})
	_check(k.dead, "killed")
	_check(k.ragdoll.active, "goes straight to ragdoll")
	for i in 20:
		await get_tree().physics_frame
	await _shot("5_falling")
	var t := 0.0
	while t < 10.0 and not k.puddled:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(k.puddled and Blood.oil_puddle_count() > puddles, "an oil puddle where it came to rest (after %.1fs)" % t)
	puddles = Blood.oil_puddle_count()
	for i in 120:
		await get_tree().physics_frame
	await _shot("6_corpse")
	cam.global_position = Vector3(1.6, 1.4, -1.6)
	cam.look_at(k.ragdoll.bones[&"Chest"].global_position)
	await _shot("6b_corpse")
	var waited := 0.0
	while waited < 6.0 and k.is_processing():
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check(not k.is_processing(), "the sparks and twitching stop (after %.1fs more)" % waited)
	k.queue_free()
	for i in 200:
		await get_tree().physics_frame
	_check(Blood.oil_puddle_count() >= puddles, "the puddles stay after the body is gone, and after time (%d)" % Blood.oil_puddle_count())
	# ordinary clowns are untouched by all this
	var c := Clown.new()
	room.add_child(c)
	c.position = Vector3(1.5, 0, -3.0)
	await get_tree().physics_frame
	var blood_before := _blood_decals()
	var cc: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	c.hit({collider = cc, position = cc.global_position + Vector3(0, 0, 0.12), direction = -front, damage = 60.0, impulse = 6.0, can_dismember = true, shot_id = 5})
	await get_tree().physics_frame
	_check(_blood_decals() > blood_before, "an ordinary clown still bleeds blood (%d new splats)" % (_blood_decals() - blood_before))
	_check(_has_flesh(c), "and still has meat and bone inside")
	Blood.clear()
	_check(Blood.oil_puddle_count() == 0, "a new floor clears the oil")
	var bare := 0
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.material_override:
			continue
		for i in m.mesh.get_surface_count():
			if m.mesh.surface_get_material(i) == null and m.get_surface_override_material(i) == null:
				bare += 1
				print("   no material: ", m.get_path(), " ", m.mesh)
	_check(bare == 0, "every mesh has a material")


func _film() -> void:
	var room: Node3D = load("res://scenes/gore_sandbox.tscn").instantiate()
	add_child(room)
	await get_tree().physics_frame
	for c in room.clowns:
		c.queue_free()
	room.clowns.clear()
	var k := Klappersoldat.new()
	k.hesitation_every = Vector2(1.2, 1.8)
	room.add_child(k)
	k.position = Vector3(-2.5, 0, -3.5)
	k.rotation.y = PI * 0.5                  # walking along +x
	var b := ClownBrain.new()               # a stand-in, never in the tree
	k.brain = b
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	var frame := 0
	for f in 300:
		b.intended_speed = 1.45
		await get_tree().physics_frame
		var rate := b.speed_scale
		k.global_position += Vector3(1.45 * rate / 60.0, 0, 0)
		k.velocity = Vector3(1.45 * rate, 0, 0)
		cam.global_position = k.global_position + Vector3(0.6, 1.05, 3.1)
		cam.look_at(k.global_position + Vector3(0.3, 0.9, 0))
		if f % 5 == 0 and f >= 30 and frame < 24:
			await _shot("film_walk_%02d" % frame)
			frame += 1
	# the blow, from the front three-quarter
	b.intended_speed = 0.0
	k.velocity = Vector3.ZERO
	cam.global_position = k.global_position + Vector3(1.6, 1.3, 3.0)
	cam.look_at(k.global_position + Vector3(0, 1.2, 0))
	for f in 30:
		await get_tree().physics_frame
	b._attack_t = 0.0
	b.attack_time = k.attack_seconds
	frame = 0
	var n := 0
	while b._attack_t < b.attack_time:
		await get_tree().physics_frame
		b._attack_t += 1.0 / 60.0
		n += 1
		if n % 6 == 0 and frame < 16:
			await _shot("film_blow_%02d" % frame)
			frame += 1
	b._attack_t = -1.0
	# idle: a minute of almost nothing, sampled
	cam.global_position = k.global_position + Vector3(1.2, 1.6, 1.4)
	cam.look_at(k.global_position + Vector3(0, 1.6, 0))
	frame = 0
	for f in 600:
		await get_tree().physics_frame
		if f % 25 == 0 and frame < 24:
			await _shot("film_idle_%02d" % frame)
			frame += 1


func _oil_decals() -> int:
	var n := 0
	for i in Blood._decal_oil.size():
		if Blood._decal_oil[i] == 1 and Blood._decals[i].visible:
			n += 1
	return n


func _blood_decals() -> int:
	var n := 0
	for i in Blood._decal_oil.size():
		if Blood._decal_oil[i] == 0 and Blood._decals[i].visible:
			n += 1
	return n


func _blood_decals_since(_oil_before: int) -> int:
	return _blood_decals()


func _has_flesh(c: Clown) -> bool:
	var flesh := [ClownGore._mat("meat"), ClownGore._mat("bone"), ClownGore._mat("gut"), ClownGore._mat("brain")]
	for holder: Node3D in c.gore._innards.values():
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_override in flesh:
				return true
	return false
