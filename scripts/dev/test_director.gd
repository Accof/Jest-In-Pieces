extends Node3D
## The Battlefield Director's foundation (Milestone 7), checked.
## Sections (user args; none = all):
##   tension   rises on notes (shots, blasts, damage), more for what is near
##             the player; holds while soldiers hunt him close by; decays to
##             nothing in quiet; the pacing mode follows it round the loop
##   local     alertness is a sector's own: a soldier in their lines who sees
##             the player raises THEIRS, not OURS; one who hears a shot
##             learns where the shot was, not where the player is; last_known
##             stays where it was learned when the player moves; it decays;
##             a body found raises the finder's sector toward the body
##   points    the floor's event points: every kind present, every one on the
##             path graph, holes out on the field, bays facing the field; a
##             point in front of the player in the open is visible, one behind
##             him is not
##   budget    can_spawn says no in COMBAT, past the live cap, past the floor
##             pool, inside the event gap, on a cooling event, with slow
##             frames - and says why; yes otherwise
##   seeded    two directors with the same seed and the same inputs make the
##             same choices; a different seed does not
##   overlay   hidden by default; F3 shows it; the text carries the state
##   events    (Milestone 8) the first three of the catalogue: each spawns
##             where the player cannot see, with a duty of the right kind on
##             real paths (silhouette: a top route of joined cells; reinforce:
##             a file from a dugout/trench to a bay on its side, leader and
##             followers; parapet: frontline men at their bays facing the
##             field, cosmetic fire); every man is in game.clowns and booked;
##             the tick picks events itself after 20 s, never in COMBAT, with
##             the gap and cooldowns kept; an event far from the player and
##             unseen for 90 s is taken off the floor; none of it is a
##             required kill (SURVIVAL)
##   activity  (Milestone 9) catalogue 4-6, 9-10 and the squad: investigate
##             (two men from a hidden start 20-45 m from an alerted sector's
##             last-known, told the place, hunting blind to it; the telling
##             is not news to the director; only offered with a sector
##             alerted), mg_sector (an idle Maxim works over a point 25 m+
##             from the player, bursts counted), shellfire (a salvo centred
##             8-12 m from a soldier 30-90 m in front of the player; a
##             frontline man within 12 m of a shell moves to another bay),
##             smoke (a bank rolled across the field on the player's lane,
##             only when he is by the field), aftermath (scorch, two bodies
##             not in game.clowns, two men running 15-30 m to a GUARD post);
##             squad (the word passes from an alerted man to his group; half
##             down and contact lost -> withdraw to the origin or hold)
##   walk      brains on, 75 s of game time: the reinforcements' leader walks
##             his beat toward the bay (legs finished, metres covered), the
##             silhouette finishes legs of his route, the parapet men fire
##             effects-only rounds (shots counted, no damage to anyone)
##   godot --headless --fixed-fps 60 res://scenes/test_director.tscn [-- section...]

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


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := ["tension", "local", "points", "budget", "seeded", "overlay", "events", "walk", "activity"]
	var any := false
	for s: String in secs:
		any = any or args.has(s)
	for s: String in secs:
		if not any or args.has(s):
			await call("_" + s)
	print("DIRECTOR: %d failed" % fails)
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
	FpsPlayer.god_mode = true
	game.floor_number = 2
	game.next_floor()
	await _frames(3)


func _dir() -> FrontDirector:
	return game.director as FrontDirector


## Let the director tick `seconds` of its own clock (no real waiting).
func _tick(d: FrontDirector, seconds: float) -> void:
	var n := int(seconds / FrontDirector.TICK)
	for i in n:
		d.clock += FrontDirector.TICK
		d._since_event += FrontDirector.TICK
		d._evaluate(FrontDirector.TICK)


