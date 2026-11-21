extends Node
## How the human soldiers move (the movement overhaul): way on built up and
## run off rather than snapped, turns at a man's rate with the feet stepping
## him round, feet planted while they carry him, side-steps committed to,
## cover held, peeks that lean out with the muzzle clear, near misses that
## make him duck and incoming fire that keeps his head down, flinches scaled
## by the hit. The Klappersoldat keeps his clockwork stepping.
## Headless: godot --headless --fixed-fps 60 scenes/test_motion.tscn
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


func _soldier(m: Maze, at: Vector3) -> Clown:
	var s := Clown.new()
	s.body = "witzsoldat"
	game._world.add_child(s)
	s.give_rifle()
	var brain := ClownBrain.new()
	brain.maze = m
	brain.player = game.player
	brain.others = game.clowns
	brain.name = "Brain"
	brain.rifleman()
	s.add_child(brain)
	s.global_position = at
	game.clowns.append(s)
	return s


func _quiet(c: Clown) -> ClownBrain:
	var b: ClownBrain = c.get_node("Brain")
	b.set_physics_process(false)
	b.set_process(false)
	return b


func _run() -> void:
	Clown.pose_lod = false
	Engine.set_meta(&"test_save", true)
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	FpsPlayer.god_mode = true
	game.start_run()
	await _frames(2)
	var m: Maze = game.maze
	for c: Clown in game.clowns:
		c.queue_free()
	game.clowns.clear()
	await _frames(2)
	# the longest straight run on one level
	var best := [0, 0]
	for i in range(m.route.size() - 1):
		var k := i
		while k + 1 < m.route.size() and m.route[k + 1] - m.route[k] == m.route[i + 1] - m.route[i] and m.level[m.idx(m.route[k + 1])] == m.level[m.idx(m.route[i])]:
			k += 1
		if k - i > best[1] - best[0]:
			best = [i, k]
	var a: Vector3 = m.cell_center(m.route[best[0]])
	var b: Vector3 = m.cell_center(m.route[best[1]])
	var run_dir := (b - a)
	run_dir.y = 0.0
	run_dir = run_dir.normalized()
	print("straight run of %d cells, %.1f m" % [best[1] - best[0] + 1, a.distance_to(b)])
	# the player out of the way (a far cell, facing away)
	game.player.global_position = m.cell_center(m.route[m.route.size() - 1]) + Vector3.UP * 0.1

	var args := OS.get_cmdline_user_args()
	if args.has("clips"):
		await _clips(m, a, b, run_dir, args)
		get_tree().quit()
		return
	var all := args.is_empty()
	if all or args.has("locomotion"):
		await _locomotion(m, a, b, run_dir)
	if all or args.has("turning"):
		await _turning(m, a, run_dir)
	if all or args.has("feet"):
		await _feet(m, a, b, run_dir)
	if all or args.has("fire"):
		await _fire_reactions(m, a, b, run_dir)
	if all or args.has("fight"):
		await _fight(m, a, b)
	if all or args.has("klapper"):
		await _klapper(m, a)
	print("MOTION: %d failed" % fails)
	FpsPlayer.god_mode = false
	get_tree().quit()


