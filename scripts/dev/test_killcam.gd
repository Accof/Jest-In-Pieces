extends Node3D
## The final-kill camera, checked. Sections (user args; none = all):
##   floor     a real floor: ordinary kills leave it alone; the last kill
##             starts it once; time slows smoothly to 25% and comes back;
##             the camera never sits inside the level and keeps the body in
##             view; the player is frozen and put back exactly; everything is
##             restored at the end
##   variety   the last kill on many floors: which shots it picks
##   double    the last two killed in the same frame: it runs once
##   interrupt the player dies mid-shot; the body is freed mid-shot; the
##             floor is torn down mid-shot: time and camera always come back
##   klapper   a Klappersoldat as the last: it waits for it to fall
##   fall      a clown killed at the edge of a high platform: it follows the fall
##   event     an event room cleared: the last kill there starts it too
##   injuries  the coroner's report: rounds placed on the eye, jaw, heart, a
##             lung, the guts, the hip; a close explosion; a Klappersoldat's
##             engineer's wording
##   report    a floor finale with the brutality report: shown over the
##             killcam, which waits for it; tickets paid; all put back
## Add "render" (with a window) for /tmp/kc_<section>_*.png frames.

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
		await get_tree().process_frame


func _shot(name_: String) -> void:
	if not render:
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/kc_%s.png" % name_)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	render = args.has("render")
	var secs := ["injuries", "report", "floor", "variety", "double", "interrupt", "klapper", "rattlejack", "fall", "event"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("KILLCAM: %d failed" % fails)
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


func _living() -> Array:
	return game.clowns.filter(func(c: Clown) -> bool: return is_instance_valid(c) and not c.dead)


## Shoot `c` dead from where the player stands, through the chest.
func _kill(c: Clown, damage := 500.0) -> void:
	var p: FpsPlayer = game.player
	var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	var dir := (chest.global_position - p.camera.global_position).normalized()
	c.hit({collider = chest, position = chest.global_position - dir * 0.1, direction = dir, damage = damage, impulse = 18.0, shot_id = randi()})


## Put the player a few metres from `c`, in the open, looking at it.
func _face(c: Clown) -> void:
	var p: FpsPlayer = game.player
	var m: Maze = game.maze
	var here := m.cell_of(c.global_position)
	var spot := c.global_position + Vector3(0, 0, 2.5)
	for dir in Maze.DIRS:
		if m.in_bounds(here + dir) and m.linked(here, here + dir):
			spot = m.cell_center(here + dir)
			break
	p.global_position = spot + Vector3.UP * 0.05
	p.look_at(Vector3(c.global_position.x, p.global_position.y, c.global_position.z))
	p.rotation.x = 0.0
	p.rotation.z = 0.0


## Watch one killcam to the end. Returns what it saw.
func _watch(tag: String) -> Dictionary:
	var kc: KillCam = game.kill_cam if game else get_tree().get_first_node_in_group(&"kill_cam")
	var out := {frames = 0, min_ts = 1.0, max_jump = 0.0, inside = 0, hidden = 0, real = 0.0, steps = []}
	var last_ts := 1.0
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.08
	var n := 0
	while kc.active and n < 900:
		await get_tree().process_frame
		n += 1
		var ts := Engine.time_scale
		out.real += get_process_delta_time() / maxf(ts, 0.01)
		out.min_ts = minf(out.min_ts, ts)
		out.max_jump = maxf(out.max_jump, absf(ts - last_ts))
		last_ts = ts
		if n % 6 == 0:
			out.steps.append(snappedf(ts, 0.01))
		var cam := get_viewport().get_camera_3d()
		if cam and is_instance_valid(kc.player) and cam != kc.player.camera:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = probe
			q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
			q.collision_mask = 1
			if not space.intersect_shape(q, 1).is_empty():
				out.inside += 1
			var f: Vector3 = kc._last_focus
			var r := PhysicsRayQueryParameters3D.create(cam.global_position, f, 1)
			if not space.intersect_ray(r).is_empty():
				out.hidden += 1
			out.frames += 1
		if render and n % 10 == 0 and n < 300:
			await _shot("%s_%02d" % [tag, n / 10])
	return out


func _floor() -> void:
	print("-- floor")
	await _new_game(4242)
	var kc: KillCam = game.kill_cam
	var plays := [0]
	kc.finished.connect(func() -> void: plays[0] += 1)
	var all := _living()
	print("   %d clowns" % all.size())
	# all but the last: nothing
	var started := false
	for i in all.size() - 1:
		var c: Clown = all[i]
		_face(c)
		await _frames(1)
		_kill(c)
		await _frames(3)
		started = started or kc.active
	_check(not started, "ordinary kills do not start it")
	var last: Clown = _living()[0]
	_face(last)
	await _frames(2)
	var p: FpsPlayer = game.player
	var pos := p.global_position
	var rot := p.global_rotation
	var cam_rot := p.camera.rotation
	var weapon: int = p.weapon
	var ammo: Array = p.ammo.duplicate()
	_kill(last)
	await _frames(1)
	_check(kc.active, "the last kill starts it (shot: %s)" % kc.shot)
	_check(p.cinematic and not p.view.visible, "the player is frozen and the gun put away")
	_check(get_viewport().get_camera_3d() != p.camera or kc.shot == "player", "the view has left the player's eyes")
	Input.action_press(&"ui_up")          # not used by the player, but make sure nothing moves it
	var w := await _watch("floor")
	print("      %d frames, %.2f s real, slowest %.2f, biggest step in speed %.3f/frame, camera inside the level %d frames, body hidden %d frames" % [w.frames, w.real, w.min_ts, w.max_jump, w.inside, w.hidden])
	print("      speed over time: %s" % [w.steps])
	_check(w.min_ts <= 0.26 and w.min_ts >= 0.24, "slows to 25%% (%.2f)" % w.min_ts)
	_check(w.max_jump < 0.12, "and smoothly (no jumps over 0.12 a frame: %.3f)" % w.max_jump)
	_check(w.real > 3.0 and w.real < 14.0, "lasts the 3-4 s of the shot plus the brutality report (%.2f s real)" % w.real)
	_check(w.inside == 0, "the camera never sits inside the level")
	_check(w.hidden <= w.frames * 0.15, "the body stays in view (hidden %d of %d frames)" % [w.hidden, w.frames])
	_check(not kc.active and Engine.time_scale == 1.0, "over, at full speed")
	_check(get_viewport().get_camera_3d() == p.camera and not p.cinematic and p.view.visible, "back in the player's eyes, controls and gun back")
	_check(p.global_position.distance_to(pos) < 0.05 and p.global_rotation.distance_to(rot) < 0.01 and p.camera.rotation.distance_to(cam_rot) < 0.01, "the player was not moved or turned")
	_check(p.weapon == weapon and p.ammo == ammo, "weapon and ammo untouched")
	_check(plays[0] == 1 and game.exit_open, "ran once; the exit is open")


func _variety() -> void:
	print("-- variety")
	var shots := {}
	var seq: Array[String] = []
	var repeats := 0
	for i in 12:
		await _new_game(9000 + i * 37)
		for c: Clown in _living():
			c.queue_free()
		game.clowns = game.clowns.filter(func(c: Clown) -> bool: return not c.is_queued_for_deletion())
		await _frames(1)
		# one ordinary clown somewhere along the route
		var cell: Vector2i = game.maze.route[mini(3 + i % 5, game.maze.route.size() - 1)]
		var c: Clown = game._spawn_clown(i % 3 == 0, false)
		c.global_position = game.maze.cell_center(cell)
		game.remaining = 1
		await _frames(3)
		_face(c)
		await _frames(2)
		_kill(c)
		await _frames(1)
		var kc: KillCam = game.kill_cam
		seq.append(kc.shot)
		shots[kc.shot] = shots.get(kc.shot, 0) + 1
		var w := await _watch("var%d" % i)
		if w.inside > 0:
			print("      floor %d: camera inside the level %d frames (%s)" % [i, w.inside, kc.shot])
	for k in range(1, seq.size()):
		if seq[k] == seq[k - 1]:
			repeats += 1
	print("   shots: %s" % shots)
	print("   in order: %s" % [seq])
	_check(shots.size() >= 4, "at least four different compositions in 12 finales (%d)" % shots.size())
	_check(repeats <= 3, "rarely the same shot twice running (%d)" % repeats)
	_check(shots.get("player", 0) <= 2, "rarely left in first person for want of a shot (%d)" % shots.get("player", 0))


func _double() -> void:
	print("-- double")
	await _new_game(777)
	var kc: KillCam = game.kill_cam
	var plays := [0]
	kc.finished.connect(func() -> void: plays[0] += 1)
	var all := _living()
	for i in all.size() - 2:
		_kill(all[i])
	await _frames(3)
	var two := _living()
	_face(two[0])
	await _frames(1)
	_kill(two[0])
	_kill(two[1])
	await _frames(1)
	_check(kc.active, "two last ones at once: it runs")
	await _watch("double")
	_check(plays[0] == 1, "once (%d)" % plays[0])


func _interrupt() -> void:
	print("-- interrupt")
	for how: String in ["player dies", "body freed", "floor torn down", "paused"]:
		await _new_game(31337)
		var kc: KillCam = game.kill_cam
		var all := _living()
		for i in all.size() - 1:
			_kill(all[i])
		await _frames(2)
		var last: Clown = _living()[0]
		_face(last)
		await _frames(1)
		_kill(last)
		await _frames(30)
		match how:
			"player dies":
				FpsPlayer.god_mode = false
				game.player.take_damage(9999.0)
			"body freed":
				last.queue_free()
			"floor torn down":
				game.next_floor()
			"paused":
				get_tree().paused = true
		var n := 0
		while kc.active and n < 120:
			await get_tree().process_frame
			n += 1
		get_tree().paused = false
		_check(not kc.active and Engine.time_scale == 1.0 and AudioServer.playback_speed_scale == 1.0, "%s: stopped and full speed again (%d frames, %s)" % [how, n, kc.aborted])
		if how == "body freed" or how == "player dies":
			_check(get_viewport().get_camera_3d() == game.player.camera, "%s: back in the player's eyes" % how)
		if how == "body freed":
			_check(not game.player.cinematic, "body freed: controls back")


func _klapper() -> void:
	print("-- klapper")
	await _new_game(5150)
	for c: Clown in _living():
		c.queue_free()
	game.clowns.clear()
	await _frames(1)
	var k: Klappersoldat = game.spawn_klapper()
	k.global_position = game.maze.cell_center(game.maze.route[mini(4, game.maze.route.size() - 1)])
	k.force_death = "short"
	game.remaining = 1
	await _frames(3)
	_face(k)
	await _frames(2)
	k.health = 1.0
	_kill(k, 50.0)
	await _frames(1)
	var kc: KillCam = game.kill_cam
	_check(kc.active, "a Klappersoldat as the last one: it runs (%s)" % kc.shot)
	var w := await _watch("klapper")
	print("      %.2f s real, ragdoll by the end %s" % [w.real, k.ragdoll.active if is_instance_valid(k) else "?"])
	_check(is_instance_valid(k) and k.ragdoll.active, "it stayed until the Klappersoldat went over")
	_check(w.real <= kc.max_seconds + kc._held + kc.return_seconds + 0.2, "and no longer than the limit plus the report (%.2f s)" % w.real)


## The Rattlejack's staged deaths as the last kill: the camera stays on the
## delayed headshot until he goes over; the Death Rattle keeps firing (in
## step with the slow motion) while it watches.
func _rattlejack() -> void:
	print("-- rattlejack")
	for kind: String in ["headshot", "rattle"]:
		await _new_game(5160)
		for c: Clown in _living():
			c.queue_free()
		game.clowns.clear()
		await _frames(1)
		var r: Rattlejack = game.spawn_rattlejack()
		r.global_position = game.maze.cell_center(game.maze.route[mini(4, game.maze.route.size() - 1)])
		r.force_death = kind
		game.remaining = 1
		await _frames(3)
		_face(r)
		await _frames(2)
		r.health = 1.0
		var deaths := [0]
		r.died.connect(func(_c: Clown) -> void: deaths[0] += 1)
		_kill(r, 30.0)
		await _frames(1)
		var kc: KillCam = game.kill_cam
		_check(kc.active, "a Rattlejack (%s) as the last one: it runs (%s)" % [kind, kc.shot])
		var slow_rounds := 0
		var handed_while_on := false
		var n := 0
		while kc.active and n < 1200:
			var before := r.rattle_rounds if is_instance_valid(r) else 0
			await get_tree().process_frame
			n += 1
			if is_instance_valid(r):
				if Engine.time_scale < 0.9 and r.rattle_rounds > before:
					slow_rounds += r.rattle_rounds - before
				handed_while_on = handed_while_on or r.handed_over
		print("      %s: handed to the ragdoll while the camera was on him %s; %d rounds in slow motion; deaths %d; remaining %d" % [kind, handed_while_on, slow_rounds, deaths[0], game.remaining])
		_check(handed_while_on, "%s: the camera stayed until he went over" % kind)
		_check(deaths[0] == 1 and game.remaining == 0, "%s: the kill counted once, the floor cleared" % kind)
		if kind == "rattle":
			_check(slow_rounds >= 1, "rattle: the gun fires on through the slow motion (%d)" % slow_rounds)


func _fall() -> void:
	print("-- fall")
	if game:
		game.queue_free()
		game = null
		await _frames(2)
	var room := Node3D.new()
	add_child(room)
	var body := StaticBody3D.new()
	room.add_child(body)
	for b: Array in [[Vector3(0, -0.1, 0), Vector3(30, 0.2, 30)], [Vector3(0, 4.9, -3), Vector3(4, 0.2, 6)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.position = b[0]
		room.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	room.add_child(sun)
	var p := FpsPlayer.new()
	room.add_child(p)
	p.global_position = Vector3(0, 5.0, -4.5)
	var kc := KillCam.new()
	room.add_child(kc)
	kc.player = p
	var c := Clown.new()
	room.add_child(c)
	c.global_position = Vector3(0, 5.0, -0.3)       # right on the edge (the platform ends at z = 0)
	c.rotation.y = PI
	c.force_variant = "blown_back"                  # backwards, off the edge (it faces the player)
	await _frames(5)
	p.look_at(Vector3(c.global_position.x, p.global_position.y, c.global_position.z))
	var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
	c.hit({collider = chest, position = chest.global_position, direction = Vector3(0, -0.1, 1).normalized(), damage = 500.0, impulse = 30.0, shot_id = 1})
	await _frames(1)
	_check(kc.play(c), "started")
	print("   shot: %s (tracking %s)" % [kc.shot, kc.tracking])
	_check(kc.shot in ["tracking", "elevated"], "a body going off a 5 m drop gets a tracking or elevated shot (%s)" % kc.shot)
	var low := 99.0
	var n := 0
	while kc.active and n < 900:
		await get_tree().process_frame
		n += 1
		low = minf(low, chest.global_position.y)
		if n % 15 == 0:
			var cam := get_viewport().get_camera_3d()
			print("      f%d real %.2f ts %.2f returning %s chest y %.2f cam %s" % [n, kc._t, Engine.time_scale, kc._returning >= 0.0, chest.global_position.y, cam.global_position.snapped(Vector3.ONE * 0.01)])
		if render and n % 10 == 0 and n < 300:
			await _shot("fall_%02d" % (n / 10))
	_check(low < 1.0, "it fell to the ground below (%.2f m)" % low)
	_check(not kc.active and Engine.time_scale == 1.0 and get_viewport().get_camera_3d() == p.camera, "back to the player after the fall")
	room.queue_free()
	await _frames(2)


func _event() -> void:
	print("-- event")
	if game:
		game.queue_free()
		game = null
		await _frames(2)
	var room := EventRoom.new()
	add_child(room)
	var floor_ := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	cs.position.y = -0.1
	floor_.add_child(cs)
	room.add_child(floor_)
	var p := FpsPlayer.new()
	room.player = p
	room.add_child(p)
	var kc := KillCam.new()
	room.add_child(kc)
	kc.player = p
	var a := room.spawn(Vector3(-1.5, 0, 5))
	var b := room.spawn(Vector3(1.5, 0, 5))
	await _frames(5)
	for c: Clown in [a, b]:
		var chest: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
		c.hit({collider = chest, position = chest.global_position, direction = Vector3(0, 0, 1), damage = 500.0, impulse = 18.0, shot_id = randi()})
		await _frames(1)
		_check(kc.active == (c == b), "event room: %s kill %s it" % ["the last" if c == b else "an ordinary", "starts" if c == b else "does not start"])
	await _watch("event")
	_check(not kc.active and Engine.time_scale == 1.0, "event room: over and back")
	room.queue_free()
	await _frames(2)


# --- the injury report --------------------------------------------------------------------
## A world point on a standing body from a point on its rest pose.
func _at_rest(c: Clown, bone: StringName, rest: Vector3) -> Vector3:
	var sk := c.skeleton
	var i := sk.find_bone(bone)
	return sk.global_transform * (c.ragdoll.bone_pose(i) * (sk.get_bone_global_rest(i).affine_inverse() * rest))


func _shoot_at(c: Clown, bone: StringName, rest: Vector3, dmg: float) -> void:
	var pb: PhysicalBone3D = c.ragdoll.bones[bone]
	var at := _at_rest(c, bone, rest)
	c.hit({collider = pb, position = at, direction = (c.global_basis * Vector3.BACK * -1.0).normalized(), damage = dmg, impulse = 8.0, shot_id = randi()})


func _report_text(r: Dictionary) -> String:
	var out: Array[String] = []
	for l: Dictionary in r.lines:
		out.append("%s (+%d)" % [l.text, l.points])
	return ", ".join(out)


func _injuries() -> void:
	print("-- injuries")
	if game:
		game.queue_free()
		game = null
		await _frames(2)
	var room := Node3D.new()
	add_child(room)
	var cases := [
		["eye", &"Neck", Vector3(0.043, 1.725, 0.11), 40.0, ["Through the left eye", "Brain destroyed"]],
		["jaw", &"Neck", Vector3(0.0, 1.62, 0.09), 40.0, ["Jaw shot away"]],
		["heart", &"Chest", Vector3(0.05, 1.3, 0.13), 60.0, ["Shot through the heart"]],
		["lung", &"Chest", Vector3(-0.11, 1.3, 0.13), 60.0, ["Right lung punctured"]],
		["guts", &"Spine", Vector3(0.0, 1.1, 0.13), 60.0, ["Gut-shot"]],
		["liver", &"Spine", Vector3(-0.09, 1.1, 0.12), 60.0, ["Liver ruptured"]],
	]
	for cs: Array in cases:
		var c := Clown.new()
		room.add_child(c)
		c.max_health = 50.0
		c.health = 50.0
		await _frames(3)
		_shoot_at(c, cs[1], cs[2], cs[3])
		await _frames(2)
		var r := Injuries.assess(c)
		var txt := _report_text(r)
		var ok := true
		for want: String in cs[4]:
			ok = ok and txt.contains(want)
		_check(ok, "%s: %s  [score %d, %s, %d tickets]" % [cs[0], txt, r.score, r.rank, r.tickets])
		c.queue_free()
		await _frames(1)
	# an explosion close by
	var b := Clown.new()
	room.add_child(b)
	await _frames(3)
	b.caught_in_blast(b.global_position + Vector3(0, 1.0, 1.0), 6.0)
	await _frames(3)
	var rb := Injuries.assess(b)
	var tb := _report_text(rb)
	_check(tb.contains("Caught in an explosion") and (tb.contains("Ribs") or tb.contains("Ribcage")), "explosion: %s  [score %d, %s]" % [tb, rb.score, rb.rank])
	b.queue_free()
	# the Klappersoldat's wording
	var k := Klappersoldat.new()
	room.add_child(k)
	await _frames(3)
	k.health = 10.0
	var e: Vector3 = k.spec.eyes[0]
	_shoot_at(k, &"Neck", e + Vector3(0, 0, 0.01), 40.0)
	await _frames(2)
	var rk := Injuries.assess(k)
	var tk := _report_text(rk)
	_check(tk.contains("optic lens shattered") and tk.contains("governor"), "Klappersoldat: %s  [%s]" % [tk, rk.rank])
	room.queue_free()
	await _frames(2)


func _report() -> void:
	print("-- report")
	await _new_game(6060)
	var kc: KillCam = game.kill_cam
	var all := _living()
	for i in all.size() - 1:
		_kill(all[i])
	await _frames(3)
	var last: Clown = _living()[0]
	_face(last)
	await _frames(2)
	# a shotgun blast to the chest, close: messy
	var p: FpsPlayer = game.player
	var chest: PhysicalBone3D = last.ragdoll.bones[&"Chest"]
	var dir := (chest.global_position - p.camera.global_position).normalized()
	var sid := 4242
	for i in 10:
		last.hit({collider = chest, position = chest.global_position - dir * 0.1 + Vector3(randf_range(-0.05, 0.05), randf_range(-0.08, 0.08), 0), direction = dir, damage = 16.0, impulse = 3.0, shot_id = sid, can_dismember = true, weapon = "Shotgun", dist = 2.0})
	var tickets_before: int = game.run_tickets
	await _frames(1)
	_check(kc.active, "the last kill starts the killcam")
	var during := false
	var t_real := 0.0
	var n := 0
	while kc.active and n < 1500:
		await get_tree().process_frame
		n += 1
		t_real += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		during = during or (kc.active and game.brutality.shown)
		if render and n % 12 == 0:
			await _shot("report_%03d" % (n / 12))
	_check(not during, "nothing of the report while the killcam runs (%.2f s)" % t_real)
	_check(t_real > 3.0 and t_real < 6.0, "the killcam is its usual length again (%.2f s)" % t_real)
	_check(get_viewport().get_camera_3d() == p.camera and not p.cinematic and Engine.time_scale == 1.0, "back with the player, all restored, before the report")
	await _frames(2)
	_check(game.brutality.shown, "then the report starts")
	var lines_max := 0
	var m := 0
	while game.brutality.shown and m < 900:
		await get_tree().process_frame
		m += 1
		lines_max = maxi(lines_max, game.brutality.lines_shown)
		if render and m % 12 == 0:
			await _shot("report_after_%03d" % (m / 12))
	var r: Dictionary = game.last_report
	print("      report: %s" % _report_text(r))
	print("      score %d, %s, %d tickets; report %.1f s" % [r.get("score", 0), r.get("rank", "?"), r.get("tickets", 0), m / 60.0])
	_check(lines_max == (r.lines as Array).size(), "every injury shown (%d)" % lines_max)
	_check(game.run_tickets - tickets_before == int(r.tickets), "its tickets were paid (%d)" % (game.run_tickets - tickets_before))
	_check(game.brutality.volume_db <= -10.0, "its sounds are turned down (%.0f dB)" % game.brutality.volume_db)
	_check(not game.brutality.shown, "and the report is gone")