# --- tension ---------------------------------------------------------------------------
func _tension() -> void:
	print("-- tension")
	await _new_game(1916)
	var d := _dir()
	_check(d != null and d.is_in_group(&"director"), "the Front has a director, in the director group")
	if d == null:
		return
	# quiet all the soldiers so only our notes count
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var pl: FpsPlayer = game.player
	_check(d.tension == 0.0 and d.mode == FrontDirector.Mode.UNEASY_QUIET, "it starts at tension 0, uneasy quiet")
	d.note("player_shot", pl.global_position, 1.0)
	var t1 := d.tension
	d.note("player_shot", pl.global_position + Vector3(0, 0, -55.0), 1.0)
	var t2 := d.tension
	_check(t1 > 0.0 and (t2 - t1) < t1 * 0.5, "a shot by him counts (%.1f); the same shot 55 m away counts less (+%.1f)" % [t1, t2 - t1])
	d.note("blast", pl.global_position + Vector3(6, 0, 0), 1.0)
	d.note("hurt", pl.global_position, 1.0)
	_tick(d, 0.5)
	_check(d.tension >= 20.0 and d.mode == FrontDirector.Mode.RISING, "a blast beside him and a wound: tension %.0f, RISING" % d.tension)
	for i in 6:
		d.note("enemy_shot", pl.global_position + Vector3(3, 0, -4), 1.0)
	d.note("blast", pl.global_position + Vector3(-5, 0, 2), 1.0)
	_tick(d, 0.5)
	_check(d.tension >= 50.0 and d.mode == FrontDirector.Mode.COMBAT, "a firefight: tension %.0f, COMBAT" % d.tension)
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("combat"), "in combat the director spawns nothing (%s)" % d.can_spawn(1).why)
	# then quiet
	_tick(d, 12.0)
	_check(d.mode == FrontDirector.Mode.RECOVERY and d.tension < 50.0, "12 quiet seconds later: tension %.0f, RECOVERY" % d.tension)
	_tick(d, 20.0)
	_check(d.mode == FrontDirector.Mode.UNEASY_QUIET and d.tension < 5.0, "and in another 20 it is quiet again (tension %.0f)" % d.tension)
	# a hunter close by holds it up without any shots
	var hunter: Clown = null
	for c: Clown in game.clowns:
		if not c.dead and not c.has_meta(&"mg_gunner") and c.get_node_or_null("Brain") is ClownBrain:
			hunter = c
			break
	if hunter:
		hunter.global_position = pl.global_position + Vector3(6, 0, 6)
		(hunter.get_node("Brain") as ClownBrain).mind = ClownBrain.Mind.HUNT
		_tick(d, 1.0)
		_check(d.threats == 1 and d.tension >= 18.0, "a soldier hunting him 8 m away: %d threat, tension held at %.0f with no shots" % [d.threats, d.tension])
		(hunter.get_node("Brain") as ClownBrain).mind = ClownBrain.Mind.IDLE


# --- local ------------------------------------------------------------------------------
func _local() -> void:
	print("-- local")
	await _new_game(1916)
	var d := _dir()
	if d == null:
		_check(false, "no director")
		return
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var m := game.maze as FrontMaze
	var pl: FpsPlayer = game.player
	# a soldier of theirs, in their lines, sees the player (his own signal)
	var theirs: Clown = null
	var ours: Clown = null
	for c: Clown in game.clowns:
		if c.dead or c.has_meta(&"mg_gunner") or not (c.get_node_or_null("Brain") is ClownBrain):
			continue
		if d.sector_of(c.global_position) == FrontDirector.Sector.THEIRS and theirs == null:
			theirs = c
		elif d.sector_of(c.global_position) == FrontDirector.Sector.OURS and ours == null:
			ours = c
	_check(theirs != null and ours != null, "a soldier in their lines and one in ours")
	if theirs == null or ours == null:
		return
	_tick(d, 0.5)                                   # watch() connects the brains
	var seen_at: Vector3 = pl.global_position
	(theirs.get_node("Brain") as ClownBrain).alert(seen_at, true, true)
	_check(d.alert[FrontDirector.Sector.THEIRS] > 0.0 and d.alert[FrontDirector.Sector.OURS] == 0.0, "he saw the player: THEIRS %.0f, OURS %.0f - the other lines learn nothing" % [d.alert[FrontDirector.Sector.THEIRS], d.alert[FrontDirector.Sector.OURS]])
	_check(d.last_known[FrontDirector.Sector.THEIRS] == seen_at, "their last known is where he saw him")
	pl.global_position += Vector3(20, 0, 0)
	_tick(d, 1.0)
	_check(d.last_known[FrontDirector.Sector.THEIRS] == seen_at, "the player moved 20 m: their last known did not (no omniscience)")
	# one of ours hears a shot: he learns the shot's place, not the player's
	var shot_at: Vector3 = ours.global_position + Vector3(5, 0, 0)
	(ours.get_node("Brain") as ClownBrain).alert(shot_at, true, false)
	_check(d.last_known[FrontDirector.Sector.OURS] == shot_at and d.alert[FrontDirector.Sector.OURS] > 0.0 and d.alert[FrontDirector.Sector.OURS] < d.alert[FrontDirector.Sector.THEIRS], "one of ours heard a shot: OURS %.0f knows the shot's place, less than a sighting" % d.alert[FrontDirector.Sector.OURS])
	# decay
	var a0: float = d.alert[FrontDirector.Sector.THEIRS]
	_tick(d, FrontDirector.ALERT_HOLD + 30.0)
	_check(d.alert[FrontDirector.Sector.THEIRS] < a0 * 0.3, "no contact for %.0f s: THEIRS %.0f -> %.0f" % [FrontDirector.ALERT_HOLD + 30.0, a0, d.alert[FrontDirector.Sector.THEIRS]])
	# a body found: the finder's sector rises toward the body
	var victim: Clown = null
	for c: Clown in game.clowns:
		if c != ours and c != theirs and not c.dead and not c.has_meta(&"mg_gunner"):
			victim = c
			break
	if victim:
		victim.global_position = ours.global_position + Vector3(2.0, 0, 0)
		var chest: PhysicalBone3D = victim.ragdoll.bones.get(&"Chest")
		victim.hit({collider = chest, position = victim.global_position + Vector3.UP * 1.2, direction = Vector3.FORWARD, damage = 5000.0, impulse = 6.0, shot_id = 1, weapon = "Rifle", dist = 10.0})
		await _frames(2)
		var before: float = d.alert[FrontDirector.Sector.OURS]
		_tick(d, 0.5)
		_check(victim.dead and d.alert[FrontDirector.Sector.OURS] > before, "a body 2 m from one of ours: OURS %.0f -> %.0f" % [before, d.alert[FrontDirector.Sector.OURS]])