## Starting, running, stopping: the way on builds up over about a second and
## runs off over a step or two; a soldier pulls up on the spot he was going for.
func _locomotion(m: Maze, a: Vector3, b: Vector3, run_dir: Vector3) -> void:
	print("-- locomotion")
	var c := _soldier(m, a)
	var br := _quiet(c)
	c.rotation.y = atan2(run_dir.x, run_dir.z)
	await _frames(10)
	_check(br.weighty, "a WitzSoldat moves with weight")
	var t := 0.0
	var t90 := -1.0
	var first := -1.0
	while t < 2.5:
		br._go_to(b, 1.0 / 60.0, br.move_speed)
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if first < 0.0:
			first = br._vel.length()
		if t90 < 0.0 and br._vel.length() >= br.move_speed * 0.9:
			t90 = t
	print("      walk %.2f m/s: first frame %.2f m/s, 90%% at %.2f s" % [br.move_speed, first, t90])
	_check(first < 0.2, "it does not jump to full pace (first frame %.2f m/s)" % first)
	_check(t90 > 0.5 and t90 < 1.6, "up to a walk in about a second (%.2f s)" % t90)
	# stopping from a walk
	var at := c.global_position
	var stop_t := 0.0
	while br._vel.length() > 0.05 and stop_t < 3.0:
		br._settle(1.0 / 60.0)
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		stop_t += 1.0 / 60.0
	var slide := Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length()
	print("      stops in %.2f s over %.2f m" % [stop_t, slide])
	_check(stop_t > 0.2 and stop_t < 1.2 and slide > 0.1 and slide < 1.2, "pulls up over a step or two, not dead (%.2f m)" % slide)
	# a run, and the stop at the end of it: it comes in to the spot
	c.global_position = a
	br._vel = Vector3.ZERO
	t = 0.0
	var top := 0.0
	var arrived := false
	var overshoot := 0.0
	while t < 12.0:
		arrived = br._go_to(b, 1.0 / 60.0, br.run_speed)
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		top = maxf(top, br._vel.length())
		var past := (c.global_position - b).dot(run_dir)
		overshoot = maxf(overshoot, past)
		if arrived:
			break
	print("      run: top %.2f m/s (run speed %.2f), arrived %s at %.1f s, overshoot %.2f m" % [top, br.run_speed, arrived, t, overshoot])
	_check(arrived and overshoot < 0.4, "runs to a spot and stops on it (overshoot %.2f m)" % overshoot)
	_check(c.run_amount > 0.0 or top > br.move_speed * 1.2, "runs (top %.2f m/s)" % top)
	# crouch-walking into cover: slow and low over the last few metres
	c.global_position = a
	br._vel = Vector3.ZERO
	br._cover_state = 1
	var low_speed := 0.0
	var low_n := 0
	var low_crouch := 0.0
	t = 0.0
	while t < 12.0:
		br.crouch_want = 0.0
		var done := br._go_to(b, 1.0 / 60.0, br.run_speed)
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var d := Vector2(c.global_position.x - b.x, c.global_position.z - b.z).length()
		if d < 2.5 and d > 0.6:
			low_speed += br._vel.length()
			low_n += 1
			low_crouch = maxf(low_crouch, c.crouch_amount)
		if done:
			break
	br._cover_state = 0
	low_speed /= maxf(low_n, 1)
	print("      last metres into cover: %.2f m/s, crouched %.2f" % [low_speed, low_crouch])
	_check(low_n > 0 and low_speed < br.move_speed * 0.75 and low_crouch > 0.4, "the last metres into cover are a crouched walk (%.2f m/s, crouch %.2f)" % [low_speed, low_crouch])
	c.queue_free()
	game.clowns.erase(c)
	await _frames(2)


## Turning: no faster than a man turns, the turn building and easing; on the
## spot the feet step him round (the stride runs while he is turning).
func _turning(m: Maze, a: Vector3, run_dir: Vector3) -> void:
	print("-- turning")
	var c := _soldier(m, a)
	var br := _quiet(c)
	c.rotation.y = atan2(run_dir.x, run_dir.z)
	await _frames(10)
	var phase0 := c.walk_phase
	var t := 0.0
	var turned := false
	var max_rate := 0.0
	var first_rate := -1.0
	while t < 3.0:
		br._face(-run_dir, 1.0 / 60.0, 8.0)
		br._settle(1.0 / 60.0, false)
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if first_rate < 0.0:
			first_rate = absf(br._yaw_rate)
		max_rate = maxf(max_rate, absf(br._yaw_rate))
		var f := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
		if f.dot(-run_dir) > 0.99:
			turned = true
			break
	var stepped := c.walk_phase - phase0
	print("      about-turn on the spot: %.2f s, top rate %.1f rad/s (first frame %.2f), stride advanced %.1f rad" % [t, max_rate, first_rate, stepped])
	_check(turned and t > 0.9 and t < 2.2, "an about-turn takes a second or so (%.2f s)" % t)
	_check(max_rate <= ClownBrain.TURN_IDLE * 1.31 + 0.01, "no faster than a man turns (%.1f rad/s)" % max_rate)
	_check(first_rate < 0.5, "the turn builds up, it does not snap (%.2f rad/s first frame)" % first_rate)
	_check(stepped > PI, "the feet step him round as he turns (%.1f rad of stride)" % stepped)
	_check(absf(c.turn_rate) > 0.0 or turned, "the body knows it is turning (shoulders lead)")
	c.queue_free()
	await _frames(2)