# --- points ----------------------------------------------------------------------------
func _points() -> void:
	print("-- points")
	await _new_game(1916)
	var d := _dir()
	var m := game.maze as FrontMaze
	var kinds := {}
	var off_graph := 0
	for pt: Dictionary in d.points:
		kinds[pt.kind] = int(kinds.get(pt.kind, 0)) + 1
		if pt.kind != "holes" and not m._astar.has_point(m.idx(pt.cell)):
			off_graph += 1
	_check(kinds.has("patrol") and kinds.has("bay") and kinds.has("bridge") and kinds.has("holes") and (kinds.has("dugout") or kinds.has("op")), "event points by kind: %s" % str(kinds))
	_check(off_graph == 0, "every trench point is on the path graph (%d were not)" % off_graph)
	var bays_face := true
	var holes_field := true
	for pt: Dictionary in d.points:
		if pt.kind == "bay" and absf(pt.dir.z) < 0.9:
			bays_face = false
		if pt.kind == "holes" and (pt.pos.z <= d.z_field_min or pt.pos.z >= d.z_field_max):
			holes_field = false
	_check(bays_face and holes_field, "bays face across the field; hole clusters lie out on it")
	# visibility: in front in the open vs behind
	var pl: FpsPlayer = game.player
	var zc := lerpf(d.z_field_min, d.z_field_max, 0.5)
	var w := m.w * m.cell
	pl.global_position = Vector3(w * 0.5, m.ground_height(w * 0.5, zc) + 0.1, zc)
	pl.rotation.y = 0.0
	pl.camera.rotation = Vector3.ZERO
	await _frames(2)
	var fwd := -pl.camera.global_basis.z
	var ahead: Vector3 = pl.global_position + fwd * 12.0
	ahead.y = m.ground_height(ahead.x, ahead.z)
	var behind: Vector3 = pl.global_position - fwd * 12.0
	behind.y = m.ground_height(behind.x, behind.z)
	_check(d.visible_to_player(ahead) and not d.visible_to_player(behind), "a point 12 m ahead in the open is visible to him; 12 m behind is not")
	var hidden := d.pick_points("bay", -1, 25.0, 200.0, true)
	var all := d.pick_points("bay", -1, 0.0, 1000.0, false)
	_check(hidden.size() <= all.size() and all.size() == kinds.get("bay", 0), "pick_points filters by distance and sight (%d of %d bays pass from mid-field)" % [hidden.size(), all.size()])


# --- budget ----------------------------------------------------------------------------
func _budget() -> void:
	print("-- budget")
	await _new_game(1916)
	var d := _dir()
	d.auto_events = false
	for c: Clown in game.clowns:
		var b := c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	_tick(d, FrontDirector.EVENT_GAP + 1.0)
	_check(d.can_spawn(2).ok, "quiet, nothing booked: can spawn (%s)" % str(d.can_spawn(2)))
	d.enabled = false
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why == "director off", "director off: %s" % d.can_spawn(1).why)
	d.enabled = true
	d.book("test", 2, 30.0)
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("event gap"), "just after an event: %s" % d.can_spawn(1).why)
	_tick(d, FrontDirector.EVENT_GAP + 1.0)
	_check(not d.can_spawn(1, "test").ok and d.can_spawn(1, "test").why.begins_with("test cooling"), "the same event again: %s" % d.can_spawn(1, "test").why)
	_check(d.can_spawn(1, "other").ok, "a different event: fine")
	d.live = [game.player, game.player, game.player, game.player, game.player, game.player]
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("live cap"), "six director soldiers alive: %s" % d.can_spawn(1).why)
	d.live = []
	d.spawned_total = FrontDirector.FLOOR_POOL
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("floor pool"), "the floor's pool spent: %s" % d.can_spawn(1).why)
	d.spawned_total = 0
	d._frame_ms = 40.0
	_check(not d.can_spawn(1).ok and d.can_spawn(1).why.begins_with("frames"), "frames at 40 ms: %s" % d.can_spawn(1).why)
	d._frame_ms = 16.0
	_check(d.can_spawn(1).ok, "and all clear again")