## Feet planted: while a foot is down and carrying him, it should hardly move
## over the ground (the stride is matched to the speed).
func _feet(m: Maze, a: Vector3, b: Vector3, run_dir: Vector3) -> void:
	print("-- feet")
	for pace in ["walk", "run"]:
		var c := _soldier(m, a)
		var br := _quiet(c)
		c.rotation.y = atan2(run_dir.x, run_dir.z)
		await _frames(10)
		var sk: Skeleton3D = c.skeleton
		var bi := sk.find_bone("LeftFoot")
		if bi < 0:
			_check(false, "found the foot bone")
			return
		var speed: float = br.move_speed if pace == "walk" else br.run_speed
		var samples: Array = []          # [foot pos, body speed]
		var t := 0.0
		while t < 4.0 and (c.global_position - b).dot(run_dir) < -1.5:
			br._go_to(b, 1.0 / 60.0, speed)
			br._after(1.0 / 60.0)
			await get_tree().process_frame
			t += 1.0 / 60.0
			if t > 1.6:                    # up to pace
				samples.append([sk.global_transform * sk.get_bone_global_pose(bi).origin, br._vel.length()])
		if samples.size() < 30:
			_check(false, "%s: enough straight ground to measure (%d frames)" % [pace, samples.size()])
			c.queue_free()
			await _frames(2)
			continue
		var low := INF
		for s: Array in samples:
			low = minf(low, (s[0] as Vector3).y)
		var planted := 0.0
		var fwd := 0.0
		var body := 0.0
		var n := 0
		for i in range(1, samples.size()):
			var p0: Vector3 = samples[i - 1][0]
			var p1: Vector3 = samples[i][0]
			if p1.y < low + 0.03 and p0.y < low + 0.03:
				planted += Vector2(p1.x - p0.x, p1.z - p0.z).length() * 60.0
				fwd += Vector2(p1.x - p0.x, p1.z - p0.z).dot(Vector2(run_dir.x, run_dir.z)) * 60.0
				body += float(samples[i][1])
				n += 1
		planted /= maxf(n, 1)
		fwd /= maxf(n, 1)
		body /= maxf(n, 1)
		print("      (along the way: %+.2f m/s)" % fwd)
		var ratio := planted / maxf(body, 0.01)
		print("      %s %.2f m/s: planted foot moves %.2f m/s over the ground (%.0f%% of body speed, %d frames)" % [pace, body, planted, ratio * 100.0, n])
		if n <= 5:
			print("      (%s: too few planted frames on this level's straight to judge)" % pace)
		else:
			_check(ratio < 0.4, "%s: the planted foot holds the ground (%.0f%% slide)" % [pace, ratio * 100.0])
		c.queue_free()
		await _frames(2)