# --- seeded ----------------------------------------------------------------------------
func _seeded() -> void:
	print("-- seeded")
	await _new_game(1916)
	var d := _dir()
	var a := FrontDirector.new()
	add_child(a)
	a.setup(game.maze as FrontMaze, game.player, game, 777)
	var b := FrontDirector.new()
	add_child(b)
	b.setup(game.maze as FrontMaze, game.player, game, 777)
	var c := FrontDirector.new()
	add_child(c)
	c.setup(game.maze as FrontMaze, game.player, game, 778)
	var pa: Array = []
	var pb: Array = []
	var pc: Array = []
	for i in 3:
		pa.append(a.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
		pb.append(b.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
		pc.append(c.pick_points("bay", -1, 0.0, 1000.0, false).map(func(p: Dictionary) -> Vector2i: return p.cell))
	_check(pa == pb, "the same seed, the same inputs: the same orderings, three times over")
	_check(pa != pc, "a different seed: a different order")
	a.queue_free()
	b.queue_free()
	c.queue_free()
	_check(d.log.size() >= 1 and d.log[0].what == "setup", "the log opens with the setup line: %s" % d.log[0].detail)


# --- overlay ---------------------------------------------------------------------------
func _overlay() -> void:
	print("-- overlay")
	await _new_game(1916)
	var d := _dir()
	_check(not d._overlay.visible, "the overlay is hidden by default")
	d.toggle_overlay()
	var txt := d.overlay_text()
	_check(d._overlay.visible and txt.contains("tension") and txt.contains("alert") and txt.contains("mode") and txt.contains("pool") and txt.contains("exit"), "F3 shows it; it carries mode, tension, alertness, pool and exit state")
	d.toggle_overlay()
	_check(not d._overlay.visible, "and hides it again")


# --- events (Milestone 8) --------------------------------------------------------------
func _events() -> void:
	print("-- events")
	var ran := {silhouette = 0, reinforce = 0, parapet = 0}
	var hidden_ok := true
	var booked_ok := true
	for seed_: int in [1916, 1917, 1918]:
		await _new_game(seed_)
		var d := _dir()
		d.auto_events = false
		for c: Clown in game.clowns:
			var b: Node = c.get_node_or_null("Brain")
			if b:
				b.set_physics_process(false)
		_check(game.objective == game.Objective.SURVIVAL, "seed %d: a SURVIVAL floor (no required kills)" % seed_)
		var before: int = game.clowns.size()
		var remaining_before: int = game.remaining
		for name_: String in ["silhouette", "reinforce", "parapet"]:
			d._since_event = 999.0
			d.cooldowns.clear()
			var r: Dictionary = d.run_event(name_)
			if not r.ok:
				print("         %s on seed %d: %s" % [name_, seed_, r.why])
				continue
			ran[name_] += 1
			var men: Array = r.soldiers
			for c: Clown in men:
				if d.visible_to_player(c.global_position):
					hidden_ok = false
					print("         %s: a man in view at %s" % [name_, c.global_position])
				if not game.clowns.has(c) or not d.live.has(c) or not c.has_meta(&"director_event"):
					booked_ok = false
				var duty := c.get_node_or_null("Duty") as BattleDuty
				if duty == null:
					_check(false, "%s: a man with no duty" % name_)
					continue
				match name_:
					"silhouette":
						_check(duty.kind == BattleDuty.Kind.PATROL and duty.route.size() >= 3, "silhouette: PATROL with %d legs" % duty.route.size())
						var joined := true
						for i in range(1, duty.route.size()):
							var a: Vector2i = game.maze.cell_of(duty.route[i - 1])
							var b: Vector2i = game.maze.cell_of(duty.route[i])
							if game.maze.path_cells(a, b) >= 9999:
								joined = false
						_check(joined, "silhouette: every leg joined on the path graph")
						var dist: float = duty.route[0].distance_to(game.player.global_position)
						_check(dist >= FrontDirector.SIL_RANGE.x - 1.0 and dist <= FrontDirector.SIL_RANGE.y + 1.0, "silhouette: starts %.0f m out" % dist)
					"reinforce":
						_check(duty.kind == BattleDuty.Kind.TRENCH_PATROL, "reinforce: a man on the beat")
					"parapet":
						_check(duty.kind == BattleDuty.Kind.FRONTLINE and absf(duty.face.z) > 0.9, "parapet: FRONTLINE facing the field")
			match name_:
				"reinforce":
					_check(men.size() == 3, "reinforce: three men (%d)" % men.size())
					var leaders := 0
					var followers := 0
					for c: Clown in men:
						var duty := c.get_node("Duty") as BattleDuty
						if duty.leader == null:
							leaders += 1
						else:
							followers += 1
					_check(leaders == 1 and followers == men.size() - 1, "reinforce: one leader, the rest follow")
					var route: Array = r.point.route
					var a: Vector2i = game.maze.cell_of(route[0])
					var b: Vector2i = game.maze.cell_of(route[route.size() - 1])
					_check(game.maze.path_cells(a, b) < 9999, "reinforce: start to bay is a real path (%d cells)" % game.maze.path_cells(a, b))
				"parapet":
					_check(men.size() >= 2, "parapet: %d men at adjacent bays" % men.size())
					_check(bool(r.cosmetic), "parapet: marked cosmetic (effects-only frontline fire)")
		_check(game.clowns.size() == before + d.live.size(), "seed %d: the men are in game.clowns (%d -> %d)" % [seed_, before, game.clowns.size()])
		_check(game.remaining == remaining_before, "seed %d: `remaining` untouched (%d): no required kills" % [seed_, game.remaining])
		_check(d.active.size() == ran_count(d), "seed %d: %d active events tracked" % [seed_, d.active.size()])
	_check(ran.silhouette >= 2 and ran.reinforce >= 2 and ran.parapet >= 2, "every event placed on at least two of three seeds: %s" % str(ran))
	_check(hidden_ok, "no man appeared in the player's view")
	_check(booked_ok, "every man in game.clowns, in `live`, tagged with his event")

	# the tick's own choices: nothing before 20 s, then events with the gap kept, none in COMBAT
	await _new_game(1916)
	var d := _dir()
	for c: Clown in game.clowns:
		var b: Node = c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	_tick(d, 19.0)
	_check(d.active.is_empty(), "nothing in the first 20 s")
	var births: Array[float] = []
	var seen := 0
	for i in 40:
		_tick(d, 5.0)
		for ev: Dictionary in d.active:
			if not births.has(float(ev.born)):
				births.append(float(ev.born))
				seen += 1
		# the men do not move (brains off): keep their brains quiet
		for c in d.live:
			if is_instance_valid(c):
				var b: Node = c.get_node_or_null("Brain")
				if b:
					b.set_physics_process(false)
	_check(seen >= 2, "the tick placed %d events in 200 s of quiet" % seen)
	births.sort()
	var gaps_ok := true
	for i in range(1, births.size()):
		if births[i] - births[i - 1] < FrontDirector.EVENT_GAP - 0.01:
			gaps_ok = false
	_check(gaps_ok, "births %s keep the %d s gap" % [str(births), int(FrontDirector.EVENT_GAP)])
	_check(d.spawned_total <= FrontDirector.FLOOR_POOL and d.live.size() <= FrontDirector.MAX_LIVE, "pool %d/%d, live %d/%d" % [d.spawned_total, FrontDirector.FLOOR_POOL, d.live.size(), FrontDirector.MAX_LIVE])
	d.mode = d.Mode.COMBAT
	d.tension = 100.0
	var n_before := d.events_run.duplicate()
	for i in 10:
		d._since_event = 999.0
		d.cooldowns.clear()
		d._select()
	_check(str(n_before) == str(d.events_run), "in COMBAT the tick places nothing (%s)" % str(d.events_run))

	# F5 (development): forces the next event, the gap and cooldowns waived, the caps kept
	await _new_game(1918)
	d = _dir()
	d.auto_events = false
	for c: Clown in game.clowns:
		var b: Node = c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var n0 := d.active.size()
	d.force_event()
	_check(d.active.size() == n0 + 1, "F5 placed an event at once (%s)" % d._events_text())
	d.force_event()
	_check(d.active.size() == n0 + 2 and d.active[0].name != d.active[1].name, "a second press: another kind (%s, %s)" % [d.active[0].name, d.active[1].name])
	_check(d._where_text(d.active[0]).contains("o'clock"), "the overlay says where: %s" % d._where_text(d.active[0]))

	# lifecycle: far and unseen for 60 s -> taken off
	await _new_game(1917)
	d = _dir()
	d.auto_events = false
	for c: Clown in game.clowns:
		var b: Node = c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)
	var r: Dictionary = d.run_event("silhouette")
	if r.ok:
		var man: Clown = r.soldiers[0]
		var brain := man.get_node("Brain")
		brain.set_physics_process(false)
		var total: int = game.clowns.size()
		game.player.global_position = man.global_position + Vector3(0, 0, 200.0)
		game.player.rotation.y = PI       # looking away
		_tick(d, FrontDirector.DESPAWN_AFTER - 2.0)
		_check(d.active.size() == 1, "far and unseen %.0f s: still on the floor" % (FrontDirector.DESPAWN_AFTER - 2.0))
		_tick(d, 4.0)
		await _frames(2)
		_check(d.active.is_empty() and not is_instance_valid(man), "far and unseen %.0f s: taken off the floor" % FrontDirector.DESPAWN_AFTER)
		_check(game.clowns.size() == total - 1 and d.live.is_empty(), "and out of game.clowns and `live`")
	else:
		_check(false, "lifecycle: no silhouette to test with (%s)" % r.why)


func ran_count(d: FrontDirector) -> int:
	var n := 0
	for k in d.events_run.keys():
		n += int(d.events_run[k])
	return n


# --- walk (Milestone 8): the men do their jobs ------------------------------------------
func _walk() -> void:
	print("-- walk")
	await _new_game(1917)
	var d := _dir()
	d.auto_events = false
	d.despawn_far = 10000.0           # nobody taken off while we watch
	d._since_event = 999.0
	var rr: Dictionary = d.run_event("reinforce")
	d._since_event = 999.0
	var rs: Dictionary = d.run_event("silhouette")
	d._since_event = 999.0
	var rp: Dictionary = d.run_event("parapet")
	_check(rr.ok and rs.ok and rp.ok, "all three placed (%s %s %s)" % [rr.why, rs.why, rp.why])
	if not (rr.ok and rs.ok and rp.ok):
		return
	var leader: Clown = rr.soldiers[0]
	var start: Vector3 = leader.global_position
	var dest: Vector3 = rr.point.dest
	var sil: Clown = rs.soldiers[0]
	var sil_start: Vector3 = sil.global_position
	var hp_before: float = game.player.health
	var frames := 75 * 60
	for i in frames:
		await get_tree().physics_frame
	var ld := leader.get_node("Duty") as BattleDuty
	var sd := sil.get_node("Duty") as BattleDuty
	var moved: float = start.distance_to(leader.global_position)
	var to_go: float = leader.global_position.distance_to(dest)
	_check(ld.legs >= 1 or moved > 6.0 or ld.kind == BattleDuty.Kind.FRONTLINE, "reinforce leader: %s, %d legs, moved %.1f m, %.1f m from the bay (was %.1f)" % [ld.name_of(), ld.legs, moved, to_go, start.distance_to(dest)])
	var on_step := 0
	for c: Clown in rr.soldiers:
		if is_instance_valid(c) and (c.get_node("Duty") as BattleDuty).kind == BattleDuty.Kind.FRONTLINE:
			on_step += 1
	_check(on_step >= 1, "%d of %d reinforcements took the fire step on arrival" % [on_step, rr.soldiers.size()])
	var follow_ok := true
	for i in range(1, rr.soldiers.size()):
		var f: Clown = rr.soldiers[i]
		if is_instance_valid(f) and f.global_position.distance_to(leader.global_position) > 14.0:
			follow_ok = false
	_check(follow_ok, "the followers kept within 14 m of the leader")
	_check(sd.legs >= 1 or sil_start.distance_to(sil.global_position) > 4.0, "silhouette: %d legs, moved %.1f m" % [sd.legs, sil_start.distance_to(sil.global_position)])
	var shots := 0
	for c: Clown in rp.soldiers:
		var pd := c.get_node("Duty") as BattleDuty
		shots += pd.shots
	_check(shots >= 1, "parapet men fired %d times" % shots)
	_check(game.player.health == hp_before, "and the player took nothing from it (%.0f hp)" % game.player.health)
	var unaware := 0
	for c in d.live:
		if is_instance_valid(c) and (c.get_node("Brain") as ClownBrain).mind == ClownBrain.Mind.IDLE:
			unaware += 1
	print("         %d of %d director men still unaware" % [unaware, d.live.size()])


# --- activity (Milestone 9) --------------------------------------------------------------
func _brains_off() -> void:
	for c: Clown in game.clowns:
		var b: Node = c.get_node_or_null("Brain")
		if b:
			b.set_physics_process(false)


func _activity() -> void:
	print("-- activity")
	await _new_game(1916)
	var d := _dir()
	d.auto_events = false
	d.despawn_far = 10000.0
	_brains_off()
	var m := game.maze as FrontMaze
	var p: FpsPlayer = game.player

	# investigate: only with a sector alerted
	d._since_event = 999.0
	var r: Dictionary = d.run_event("investigate")
	_check(not r.ok and d._alerted_sector() < 0, "investigate with nothing alerted: refused (%s)" % r.why)
	var lk: Vector3 = Vector3.INF
	for b: Dictionary in d.pick_points("bay", d.Sector.THEIRS, 0.0, 1000.0, false):
		lk = d._stand(b.pos)
		break
	d.alert[d.Sector.THEIRS] = 30.0
	d.last_known[d.Sector.THEIRS] = lk
	d.last_contact[d.Sector.THEIRS] = d.clock
	_check(d._alerted_sector() == d.Sector.THEIRS, "THEIRS at 30 with a fresh last-known is the sector to send men to")
	d._since_event = 999.0
	r = d.run_event("investigate")
	_check(r.ok, "investigate placed (%s)" % r.why)
	if r.ok:
		_check(r.soldiers.size() == 2, "two men")
		var hunting := 0
		var hidden := 0
		for c: Clown in r.soldiers:
			var b := c.get_node("Brain") as ClownBrain
			if b.mind != ClownBrain.Mind.IDLE and b._last_known == lk:
				hunting += 1
			if not d.visible_to_player(c.global_position):
				hidden += 1
		_check(hunting == 2, "both told the place and going to look (hunt-blind to the last-known)")
		_check(hidden == 2, "both placed out of sight")
		var st: Vector3 = r.point.pos
		_check(st.distance_to(lk) >= 20.0 and st.distance_to(lk) <= 45.0 and m.path_cells(r.point.cell, m.cell_of(lk)) < 9999, "from %.0f m away with a path" % st.distance_to(lk))
		_check(absf(float(d.alert[d.Sector.THEIRS]) - 30.0) < 0.01, "the director's own telling was not news (alert still 30)")
		_check(r.squad != null and (r.squad as Squad).members.size() == 2, "a squad of two")

	# mg_sector
	d._since_event = 999.0
	r = d.run_event("mg_sector")
	_check(r.ok, "mg_sector placed (%s)" % r.why)
	if r.ok:
		var at: Vector3 = r.point.pos
		_check(at.distance_to(p.global_position) >= 25.0, "the sector %.0f m from the player" % at.distance_to(p.global_position))
		var engaged := 0
		var mg_busy: FrontMg = null
		for mg: FrontMg in game.threats.nests:
			if mg._engage_left > 0:
				mg_busy = mg
		_check(mg_busy != null, "a nest has the bursts queued")
		for i in 30 * 60:
			await get_tree().physics_frame
		for mg: FrontMg in game.threats.nests:
			engaged += mg.engaged
		_check(engaged >= 3, "%d bursts fired on the director's word in 30 s" % engaged)
		_check(d.active.size() >= 1, "the event lasts its while (%s)" % d._events_text())

	# smoke: only by the field
	d._since_event = 999.0
	r = d.run_event("smoke")
	_check(not r.ok, "smoke with the player at our rear: refused (%s)" % r.why)
	var atmos := get_tree().get_first_node_in_group(&"fog")
	var fog = atmos.front_fog
	var banks0: int = fog.banks.size()
	p.global_position = Vector3(m.w * m.cell * 0.5, 0, (d.z_field_min + d.z_field_max) * 0.5)
	p.global_position.y = m.ground_height(p.global_position.x, p.global_position.z) + 0.1
	await _frames(2)
	fog.clear_banks()
	d._since_event = 999.0
	r = d.run_event("smoke")
	_check(r.ok, "smoke with the player on the field, the banks clear (%s)" % r.why)
	if r.ok:
		_check(fog.banks.size() == 1, "a bank rolled (%d)" % fog.banks.size())
		var bp: Vector3 = r.point.pos
		var v: Vector3 = r.bank_vel
		var tt: float = (p.global_position.z - bp.z) / maxf(v.z, 0.01)
		var heading: Vector3 = bp + v * tt
		_check(bp.z < p.global_position.z - 25.0 and absf(heading.x - p.global_position.x) < 12.0, "from their side (z %.0f), over his lane in %.0f s (x %.0f -> %.0f vs %.0f)" % [bp.z, tt, bp.x, heading.x, p.global_position.x])
	# the banks full and thick: the one nearest their side is steered across the lane instead
	fog.clear_banks()
	for i in fog.MAX_BANKS:
		var b = fog.roll_in(0)
		b.density = b.peak
		b.age = 40.0
		b.pos = Vector3(5.0 + 20.0 * i, 0, d.z_field_min + 6.0 + 4.0 * i)
	d._since_event = 999.0
	d.cooldowns.clear()
	var steered0: int = fog.steered
	r = d.run_event("smoke")
	_check(r.ok and fog.steered == steered0 + 1 and fog.banks.size() == fog.MAX_BANKS, "banks full and thick: one steered, none added (%s)" % r.why)
	if r.ok:
		var bp: Vector3 = r.point.pos
		var v: Vector3 = r.bank_vel
		var tt: float = (p.global_position.z - bp.z) / maxf(v.z, 0.01)
		var heading: Vector3 = bp + v * tt
		_check(absf(heading.x - p.global_position.x) < 12.0, "and it will pass over his lane in %.0f s (x %.0f -> %.0f vs %.0f)" % [tt, bp.x, heading.x, p.global_position.x])
	# full, thick and all near: nothing can be done
	fog.clear_banks()
	for i in fog.MAX_BANKS:
		var b = fog.roll_in(0)
		b.density = b.peak
		b.age = 40.0
		b.pos = p.global_position + Vector3(-20.0 + 20.0 * i, 0, -10.0)
	d._since_event = 999.0
	d.cooldowns.clear()
	r = d.run_event("smoke")
	_check(not r.ok, "banks full, thick and all about him: refused (%s)" % r.why)
	fog.clear_banks()

	# shellfire: a soldier 30-90 m in front of the player, in the fair zone
	p.global_position = Vector3(m.w * m.cell * 0.5, 0, d.z_field_max - 1.0)
	p.global_position.y = m.ground_height(p.global_position.x, p.global_position.z) + 0.1
	p.rotation.y = 0.0          # facing -z: the field and their line
	await _frames(2)
	d._since_event = 999.0
	d.cooldowns.clear()
	var rp: Dictionary = d.run_event("parapet")
	await _frames(2)
	d._since_event = 999.0
	var art: FrontArtillery = game.threats.artillery
	var salvos0: int = art.salvos
	r = d.run_event("shellfire")
	_check(r.ok, "shellfire placed (%s)" % r.why)
	if r.ok:
		_check(art.salvos == salvos0 + 1 and art._salvo_left > 0, "a salvo called now")
		var centre: Vector3 = r.point.pos
		var nearest := INF
		for c in game.clowns:
			if is_instance_valid(c) and not c.dead:
				nearest = minf(nearest, c.global_position.distance_to(centre))
		_check(nearest <= 12.5, "centred %.1f m from a soldier" % nearest)
		_check(centre.distance_to(p.global_position) >= 7.5, "%.0f m from the player" % centre.distance_to(p.global_position))
	# a shell by a frontline man: he moves to another bay
	if rp.ok:
		var man: Clown = rp.soldiers[0]
		var duty := man.get_node("Duty") as BattleDuty
		var rel0: int = duty.relocations
		d._on_shell_landed(man.global_position + Vector3(3.0, 0, 0))
		_check(duty.relocations == rel0 + 1 and duty.post.distance_to(man.global_position) >= 4.0, "a shell 3 m off: he relocates %.0f m to another bay" % duty.post.distance_to(man.global_position))
		d._on_shell_landed(man.global_position + Vector3(0, 0, -40.0))
		_check(duty.relocations == rel0 + 1, "a shell 40 m off: he stays")

	# aftermath
	await _new_game(1917)
	d = _dir()
	d.auto_events = false
	d.despawn_far = 10000.0
	_brains_off()
	m = game.maze as FrontMaze
	p = game.player
	d._since_event = 999.0
	var n_clowns: int = game.clowns.size()
	r = d.run_event("aftermath")
	_check(r.ok, "aftermath placed (%s)" % r.why)
	if r.ok:
		await _frames(2)
		_check(d.corpses.size() == 2, "%d bodies" % d.corpses.size())
		var bodies_ok := true
		for c in d.corpses:
			if not is_instance_valid(c) or not c.dead or game.clowns.has(c):
				bodies_ok = false
		_check(bodies_ok, "the bodies are dead and not in game.clowns")
		_check(game.clowns.size() == n_clowns + 2, "two living men in game.clowns (%d -> %d)" % [n_clowns, game.clowns.size()])
		var runners := 0
		for c: Clown in r.soldiers:
			if (c.get_node("Duty") as BattleDuty).kind == BattleDuty.Kind.RUNNER and c.has_meta(&"arrive_kind"):
				runners += 1
		_check(runners == 2, "both running, to stop and keep their heads down")
		var start: Vector3 = (r.soldiers[0] as Clown).global_position
		for i in 40 * 60:
			await get_tree().physics_frame
		var moved: float = start.distance_to((r.soldiers[0] as Clown).global_position)
		var kinds := ""
		for c: Clown in r.soldiers:
			kinds += (c.get_node("Duty") as BattleDuty).name_of() + " "
		_check(moved >= 8.0, "40 s on: the first ran %.1f m (%s)" % [moved, kinds])

	# squad: the word, and the withdrawal
	await _new_game(1918)
	d = _dir()
	d.auto_events = false
	d.despawn_far = 10000.0
	_brains_off()
	m = game.maze as FrontMaze
	d._since_event = 999.0
	r = d.run_event("reinforce")
	if r.ok:
		var sq := r.squad as Squad
		var lead: BattleDuty = sq.members[0]
		var spot: Vector3 = lead.clown.global_position + Vector3(0, 0, 10.0)
		sq.word_chance = 1.0        # the mechanism; the imperfection is the chance
		lead.brain.alert(spot, true, true)
		var said: String = sq.tick(d.rng, m)
		var told := 0
		for o: BattleDuty in sq.members:
			if o != lead and (o.brain.mind != ClownBrain.Mind.IDLE or sq.told.has(o)):
				told += 1
		_check(told == 2 and sq.words == 2, "the word passed to the other two (%d told, %d took it): %s" % [told, sq.words, said if said != "" else "-"])
		# two of three down, the third without contact
		for o: BattleDuty in sq.members:
			o.brain.mind = ClownBrain.Mind.IDLE
		(sq.members[1] as BattleDuty).clown.dead = true
		(sq.members[2] as BattleDuty).clown.dead = true
		said = sq.tick(d.rng, m)
		_check(sq.withdrawn and (said.contains("withdraw") or said.contains("holds")), "two down, contact lost: %s" % said)
		if said.contains("withdraw"):
			_check(lead.kind == BattleDuty.Kind.GUARD and lead.post == sq.origin, "the survivor falls back to the origin and holds")
	else:
		_check(false, "squad: no reinforce to test with (%s)" % r.why)