## Near misses, incoming fire, being hit.
func _fire_reactions(m: Maze, a: Vector3, b: Vector3, run_dir: Vector3) -> void:
	print("-- under fire")
	var c := _soldier(m, a + run_dir * 1.5)
	var br: ClownBrain = c.get_node("Brain")
	br.set_physics_process(false)
	await _frames(20)
	var chest := c.global_position + Vector3.UP * 1.25
	var side := Vector3(-run_dir.z, 0, run_dir.x)
	# a round cracking past 3 m off: nothing
	var from := chest - run_dir * 15.0 + side * 3.0
	game.player._near_misses(from, from + run_dir * 30.0, null)
	_check(br.near_misses == 0 and br.suppression == 0.0, "a round 3 m off goes unremarked")
	# a round cracking past 0.5 m off
	from = chest - run_dir * 15.0 + side * 0.5
	var c0 := c.crouch_amount
	game.player._near_misses(from, from + run_dir * 30.0, null)
	var flinch_peak := 0.0
	var crouch_peak := 0.0
	for i in 30:
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		flinch_peak = maxf(flinch_peak, c._flinch.length())
		crouch_peak = maxf(crouch_peak, c.crouch_amount)
	print("      near miss 0.5 m: suppression %.2f, duck to %.2f (from %.2f), flinch %.2f rad, mind %s" % [br.suppression, crouch_peak, c0, flinch_peak, br.mind])
	_check(br.near_misses == 1, "a round 0.5 m past him registers")
	_check(crouch_peak > c0 + 0.3, "he ducks (%.2f)" % crouch_peak)
	_check(flinch_peak > 0.05, "he flinches away from it (%.2f rad)" % flinch_peak)
	_check(br.mind != ClownBrain.Mind.IDLE, "an unaware man is alerted by it")
	# a second straight after: the reaction has a cooldown
	game.player._near_misses(from, from + run_dir * 30.0, null)
	_check(br.near_misses == 1, "rounds in quick succession do not stack reactions")
	# a burst: suppression builds, then fades
	var peak := 0.0
	for k in 6:
		for i in 60:
			br._after(1.0 / 60.0)
			await get_tree().physics_frame
		game.player._near_misses(from, from + run_dir * 30.0, null)
		peak = maxf(peak, br.suppression)
	var crouched_now := c.crouch_amount
	var t := 0.0
	while br.suppression > 0.05 and t < 15.0:
		br._after(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	print("      sustained fire: suppression %.2f, crouch %.2f; gone in %.1f s" % [peak, crouched_now, t])
	_check(peak > 0.6, "sustained near misses suppress him (%.2f)" % peak)
	_check(t > 2.0 and t < 12.0, "and it fades when the fire stops (%.1f s)" % t)
	# hits: the flinch scales with the damage
	var peaks: Array[float] = []
	for dmg in [8.0, 60.0]:
		await _frames(90)
		var p0 := c._flinch.length()
		c._flinch_from(c.global_position + Vector3.UP * 1.3 + side * 0.15, run_dir, dmg)
		var pk := 0.0
		for i in 40:
			await get_tree().physics_frame
			pk = maxf(pk, c._flinch.length())
		peaks.append(pk - p0)
	print("      hit flinch: 8 dmg %.2f rad, 60 dmg %.2f rad" % [peaks[0], peaks[1]])
	_check(peaks[1] > peaks[0] * 1.5 and peaks[0] > 0.02, "a heavy hit rocks him further than a graze")
	c.queue_free()
	game.clowns.erase(c)
	await _frames(2)


## A fight down a straight corridor: side-steps held, not flicked; cover held
## for a while, peeks with the lean out and the muzzle clear.
func _fight(m: Maze, a: Vector3, b: Vector3) -> void:
	print("-- fight")
	var c := _soldier(m, b)
	var br: ClownBrain = c.get_node("Brain")
	br.use_cover = true
	game.player.global_position = a + Vector3.UP * 0.1
	game.player.look_at(Vector3(b.x, game.player.global_position.y, b.z))
	await _frames(5)
	br.alert(game.player.global_position, false)
	var t := 0.0
	var last := -1
	var states: Array = []
	var dwell: Array[float] = []
	var entered := 0.0
	var lean_max := 0.0
	var lat_max := 0.0
	var crouch_hide := 0.0
	var lat_sign := 0.0
	var lat_switches := 0
	var hide_n := 0
	var shots0 := br.rounds_fired
	while t < 45.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 12.0 and br._cover_state == 0 and br._cover_cooldown <= 0.0 and int(t * 60.0) % 120 == 0:
			br._find_cover()            # after a spell in the open, nudge him to cover so it is measured
		if br._cover_state != last:
			if last == 2:
				dwell.append(t - entered)
			last = br._cover_state
			entered = t
			states.append("%.1f:%s" % [t, ["open", "to", "hide", "peek"][last]])
		if OS.has_environment("MDEBUG") and int(t * 60) % 60 == 0:
			print("        t%.0f pos %s cover %s peek %s vel %.2f mind %d state %d unseen %.1f" % [t, c.global_position, br._cover, br._peek, br._vel.length(), br.mind, br._cover_state, br._unseen])
		lean_max = maxf(lean_max, absf(c.lean))
		if br._cover_state == 2:
			crouch_hide += c.crouch_amount
			hide_n += 1
		if br._cover_state == 0 and br.mind == ClownBrain.Mind.HUNT:
			var f := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
			var lat_s := br._vel.dot(Vector3(-f.z, 0, f.x))
			var lat := absf(lat_s)
			lat_max = maxf(lat_max, lat)
			if lat > 0.25 and signf(lat_s) != lat_sign:
				if lat_sign != 0.0:
					lat_switches += 1
				lat_sign = signf(lat_s)
		if c.dead:
			break
	var shots := br.rounds_fired - shots0
	print("      45 s: states ", states)
	print("      shots %d, side-step reversals %d, sideways direction changes seen %d (%.2f/s), fastest side-step %.2f m/s, top turn %.1f rad/s, lean %.2f" % [shots, br.strafe_flips, lat_switches, lat_switches / t, lat_max, br.yaw_rate_max, lean_max])
	var avg_dwell := 0.0
	for d in dwell:
		avg_dwell += d
	avg_dwell /= maxf(dwell.size(), 1)
	print("      hid %d times, %.1f s on average, crouched %.2f while hiding" % [dwell.size(), avg_dwell, crouch_hide / maxf(hide_n, 1)])
	_check(lat_switches / t < 0.4 and br.strafe_flips / t < 0.2, "side-steps are held, not flicked (%.2f changes/s)" % (lat_switches / t))
	_check(lat_max < br.move_speed * 0.5, "side-steps at a careful pace (%.2f m/s)" % lat_max)
	_check(br.yaw_rate_max <= ClownBrain.TURN_WALK * 1.31 + 0.01, "never turns faster than a man (%.1f rad/s)" % br.yaw_rate_max)
	_check(shots > 0, "he fights (%d shots)" % shots)
	if dwell.size() > 0:
		_check(avg_dwell > 2.0, "cover is held for a while (%.1f s)" % avg_dwell)
		_check(crouch_hide / maxf(hide_n, 1) > 0.6, "crouched while hiding")
	else:
		print("      (no cover taken on this level: dwell not measured)")
	# out in the open (no cover): the side-stepping on its own, in the corridor
	br.use_cover = false
	br._drop_cover()
	br.strafe_flips = 0
	var st := 0.0
	var moving := 0.0
	var sw := 0
	var sg := 0.0
	var lm := 0.0
	while st < 25.0 and not c.dead:
		await get_tree().physics_frame
		st += 1.0 / 60.0
		var f := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
		var ls := br._vel.dot(Vector3(-f.z, 0, f.x))
		lm = maxf(lm, absf(ls))
		if absf(ls) > 0.25:
			moving += 1.0 / 60.0
			if signf(ls) != sg:
				if sg != 0.0:
					sw += 1
				sg = signf(ls)
	print("      open, 25 s: side-stepping %.1f s, %d changes of side, %d reversals, fastest %.2f m/s" % [moving, sw, br.strafe_flips, lm])
	_check(sw / 25.0 < 0.4, "in the open the side-steps are held (%.2f changes/s)" % (sw / 25.0))
	_check(lm < br.move_speed * 0.5, "and taken at a careful pace (%.2f m/s)" % lm)
	# the muzzle check: a wall between the muzzle and the player blocks the shot
	_check(br._muzzle_clear() == br._clear(c.muzzle_position(), game.player.global_position + Vector3.UP * 1.25), "the muzzle check is the line from the muzzle")
	c.queue_free()
	game.clowns.erase(c)
	await _frames(2)


## The Klappersoldat keeps his own stepping (no human weight or turning).
func _klapper(m: Maze, a: Vector3) -> void:
	print("-- klappersoldat")
	var k: Clown = game.spawn_klapper()
	k.global_position = a
	await _frames(10)
	var br := k.get_node_or_null("Brain") as ClownBrain
	_check(br != null and not br.weighty, "the Klappersoldat is not given a man's weight")
	k.queue_free()
	await _frames(2)


# ---------------------------------------------------------------- clips --
# Frame sequences for review (args: clips [name ...]); run with a window
# (xvfb) and the Compatibility renderer. /tmp/clips/<name>_NNN.png at 15 fps.
var _cam: Camera3D
var _lamp: OmniLight3D
var _fno := 0


var cam_axis := Vector3.FORWARD     ## the corridor's way: the camera stands along it, not in a wall
var cam_anchor := Vector3.INF       ## a fixed spot to film from, or follow the man


func _film(c: Node3D, name_: String) -> void:
	var at := c.global_position if cam_anchor == Vector3.INF else cam_anchor
	var side := Vector3(-cam_axis.z, 0, cam_axis.x)
	_cam.global_position = at + cam_axis * 3.6 + side * 0.45 + Vector3.UP * 1.5
	_cam.fov = 60.0
	if name_ == "fight":
		# what the player sees of him (zoomed): the peeks round the corner
		_cam.global_position = game.player.global_position + Vector3.UP * 1.6
		_cam.fov = 28.0
	_cam.look_at(c.global_position + Vector3.UP * 0.95)
	_lamp.global_position = _cam.global_position + Vector3.UP * 0.4
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/clips/%s_%03d.png" % [name_, _fno])
	_fno += 1


func _clip(c: Clown, name_: String, secs: float, step: Callable, fixed := false, anchor := Vector3.INF) -> void:
	_fno = 0
	cam_anchor = (c.global_position if anchor == Vector3.INF else anchor) if fixed else Vector3.INF
	var t := 0.0
	var f := 0
	while t < secs:
		step.call(t)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		f += 1
		if f % 4 == 0 and is_instance_valid(c):
			await _film(c, name_)
	print("      clip %s: %d frames" % [name_, _fno])


func _clips(m: Maze, a: Vector3, b: Vector3, run_dir: Vector3, args: Array) -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/clips")
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	cam_axis = run_dir
	for n in game.player.camera.get_children():
		if n is Node3D:
			(n as Node3D).visible = false          # the viewmodel would fill the player's-eye shots
	_cam = Camera3D.new()
	_cam.fov = 60
	game._world.add_child(_cam)
	_cam.make_current()
	_lamp = OmniLight3D.new()
	_lamp.omni_range = 14.0
	_lamp.light_energy = 2.2
	game._world.add_child(_lamp)
	var want := func(n: String) -> bool: return args.size() == 1 or args.has(n)
	var dt := 1.0 / 60.0
	if want.call("walk_stop"):
		var c := _soldier(m, a)
		var br := _quiet(c)
		c.rotation.y = atan2(run_dir.x, run_dir.z)
		await _frames(5)
		var mid := a + run_dir * 6.0
		await _clip(c, "walk_stop", 4.0, func(t: float) -> void:
			if t < 0.4:
				br._settle(dt)
			elif Vector2(c.global_position.x - mid.x, c.global_position.z - mid.z).length() > 0.25 and t < 3.0:
				br._go_to(mid, dt, br.move_speed)
			else:
				br._settle(dt)
			br._after(dt), true, mid)
		c.queue_free()
		game.clowns.erase(c)
	if want.call("run_turn"):
		var c := _soldier(m, a)
		var br := _quiet(c)
		c.rotation.y = atan2(run_dir.x, run_dir.z)
		await _frames(5)
		var tgt := [b]
		await _clip(c, "run_turn", 5.0, func(t: float) -> void:
			if br._go_to(tgt[0], dt, br.run_speed):
				tgt[0] = a
			br._after(dt))
		c.queue_free()
		game.clowns.erase(c)
	if want.call("turn_spot"):
		var c := _soldier(m, a + run_dir * 2.0)
		var br := _quiet(c)
		c.rotation.y = atan2(run_dir.x, run_dir.z)
		await _frames(5)
		await _clip(c, "turn_spot", 3.0, func(t: float) -> void:
			if t > 0.4:
				br._face(-run_dir, dt, 8.0)
			br._settle(dt, false)
			br._after(dt), true)
		c.queue_free()
		game.clowns.erase(c)
	if want.call("crouch_walk"):
		var c := _soldier(m, a)
		var br := _quiet(c)
		c.rotation.y = atan2(run_dir.x, run_dir.z)
		await _frames(5)
		br._cover_state = 1
		var goal := a + run_dir * 7.0
		await _clip(c, "crouch_walk", 4.0, func(t: float) -> void:
			br.crouch_want = 0.0
			if br._go_to(goal, dt, br.run_speed):
				br.crouch_want = 1.0
			br._after(dt), true, goal)
		c.queue_free()
		game.clowns.erase(c)
	if want.call("near_miss") or want.call("hit"):
		var c := _soldier(m, a + run_dir * 2.0)
		var br: ClownBrain = c.get_node("Brain")
		br.set_physics_process(false)
		c.rotation.y = atan2(-run_dir.x, -run_dir.z)
		await _frames(10)
		var side := Vector3(-run_dir.z, 0, run_dir.x)
		var chest := c.global_position + Vector3.UP * 1.25
		var from := chest - run_dir * 15.0 + side * 0.5
		if want.call("near_miss"):
			await _clip(c, "near_miss", 2.5, func(t: float) -> void:
				if absf(t - 0.5) < 0.01:
					game.player._near_misses(from, from + run_dir * 30.0, null)
				br._after(dt), true)
		if want.call("hit"):
			await _frames(90)
			var chest_b: PhysicalBone3D = c.ragdoll.bones[&"Chest"]
			await _clip(c, "hit", 2.0, func(t: float) -> void:
				if absf(t - 0.4) < 0.01:
					c.hit({collider = chest_b, position = chest_b.global_position + side * 0.12 - run_dir * 0.1, direction = run_dir, damage = 35.0, impulse = 4.0, shot_id = randi()})
				br._after(dt), true)
		if want.call("ragdoll") or args.size() == 1:
			var head: PhysicalBone3D = c.ragdoll.bones[&"Head"] if c.ragdoll.bones.has(&"Head") else c.ragdoll.bones[&"Chest"]
			await _clip(c, "ragdoll", 3.0, func(t: float) -> void:
				if absf(t - 0.4) < 0.01:
					c.hit({collider = head, position = head.global_position - run_dir * 0.1, direction = run_dir, damage = 500.0, impulse = 14.0, shot_id = randi()}), true)
		if is_instance_valid(c):
			c.queue_free()
		game.clowns.erase(c)
	if want.call("fight"):
		# cover, peeks round the corner, side-steps: the brain left to itself
		var c := _soldier(m, b)
		var br: ClownBrain = c.get_node("Brain")
		br.use_cover = true
		game.player.global_position = a + Vector3.UP * 0.1
		game.player.look_at(Vector3(b.x, game.player.global_position.y, b.z))
		await _frames(5)
		br.alert(game.player.global_position, false)
		await _clip(c, "fight", 16.0, func(t: float) -> void:
			if t > 6.0 and br._cover_state == 0 and br._cover_cooldown <= 0.0 and int(t * 60.0) % 120 == 0:
				br._find_cover())
		c.queue_free()
		game.clowns.erase(c)
